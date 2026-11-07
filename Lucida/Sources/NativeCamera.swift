import UIKit
import AVFoundation
import Photos

/// 原生拍一张（JPEG / HEIF / Apple ProRAW）。
/// iOS 同一时刻只允许一个会话占用摄像头，所以网页在调用前会先释放自己的取景流，
/// 拍完后再重新打开。写入系统相册：ProRAW = DNG 主资源 + 处理后的 JPEG 作为备用资源。
final class NativeCamera: NSObject, AVCapturePhotoCaptureDelegate {
    static let shared = NativeCamera()

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "lucida.nativecam")
    private var completion: (([String: Any]) -> Void)?
    private var processed: Data?
    private var rawData: Data?
    private var wantRaw = false
    private var wantHEIF = false
    private var failMsg: String?

    /// body: position("back"|"front"), zoom(网页倍率，1=主摄), format("jpeg"|"heif"|"raw"), orientation(UIDeviceOrientation.rawValue)
    func capture(body: [String: Any], completion: @escaping ([String: Any]) -> Void) {
        let position = (body["position"] as? String) == "front" ? AVCaptureDevice.Position.front : .back
        let zoom = (body["zoom"] as? Double) ?? 1
        let format = (body["format"] as? String) ?? "jpeg"
        let orient = AVCaptureVideoOrientation(deviceOrientation: UIDeviceOrientation(rawValue: (body["orientation"] as? Int) ?? 1) ?? .portrait)
        queue.async { [weak self] in
            self?.run(position: position, zoom: zoom, format: format, orientation: orient, completion: completion)
        }
    }

    private func fail(_ msg: String, _ completion: @escaping ([String: Any]) -> Void) {
        if session.isRunning { session.stopRunning() }
        DispatchQueue.main.async { completion(["ok": false, "error": msg]) }
    }

    private func run(position: AVCaptureDevice.Position, zoom: Double, format: String,
                     orientation: AVCaptureVideoOrientation, completion: @escaping ([String: Any]) -> Void) {
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            fail("没有相机权限", completion); return
        }
        // 虚拟多摄优先（三摄 > 双广角 > 双摄 > 广角）：一颗设备里所有镜头同时待命，变焦时系统自动无缝换镜头
        let order: [AVCaptureDevice.DeviceType] = position == .back
            ? [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            : [.builtInWideAngleCamera]
        var dev: AVCaptureDevice?
        for t in order { if let d = AVCaptureDevice.default(t, for: .video, position: position) { dev = d; break } }
        guard let device = dev, let input = try? AVCaptureDeviceInput(device: device) else {
            fail("找不到摄像头", completion); return
        }

        self.completion = completion
        self.processed = nil; self.rawData = nil; self.failMsg = nil
        wantRaw = (format == "raw"); wantHEIF = (format == "heif")

        session.beginConfiguration()
        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }
        session.outputs.forEach { session.removeOutput($0) }
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration(); fail("相机会话配置失败", completion); return
        }
        session.addInput(input)
        session.addOutput(output)
        if #available(iOS 16.0, *) {
            if let best = device.activeFormat.supportedMaxPhotoDimensions.last { output.maxPhotoDimensions = best }
        } else {
            output.isHighResolutionCaptureEnabled = true
        }
        output.maxPhotoQualityPrioritization = .quality
        if #available(iOS 14.3, *), output.isAppleProRAWSupported { output.isAppleProRAWEnabled = true }
        session.commitConfiguration()

        // 网页倍率 → 设备倍率：虚拟设备里 1.0 是超广角，主摄在第一个换镜倍数（通常 2.0）
        var base = 1.0
        if device.isVirtualDevice, device.constituentDevices.first?.deviceType == .builtInUltraWideCamera {
            base = device.virtualDeviceSwitchOverVideoZoomFactors.first?.doubleValue ?? 2.0
        }
        do {
            try device.lockForConfiguration()
            let f = min(max(zoom * base, Double(device.minAvailableVideoZoomFactor)), Double(device.maxAvailableVideoZoomFactor))
            device.videoZoomFactor = CGFloat(f)
            device.unlockForConfiguration()
        } catch {}

        session.startRunning()
        // 等自动曝光 / 对焦稳定（最多 1.2 秒）
        Thread.sleep(forTimeInterval: 0.45)
        var waited = 0.0
        while (device.isAdjustingExposure || device.isAdjustingFocus) && waited < 0.8 {
            Thread.sleep(forTimeInterval: 0.05); waited += 0.05
        }

        if let c = output.connection(with: .video), c.isVideoOrientationSupported { c.videoOrientation = orientation }

        var settings: AVCapturePhotoSettings
        var gotRawFormat = false
        if wantRaw, #available(iOS 14.3, *), output.isAppleProRAWEnabled,
           let rawType = output.availableRawPhotoPixelFormatTypes.first(where: { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }) {
            settings = AVCapturePhotoSettings(rawPixelFormatType: rawType,
                                              processedFormat: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            gotRawFormat = true
        } else if wantHEIF, output.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
        }
        if wantRaw && !gotRawFormat { failMsg = "这台设备不支持 ProRAW，已改拍 JPEG" }
        settings.photoQualityPrioritization = .quality
        if #available(iOS 16.0, *) { settings.maxPhotoDimensions = output.maxPhotoDimensions }
        output.capturePhoto(with: settings, delegate: self)
    }

    // MARK: AVCapturePhotoCaptureDelegate
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error { failMsg = error.localizedDescription; return }
        guard let d = photo.fileDataRepresentation() else { return }
        if photo.isRawPhoto { rawData = d } else { processed = d }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        session.stopRunning()
        let cb = completion; completion = nil
        guard let done = cb else { return }
        guard processed != nil || rawData != nil else {
            let m = error?.localizedDescription ?? failMsg ?? "拍摄失败"
            DispatchQueue.main.async { done(["ok": false, "error": m]) }
            return
        }
        let proc = processed, raw = rawData, heif = wantHEIF
        // 1. 写入系统相册
        PhotoSaver.auth { granted in
            let finish: (Bool, String?) -> Void = { saved, msg in
                // 2. 给网页一份 JPEG（相册预览 / 编辑用）
                var url = "", name = "", mime = "image/jpeg"
                let src = proc ?? raw
                if let s = src, let j = PhotoSaver.jpegFile(from: s) {
                    name = j.lastPathComponent
                    url = "lucida://file/" + (name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name)
                } else { mime = "" }
                var r: [String: Any] = ["ok": !url.isEmpty, "saved": saved, "raw": raw != nil, "url": url, "name": name, "mime": mime]
                if let m = msg { r["error"] = m } else if let f = self.failMsg { r["note"] = f }
                DispatchQueue.main.async { done(r) }
            }
            guard granted else { finish(false, "没有系统相册权限"); return }
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                if let raw = raw {
                    let o = PHAssetResourceCreationOptions(); o.uniformTypeIdentifier = "com.adobe.raw-image"
                    req.addResource(with: .photo, data: raw, options: o)
                    if let p = proc { req.addResource(with: .alternatePhoto, data: p, options: nil) }
                } else if let p = proc {
                    let o = PHAssetResourceCreationOptions()
                    o.uniformTypeIdentifier = heif ? "public.heic" : "public.jpeg"
                    req.addResource(with: .photo, data: p, options: o)
                }
            }, completionHandler: { ok, err in finish(ok, err?.localizedDescription) })
        }
    }
}

extension AVCaptureVideoOrientation {
    init(deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .landscapeLeft: self = .landscapeRight        // 设备与取景方向相反
        case .landscapeRight: self = .landscapeLeft
        case .portraitUpsideDown: self = .portraitUpsideDown
        default: self = .portrait
        }
    }
}
