import UIKit

/// 调色面板（底部深色圆角面板，对照苹果相机的样式）：
/// 顶部「后置 / 前置 / 同时」选择改谁；中间随标签变化；底部标签：调色板 · 质感 · 颗粒。
/// 每条调节后面都有重置按钮。参数写进 DualSettings 里前 / 后摄各自的 GradeState。
final class DualPalettePanel: UIView {
    var onClose: (() -> Void)?
    var onShutter: (() -> Void)?
    var onChange: (() -> Void)?
    var glass = false { didSet { restyle(); rebuild() } }

    private let st = DualSettings.shared
    private var tab = 0
    private let bg = DualBackdrop(radius: 34)
    private let targetSeg = GlassSegmented(items: ["后置", "前置", "同时"], selected: 2)
    private let tabSeg = GlassSegmented(items: ["调色板", "质感", "颗粒"], selected: 0)
    private let host = UIView()
    private let pad = PadView()
    private var strengthSlider: GlassSlider?

    override init(frame: CGRect) {
        super.init(frame: frame)
        bg.apply(glass: false, flat: UIColor(white: 0.07, alpha: 0.96))
        addSubview(bg)
        for v in [targetSeg, tabSeg, host] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        targetSeg.select(st.gradeTarget, animated: false)
        targetSeg.onChange = { [weak self] i in self?.st.gradeTarget = i; self?.rebuild(); self?.onChange?() }
        tabSeg.onChange = { [weak self] i in self?.tab = i; self?.rebuild() }
        NSLayoutConstraint.activate([
            targetSeg.topAnchor.constraint(equalTo: topAnchor, constant: 14), targetSeg.centerXAnchor.constraint(equalTo: centerXAnchor),
            targetSeg.widthAnchor.constraint(equalToConstant: 220), targetSeg.heightAnchor.constraint(equalToConstant: 32),
            tabSeg.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16), tabSeg.centerXAnchor.constraint(equalTo: centerXAnchor),
            tabSeg.widthAnchor.constraint(equalToConstant: 250), tabSeg.heightAnchor.constraint(equalToConstant: 36),
            host.topAnchor.constraint(equalTo: targetSeg.bottomAnchor, constant: 10), host.bottomAnchor.constraint(equalTo: tabSeg.topAnchor, constant: -10),
            host.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16), host.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)])
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() { super.layoutSubviews(); bg.frame = bounds }

    private func restyle() {
        bg.apply(glass: glass, flat: UIColor(white: 0.07, alpha: 0.96))
        targetSeg.glass = glass; tabSeg.glass = glass
    }

    /// 当前正在改的目标（后置 / 前置 / 两个）
    private var targets: [GradeState] {
        switch st.gradeTarget { case 0: return [st.gradeBack]; case 1: return [st.gradeFront]; default: return [st.gradeBack, st.gradeFront] }
    }
    private var shown: GradeState { st.gradeTarget == 1 ? st.gradeFront : st.gradeBack }
    private func edit(_ f: (GradeState) -> Void) { targets.forEach(f); onChange?() }

    /// 外部（切预设、重置）改了参数后同步界面
    func syncFromState() { rebuild() }

    // MARK: 构件

    private func circle(_ symbol: String, size: CGFloat = 44, _ f: @escaping () -> Void) -> DualCircleButton {
        let b = DualCircleButton(symbol: symbol, size: size)
        b.setGlass(glass)
        b.addAction(UIAction { _ in f() }, for: .touchUpInside)
        return b
    }

    private func shutterButton() -> UIView {
        let w = UIView(); w.translatesAutoresizingMaskIntoConstraints = false
        let ring = UIView(); ring.layer.borderColor = UIColor.white.cgColor; ring.layer.borderWidth = 3.5; ring.layer.cornerRadius = 32; ring.isUserInteractionEnabled = false
        let inner = UIButton(type: .custom); inner.backgroundColor = .white; inner.layer.cornerRadius = 26
        inner.addAction(UIAction { [weak self] _ in self?.onShutter?() }, for: .touchUpInside)
        [ring, inner].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; w.addSubview($0) }
        NSLayoutConstraint.activate([
            w.widthAnchor.constraint(equalToConstant: 64), w.heightAnchor.constraint(equalToConstant: 64),
            ring.leadingAnchor.constraint(equalTo: w.leadingAnchor), ring.trailingAnchor.constraint(equalTo: w.trailingAnchor),
            ring.topAnchor.constraint(equalTo: w.topAnchor), ring.bottomAnchor.constraint(equalTo: w.bottomAnchor),
            inner.centerXAnchor.constraint(equalTo: w.centerXAnchor), inner.centerYAnchor.constraint(equalTo: w.centerYAnchor),
            inner.widthAnchor.constraint(equalToConstant: 52), inner.heightAnchor.constraint(equalToConstant: 52)])
        return w
    }

    /// 一行：名称 | 滑动条 | 重置
    private func sliderRow(_ title: String, min: Double, max: Double, value: Double, set: @escaping (GradeState, Double) -> Void, reset: @escaping (GradeState) -> Void) -> UIView {
        let l = UILabel(); l.text = title; l.textColor = UIColor(white: 1, alpha: 0.85); l.font = .systemFont(ofSize: 13)
        l.widthAnchor.constraint(equalToConstant: 46).isActive = true
        let s = GlassSlider(); s.minValue = min; s.maxValue = max; s.glass = glass; s.set(value)
        s.onChange = { [weak self] v in self?.edit { set($0, v) } }
        let r = circle("arrow.counterclockwise", size: 30) { [weak self, weak s] in
            self?.edit(reset)
            if let g = self?.shown { _ = g }
            self?.rebuild()
        }
        _ = s
        let row = UIStackView(arrangedSubviews: [l, s, r]); row.spacing = 8; row.alignment = .center
        s.heightAnchor.constraint(equalToConstant: 34).isActive = true
        return row
    }

    func rebuild() {
        host.subviews.forEach { $0.removeFromSuperview() }
        targetSeg.select(st.gradeTarget, animated: false)
        let snap = shown.snapshot()
        let back = circle("chevron.down") { [weak self] in self?.onClose?() }
        let shutter = shutterButton()
        let row = UIStackView(); row.axis = .horizontal; row.alignment = .center; row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(row)
        NSLayoutConstraint.activate([row.leadingAnchor.constraint(equalTo: host.leadingAnchor), row.trailingAnchor.constraint(equalTo: host.trailingAnchor),
                                     row.topAnchor.constraint(equalTo: host.topAnchor), row.bottomAnchor.constraint(equalTo: host.bottomAnchor)])
        row.addArrangedSubview(back)
        if tab == 0 {
            pad.glass = glass
            pad.set(x: snap.x, y: snap.y)
            pad.onMove = { [weak self] x, y in self?.edit { $0.setPad(x: x, y: y) } }
            let ss = GlassSlider(); ss.glass = glass; ss.set(snap.str)
            ss.onChange = { [weak self] v in self?.edit { $0.setStrength(v) } }
            strengthSlider = ss
            let sr = circle("arrow.counterclockwise", size: 30) { [weak self] in
                self?.edit { $0.setStrength($0.snapshot().preset.s / 100) }; self?.rebuild() }
            let sRow = UIStackView(arrangedSubviews: [ss, sr]); sRow.spacing = 8; sRow.alignment = .center
            let col = UIStackView(arrangedSubviews: [pad, sRow]); col.axis = .vertical; col.spacing = 6
            pad.translatesAutoresizingMaskIntoConstraints = false
            pad.widthAnchor.constraint(equalToConstant: 150).isActive = true; pad.heightAnchor.constraint(equalToConstant: 96).isActive = true
            ss.heightAnchor.constraint(equalToConstant: 34).isActive = true
            let padReset = circle("arrow.counterclockwise") { [weak self] in
                self?.edit { let p = $0.snapshot().preset; $0.setPad(x: p.c / 100, y: p.t / 100) }; self?.rebuild() }
            row.addArrangedSubview(UIView())
            row.addArrangedSubview(col)
            row.addArrangedSubview(padReset)
            row.addArrangedSubview(UIView())
            row.addArrangedSubview(shutter)
        } else {
            var rows: [UIView] = []
            if tab == 1 {
                rows = [
                    sliderRow("对比度", min: -1, max: 1, value: snap.contrast, set: { $0.setTexture(contrast: $1) }, reset: { $0.setTexture(contrast: 0) }),
                    sliderRow("清晰度", min: 0, max: 1, value: snap.clarity, set: { $0.setTexture(clarity: $1) }, reset: { $0.setTexture(clarity: 0) }),
                    sliderRow("锐度", min: 0, max: 1, value: snap.sharp, set: { $0.setTexture(sharp: $1) }, reset: { $0.setTexture(sharp: 0) })]
            } else {
                rows = [
                    sliderRow("数量", min: 0, max: 1, value: snap.grainAmt, set: { $0.setGrain(amount: $1) }, reset: { $0.setGrain(amount: 0) }),
                    sliderRow("大小", min: 0, max: 1, value: snap.grainSize, set: { $0.setGrain(size: $1) }, reset: { $0.setGrain(size: 0.3) })]
            }
            let col = UIStackView(arrangedSubviews: rows); col.axis = .vertical; col.spacing = 8
            row.addArrangedSubview(col)
            row.addArrangedSubview(shutter)
        }
    }
}

/// 二维调色盘：横向 = 颜色，纵向 = 色调（上为正）；小圆点阵 + 白色旋钮
private final class PadView: UIView {
    var onMove: ((Double, Double) -> Void)?
    var glass = false { didSet { restyle() } }
    private var x = 0.0, y = 0.0
    private let bg = DualBackdrop(radius: 18)
    private let dots = DotsLayer()
    private let knob = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(bg)
        layer.addSublayer(dots)
        knob.backgroundColor = .white; knob.layer.cornerRadius = 13; knob.isUserInteractionEnabled = false
        knob.layer.shadowColor = UIColor.black.cgColor; knob.layer.shadowOpacity = 0.35; knob.layer.shadowRadius = 4; knob.layer.shadowOffset = CGSize(width: 0, height: 2)
        addSubview(knob)
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func restyle() { bg.apply(glass: glass, flat: UIColor(white: 1, alpha: 0.10)) }
    func set(x: Double, y: Double) { self.x = x; self.y = y; layoutKnob() }
    private func layoutKnob() { knob.frame = CGRect(x: bounds.width * CGFloat((x + 1) / 2) - 13, y: bounds.height * CGFloat((1 - y) / 2) - 13, width: 26, height: 26) }
    override func layoutSubviews() { super.layoutSubviews(); bg.frame = bounds; dots.frame = bounds; dots.setNeedsDisplay(); layoutKnob() }
    private func upd(_ p: CGPoint) {
        x = Double(max(-1, min(1, (p.x / bounds.width - 0.5) * 2))); y = Double(max(-1, min(1, -(p.y / bounds.height - 0.5) * 2)))
        layoutKnob(); onMove?(x, y)
    }
    override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { if let p = t.first?.location(in: self) { upd(p) } }
    override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) { if let p = t.first?.location(in: self) { upd(p) } }
}

private final class DotsLayer: CALayer {
    override func draw(in c: CGContext) {
        c.setFillColor(UIColor(white: 1, alpha: 0.3).cgColor)
        let cols = 11, rows = 7
        for i in 0..<cols { for j in 0..<rows {
            let px = bounds.width * (CGFloat(i) + 0.5) / CGFloat(cols), py = bounds.height * (CGFloat(j) + 0.5) / CGFloat(rows)
            c.fillEllipse(in: CGRect(x: px - 1.2, y: py - 1.2, width: 2.4, height: 2.4))
        } }
    }
}
