import UIKit

/// 取景框里的对焦框：黄色方框 + 旁边一条带太阳的曝光滑轨（和系统相机一样：上拉变亮、下拉变暗）。
/// 长按后显示「AE/AF 锁定」并一直保留，直到再点一下。
final class FocusIndicator: UIView {
    private(set) var locked = false
    var bias: Float = 0
    var range: (Float, Float) = (-2, 2)
    private var side: CGFloat = 1          // 1 = 滑轨在右，-1 = 在左
    private var hideTimer: Timer?
    private let boxSize: CGFloat = 76
    private let sideW: CGFloat = 40
    private let trackH: CGFloat = 150
    private let yellow = UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)

    var isVisible: Bool { !isHidden && alpha > 0.01 }

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: 76 + 40, height: 150))
        backgroundColor = .clear; isUserInteractionEnabled = false; isOpaque = false
    }
    required init?(coder: NSCoder) { fatalError() }

    /// p：对焦点（取景框坐标）；bounds：取景框尺寸，用来避免跑出画面
    func show(at p: CGPoint, in area: CGRect, locked lock: Bool) {
        locked = lock; bias = 0
        let w = boxSize + sideW, h = trackH
        side = (p.x + boxSize / 2 + sideW > area.width - 4) ? -1 : 1
        let boxX = side > 0 ? 0 : sideW
        var ox = p.x - boxSize / 2 - boxX, oy = p.y - h / 2
        ox = min(max(ox, 2 - boxX), area.width - boxSize - boxX - 2)
        oy = min(max(oy, 2), area.height - h - 2)
        bounds = CGRect(x: 0, y: 0, width: w, height: h)
        frame = CGRect(x: ox, y: oy, width: w, height: h)
        hideTimer?.invalidate()
        isHidden = false; alpha = 1
        transform = CGAffineTransform(scaleX: 1.25, y: 1.25)
        setNeedsDisplay()
        UIView.animate(withDuration: 0.18) { self.transform = .identity }
        keepAlive()
    }

    func keepAlive() {
        hideTimer?.invalidate()
        guard !locked else { return }
        hideTimer = Timer.scheduledTimer(withTimeInterval: 2.8, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            UIView.animate(withDuration: 0.3, animations: { self.alpha = 0 }) { _ in if self.alpha < 0.05 { self.isHidden = true } }
        }
    }

    func hide() {
        hideTimer?.invalidate(); hideTimer = nil
        locked = false; isHidden = true; alpha = 0
    }

    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        let boxX: CGFloat = side > 0 ? 0 : sideW
        let box = CGRect(x: boxX, y: (bounds.height - boxSize) / 2, width: boxSize, height: boxSize)
        c.setStrokeColor(yellow.cgColor); c.setLineWidth(1.5)
        c.stroke(box)
        // 四边中点小刻度（系统对焦框的样子）
        let t: CGFloat = 6
        c.setLineWidth(1.5)
        c.move(to: CGPoint(x: box.midX, y: box.minY)); c.addLine(to: CGPoint(x: box.midX, y: box.minY + t))
        c.move(to: CGPoint(x: box.midX, y: box.maxY)); c.addLine(to: CGPoint(x: box.midX, y: box.maxY - t))
        c.move(to: CGPoint(x: box.minX, y: box.midY)); c.addLine(to: CGPoint(x: box.minX + t, y: box.midY))
        c.move(to: CGPoint(x: box.maxX, y: box.midY)); c.addLine(to: CGPoint(x: box.maxX - t, y: box.midY))
        c.strokePath()
        // 曝光滑轨 + 太阳
        let tx = side > 0 ? box.maxX + 20 : box.minX - 20
        let top: CGFloat = 8, bot = bounds.height - 8
        c.setLineWidth(1.2)
        c.move(to: CGPoint(x: tx, y: top)); c.addLine(to: CGPoint(x: tx, y: bot)); c.strokePath()
        let span = max(0.01, range.1 - range.0)
        let tt = CGFloat((bias - range.0) / span)
        let sy = bot - tt * (bot - top)
        let r: CGFloat = 9
        c.setFillColor(yellow.cgColor)
        c.fillEllipse(in: CGRect(x: tx - r / 2, y: sy - r / 2, width: r, height: r))
        c.setLineWidth(1.4)
        for k in 0..<8 {
            let a = CGFloat(k) * .pi / 4
            c.move(to: CGPoint(x: tx + cos(a) * (r / 2 + 3), y: sy + sin(a) * (r / 2 + 3)))
            c.addLine(to: CGPoint(x: tx + cos(a) * (r / 2 + 6), y: sy + sin(a) * (r / 2 + 6)))
        }
        c.strokePath()
        if locked {
            let text = "AE/AF 锁定" as NSString
            let at: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11, weight: .bold), .foregroundColor: UIColor.black]
            let sz = text.size(withAttributes: at)
            let pill = CGRect(x: box.midX - (sz.width + 14) / 2, y: box.minY - 22, width: sz.width + 14, height: 18)
            c.setFillColor(yellow.cgColor)
            UIBezierPath(roundedRect: pill, cornerRadius: 9).fill()
            text.draw(at: CGPoint(x: pill.minX + 7, y: pill.minY + 2), withAttributes: at)
        }
    }
}
