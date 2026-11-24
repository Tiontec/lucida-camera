import UIKit

// 灵动岛样式（设置 →「灵动岛样式」，iOS 专用，安卓不显示）
//   none  = 无：不画岛，录制时只显示计时胶囊
//   pro17 = iPhone 17 Pro：标准宽度（默认）
//   pro18 = iPhone 18 Pro：更小，宽度 = 标准宽 × 0.75（约缩小 25%）
// 只提供样式和宽度；相机界面里怎么排版由 A 接入（见 CHANGES.md「给 A 的接口」）。

enum DualIslandStyle { case none, pro17, pro18 }

/// 17 Pro 的标准岛宽（pt）。暂用 126，A 接线时请按实机测量后校准。
let dualIslandStandardWidth: CGFloat = 126

/// 当前灵动岛样式（读设置键 island："0" 无 / "17" 或其它 = 17 Pro / "18" = 18 Pro）
var dualIslandStyle: DualIslandStyle {
    switch SettingsStore.get("island") {
    case "0": return .none
    case "18": return .pro18
    default: return .pro17
    }
}

/// 岛的宽度（pt）。「无」返回 0
func dualIslandWidth(_ style: DualIslandStyle) -> CGFloat {
    switch style {
    case .none: return 0
    case .pro17: return dualIslandStandardWidth
    case .pro18: return dualIslandStandardWidth * 0.75
    }
}

/// 是否要画岛本身。「无」档只显示录制计时胶囊
var dualIslandShowsShape: Bool { dualIslandStyle != .none }
