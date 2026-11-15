import UIKit
import AVFoundation
import CoreImage
import ImageIO

/// 原生双摄引擎（11.1.8 重写，11.2.0 扩展）：AVCaptureMultiCamSession 同时开前后摄像头（可选麦克风），
/// 每一帧用 CoreImage 合成「画中画 / 上下分屏」+ 调色，同一份合成结果用来：
///   · 预览（AVSampleBufferDisplayLayer，所见即所得：小窗圆角、边框、调色都在预览里）
///   · 拍照（JPEG / HEIF）
///   · 录像（AVAssetWriter，H.264 / HEVC + AAC，帧率跟随设置，最高 60）
///   · 实况照片（环形缓存最近 1.5 秒，快门后继续收，合成 MOV 后配对存入系统相册）
/// 规格：分辨率 720p / 1080p / 4K × 帧率 24 / 30 / 60，前后摄各自挑「系统允许同时工作」的最合适规格；
/// 系统带宽不够时自动逐级降档并告诉界面实际用了什么。

struct DualLayout {
    enum Style { case pip, split }
    var style: Style = .pip
    var backIsMain = true
    var mirrorFront = true
    var pipX: CGFloat = 1      // 0…1：小窗在可移动范围里的水平位置（1 = 最右）
    var pipY: CGFloat = 0      // 0…1：垂直位置（0 = 最上）
    var pipW: CGFloat = 0.32   // 小窗宽度 / 画面宽度
    var border: PipBorder = .none
    var pipRadius: CGFloat = 0.14   // 小窗圆角 / 小窗宽度（0 = 直角，0.3 = 大圆角）

    /// 画面（宽 W、高 H，左上角为原点）里的两个矩形：主画面、副画面
    func rects(_ W: CGFloat, _ H: CGFloat) -> (main: CGRect, second: CGRect) {
        switch style {
        case .split:
            return (CGRect(x: 0, y: 0, width: W, height: H / 2), CGRect(x: 0, y: H / 2, width: W, height: H / 2))
        case .pip:
            let w = (W * pipW).rounded(), h = (w * 4 / 3).rounded(), m = (W * 0.04).rounded()
            let x = m + max(0, W - w - 2 * m) * pipX, y = m + max(0, H - h - 2 * m) * pipY
            return (CGRect(x: 0, y: 0, width: W, height: H), CGRect(x: x.rounded(), y: y.rounded(), width: w, height: h))
        }
    }
}

enum DualError: Error {
    case unsupported(String)
    case failed(String)
    var message: String {
        switch self { case .unsupported(let s): return s; case .failed(let s): return s }
    }
}

/// 一次生效的规格请求
struct DualSpec: Equatable {
    var res = 1080          // 720 / 1080 / 2160
    var fps = 30            // 24 / 30 / 60
    var full = false        // 片门全开
    var ultraWide = false   // 后置用超广角镜头
    var aspect: CGFloat = 9.0 / 16.0   // 成品画面宽 / 高（竖屏），和取景框一致；片门全开固定 3:4

    var bound: Int32 { res == 720 ? 1280 : (res == 1080 ? 1920 : 4300) }
    var label: String { (res == 2160 ? "4K" : "\(res)p") + "·\(fps)" }
}

final class DualCamEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let session = AVCaptureMultiCamSession()
    let sessionQueue = DispatchQueue(label: "lucida.dual.session")
    private let dataQueue = DispatchQueue(label: "lucida.dual.data", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "lucida.dual.audio", qos: .userInitiated)
    private let writeQueue = DispatchQueue(label: "lucida.dual.write", qos: .utility)

    /// 预览显示层（界面把它放进取景区）
    let previewLayer = AVSampleBufferDisplayLayer()

    private(set) var backDevice: AVCaptureDevice?
    private(set) var frontDevice: AVCaptureDevice?
    private var backOut = AVCaptureVideoDataOutput()
    private var frontOut = AVCaptureVideoDataOutput()
    private var audioOut = AVCaptureAudioDataOutput()
    private(set) var hasAudio = false
    private var wantAudioSaved = false

    /// 成品画面尺寸（竖屏，宽 × 高）
    private(set) var canvas = CGSize(width: 1080, height: 1920)
    private var pvSize = CGSize(width: 608, height: 1080)
    private var liveSize = CGSize(width: 540, height: 960)
    /// 当前实际在用的规格（可能比请求的低）
    private(set) var spec = DualSpec()
    private(set) var actualBackFps = 30
    private(set) var info = ""
    /// 这台设备能不能「超广角 + 前置」同时工作
    private(set) var hasUltraWide = false

    // 每个摄像头各记各的变焦倍数（等效倍数：后置 1× = 广角；超广角 0.5×）
    private(set) var backZoom: CGFloat = 1
    private(set) var frontZoom: CGFloat = 1

    // 最新一帧（数据队列写、其它线程读）
    private let lock = NSLock()
    private var lastBack: CVPixelBuffer?
    private var lastFront: CVPixelBuffer?
    private var _layout = DualLayout()
    var layout: DualLayout {
        get { lock.lock(); defer { lock.unlock() }; return _layout }
        set { lock.lock(); _layout = newValue; lock.unlock() }
    }

    var gradeBack: GradeState { DualSettings.shared.gradeBack }
    var gradeFront: GradeState { DualSettings.shared.gradeFront }
    var liveEnabled = false

    private let ci = CIContext(options: [.cacheIntermediates: false, .workingColorSpace: NSNull()])
    private let rgb = CGColorSpaceCreateDeviceRGB()

    // 预览 / 实况缓冲池
    private var pvPool: CVPixelBufferPool?
    private var livePool: CVPixelBufferPool?
    private var pvFrameN = 0
    private var previewN = 0

    // 录像
    private var writer: AVAssetWriter?
    private var vIn: AVAssetWriterInput?
    private var aIn: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var wantRecord = false
    private var recordAudio = false
    private var recURL: URL?
    private var started = false
    private var startPTS = CMTime.invalid
    private(set) var isRecording = false
    private var failMsg: String?

    // 实况
    private struct LiveFrame { let pb: CVPixelBuffer; let pts: CMTime }
    private var liveRing: [LiveFrame] = []

    static var isSupported: Bool { AVCaptureMultiCamSession.isMultiCamSupported }

    override init() {
        super.init()
        previewLayer.videoGravity = .resizeAspect
        previewLayer.backgroundColor = UIColor.black.cgColor
    }

    // MARK: - 配置

    /// 在 sessionQueue 上调用。成功返回「实际规格与请求不一致」时的说明（一致则空串）；失败抛 DualError。
    @discardableResult
    func configure(_ want: DualSpec, wantAudio: Bool) throws -> String {
        wantAudioSaved = wantAudio
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw DualError.unsupported("这台 iPhone 不支持前后摄像头同时工作（需要 iPhone XS / XR 及以后的机型）")
        }
        hasUltraWide = Self.ultraWideWorksWithFront()
        var w = want
        if w.ultraWide && !hasUltraWide { w.ultraWide = false }
        let backType: AVCaptureDevice.DeviceType = w.ultraWide ? .builtInUltraWideCamera : .builtInWideAngleCamera
        guard let back = AVCaptureDevice.default(backType, for: .video, position: .back),
              let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw DualError.unsupported("没有找到前置或后置摄像头")
        }
        backDevice = back; frontDevice = front

        // 降档顺序：先降帧率（60 → 30），再降分辨率（4K → 1080p → 720p）
        var resList = [w.res]
        for r in [2160, 1080, 720] where r < w.res { resList.append(r) }
        var lastWhy = "系统不允许这两颗摄像头同时以可用规格工作"
        for r in resList {
            var fpsList = [w.fps]
            if w.fps > 30 { fpsList.append(30) }
            if w.fps == 30 { fpsList.append(24) }
            for f in fpsList {
                var s = w; s.res = r; s.fps = f
                resetSession()
                do {
                    try build(back: back, front: front, spec: s, wantAudio: wantAudio)
                    if session.hardwareCost <= 1.0 && session.systemPressureCost <= 1.0 {
                        spec = s
                        watchPressure()
                        backZoom = 1; frontZoom = 1
                        if s.ultraWide { backZoom = 0.5 }
                        if s == w { return "" }
                        var parts: [String] = []
                        if s.res != w.res { parts.append("分辨率 \(w.res == 2160 ? "4K" : "\(w.res)p") → \(s.res == 2160 ? "4K" : "\(s.res)p")") }
                        if s.fps != w.fps { parts.append("帧率 \(w.fps) → \(s.fps)") }
                        return "两颗摄像头同时工作时，系统带宽撑不住所选规格，已自动调整：" + parts.joined(separator: "，")
                    }
                    lastWhy = "硬件负载过高（\(String(format: "%.2f", session.hardwareCost))）"
                } catch let e as DualError {
                    lastWhy = e.message
                }
            }
        }
        throw DualError.unsupported(lastWhy)
    }

    private static func ultraWideWorksWithFront() -> Bool {
        guard let uw = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back),
              let fr = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else { return false }
        let ds = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera],
                                                  mediaType: .video, position: .unspecified)
        return ds.supportedMultiCamDeviceSets.contains { $0.contains(uw) && $0.contains(fr) }
    }

    private func resetSession() {
        session.beginConfiguration()
        for c in session.connections { session.removeConnection(c) }
        for o in session.outputs { session.removeOutput(o) }
        for i in session.inputs { session.removeInput(i) }
        session.commitConfiguration()
        backOut = AVCaptureVideoDataOutput(); frontOut = AVCaptureVideoDataOutput(); audioOut = AVCaptureAudioDataOutput()
        hasAudio = false
    }

    /// 在设备所有「支持同时工作」的规格里，挑最合适的一个。
    /// 片门全开偏好 4:3（整块传感器），否则偏好 16:9；长边不超过 bound；必须支持目标帧率。
    private func pickFormat(_ d: AVCaptureDevice, bound: Int32, fps: Int, full: Bool) -> AVCaptureDevice.Format? {
        var best: AVCaptureDevice.Format?
        var bestScore = -1
        for f in d.formats where f.isMultiCamSupported {
            let dim = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            guard dim.width <= bound else { continue }
            guard f.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= Double(fps) && $0.minFrameRate <= Double(fps) }) else { continue }
            let ar = Double(dim.width) / Double(dim.height)
            let is169 = abs(ar - 16.0 / 9.0) < 0.02, is43 = abs(ar - 4.0 / 3.0) < 0.02
            let pref = full ? is43 : is169
            let score = Int(dim.width) + (pref ? 1_000_000 : 0)
            if score > bestScore { bestScore = score; best = f }
        }
        return best
    }

    private func setFormat(_ d: AVCaptureDevice, _ f: AVCaptureDevice.Format, fps: Int) throws {
        try d.lockForConfiguration()
        defer { d.unlockForConfiguration() }
        d.activeFormat = f
        let t = CMTime(value: 1, timescale: CMTimeScale(fps))
        d.activeVideoMinFrameDuration = t
        d.activeVideoMaxFrameDuration = t
    }

    private func build(back: AVCaptureDevice, front: AVCaptureDevice, spec s: DualSpec, wantAudio: Bool) throws {
        guard let bf = pickFormat(back, bound: s.bound, fps: s.fps, full: s.full) else {
            throw DualError.unsupported("后置摄像头没有 \(s.label) 的「同时工作」规格")
        }
        // 前置：先按同样帧率找，没有就逐级降（前置往往到不了 60）
        var ffps = s.fps
        var ffOpt = pickFormat(front, bound: s.bound, fps: ffps, full: s.full)
        for f in [30, 24] where ffOpt == nil && f < s.fps { ffps = f; ffOpt = pickFormat(front, bound: s.bound, fps: f, full: s.full) }
        guard let ff = ffOpt else { throw DualError.unsupported("前置摄像头没有可用的「同时工作」规格") }
        try setFormat(back, bf, fps: s.fps); try setFormat(front, ff, fps: ffps)
        actualBackFps = s.fps

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let backIn: AVCaptureDeviceInput, frontIn: AVCaptureDeviceInput
        do { backIn = try AVCaptureDeviceInput(device: back); frontIn = try AVCaptureDeviceInput(device: front) }
        catch { throw DualError.failed("无法打开摄像头：\(error.localizedDescription)") }
        for i in [backIn, frontIn] {
            guard session.canAddInput(i) else { throw DualError.unsupported("系统不允许同时添加这两颗摄像头") }
            session.addInputWithNoConnections(i)
        }
        guard let bPort = backIn.ports(for: .video, sourceDeviceType: back.deviceType, sourceDevicePosition: back.position).first,
              let fPort = frontIn.ports(for: .video, sourceDeviceType: front.deviceType, sourceDevicePosition: front.position).first else {
            throw DualError.failed("找不到摄像头的视频端口")
        }
        let settings: [String: Any] = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        for (out, port) in [(backOut, bPort), (frontOut, fPort)] {
            out.videoSettings = settings
            out.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(out) else { throw DualError.failed("无法添加视频输出") }
            session.addOutputWithNoConnections(out)
            out.setSampleBufferDelegate(self, queue: dataQueue)
            let c = AVCaptureConnection(inputPorts: [port], output: out)
            guard session.canAddConnection(c) else { throw DualError.failed("无法连接视频输出") }
            session.addConnection(c)
            c.videoOrientation = .portrait
            if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = false }
        }
        // 麦克风（可选：没有权限就只录画面）
        if wantAudio, let mic = AVCaptureDevice.default(for: .audio), let micIn = try? AVCaptureDeviceInput(device: mic),
           session.canAddInput(micIn) {
            session.addInputWithNoConnections(micIn)
            let port = micIn.ports(for: .audio, sourceDeviceType: mic.deviceType, sourceDevicePosition: back.position).first
                ?? micIn.ports.first(where: { $0.mediaType == .audio })
            if let port = port, session.canAddOutput(audioOut) {
                session.addOutputWithNoConnections(audioOut)
                audioOut.setSampleBufferDelegate(self, queue: audioQueue)
                let ac = AVCaptureConnection(inputPorts: [port], output: audioOut)
                if session.canAddConnection(ac) { session.addConnection(ac); hasAudio = true }
            }
        }
        // 成品尺寸：在「后置规格竖过来」的画面里，取出和取景框同比例的最大矩形，长边不超过档位（720→1280，1080→1920，4K→3840）
        let dim = CMVideoFormatDescriptionGetDimensions(bf.formatDescription)
        let fdim = CMVideoFormatDescriptionGetDimensions(ff.formatDescription)
        let sw = CGFloat(dim.height), sh = CGFloat(dim.width)
        let asp = s.full ? CGFloat(dim.height) / CGFloat(dim.width) : max(0.4, min(1, s.aspect))
        var cw: CGFloat, ch: CGFloat
        if asp <= sw / sh { ch = sh; cw = sh * asp } else { cw = sw; ch = sw / asp }
        let cap: CGFloat = s.res == 720 ? 1280 : (s.res == 1080 ? 1920 : 3840)
        let k = min(1, cap / max(cw, ch)); cw *= k; ch *= k
        canvas = CGSize(width: (cw / 2).rounded() * 2, height: (ch / 2).rounded() * 2)
        let pk = min(1, 1080 / max(canvas.width, canvas.height))
        pvSize = CGSize(width: ((canvas.width * pk) / 2).rounded() * 2, height: ((canvas.height * pk) / 2).rounded() * 2)
        let lk = min(1, 720 / max(canvas.width, canvas.height))
        liveSize = CGSize(width: ((canvas.width * lk) / 2).rounded() * 2, height: ((canvas.height * lk) / 2).rounded() * 2)
        pvPool = makePool(pvSize); livePool = makePool(liveSize)
        info = "后置 \(dim.width)×\(dim.height)@\(s.fps)  前置 \(fdim.width)×\(fdim.height)@\(ffps)"
    }

    private func makePool(_ size: CGSize) -> CVPixelBufferPool? {
        var pool: CVPixelBufferPool?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width), kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        return pool
    }

    // MARK: - 变焦（等效倍数：后置 1× = 广角，0.5× = 超广角）

    func zoomRange(back: Bool) -> (CGFloat, CGFloat) {
        if back {
            let wide = backDevice?.deviceType == .builtInWideAngleCamera ? backDevice : AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
            let hi = min(30, wide?.activeFormat.videoMaxZoomFactor ?? 10)
            return (hasUltraWide ? 0.5 : 1, max(1, hi))
        }
        let hi = min(10, frontDevice?.activeFormat.videoMaxZoomFactor ?? 1)
        return (1, max(1, hi))
    }

    func currentZoom(back: Bool) -> CGFloat { back ? backZoom : frontZoom }

    /// 设置变焦。后置：等效倍数 < 1 时需要超广角镜头；镜头切换要重配会话，由 `needsLensSwitch` 判断，界面在松手时调用 `switchLens`。
    func setZoom(back: Bool, _ ez: CGFloat) {
        let (lo, hi) = zoomRange(back: back)
        let v = min(hi, max(lo, ez))
        if back { backZoom = v } else { frontZoom = v }
        sessionQueue.async { self.applyZoom(back: back) }
    }

    private func applyZoom(back: Bool) {
        guard let d = back ? backDevice : frontDevice else { return }
        var vz: CGFloat
        if back {
            let ez = backZoom
            vz = d.deviceType == .builtInUltraWideCamera ? ez / 0.5 : ez
        } else { vz = frontZoom }
        let hi = min(d.activeFormat.videoMaxZoomFactor, d.maxAvailableVideoZoomFactor)
        vz = min(hi, max(d.minAvailableVideoZoomFactor, vz))
        do {
            try d.lockForConfiguration()
            d.videoZoomFactor = vz
            d.unlockForConfiguration()
        } catch { /* 变焦失败不影响取景 */ }
    }

    /// 当前后置镜头能不能表达这个倍数；不能就说明需要换镜头
    func needsLensSwitch(forBackZoom ez: CGFloat) -> Bool {
        guard hasUltraWide else { return false }
        let onUW = backDevice?.deviceType == .builtInUltraWideCamera
        return (ez < 1 && !onUW) || (ez >= 1 && onUW)
    }

    // MARK: - 重配（设置里改了规格 / 切换镜头）

    /// 停掉会话 → 按新规格重配 → 重新开始。完成时回到主线程：
    /// (说明文字, 错误)。出错时已退回原来的规格。
    func reconfigure(_ want: DualSpec, completion: @escaping (String, String?) -> Void) {
        sessionQueue.async {
            let old = self.spec
            if self.session.isRunning { self.session.stopRunning() }
            self.lock.lock(); self.lastBack = nil; self.lastFront = nil; self.lock.unlock()
            self.dataQueue.sync { self.liveRing.removeAll() }
            DispatchQueue.main.async { self.previewLayer.flushAndRemoveImage() }
            let keepBack = self.backZoom, keepFront = self.frontZoom
            do {
                let note = try self.configure(want, wantAudio: self.wantAudioSaved)
                self.session.startRunning()
                // 同一颗镜头换规格时保留各自的倍数
                if (self.spec.ultraWide == old.ultraWide) { self.backZoom = keepBack; self.frontZoom = keepFront; self.applyZoom(back: true); self.applyZoom(back: false) }
                else { self.applyZoom(back: true) }
                DispatchQueue.main.async { completion(note, nil) }
            } catch {
                let msg = (error as? DualError)?.message ?? error.localizedDescription
                _ = try? self.configure(old, wantAudio: self.wantAudioSaved)
                self.session.startRunning()
                DispatchQueue.main.async { completion("", msg) }
            }
        }
    }

    func start() { sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop() { sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func setTorch(_ on: Bool) {
        guard let d = backDevice, d.hasTorch else { return }
        try? d.lockForConfiguration()
        d.torchMode = on ? .on : .off
        d.unlockForConfiguration()
    }

    // MARK: - 对焦 / 曝光

    private func dev(_ back: Bool) -> AVCaptureDevice? { back ? backDevice : frontDevice }

    /// 主画面里某点（0…1，已按取景框裁切后的坐标）→ 该摄像头传感器的对焦点（横屏坐标）
    func devicePoint(back: Bool, nx: CGFloat, ny: CGFloat, rectAspect: CGFloat) -> CGPoint {
        var x = nx
        if !back && layout.mirrorFront { x = 1 - x }
        guard let d = dev(back) else { return CGPoint(x: 0.5, y: 0.5) }
        let dim = CMVideoFormatDescriptionGetDimensions(d.activeFormat.formatDescription)
        let sw = CGFloat(dim.height), sh = CGFloat(dim.width)          // 竖屏后的源尺寸
        let srcA = sw / sh
        var vw: CGFloat = 1, vh: CGFloat = 1
        if rectAspect > srcA { vh = srcA / rectAspect } else { vw = rectAspect / srcA }
        let sx = 0.5 + (x - 0.5) * vw, sy = 0.5 + (ny - 0.5) * vh
        return CGPoint(x: min(1, max(0, sy)), y: min(1, max(0, 1 - sx)))
    }

    /// 对焦 + 测光到某点；lock = true 时锁定对焦和曝光
    func focus(back: Bool, at p: CGPoint, lock: Bool) {
        sessionQueue.async {
            guard let d = self.dev(back) else { return }
            do {
                try d.lockForConfiguration()
                if d.isFocusPointOfInterestSupported {
                    d.focusPointOfInterest = p
                    if d.isFocusModeSupported(lock ? .autoFocus : .continuousAutoFocus) { d.focusMode = lock ? .autoFocus : .continuousAutoFocus }
                }
                if d.isExposurePointOfInterestSupported {
                    d.exposurePointOfInterest = p
                    if d.isExposureModeSupported(lock ? .autoExpose : .continuousAutoExposure) { d.exposureMode = lock ? .autoExpose : .continuousAutoExposure }
                }
                d.unlockForConfiguration()
                if lock {
                    // 对完焦、测完光后再锁定
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.7) {
                        try? d.lockForConfiguration()
                        if d.isFocusModeSupported(.locked) { d.focusMode = .locked }
                        if d.isExposureModeSupported(.locked) { d.exposureMode = .locked }
                        d.unlockForConfiguration()
                    }
                }
            } catch {}
        }
    }

    func resetFocus(back: Bool) {
        sessionQueue.async {
            guard let d = self.dev(back) else { return }
            try? d.lockForConfiguration()
            if d.isFocusModeSupported(.continuousAutoFocus) { d.focusMode = .continuousAutoFocus }
            if d.isExposureModeSupported(.continuousAutoExposure) { d.exposureMode = .continuousAutoExposure }
            d.setExposureTargetBias(0, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }

    func biasRange(back: Bool) -> (Float, Float) {
        guard let d = dev(back) else { return (-2, 2) }
        return (max(-4, d.minExposureTargetBias), min(4, d.maxExposureTargetBias))
    }

    func setBias(back: Bool, _ v: Float) {
        sessionQueue.async {
            guard let d = self.dev(back) else { return }
            try? d.lockForConfiguration()
            // 曝光已锁定时，先让它重新收敛一次再自动锁回，否则曝光补偿不生效
            if d.exposureMode == .locked, d.isExposureModeSupported(.autoExpose) { d.exposureMode = .autoExpose }
            d.setExposureTargetBias(v, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }

    // MARK: - 过热 / 系统压力：自动降到 30 帧，保持流畅不卡死

    /// 系统压力或温度升高、已自动降帧时回调（主线程）
    var onPressure: ((String) -> Void)?
    private var pressureObs: [NSKeyValueObservation] = []
    private var thermalObs: NSObjectProtocol?
    private var throttled = false

    private func watchPressure() {
        pressureObs.removeAll()
        for d in [backDevice, frontDevice].compactMap({ $0 }) {
            pressureObs.append(d.observe(\.systemPressureState, options: [.new]) { [weak self] dev, _ in
                let lv = dev.systemPressureState.level
                if lv == .serious || lv == .critical || lv == .shutdown { self?.throttle("系统压力升高") }
            })
        }
        if thermalObs == nil {
            thermalObs = NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
                let t = ProcessInfo.processInfo.thermalState
                if t == .serious || t == .critical { self?.throttle("手机温度升高") }
            }
        }
        throttled = false
    }

    private func throttle(_ why: String) {
        sessionQueue.async {
            guard !self.throttled, self.actualBackFps > 30 else { return }
            self.throttled = true
            let t = CMTime(value: 1, timescale: 30)
            for d in [self.backDevice, self.frontDevice].compactMap({ $0 }) {
                try? d.lockForConfiguration()
                if d.activeVideoMinFrameDuration < t { d.activeVideoMinFrameDuration = t }
                if d.activeVideoMaxFrameDuration < t { d.activeVideoMaxFrameDuration = t }
                d.unlockForConfiguration()
            }
            self.actualBackFps = 30
            DispatchQueue.main.async { self.onPressure?("\(why)，已自动降到 30 帧，防止掉帧卡住") }
        }
    }

    // MARK: - 采集回调

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if output === audioOut { appendAudio(sampleBuffer); return }
        guard let pb = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        if output === frontOut {
            lock.lock(); lastFront = pb; lock.unlock()
            return
        }
        guard output === backOut else { return }
        lock.lock(); lastBack = pb; let f = lastFront; lock.unlock()
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        previewN += 1
        if actualBackFps <= 35 || previewN % 2 == 0 { renderPreview(back: pb, front: f, pts: pts) }     // 60 帧时预览隔帧刷新，把算力留给录像
        if wantRecord || isRecording { recordFrame(pts) }
        collectLive(back: pb, front: f, pts: pts)
    }

    // MARK: - 预览

    private func renderPreview(back: CVPixelBuffer, front: CVPixelBuffer?, pts: CMTime) {
        guard let pool = pvPool else { return }
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess, let dst = out else { return }
        let img = compose(back: back, front: front, size: pvSize)
        ci.render(img, to: dst, bounds: CGRect(origin: .zero, size: pvSize), colorSpace: rgb)
        var fd: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: dst, formatDescriptionOut: &fd)
        guard let fmt = fd else { return }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sb: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: dst, formatDescription: fmt, sampleTiming: &timing, sampleBufferOut: &sb)
        guard let sample = sb else { return }
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(arr) > 0 {
            let dict = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dict, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
                                 Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        if previewLayer.status == .failed { previewLayer.flush() }
        previewLayer.enqueue(sample)
    }

    // MARK: - 合成

    private var ovKey = ""
    private var maskImg: CIImage?
    private var ringImg: CIImage?

    /// 小窗的圆角遮罩（和边框）：只生成小窗那么大的一张，再平移到位置上
    private func overlays(_ rect: CGRect, _ size: CGSize, border: PipBorder, pipRadius: CGFloat) -> (CIImage, CIImage?) {
        let radius = rect.width * pipRadius, lw = max(2, size.width * 0.007)
        let key = "\(Int(rect.width))x\(Int(rect.height))r\(Int(radius))b\(border.rawValue)"
        if key != ovKey || maskImg == nil {
            let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
            let rs = CGSize(width: rect.width, height: rect.height)
            let rend = UIGraphicsImageRenderer(size: rs, format: fmt)
            let mask = rend.image { _ in
                UIColor.white.setFill()
                UIBezierPath(roundedRect: CGRect(origin: .zero, size: rs), cornerRadius: radius).fill()
            }
            maskImg = CIImage(cgImage: mask.cgImage!)
            if border == .none { ringImg = nil } else {
                let ring = rend.image { _ in
                    let p = UIBezierPath(roundedRect: CGRect(origin: .zero, size: rs).insetBy(dx: lw / 2, dy: lw / 2), cornerRadius: radius - lw / 2)
                    p.lineWidth = lw
                    (border == .white ? UIColor(white: 1, alpha: 0.95) : UIColor(white: 0, alpha: 0.9)).setStroke()
                    p.stroke()
                }
                ringImg = CIImage(cgImage: ring.cgImage!)
            }
            ovKey = key
        }
        return (maskImg!, ringImg)
    }

    /// 把 img 等比铺满 r（r 以左上角为原点），多出的部分裁掉
    private func fill(_ img: CIImage, _ r: CGRect, _ H: CGFloat, mirror: Bool) -> CIImage {
        var im = img
        let e = im.extent
        if mirror { im = im.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: e.width + 2 * e.origin.x, ty: 0)) }
        let e2 = im.extent
        let k = max(r.width / e2.width, r.height / e2.height)
        let sw = e2.width * k, sh = e2.height * k
        let cy = H - r.midY
        let moved = im.transformed(by: CGAffineTransform(scaleX: k, y: k))
            .transformed(by: CGAffineTransform(translationX: r.midX - sw / 2 - e2.origin.x * k, y: cy - sh / 2 - e2.origin.y * k))
        return moved.cropped(to: CGRect(x: r.minX, y: H - r.maxY, width: r.width, height: r.height))
    }

    func compose(back: CVPixelBuffer, front: CVPixelBuffer?, size: CGSize) -> CIImage {
        let L = layout, W = size.width, H = size.height
        let bk = CIImage(cvPixelBuffer: back)
        let ft = front.map { CIImage(cvPixelBuffer: $0) }
        let bg = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        var out: CIImage
        if let f = ft {
            let (mr, sr) = L.rects(W, H)
            let mainIsBack = L.backIsMain
            let mainImg = mainIsBack ? bk : f, secImg = mainIsBack ? f : bk
            let mainMirror = !mainIsBack && L.mirrorFront, secMirror = mainIsBack && L.mirrorFront
            let gMain = mainIsBack ? gradeBack : gradeFront, gSec = mainIsBack ? gradeFront : gradeBack
            var mainF = fill(mainImg, mr, H, mirror: mainMirror)
            if !gMain.isNeutral { mainF = gMain.apply(mainF) }
            out = mainF.composited(over: bg)
            var sec = fill(secImg, sr, H, mirror: secMirror)
            if !gSec.isNeutral { sec = gSec.apply(sec) }
            switch L.style {
            case .split:
                out = sec.composited(over: out)
            case .pip:
                let (mask, ring) = overlays(sr, size, border: L.border, pipRadius: L.pipRadius)
                let place = CGAffineTransform(translationX: sr.minX, y: H - sr.maxY)
                let blended = sec.applyingFilter("CIBlendWithAlphaMask", parameters: [
                    kCIInputBackgroundImageKey: out, kCIInputMaskImageKey: mask.transformed(by: place)])
                out = ring.map { $0.transformed(by: place).composited(over: blended) } ?? blended
            }
        } else {
            var one = fill(bk, CGRect(x: 0, y: 0, width: W, height: H), H, mirror: false)
            if !gradeBack.isNeutral { one = gradeBack.apply(one) }
            out = one.composited(over: bg)
        }
        return out.cropped(to: CGRect(origin: .zero, size: size))
    }

    // MARK: - 拍照

    /// 把当前一帧合成并存成 JPEG / HEIF 文件
    func takePhoto(to url: URL, heif: Bool, completion: @escaping (Bool, String?) -> Void) {
        dataQueue.async {
            self.lock.lock(); let b = self.lastBack, f = self.lastFront; self.lock.unlock()
            guard let back = b else { completion(false, "还没有画面"); return }
            let img = self.compose(back: back, front: f, size: self.canvas)
            do {
                if heif {
                    try self.ci.writeHEIFRepresentation(of: img, to: url, format: .RGBA8, colorSpace: self.rgb,
                                                        options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.9])
                } else {
                    try self.ci.writeJPEGRepresentation(of: img, to: url, colorSpace: self.rgb,
                                                        options: [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.93])
                }
                completion(true, nil)
            } catch { completion(false, error.localizedDescription) }
        }
    }

    // MARK: - 录像

    func startRecording(to url: URL, audio: Bool) {
        dataQueue.async {
            self.recURL = url; self.recordAudio = audio && self.hasAudio
            self.started = false; self.startPTS = .invalid; self.failMsg = nil
            self.wantRecord = true
        }
    }

    private func prepareWriter(firstPTS: CMTime) -> Bool {
        guard let url = recURL else { return false }
        try? FileManager.default.removeItem(at: url)
        do {
            let w = try AVAssetWriter(outputURL: url, fileType: .mp4)
            let big = max(canvas.width, canvas.height) > 2600
            let fps = actualBackFps
            let bitrate = Int(canvas.width * canvas.height * CGFloat(fps) * (big ? 0.07 : 0.1))
            let vs: [String: Any] = [
                AVVideoCodecKey: big ? AVVideoCodecType.hevc : AVVideoCodecType.h264,
                AVVideoWidthKey: Int(canvas.width), AVVideoHeightKey: Int(canvas.height),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(6_000_000, min(bitrate, 80_000_000)),
                                                  AVVideoExpectedSourceFrameRateKey: fps]
            ]
            let vi = AVAssetWriterInput(mediaType: .video, outputSettings: vs)
            vi.expectsMediaDataInRealTime = true
            let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vi, sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(canvas.width), kCVPixelBufferHeightKey as String: Int(canvas.height),
                kCVPixelBufferMetalCompatibilityKey as String: true
            ])
            guard w.canAdd(vi) else { return false }
            w.add(vi)
            if recordAudio {
                let aset: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: 1,
                                           AVSampleRateKey: 44100, AVEncoderBitRateKey: 96000]
                let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: aset)
                ai.expectsMediaDataInRealTime = true
                if w.canAdd(ai) { w.add(ai); aIn = ai } else { aIn = nil }
            } else { aIn = nil }
            guard w.startWriting() else { failMsg = w.error?.localizedDescription; return false }
            w.startSession(atSourceTime: firstPTS)
            writer = w; vIn = vi; adaptor = ad; startPTS = firstPTS; started = true
            return true
        } catch { failMsg = error.localizedDescription; return false }
    }

    private func recordFrame(_ pts: CMTime) {
        if !started {
            guard wantRecord else { return }
            if !prepareWriter(firstPTS: pts) { wantRecord = false; isRecording = false; return }
            isRecording = true; wantRecord = false
        }
        guard isRecording, let vi = vIn, let ad = adaptor, vi.isReadyForMoreMediaData, let pool = ad.pixelBufferPool else { return }
        lock.lock(); let b = lastBack, f = lastFront; lock.unlock()
        guard let back = b else { return }
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess, let dst = out else { return }
        let img = compose(back: back, front: f, size: canvas)
        ci.render(img, to: dst, bounds: CGRect(origin: .zero, size: canvas), colorSpace: rgb)
        if !ad.append(dst, withPresentationTime: pts) { failMsg = writer?.error?.localizedDescription }
    }

    private func appendAudio(_ sb: CMSampleBuffer) {
        guard isRecording, started, let ai = aIn, ai.isReadyForMoreMediaData else { return }
        if CMSampleBufferGetPresentationTimeStamp(sb) < startPTS { return }
        ai.append(sb)
    }

    func stopRecording(completion: @escaping (URL?, String?) -> Void) {
        dataQueue.async {
            self.wantRecord = false
            guard self.isRecording, let w = self.writer else {
                self.isRecording = false; self.started = false
                completion(nil, self.failMsg ?? "录像还没开始"); return
            }
            self.isRecording = false; self.started = false
            self.vIn?.markAsFinished(); self.aIn?.markAsFinished()
            let url = self.recURL
            w.finishWriting {
                self.writer = nil; self.vIn = nil; self.aIn = nil; self.adaptor = nil
                if w.status == .completed { completion(url, nil) }
                else { completion(nil, w.error?.localizedDescription ?? "录像写入失败") }
            }
        }
    }

    // MARK: - 实况照片

    private final class LiveJob {
        let writer: AVAssetWriter, vi: AVAssetWriterInput, ad: AVAssetWriterInputPixelBufferAdaptor
        var pending: [LiveFrame]
        let base: CMTime, need: Double, still: Double, url: URL
        let done: (URL?, Double, String?) -> Void
        init(writer: AVAssetWriter, vi: AVAssetWriterInput, ad: AVAssetWriterInputPixelBufferAdaptor, pending: [LiveFrame],
             base: CMTime, need: Double, still: Double, url: URL, done: @escaping (URL?, Double, String?) -> Void) {
            self.writer = writer; self.vi = vi; self.ad = ad; self.pending = pending; self.base = base
            self.need = need; self.still = still; self.url = url; self.done = done
        }
        func drain() {
            while !pending.isEmpty && vi.isReadyForMoreMediaData {
                let f = pending.removeFirst()
                _ = ad.append(f.pb, withPresentationTime: CMTimeSubtract(f.pts, base))
            }
        }
    }
    private var liveJob: LiveJob?

    /// 实况开着时，持续把最近 1.5 秒（合成 + 调色后、缩小到长边 720）留在内存里；快门后边收边写文件。
    private func collectLive(back: CVPixelBuffer, front: CVPixelBuffer?, pts: CMTime) {
        guard liveEnabled || liveJob != nil, !isRecording, let pool = livePool else { return }
        pvFrameN += 1
        if actualBackFps > 35 && pvFrameN % 2 == 1 { return }       // 60 帧时隔帧取，实况视频按 30 帧
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess, let dst = out else { return }
        let img = compose(back: back, front: front, size: liveSize)
        ci.render(img, to: dst, bounds: CGRect(origin: .zero, size: liveSize), colorSpace: rgb)
        let fr = LiveFrame(pb: dst, pts: pts)
        if let job = liveJob {
            job.pending.append(fr)
            job.drain()
            let t = CMTimeGetSeconds(CMTimeSubtract(pts, job.base))
            if t >= job.need {
                liveJob = nil
                writeQueue.async {
                    var n = 0
                    while !job.pending.isEmpty && n < 3000 { job.drain(); usleep(2000); n += 1 }
                    job.vi.markAsFinished()
                    job.writer.finishWriting {
                        if job.writer.status == .completed { job.done(job.url, job.still, nil) }
                        else { job.done(nil, 0, job.writer.error?.localizedDescription ?? "实况合成失败") }
                    }
                }
            }
            return
        }
        liveRing.append(fr)
        while let f = liveRing.first, CMTimeGetSeconds(CMTimeSubtract(pts, f.pts)) > 1.5 { liveRing.removeFirst() }
    }

    /// 按下快门：取走环形缓存，继续收到总长 totalSeconds，合成 MOV。done(MOV 文件, 静帧所在秒数, 错误)
    func captureLive(totalSeconds: Double, done: @escaping (URL?, Double, String?) -> Void) {
        dataQueue.async {
            guard self.liveJob == nil else { done(nil, 0, "上一张实况还在合成"); return }
            guard let first = self.liveRing.first, let last = self.liveRing.last else { done(nil, 0, "实况缓存还没准备好，请稍等一下再拍"); return }
            let size = self.liveSize
            let url = SchemeHandler.outDir.appendingPathComponent("澄影双摄_实况_\(UUID().uuidString).mov")
            do {
                try? FileManager.default.removeItem(at: url)
                let w = try AVAssetWriter(outputURL: url, fileType: .mov)
                let vs: [String: Any] = [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(size.width), AVVideoHeightKey: Int(size.height),
                                         AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: Int(size.width * size.height * 8)]]
                let vi = AVAssetWriterInput(mediaType: .video, outputSettings: vs)
                vi.expectsMediaDataInRealTime = true
                let ad = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vi, sourcePixelBufferAttributes: nil)
                guard w.canAdd(vi) else { done(nil, 0, "无法创建实况视频"); return }
                w.add(vi)
                guard w.startWriting() else { done(nil, 0, w.error?.localizedDescription ?? "无法写入"); return }
                w.startSession(atSourceTime: .zero)
                let still = CMTimeGetSeconds(CMTimeSubtract(last.pts, first.pts))
                let job = LiveJob(writer: w, vi: vi, ad: ad, pending: self.liveRing, base: first.pts,
                                  need: max(1.0, totalSeconds), still: still, url: url, done: done)
                self.liveRing.removeAll()
                job.drain()
                self.liveJob = job
            } catch { done(nil, 0, error.localizedDescription) }
        }
    }
}
