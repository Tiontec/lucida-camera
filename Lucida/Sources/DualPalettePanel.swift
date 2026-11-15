import UIKit

/// 调色面板（底部深色圆角面板）：返回 / 二维调色盘 / 重置 / 快门 / 强度，三个标签：调色板 · 质感 · 颗粒。
/// 参数直接写进 DualSettings.shared.grade，引擎预览和成品都按它调色。
final class DualPalettePanel: UIView {
    var onClose: (() -> Void)?
    var onShutter: (() -> Void)?
    var onChange: (() -> Void)?
    private let g = DualSettings.shared.grade
    private let yellow = UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)
    private var tab = 0
    private let tabs = UISegmentedControl(items: ["调色板", "质感", "颗粒"])
    private let pad = PadView()
    private let host = UIView()
    private let strength = UISlider()
    private let shutterView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(white: 0.07, alpha: 0.96)
        layer.cornerRadius = 30; layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        tabs.selectedSegmentIndex = 0
        tabs.addAction(UIAction { [weak self] _ in self?.tab = self?.tabs.selectedSegmentIndex ?? 0; self?.rebuild() }, for: .valueChanged)
        for v in [tabs, host] as [UIView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: topAnchor, constant: 14), tabs.centerXAnchor.constraint(equalTo: centerXAnchor),
            tabs.widthAnchor.constraint(equalToConstant: 240),
            host.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 10), host.leadingAnchor.constraint(equalTo: leadingAnchor),
            host.trailingAnchor.constraint(equalTo: trailingAnchor), host.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -20)])
        rebuild()
    }
    required init?(coder: NSCoder) { fatalError() }

    func syncFromState() { let s = g.snapshot(); pad.set(x: s.x, y: s.y); strength.value = Float(s.str) }

    private func btn(_ name: String, _ f: @escaping () -> Void) -> UIButton {
        let b = UIButton(type: .system); b.setImage(UIImage(systemName: name), for: .normal); b.tintColor = .white
        b.backgroundColor = UIColor(white: 1, alpha: 0.12); b.layer.cornerRadius = 22
        b.addAction(UIAction { _ in f() }, for: .touchUpInside)
        b.widthAnchor.constraint(equalToConstant: 44).isActive = true; b.heightAnchor.constraint(equalToConstant: 44).isActive = true
        return b
    }

    private func slider(_ title: String, _ min: Float, _ max: Float, _ v: Float, _ f: @escaping (Float) -> Void) -> UIView {
        let l = UILabel(); l.text = title; l.textColor = UIColor(white: 1, alpha: 0.8); l.font = .systemFont(ofSize: 13)
        l.widthAnchor.constraint(equalToConstant: 56).isActive = true
        let s = UISlider(); s.minimumValue = min; s.maximumValue = max; s.value = v; s.tintColor = yellow
        s.addAction(UIAction { [weak s] _ in if let s = s { f(s.value); self.onChange?() } }, for: .valueChanged)
        let r = UIStackView(arrangedSubviews: [l, s]); r.spacing = 10; r.alignment = .center
        return r
    }

    private func rebuild() {
        host.subviews.forEach { $0.removeFromSuperview() }
        let snap = g.snapshot()
        if tab == 0 {
            // 左：返回 + 重置；中：调色盘；右：快门 + 强度
            pad.onMove = { [weak self] x, y in self?.g.setPad(x: x, y: y); self?.onChange?() }
            pad.set(x: snap.x, y: snap.y)
            let back = btn("chevron.down") { [weak self] in self?.onClose?() }
            let reset = btn("arrow.counterclockwise") { [weak self] in self?.g.reset(); self?.syncFromState(); self?.onChange?() }
            let left = UIStackView(arrangedSubviews: [back, UIView(), reset]); left.axis = .vertical; left.alignment = .center
            strength.minimumValue = 0; strength.maximumValue = 1; strength.value = Float(snap.str); strength.tintColor = yellow
            strength.removeTarget(nil, action: nil, for: .allEvents)
            strength.addAction(UIAction { [weak self] _ in self?.g.setStrength(Double(self?.strength.value ?? 1)); self?.onChange?() }, for: .valueChanged)
            let sh = UIButton(type: .custom); sh.backgroundColor = .white; sh.layer.cornerRadius = 30
            sh.layer.borderWidth = 3; sh.layer.borderColor = UIColor.black.cgColor
            sh.addAction(UIAction { [weak self] _ in self?.onShutter?() }, for: .touchUpInside)
            sh.widthAnchor.constraint(equalToConstant: 60).isActive = true; sh.heightAnchor.constraint(equalToConstant: 60).isActive = true
            let sl = UILabel(); sl.text = "强度"; sl.textColor = UIColor(white: 1, alpha: 0.7); sl.font = .systemFont(ofSize: 12)
            let shWrap = UIView(); shWrap.addSubview(sh); sh.translatesAutoresizingMaskIntoConstraints = false
            sh.centerXAnchor.constraint(equalTo: shWrap.centerXAnchor).isActive = true
            sh.topAnchor.constraint(equalTo: shWrap.topAnchor).isActive = true; sh.bottomAnchor.constraint(equalTo: shWrap.bottomAnchor).isActive = true
            let right = UIStackView(arrangedSubviews: [shWrap, sl, strength]); right.axis = .vertical; right.spacing = 6; right.alignment = .fill
            let row = UIStackView(arrangedSubviews: [left, pad, right]); row.spacing = 14; row.alignment = .fill
            row.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(row)
            left.widthAnchor.constraint(equalToConstant: 44).isActive = true
            right.widthAnchor.constraint(equalToConstant: 96).isActive = true
            NSLayoutConstraint.activate([row.topAnchor.constraint(equalTo: host.topAnchor), row.bottomAnchor.constraint(equalTo: host.bottomAnchor),
                row.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16), row.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16)])
        } else {
            let back = btn("chevron.down") { [weak self] in self?.onClose?() }
            var rows: [UIView] = []
            if tab == 1 {
                rows = [slider("对比度", -1, 1, Float(snap.contrast)) { [g] v in g.setTexture(contrast: Double(v)) },
                        slider("清晰度", 0, 1, Float(snap.clarity)) { [g] v in g.setTexture(clarity: Double(v)) },
                        slider("锐度", 0, 1, Float(snap.sharp)) { [g] v in g.setTexture(sharp: Double(v)) }]
            } else {
                rows = [slider("数量", 0, 1, Float(snap.grainAmt)) { [g] v in g.setGrain(amount: Double(v)) },
                        slider("大小", 0, 1, Float(snap.grainSize)) { [g] v in g.setGrain(size: Double(v)) }]
            }
            let col = UIStackView(arrangedSubviews: rows); col.axis = .vertical; col.spacing = 16
            let row = UIStackView(arrangedSubviews: [back, col]); row.spacing = 14; row.alignment = .top
            row.translatesAutoresizingMaskIntoConstraints = false; host.addSubview(row)
            NSLayoutConstraint.activate([row.topAnchor.constraint(equalTo: host.topAnchor, constant: 6),
                row.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 16), row.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -16)])
        }
    }
}

/// 二维调色盘：横向 = 颜色，纵向 = 色调（上为正）；一格格的小圆点，手指处亮黄
private final class PadView: UIView {
    var onMove: ((Double, Double) -> Void)?
    private var x = 0.0, y = 0.0
    override init(frame: CGRect) {
        super.init(frame: frame); backgroundColor = UIColor(white: 1, alpha: 0.06); layer.cornerRadius = 18
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
    func set(x: Double, y: Double) { self.x = x; self.y = y; setNeedsDisplay() }
    private func upd(_ p: CGPoint) {
        let nx = Double(max(-1, min(1, (p.x / bounds.width - 0.5) * 2))), ny = Double(max(-1, min(1, -(p.y / bounds.height - 0.5) * 2)))
        x = nx; y = ny; setNeedsDisplay(); onMove?(nx, ny)
    }
    override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { if let p = t.first?.location(in: self) { upd(p) } }
    override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) { if let p = t.first?.location(in: self) { upd(p) } }
    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        let cols = 11, rows = 9
        for i in 0..<cols { for j in 0..<rows {
            let px = bounds.width * (CGFloat(i) + 0.5) / CGFloat(cols), py = bounds.height * (CGFloat(j) + 0.5) / CGFloat(rows)
            c.setFillColor(UIColor(white: 1, alpha: 0.28).cgColor)
            c.fillEllipse(in: CGRect(x: px - 1.5, y: py - 1.5, width: 3, height: 3))
        } }
        let cx = bounds.width * CGFloat((x + 1) / 2), cy = bounds.height * CGFloat((1 - y) / 2)
        c.setFillColor(UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1).cgColor)
        c.fillEllipse(in: CGRect(x: cx - 11, y: cy - 11, width: 22, height: 22))
        c.setStrokeColor(UIColor.white.cgColor); c.setLineWidth(2)
        c.strokeEllipse(in: CGRect(x: cx - 11, y: cy - 11, width: 22, height: 22))
    }
}
