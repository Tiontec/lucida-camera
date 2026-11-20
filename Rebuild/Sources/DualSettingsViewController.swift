import UIKit

/// 双摄「更多设置」：实况时长 / 实况保存方式 / 实况计时显示 / 片门全开 / 小窗边框 / 前置镜像 / 录像声音 / 液态玻璃
/// 液态玻璃开启时，分段选择、开关、滑块都换成系统玻璃样式。
final class DualSettingsViewController: UIViewController {
    /// reconfigure = 需要重配摄像头（片门全开改了）
    var onChange: ((_ reconfigure: Bool) -> Void)?
    private let st = DualSettings.shared
    private let stack = UIStackView()
    private let scroll = UIScrollView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.1, alpha: 1)
        overrideUserInterfaceStyle = .dark
        let title = UILabel(); title.text = "更多设置"; title.textColor = .white
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        let done = UIButton(type: .system); done.setTitle("完成", for: .normal)
        done.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        done.tintColor = dualYellow
        done.addTarget(self, action: #selector(close), for: .touchUpInside)
        let bar = UIView(); bar.translatesAutoresizingMaskIntoConstraints = false
        [title, done].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview($0) }
        view.addSubview(bar)
        scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        stack.axis = .vertical; stack.spacing = 12; stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 56),
            title.centerXAnchor.constraint(equalTo: bar.centerXAnchor), title.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            done.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -18), done.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 8), stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -30),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16), stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32)
        ])
        build()
    }

    private func build() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let g = st.glass
        let durs: [Double] = [3, 5, 6, 8]
        addSeg("实况时长（快门前 1.5 秒）", durs.map { "\(Int($0)) 秒" }, durs.firstIndex(of: st.liveDur) ?? 0) { [st] i in st.liveDur = durs[i] }
        addSeg("实况保存方式", ["只存实况", "实况 + 静态照片"], st.liveAlsoStill ? 1 : 0) { [st] i in st.liveAlsoStill = i == 1 }
        addSwitch("实况计时显示", "拍实况时在取景框左上角显示已经拍到第几秒、有没有拍完", st.liveTimer) { [st] v in st.liveTimer = v }
        addSwitch("片门全开", "前后摄像头都用 4:3 整块传感器规格，成品 3:4；帧率尽量保持所选值", st.fullSensor) { [weak self] v in
            self?.st.fullSensor = v; self?.onChange?(true) }
        addSwitch("满帧画面运行录制", "开：不因手机发烫自动降帧，取景和录制都按所选帧率；关：发烫时自动降到 30 帧、60 帧取景隔帧刷新，降低功耗，保证录完的视频流畅", st.fullRate) { [weak self] v in
            self?.st.fullRate = v; self?.onChange?(false) }
        addSwitch("取景网格线", "在取景框里画三分线，方便构图", st.gridLines) { [weak self] v in self?.st.gridLines = v; self?.onChange?(false) }
        addSwitch("倒计时震动", "倒计时每数一秒轻震一下；关掉就只有数字，没有震动", st.countVibrate) { [weak self] v in self?.st.countVibrate = v; self?.onChange?(false) }
        addSwitch("水平仪", "取景框中间显示水平线：竖拿手机时线跟地平线平行，歪在 0.8° 内变黄；手机平放俯拍时变成圆圈 + 小圆点", st.level) { [weak self] v in self?.st.level = v; self?.onChange?(false) }
        let pf: [Int] = [30, 60, 120]
        addSeg("小窗滑动帧率", pf.map { "\($0) 帧" }, pf.firstIndex(of: st.pipDragFps) ?? 1) { [st] i in st.pipDragFps = pf[i] }
        let bs: [PipBorder] = [.none, .white, .black]
        addSeg("小窗边框", ["无", "白色", "黑色"], bs.firstIndex(of: st.border) ?? 0) { [st] i in st.border = bs[i] }
        addSwitch("前置画面镜像", nil, st.mirror) { [st] v in st.mirror = v }
        addSwitch("录像时录制声音", nil, st.audio) { [st] v in st.audio = v }
        addSwitch("液态玻璃界面", "iOS 26 及以上使用系统原生液态玻璃；低版本自动用普通毛玻璃", g) { [weak self] v in
            self?.st.glass = v; self?.build() }
        addLink("调色盘预设顺序", "拖动调整 13 个预设的顺序，调色盘里左右滑动就按这个顺序切换；「标准」固定在第一位") { [weak self] in
            let v = DualPresetOrderViewController(); v.modalPresentationStyle = .pageSheet
            self?.present(v, animated: true)
        }
        let note = UILabel(); note.numberOfLines = 0; note.textColor = UIColor(white: 1, alpha: 0.45); note.font = .systemFont(ofSize: 12)
        note.text = "说明：同时开前后摄像头时，系统不提供 ProRAW。小窗滑动帧率 120 需要支持 120Hz 的屏幕；录下来的视频帧率以「帧率」档位为准。"
        stack.addArrangedSubview(note)
    }

    private func card(_ title: String, _ sub: String?, _ control: UIView, inline: Bool) {
        let c = UIView(); c.layer.cornerRadius = 14; c.layer.cornerCurve = .continuous
        let back = DualBackdrop(radius: 14); back.translatesAutoresizingMaskIntoConstraints = false
        back.apply(glass: st.glass, flat: UIColor(white: 1, alpha: 0.08)); c.addSubview(back)
        NSLayoutConstraint.activate([back.topAnchor.constraint(equalTo: c.topAnchor), back.bottomAnchor.constraint(equalTo: c.bottomAnchor),
                                     back.leadingAnchor.constraint(equalTo: c.leadingAnchor), back.trailingAnchor.constraint(equalTo: c.trailingAnchor)])
        let t = UILabel(); t.text = title; t.textColor = .white; t.font = .systemFont(ofSize: 15, weight: .medium); t.numberOfLines = 0
        let sl = UILabel(); sl.text = sub; sl.textColor = UIColor(white: 1, alpha: 0.5); sl.font = .systemFont(ofSize: 12); sl.numberOfLines = 0
        sl.isHidden = sub == nil
        let left = UIStackView(arrangedSubviews: [t, sl]); left.axis = .vertical; left.spacing = 3
        let row = UIStackView(arrangedSubviews: [left, control])
        if inline { row.axis = .horizontal; row.alignment = .center; row.spacing = 10 } else { row.axis = .vertical; row.spacing = 10 }
        row.translatesAutoresizingMaskIntoConstraints = false
        c.addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: c.topAnchor, constant: 12), row.bottomAnchor.constraint(equalTo: c.bottomAnchor, constant: -12),
            row.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 14), row.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -14)])
        stack.addArrangedSubview(c)
    }

    private func addSeg(_ title: String, _ items: [String], _ sel: Int, _ f: @escaping (Int) -> Void) {
        let s = GlassSegmented(items: items, selected: sel); s.glass = st.glass
        s.onChange = { [weak self] i in f(i); self?.onChange?(false) }
        s.heightAnchor.constraint(equalToConstant: 38).isActive = true
        card(title, nil, s, inline: false)
    }
    private func addSwitch(_ title: String, _ sub: String?, _ on: Bool, _ f: @escaping (Bool) -> Void) {
        let s = GlassSwitch(on: on); s.glass = st.glass
        s.onChange = { [weak self] v in f(v); if title.hasPrefix("液态") { self?.onChange?(false) } }
        s.setContentHuggingPriority(.required, for: .horizontal)
        s.widthAnchor.constraint(equalToConstant: 50).isActive = true; s.heightAnchor.constraint(equalToConstant: 28).isActive = true
        card(title, sub, s, inline: true)
    }
    private var linkActions: [ObjectIdentifier: () -> Void] = [:]
    private func addLink(_ title: String, _ sub: String?, _ f: @escaping () -> Void) {
        let chev = UIImageView(image: UIImage(systemName: "chevron.right"))
        chev.tintColor = UIColor(white: 1, alpha: 0.5); chev.contentMode = .scaleAspectFit
        chev.setContentHuggingPriority(.required, for: .horizontal)
        card(title, sub, chev, inline: true)
        guard let c = stack.arrangedSubviews.last else { return }
        linkActions[ObjectIdentifier(c)] = f
        c.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(linkTapped(_:))))
    }
    @objc private func linkTapped(_ g: UITapGestureRecognizer) {
        if let v = g.view, let f = linkActions[ObjectIdentifier(v)] { f() }
    }
    @objc private func close() { dismiss(animated: true) }
}


// MARK: - 调色盘预设顺序（拖动排序；「标准」固定第一位）

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
