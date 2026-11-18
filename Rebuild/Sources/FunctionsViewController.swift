import UIKit

/// 多功能面板（相机底部快门旁的按键）：以后新增的功能开关、入口都放在这里。
/// 1.1.0：双摄开关 / 更多设置 / 调色盘预设顺序 / 关于。
final class FunctionsViewController: UIViewController {
    var onOpenSettings: (() -> Void)?
    /// 双摄开关：当前状态 / 请求切换（回调：最终状态，提示文字）
    var dualOn = false
    var onToggleDual: ((Bool, @escaping (Bool, String?) -> Void) -> Void)?
    private let dualSwitch = UISwitch()
    private let dualNote = UILabel()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.1, alpha: 1)
        overrideUserInterfaceStyle = .dark
        let title = UILabel(); title.text = "功能"; title.textColor = .white; title.font = .systemFont(ofSize: 18, weight: .semibold)
        let done = UIButton(type: .system); done.setTitle("完成", for: .normal); done.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        done.tintColor = dualYellow; done.addTarget(self, action: #selector(close), for: .touchUpInside)
        let scroll = UIScrollView()
        [title, done, scroll].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.topAnchor, constant: 20), title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            done.centerYAnchor.constraint(equalTo: title.centerYAnchor), done.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            scroll.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor), stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -30),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16), stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32)])
        addDual()
        addLink("更多设置", "实况、片门、小窗边框、镜像、录像声音、液态玻璃…") { [weak self] in
            self?.dismiss(animated: true) { self?.onOpenSettings?() } }
        addLink("调色盘预设顺序", "拖动调整预设的先后，「标准」固定在第一位") { [weak self] in
            let v = DualPresetOrderViewController(); v.modalPresentationStyle = .pageSheet; self?.present(v, animated: true) }
        addInfo("关于", "\(AppInfo.name) \(AppInfo.version)（\(AppInfo.build)）")
    }

    @objc private func close() { dismiss(animated: true) }

    private func addDual() {
        let c = UIView(); c.backgroundColor = UIColor(white: 1, alpha: 0.07); c.layer.cornerRadius = 18; c.layer.cornerCurve = .continuous
        let t = UILabel(); t.text = "双摄"; t.textColor = .white; t.font = .systemFont(ofSize: 16, weight: .semibold)
        dualNote.text = "前后摄像头同时拍摄（画中画 / 上下分屏）。默认关闭；设备不能同时开两颗摄像头时会自动退回单摄并提示。"
        dualNote.numberOfLines = 0; dualNote.textColor = UIColor(white: 1, alpha: 0.55); dualNote.font = .systemFont(ofSize: 12)
        let col = UIStackView(arrangedSubviews: [t, dualNote]); col.axis = .vertical; col.spacing = 3
        dualSwitch.isOn = dualOn; dualSwitch.onTintColor = dualYellow
        dualSwitch.addAction(UIAction { [weak self] _ in
            guard let self = self else { return }
            let want = self.dualSwitch.isOn
            self.dualSwitch.isEnabled = false
            self.dualNote.text = "正在切换…"
            self.onToggleDual?(want) { isOn, msg in
                self.dualSwitch.setOn(isOn, animated: true); self.dualSwitch.isEnabled = true
                self.dualNote.text = msg ?? (isOn ? "双摄已开启" : "双摄已关闭")
            }
        }, for: .valueChanged)
        col.translatesAutoresizingMaskIntoConstraints = false; dualSwitch.translatesAutoresizingMaskIntoConstraints = false
        c.addSubview(col); c.addSubview(dualSwitch)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: c.topAnchor, constant: 14), col.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -14),
            col.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 16), col.trailingAnchor.constraint(equalTo: dualSwitch.leadingAnchor, constant: -12),
            dualSwitch.centerYAnchor.constraint(equalTo: c.centerYAnchor), dualSwitch.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -16)])
        stack.addArrangedSubview(c)
    }

    private func card(_ title: String, _ sub: String?, chevron: Bool, tap: (() -> Void)?) {
        let c = UIControl(); c.backgroundColor = UIColor(white: 1, alpha: 0.07); c.layer.cornerRadius = 18; c.layer.cornerCurve = .continuous
        let t = UILabel(); t.text = title; t.textColor = .white; t.font = .systemFont(ofSize: 16, weight: .semibold)
        let col = UIStackView(arrangedSubviews: [t]); col.axis = .vertical; col.spacing = 3; col.isUserInteractionEnabled = false
        if let sub = sub { let s = UILabel(); s.text = sub; s.numberOfLines = 0; s.textColor = UIColor(white: 1, alpha: 0.55); s.font = .systemFont(ofSize: 12); col.addArrangedSubview(s) }
        col.translatesAutoresizingMaskIntoConstraints = false; c.addSubview(col)
        var trailing = c.trailingAnchor
        NSLayoutConstraint.activate([col.topAnchor.constraint(equalTo: c.topAnchor, constant: 14), col.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -14),
                                     col.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 16)])
        if chevron {
            let iv = UIImageView(image: UIImage(systemName: "chevron.right")); iv.tintColor = UIColor(white: 1, alpha: 0.4); iv.translatesAutoresizingMaskIntoConstraints = false
            c.addSubview(iv); iv.centerYAnchor.constraint(equalTo: c.centerYAnchor).isActive = true; iv.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -16).isActive = true
            trailing = iv.leadingAnchor
        }
        col.trailingAnchor.constraint(lessThanOrEqualTo: trailing, constant: -12).isActive = true
        if let tap = tap { c.addAction(UIAction { _ in tap() }, for: .touchUpInside) }
        stack.addArrangedSubview(c)
    }
    private func addLink(_ t: String, _ s: String?, _ tap: @escaping () -> Void) { card(t, s, chevron: true, tap: tap) }
    private func addInfo(_ t: String, _ s: String?) { card(t, s, chevron: false, tap: nil) }
}
