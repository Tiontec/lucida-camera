import UIKit
import CoreImage

/// 原生双摄的设置（记在 UserDefaults 里）。
enum PipBorder: String { case none, white, black }

final class DualSettings {
    static let shared = DualSettings()
    private let d = UserDefaults.standard
    private func key(_ k: String) -> String { "lucida.dual2." + k }

    var res: Int {            // 720 / 1080 / 2160
        get { let v = d.integer(forKey: key("res")); return [720, 1080, 2160].contains(v) ? v : 1080 }
        set { d.set(newValue, forKey: key("res")) }
    }
    var fps: Int {            // 24 / 30 / 60
        get { let v = d.integer(forKey: key("fps")); return [24, 30, 60].contains(v) ? v : 30 }
        set { d.set(newValue, forKey: key("fps")) }
    }
    var heif: Bool { get { d.bool(forKey: key("heif")) } set { d.set(newValue, forKey: key("heif")) } }
    var fullSensor: Bool { get { d.bool(forKey: key("full")) } set { d.set(newValue, forKey: key("full")) } }
    var border: PipBorder {
        get { PipBorder(rawValue: d.string(forKey: key("border")) ?? "") ?? .none }
        set { d.set(newValue.rawValue, forKey: key("border")) }
    }
    var liveOn: Bool { get { d.bool(forKey: key("live")) } set { d.set(newValue, forKey: key("live")) } }
    var liveDur: Double {     // 3 / 5 / 6 / 8 秒（快门前固定 1.5 秒）
        get { let v = d.double(forKey: key("liveDur")); return [3, 5, 6, 8].contains(v) ? v : 3 }
        set { d.set(newValue, forKey: key("liveDur")) }
    }
    var liveAlsoStill: Bool { get { d.bool(forKey: key("liveStill")) } set { d.set(newValue, forKey: key("liveStill")) } }
    var glass: Bool { get { d.bool(forKey: key("glass")) } set { d.set(newValue, forKey: key("glass")) } }
    var mirror: Bool { get { d.object(forKey: key("mirror")) as? Bool ?? true } set { d.set(newValue, forKey: key("mirror")) } }
    var audio: Bool { get { d.object(forKey: key("audio")) as? Bool ?? true } set { d.set(newValue, forKey: key("audio")) } }
    var pipStyleSplit: Bool { get { d.bool(forKey: key("split")) } set { d.set(newValue, forKey: key("split")) } }
    var backIsMain: Bool { get { d.object(forKey: key("backMain")) as? Bool ?? true } set { d.set(newValue, forKey: key("backMain")) } }

    let grade = GradeState()
}

// MARK: - 调色（和主页面「调色板 / 质感 / 颗粒」同一套预设和参数）

struct StylePreset {
    let sid: String, name: String
    let t: Double, c: Double, s: Double          // 色调 / 颜色 / 强度（-100…100，强度 0…100）
    let cast: [Double], ca: Double
    var fade: Double = 0, con: Double = 0
}

let stylePresets: [StylePreset] = [
    StylePreset(sid: "standard", name: "标准", t: 0, c: 0, s: 100, cast: [1, 1, 1], ca: 0),
    StylePreset(sid: "pearl", name: "珠光", t: 18, c: 0, s: 100, cast: [1, 0.66, 0.76], ca: 0.28, fade: 0.02),
    StylePreset(sid: "coolrose", name: "冷调玫瑰色", t: -100, c: -100, s: 75, cast: [0.86, 0.7, 0.92], ca: 0.42),
    StylePreset(sid: "amber", name: "琥珀色", t: 20, c: 20, s: 100, cast: [1, 0.7, 0.3], ca: 0.55),
    StylePreset(sid: "gold", name: "金色", t: 20, c: 10, s: 85, cast: [1, 0.82, 0.3], ca: 0.5),
    StylePreset(sid: "rosegold", name: "玫瑰金色", t: -20, c: -20, s: 75, cast: [1, 0.72, 0.62], ca: 0.45),
    StylePreset(sid: "natural", name: "自然", t: -70, c: -15, s: 100, cast: [0.78, 0.84, 0.94], ca: 0.12),
    StylePreset(sid: "cozy", name: "温馨", t: -75, c: -20, s: 100, cast: [1, 0.72, 0.74], ca: 0.38),
    StylePreset(sid: "calm", name: "安静", t: 50, c: 45, s: 100, cast: [1, 0.9, 0.66], ca: 0.3),
    StylePreset(sid: "ethereal", name: "缥缈", t: 68, c: -15, s: 100, cast: [0.72, 0.78, 1], ca: 0.2, fade: 0.06),
    StylePreset(sid: "contrast", name: "反差色", t: -76, c: 19, s: 100, cast: [0.55, 0.82, 0.96], ca: 0.22, con: 0.28),
    StylePreset(sid: "radiant", name: "耀目", t: 35, c: 30, s: 100, cast: [0.88, 0.78, 1], ca: 0.22),
    StylePreset(sid: "vivid", name: "鲜明", t: -30, c: 33, s: 100, cast: [1, 1, 1], ca: 0, con: 0.16)
]

/// 调色状态：预设 + 调色盘落点（x = 颜色，y = 色调，-1…1）+ 强度（0…1）+ 质感 + 颗粒。线程安全（预览线程读、界面线程写）。
final class GradeState {
    private let lock = NSLock()
    private var _preset = 0
    private var _x = 0.0, _y = 0.0, _str = 1.0
    private var _contrast = 0.0, _clarity = 0.0, _sharp = 0.0      // 质感
    private var _grainAmt = 0.0, _grainSize = 0.3                  // 颗粒

    struct Snapshot {
        var preset: StylePreset
        var x: Double, y: Double, str: Double
        var contrast: Double, clarity: Double, sharp: Double
        var grainAmt: Double, grainSize: Double
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(preset: stylePresets[_preset], x: _x, y: _y, str: _str, contrast: _contrast, clarity: _clarity,
                        sharp: _sharp, grainAmt: _grainAmt, grainSize: _grainSize)
    }

    var presetIndex: Int { lock.lock(); defer { lock.unlock() }; return _preset }

    func selectPreset(_ i: Int) {
        lock.lock(); defer { lock.unlock() }
        _preset = max(0, min(stylePresets.count - 1, i))
        let p = stylePresets[_preset]
        _x = p.c / 100; _y = p.t / 100; _str = p.s / 100
    }
    func setPad(x: Double, y: Double) { lock.lock(); _x = max(-1, min(1, x)); _y = max(-1, min(1, y)); lock.unlock() }
    func setStrength(_ v: Double) { lock.lock(); _str = max(0, min(1, v)); lock.unlock() }
    func setTexture(contrast: Double? = nil, clarity: Double? = nil, sharp: Double? = nil) {
        lock.lock()
        if let v = contrast { _contrast = max(-1, min(1, v)) }
        if let v = clarity { _clarity = max(0, min(1, v)) }
        if let v = sharp { _sharp = max(0, min(1, v)) }
        lock.unlock()
    }
    func setGrain(amount: Double? = nil, size: Double? = nil) {
        lock.lock()
        if let v = amount { _grainAmt = max(0, min(1, v)) }
        if let v = size { _grainSize = max(0, min(1, v)) }
        lock.unlock()
    }
    func reset() {
        lock.lock(); _preset = 0; _x = 0; _y = 0; _str = 1; _contrast = 0; _clarity = 0; _sharp = 0; _grainAmt = 0; _grainSize = 0.3; lock.unlock()
    }

    var isNeutral: Bool {
        let s = snapshot()
        let p = s.preset
        let amt = abs(p.ca * s.str), tone = abs(s.y * s.str * 0.6), sat = abs(s.x * s.str * 0.8), con = abs(p.con * s.str), fade = p.fade * s.str
        return amt + tone + sat + con + fade < 0.004 && abs(s.contrast) + s.clarity + s.sharp + s.grainAmt < 0.004
    }

    // MARK: 应用到画面（把主页面着色器的算法折算成 CoreImage 滤镜链）

    func apply(_ input: CIImage) -> CIImage {
        let s = snapshot()
        let p = s.preset
        var img = input
        let ext = input.extent
        let amt = p.ca * s.str, tone = s.y * s.str * 0.6, sat = s.x * s.str * 0.8, con = p.con * s.str, fade = p.fade * s.str

        // 1. 色偏：给中间调加一点「预设的颜色」
        if amt > 0.002 {
            let l = 0.2126 * p.cast[0] + 0.7152 * p.cast[1] + 0.0722 * p.cast[2]
            let k = amt * 0.3
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: CGFloat((p.cast[0] - l) * k), y: CGFloat((p.cast[1] - l) * k), z: CGFloat((p.cast[2] - l) * k), w: 0)])
        }
        // 2. 色调：整体明暗曲线
        if abs(tone) > 0.002 {
            img = img.applyingFilter("CIGammaAdjust", parameters: ["inputPower": pow(2.0, -tone * 0.55)])
        }
        // 3. 对比 + 4. 饱和（预设对比、色调带来的对比、质感里的对比叠加）
        var cc = con + max(-tone, 0) * 0.35 + s.contrast * 0.6
        cc = max(-1, min(1, cc))
        let contrast = cc >= 0 ? 1 + cc * 0.8 : 1 + cc * 0.7
        let satur = sat > 0 ? 1 + sat * 0.7 : 1 + sat * 0.95
        if abs(contrast - 1) > 0.002 || abs(satur - 1) > 0.002 {
            img = img.applyingFilter("CIColorControls", parameters: ["inputContrast": contrast, "inputSaturation": max(0, satur), "inputBrightness": 0])
        }
        // 5. 褪色（抬黑）
        if fade > 0.002 {
            img = img.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: CGFloat(1 - fade), y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: CGFloat(1 - fade), z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: CGFloat(1 - fade), w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: CGFloat(fade), y: CGFloat(fade), z: CGFloat(fade), w: 0)])
        }
        // 6. 质感：清晰度（大半径反锐化）+ 锐度（小半径）
        let scale = max(ext.width, ext.height) / 1000
        if s.clarity > 0.01 {
            img = img.applyingFilter("CIUnsharpMask", parameters: ["inputRadius": 18 * scale, "inputIntensity": s.clarity * 0.9])
        }
        if s.sharp > 0.01 {
            img = img.applyingFilter("CIUnsharpMask", parameters: ["inputRadius": 2.2 * scale, "inputIntensity": s.sharp * 1.4])
        }
        // 7. 颗粒：随机噪点按柔光叠上去
        if s.grainAmt > 0.01, let noise = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let k = CGFloat(1 + s.grainSize * 2.5) * max(1, scale)
            let off = CGAffineTransform(translationX: CGFloat.random(in: 0...400), y: CGFloat.random(in: 0...400))
            var g = noise.transformed(by: off).transformed(by: CGAffineTransform(scaleX: k, y: k))
                .applyingFilter("CIColorControls", parameters: ["inputSaturation": 0])
            let a = CGFloat(s.grainAmt * 0.9)
            g = g.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: a, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: a, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: a, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: 0.5 * (1 - a), y: 0.5 * (1 - a), z: 0.5 * (1 - a), w: 0)]).cropped(to: ext)
            img = g.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: ext)
            // CISoftLightBlendMode：输入是前景（噪点），背景是画面
            img = img.cropped(to: ext)
        }
        return img.cropped(to: ext)
    }
}
