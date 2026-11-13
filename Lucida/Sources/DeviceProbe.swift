import UIKit
import AVFoundation

/// 打开澄影时先测：有几颗摄像头、有没有超广角 / 长焦、虚拟多摄的换镜倍数、屏幕比例。
/// 结果以 JSON 注入网页（window.__LUCIDA_NATIVE__），网页据此决定变焦条和镜头预热。
enum DeviceProbe {
    static func machine() -> String {
        var sys = utsname(); uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        return mirror.children.reduce("") { acc, e in
            guard let v = e.value as? Int8, v != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(v)))
        }
    }

    static func info() -> [String: Any] {
        var types: [AVCaptureDevice.DeviceType] = [
            .builtInUltraWideCamera, .builtInWideAngleCamera, .builtInTelephotoCamera,
            .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera
        ]
        types.append(.builtInTrueDepthCamera)
        let ds = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified)
        var cams: [[String: Any]] = []
        var hasUW = false, hasTele = false, hasWide = false, backCount = 0, virtualTriple = false
        for d in ds.devices {
            let pos: String = d.position == .back ? "back" : (d.position == .front ? "front" : "unspecified")
            var kind = "other"
            switch d.deviceType {
            case .builtInUltraWideCamera: kind = "ultrawide"; if d.position == .back { hasUW = true }
            case .builtInWideAngleCamera: kind = "wide"; if d.position == .back { hasWide = true }
            case .builtInTelephotoCamera: kind = "tele"; if d.position == .back { hasTele = true }
            case .builtInDualCamera: kind = "dual"
            case .builtInDualWideCamera: kind = "dualwide"
            case .builtInTripleCamera: kind = "triple"; virtualTriple = true
            default: break
            }
            if d.position == .back && !d.isVirtualDevice { backCount += 1 }
            var item: [String: Any] = [
                "id": d.uniqueID, "name": d.localizedName, "kind": kind, "pos": pos,
                "fov": Double(d.activeFormat.videoFieldOfView),
                "maxZoom": Double(d.maxAvailableVideoZoomFactor),
                "virtual": d.isVirtualDevice
            ]
            if d.isVirtualDevice {
                item["switchOver"] = d.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue }
                item["constituents"] = d.constituentDevices.map { $0.localizedName }
            }
            cams.append(item)
        }
        let scr = UIScreen.main
        let b = scr.bounds
        var safe: [String: Double] = ["top": 0, "bottom": 0]
        if let w = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.windows.first }).first {
            safe = ["top": Double(w.safeAreaInsets.top), "bottom": Double(w.safeAreaInsets.bottom)]
        }
        return [
            "version": "11.1.5",
            "multiCam": AVCaptureMultiCamSession.isMultiCamSupported,
            "model": machine(),
            "ios": UIDevice.current.systemVersion,
            "cameras": cams,
            "hasUltraWide": hasUW, "hasTele": hasTele, "hasWide": hasWide,
            "backPhysical": backCount, "virtualTriple": virtualTriple,
            "screen": ["w": Double(b.width), "h": Double(b.height), "scale": Double(scr.scale),
                       "ratio": Double(max(b.width, b.height) / max(1, min(b.width, b.height))), "safe": safe],
            // 能不能拍 ProRAW 要等真正建立相机会话才知道；三摄 Pro 机型一般可以
            "rawLikely": virtualTriple,
            "heif": true
        ]
    }

    static func json() -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: info(), options: []),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
}
