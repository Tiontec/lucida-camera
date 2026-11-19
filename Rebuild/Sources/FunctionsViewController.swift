import UIKit

/// 多功能面板（相机底部快门旁的按键）：底部抽屉。
/// - 3 列圆形图标按钮；半屏（露出前两行）⇄ 近全屏 两档，手势跟手、松手吸附；点面板外面、或往下拉到底关闭。
/// - 按钮清单和状态都在 PanelRegistry.swift 里；灰色（.soon）的点击提示「未加入此功能」。
/// - 右上角齿轮 = 进设置；原来的「更多设置 / 预设顺序 / 关于」入口已经迁到设置里。
/// 呈现方式：overFullScreen（背后的相机画面保持运行），不用动画呈现（入场 / 退场动画自己做）。
final class FunctionsViewController: UIViewController {
    var onOpenSettings: (() -> Void)?
    var onOpenPalette: (() -> Void)?
    var onOpenRatio: (() -> Void)?
    /// 闪光灯：当前模式（0 关 / 1 自动 / 2 开）；点一下切到下一档，回调返回新的模式
    var flashMode = 0
    var onCycleFlash: (() -> Int)?
    /// 双摄开关：当前状态 / 请求切换（回调：最终状态，提示文字）
    var dualOn = false
    var onToggleDual: ((Bool, @escaping (Bool, String?) -> Void) -> Void)?

    private let st = DualSettings.shared
    private let dim = UIView()
    private let sheet = UIView()
    private let sheetBg = DualBackdrop()
    private let grabber = UIView()
    private var gear: PanelCircle!
    private let content = UIView()
    private var tiles: [PanelTile] = []
    private let toastBox = UIView()
    private let toastBg = DualBackdrop()
    private let toastLabel = UILabel()
    private var toastGen = 0

    private let sideMargin: CGFloat = 12
    private let headerH: CGFloat = 44
    private let minPitch: CGFloat = 112
    private var hMin: CGFloat = 300, hMax: CGFloat = 600, bottomMargin: CGFloat = 40
    private var sheetH: CGFloat = 0
    private var dragStartH: CGFloat = 0
    private var shown = false, closing = false, dualBusy = false
    private var lastSize = CGSize.zero

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        overrideUserInterfaceStyle = .dark

        dim.backgroundColor = .black; dim.alpha = 0
        dim.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dimTapped)))
        view.addSubview(dim)

        sheet.clipsToBounds = true
        sheet.layer.cornerRadius = 34; sheet.layer.cornerCurve = .continuous
        view.addSubview(sheet)
        if st.glass {
            sheetBg.apply(glass: true)
        } else {
            sheetBg.effect = UIBlurEffect(style: .systemThickMaterialDark)
            sheetBg.backgroundColor = UIColor(white: 0.08, alpha: 0.45)
        }
        sheet.addSubview(sheetBg)

        grabber.backgroundColor = UIColor(white: 1, alpha: 0.35)
        grabber.layer.cornerRadius = 2.5
        sheet.addSubview(grabber)

        gear = PanelCircle(symbols: ["gearshape.fill", "gearshape"], pointSize: 18, glass: st.glass)
        gear.accessibilityLabel = "设置"
        gear.addTarget(self, action: #selector(gearTapped), for: .touchUpInside)
        sheet.addSubview(gear)

        sheet.addSubview(content)
        for it in PanelRegistry.items {
            let t = PanelTile(item: it, glass: st.glass)
            if it.action == .toggleDual { t.active = dualOn }
            if it.action == .cycleFlash { t.active = flashMode != 0 }
            t.addTarget(self, action: #selector(tileTapped(_:)), for: .touchUpInside)
            content.addSubview(t)
            tiles.append(t)
        }
        sheet.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(pan(_:))))

        toastBox.alpha = 0; toastBox.isUserInteractionEnabled = false
        toastBg.capsule = true
        toastBg.apply(glass: st.glass, flat: UIColor(white: 0.12, alpha: 0.92))
        toastLabel.textColor = .white; toastLabel.font = .systemFont(ofSize: 14, weight: .medium)
        toastLabel.textAlignment = .center; toastLabel.numberOfLines = 2
        toastBox.addSubview(toastBg); toastBox.addSubview(toastLabel)
        view.addSubview(toastBox)
    }

    // MARK: - 布局与高度

    private func computeMetrics() {
        let b = view.bounds
        let safe = view.safeAreaInsets
        bottomMargin = max(safe.bottom, 4) + 8
        hMax = max(320, b.height - (safe.top + 52) - bottomMargin)
        hMin = min(300, hMax - 40)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        dim.frame = view.bounds
        if lastSize != view.bounds.size {
            lastSize = view.bounds.size
            computeMetrics()
            if !shown { setHeight(0) }
            else if !closing { setHeight(sheetH <= 0 ? hMin : min(max(sheetH, hMin), hMax)) }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !shown else { return }
        shown = true
        computeMetrics()
        UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.3, options: [.allowUserInteraction]) {
            self.setHeight(self.hMin)
        }
    }

    /// 把面板高度设成 h（拖动时每一帧都调；动画块里调就是动画）。按钮的行距随高度变大：半屏时紧凑，拉开后撑满
    private func setHeight(_ h: CGFloat) {
        sheetH = h
        let b = view.bounds
        let w = b.width - sideMargin * 2
        sheet.frame = CGRect(x: sideMargin, y: b.height - bottomMargin - h, width: w, height: h)
        sheetBg.frame = sheet.bounds
        grabber.frame = CGRect(x: (w - 40) / 2, y: 8, width: 40, height: 5)
        gear.frame = CGRect(x: w - 14 - 36, y: 4, width: 36, height: 36)
        content.frame = CGRect(x: 0, y: headerH, width: w, height: max(0, h - headerH))
        let span = max(1, hMax - hMin)
        let t = max(0, min(1, (h - hMin) / span))
        let pMax = max(minPitch, (hMax - headerH - 20) / 4)
        let pitch = minPitch + (pMax - minPitch) * t
        let colW = w / 3
        let tileH: CGFloat = 68 + 30
        for (i, tile) in tiles.enumerated() {
            tile.bounds = CGRect(x: 0, y: 0, width: colW, height: tileH)
            tile.center = CGPoint(x: colW * (CGFloat(i % 3) + 0.5), y: 8 + pitch * CGFloat(i / 3) + tileH / 2)
        }
        dim.alpha = 0.32 * t
    }

    // MARK: - 手势

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        if closing { return }
        switch g.state {
        case .began:
            dragStartH = sheetH
        case .changed:
            var h = dragStartH - g.translation(in: view).y
            if h > hMax { h = hMax + (h - hMax) * 0.25 }     // 上拉过头有阻尼
            setHeight(max(0, h))
        case .ended, .cancelled, .failed:
            settle(velocity: g.velocity(in: view).y)          // 正数 = 向下
        default:
            break
        }
    }

    private func settle(velocity v: CGFloat) {
        var target: CGFloat
        if v > 800 {
            if sheetH > hMin + 30 { target = hMin } else { dismissPanel(); return }
        } else if v < -800 {
            target = hMax
        } else if sheetH < hMin * 0.7 {
            dismissPanel(); return
        } else {
            target = sheetH < (hMin + hMax) / 2 ? hMin : hMax
        }
        target = max(hMin, min(hMax, target))
        UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.86, initialSpringVelocity: 0,
                       options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.setHeight(target)
        }
    }

    @objc private func dimTapped() { dismissPanel() }

    /// 面板收下去再关掉；then 在关掉之后执行（比如接着打开调色盘 / 设置）
    private func dismissPanel(then: (() -> Void)? = nil) {
        if closing { return }
        closing = true
        UIView.animate(withDuration: 0.28, delay: 0, options: [.curveEaseIn, .beginFromCurrentState], animations: {
            self.setHeight(0)
        }, completion: { _ in
            self.dismiss(animated: false) { then?() }
        })
    }

    // MARK: - 点击

    @objc private func gearTapped() {
        let cb = onOpenSettings
        dismissPanel { cb?() }
    }

    @objc private func tileTapped(_ t: UIControl) {
        guard !closing, let tile = t as? PanelTile else { return }
        if tile.item.state == .soon { showToast(SettingsRegistry.panelSoonToast); return }
        perform(tile)
    }

    /// 各按钮的点击动作；新功能做好后在这里接上
    private func perform(_ tile: PanelTile) {
        switch tile.item.action {
        case .openPalette:
            let cb = onOpenPalette
            dismissPanel { cb?() }
        case .toggleDual:
            guard !dualBusy, let toggle = onToggleDual else { return }
            dualBusy = true
            tile.isEnabled = false
            toggle(!dualOn) { [weak self, weak tile] isOn, msg in
                guard let self = self else { return }
                self.dualBusy = false
                self.dualOn = isOn
                tile?.isEnabled = true
                tile?.active = isOn
                self.showToast(msg ?? (isOn ? "双摄已开启" : "双摄已关闭"))
            }
        case .openRatio:
            let cb = onOpenRatio
            dismissPanel { cb?() }
        case .cycleFlash:
            guard let cycle = onCycleFlash else { return }
            flashMode = cycle()
            tile.active = flashMode != 0
            showToast(["闪光灯：关", "闪光灯：自动（暗处才闪）", "闪光灯：开"][flashMode])
        case .none:
            showToast(SettingsRegistry.panelSoonToast)
        }
    }

    // MARK: - 提示条（浮在面板上方）

    private func showToast(_ s: String) {
        toastGen += 1
        let gen = toastGen
        toastLabel.text = s
        let maxW = view.bounds.width - 40
        let textW = min(maxW - 32, toastLabel.sizeThatFits(CGSize(width: maxW - 32, height: 60)).width)
        let w = textW + 32
        let hgt: CGFloat = toastLabel.numberOfLines == 2 && textW >= maxW - 33 ? 52 : 38
        let y = max(view.safeAreaInsets.top + 8, sheet.frame.minY - 12 - hgt)
        toastBox.frame = CGRect(x: (view.bounds.width - w) / 2, y: y, width: w, height: hgt)
        toastBg.frame = toastBox.bounds
        toastLabel.frame = toastBox.bounds.insetBy(dx: 16, dy: 4)
        view.bringSubviewToFront(toastBox)
        UIView.animate(withDuration: 0.18) { self.toastBox.alpha = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self = self, self.toastGen == gen else { return }
            UIView.animate(withDuration: 0.25) { self.toastBox.alpha = 0 }
        }
    }
}

// MARK: - 面板里的小控件

/// 圆形图标按钮（齿轮用）：玻璃 / 平面两种底
final class PanelCircle: UIControl {
    private let bg = DualBackdrop()
    private let icon = UIImageView()

    init(symbols: [String], pointSize: CGFloat, glass: Bool) {
        super.init(frame: .zero)
        bg.capsule = true
        bg.apply(glass: glass, flat: UIColor(white: 1, alpha: 0.16), interactive: true)
        addSubview(bg)
        icon.contentMode = .center; icon.tintColor = .white; icon.isUserInteractionEnabled = false
        icon.image = PanelRegistry.symbol(symbols, size: pointSize, weight: .semibold)
        addSubview(icon)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        bg.frame = bounds
        icon.frame = bounds
    }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { bounds.insetBy(dx: -6, dy: -6).contains(point) }
    override var isHighlighted: Bool {
        didSet { UIView.animate(withDuration: 0.12) { self.alpha = self.isHighlighted ? 0.6 : 1 } }
    }
}

/// 面板里的一个功能按钮：圆形图标 + 下面的文字。soon 的整个变灰；active（如双摄已开）高亮成黄色
final class PanelTile: UIControl {
    let item: PanelItem
    private let glass: Bool
    private let circle = DualBackdrop()
    private let icon = UIImageView()
    private let label = UILabel()
    var active = false { didSet { restyle() } }

    init(item: PanelItem, glass: Bool) {
        self.item = item
        self.glass = glass
        super.init(frame: .zero)
        circle.capsule = true
        addSubview(circle)
        icon.contentMode = .center; icon.isUserInteractionEnabled = false
        icon.image = PanelRegistry.symbol(item.symbols, size: 26)
        addSubview(icon)
        label.text = item.title
        label.textAlignment = .center
        label.font = .systemFont(ofSize: 14, weight: .regular)
        label.isUserInteractionEnabled = false
        addSubview(label)
        alpha = item.state == .soon ? 0.38 : 1
        accessibilityLabel = item.title
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func restyle() {
        let on = active && item.state == .enabled
        let flat = on ? dualYellow.withAlphaComponent(0.30) : UIColor(white: 1, alpha: 0.16)
        circle.apply(glass: glass, flat: flat, interactive: false, tint: on ? dualYellow.withAlphaComponent(0.35) : nil)
        icon.tintColor = on ? dualYellow : .white
        label.textColor = on ? dualYellow : .white
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let d: CGFloat = 68
        circle.frame = CGRect(x: (bounds.width - d) / 2, y: 0, width: d, height: d)
        icon.frame = circle.frame
        label.frame = CGRect(x: 0, y: d + 8, width: bounds.width, height: 20)
    }

    override var isHighlighted: Bool {
        didSet {
            UIView.animate(withDuration: 0.12) {
                self.transform = self.isHighlighted ? CGAffineTransform(scaleX: 0.93, y: 0.93) : .identity
            }
        }
    }
}
