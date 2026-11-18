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
    /// 单摄时不分「后置 / 前置 / 同时」：直接调当前这颗摄像头的画面
    func setSingle(_ single: Bool, front: Bool) {
        targetSeg.isHidden = single
        st.gradeTarget = single ? (front ? 1 : 0) : 2
    }
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
            pad.setPreset(snap.preset)
            pad.set(x: snap.x, y: snap.y)
            pad.onMove = { [weak self] x, y in self?.edit { $0.setPad(x: x, y: y) } }
            let ss = GlassSlider(); ss.glass = glass; ss.set(snap.str)
            ss.tint = PadImage.sliderColor(snap.preset)          // 滑条的颜色跟着当前底色走（和主页面一样）
            ss.onChange = { [weak self] v in self?.edit { $0.setStrength(v) } }
            strengthSlider = ss
            let sr = circle("arrow.counterclockwise", size: 30) { [weak self] in
                self?.edit { $0.setStrength($0.snapshot().preset.s / 100) }; self?.rebuild() }
            let sRow = UIStackView(arrangedSubviews: [ss, sr]); sRow.spacing = 8; sRow.alignment = .center
            let col = UIStackView(arrangedSubviews: [pad, sRow]); col.axis = .vertical; col.spacing = 4
            pad.translatesAutoresizingMaskIntoConstraints = false
            pad.widthAnchor.constraint(equalToConstant: 118).isActive = true; pad.heightAnchor.constraint(equalToConstant: 118).isActive = true
            ss.heightAnchor.constraint(equalToConstant: 34).isActive = true
            sRow.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
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
                // 质感：标准 / 柔肤 / 光晕 / 胶片（和主页面一样），每种风格各自记住强度
                let seg = GlassSegmented(items: texNames, selected: snap.tex); seg.glass = glass
                seg.onChange = { [weak self] i in self?.edit { $0.setTexStyle(i) }; self?.rebuild() }
                seg.heightAnchor.constraint(equalToConstant: 32).isActive = true
                rows = [seg,
                        sliderRow("强度", min: 0, max: 1, value: snap.tv, set: { $0.setTexStrength($1) }, reset: { $0.resetTexture() })]
            } else {
                rows = [sliderRow("强度", min: 0, max: 1, value: snap.gr, set: { $0.setGrain($1) }, reset: { $0.setGrain(0) })]
            }
            let col = UIStackView(arrangedSubviews: rows); col.axis = .vertical; col.spacing = 8
            row.addArrangedSubview(col)
            row.addArrangedSubview(shutter)
        }
    }
}

/// 每个预设自己的调色盘底图（和主页面 drawPadBg 同一个公式）：灰阶（上亮下暗）+ 右侧的风格色，「鲜明」右下角另有第二色。
enum PadImage {
    private static var cache: [String: UIImage] = [:]
    private static let lock = NSLock()

    static func make(_ p: StylePreset) -> UIImage {
        lock.lock(); defer { lock.unlock() }
        if let i = cache[p.sid] { return i }
        let W = 80
        var px = [UInt8](repeating: 255, count: W * W * 4)
        let t = p.tintUI, t2 = p.tintUI2
        for j in 0..<W {
            for i in 0..<W {
                let u = Double(i) / Double(W - 1), v = 1 - Double(j) / Double(W - 1)
                let g = 0.1 + 0.68 * pow(v, 0.9)
                let m = pow(u, 1.5) * (0.25 + 0.75 * pow(v, 0.8))
                let m2 = t2 != nil ? pow(u, 1.5) * pow(1 - v, 1.1) : 0.0
                for c in 0..<3 {
                    var val = g * (1 - m - m2) + t[c] * (0.55 + 0.7 * v) * m
                    if let t2 = t2 { val += t2[c] * (0.5 + 0.6 * v) * m2 }
                    px[(j * W + i) * 4 + c] = UInt8(max(0, min(255, val * 255)))
                }
            }
        }
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let prov = CGDataProvider(data: Data(px) as CFData),
              let cg = CGImage(width: W, height: W, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: W * 4, space: cs,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue), provider: prov,
                               decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return UIImage() }
        let img = UIImage(cgImage: cg)
        cache[p.sid] = img
        return img
    }

    /// 强度滑条的颜色：有第二色就取两色平均，否则取风格色提亮 25%（主页面 --tc 同一个算法）
    static func sliderColor(_ p: StylePreset) -> UIColor {
        let t = p.tintUI
        if let t2 = p.tintUI2 {
            return UIColor(red: CGFloat((t[0] + t2[0]) / 2), green: CGFloat((t[1] + t2[1]) / 2), blue: CGFloat((t[2] + t2[2]) / 2), alpha: 1)
        }
        return UIColor(red: CGFloat(min(1, t[0] * 1.25)), green: CGFloat(min(1, t[1] * 1.25)), blue: CGFloat(min(1, t[2] * 1.25)), alpha: 1)
    }
}

/// 二维调色盘：横向 = 颜色，纵向 = 色调（上为正）；每个预设自己的彩色底图 + 13×13 点阵（和落点同行同列的点更亮）+ 白色旋钮
private final class PadView: UIView {
    var onMove: ((Double, Double) -> Void)?
    var glass = false
    private var x = 0.0, y = 0.0
    private var sid = ""
    private let image = UIImageView()
    private let dots = DotsLayer()
    private let knob = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 24; layer.cornerCurve = .continuous; clipsToBounds = true
        image.contentMode = .scaleToFill; image.layer.magnificationFilter = .linear
        addSubview(image)
        layer.addSublayer(dots)
        knob.backgroundColor = .white; knob.layer.cornerRadius = 12; knob.isUserInteractionEnabled = false
        knob.layer.shadowColor = UIColor.black.cgColor; knob.layer.shadowOpacity = 0.35; knob.layer.shadowRadius = 4; knob.layer.shadowOffset = CGSize(width: 0, height: 2)
        knob.layer.masksToBounds = false
        addSubview(knob)
        layer.borderWidth = 1; layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
    }
    required init?(coder: NSCoder) { fatalError() }

    func setPreset(_ p: StylePreset) {
        guard p.sid != sid else { return }
        sid = p.sid; image.image = PadImage.make(p)
    }
    func set(x: Double, y: Double) { self.x = x; self.y = y; dots.x = x; dots.y = y; dots.setNeedsDisplay(); layoutKnob() }
    private func layoutKnob() {
        let pad: CGFloat = 11
        let kx = pad + CGFloat(x * 0.5 + 0.5) * (bounds.width - pad * 2), ky = pad + CGFloat((1 - y) / 2) * (bounds.height - pad * 2)
        knob.frame = CGRect(x: kx - 12, y: ky - 12, width: 24, height: 24)
    }
    override func layoutSubviews() { super.layoutSubviews(); image.frame = bounds; dots.frame = bounds; dots.contentsScale = UIScreen.main.scale; dots.setNeedsDisplay(); layoutKnob() }
    private func upd(_ p: CGPoint) {
        let pad: CGFloat = 11
        var nx = Double(((p.x - pad) / max(1, bounds.width - pad * 2) - 0.5) * 2), ny = Double(-((p.y - pad) / max(1, bounds.height - pad * 2) - 0.5) * 2)
        nx = max(-1, min(1, nx)); ny = max(-1, min(1, ny))
        if abs(nx) < 0.04 { nx = 0 }; if abs(ny) < 0.04 { ny = 0 }          // 靠近中线自动吸附到 0
        x = nx; y = ny; dots.x = x; dots.y = y; dots.setNeedsDisplay(); layoutKnob(); onMove?(x, y)
    }
    override func touchesBegan(_ t: Set<UITouch>, with e: UIEvent?) { if let p = t.first?.location(in: self) { upd(p) } }
    override func touchesMoved(_ t: Set<UITouch>, with e: UIEvent?) { if let p = t.first?.location(in: self) { upd(p) } }
}

private final class DotsLayer: CALayer {
    var x = 0.0, y = 0.0
    override func draw(in c: CGContext) {
        let N = 13, pad = bounds.width * 0.1, st = (bounds.width - pad * 2) / CGFloat(N - 1)
        let ci = Int((x * 0.5 + 0.5) * Double(N - 1) + 0.5), cj = Int(((1 - y) / 2) * Double(N - 1) + 0.5)
        for a in 0..<N {
            for b in 0..<N {
                let hot = a == ci || b == cj, mid = a == (N - 1) / 2 || b == (N - 1) / 2
                c.setFillColor(UIColor(white: 1, alpha: hot ? 0.9 : mid ? 0.5 : 0.26).cgColor)
                let r = bounds.width * (hot ? 0.0085 : 0.0065) * 1.6
                c.fillEllipse(in: CGRect(x: pad + CGFloat(a) * st - r, y: pad + CGFloat(b) * st - r, width: r * 2, height: r * 2))
            }
        }
    }
}
