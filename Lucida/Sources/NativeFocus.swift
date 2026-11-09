import UIKit
import AVFoundation

/// 点按对焦 / 长按锁定 AE·AF（原生）。
/// iPhone 的网页取景（WKWebView 的 getUserMedia）没有开放对焦接口，所以由原生壳直接设置摄像头的对焦点 / 曝光点。
/// 坐标：网页传来的是「画面里的位置」(x 向右、y 向下，0…1)，这里换算成摄像头传感器坐标
/// （传感器的原生方向是横屏、Home 键在右侧）。
/// 说明：网页取景是系统另一个进程在用这颗摄像头，这里是对同一颗摄像头设置对焦——能不能生效取决于系统是否允许，
/// 失败时返回 ok:false，网页会回到原来的「系统自动对焦」提示。
enum NativeFocus {
    static func apply(_ b: [String: Any], done: @escaping (Bool) -> Void) {
        let front = (b["position"] as? String) == "front"
        if front { done(false); return }                       // 前置镜头固定焦距，没有可对焦的
        let label = (b["label"] as? String) ?? ""
        guard let device = pick(label: label) else { done(false); return }
        let release = (b["release"] as? Bool) ?? false
        let lock = (b["lock"] as? Bool) ?? false
        let x = max(0, min(1, (b["x"] as? Double) ?? 0.5))
        let y = max(0, min(1, (b["y"] as? Double) ?? 0.5))
        let angle = (b["angle"] as? Int) ?? 0
        let p = release ? CGPoint(x: 0.5, y: 0.5) : devicePoint(x: x, y: y, angle: angle)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try device.lockForConfiguration()
                defer { device.unlockForConfiguration() }
                var touched = false
                if device.isFocusPointOfInterestSupported {
                    device.focusPointOfInterest = p
                    let mode: AVCaptureDevice.FocusMode = (lock && !release) ? .autoFocus : .continuousAutoFocus
                    if device.isFocusModeSupported(mode) { device.focusMode = mode; touched = true }
                }
                if device.isExposurePointOfInterestSupported {
                    device.exposurePointOfInterest = p
                    let mode: AVCaptureDevice.ExposureMode = (lock && !release) ? .autoExpose : .continuousAutoExposure
                    if device.isExposureModeSupported(mode) { device.exposureMode = mode; touched = true }
                }
                DispatchQueue.main.async { done(touched) }
            } catch {
                DispatchQueue.main.async { done(false) }
            }
        }
    }

    /// 按网页轨道的名称找当前正在用的那颗后置摄像头；找不到就用后置广角。
    private static func pick(label: String) -> AVCaptureDevice? {
        let types: [AVCaptureDevice.DeviceType] = [
            .builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
            .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera
        ]
        let ds = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .back)
        if !label.isEmpty, let d = ds.devices.first(where: { $0.localizedName == label }) { return d }
        return AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    }

    /// 屏幕方向 → 传感器坐标。angle 是网页 screen.orientation.angle：
    /// 0 竖屏；90 / 270 横屏（和 NativeCamera 里的方向换算保持一致）；180 倒置竖屏。
    private static func devicePoint(x: Double, y: Double, angle: Int) -> CGPoint {
        switch angle {
        case 90:        return CGPoint(x: 1 - x, y: 1 - y)
        case 270, -90:  return CGPoint(x: x, y: y)
        case 180:       return CGPoint(x: 1 - y, y: x)
        default:        return CGPoint(x: y, y: 1 - x)         // 竖屏
        }
    }
}
