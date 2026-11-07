import UIKit

/// 原生液态玻璃叠层（iOS 26+，需要 Xcode 26 编译）。
/// 网页把需要玻璃的控件矩形（药丸、顶部图标、设置面板、功能面板、变焦条……）报给原生，
/// 原生在网页上方铺一层 UIGlassEffect。叠层不接收触摸，点击仍然落在网页控件上。
/// 低于 iOS 26 或用旧版 Xcode 编译时，这里什么都不画（网页自己的玻璃样式照常使用）。
final class GlassOverlay {
    private let layerView = PassThroughView()
    private var views: [String: UIVisualEffectView] = [:]

    final class PassThroughView: UIView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? { nil }
    }

    func attach(to parent: UIView) {
        layerView.frame = parent.bounds
        layerView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        layerView.isUserInteractionEnabled = false
        layerView.backgroundColor = .clear
        parent.addSubview(layerView)
    }

    func layoutIfNeeded() { layerView.superview?.bringSubviewToFront(layerView) }

    private static func makeEffect() -> UIVisualEffect? {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) { return UIGlassEffect() }
        #endif
        return nil
    }

    func update(_ body: [String: Any]) {
        let on = (body["on"] as? Bool) ?? false
        let list = (body["surfaces"] as? [[String: Any]]) ?? []
        DispatchQueue.main.async { [weak self] in self?.apply(on: on, list: list) }
    }

    private func apply(on: Bool, list: [[String: Any]]) {
        guard on, GlassOverlay.makeEffect() != nil else {
            views.values.forEach { $0.removeFromSuperview() }; views.removeAll(); return
        }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        var seen = Set<String>()
        for s in list {
            guard let id = s["id"] as? String,
                  let x = (s["x"] as? NSNumber)?.doubleValue, let y = (s["y"] as? NSNumber)?.doubleValue,
                  let w = (s["w"] as? NSNumber)?.doubleValue, let h = (s["h"] as? NSNumber)?.doubleValue,
                  w > 1, h > 1 else { continue }
            seen.insert(id)
            let r = (s["radius"] as? NSNumber)?.doubleValue ?? 16
            let v: UIVisualEffectView
            if let e = views[id] { v = e }
            else {
                v = UIVisualEffectView(effect: GlassOverlay.makeEffect())
                v.isUserInteractionEnabled = false
                v.clipsToBounds = true
                v.layer.cornerCurve = .circular          // 与网页里的圆角一致（不用连续曲率）
                layerView.addSubview(v)
                views[id] = v
            }
            v.frame = CGRect(x: x, y: y, width: w, height: h)
            v.layer.cornerRadius = min(r, min(w, h) / 2)
        }
        for (id, v) in views where !seen.contains(id) { v.removeFromSuperview(); views[id] = nil }
        CATransaction.commit()
    }
}
