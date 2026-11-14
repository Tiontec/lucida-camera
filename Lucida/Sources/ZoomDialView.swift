import UIKit

/// 变焦滑动转盘（和澄影主页面那条横向刻度转盘一样的用法）：
/// 左右拖动刻度尺连续变焦，松手后带惯性；点中间的倍数读数回到 1×；点刻度上的位置直接跳过去。
/// 刻度按对数分布（0.5 → 1 → 2 → 5 间距相等）。
final class ZoomDialView: UIView {
    var onZoom: ((CGFloat, Bool) -> Void)?       // (倍数, 是否来自手指)
    private(set) var zoom: CGFloat = 1
    private var zMin: CGFloat = 1, zMax: CGFloat = 5
    private let pxLn: CGFloat = 150               // 每 ln(1) 对应的点数
    private var vLn: CGFloat = 0                  // 惯性速度（ln/秒）
    private var link: CADisplayLink?
    private var lastT: CFTimeInterval = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
        addGestureRecognizer(tap)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { link?.invalidate() }

    /// 设置可用范围和当前值（不触发回调）
    func setRange(min lo: CGFloat, max hi: CGFloat, current: CGFloat) {
        zMin = Swift.max(0.1, lo); zMax = Swift.max(zMin, hi)
        zoom = Swift.min(zMax, Swift.max(zMin, current))
        stopInertia()
        setNeedsDisplay()
    }

    private func set(_ v: CGFloat, user: Bool) {
        let nz = Swift.min(zMax, Swift.max(zMin, v))
        if abs(nz - zoom) < 1e-4 { return }
        zoom = nz
        setNeedsDisplay()
        onZoom?(zoom, user)
    }

    // MARK: 手势

    @objc private func pan(_ g: UIPanGestureRecognizer) {
        switch g.state {
        case .began:
            stopInertia()
        case .changed:
            let dx = g.translation(in: self).x
            g.setTranslation(.zero, in: self)
            set(exp(log(zoom) - dx / pxLn), user: true)
        case .ended, .cancelled:
            let v = -g.velocity(in: self).x / pxLn
            if abs(v) > 0.15 { vLn = v; startInertia() }
        default: break
        }
    }

    @objc private func tap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: self), cx = bounds.midX
        if abs(p.x - cx) < 36 && p.y < 30 { set(1, user: true) }
        else { set(exp(log(zoom) + (p.x - cx) / pxLn), user: true) }
    }

    private func startInertia() {
        link?.invalidate()
        lastT = CACurrentMediaTime()
        let l = CADisplayLink(target: self, selector: #selector(step))
        l.add(to: .main, forMode: .common)
        link = l
    }
    private func stopInertia() { link?.invalidate(); link = nil; vLn = 0 }

    @objc private func step() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(Swift.min(0.05, now - lastT)); lastT = now
        set(exp(log(zoom) + vLn * dt), user: true)
        vLn *= CGFloat(pow(0.04, Double(dt)))
        let edge = (zoom <= zMin + 1e-3 && vLn < 0) || (zoom >= zMax - 1e-3 && vLn > 0)
        if abs(vLn) < 0.03 || edge { stopInertia() }
    }

    // MARK: 绘制

    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        let W = bounds.width, cx = W / 2, lnz = log(zoom)
        // 读数
        let s = zoom >= 10 ? String(format: "%.0f×", zoom) : String(format: "%.1f×", zoom)
        let bigAttr: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 17, weight: .bold),
                                                      .foregroundColor: UIColor.systemYellow]
        let sz = (s as NSString).size(withAttributes: bigAttr)
        (s as NSString).draw(at: CGPoint(x: cx - sz.width / 2, y: 0), withAttributes: bigAttr)
        // 刻度
        let base: CGFloat = 26, hMinor: CGFloat = 8, hMajor: CGFloat = 15
        let lo = exp(lnz - cx / pxLn) - 0.05, hi = exp(lnz + cx / pxLn) + 0.05
        let small: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .medium),
                                                    .foregroundColor: UIColor(white: 1, alpha: 0.8)]
        c.setLineWidth(1.5)
        var v: CGFloat = 0.1
        while v <= zMax + 0.001 {
            defer { v += (v < 2 ? 0.1 : (v < 5 ? 0.5 : 1)) }
            if v < zMin - 0.001 || v < lo || v > hi { continue }
            let x = cx + (log(v) - lnz) * pxLn
            let isInt = abs(v - v.rounded()) < 0.01 && v >= 1
            let isHalf = abs(v - 0.5) < 0.01
            let major = isInt || isHalf
            c.setStrokeColor(UIColor(white: 1, alpha: 0.8).cgColor)
            c.move(to: CGPoint(x: x, y: base)); c.addLine(to: CGPoint(x: x, y: base + (major ? hMajor : hMinor))); c.strokePath()
            if major && abs(x - cx) > 22 {
                let t = isHalf ? "0.5" : String(Int(v.rounded()))
                let ts = (t as NSString).size(withAttributes: small)
                (t as NSString).draw(at: CGPoint(x: x - ts.width / 2, y: base + hMajor + 2), withAttributes: small)
            }
        }
        // 中心指针
        c.setStrokeColor(UIColor.systemYellow.cgColor); c.setLineWidth(2.5)
        c.move(to: CGPoint(x: cx, y: base - 2)); c.addLine(to: CGPoint(x: cx, y: base + hMajor + 2)); c.strokePath()
    }
}
