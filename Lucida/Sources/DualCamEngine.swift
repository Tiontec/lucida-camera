import UIKit
import AVFoundation
import CoreImage
import ImageIO

/// 原生双摄引擎：AVCaptureMultiCamSession 同时开前后摄像头（可选麦克风），
/// 用 CoreImage 把两路画面合成「画中画」或「上下分屏」，拍照输出 JPEG，录像用 AVAssetWriter（H.264 + AAC，带声音）。
/// 预览不经过合成（两个 AVCaptureVideoPreviewLayer 直接显示，省电、不卡），界面上的摆放和成品里的摆放用同一份 DualLayout 计算，所见即所得。

struct DualLayout {
    enum Style { case pip, split }
    var style: Style = .pip
    var backIsMain = true
    var mirrorFront = true
    var pipX: CGFloat = 1      // 0…1：小窗在可移动范围里的水平位置（1 = 最右）
    var pipY: CGFloat = 0      // 0…1：垂直位置（0 = 最上）
    var pipW: CGFloat = 0.32   // 小窗宽度 / 画面宽度

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

final class DualCamEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    let session = AVCaptureMultiCamSession()
    let sessionQueue = DispatchQueue(label: "lucida.dual.session")
    private let dataQueue = DispatchQueue(label: "lucida.dual.data", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "lucida.dual.audio", qos: .userInitiated)

    private(set) var backDevice: AVCaptureDevice?
    private(set) var frontDevice: AVCaptureDevice?
    private var backOut = AVCaptureVideoDataOutput()
    private var frontOut = AVCaptureVideoDataOutput()
    private var audioOut = AVCaptureAudioDataOutput()
    private(set) var hasAudio = false
    private(set) var backPreview: AVCaptureVideoPreviewLayer?
    private(set) var frontPreview: AVCaptureVideoPreviewLayer?
    private var frontPreviewConn: AVCaptureConnection?
    /// 成品画面尺寸（竖屏，宽 × 高）
    private(set) var canvas = CGSize(width: 720, height: 1280)

    // 最新一帧（数据队列写、其它线程读）
    private let lock = NSLock()
    private var lastBack: CVPixelBuffer?
    private var lastFront: CVPixelBuffer?
    private var _layout = DualLayout()
    var layout: DualLayout {
        get { lock.lock(); defer { lock.unlock() }; return _layout }
        set { lock.lock(); _layout = newValue; lock.unlock(); applyPreviewMirror() }
    }

    private let ci = CIContext(options: [.cacheIntermediates: false])
    private let rgb = CGColorSpaceCreateDeviceRGB()

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

    // MARK: - 配置

    static var isSupported: Bool { AVCaptureMultiCamSession.isMultiCamSupported }

    /// 在 sessionQueue 上调用。成功返回 nil；失败抛 DualError。
    func configure(wantAudio: Bool) throws {
        guard AVCaptureMultiCamSession.isMultiCamSupported else {
            throw DualError.unsupported("这台 iPhone 不支持前后摄像头同时工作（需要 iPhone XS / XR 及以后的机型）")
        }
        guard let back = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) else {
            throw DualError.unsupported("没有找到前置或后置摄像头")
        }
        backDevice = back; frontDevice = front
        // 从高到低试三档规格，直到系统说「撑得住」（hardwareCost / systemPressureCost ≤ 1）
        let tiers: [Int32] = [1920, 1280, 640]
        var lastWhy = "系统不允许这两颗摄像头同时以可用规格工作"
        for maxW in tiers {
            resetSession()
            do {
                try build(back: back, front: front, maxW: maxW, wantAudio: wantAudio)
                if session.hardwareCost <= 1.0 && session.systemPressureCost <= 1.0 { return }
                lastWhy = "硬件负载过高（\(String(format: "%.2f", session.hardwareCost))）"
            } catch let e as DualError {
                lastWhy = e.message
            }
        }
        throw DualError.unsupported(lastWhy)
    }

    private func resetSession() {
        session.beginConfiguration()
        for c in session.connections { session.removeConnection(c) }
        for o in session.outputs { session.removeOutput(o) }
        for i in session.inputs { session.removeInput(i) }
        session.commitConfiguration()
        backOut = AVCaptureVideoDataOutput(); frontOut = AVCaptureVideoDataOutput(); audioOut = AVCaptureAudioDataOutput()
        backPreview = nil; frontPreview = nil; frontPreviewConn = nil; hasAudio = false
    }

    private func pickFormat(_ d: AVCaptureDevice, maxW: Int32) -> AVCaptureDevice.Format? {
        var best: AVCaptureDevice.Format?
        var bestScore = -1
        for f in d.formats where f.isMultiCamSupported {
            let dim = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
            guard dim.width <= maxW else { continue }
            guard f.videoSupportedFrameRateRanges.contains(where: { $0.maxFrameRate >= 30 && $0.minFrameRate <= 30 }) else { continue }
            let is169 = abs(Double(dim.width) / Double(dim.height) - 16.0 / 9.0) < 0.02
            let score = Int(dim.width) + (is169 ? 100_000 : 0)
            if score > bestScore { bestScore = score; best = f }
        }
        return best
    }

    private func setFormat(_ d: AVCaptureDevice, _ f: AVCaptureDevice.Format) throws {
        try d.lockForConfiguration()
        d.activeFormat = f
        d.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        d.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
        d.unlockForConfiguration()
    }

    private func build(back: AVCaptureDevice, front: AVCaptureDevice, maxW: Int32, wantAudio: Bool) throws {
        guard let bf = pickFormat(back, maxW: maxW), let ff = pickFormat(front, maxW: maxW) else {
            throw DualError.unsupported("这台设备的摄像头没有支持「同时工作」的规格")
        }
        try setFormat(back, bf); try setFormat(front, ff)
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
        for (out, port, mirror) in [(backOut, bPort, false), (frontOut, fPort, false)] {
            out.videoSettings = settings
            out.alwaysDiscardsLateVideoFrames = true
            guard session.canAddOutput(out) else { throw DualError.failed("无法添加视频输出") }
            session.addOutputWithNoConnections(out)
            out.setSampleBufferDelegate(self, queue: dataQueue)
            let c = AVCaptureConnection(inputPorts: [port], output: out)
            guard session.canAddConnection(c) else { throw DualError.failed("无法连接视频输出") }
            session.addConnection(c)
            c.videoOrientation = .portrait
            if c.isVideoMirroringSupported { c.automaticallyAdjustsVideoMirroring = false; c.isVideoMirrored = mirror }
        }
        // 预览层
        let bl = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        let fl = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        for (l, p) in [(bl, bPort), (fl, fPort)] {
            let c = AVCaptureConnection(inputPort: p, videoPreviewLayer: l)
            guard session.canAddConnection(c) else { throw DualError.failed("无法连接预览") }
            session.addConnection(c)
            c.videoOrientation = .portrait
            if l === fl { frontPreviewConn = c }
            l.videoGravity = .resizeAspectFill
        }
        backPreview = bl; frontPreview = fl
        applyPreviewMirror()

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
        // 成品尺寸：后置主画面竖过来后的尺寸，最大 1080×1920
        let dim = CMVideoFormatDescriptionGetDimensions(bf.formatDescription)
        let w = CGFloat(min(dim.height, 1080)), h = CGFloat(min(dim.width, 1920))
        canvas = CGSize(width: (w / 2).rounded() * 2, height: (h / 2).rounded() * 2)
    }

    private func applyPreviewMirror() {
        guard let c = frontPreviewConn, c.isVideoMirroringSupported else { return }
        lock.lock(); let m = _layout.mirrorFront; lock.unlock()
        c.automaticallyAdjustsVideoMirroring = false
        c.isVideoMirrored = m
    }

    func start() { sessionQueue.async { if !self.session.isRunning { self.session.startRunning() } } }
    func stop() { sessionQueue.async { if self.session.isRunning { self.session.stopRunning() } } }

    func setTorch(_ on: Bool) {
        guard let d = backDevice, d.hasTorch else { return }
        try? d.lockForConfiguration()
        d.torchMode = on ? .on : .off
        d.unlockForConfiguration()
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
        lock.lock(); lastBack = pb; lock.unlock()
        if wantRecord || isRecording { recordFrame(sampleBuffer) }
    }

    // MARK: - 合成

    private var maskKey = ""
    private var maskImg: CIImage?
    private var ringImg: CIImage?

    private func overlays(_ rect: CGRect, _ size: CGSize) -> (CIImage, CIImage) {
        let key = "\(Int(size.width))x\(Int(size.height))@\(rect)"
        if key == maskKey, let m = maskImg, let r = ringImg { return (m, r) }
        let radius = rect.width * 0.16, lw = max(3, size.width * 0.006)
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1; fmt.opaque = false
        let rend = UIGraphicsImageRenderer(size: size, format: fmt)
        let mask = rend.image { c in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: radius).fill()
        }
        let ring = rend.image { c in
            let p = UIBezierPath(roundedRect: rect.insetBy(dx: lw / 2, dy: lw / 2), cornerRadius: radius)
            p.lineWidth = lw
            UIColor(white: 1, alpha: 0.92).setStroke()
            p.stroke()
        }
        maskImg = CIImage(cgImage: mask.cgImage!); ringImg = CIImage(cgImage: ring.cgImage!); maskKey = key
        return (maskImg!, ringImg!)
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

    func compose(back: CVPixelBuffer, front: CVPixelBuffer?) -> CIImage {
        let L = layout, size = canvas, W = size.width, H = size.height
        let bk = CIImage(cvPixelBuffer: back)
        let ft = front.map { CIImage(cvPixelBuffer: $0) }
        let bg = CIImage(color: .black).cropped(to: CGRect(origin: .zero, size: size))
        guard let f = ft else { return fill(bk, CGRect(x: 0, y: 0, width: W, height: H), H, mirror: false).composited(over: bg) }
        let (mr, sr) = L.rects(W, H)
        let mainIsBack = L.backIsMain
        let mainImg = mainIsBack ? bk : f, secImg = mainIsBack ? f : bk
        let mainMirror = !mainIsBack && L.mirrorFront, secMirror = mainIsBack && L.mirrorFront
        var out = fill(mainImg, mr, H, mirror: mainMirror).composited(over: bg)
        let sec = fill(secImg, sr, H, mirror: secMirror)
        switch L.style {
        case .split:
            out = sec.composited(over: out)
        case .pip:
            let (mask, ring) = overlays(sr, size)
            let blended = sec.applyingFilter("CIBlendWithAlphaMask",
                                             parameters: [kCIInputBackgroundImageKey: out, kCIInputMaskImageKey: mask])
            out = ring.composited(over: blended)
        }
        return out.cropped(to: CGRect(origin: .zero, size: size))
    }

    // MARK: - 拍照

    /// 把当前一帧合成并存成 JPEG 文件
    func takePhoto(to url: URL, completion: @escaping (Bool, String?) -> Void) {
        dataQueue.async {
            self.lock.lock(); let b = self.lastBack, f = self.lastFront; self.lock.unlock()
            guard let back = b else { completion(false, "还没有画面"); return }
            let img = self.compose(back: back, front: f)
            let opts: [CIImageRepresentationOption: Any] = [CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): 0.93]
            do {
                try self.ci.writeJPEGRepresentation(of: img, to: url, colorSpace: self.rgb, options: opts)
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
            let bitrate = Int(canvas.width * canvas.height * 6)   // 1080×1920 ≈ 12 Mbps
            let vs: [String: Any] = [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(canvas.width), AVVideoHeightKey: Int(canvas.height),
                AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate,
                                                  AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                                  AVVideoExpectedSourceFrameRateKey: 30]
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

    private func recordFrame(_ sb: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
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
        let img = compose(back: back, front: f)
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
}
