import UIKit

// 设置整页：主页 → 集合页 → 单选列表页。内容全部由 SettingsRegistry 描述，这里只负责把注册表画出来：
//   live 的项：正常显示，读写真实设置（SettingsStore）；soon 的项：整行变灰，点击提示「不可用」。

/// 设置各页共用的上下文：怎么通知相机界面、怎么跳页
final class SettingsContext {
    /// 通知相机界面设置变了（Bool = 需要重新配置摄像头）
    var onChange: ((Bool) -> Void)?
    weak var nav: UINavigationController?
    /// 玻璃 / 平面切换后，所有已打开的页面重画
    var refreshAll: () -> Void = {}

    func changed(_ reconfigure: Bool) { onChange?(reconfigure) }
    func push(_ kind: SettingsPageKind) {
        nav?.pushViewController(SettingsPageViewController(ctx: self, kind: kind), animated: true)
    }
}

enum SettingsPageKind {
    case home                 // 设置主页
    case collection(String)   // 某个集合的页面（集合 id）
    case radio(String)        // 单选列表页（设置项 id）
}

final class SettingsPageViewController: UIViewController {
    let ctx: SettingsContext
    let kind: SettingsPageKind
    let st = DualSettings.shared

    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let titleLabel = UILabel()
    private let backBtn = DualCircleButton(symbol: "chevron.left", size: 40)
    private let toast = DualToastView()
    private var toastGen = 0

    init(ctx: SettingsContext, kind: SettingsPageKind) {
        self.ctx = ctx
        self.kind = kind
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var isHome: Bool { if case .home = kind { return true } else { return false } }

    private var pageTitle: String {
        switch kind {
        case .home: return "更多设置"
        case .collection(let id): return SettingsRegistry.collection(id)?.title ?? "设置"
        case .radio(let id): return SettingsRegistry.item(id)?.title ?? "设置"
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(white: 0.07, alpha: 1)
        overrideUserInterfaceStyle = .dark

        backBtn.setSymbol(isHome ? "chevron.down" : "chevron.left", size: 40)
        backBtn.addTarget(self, action: #selector(backTapped), for: .touchUpInside)
        backBtn.accessibilityLabel = isHome ? "关闭" : "返回"
        titleLabel.text = pageTitle; titleLabel.textColor = .white
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        let bar = UIView()
        for v in [backBtn, titleLabel] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview(v) }
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        stack.axis = .vertical; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)

        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor), bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.heightAnchor.constraint(equalToConstant: 60),
            backBtn.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16), backBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: bar.centerXAnchor), titleLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: bar.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: scroll.bottomAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: scroll.leadingAnchor, constant: 16),
            stack.widthAnchor.constraint(equalTo: scroll.widthAnchor, constant: -32),
            toast.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 4),
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24)])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuild()      // 从子页回来时，右侧的当前值要刷新
    }

    @objc private func backTapped() {
        if isHome { dismiss(animated: true) } else { navigationController?.popViewController(animated: true) }
    }

    // MARK: - 画页面

    /// 按注册表重画整页（玻璃 / 平面切换、从子页返回时调用）
    func rebuild() {
        backBtn.setGlass(st.glass)
        toast.setGlass(st.glass)
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        switch kind {
        case .home: buildHome()
        case .collection(let id): if let c = SettingsRegistry.collection(id) { buildCollectionPage(c) }
        case .radio(let id): if let it = SettingsRegistry.item(id) { buildRadioPage(it) }
        }
    }

    private func buildHome() {
        for c in SettingsRegistry.collections {
            stack.addArrangedSubview(SettingsText.heading(c.title))
            if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(8, after: last) }
            switch c.kind {
            case .inline:
                addGroups(of: c)
            case .page:
                let card = SettingsCard(glass: st.glass)
                let chev = chevron()
                let row = SettingsRowView(title: c.summary, accessory: chev)
                let id = c.id
                row.onTap = { [weak self] in self?.ctx.push(.collection(id)) }
                card.addRow(row)
                stack.addArrangedSubview(card)
                spaceAfterLast(22)
            }
        }
    }

    private func buildCollectionPage(_ c: SCollection) {
        if !c.intro.isEmpty {
            stack.addArrangedSubview(SettingsText.note(SettingsRegistry.resolve(c.intro)))
            spaceAfterLast(6)
        }
        addGroups(of: c)
    }

    /// 把集合里的各分组画成：灰色小标题 + 卡片（一行一项）+ 灰色说明
    private func addGroups(of c: SCollection) {
        for g in c.groups {
            if !g.head.isEmpty && g.head != c.title {
                stack.addArrangedSubview(SettingsText.subhead(g.head))
                spaceAfterLast(6)
            }
            let card = SettingsCard(glass: st.glass)
            var notes: [String] = []
            for it in g.items {
                for r in rows(for: it) { card.addRow(r) }
                if it.type != .radio || it.inline { notes.append(contentsOf: it.notes) }
            }
            stack.addArrangedSubview(card)
            var foots: [String] = []
            if !g.foot.isEmpty { foots.append(g.foot) }
            foots.append(contentsOf: notes)
            if foots.isEmpty {
                spaceAfterLast(20)
            } else {
                spaceAfterLast(8)
                for (i, f) in foots.enumerated() {
                    stack.addArrangedSubview(SettingsText.note(SettingsRegistry.resolve(f)))
                    spaceAfterLast(i == foots.count - 1 ? 20 : 6)
                }
            }
        }
    }

    private func buildRadioPage(_ it: SItem) {
        let card = SettingsCard(glass: st.glass)
        for r in radioRows(it) { card.addRow(r) }
        stack.addArrangedSubview(card)
        spaceAfterLast(10)
        for n in it.notes {
            stack.addArrangedSubview(SettingsText.note(n))
            spaceAfterLast(6)
        }
    }

    private func spaceAfterLast(_ s: CGFloat) {
        if let last = stack.arrangedSubviews.last { stack.setCustomSpacing(s, after: last) }
    }

    func chevron() -> UIImageView {
        let c = UIImageView(image: UIImage(systemName: "chevron.right"))
        c.tintColor = UIColor(white: 1, alpha: 0.5); c.contentMode = .scaleAspectFit
        return c
    }

    // MARK: - 一项 → 若干行

    private func rows(for it: SItem) -> [UIView] {
        var out: [UIView]
        switch it.type {
        case .toggle: out = [toggleRow(it)]
        case .seg: out = [segRow(it)]
        case .link: out = [linkRow(it)]
        case .slider: out = [sliderRow(it)]
        case .info: out = [SettingsRowView(title: it.title, sub: SettingsRegistry.resolve(SettingsRegistry.subtitle(it)))]
        case .radio:
            if it.inline { out = radioRows(it) } else { out = [radioEntryRow(it)] }
        }
        if it.status == .soon { for v in out { markSoon(v) } }
        return out
    }

    private func toggleRow(_ it: SItem) -> UIView {
        let sw = GlassSwitch(on: SettingsStore.bool(it.id))
        sw.glass = st.glass
        sw.widthAnchor.constraint(equalToConstant: 50).isActive = true
        sw.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let id = it.id, recfg = it.reconfigure
        sw.onChange = { [weak self] v in
            SettingsStore.set(id, v ? "1" : "0")
            self?.ctx.changed(recfg)
            if id == "glass" { DispatchQueue.main.async { self?.ctx.refreshAll() } }     // 玻璃样式变了，所有页面重画
        }
        return SettingsRowView(title: it.title, sub: SettingsRegistry.resolve(SettingsRegistry.subtitle(it)), accessory: sw, interactiveAccessory: true)
    }

    private func segRow(_ it: SItem) -> UIView {
        let seg = GlassSegmented(items: it.options.map { $0.title }, selected: SettingsRegistry.selectedIndex(it))
        seg.glass = st.glass
        seg.heightAnchor.constraint(equalToConstant: 38).isActive = true
        let id = it.id, recfg = it.reconfigure, opts = it.options
        seg.onChange = { [weak self, weak seg] i in
            guard i >= 0 && i < opts.count else { return }
            if id == "ratio" && SettingsStore.bool("full") {       // 片门全开时画幅固定 4:3：不改，选中态退回去
                if let idx = opts.firstIndex(where: { $0.v == SettingsStore.get("ratio") }) { seg?.select(idx) }
                self?.showToast("「片门全开」开着时画幅固定为 4:3，关掉后才能改")
                return
            }
            SettingsStore.set(id, opts[i].v)
            self?.ctx.changed(recfg)
        }
        return SettingsControlRow(title: it.title, sub: SettingsRegistry.resolve(SettingsRegistry.subtitle(it)), control: seg)
    }

    private func sliderRow(_ it: SItem) -> UIView {
        let s = GlassSlider(frame: .zero)
        s.minValue = Double(it.min); s.maxValue = Double(it.max)
        s.set(Double(SettingsStore.int(it.id)))
        s.glass = st.glass
        s.heightAnchor.constraint(equalToConstant: 34).isActive = true
        s.isUserInteractionEnabled = it.status == .live
        let id = it.id
        s.onChange = { v in SettingsStore.set(id, String(Int(v.rounded()))) }
        return SettingsControlRow(title: it.title, sub: SettingsRegistry.resolve(SettingsRegistry.subtitle(it)),
                                  value: SettingsStore.get(it.id) + "%", control: s)
    }

    private func linkRow(_ it: SItem) -> UIView {
        let row = SettingsRowView(title: it.title, sub: SettingsRegistry.subtitle(it), value: SettingsRegistry.rowValue(it), accessory: chevron())
        let dest = it.dest, live = it.status == .live
        row.onTap = { [weak self] in
            guard let self = self else { return }
            if live && dest == "order" {
                let v = DualPresetOrderViewController(); v.modalPresentationStyle = .pageSheet
                self.present(v, animated: true)
            } else {
                self.showToast(SettingsRegistry.soonToast)      // 摄像头检测 / 赞赏 / 日志 / 版本 / 关于：M3 做，先灰色
            }
        }
        return row
    }

    /// 单选列表：点一个选项就选中它（右侧对勾）
    private func radioRows(_ it: SItem) -> [UIView] {
        var out: [UIView] = []
        var checks: [(String, UIImageView)] = []
        let current = SettingsStore.get(it.id)
        let id = it.id, recfg = it.reconfigure
        for o in it.options {
            let check = UIImageView(image: UIImage(systemName: "checkmark"))
            check.tintColor = dualYellow; check.contentMode = .scaleAspectFit
            check.isHidden = o.v != current || o.soon
            checks.append((o.v, check))
            let row = SettingsRowView(title: o.title, sub: o.sub, accessory: check)
            let v = o.v, soon = o.soon
            row.onTap = { [weak self] in
                if soon { self?.showToast(SettingsRegistry.soonToast); return }
                SettingsStore.set(id, v)
                for (cv, ci) in checks { ci.isHidden = cv != v }
                self?.ctx.changed(recfg)
                if id == "glassStyle" { DispatchQueue.main.async { self?.ctx.refreshAll() } }     // 玻璃样式换了，设置页自己也重画
            }
            if o.soon { markSoon(row) }
            out.append(row)
        }
        return out
    }

    /// 非内联的单选：主页 / 集合页上只有一行（右侧显示当前值），点开进选项页
    private func radioEntryRow(_ it: SItem) -> UIView {
        let row = SettingsRowView(title: it.title, value: SettingsRegistry.rowValue(it), accessory: chevron())
        let id = it.id
        row.onTap = { [weak self] in self?.ctx.push(.radio(id)) }
        return row
    }

    // MARK: - soon（灰色）与提示

    private func markSoon(_ v: UIView) {
        v.alpha = 0.4
        let cover = UIControl()
        cover.translatesAutoresizingMaskIntoConstraints = false
        v.addSubview(cover)
        NSLayoutConstraint.activate([
            cover.topAnchor.constraint(equalTo: v.topAnchor), cover.bottomAnchor.constraint(equalTo: v.bottomAnchor),
            cover.leadingAnchor.constraint(equalTo: v.leadingAnchor), cover.trailingAnchor.constraint(equalTo: v.trailingAnchor)])
        cover.addTarget(self, action: #selector(soonTapped), for: .touchUpInside)
    }

    @objc private func soonTapped() { showToast(SettingsRegistry.soonToast) }

    func showToast(_ s: String) {
        toastGen += 1
        let gen = toastGen
        toast.show(s)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self = self, self.toastGen == gen else { return }
            self.toast.hide()
        }
    }
}
