import Foundation

// 设置注册表：描述「设置主页」里每个集合、每一项（类型 / 选项 / 范围 / 默认值 / 状态）。
// 内容由 tools/gen_settings.py 生成到 SettingsData.swift（安卓同一份数据生成 SettingsData.java，两端永远一致）。
// 以后某项接线完成：只改 gen_settings.py 里它的 status（soon → live）重新生成即可。

/// 设置项类型：开关 / 分段 / 链接（进新页面）/ 单选列表 / 滑块 / 纯文字
enum SType { case toggle, seg, link, radio, slider, info }
/// live = 能用（读写真实设置）；soon = 灰色，点击提示「不可用」
enum SStatus { case live, soon }
/// 作用范围：双摄 / 单摄 / 两者
enum SScope { case dual, single, both }
/// inline = 直接在设置主页里展开（黄色小标题 + 卡片）；page = 主页上只有一行入口，点开进新页面
enum SKind { case inline, page }

struct SOption {
    let v: String        // 存储值
    let title: String    // 选项标题
    let sub: String      // 说明文字
    let short: String    // 设置行右侧显示的简短当前值
    var soon: Bool = false   // true = 这个选项灰色，点击提示「不可用」，不会被选中（如「液态玻璃」）
}

struct SItem {
    let id: String
    let title: String
    let sub: String
    let type: SType
    let scope: SScope
    var status: SStatus
    let def: String          // 默认值（开关 "1"/"0"，其余是选项的 v 或数字）
    let options: [SOption]
    let notes: [String]      // 选项页底部的说明段落
    let dest: String         // link 的目标：order / cams / donate / log / version / about
    let inline: Bool         // radio：直接在页内展开（带说明、右侧对勾），否则主页只显示一行 + 当前值，点开进选项页
    let reconfigure: Bool    // 改了之后需要重新配置摄像头
    let icon: String         // SF Symbol 名（安卓用同名映射到自绘图标）
    let min: Int, max: Int   // slider 范围
}

struct SGroup {
    let head: String        // 卡片上方的灰色小标题
    let foot: String        // 卡片下方的灰色说明
    var items: [SItem]
}

struct SCollection {
    let id: String
    let title: String
    let kind: SKind
    let summary: String      // page 型集合在主页入口行右侧显示的简述
    let intro: String        // 集合页顶部的说明
    let icon: String
    var groups: [SGroup]
}

enum SettingsRegistry {
    /// 设置主页的集合顺序
    static let collections: [SCollection] = SettingsRegistry.buildAll()

    static let soonToast = "不可用"            // 设置里灰色项被点击
    static let panelSoonToast = "未加入此功能"   // 多功能面板里灰色按钮被点击

    private static let index: [String: SItem] = {
        var d: [String: SItem] = [:]
        for c in collections { for g in c.groups { for i in g.items { d[i.id] = i } } }
        return d
    }()

    static func item(_ id: String) -> SItem? { index[id] }
    static func collection(_ id: String) -> SCollection? { collections.first { $0.id == id } }

    /// 文案里的占位符：{version} = 当前版本号
    static func resolve(_ s: String) -> String {
        s.replacingOccurrences(of: "{version}", with: AppInfo.version)
    }

    /// 选项在列表里的位置（当前值找不到就当第一项）
    static func selectedIndex(_ it: SItem) -> Int {
        let v = SettingsStore.get(it.id)
        return it.options.firstIndex { $0.v == v } ?? 0
    }

    /// 设置行右侧显示的当前值（开关、普通链接返回空串）
    static func rowValue(_ it: SItem) -> String {
        switch it.type {
        case .seg, .radio:
            if it.options.isEmpty { return "" }
            return it.options[selectedIndex(it)].short
        case .slider: return SettingsStore.get(it.id) + "%"
        case .link:   return it.sub.hasPrefix("{") ? resolve(it.sub) : ""   // 如「版本更新」右侧显示 {version}
        default:      return ""
        }
    }

    /// 设置行标题下方的说明文字（占位符型的 sub 是右侧值，不算说明）
    static func subtitle(_ it: SItem) -> String { it.sub.hasPrefix("{") ? "" : it.sub }
}
