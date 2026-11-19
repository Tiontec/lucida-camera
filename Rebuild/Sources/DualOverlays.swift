import UIKit

/// 取景网格线（三分线）
final class DualGridView: UIView {
    private let lines = CAShapeLayer()
    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        lines.strokeColor = UIColor(white: 1, alpha: 0.38).cgColor
        lines.lineWidth = 0.8; lines.fillColor = nil
        layer.addSublayer(lines)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width, h = bounds.height
        let p = UIBezierPath()
        for i in 1...2 {
            let x = w * CGFloat(i) / 3, y = h * CGFloat(i) / 3
            p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: h))
            p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
        }
        lines.frame = bounds; lines.path = p.cgPath
    }
}

/// 水平仪：竖着拿手机时，中间一条线始终跟地平线平行，歪在 ±0.8° 以内变黄；手机平放朝下拍（俯拍）时，变成一个圆圈 + 小圆点，点进圈里就是水平
final class DualLevelView: UIView {
    private let fixedL = CAShapeLayer(), fixedR = CAShapeLayer(), tilt = CAShapeLayer(), ring = CAShapeLayer(), dot = CAShapeLayer()
    private var lastG: (Double, Double, Double) = (0, -1, 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        for l in [fixedL, fixedR, tilt, ring] {
            l.lineWidth = 1.8; l.lineCap = .round; l.fillColor = nil
            l.strokeColor = UIColor(white: 1, alpha: 0.85).cgColor
            layer.addSublayer(l)
        }
        dot.fillColor = UIColor(white: 1, alpha: 0.9).cgColor
        layer.addSublayer(dot)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        func seg(_ a: CGPoint, _ b: CGPoint) -> CGPath { let p = UIBezierPath(); p.move(to: a); p.addLine(to: b); return p.cgPath }
        fixedL.path = seg(CGPoint(x: c.x - 98, y: c.y), CGPoint(x: c.x - 80, y: c.y))
        fixedR.path = seg(CGPoint(x: c.x + 80, y: c.y), CGPoint(x: c.x + 98, y: c.y))
        tilt.frame = bounds
        tilt.path = seg(CGPoint(x: c.x - 62, y: c.y), CGPoint(x: c.x + 62, y: c.y))
        ring.path = UIBezierPath(ovalIn: CGRect(x: c.x - 30, y: c.y - 30, width: 60, height: 60)).cgPath
        apply(gx: lastG.0, gy: lastG.1, gz: lastG.2)
    }

    /// 重力在手机坐标系里的三个分量（CoreMotion 的 deviceMotion.gravity）
    func apply(gx: Double, gy: Double, gz: Double) {
        lastG = (gx, gy, gz)
        let c = CGPoint(x: bounds.midX, y: bounds.midY)
        let flat = abs(gz) > 0.93
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        fixedL.isHidden = flat; fixedR.isHidden = flat; tilt.isHidden = flat
        ring.isHidden = !flat; dot.isHidden = !flat
        if flat {
            let k: CGFloat = 220
            let dx = CGFloat(gx) * k, dy = CGFloat(-gy) * k
            let r: CGFloat = 7
            dot.path = UIBezierPath(ovalIn: CGRect(x: c.x + dx - r, y: c.y + dy - r, width: r * 2, height: r * 2)).cgPath
            let ok = hypot(gx, gy) < 0.026          // ≈ 1.5°
            let col = ok ? dualYellow : UIColor(white: 1, alpha: 0.85)
            ring.strokeColor = col.cgColor; dot.fillColor = col.cgColor
        } else {
            let roll = atan2(gx, -gy)               // 手机顺时针歪了多少（弧度）
            let deg = abs(roll) * 180 / .pi
            tilt.isHidden = deg > 25                 // 歪太多说明在故意横着 / 斜着拍，不显示
            tilt.setAffineTransform(CGAffineTransform(rotationAngle: CGFloat(-roll)))
            let ok = deg < 0.8
            let col = ok ? dualYellow : UIColor(white: 1, alpha: 0.85)
            tilt.strokeColor = col.cgColor; fixedL.strokeColor = col.cgColor; fixedR.strokeColor = col.cgColor
        }
    }
}
