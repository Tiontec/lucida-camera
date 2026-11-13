import UIKit
import WebKit

/// 键盘弹出时让网页（WKWebView）原地不动。
/// WKWebView 在输入框获得焦点时，会自己改 scrollView 的 contentInset / contentOffset，把输入框「居中」顶上来，
/// 登录页顶部的验证码数字条因此被顶出屏幕。这里：
///   ① 键盘显示期间（以及收起后 1 秒内）把 contentInset / contentOffset 钉在 0，
///   ② 量出键盘盖住了网页底部多少，通过 window.__lucidaKb(CSS 像素) 告诉网页，
///      网页再决定只把「当前输入的那一行」往上抬（见 网页 kbpin 模块）。
final class KeyboardPin: NSObject {
    private weak var web: WKWebView?
    private var observers: [NSKeyValueObservation] = []
    private(set) var height: CGFloat = 0
    private var graceUntil: CFTimeInterval = 0
    private var fixing = false
    /// (键盘遮住网页底部的高度（点 = CSS 像素）, 动画时长)
    var onHeight: ((CGFloat, TimeInterval) -> Void)?

    func attach(to web: WKWebView) {
        self.web = web
        let sv = web.scrollView
        observers.append(sv.observe(\.contentOffset, options: [.new]) { [weak self] _, _ in self?.normalize() })
        observers.append(sv.observe(\.contentInset, options: [.new]) { [weak self] _, _ in self?.normalize() })
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(frameChanged(_:)),
                       name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        nc.addObserver(self, selector: #selector(willHide(_:)),
                       name: UIResponder.keyboardWillHideNotification, object: nil)
        nc.addObserver(self, selector: #selector(didShow(_:)),
                       name: UIResponder.keyboardDidShowNotification, object: nil)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func normalize() {
        guard !fixing, let sv = web?.scrollView else { return }
        guard height > 0 || CACurrentMediaTime() < graceUntil else { return }
        fixing = true
        defer { fixing = false }
        if sv.contentInset != .zero { sv.contentInset = .zero }
        if sv.scrollIndicatorInsets != .zero { sv.scrollIndicatorInsets = .zero }
        if sv.contentOffset != .zero { sv.setContentOffset(.zero, animated: false) }
    }

    @objc private func frameChanged(_ n: Notification) {
        guard let web = web, let win = web.window,
              let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let dur = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        let inWin = win.convert(end, from: nil)
        let inWeb = web.convert(inWin, from: win)
        let hit = web.bounds.intersection(inWeb)
        // 只处理停靠在屏幕底部的键盘；浮动 / 分离的 iPad 键盘不挡网页
        let docked = inWin.maxY >= win.bounds.height - 1
        apply((docked && !hit.isNull) ? hit.height : 0, dur)
    }

    @objc private func willHide(_ n: Notification) {
        let dur = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        apply(0, dur)
    }

    @objc private func didShow(_ n: Notification) { normalize() }

    private func apply(_ h: CGFloat, _ dur: TimeInterval) {
        height = h
        graceUntil = CACurrentMediaTime() + 1.0
        normalize()
        onHeight?(h, dur)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05) { [weak self] in self?.normalize() }
    }
}
