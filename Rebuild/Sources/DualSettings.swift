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
    var mirror: Bool { get { d.object(forKey: key("mirror2")) as? Bool ?? false } set { d.set(newValue, forKey: key("mirror2")) } }
    var audio: Bool { get { d.object(forKey: key("audio")) as? Bool ?? true } set { d.set(newValue, forKey: key("audio")) } }
    var pipStyleSplit: Bool { get { d.bool(forKey: key("split")) } set { d.set(newValue, forKey: key("split")) } }
    /// 双摄开关（默认关）。关 = 单摄；开 = 前后摄像头同时工作（设备不支持时开不了）
    var dualOn: Bool { get { d.object(forKey: key("dualOn")) as? Bool ?? false } set { d.set(newValue, forKey: key("dualOn")) } }
    /// 单摄时用前置摄像头
    var singleFront: Bool { get { d.bool(forKey: key("singleFront")) } set { d.set(newValue, forKey: key("singleFront")) } }
    var backIsMain: Bool { get { d.object(forKey: key("backMain")) as? Bool ?? true } set { d.set(newValue, forKey: key("backMain")) } }

    /// 满帧画面运行录制：开 = 不因设备发烫自动降帧，预览和录制都按所选帧率；关 = 发烫时自动降到 30 帧并减半取景渲染，保证录完的视频流畅
    var fullRate: Bool { get { d.bool(forKey: key("fullRate")) } set { d.set(newValue, forKey: key("fullRate")) } }

    /// 画幅比例（竖屏取景）：16:9（铺满，默认）/ 4:3 / 1:1。「片门全开」开着时固定 3:4，不受这项影响
    var ratio: String {
        get { let v = d.string(forKey: key("ratio")) ?? ""; return ["16:9", "4:3", "1:1"].contains(v) ? v : "16:9" }
        set { d.set(newValue, forKey: key("ratio")) }
    }

    /// 拍照闪光灯：0 关 / 1 自动（暗处才闪）/ 2 开。后置用手电筒补光，前置用屏幕补光
    var flashMode: Int {
        get { let v = d.integer(forKey: key("flashMode")); return (0...2).contains(v) ? v : 0 }
        set { d.set(newValue, forKey: key("flashMode")) }
    }

    /// 取景网格线（三分线）
    var gridLines: Bool { get { d.bool(forKey: key("grid")) } set { d.set(newValue, forKey: key("grid")) } }
    /// 水平仪
    /// 多功能面板按钮顺序（逗号分隔的 PanelItem.id）；空 = 出厂顺序
    var panelOrder: [String] { get { (d.string(forKey: key("panelOrder")) ?? "").split(separator: ",").map(String.init) } set { d.set(newValue.joined(separator: ","), forKey: key("panelOrder")) } }
    /// 倒计时每秒震动一下（默认开）
    var countVibrate: Bool { get { d.object(forKey: key("countVibrate")) as? Bool ?? true } set { d.set(newValue, forKey: key("countVibrate")) } }
    var level: Bool { get { d.bool(forKey: key("level")) } set { d.set(newValue, forKey: key("level")) } }
    /// 倒计时拍摄：0 关 / 3 / 5 / 10 秒（拍照、录像、实况都适用）
    var timerSec: Int {
        get { let v = d.integer(forKey: key("timerSec")); return [0, 3, 5, 10].contains(v) ? v : 0 }
        set { d.set(newValue, forKey: key("timerSec")) }
    }

    var liveTimer: Bool { get { d.object(forKey: key("liveTimer")) as? Bool ?? true } set { d.set(newValue, forKey: key("liveTimer")) } }

    /// 前后摄像头各一套调色
    let gradeBack = GradeState(storeKey: "lucida.dual2.gradeBack")
    let gradeFront = GradeState(storeKey: "lucida.dual2.gradeFront")
    /// 调色盘正在改谁：0 后置 / 1 前置 / 2 同时
    var gradeTarget = 2
}

// MARK: - 调色（和主页面「调色板 / 质感 / 颗粒」同一套预设和参数）

// 预设（StylePreset / stylePresets）和质感系数（SharedGrade / texNames）在 SharedData.swift，由 shared/lucida-shared.json 生成，和网页 / 安卓共用。

// MARK: - 预设顺序（和主页面「调色盘预设顺序」同一套：可拖动调整，「标准」始终排第一）

enum PresetOrder {
    /// 和主页面同一个存档键：网页写的原生能读，原生写的网页也能读（长期计划 A2）
    private static let key = "lucida.order2", oldKey = "lucida.dual2.presetOrder"
    private static var all: [String] { stylePresets.map { $0.sid } }
    private static func valid(_ o: [String]) -> Bool { o.count == all.count && Set(o) == Set(all) }
    private static func json(_ o: [String]) -> String {
        (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }
    static var sids: [String] {
        get {
            if let s = NativeKV.shared.get(key), let d = s.data(using: .utf8),
               let o = (try? JSONSerialization.jsonObject(with: d)) as? [String], valid(o) { return pinStandard(o) }
            // 迁移：11.2.x 的双摄自己存过一份，网页还没存过时沿用它
            if let o = UserDefaults.standard.array(forKey: oldKey) as? [String], valid(o) {
                let p = pinStandard(o); NativeKV.shared.setNative(key, json(p)); UserDefaults.standard.removeObject(forKey: oldKey); return p
            }
            return all
        }
        set { NativeKV.shared.setNative(key, json(pinStandard(newValue))) }
    }
    private static func pinStandard(_ o: [String]) -> [String] {
        var r = o
        if let i = r.firstIndex(of: "standard"), i > 0 { r.remove(at: i); r.insert("standard", at: 0) }
        return r
    }
    static func reset() { NativeKV.shared.setNative(key, json(all)) }
    /// 按顺序排好的预设下标（指向 stylePresets）
    static var indices: [Int] { sids.compactMap { sid in stylePresets.firstIndex { $0.sid == sid } } }
}

// MARK: - 质感 / 颗粒（和主页面 texParams 一模一样：标准 / 柔肤 / 光晕 / 胶片 + 强度，颗粒单独一条）

struct FilterParams {
    var con = 0.0, sat = 0.0, hi = 0.0, sh = 0.0, tmp = 0.0, cl = 0.0, sp = 0.0, gr = 0.0, hal = 0.0
    var tint = [0.0, 0.0, 0.0], shd = [0.0, 0.0, 0.0]
}

func texParams(tex: Int, tv: Double, gr: Double) -> FilterParams? {
    let on = tv > SharedGrade.texOn
    if !on && gr < SharedGrade.grainOn { return nil }
    var o = FilterParams()
    if on {
        let ti = max(0, min(SharedGrade.texCoef.count - 1, tex)), k = SharedGrade.texCoef[ti], d = SharedGrade.texShd[ti]
        // 列顺序见 SharedGrade.texKeys：con sat hi sh tmp cl sp gr hal
        o.con = k[0] * tv; o.sat = k[1] * tv; o.hi = k[2] * tv; o.sh = k[3] * tv; o.tmp = k[4] * tv
        o.cl = k[5] * tv; o.sp = k[6] * tv; o.gr = k[7] * tv; o.hal = k[8] * tv
        o.shd = [d[0] * tv, d[1] * tv, d[2] * tv]
    }
    o.gr += gr * SharedGrade.grainK
    return o
}

/// 逐像素的颜色运算：把主页面着色器（色偏 → 色调 → 对比 → 褪色 → 带肤色保护的自然饱和度 → 滤镜影调）照抄一遍，
/// 做成 3D 色彩查找表交给 CoreImage（CIColorCube），这样原生双摄的颜色和主页面一致。
struct GradeMath {
    var tnt = [1.0, 1.0, 1.0]
    var amt = 0.0, tone = 0.0, sat = 0.0, con = 0.0, fade = 0.0
    var fp: FilterParams?

    private func sstep(_ a: Double, _ b: Double, _ x: Double) -> Double { let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }
    private func lum(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
    private func cl(_ v: Double) -> Double { max(0, min(1, v)) }

    func shade(_ r0: Double, _ g0: Double, _ b0: Double, pw: Double) -> (Double, Double, Double) {
        var r = r0, g = g0, b = b0
        var y = lum(r, g, b)
        let mx = max(r, max(g, b)), mn = min(r, min(g, b)), ch = mx - mn, sn = ch / (mx + 1e-4)
        var h = 0.0
        if ch > 1e-4 {
            if mx == r { h = ((g - b) / ch).truncatingRemainder(dividingBy: 6); if h < 0 { h += 6 } }
            else if mx == g { h = (b - r) / ch + 2 } else { h = (r - g) / ch + 4 }
            h /= 6
            if h > 0.9 { h -= 1 }
        }
        let skin = sstep(-0.01, 0.03, h) * (1 - sstep(0.10, 0.15, h)) * sstep(0.08, 0.22, sn) * (1 - sstep(0.6, 0.8, sn))
        let mid = 4 * y * (1 - y)
        let tl = lum(tnt[0], tnt[1], tnt[2])
        let k = amt * 0.5 * (0.35 + 0.65 * mid) * (1 - 0.5 * skin)
        r = cl(r + (tnt[0] - tl) * k); g = cl(g + (tnt[1] - tl) * k); b = cl(b + (tnt[2] - tl) * k)
        r = pow(r, pw); g = pow(g, pw); b = pow(b, pw)
        let cc = con + max(-tone, 0) * 0.35
        func curve(_ v: Double) -> Double {
            if cc >= 0 { let s = v * v * (3 - 2 * v); let t = max(0, min(1, cc)); return v + (s - v) * t }
            return 0.5 + (v - 0.5) * (1 + cc * 0.7)
        }
        r = curve(r); g = curve(g); b = curve(b)
        r = fade + r * (1 - fade); g = fade + g * (1 - fade); b = fade + b * (1 - fade)
        y = lum(r, g, b)
        let m2 = max(r, max(g, b)), n2 = min(r, min(g, b)), s2 = (m2 - n2) / (m2 + 1e-4)
        let prot = (1 - 0.45 * skin) * (1 - sstep(0.82, 1, y)) * sstep(0, 0.12, y)
        let a2 = sat > 0 ? 1 + sat * 0.95 * (1 - 0.55 * s2) * prot : 1 + sat * 0.95
        r = cl(y + (r - y) * a2); g = cl(y + (g - y) * a2); b = cl(y + (b - y) * a2)
        if let f = fp {
            let yy = lum(r, g, b), wH = sstep(0.45, 1, yy), wS = 1 - sstep(0, 0.55, yy)
            let kh = 1 + f.hi * 0.5 * wH, ks = 1 + f.sh * 0.8 * wS
            r *= kh * ks; g *= kh * ks; b *= kh * ks
            r *= 1 + f.tmp * 0.5; b *= 1 - f.tmp * 0.5
            r += f.tint[0] + f.shd[0] * wS; g += f.tint[1] + f.shd[1] * wS; b += f.tint[2] + f.shd[2] * wS
            let kc = 1 + f.con * 0.8
            r = 0.5 + (r - 0.5) * kc; g = 0.5 + (g - 0.5) * kc; b = 0.5 + (b - 0.5) * kc
            let y2 = lum(r, g, b), ksat = 1 + f.sat
            r = cl(y2 + (r - y2) * ksat); g = cl(y2 + (g - y2) * ksat); b = cl(y2 + (b - y2) * ksat)
        }
        return (cl(r), cl(g), cl(b))
    }

    static let dim = 33

    func makeCube() -> Data {
        let n = GradeMath.dim
        var out = [Float](repeating: 1, count: n * n * n * 4)
        let pw = pow(2.0, -tone * 0.55)
        var i = 0
        let d = Double(n - 1)
        for bi in 0..<n {
            for gi in 0..<n {
                for ri in 0..<n {
                    let (r, g, b) = shade(Double(ri) / d, Double(gi) / d, Double(bi) / d, pw: pw)
                    out[i] = Float(r); out[i + 1] = Float(g); out[i + 2] = Float(b); out[i + 3] = 1
                    i += 4
                }
            }
        }
        return out.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}

/// 调色状态：预设 + 调色盘落点（x = 颜色，y = 色调，-1…1）+ 强度（0…1）+ 质感（4 种风格各自的强度）+ 颗粒。
/// 线程安全（预览线程读、界面线程写）。
final class GradeState {
    private let lock = NSLock()
    private var _preset = 0
    private var _x = 0.0, _y = 0.0, _str = 1.0
    private var _tex = 0, _tv = 0.0, _tvm = [0.0, 0.0, 0.0, 0.0]      // 质感风格 / 强度 / 各风格各自的强度
    private var _gr = 0.0                                              // 颗粒
    private var version = 0
    private var cubeKey = -1, cube: Data?
    private var cubeBusy = false
    private let cubeQueue = DispatchQueue(label: "lucida.grade.cube", qos: .userInitiated)
    private let storeKey: String?
    private var saveWork: DispatchWorkItem?

    init(storeKey: String? = nil) {
        self.storeKey = storeKey
        if let k = storeKey, let d = UserDefaults.standard.dictionary(forKey: k) {
            _preset = max(0, min(stylePresets.count - 1, (d["p"] as? Int) ?? 0))
            _x = max(-1, min(1, (d["x"] as? Double) ?? 0)); _y = max(-1, min(1, (d["y"] as? Double) ?? 0)); _str = max(0, min(1, (d["s"] as? Double) ?? 1))
            _tex = max(0, min(3, (d["t"] as? Int) ?? 0)); _tv = max(0, min(1, (d["tv"] as? Double) ?? 0)); _gr = max(0, min(1, (d["gr"] as? Double) ?? 0))
            if let m = d["tvm"] as? [Double], m.count == 4 { _tvm = m }
        }
    }

    struct Snapshot {
        var preset: StylePreset, presetIndex: Int
        var x: Double, y: Double, str: Double
        var tex: Int, tv: Double, tvm: [Double]
        var gr: Double
    }

    func snapshot() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        return Snapshot(preset: stylePresets[_preset], presetIndex: _preset, x: _x, y: _y, str: _str, tex: _tex, tv: _tv, tvm: _tvm, gr: _gr)
    }

    var presetIndex: Int { lock.lock(); defer { lock.unlock() }; return _preset }

    private func touched() {
        version += 1
        guard let k = storeKey else { return }
        saveWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            let s = self.snapshot()
            UserDefaults.standard.set(["p": s.presetIndex, "x": s.x, "y": s.y, "s": s.str, "t": s.tex, "tv": s.tv, "tvm": s.tvm, "gr": s.gr] as [String: Any], forKey: k)
        }
        saveWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: w)
    }

    /// 整套参数照抄另一个状态（「同时更改」时用）
    func copy(from o: GradeState) {
        let s = o.snapshot()
        lock.lock()
        _preset = s.presetIndex; _x = s.x; _y = s.y; _str = s.str; _tex = s.tex; _tv = s.tv; _tvm = s.tvm; _gr = s.gr
        touched(); lock.unlock()
    }

    func selectPreset(_ i: Int) {
        lock.lock(); defer { lock.unlock() }
        _preset = max(0, min(stylePresets.count - 1, i))
        let p = stylePresets[_preset]
        _x = p.c / 100; _y = p.t / 100; _str = p.s / 100
        touched()
    }
    func setPad(x: Double, y: Double) { lock.lock(); _x = max(-1, min(1, x)); _y = max(-1, min(1, y)); touched(); lock.unlock() }
    func setStrength(_ v: Double) { lock.lock(); _str = max(0, min(1, v)); touched(); lock.unlock() }
    /// 切换质感风格：每种风格记住自己的强度
    func setTexStyle(_ t: Int) {
        lock.lock()
        _tvm[_tex] = _tv; _tex = max(0, min(3, t)); _tv = _tvm[_tex]
        touched(); lock.unlock()
    }
    func setTexStrength(_ v: Double) { lock.lock(); _tv = max(0, min(1, v)); _tvm[_tex] = _tv; touched(); lock.unlock() }
    func resetTexture() { lock.lock(); _tex = 0; _tv = 0; _tvm = [0, 0, 0, 0]; touched(); lock.unlock() }
    func setGrain(_ v: Double) { lock.lock(); _gr = max(0, min(1, v)); touched(); lock.unlock() }
    func reset() {
        lock.lock(); _preset = 0; _x = 0; _y = 0; _str = 1; _tex = 0; _tv = 0; _tvm = [0, 0, 0, 0]; _gr = 0; touched(); lock.unlock()
    }

    private func math(_ s: Snapshot) -> GradeMath {
        let p = s.preset
        return GradeMath(tnt: p.cast, amt: p.ca * s.str, tone: s.y * s.str * SharedGrade.toneK, sat: s.x * s.str * SharedGrade.satK, con: p.con * s.str, fade: p.fade * s.str * SharedGrade.fadeK,
                         fp: texParams(tex: s.tex, tv: s.tv, gr: s.gr))
    }

    var isNeutral: Bool {
        let s = snapshot(), m = math(s)
        let color = abs(m.amt) + abs(m.tone) + abs(m.sat) + abs(m.con) + m.fade
        return color < 0.004 && m.fp == nil
    }

    // MARK: 应用到画面（颜色部分 = 3D 查找表；质感里的锐化 / 柔化 / 光晕 / 颗粒是空间运算，用 CoreImage 滤镜）

    func apply(_ input: CIImage) -> CIImage {
        lock.lock()
        let s = Snapshot(preset: stylePresets[_preset], presetIndex: _preset, x: _x, y: _y, str: _str, tex: _tex, tv: _tv, tvm: _tvm, gr: _gr)
        let ver = version
        var data = cube
        let fresh = cubeKey == ver
        let busy = cubeBusy
        lock.unlock()
        let m = math(s)
        if !fresh {
            if data == nil {
                // 第一次：还没有旧表，只能当场算
                data = m.makeCube()
                lock.lock(); if cubeKey < ver { cube = data; cubeKey = ver }; lock.unlock()
            } else if !busy {
                // 拖动调色盘 / 滑块时：这一帧先沿用旧表，新表放到后台算（算一张 33³ 的表要十几毫秒，放在取景线程上会掉帧）
                lock.lock(); cubeBusy = true; lock.unlock()
                cubeQueue.async { [weak self] in
                    let d = m.makeCube()
                    guard let self = self else { return }
                    self.lock.lock()
                    if self.cubeKey < ver { self.cube = d; self.cubeKey = ver }
                    self.cubeBusy = false
                    self.lock.unlock()
                }
            }
        }
        let ext = input.extent
        var img = input
        let colorOn = abs(m.amt) + abs(m.tone) + abs(m.sat) + abs(m.con) + m.fade > 0.004 || m.fp != nil
        if colorOn, let d = data {
            img = img.applyingFilter("CIColorCube", parameters: ["inputCubeDimension": GradeMath.dim, "inputCubeData": d])
        }
        guard let f = m.fp else { return img.cropped(to: ext) }
        let px = max(1, min(ext.width, ext.height) / 1080)

        // 锐度 / 柔化（小半径）、清晰度（大半径）：正值反锐化，负值向模糊图靠拢
        func detail(_ v: Double, radius: CGFloat, boost: Double) {
            if v > 0.01 {
                img = img.applyingFilter("CIUnsharpMask", parameters: ["inputRadius": radius, "inputIntensity": v * boost])
            } else if v < -0.01 {
                let w = CGFloat(min(1, -v))
                let blur = img.clampedToExtent().applyingGaussianBlur(sigma: Double(radius)).cropped(to: ext)
                let faded = blur.applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: w)])
                img = faded.composited(over: img).cropped(to: ext)
            }
        }
        detail(f.sp, radius: 1.6 * px, boost: 1.0)
        detail(f.cl, radius: 6.5 * px, boost: 1.0)

        // 光晕：模糊后取亮部，染成偏暖的红橙色叠回去
        if f.hal > 0.01 {
            let blur = img.clampedToExtent().applyingGaussianBlur(sigma: Double(6.5 * px)).cropped(to: ext)
            let k = 2.2 * f.hal
            func row(_ w: Double) -> CIVector { CIVector(x: CGFloat(0.2126 * k * w), y: CGFloat(0.7152 * k * w), z: CGFloat(0.0722 * k * w), w: 0) }
            let glow = blur.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": row(1.0), "inputGVector": row(0.42), "inputBVector": row(0.3),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBiasVector": CIVector(x: CGFloat(-0.6 * k), y: CGFloat(-0.6 * k * 0.42), z: CGFloat(-0.6 * k * 0.3), w: 1)])
                .applyingFilter("CIColorClamp", parameters: ["inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0), "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)])
            img = glow.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: ext)
        }

        // 颗粒：随机噪点按柔光叠上去（强度 = 主页面的 gr 参数）
        if f.gr > 0.004, let noise = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let amp = CGFloat(min(1, f.gr * 3))
            let off = CGAffineTransform(translationX: CGFloat.random(in: 0...400), y: CGFloat.random(in: 0...400))
            var g = noise.transformed(by: off)
                .applyingFilter("CIColorMatrix", parameters: [
                    "inputRVector": CIVector(x: amp, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: amp, y: 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: amp, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                    "inputBiasVector": CIVector(x: 0.5 * (1 - amp), y: 0.5 * (1 - amp), z: 0.5 * (1 - amp), w: 0)])
            g = g.cropped(to: ext)
            img = g.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: img]).cropped(to: ext)
        }
        return img.cropped(to: ext)
    }
}
