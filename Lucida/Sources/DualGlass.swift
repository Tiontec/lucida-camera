import UIKit

/// 液态玻璃 / 普通样式 两用的控件：分段选择、开关、滑动条。
/// glass = true：iOS 26 及以上用系统原生 UIGlassEffect（低版本自动退回系统毛玻璃）；glass = false：平面深色样式。

let dualYellow = UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)

/// 系统玻璃效果（iOS 26 UIGlassEffect），拿不到时退回毛玻璃
func dualGlassEffect(interactive: Bool = false, tint: UIColor? = nil) -> UIVisualEffect {
    #if compiler(>=6.2)
    if #available(iOS 26.0, *) {
        let e = UIGlassEffect()
        e.isInteractive = interactive
        if let t = tint { e.tintColor = t }
        return e
    }
    #endif
    return UIBlurEffect(style: .systemThinMaterialDark)
}

/// 给任意视图垫一层玻璃（或平面）背景
final class DualBackdrop: UIVisualEffectView {
    private var radius: CGFloat = 0
    init(radius: CGFloat = 0) {
        super.init(effect: nil)
        self.radius = radius
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.cornerCurve = .continuous
    }
    required init?(coder: NSCoder) { fatalError() }
    /// radius < 0 = 胶囊
    var capsule = false { didSet { setNeedsLayout() } }
    func apply(glass: Bool, flat: UIColor = UIColor(white: 1, alpha: 0.12), interactive: Bool = false, tint: UIColor? = nil) {
        if glass { effect = dualGlassEffect(interactive: interactive, tint: tint); backgroundColor = nil }
        else { effect = nil; backgroundColor = flat }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = capsule ? min(bounds.width, bounds.height) / 2 : radius
    }
}

// MARK: - 分段选择

final class GlassSegmented: UIControl {
    private(set) var selectedIndex = 0
    var onChange: ((Int) -> Void)?
    var glass = false { didSet { restyle() } }
    private let bg = DualBackdrop()
    private let thumb = DualBackdrop()
    private var labels: [UILabel] = []

    init(items: [String], selected: Int = 0) {
        super.init(frame: .zero)
        self.selectedIndex = selected
        bg.capsule = true; thumb.capsule = true
        addSubview(bg); addSubview(thumb)
        for t in items {
            let l = UILabel(); l.text = t; l.textAlignment = .center; l.font = .systemFont(ofSize: 13, weight: .semibold)
            l.isUserInteractionEnabled = false
            addSubview(l); labels.append(l)
        }
        restyle()
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
    }
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 34) }

    func select(_ i: Int, animated: Bool = true) {
        selectedIndex = max(0, min(labels.count - 1, i))
        restyleLabels()
        UIView.animate(withDuration: animated ? 0.28 : 0, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0.2, options: [.beginFromCurrentState]) { self.layoutThumb() }
    }

    private func restyle() {
        bg.apply(glass: glass, flat: UIColor(white: 1, alpha: 0.10))
        thumb.apply(glass: glass, flat: UIColor(white: 1, alpha: 0.26), interactive: true)
        restyleLabels()
    }
    private func restyleLabels() {
        for (i, l) in labels.enumerated() { l.textColor = i == selectedIndex ? .white : UIColor(white: 1, alpha: 0.7) }
    }
    private func layoutThumb() {
        guard !labels.isEmpty else { return }
        let w = (bounds.width - 6) / CGFloat(labels.count)
        thumb.frame = CGRect(x: 3 + w * CGFloat(selectedIndex), y: 3, width: w, height: bounds.height - 6)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        bg.frame = bounds
        let w = (bounds.width - 6) / CGFloat(labels.count)
        for (i, l) in labels.enumerated() { l.frame = CGRect(x: 3 + w * CGFloat(i), y: 0, width: w, height: bounds.height) }
        layoutThumb()
    }
    @objc private func tap(_ g: UITapGestureRecognizer) {
        let w = (bounds.width - 6) / CGFloat(labels.count)
        let i = max(0, min(labels.count - 1, Int((g.location(in: self).x - 3) / w)))
        if i != selectedIndex { select(i); onChange?(i); sendActions(for: .valueChanged) }
    }
}

// MARK: - 开关

/// 开关（紧凑尺寸 50 × 28）：旋钮平时是纯白色长圆；按住 / 点击 / 拖动时变成液态玻璃水滴，
/// 拖到哪一边松手就开 / 关，松手后水滴落回纯白旋钮。未开液态玻璃时只做普通的白色旋钮（按下会略微拉长）。
final class GlassSwitch: UIControl {
    private(set) var isOn = false
    var onChange: ((Bool) -> Void)?
    var glass = false { didSet { restyle() } }
    private let track = UIView()
    private let solid = UIView()
    private let drop = DualBackdrop()
    private let trackW: CGFloat = 50, trackH: CGFloat = 28, knobW: CGFloat = 31, knobH: CGFloat = 24, inset: CGFloat = 2
    private var grabbing = false, moved = false
    private var startX: CGFloat = 0, knobStart: CGFloat = 0, knobNow: CGFloat = 2

    init(on: Bool) {
        super.init(frame: CGRect(x: 0, y: 0, width: 50, height: 28))
        isOn = on
        track.isUserInteractionEnabled = false; solid.isUserInteractionEnabled = false
        solid.backgroundColor = .white
        drop.capsule = true; drop.alpha = 0
        addSubview(track); addSubview(solid); addSubview(drop)
        knobNow = restX(on)
        let g = UILongPressGestureRecognizer(target: self, action: #selector(press(_:)))
        g.minimumPressDuration = 0; g.allowableMovement = CGFloat.greatestFiniteMagnitude
        addGestureRecognizer(g)
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: CGSize { CGSize(width: trackW, height: trackH) }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool { bounds.insetBy(dx: -8, dy: -8).contains(point) }

    private func restX(_ on: Bool) -> CGFloat { on ? bounds.width - knobW - inset : inset }
    private func progress(_ x: CGFloat) -> CGFloat {
        let lo = inset, hi = max(lo + 1, bounds.width - knobW - inset)
        return max(0, min(1, (x - lo) / (hi - lo)))
    }
    private func mix(_ a: UIColor, _ b: UIColor, _ t: CGFloat) -> UIColor {
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0, br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        a.getRed(&ar, green: &ag, blue: &ab, alpha: &aa); b.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return UIColor(red: ar + (br - ar) * t, green: ag + (bg - ag) * t, blue: ab + (bb - ab) * t, alpha: aa + (ba - aa) * t)
    }
    private func paintTrack(_ x: CGFloat) {
        track.backgroundColor = mix(UIColor(white: 1, alpha: 0.2), dualYellow, progress(x))
    }
    private func place(_ x: CGFloat) {
        knobNow = x
        let h = bounds.height
        solid.frame = CGRect(x: x, y: (h - knobH) / 2, width: knobW, height: knobH)
        solid.layer.cornerRadius = knobH / 2
        drop.frame = solid.frame.insetBy(dx: -7, dy: -5)
        paintTrack(x)
    }
    private func restyle() {
        drop.apply(glass: glass, flat: UIColor(white: 1, alpha: 0.55), interactive: true)
        setNeedsLayout()
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        track.frame = bounds; track.layer.cornerRadius = bounds.height / 2
        if !grabbing { place(restX(isOn)) }
    }

    /// 液态玻璃水滴 ⇄ 纯白旋钮
    private func grab(_ on: Bool) {
        grabbing = on
        if glass {
            if on { drop.transform = CGAffineTransform(scaleX: 0.85, y: 0.85) }
            UIView.animate(withDuration: on ? 0.32 : 0.28, delay: 0, usingSpringWithDamping: on ? 0.55 : 0.8, initialSpringVelocity: 0.6, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.drop.alpha = on ? 1 : 0
                self.drop.transform = .identity
                self.solid.alpha = on ? 0 : 1
            }
        } else {
            UIView.animate(withDuration: 0.2, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.solid.transform = on ? CGAffineTransform(scaleX: 1.14, y: 1) : .identity
            }
        }
    }

    private func settle(_ newOn: Bool, animated: Bool) {
        let changed = newOn != isOn
        isOn = newOn
        let x = restX(newOn)
        let move = { self.place(x) }
        if animated { UIView.animate(withDuration: 0.38, delay: 0, usingSpringWithDamping: 0.7, initialSpringVelocity: 0.4, options: [.beginFromCurrentState, .allowUserInteraction], animations: move) } else { move() }
        if changed { onChange?(isOn); sendActions(for: .valueChanged) }
    }

    func set(_ v: Bool, animated: Bool = false) {
        guard !grabbing else { return }
        isOn = v
        if animated { UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.75, initialSpringVelocity: 0.3, options: [.beginFromCurrentState]) { self.place(self.restX(v)) } }
        else { place(restX(v)) }
    }

    @objc private func press(_ g: UILongPressGestureRecognizer) {
        let px = g.location(in: self).x
        switch g.state {
        case .began:
            moved = false; startX = px; knobStart = knobNow
            grab(true)
        case .changed:
            if abs(px - startX) > 3 { moved = true }
            let x = min(max(knobStart + (px - startX), inset), bounds.width - knobW - inset)
            place(x)
        case .ended, .cancelled:
            var newOn = isOn
            if g.state == .ended {
                if moved { newOn = progress(knobNow) > 0.5 } else { newOn = !isOn }
            }
            grab(false)
            settle(newOn, animated: true)
        default: break
        }
    }
}

// MARK: - 滑动条

final class GlassSlider: UIControl {
    var minValue: Double = 0, maxValue: Double = 1
    private(set) var value: Double = 0
    var onChange: ((Double) -> Void)?
    var glass = false { didSet { restyle() } }
    var tint: UIColor = dualYellow { didSet { fill.backgroundColor = tint } }
    private let track = UIView(), fill = UIView()
    private let thumb = DualBackdrop()
    private var dragging = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        track.isUserInteractionEnabled = false; fill.isUserInteractionEnabled = false
        track.backgroundColor = UIColor(white: 1, alpha: 0.22); fill.backgroundColor = tint
        addSubview(track); addSubview(fill); addSubview(thumb)
        thumb.capsule = true
        restyle()
    }
    required init?(coder: NSCoder) { fatalError() }
    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 34) }

    func set(_ v: Double) { value = max(minValue, min(maxValue, v)); layoutKnob() }
    private func restyle() { thumb.apply(glass: glass, flat: .white, interactive: true); layoutKnob() }

    private var knobSize: CGSize { glass ? CGSize(width: 44, height: 28) : CGSize(width: 38, height: 24) }
    private func layoutKnob() {
        let k = knobSize, usable = max(1, bounds.width - k.width)
        let f = maxValue > minValue ? CGFloat((value - minValue) / (maxValue - minValue)) : 0
        thumb.frame = CGRect(x: usable * f, y: (bounds.height - k.height) / 2, width: k.width, height: k.height)
        track.frame = CGRect(x: 0, y: bounds.height / 2 - 2, width: bounds.width, height: 4)
        track.layer.cornerRadius = 2
        fill.frame = CGRect(x: 0, y: bounds.height / 2 - 2, width: thumb.frame.midX, height: 4)
        fill.layer.cornerRadius = 2
    }
    override func layoutSubviews() { super.layoutSubviews(); layoutKnob() }

    private func update(_ p: CGPoint) {
        let k = knobSize, usable = max(1, bounds.width - k.width)
        let f = max(0, min(1, (p.x - k.width / 2) / usable))
        value = minValue + Double(f) * (maxValue - minValue)
        layoutKnob(); onChange?(value); sendActions(for: .valueChanged)
    }
    override func beginTracking(_ t: UITouch, with e: UIEvent?) -> Bool {
        dragging = true; update(t.location(in: self))
        UIView.animate(withDuration: 0.15) { self.thumb.transform = CGAffineTransform(scaleX: 1.12, y: 1.12) }
        return true
    }
    override func continueTracking(_ t: UITouch, with e: UIEvent?) -> Bool { update(t.location(in: self)); return true }
    override func endTracking(_ t: UITouch?, with e: UIEvent?) {
        dragging = false
        UIView.animate(withDuration: 0.2) { self.thumb.transform = .identity }
    }
    override func cancelTracking(with e: UIEvent?) { endTracking(nil, with: e) }
}

// MARK: - 圆形按钮（图标 / 文字，玻璃或平面）

final class DualCircleButton: UIButton {
    private let bg = DualBackdrop()
    private(set) var glass = false
    var active = false { didSet { tintColor = active ? dualYellow : .white } }
    init(symbol: String? = nil, size: CGFloat) {
        super.init(frame: .zero)
        bg.capsule = true
        insertSubview(bg, at: 0)
        if let s = symbol { setSymbol(s, size: size) }
        tintColor = .white
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        setGlass(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() { super.layoutSubviews(); bg.frame = bounds; sendSubviewToBack(bg) }
    func setSymbol(_ n: String, size: CGFloat? = nil) {
        let s = size ?? bounds.width
        setImage(UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)), for: .normal)
    }
    func setGlass(_ on: Bool) {
        glass = on
        bg.apply(glass: on, flat: UIColor(white: 1, alpha: 0.16), interactive: true)
    }
}

// MARK: - 顶部规格胶囊（液态玻璃长条水滴，文字保持清晰）

final class DualPillButton: UIButton {
    private let bg = DualBackdrop()
    private(set) var glass = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        bg.capsule = true
        insertSubview(bg, at: 0)
        setTitleColor(.white, for: .normal)
        titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        contentEdgeInsets = UIEdgeInsets(top: 0, left: 16, bottom: 0, right: 16)
        setGlass(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    func setGlass(_ on: Bool) {
        glass = on
        bg.apply(glass: on, flat: UIColor(white: 1, alpha: 0.16), interactive: true)
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        bg.frame = bounds
        sendSubviewToBack(bg)          // 文字始终在玻璃上面，不会被模糊
    }
}

// MARK: - 提示条（放在取景框左上角；开液态玻璃时是玻璃，关闭时是普通深色面板）

final class DualToastView: UIView {
    private let bg = DualBackdrop(radius: 15)
    private let label = UILabel()
    private var glass = false
    override init(frame: CGRect) {
        super.init(frame: frame)
        bg.translatesAutoresizingMaskIntoConstraints = false; addSubview(bg)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textColor = .white; label.font = .systemFont(ofSize: 13, weight: .medium); label.numberOfLines = 0
        addSubview(label)
        NSLayoutConstraint.activate([
            bg.topAnchor.constraint(equalTo: topAnchor), bg.bottomAnchor.constraint(equalTo: bottomAnchor),
            bg.leadingAnchor.constraint(equalTo: leadingAnchor), bg.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 7), label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -7),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13), label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13)])
        isUserInteractionEnabled = false
        isHidden = true; alpha = 0
        setGlass(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    func setGlass(_ on: Bool) {
        glass = on
        bg.apply(glass: on, flat: UIColor(white: 0.1, alpha: 0.92))
    }
    func show(_ text: String) {
        label.text = text
        layer.removeAllAnimations()
        isHidden = false
        if alpha < 0.05 { alpha = 0; transform = CGAffineTransform(scaleX: 0.86, y: 0.86) }
        UIView.animate(withDuration: glass ? 0.45 : 0.2, delay: 0, usingSpringWithDamping: glass ? 0.6 : 1, initialSpringVelocity: 0.5, options: [.beginFromCurrentState]) {
            self.alpha = 1; self.transform = .identity
        }
    }
    func hide() {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState]) {
            self.alpha = 0
        } completion: { _ in
            if self.alpha < 0.05 { self.isHidden = true }
        }
    }
}

// MARK: - 调色盘图标（和主界面一致：圆角方框 + 圆点阵列，中心大点跟着调色盘落点走）

enum PaletteGlyph {
    /// x / y：调色盘落点（-1…1）
    static func image(size: CGFloat, x: Double, y: Double) -> UIImage {
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = UIScreen.main.scale; fmt.opaque = false
        let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: fmt)
        return r.image { ctx in
            let c = ctx.cgContext
            UIColor.white.setStroke(); UIColor.white.setFill()
            let lw = size * 0.075
            let box = CGRect(x: lw / 2, y: lw / 2, width: size - lw, height: size - lw)
            let path = UIBezierPath(roundedRect: box, cornerRadius: size * 0.28)
            path.lineWidth = lw; path.stroke()
            // 点阵 5 × 5
            let inner = box.insetBy(dx: size * 0.2, dy: size * 0.2)
            let step = inner.width / 4, dot = size * 0.045
            for i in 0..<5 { for j in 0..<5 {
                c.setAlpha(0.85)
                c.fillEllipse(in: CGRect(x: inner.minX + step * CGFloat(i) - dot, y: inner.minY + step * CGFloat(j) - dot, width: dot * 2, height: dot * 2))
            } }
            // 中心大点：随落点移动
            let cx = inner.midX + CGFloat(x) * inner.width / 2, cy = inner.midY - CGFloat(y) * inner.height / 2
            let big = size * 0.11
            c.setAlpha(1)
            c.fillEllipse(in: CGRect(x: cx - big, y: cy - big, width: big * 2, height: big * 2))
        }.withRenderingMode(.alwaysTemplate)
    }
}
