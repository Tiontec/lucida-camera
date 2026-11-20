import UIKit

/// 双摄界面的变焦控件 —— 逐行移植自澄影主页面的「变焦胶囊 + 弧形转盘」：
///  · 底部胶囊：.5 1 2 3 5 10 15 20 25 30，当前档显示为深色圆里的黄色「1.0×」，点档位直接跳过去
///  · 在胶囊上按住 300ms 或拖动超过 6pt → 展开弧形转盘（刻度 / 数字 / MM 焦段 / 黄色指针 / 读数）
///  · 手指沿圆弧滑动变焦，弹簧阻尼 + 磁吸档位 + 橡皮筋边界 + 松手惯性；松手 1.7 秒后收起
///  · 点转盘上的大刻度直接跳过去
/// 纯原生 UIKit / CoreGraphics 绘制，没有任何 HTML。
final class DualZoomControl: UIView {
    // MARK: 对外接口
    /// 每帧当前（平滑后的）倍数
    var onZoom: ((CGFloat) -> Void)?
    /// 动作全部停稳（松手 + 弹簧 + 惯性结束）后回调，用来在这时切换镜头
    var onSettle: ((CGFloat) -> Void)?
    /// 玻璃外观（液态玻璃开关）
    var glass = false { didSet { applyChrome() } }

    private(set) var lo: CGFloat = 1
    private(set) var hi: CGFloat = 10
    var zoom: CGFloat { exp(lz) }

    // MARK: 主页面同款常量
    private let STOPS: [CGFloat] = [0.5, 1, 2, 3, 5, 10, 15, 20, 25, 30]
    private let MMS: [Double: Int] = [0.5: 13, 0.6: 16, 1: 26, 2: 52, 3: 77, 5: 120, 10: 240, 15: 360, 20: 480, 25: 600, 30: 720]
    private let LPRI = ["1", "10", "30", "5", "2", "3", "0.5", "0.6", "20", "15", "25"]
    private let zspdMax: CGFloat = 30           // 变焦速度档（默认 30×：1× → 30× 走 34.7% 屏宽）
    private let dH: CGFloat = 140

    private struct Tick { let l: CGFloat; let maj: Bool; let txt: String; let mm: Int }
    private var ticks: [Tick] = []
    private var mags: [CGFloat] = []            // 磁吸档位（ln）
    private var lmax: CGFloat = log(30)

    // 物理状态（对应 JS 的 S.raw / S.lt / S.lz / S.lv / S.om / S.drag / S.fling）
    private var raw: CGFloat = 0, lt: CGFloat = 0, lz: CGFloat = 0, lv: CGFloat = 0, om: CGFloat = 11.5
    private var drag = false
    private var fling: CGFloat = 0

    // 手势状态（对应 JS 的 G）
    private var gOn = false, gSrcDial = false, gMoved = false, gOpened = false
    private var gX0: CGFloat = 0, gY0: CGFloat = 0, gS0: CGFloat = 0, gPx: CGFloat = 0, gRaw0: CGFloat = 0, gV: CGFloat = 0
    private var gPt: CFTimeInterval = 0
    private var holdTimer: Timer?, hideTimer: Timer?
    private var touch: UITouch?

    // 视图
    private let pill = UIView()
    private let pillBlur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
    private var pillLabels: [UILabel] = []
    private var pillStops: [CGFloat] = []
    private let dial = DialCanvas()
    private let dialBg = CAGradientLayer()
    private let dialMask = CAShapeLayer()
    private var dialOpen = false
    private var link: CADisplayLink?
    private var lastT: CFTimeInterval = 0
    private var lastNotified: CGFloat = -1
    private var zKey = ""
    private var pxln: CGFloat { max(25, bounds.width * 0.347 / log(zspdMax)) }

    // MARK: 初始化
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        clipsToBounds = true
        isMultipleTouchEnabled = false

        dial.owner = self
        dial.backgroundColor = .clear
        dial.isOpaque = false
        dial.alpha = 0
        dial.isUserInteractionEnabled = false
        dialBg.colors = [UIColor(white: 40 / 255, alpha: 0.34).cgColor, UIColor(white: 14 / 255, alpha: 0.52).cgColor]
        dialBg.mask = dialMask
        dial.layer.addSublayer(dialBg)
        addSubview(dial)

        pill.layer.cornerRadius = 26
        pill.layer.cornerCurve = .continuous
        pill.clipsToBounds = true
        pillBlur.isUserInteractionEnabled = false
        pill.addSubview(pillBlur)
        pill.isUserInteractionEnabled = false
        addSubview(pill)

        setRange(lo: 1, hi: 10, current: 1)
        link = CADisplayLink(target: WeakProxy(self), selector: #selector(WeakProxy.tick(_:)))
        link?.isPaused = true
        link?.add(to: .main, forMode: .common)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    deinit { link?.invalidate(); holdTimer?.invalidate(); hideTimer?.invalidate() }

    override var intrinsicContentSize: CGSize { CGSize(width: UIView.noIntrinsicMetric, height: 160) }

    // MARK: 范围 / 外部设值
    /// 设置可用范围并把倍数放到 current（不触发 onZoom）
    func setRange(lo l: CGFloat, hi h: CGFloat, current: CGFloat) {
        lo = l; hi = max(l, h); lmax = log(hi)
        buildTicks()
        buildPill()
        let c = clamp(log(max(0.01, current)))
        raw = c; lt = c; lz = c; lv = 0; fling = 0; drag = false
        lastNotified = zoom
        zKey = ""
        updPill()
        dial.setNeedsDisplay()
        layoutPill()
    }

    /// 外部直接设置（例如切到前置后回到 1×），不触发回调
    func jump(to z: CGFloat) {
        let c = clamp(log(max(0.01, z)))
        raw = c; lt = c; lz = c; lv = 0; fling = 0
        lastNotified = zoom
        updPill(); dial.setNeedsDisplay()
    }

    private func buildTicks() {
        var maj: [CGFloat] = []
        if lo < 1 - 0.001 { maj.append(lo) }
        for s in [1, 2, 3, 5, 10, 15, 20, 25, 30] as [CGFloat] where s >= lo - 0.001 && s <= hi + 0.001 { maj.append(s) }
        mags = maj.map { log($0) }
        ticks = []
        var v = lo
        while v <= hi + 0.001 {
            let k = (v * 100).rounded() / 100
            let isMaj = maj.contains { abs($0 - k) < 0.005 }
            let txt = abs(k - k.rounded()) < 0.001 ? String(Int(k.rounded())) : "\(k)"
            ticks.append(Tick(l: log(k), maj: isMaj, txt: txt, mm: MMS[Double(k)] ?? Int((26 * k).rounded())))
            v = k < 2 ? k + 0.1 : (k < 5 ? k + 0.2 : (k < 10 ? k + 0.5 : (k < 30 ? k + 1 : k + 5)))
        }
    }

    private func buildPill() {
        pillLabels.forEach { $0.removeFromSuperview() }
        pillLabels = []
        pillStops = STOPS.filter { $0 >= lo - 0.001 && $0 <= hi + 0.001 }
        for _ in pillStops {
            let l = UILabel()
            l.textAlignment = .center
            l.layer.masksToBounds = true
            pill.addSubview(l)
            pillLabels.append(l)
        }
    }

    // MARK: 外观
    private func applyChrome() {
        pillBlur.effect = glass ? dualGlassEffect() : UIBlurEffect(style: .systemUltraThinMaterialDark)
        pill.layer.borderWidth = glass ? 0.6 : 0
        pill.layer.borderColor = UIColor(white: 1, alpha: 0.25).cgColor
    }

    private func clamp(_ l: CGFloat) -> CGFloat { min(lmax, max(log(lo), l)) }
    private func minLn() -> CGFloat { log(lo) }

    // MARK: 布局
    override func layoutSubviews() {
        super.layoutSubviews()
        let W = bounds.width, H = bounds.height
        dial.frame = CGRect(x: 0, y: H - dH, width: W, height: dH)
        let d = max(60, dH - 8)
        let R = max(160, ((W / 2 + 8) * (W / 2 + 8) + d * d) / (2 * d))
        dialBg.frame = dial.bounds
        dialMask.path = UIBezierPath(arcCenter: CGPoint(x: W / 2, y: 8 + R), radius: R, startAngle: 0, endAngle: .pi * 2, clockwise: true).cgPath
        layoutPill()
        dial.setNeedsDisplay()
    }

    fileprivate var dialR: CGFloat {
        let W = bounds.width, d = max(60, dH - 8)
        return max(160, ((W / 2 + 8) * (W / 2 + 8) + d * d) / (2 * d))
    }

    private func layoutPill() {
        let n = pillLabels.count
        guard n > 0 else { return }
        let cur = zoom
        var a = 0
        for (i, s) in pillStops.enumerated() where cur >= s - 0.001 { a = i }
        // 档位多、取景框窄时，把没选中的按钮收窄，保证整条胶囊完整落在取景框里（两端不再被切掉）
        let avail = bounds.width - 24
        let gaps = CGFloat(n - 1) * 2 + 8
        let inactive = max(22, min(34, (avail - 44 - gaps) / CGFloat(max(1, n - 1))))
        let widths: [CGFloat] = (0..<n).map { $0 == a ? 44 : inactive }
        let total = min(widths.reduce(0, +) + gaps, avail)
        let h: CGFloat = 52
        let x0 = (bounds.width - total) / 2
        pill.frame = CGRect(x: x0, y: bounds.height - 14 - h, width: total, height: h)
        pill.layer.cornerRadius = h / 2
        pillBlur.frame = pill.bounds
        var x: CGFloat = 4
        for (i, l) in pillLabels.enumerated() {
            let w = widths[i]
            l.frame = CGRect(x: x, y: (h - w) / 2, width: w, height: w)
            l.layer.cornerRadius = w / 2
            l.adjustsFontSizeToFitWidth = true; l.minimumScaleFactor = 0.7
            x += w + 2
        }
    }

    private func fmtZ(_ z: CGFloat) -> String {
        let r = (z * 10).rounded() / 10
        return (abs(r - r.rounded()) < 0.001 ? String(format: "%.0f", r) : String(format: "%.1f", r)) + "×"
    }

    private func updPill() {
        let z = zoom
        var a = 0
        for (i, s) in pillStops.enumerated() where z >= s - 0.001 { a = i }
        let key = "\(a)|\(Int((z * 10).rounded()))"
        if key == zKey { return }
        zKey = key
        for (i, l) in pillLabels.enumerated() {
            let on = i == a
            l.backgroundColor = on ? UIColor(white: 0, alpha: 0.42) : .clear
            l.textColor = on ? UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1) : .white
            l.font = .systemFont(ofSize: on ? 13 : 12, weight: .semibold)
            l.text = on ? fmtZ(z) : (pillStops[i] < 1 ? ".5" : String(Int(pillStops[i])))
            l.layer.borderWidth = on ? 0.5 : 0
            l.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        }
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
            self.layoutPill()
        }
    }

    // MARK: 命中（和 HTML 一样：胶囊 / 展开的转盘接收触摸，其余穿透）
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if !dialOpen && pill.frame.insetBy(dx: -4, dy: -6).contains(point) { return self }
        if dialOpen && dial.frame.contains(point) { return self }
        if dialOpen && gOn { return self }
        return nil
    }

    // MARK: 触摸（= JS pointerdown / move / up）
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard touch == nil, let t = touches.first else { return }
        touch = t
        let p = t.location(in: self)
        gStart(p, srcDial: dialOpen && !pill.frame.contains(p))
    }
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        gMove(t.location(in: self))
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        gEnd(t.location(in: self)); touch = nil
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let t = touch, touches.contains(t) else { return }
        gEnd(t.location(in: self)); touch = nil
    }

    /// 手指在转盘圆弧上的弧长位置
    private func arcPos(_ p: CGPoint) -> CGFloat {
        let R = dialR, cx = bounds.width / 2, cy = bounds.height - dH + 8 + R
        return atan2(p.x - cx, cy - p.y) * R
    }

    private func gStart(_ p: CGPoint, srcDial: Bool) {
        gOn = true; gSrcDial = srcDial
        gX0 = p.x; gPx = p.x; gY0 = p.y
        gPt = CACurrentMediaTime(); gV = 0; gMoved = false; gOpened = false
        fling = 0; gRaw0 = lz
        hideTimer?.invalidate()
        holdTimer?.invalidate()
        if !srcDial {
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: false) { [weak self] _ in
                guard let s = self, s.gOn, !s.gMoved else { return }
                s.openDial(); s.gOpened = true
            }
        }
        wake()
    }

    private func gMove(_ p: CGPoint) {
        guard gOn else { return }
        if !gMoved && hypot(p.x - gX0, p.y - gY0) > 6 {
            gMoved = true
            gS0 = arcPos(p); gPx = gS0
            gRaw0 = lz; raw = lz
            drag = true; fling = 0
            holdTimer?.invalidate()
            openDial()
        }
        guard gMoved else { return }
        let now = CACurrentMediaTime(), dt = now - gPt, sp = arcPos(p)
        if dt > 0 {
            let inst = -(sp - gPx) / pxln / CGFloat(dt)
            gV = gV * 0.6 + max(-14, min(14, inst)) * 0.4
        }
        gPx = sp; gPt = now
        raw = gRaw0 - (sp - gS0) / pxln
        lt = rub(mag(raw))
    }

    private func gEnd(_ p: CGPoint) {
        guard gOn else { return }
        gOn = false
        holdTimer?.invalidate()
        if gMoved {
            drag = false
            let lo0 = minLn()
            if raw < lo0 || raw > lmax {
                raw = clamp(raw); lt = raw; fling = 0; scheduleHide()
            } else {
                let stale = CACurrentMediaTime() - gPt > 0.09, v = stale ? 0 : gV
                if abs(v) > 0.12 { fling = max(-10, min(10, v)) } else { detent(); scheduleHide() }
            }
        } else if gSrcDial {
            // 点转盘上的大刻度：跳过去
            let cx = bounds.width / 2, px = p.x
            for t in ticks where t.maj {
                let th = (t.l - lz) * pxln / dialR, sx = cx + dialR * sin(th)
                if abs(px - sx) < 30 && abs(th) < 1 { zoomTo(exp(t.l)); break }
            }
            scheduleHide()
        } else if gOpened {
            scheduleHide()
        } else {
            // 在胶囊上点按：跳到被点的那个档位
            for (i, l) in pillLabels.enumerated() where l.frame.insetBy(dx: -2, dy: -8).contains(convert(p, to: pill)) {
                zoomTo(pillStops[i]); break
            }
        }
        wake()
    }

    func zoomTo(_ z: CGFloat) {
        fling = 0
        let c = clamp(log(max(0.01, z)))
        raw = c; lt = c
        wake()
    }

    // MARK: 物理（主页面 rub / mag / detent / step / fling 的原样移植）
    private func rub(_ x: CGFloat) -> CGFloat {
        let l0 = minLn()
        if x < l0 { return l0 - 0.12 * CGFloat(tanh(Double((l0 - x) / 0.3))) }
        if x > lmax { return lmax + 0.12 * CGFloat(tanh(Double((x - lmax) / 0.3))) }
        return x
    }
    private func mag(_ l: CGFloat) -> CGFloat {
        for c in mags {
            let d = l - c, W: CGFloat = 0.04
            if abs(d) < W { return c + (d < 0 ? -1 : 1) * W * CGFloat(pow(Double(abs(d) / W), 2.2)) }
        }
        return l
    }
    private func detent() {
        let l0 = minLn()
        for c in mags where c >= l0 - 0.001 && abs(raw - c) < 0.06 { raw = c; lt = c; return }
    }

    private func stepPhysics(_ dt: CGFloat) {
        if !drag && fling != 0 {
            raw += fling * dt
            fling *= CGFloat(exp(Double(-dt) * 3.6))
            if raw > lmax || raw < minLn() {
                raw = clamp(raw); fling = 0; lt = raw; scheduleHide()
            } else {
                lt = mag(raw)
                if abs(fling) < 0.03 { fling = 0; detent(); scheduleHide() }
            }
        }
        om += ((drag ? 48 : 11.5) - om) * min(1, dt * 20)
        let w = om, ze: CGFloat = drag ? 1 : 0.9
        let n = max(1, Int(ceil(dt / 0.006))), h = dt / CGFloat(n)
        for _ in 0..<n {
            let a = w * w * (lt - lz) - 2 * ze * w * lv
            lv += a * h
            lz += lv * h
        }
    }

    private var moving: Bool { drag || gOn || fling != 0 || abs(lt - lz) > 0.004 || abs(lv) > 0.012 }

    private func wake() { link?.isPaused = false; lastT = CACurrentMediaTime() }

    fileprivate func tick(_ l: CADisplayLink) {
        let now = CACurrentMediaTime()
        let dt = CGFloat(min(0.05, max(0.001, now - lastT))); lastT = now
        let wasMoving = moving
        stepPhysics(dt)
        let z = zoom
        if abs(z - lastNotified) > 1e-4 { lastNotified = z; onZoom?(z) }
        updPill()
        if dialOpen { dial.setNeedsDisplay() }
        if wasMoving && !moving && !dialOpen { onSettle?(z) }
        if !moving && !dialOpen { link?.isPaused = true }
    }

    // MARK: 转盘开合
    private func openDial() {
        hideTimer?.invalidate()
        if dialOpen { return }
        dialOpen = true
        dial.transform = CGAffineTransform(translationX: 0, y: 50).scaledBy(x: 0.94, y: 0.94)
        UIView.animate(withDuration: 0.55, delay: 0, usingSpringWithDamping: 0.82, initialSpringVelocity: 0, options: [.allowUserInteraction]) {
            self.dial.alpha = 1; self.dial.transform = .identity
            self.pill.alpha = 0; self.pill.transform = CGAffineTransform(scaleX: 0.7, y: 0.7).translatedBy(x: 0, y: 14)
        }
        dial.setNeedsDisplay()
        wake()
    }

    private func closeDial() {
        if gOn || fling != 0 { return }
        guard dialOpen else { return }
        dialOpen = false
        UIView.animate(withDuration: 0.4, delay: 0, options: [.allowUserInteraction, .curveEaseOut]) {
            self.dial.alpha = 0
            self.dial.transform = CGAffineTransform(translationX: 0, y: 50).scaledBy(x: 0.94, y: 0.94)
            self.pill.alpha = 1; self.pill.transform = .identity
        }
        onSettle?(zoom)
        wake()
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.7, repeats: false) { [weak self] _ in self?.closeDial() }
    }

    // MARK: 转盘绘制（= JS drawDial）
    fileprivate func drawDial(in rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        let W = dial.bounds.width, R = dialR, cx = W / 2, cy = 8 + R
        let lim = asin(min(1, (W / 2 + 34) / R))
        let cur = lz, l0 = minLn(), px = pxln
        // 轨道弧线
        c.setStrokeColor(UIColor(white: 1, alpha: 0.2).cgColor)
        c.setLineWidth(1)
        let arc = UIBezierPath(arcCenter: CGPoint(x: cx, y: cy), radius: R - 0.5, startAngle: -.pi / 2 - lim, endAngle: -.pi / 2 + lim, clockwise: true)
        c.addPath(arc.cgPath); c.strokePath()

        let labelAttr: (CGFloat) -> [NSAttributedString.Key: Any] = { a in
            [.font: UIFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: UIColor(white: 1, alpha: 0.95 * a)]
        }
        let mmAttr: (CGFloat) -> [NSAttributedString.Key: Any] = { a in
            [.font: UIFont.systemFont(ofSize: 8.5, weight: .semibold), .foregroundColor: UIColor(white: 1, alpha: 0.5 * a)]
        }
        // 数字按优先级摆放，间距不足 34pt 的不画
        var show = Set<Int>(), placed: [CGFloat] = []
        for k in LPRI {
            guard let i = ticks.firstIndex(where: { $0.maj && $0.txt == k }) else { continue }
            let p = (ticks[i].l - cur) * px
            if abs(p) < 22 || abs(p) > W { continue }
            if placed.allSatisfy({ abs($0 - p) >= 34 }) { placed.append(p); show.insert(i) }
        }
        c.setLineCap(.round)
        for (i, t) in ticks.enumerated() {
            let th = (t.l - cur) * px / R
            if abs(th) > lim { continue }
            let a = max(0, 1 - pow(abs(th) / lim, 2) * 0.8) * (t.l < l0 - 0.001 ? 0.3 : 1)
            c.saveGState()
            c.translateBy(x: cx, y: cy)
            c.rotate(by: th)
            c.setStrokeColor(UIColor(white: 1, alpha: (t.maj ? 0.92 : 0.45) * a).cgColor)
            c.setLineWidth(t.maj ? 1.8 : 1)
            c.move(to: CGPoint(x: 0, y: -R + 14))
            c.addLine(to: CGPoint(x: 0, y: -R + 14 + (t.maj ? 18 : 9)))
            c.strokePath()
            if show.contains(i) {
                drawCentered(t.txt, at: CGPoint(x: 0, y: -R + 54), attrs: labelAttr(a))
                drawCentered("\(t.mm)MM", at: CGPoint(x: 0, y: -R + 67), attrs: mmAttr(a))
            }
            c.restoreGState()
        }
        // 指针 + 读数
        let yellow = UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)
        c.setFillColor(yellow.cgColor)
        c.move(to: CGPoint(x: cx - 5, y: 2)); c.addLine(to: CGPoint(x: cx + 5, y: 2)); c.addLine(to: CGPoint(x: cx, y: 10.5))
        c.closePath(); c.fillPath()
        drawCentered(fmtZ(zoom), at: CGPoint(x: cx, y: 48),
                     attrs: [.font: UIFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: yellow])
    }

    private func drawCentered(_ s: String, at p: CGPoint, attrs: [NSAttributedString.Key: Any]) {
        let ns = s as NSString, sz = ns.size(withAttributes: attrs)
        ns.draw(at: CGPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2), withAttributes: attrs)
    }
}

/// 转盘画布
private final class DialCanvas: UIView {
    weak var owner: DualZoomControl?
    override func draw(_ rect: CGRect) { owner?.drawDial(in: rect) }
}

/// 避免 CADisplayLink 强引用 self
private final class WeakProxy {
    weak var target: DualZoomControl?
    init(_ t: DualZoomControl) { target = t }
    @objc func tick(_ l: CADisplayLink) { target?.tick(l) }
}
