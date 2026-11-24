import UIKit

// 面板样式（设置 →「界面与外观 → 面板样式」）
//   glass = 默认：跟随「界面风格」（毛玻璃 / 液态玻璃）
//   dark  = 黑色面板 UI：纯色底，去掉玻璃和模糊
//   light = 白色面板 UI：纯白底，深色字，去掉玻璃和模糊
// 设置页自己的卡片、文字、页面底色都从 PanelPalette 取，不写死颜色。
// 相机界面的面板（A 的文件）要跟着变：见 CHANGES.md「给 A 的接口」。

enum DualPanelTheme { case glass, dark, light }

/// 当前面板样式（读设置键 panelTheme）
var dualPanelTheme: DualPanelTheme {
    switch SettingsStore.get("panelTheme") {
    case "dark": return .dark
    case "light": return .light
    default: return .glass
    }
}

enum PanelPalette {
    static var isLight: Bool { dualPanelTheme == .light }
    /// 纯色面板的底色（卡片 / 面板）
    static var surface: UIColor { isLight ? .white : UIColor(white: 0.10, alpha: 1) }
    /// 页面底色
    static var pageBg: UIColor { isLight ? UIColor(white: 0.93, alpha: 1) : .black }
    static var text: UIColor { isLight ? UIColor(white: 0.08, alpha: 1) : .white }
    static var sub: UIColor { isLight ? UIColor(white: 0.08, alpha: 0.60) : UIColor(white: 1, alpha: 0.50) }
    static var note: UIColor { isLight ? UIColor(white: 0.08, alpha: 0.50) : UIColor(white: 1, alpha: 0.45) }
    static var value: UIColor { isLight ? UIColor(white: 0.08, alpha: 0.55) : UIColor(white: 1, alpha: 0.55) }
    static var chevron: UIColor { isLight ? UIColor(white: 0.08, alpha: 0.35) : UIColor(white: 1, alpha: 0.50) }
    static var divider: UIColor { isLight ? UIColor(white: 0, alpha: 0.10) : UIColor(white: 1, alpha: 0.10) }
    static var hover: UIColor { isLight ? UIColor(white: 0, alpha: 0.05) : UIColor(white: 1, alpha: 0.08) }
    /// 危险操作（清空日志）和错误级别的红色
    static var danger: UIColor { isLight ? UIColor(red: 0.80, green: 0.18, blue: 0.16, alpha: 1) : UIColor(red: 1, green: 0.38, blue: 0.36, alpha: 1) }

    /// 给面板 / 卡片垫底。玻璃模式交给 DualBackdrop（玻璃 / 毛玻璃，glassAllowed 为 false 时平面）；纯色模式直接用 surface
    static func paintSurface(_ b: DualBackdrop, glassAllowed: Bool) {
        if dualPanelTheme == .glass {
            b.apply(glass: glassAllowed, flat: UIColor(white: 1, alpha: 0.08))
        } else {
            b.apply(glass: false, flat: surface)
        }
    }
}
