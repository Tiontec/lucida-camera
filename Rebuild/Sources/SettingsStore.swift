import Foundation

/// 设置项的统一存取（按注册表里的 id）。值一律是字符串：开关 "1"/"0"，数字就是数字文字，单选就是选项的 v。
/// - 已有的真实设置（res / fps / glass / liveDur …）转到 DualSettings 的原属性；
/// - 新增的键（pipDragFps / sLiveDur / zoomRange …）存在 UserDefaults「lucida.dual2.<id>」，不改动 DualSettings.swift 本身。
/// 暂时不能用（soon）的项也已经定义好键和默认值，以后接线直接读 DualSettings 里的同名属性即可。
enum SettingsStore {
    private static let prefix = "lucida.dual2."
    private static func b(_ v: Bool) -> String { v ? "1" : "0" }

    /// 默认值（注册表里的 def；注册表没有的额外键看 extraDefaults）
    static func defaultValue(_ id: String) -> String {
        if let it = SettingsRegistry.item(id) { return it.def }
        for (k, d) in SettingsRegistry.extraDefaults where k == id { return d }
        return ""
    }

    /// 当前值是否合法（非法时 get 返回默认值）
    private static func valid(_ id: String, _ v: String) -> Bool {
        if let it = SettingsRegistry.item(id) {
            switch it.type {
            case .toggle: return v == "0" || v == "1"
            case .seg, .radio: return it.options.contains { $0.v == v }
            case .slider: if let n = Int(v) { return n >= it.min && n <= it.max } else { return false }
            default: return true
            }
        }
        return v == "0" || v == "1"
    }

    static func get(_ id: String) -> String {
        let s = DualSettings.shared
        switch id {
        // ── 已有的真实设置 ──
        case "res":        return String(s.res)
        case "fps":        return String(s.fps)
        case "heif":       return b(s.heif)
        case "full":       return b(s.fullSensor)
        case "border":
            switch s.border { case .none: return "0"; case .white: return "1"; case .black: return "2" }
        case "mirror":     return b(s.mirror)
        case "audio":      return b(s.audio)
        case "glass":      return b(s.glass)
        case "live":       return b(s.liveOn)
        case "liveDur":    return String(Int(s.liveDur))
        case "liveStill":  return b(s.liveAlsoStill)
        case "liveTimer":  return b(s.liveTimer)
        case "fullRate":   return b(s.fullRate)
        case "split":      return b(s.pipStyleSplit)
        case "dualOn":     return b(s.dualOn)
        case "singleFront": return b(s.singleFront)
        case "backMain":   return b(s.backIsMain)
        // ── A 在 1.3.0–1.5.0 新做的功能（键在 DualSettings 里已有）──
        case "ratio":      return s.ratio                    // "16:9" / "4:3" / "1:1"
        case "flash":      return String(s.flashMode)        // 0 关 / 1 自动 / 2 开
        case "timerSec":   return String(s.timerSec)         // 0 / 3 / 5 / 10
        case "grid":       return b(s.gridLines)
        case "level":      return b(s.level)
        case "countVibrate": return b(s.countVibrate)
        default: break
        }
        // 旧值 0（只存实况）/ 1（实况 + 静态照片）统一迁移为 pair（照片 + 视频）：两个旧值都不丢信息
        if id == "sLiveStill", let o = UserDefaults.standard.object(forKey: prefix + id), ["0", "1"].contains("\(o)") {
            return "pair"
        }
        // ── 新增的键 ──
        if id == "panelOrder" {
            return UserDefaults.standard.string(forKey: prefix + id) ?? ""
        }
        if let o = UserDefaults.standard.object(forKey: prefix + id) {
            let v = "\(o)"
            if valid(id, v) { return v }
        }
        // 没存过界面风格：按旧的「液态玻璃界面」开关推导（开 = 液态玻璃，关 = 默认面板），旧用户外观不变
        if id == "glassStyle" { return DualSettings.shared.glass ? "liquid" : "plain" }
        return defaultValue(id)
    }

    static func bool(_ id: String) -> Bool { get(id) == "1" }
    static func int(_ id: String) -> Int { Int(get(id)) ?? Int(defaultValue(id)) ?? 0 }

    static func set(_ id: String, _ v: String) {
        let s = DualSettings.shared
        switch id {
        case "res":        s.res = Int(v) ?? 1080
        case "fps":        s.fps = Int(v) ?? 30
        case "heif":       s.heif = v == "1"
        case "full":       s.fullSensor = v == "1"
        case "border":     s.border = v == "1" ? .white : (v == "2" ? .black : .none)
        case "mirror":     s.mirror = v == "1"
        case "audio":      s.audio = v == "1"
        case "glass":      s.glass = v == "1"
        case "live":       s.liveOn = v == "1"
        case "liveDur":    s.liveDur = Double(v) ?? 3
        case "liveStill":  s.liveAlsoStill = v == "1"
        case "liveTimer":  s.liveTimer = v == "1"
        case "fullRate":   s.fullRate = v == "1"
        case "split":      s.pipStyleSplit = v == "1"
        case "dualOn":     s.dualOn = v == "1"
        case "singleFront": s.singleFront = v == "1"
        case "backMain":   s.backIsMain = v == "1"
        case "ratio":      if ["16:9", "4:3", "1:1"].contains(v) { s.ratio = v }
        case "flash":      s.flashMode = Int(v) ?? 0
        case "timerSec":   s.timerSec = Int(v) ?? 0
        case "grid":       s.gridLines = v == "1"
        case "level":      s.level = v == "1"
        case "countVibrate": s.countVibrate = v == "1"
        case "panelOrder":
            // 面板按钮顺序：逗号分隔的 id，不是开关，不走 valid() 校验
            UserDefaults.standard.set(v, forKey: prefix + id)
        case "glassStyle":
            // 界面风格：毛玻璃 / 液态玻璃 = 开启玻璃；默认面板 = 关掉玻璃（同步到 glass，调用方照常读 glass）
            if valid(id, v) { UserDefaults.standard.set(v, forKey: prefix + id); DualSettings.shared.glass = (v != "plain") }
        default:
            if valid(id, v) { UserDefaults.standard.set(v, forKey: prefix + id) }
        }
    }
}

/// 新增设置键的类型化读写（Claude A 在内核里直接用：DualSettings.shared.pipDragFps 等）。
/// 都转到 SettingsStore，键名和注册表里的 id 一致。
extension DualSettings {
    /// 双摄小窗滑动帧率 30 / 60 / 120（默认 60）—— 由 A 接线
    var pipDragFps: Int { get { SettingsStore.int("pipDragFps") } set { SettingsStore.set("pipDragFps", String(newValue)) } }

    // 单摄的实况（和双摄的 liveDur / liveAlsoStill / liveTimer 各自独立）—— 由 A 接线
    var sLiveDur: Double { get { Double(SettingsStore.int("sLiveDur")) } set { SettingsStore.set("sLiveDur", String(Int(newValue))) } }
    /// 单摄实况保存方式：true = pair（照片 + 视频，默认）；false = native（只存实况，仅 iOS）。存的值是 "pair" / "native"
    var sLiveStill: Bool { get { SettingsStore.get("sLiveStill") == "pair" } set { SettingsStore.set("sLiveStill", newValue ? "pair" : "native") } }
    var sLiveTimer: Bool { get { SettingsStore.bool("sLiveTimer") } set { SettingsStore.set("sLiveTimer", newValue ? "1" : "0") } }
    var sLiveFps: Int { get { SettingsStore.int("sLiveFps") } set { SettingsStore.set("sLiveFps", String(newValue)) } }

    // 变焦与镜头（暂不可用，键已定义）
    var zoomSpeed: Int { get { SettingsStore.int("zoomSpeed") } set { SettingsStore.set("zoomSpeed", String(newValue)) } }
    var uwScale: String { get { SettingsStore.get("uwScale") } set { SettingsStore.set("uwScale", newValue) } }
    var teleScale: String { get { SettingsStore.get("teleScale") } set { SettingsStore.set("teleScale", newValue) } }
    var zoomFrame: String { get { SettingsStore.get("zoomFrame") } set { SettingsStore.set("zoomFrame", newValue) } }
    var lensSwitch: String { get { SettingsStore.get("lensSwitch") } set { SettingsStore.set("lensSwitch", newValue) } }
    var zoomRange: Int { get { SettingsStore.int("zoomRange") } set { SettingsStore.set("zoomRange", String(newValue)) } }

    // 其它（暂不可用，键已定义）
    var panoBlend: String { get { SettingsStore.get("panoBlend") } set { SettingsStore.set("panoBlend", newValue) } }
    var directRecord: Bool { get { SettingsStore.bool("direct") } set { SettingsStore.set("direct", newValue ? "1" : "0") } }
    var nativeSave: Bool { get { SettingsStore.bool("nativeSave") } set { SettingsStore.set("nativeSave", newValue ? "1" : "0") } }
    var skin: String { get { SettingsStore.get("skin") } set { SettingsStore.set("skin", newValue) } }
    var panelTheme: String { get { SettingsStore.get("panelTheme") } set { SettingsStore.set("panelTheme", newValue) } }
    var uiScale: Int { get { SettingsStore.int("uiScale") } set { SettingsStore.set("uiScale", String(newValue)) } }
    var fontScale: Int { get { SettingsStore.int("fontScale") } set { SettingsStore.set("fontScale", String(newValue)) } }
    var uiReset: Bool { get { SettingsStore.bool("uiReset") } set { SettingsStore.set("uiReset", newValue ? "1" : "0") } }
    var island: String { get { SettingsStore.get("island") } set { SettingsStore.set("island", newValue) } }
    var logOn: Bool { get { SettingsStore.bool("logOn") } set { SettingsStore.set("logOn", newValue ? "1" : "0") } }
    // countVibrate 由 DualSettings 主类自己定义（这里不能再写一遍，否则「invalid redeclaration」）
    /// 界面风格：frosted 毛玻璃（默认）/ liquid 液态玻璃（A 做完后接线；设置里这一项的「液态玻璃」现在灰色）
    var glassStyle: String { get { SettingsStore.get("glassStyle") } set { SettingsStore.set("glassStyle", newValue) } }
}
