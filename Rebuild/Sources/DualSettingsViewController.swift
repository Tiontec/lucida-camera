import UIKit

/// 「更多设置」整页的容器：里面是一个不显示导航栏的 UINavigationController（主页 → 集合页 → 单选列表页，左上角返回、支持右滑返回）。
/// 页面内容全部来自 SettingsRegistry，画页面的代码在 SettingsPages.swift / SettingsRows.swift。
/// 对相机界面的接口和以前一样：设置 onChange，然后 present（pageSheet）即可。
final class DualSettingsViewController: UIViewController, UIGestureRecognizerDelegate {
    /// reconfigure = 需要重配摄像头（片门全开改了）。任何设置改动都会回调（相机界面据此重新应用边框 / 镜像 / 玻璃等）
    var onChange: ((_ reconfigure: Bool) -> Void)?

    private let ctx = SettingsContext()
    private var navVC: UINavigationController?

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)

        ctx.onChange = { [weak self] recfg in self?.onChange?(recfg) }
        let home = SettingsPageViewController(ctx: ctx, kind: .home)
        let nav = UINavigationController(rootViewController: home)
        nav.setNavigationBarHidden(true, animated: false)
        nav.view.backgroundColor = UIColor(white: 0.07, alpha: 1)
        nav.interactivePopGestureRecognizer?.delegate = self      // 隐藏导航栏后仍然支持右滑返回
        ctx.nav = nav
        ctx.refreshAll = { [weak self] in self?.refreshAll() }
        navVC = nav

        addChild(nav)
        nav.view.frame = view.bounds
        nav.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(nav.view)
        nav.didMove(toParent: self)
    }

    /// 玻璃 / 平面切换后：所有已打开的页面重画
    private func refreshAll() {
        for vc in navVC?.viewControllers ?? [] {
            (vc as? SettingsPageViewController)?.rebuild()
        }
    }

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        (navVC?.viewControllers.count ?? 0) > 1
    }
}

final class DualPresetOrderViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private var sids = PresetOrder.sids
    private let table = UITableView(frame: .zero, style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.07, alpha: 1); overrideUserInterfaceStyle = .dark
        let title = UILabel(); title.text = "调色盘预设顺序"; title.textColor = .white; title.font = .systemFont(ofSize: 17, weight: .semibold)
        let done = UIButton(type: .system); done.setTitle("完成", for: .normal); done.tintColor = dualYellow
        done.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        done.addTarget(self, action: #selector(close), for: .touchUpInside)
        let reset = UIButton(type: .system); reset.setTitle("恢复默认", for: .normal); reset.tintColor = dualYellow
        reset.titleLabel?.font = .systemFont(ofSize: 15)
        reset.addTarget(self, action: #selector(resetOrder), for: .touchUpInside)
        let bar = UIView(); bar.translatesAutoresizingMaskIntoConstraints = false
        [title, done, reset].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview($0) }
        table.translatesAutoresizingMaskIntoConstraints = false
        table.backgroundColor = .clear; table.dataSource = self; table.delegate = self
        table.isEditing = true; table.separatorColor = UIColor(white: 1, alpha: 0.1)
        table.register(UITableViewCell.self, forCellReuseIdentifier: "c")
        view.addSubview(bar); view.addSubview(table)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 56),
            title.centerXAnchor.constraint(equalTo: bar.centerXAnchor), title.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -18), done.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            reset.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 18), reset.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            table.topAnchor.constraint(equalTo: bar.bottomAnchor), table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor), table.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
    }
    @objc private func close() { dismiss(animated: true) }
    @objc private func resetOrder() { PresetOrder.reset(); sids = PresetOrder.sids; table.reloadData() }

    private func dot(_ c: [Double]) -> UIImage {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 22, height: 22))
        return r.image { _ in
            UIColor(red: CGFloat(min(1, c[0] * 1.1)), green: CGFloat(min(1, c[1] * 1.1)), blue: CGFloat(min(1, c[2] * 1.1)), alpha: 1).setFill()
            UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 20, height: 20)).fill()
        }
    }

    func tableView(_ t: UITableView, numberOfRowsInSection s: Int) -> Int { sids.count }
    func tableView(_ t: UITableView, cellForRowAt ip: IndexPath) -> UITableViewCell {
        let cell = t.dequeueReusableCell(withIdentifier: "c", for: ip)
        let p = stylePresets.first { $0.sid == sids[ip.row] } ?? stylePresets[0]
        cell.textLabel?.text = "\(ip.row + 1)  \(p.name)" + (ip.row == 0 ? "（固定第一位）" : "")
        cell.textLabel?.textColor = .white
        cell.imageView?.image = dot(p.tint)
        cell.backgroundColor = UIColor(white: 1, alpha: 0.06)
        return cell
    }
    func tableView(_ t: UITableView, canMoveRowAt ip: IndexPath) -> Bool { ip.row != 0 }
    func tableView(_ t: UITableView, editingStyleForRowAt ip: IndexPath) -> UITableViewCell.EditingStyle { .none }
    func tableView(_ t: UITableView, shouldIndentWhileEditingRowAt ip: IndexPath) -> Bool { false }
    func tableView(_ t: UITableView, targetIndexPathForMoveFromRowAt src: IndexPath, toProposedIndexPath dst: IndexPath) -> IndexPath {
        dst.row == 0 ? IndexPath(row: 1, section: 0) : dst
    }
    func tableView(_ t: UITableView, moveRowAt src: IndexPath, to dst: IndexPath) {
        let x = sids.remove(at: src.row); sids.insert(x, at: dst.row)
        PresetOrder.sids = sids
        t.reloadData()
    }
}
