import UIKit

/// 液态玻璃 / 普通样式 两用的控件：分段选择、开关、滑动条。
/// glass = true：iOS 26 及以上用系统原生 UIGlassEffect（低版本自动退回系统毛玻璃）；glass = false：平面深色样式。

let dualYellow = UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)

// MARK: - 玻璃样式（设置 → 界面风格）

/// frosted = 毛玻璃；liquid = 液态玻璃（iOS 26 及以上用系统原生 UIGlassEffect，低版本用自绘折射）
enum DualGlassStyle { case frosted, liquid }
var dualGlassStyle: DualGlassStyle { DualSettings.shared.glassStyle == "frosted" ? .frosted : .liquid }

/// 本机能不能用系统原生液态玻璃（要 iOS 26 且用新 SDK 编译）
let dualNativeGlassAvailable: Bool = {
    #if compiler(>=6.2)
    if #available(iOS 26.0, *) { return true }
    #endif
    return false
}()

/// 现在这块玻璃是不是用系统原生在画（注意：按压的光团 + 拉伸现在对所有玻璃样式都启用，见 LiquidTouchFX）
func dualUsesNativeGlass(_ glass: Bool) -> Bool { glass && dualGlassStyle == .liquid && dualNativeGlassAvailable }

/// 系统玻璃效果（iOS 26 UIGlassEffect），拿不到时退回毛玻璃
func dualGlassEffect(interactive: Bool = false, tint: UIColor? = nil) -> UIVisualEffect {
    #if compiler(>=6.2)
    if #available(iOS 26.0, *), dualGlassStyle == .liquid {
        let e = UIGlassEffect()
        e.isInteractive = interactive
        if let t = tint { e.tintColor = t }
        return e
    }
    #endif
    return UIBlurEffect(style: .systemThinMaterialDark)
}

/// 给任意视图垫一层玻璃（或平面）背景。
/// 四种样子：平面 / 毛玻璃（模糊 + 高光描边）/ 系统液态玻璃 / 自绘折射液态玻璃（小控件拿取景画面做折射，大面板用毛玻璃 + 高光）。
final class DualBackdrop: UIVisualEffectView {
    enum Mode { case flat, frosted, native, refract }
    private(set) var mode: Mode = .flat
    private var radius: CGFloat = 0
    private let refractLayer = CALayer()      // 折射画面（只有 .refract 且小控件才有）
    private let rim = GlassRim()              // 高光描边
    private(set) var refractReady = false     // 已经有折射画面在显示

    init(radius: CGFloat = 0) {
        super.init(effect: nil)
        self.radius = radius
        isUserInteractionEnabled = false
        clipsToBounds = true
        layer.cornerCurve = .continuous
        refractLayer.isHidden = true
        refractLayer.contentsGravity = .resize
        contentView.layer.addSublayer(refractLayer)
        rim.isHidden = true
        contentView.layer.addSublayer(rim)
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { GlassRefractHub.shared.unregister(self) }

    /// radius < 0 = 胶囊
    var capsule = false { didSet { setNeedsLayout() } }

    func apply(glass: Bool, flat: UIColor = UIColor(white: 1, alpha: 0.12), interactive: Bool = false, tint: UIColor? = nil) {
        refractReady = false; refractLayer.contents = nil; refractLayer.isHidden = true
        if glass && dualPanelTheme != .glass {     // 设置 → 面板样式 选了纯色：相机界面的玻璃改成深色纯色（白色面板的文字适配排在后面，这里统一用深色）
            mode = .flat; effect = nil; backgroundColor = tint ?? UIColor(white: 0.10, alpha: 0.96); rim.isHidden = true
            GlassRefractHub.shared.unregister(self); setNeedsLayout(); return
        }
        if !glass {
            mode = .flat; effect = nil; backgroundColor = flat; rim.isHidden = true
            GlassRefractHub.shared.unregister(self)
        } else if dualGlassStyle == .liquid && dualNativeGlassAvailable {
            mode = .native; effect = dualGlassEffect(interactive: interactive, tint: tint); backgroundColor = nil; rim.isHidden = true
            GlassRefractHub.shared.unregister(self)
        } else if dualGlassStyle == .liquid {
            mode = .refract
            effect = UIBlurEffect(style: .systemUltraThinMaterialDark)     // 还没拿到取景画面（或控件太大）时的底
            backgroundColor = tint ?? UIColor(white: 1, alpha: 0.05)
            rim.isHidden = false
            if window != nil { GlassRefractHub.shared.register(self) }
        } else {
            mode = .frosted
            effect = UIBlurEffect(style: .systemThinMaterialDark)
            backgroundColor = tint ?? UIColor(white: 1, alpha: 0.05)
            rim.isHidden = false
            GlassRefractHub.shared.unregister(self)
        }
        setNeedsLayout()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if mode == .refract { if window != nil { GlassRefractHub.shared.register(self) } else { GlassRefractHub.shared.unregister(self) } }
    }

    /// 折射画面送来了（nil = 现在不折射，露出底下的模糊）
    func showRefraction(_ img: CGImage?) {
        guard mode == .refract else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        refractLayer.contents = img
        refractLayer.isHidden = img == nil
        CATransaction.commit()
        refractReady = img != nil
    }

    var cornerRadiusNow: CGFloat { capsule ? min(bounds.width, bounds.height) / 2 : radius }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = cornerRadiusNow
        CATransaction.begin(); CATransaction.setDisableActions(true)
        refractLayer.frame = bounds
        rim.frame = bounds
        rim.update(radius: cornerRadiusNow)
        CATransaction.commit()
    }
}

/// 玻璃的边缘高光：左上亮、右下次亮、中间几乎透明，一圈很细的描边
final class GlassRim: CAGradientLayer {
    private let ring = CAShapeLayer()
    override init() {
        super.init()
        colors = [UIColor(white: 1, alpha: 0.85).cgColor, UIColor(white: 1, alpha: 0.10).cgColor, UIColor(white: 1, alpha: 0.0).cgColor, UIColor(white: 1, alpha: 0.38).cgColor]
        locations = [0, 0.32, 0.62, 1]
        startPoint = CGPoint(x: 0, y: 0); endPoint = CGPoint(x: 1, y: 1)
        ring.fillColor = nil; ring.strokeColor = UIColor.white.cgColor; ring.lineWidth = 1.2
        mask = ring
    }
    override init(layer: Any) { super.init(layer: layer) }
    required init?(coder: NSCoder) { fatalError() }
    func update(radius: CGFloat) {
        ring.frame = bounds
        ring.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.6, dy: 0.6), cornerRadius: max(0, radius - 0.6)).cgPath
    }
}

// MARK: - 折射渲染（液态玻璃的自绘版）

/// 取景画面一份缩小的副本 + 一个定时器：每隔一会儿，给每个「小玻璃控件」从取景画面里裁出它背后的那一块，
/// 套上玻璃透镜（CIGlassLozenge：边缘把背后的画面向内折弯），再轻轻虚化提亮，贴回控件里。
/// 只有控件在取景框上面、尺寸不大（短边 ≤ 90）时才折射，其余情况露出底下的模糊，不会出错。
final class GlassRefractHub {
    static let shared = GlassRefractHub()
    weak var stage: UIView?                                        // 取景容器；设了才会折射
    private let views = NSHashTable<DualBackdrop>.weakObjects()
    private var link: CADisplayLink?
    private let lock = NSLock()
    private var frame: CGImage?                                    // 最近一帧取景画面（缩小）
    private var lastSubmit: CFTimeInterval = 0
    private let renderQ = DispatchQueue(label: "lucida.glass.refract", qos: .userInitiated)
    private let ci = CIContext(options: [.cacheIntermediates: false])
    private var busy = false

    /// 引擎线程每画好一帧调一次：这里自己限速（约 15 帧/秒），没人需要折射就立刻返回
    func offer(_ pb: CVPixelBuffer) {
        guard link != nil else { return }
        let now = CACurrentMediaTime()
        guard now - lastSubmit > 0.065 else { return }
        lastSubmit = now
        let w = CGFloat(CVPixelBufferGetWidth(pb)), h = CGFloat(CVPixelBufferGetHeight(pb))
        guard w > 0, h > 0 else { return }
        let k = min(1, 640 / max(w, h))
        let img = CIImage(cvPixelBuffer: pb).transformed(by: CGAffineTransform(scaleX: k, y: k))
        guard let cg = ci.createCGImage(img, from: img.extent) else { return }
        lock.lock(); frame = cg; lock.unlock()
    }

    func register(_ v: DualBackdrop) {
        views.add(v)
        if link == nil {
            let l = CADisplayLink(target: HubTarget(self), selector: #selector(HubTarget.tick))
            l.preferredFramesPerSecond = 15
            l.add(to: .main, forMode: .common)
            link = l
        }
    }

    func unregister(_ v: DualBackdrop) {
        views.remove(v)
        if views.count == 0 { link?.invalidate(); link = nil }
    }

    fileprivate func tick() {
        guard !busy, let stage = stage, let win = stage.window else { return }
        lock.lock(); let src = frame; lock.unlock()
        guard let image = src else { return }
        let stageRect = stage.convert(stage.bounds, to: win)
        let scale = min(2, win.screen.scale)
        struct Job { let view: DualBackdrop; let rect: CGRect }
        var jobs: [Job] = []
        for v in views.allObjects {
            guard v.mode == .refract, v.window === win, !v.isHidden, v.alpha > 0.02, v.bounds.width > 4, v.bounds.height > 4 else { continue }
            if min(v.bounds.width, v.bounds.height) > 90 { if v.refractReady { v.showRefraction(nil) }; continue }
            var a: CGFloat = 1; var p: UIView? = v
            while let q = p { a *= q.alpha; if q.isHidden { a = 0; break }; p = q.superview }
            let r = v.convert(v.bounds, to: win)
            if a < 0.02 || !r.intersects(stageRect) { if v.refractReady { v.showRefraction(nil) }; continue }
            jobs.append(Job(view: v, rect: r))
        }
        guard !jobs.isEmpty else { return }
        busy = true
        let fit = stageRect
        renderQ.async { [weak self] in
            guard let self = self else { return }
            var out: [(DualBackdrop, CGImage?)] = []
            for j in jobs { out.append((j.view, self.render(image, fit: fit, rect: j.rect, scale: scale))) }
            DispatchQueue.main.async {
                for (v, img) in out { v.showRefraction(img) }
                self.busy = false
            }
        }
    }

    /// 把「取景画面按 aspect-fit 铺进 stage」后，rect 那一块（窗口坐标）裁出来，做玻璃透镜
    private func render(_ cg: CGImage, fit: CGRect, rect: CGRect, scale: CGFloat) -> CGImage? {
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        let s = min(fit.width / iw, fit.height / ih)
        let ox = fit.minX + (fit.width - iw * s) / 2, oy = fit.minY + (fit.height - ih * s) / 2
        // 图像（y 向上）→ 控件本地（y 向上，单位 = 像素）
        let t = CGAffineTransform(a: s * scale, b: 0, c: 0, d: s * scale, tx: (ox - rect.minX) * scale, ty: (rect.maxY - oy - s * ih) * scale)
        let W = rect.width * scale, H = rect.height * scale
        let box = CGRect(x: 0, y: 0, width: W, height: H)
        var img = CIImage(cgImage: cg).transformed(by: t).clampedToExtent()
        if let blur = CIFilter(name: "CIGaussianBlur") {
            blur.setValue(img, forKey: kCIInputImageKey); blur.setValue(2.0 * scale, forKey: kCIInputRadiusKey)
            if let o = blur.outputImage { img = o.clampedToExtent() }
        }
        let horizontal = W >= H
        let r = min(W, H) / 2
        let p0 = horizontal ? CGPoint(x: r, y: H / 2) : CGPoint(x: W / 2, y: r)
        let p1 = horizontal ? CGPoint(x: W - r, y: H / 2) : CGPoint(x: W / 2, y: H - r)
        if let lens = CIFilter(name: "CIGlassLozenge") {
            lens.setValue(img, forKey: kCIInputImageKey)
            lens.setValue(CIVector(cgPoint: p0), forKey: "inputPoint0")
            lens.setValue(CIVector(cgPoint: p1), forKey: "inputPoint1")
            lens.setValue(r, forKey: kCIInputRadiusKey)
            lens.setValue(1.35, forKey: "inputRefraction")
            if let o = lens.outputImage { img = o.clampedToExtent() }
        }
        if let cc = CIFilter(name: "CIColorControls") {                       // 玻璃比背后的画面略亮、略鲜
            cc.setValue(img, forKey: kCIInputImageKey)
            cc.setValue(0.05, forKey: kCIInputBrightnessKey); cc.setValue(1.18, forKey: kCIInputSaturationKey)
            if let o = cc.outputImage { img = o }
        }
        return ci.createCGImage(img.cropped(to: box), from: box)
    }
}

private final class HubTarget: NSObject {
    private weak var hub: GlassRefractHub?
    init(_ h: GlassRefractHub) { hub = h }
    @objc func tick() { hub?.tick() }
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

// MARK: - 液态按压效果（按下有一团光跟着手指，按住拖动会向手指的方向拉伸，松手弹回）

/// 挂在任意按钮上：touchesBegan/Moved/Ended/Cancelled 里转发进来即可。
/// 静息 = 原样；按下 = 光团淡入并跟手；拖动 = 朝手指方向拉长（最多约 35%）并轻微跟随；松手 = 弹簧回弹。
final class LiquidTouchFX {
    private weak var host: UIView?
    private let holder = UIView()
    private let glow = CAGradientLayer()
    private var down = false

    init(host: UIView) {
        self.host = host
        holder.isUserInteractionEnabled = false
        holder.clipsToBounds = true
        holder.alpha = 0
        glow.type = .radial
        glow.colors = [UIColor(white: 1, alpha: 0.62).cgColor, UIColor(white: 1, alpha: 0.18).cgColor, UIColor(white: 1, alpha: 0).cgColor]
        glow.locations = [0, 0.45, 1]
        glow.startPoint = CGPoint(x: 0.5, y: 0.5); glow.endPoint = CGPoint(x: 1, y: 1)
        holder.layer.addSublayer(glow)
    }

    /// 布局后调用（按钮尺寸变了要更新圆角）
    func layout(in bounds: CGRect, capsule: Bool = true) {
        guard let h = host else { return }
        if holder.superview == nil { h.insertSubview(holder, at: min(1, h.subviews.count)) }
        holder.frame = bounds
        holder.layer.cornerRadius = capsule ? min(bounds.width, bounds.height) / 2 : 0
        holder.layer.cornerCurve = .continuous
        let d = max(bounds.width, bounds.height) * 1.25
        glow.bounds = CGRect(x: 0, y: 0, width: d, height: d)
    }

    func began(_ t: UITouch) {
        guard let h = host else { return }
        down = true
        moveGlow(t.location(in: h), animated: false)
        UIView.animate(withDuration: 0.18, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) { self.holder.alpha = 1 }
        stretch(t.location(in: h), spring: true)
    }

    func moved(_ t: UITouch) {
        guard let h = host, down else { return }
        let p = t.location(in: h)
        moveGlow(p, animated: false)
        stretch(p, spring: false)
    }

    func ended() {
        guard let h = host else { return }
        down = false
        UIView.animate(withDuration: 0.35, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState]) { self.holder.alpha = 0 }
        UIView.animate(withDuration: 0.6, delay: 0, usingSpringWithDamping: 0.38, initialSpringVelocity: 0.8,
                       options: [.allowUserInteraction, .beginFromCurrentState]) { h.transform = .identity }
    }

    private func moveGlow(_ p: CGPoint, animated: Bool) {
        CATransaction.begin(); CATransaction.setDisableActions(true)
        glow.position = p
        CATransaction.commit()
    }

    private func stretch(_ p: CGPoint, spring: Bool) {
        guard let h = host else { return }
        let w = max(1, h.bounds.width), hh = max(1, h.bounds.height)
        let dx = (p.x - w / 2) / w, dy = (p.y - hh / 2) / hh               // -0.5…0.5（手指跑到外面可以更大）
        let cx = max(-1.2, min(1.2, dx)), cy = max(-1.2, min(1.2, dy))
        let sx = 1 + 0.06 + abs(cx) * 0.3, sy = 1 + 0.06 + abs(cy) * 0.3   // 按下就先涨一点，拖得越远拉得越长
        var tf = CGAffineTransform(translationX: cx * w * 0.16, y: cy * hh * 0.16)
        tf = tf.scaledBy(x: sx, y: sy)
        if spring {
            UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.5,
                           options: [.allowUserInteraction, .beginFromCurrentState]) { h.transform = tf }
        } else {
            UIView.animate(withDuration: 0.08, delay: 0, options: [.allowUserInteraction, .beginFromCurrentState, .curveLinear]) { h.transform = tf }
        }
    }
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
    private lazy var fx = LiquidTouchFX(host: self)
    override func layoutSubviews() { super.layoutSubviews(); bg.frame = bounds; sendSubviewToBack(bg); fx.layout(in: bounds) }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { super.touchesBegan(touches, with: event); if let t = touches.first { fx.began(t) } }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { super.touchesMoved(touches, with: event); if let t = touches.first { fx.moved(t) } }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { super.touchesEnded(touches, with: event); fx.ended() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { super.touchesCancelled(touches, with: event); fx.ended() }
    func setSymbol(_ n: String, size: CGFloat? = nil) {
        let s = size ?? bounds.width
        setImage(UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: s * 0.42, weight: .semibold)), for: .normal)
    }
    func setGlass(_ on: Bool) {
        glass = on
        bg.apply(glass: on, flat: UIColor(white: 1, alpha: 0.16), interactive: false)     // 按压动效由 LiquidTouchFX 统一提供（毛玻璃和液态玻璃一致）
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
        bg.apply(glass: on, flat: UIColor(white: 1, alpha: 0.16), interactive: false)     // 按压动效由 LiquidTouchFX 统一提供（毛玻璃和液态玻璃一致）
    }
    private lazy var fx = LiquidTouchFX(host: self)
    override func layoutSubviews() {
        super.layoutSubviews()
        bg.frame = bounds
        sendSubviewToBack(bg)          // 文字始终在玻璃上面，不会被模糊
        fx.layout(in: bounds)
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) { super.touchesBegan(touches, with: event); if let t = touches.first { fx.began(t) } }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) { super.touchesMoved(touches, with: event); if let t = touches.first { fx.moved(t) } }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) { super.touchesEnded(touches, with: event); fx.ended() }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { super.touchesCancelled(touches, with: event); fx.ended() }
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
