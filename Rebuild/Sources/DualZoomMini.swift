import UIKit

/// 变焦放大取景框（设置 → 变焦放大取景框）：
/// 放大到设定的倍数（10 / 20 / 25 / 30 / 50 / 80 / 100，默认 10）以后，左上角出现一个小框，
/// 用黄色方框标出现在放大到的画面位置（变焦是从画面中心放大的，所以黄框在小框中心）。
final class DualZoomMiniView: UIView {
    private let bg = CAShapeLayer()
    private let box = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(bg)
        layer.addSublayer(box)
        bg.fillColor = UIColor.black.withAlphaComponent(0.45).cgColor
        bg.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
        bg.lineWidth = 1
        box.fillColor = nil
        box.lineWidth = 2
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        bg.path = UIBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 6).cgPath
    }

    /// zoom：当前变焦倍数；threshold：设置里的档位（超过它才显示）
    func update(zoom z: CGFloat, threshold: CGFloat) {
        let show = z > threshold + 0.001
        isHidden = !show
        guard show, z > 0 else { return }
        let w = max(4, bounds.width / z), h = max(4, bounds.height / z)
        let r = CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
        box.path = UIBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 2).cgPath
        box.strokeColor = dualYellow.cgColor
    }
}
