import UIKit

/// 多功能面板里一个按钮的描述
struct PanelItem {
    enum State { case enabled, soon }          // enabled = 正常可点；soon = 灰色，点击提示「未加入此功能」
    enum Action { case none, openPalette, toggleDual, openRatio, cycleFlash, cycleTimer }
    let id: String
    let title: String
    let symbols: [String]                       // SF Symbol 名，前面的优先，系统没有就用后面的（iOS 15 兼容）
    let state: State
    let action: Action
}

/// 多功能面板的按钮注册表：所有按钮的 id / 标题 / 图标 / 状态 / 点击动作都在这一个数组里。
/// 以后某个功能做好了：把它的 state 改成 .enabled，并在 FunctionsViewController.perform(_:) 里给它的 action 接上调用。
/// （安卓的 PanelRegistry.java 与这里一一对应：同样的 id、标题、顺序、状态。）
enum PanelRegistry {
    /// 面板按钮（3 列，从左到右、从上到下）
    static let items: [PanelItem] = [
        PanelItem(id: "filter", title: "滤镜影调", symbols: ["camera.filters", "circle.hexagongrid"], state: .soon, action: .none),
        PanelItem(id: "flash", title: "闪光灯", symbols: ["bolt.fill"], state: .enabled, action: .cycleFlash),
        PanelItem(id: "palette", title: "调色盘", symbols: ["circle.grid.3x3.fill", "square.grid.3x3.fill"], state: .enabled, action: .openPalette),
        PanelItem(id: "ratio", title: "比例", symbols: ["viewfinder", "aspectratio"], state: .enabled, action: .openRatio),
        PanelItem(id: "timer", title: "倒计时", symbols: ["timer"], state: .enabled, action: .cycleTimer),
        PanelItem(id: "pano", title: "360° 全景", symbols: ["globe"], state: .soon, action: .none),
        PanelItem(id: "dual", title: "前后双摄", symbols: ["rectangle.inset.filled.on.rectangle", "rectangle.on.rectangle"], state: .enabled, action: .toggleDual),
        PanelItem(id: "space", title: "空间重构", symbols: ["cube", "shippingbox"], state: .soon, action: .none),
        PanelItem(id: "skin", title: "皮肤", symbols: ["fish", "paintbrush"], state: .soon, action: .none),
        PanelItem(id: "aiext", title: "AI 扩图", symbols: ["wand.and.stars", "sparkles"], state: .soon, action: .none),
        PanelItem(id: "pro", title: "专业模式", symbols: ["dial.medium", "camera.aperture"], state: .soon, action: .none),
        PanelItem(id: "cine", title: "电影模式", symbols: ["film"], state: .soon, action: .none),
    ]

    /// 按用户排好的顺序返回按钮：存档里有的按存档排，新增的按钮追加在末尾，已经不存在的丢掉
    static func ordered() -> [PanelItem] {
        let saved = DualSettings.shared.panelOrder
        if saved.isEmpty { return items }
        var out: [PanelItem] = []
        for id in saved { if let it = items.first(where: { $0.id == id }), !out.contains(where: { $0.id == id }) { out.append(it) } }
        for it in items where !out.contains(where: { $0.id == it.id }) { out.append(it) }
        return out
    }

    /// 按顺序找系统里存在的第一个符号
    static func symbol(_ names: [String], size: CGFloat, weight: UIImage.SymbolWeight = .regular) -> UIImage? {
        let cfg = UIImage.SymbolConfiguration(pointSize: size, weight: weight)
        for n in names { if let i = UIImage(systemName: n, withConfiguration: cfg) { return i } }
        return nil
    }
}
