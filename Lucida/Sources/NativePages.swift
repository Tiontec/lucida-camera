import UIKit

/// B1a：「关于 / 版本更新 / 赞赏」三个展示页 + 启动时的「更新了什么」弹窗，全部原生。
/// 内容来自 App 包里的 content/（about.json / updates.json / donate.json + 三张图），由构建脚本从同一份网页源提取，
/// 所以以后改文案、加更新记录仍然只改一处。
enum NativeContent {
    static func json(_ name: String) -> Any? {
        guard let u = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "content"),
              let d = try? Data(contentsOf: u) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }
    static func image(_ name: String) -> UIImage? {
        guard let u = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "content"),
              let d = try? Data(contentsOf: u) else { return nil }
        return UIImage(data: d)
    }

    /// 文案里只用到 <b> 和 <br>：转成富文本
    static func rich(_ html: String, size: CGFloat, color: UIColor, bold: UIColor, lineSpacing: CGFloat = 4) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let ps = NSMutableParagraphStyle(); ps.lineSpacing = lineSpacing
        var isBold = false
        var buf = ""
        func flush() {
            guard !buf.isEmpty else { return }
            out.append(NSAttributedString(string: buf, attributes: [
                .font: UIFont.systemFont(ofSize: size, weight: isBold ? .semibold : .regular),
                .foregroundColor: isBold ? bold : color, .paragraphStyle: ps]))
            buf = ""
        }
        var i = html.startIndex
        while i < html.endIndex {
            if html[i] == "<", let close = html[i...].firstIndex(of: ">") {
                let tag = html[html.index(after: i)..<close].lowercased().replacingOccurrences(of: " ", with: "")
                if tag == "b" { flush(); isBold = true }
                else if tag == "/b" { flush(); isBold = false }
                else if tag == "br" || tag == "br/" { buf += "\n" }
                i = html.index(after: close)
            } else { buf.append(html[i]); i = html.index(after: i) }
        }
        flush()
        return out
    }
}

enum NativePages {
    /// 网页发来 {type:'page', name} 时调用。about / ver / donate = 整页；update = 启动弹窗（每个版本只弹一次）
    static func open(_ name: String, from host: UIViewController) {
        var top: UIViewController = host
        while let p = top.presentedViewController { top = p }
        switch name {
        case "update":
            guard top === host else { return }                   // 别的界面（比如双摄）开着就不打扰
            UpdateDialog.showIfNeeded(on: host)
        case "about": present(NativePageViewController(kind: .about), on: top)
        case "ver": present(NativePageViewController(kind: .ver), on: top)
        case "donate": present(NativePageViewController(kind: .donate), on: top)
        default: break
        }
    }
    private static func present(_ vc: UIViewController, on top: UIViewController) {
        vc.modalPresentationStyle = .overFullScreen           // 网页要留在界面层级里，不能被整个盖掉
        vc.modalTransitionStyle = .crossDissolve
        top.present(vc, animated: true)
    }
}

let pageBG = UIColor(red: 0.043, green: 0.043, blue: 0.051, alpha: 1)

final class NativePageViewController: UIViewController {
    enum Kind { case about, ver, donate }
    private let kind: Kind
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private var modal: UIView?

    init(kind: Kind) { self.kind = kind; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = pageBG; overrideUserInterfaceStyle = .dark
        let back = DualCircleButton(symbol: "chevron.left", size: 40); back.setGlass(DualSettings.shared.glass)
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        let title = UILabel(); title.textColor = .white; title.font = .systemFont(ofSize: 17, weight: .semibold)
        title.text = { () -> String in switch kind { case .about: return "关于"; case .ver: return "版本更新"; case .donate: return "赞赏" } }()
        [back, title, scroll].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; view.addSubview($0) }
        stack.axis = .vertical; stack.spacing = 0; stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false; scroll.addSubview(stack)
        scroll.alwaysBounceVertical = true; scroll.showsVerticalScrollIndicator = false
        NSLayoutConstraint.activate([
            back.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            back.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor), title.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            scroll.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 6), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -40),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20)])
        switch kind { case .about: buildAbout(); case .ver: buildVer(); case .donate: buildDonate() }
    }

    @objc private func close() { dismiss(animated: true) }

    private func space(_ h: CGFloat) { let v = UIView(); v.heightAnchor.constraint(equalToConstant: h).isActive = true; stack.addArrangedSubview(v) }

    // MARK: 关于
    private func buildAbout() {
        guard let a = NativeContent.json("about") as? [String: Any] else { return }
        let logo = UIImageView(image: NativeContent.image("logo")); logo.contentMode = .scaleAspectFill
        logo.layer.cornerRadius = 24; logo.layer.cornerCurve = .continuous; logo.clipsToBounds = true
        logo.translatesAutoresizingMaskIntoConstraints = false
        logo.widthAnchor.constraint(equalToConstant: 96).isActive = true; logo.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let lw = UIStackView(arrangedSubviews: [logo]); lw.alignment = .center; lw.axis = .vertical
        stack.addArrangedSubview(lw); space(14)
        let t = UILabel(); t.text = a["title"] as? String; t.textColor = .white; t.textAlignment = .center
        t.font = .systemFont(ofSize: 30, weight: .semibold)
        t.attributedText = NSAttributedString(string: t.text ?? "", attributes: [.kern: 8, .font: t.font as Any, .foregroundColor: UIColor.white])
        stack.addArrangedSubview(t); space(6)
        let v = UILabel(); v.text = ((a["verPrefix"] as? String) ?? "") + SharedApp.version
        v.textColor = UIColor(white: 1, alpha: 0.5); v.font = .systemFont(ofSize: 13); v.textAlignment = .center
        stack.addArrangedSubview(v)
        for s in (a["sections"] as? [[String: String]]) ?? [] {
            space(22)
            let h = UILabel(); h.text = s["h"]; h.textColor = UIColor(white: 1, alpha: 0.5); h.font = .systemFont(ofSize: 13)
            stack.addArrangedSubview(h); space(8)
            let p = UILabel(); p.numberOfLines = 0
            p.attributedText = NativeContent.rich(s["p"] ?? "", size: 15, color: UIColor(white: 1, alpha: 0.88), bold: .white, lineSpacing: 5)
            stack.addArrangedSubview(p)
        }
        space(26)
        if let d = a["dev"] as? [String: String] { stack.addArrangedSubview(devCard(name: d["name"] ?? "", sub: d["sub"] ?? "")) }
    }

    private func devCard(name: String, sub: String) -> UIView {
        let card = UIView(); card.layer.cornerRadius = 26; card.layer.cornerCurve = .continuous
        card.backgroundColor = UIColor(white: 1, alpha: 0.07)
        card.layer.borderWidth = 1; card.layer.borderColor = UIColor(white: 1, alpha: 0.1).cgColor
        let av = UIImageView(image: NativeContent.image("dev")); av.contentMode = .scaleAspectFill
        av.layer.cornerRadius = 32; av.clipsToBounds = true
        let n = UILabel(); n.attributedText = NSAttributedString(string: name, attributes: [.kern: 4, .font: UIFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: UIColor.white])
        let s = UILabel(); s.text = sub; s.textColor = UIColor(white: 1, alpha: 0.5); s.font = .systemFont(ofSize: 13); s.numberOfLines = 0
        let tx = UIStackView(arrangedSubviews: [n, s]); tx.axis = .vertical; tx.spacing = 4
        [av, tx].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; card.addSubview($0) }
        NSLayoutConstraint.activate([
            av.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16), av.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            av.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            av.widthAnchor.constraint(equalToConstant: 64), av.heightAnchor.constraint(equalToConstant: 64),
            tx.leadingAnchor.constraint(equalTo: av.trailingAnchor, constant: 16), tx.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            tx.centerYAnchor.constraint(equalTo: card.centerYAnchor)])
        return card
    }

    // MARK: 版本更新
    private func buildVer() {
        let head = UIView(); head.layer.cornerRadius = 20; head.layer.cornerCurve = .continuous
        head.backgroundColor = UIColor(white: 1, alpha: 0.07)
        let b = UILabel(); b.text = "澄影 " + SharedApp.version; b.textColor = .white; b.font = .systemFont(ofSize: 20, weight: .semibold)
        let c = UILabel(); c.text = "当前版本"; c.textColor = dualYellow; c.font = .systemFont(ofSize: 13)
        [b, c].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; head.addSubview($0) }
        NSLayoutConstraint.activate([
            b.leadingAnchor.constraint(equalTo: head.leadingAnchor, constant: 18), b.topAnchor.constraint(equalTo: head.topAnchor, constant: 16),
            c.leadingAnchor.constraint(equalTo: b.leadingAnchor), c.topAnchor.constraint(equalTo: b.bottomAnchor, constant: 4),
            c.bottomAnchor.constraint(equalTo: head.bottomAnchor, constant: -16), b.trailingAnchor.constraint(lessThanOrEqualTo: head.trailingAnchor, constant: -18)])
        stack.addArrangedSubview(head)
        for u in (NativeContent.json("updates") as? [[String: Any]]) ?? [] {
            space(14); stack.addArrangedSubview(versionCard(u))
        }
    }

    private func versionCard(_ u: [String: Any]) -> UIView {
        let card = UIView(); card.layer.cornerRadius = 20; card.layer.cornerCurve = .continuous
        card.backgroundColor = UIColor(white: 1, alpha: 0.05)
        let v = UILabel(); v.text = u["v"] as? String; v.textColor = .white; v.font = .systemFont(ofSize: 17, weight: .semibold)
        let d = UILabel(); d.text = u["d"] as? String; d.textColor = UIColor(white: 1, alpha: 0.45); d.font = .systemFont(ofSize: 12)
        let col = UIStackView(arrangedSubviews: [v, d]); col.axis = .vertical; col.spacing = 3
        col.setCustomSpacing(10, after: d)
        for it in (u["items"] as? [String]) ?? [] { col.addArrangedSubview(UpdateDialog.bullet(it)) }
        col.spacing = 3; col.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(col)
        NSLayoutConstraint.activate([
            col.topAnchor.constraint(equalTo: card.topAnchor, constant: 16), col.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            col.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18), col.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18)])
        return card
    }

    // MARK: 赞赏
    private func buildDonate() {
        guard let d = NativeContent.json("donate") as? [String: Any], let hero = d["hero"] as? [String: String] else { return }
        let t = UILabel(); t.text = hero["title"]; t.textColor = .white; t.font = .systemFont(ofSize: 26, weight: .semibold); t.numberOfLines = 0
        let s = UILabel(); s.text = hero["sub"]; s.textColor = UIColor(white: 1, alpha: 0.6); s.font = .systemFont(ofSize: 14); s.numberOfLines = 0
        let col = UIStackView(arrangedSubviews: [t, s]); col.axis = .vertical; col.spacing = 8
        stack.addArrangedSubview(col); space(22)
        let btn = UIButton(type: .system); btn.setTitle("♥  " + (hero["button"] ?? "赞赏"), for: .normal)
        btn.setTitleColor(.black, for: .normal); btn.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold)
        btn.backgroundColor = dualYellow; btn.layer.cornerRadius = 26; btn.layer.cornerCurve = .continuous
        btn.heightAnchor.constraint(equalToConstant: 52).isActive = true
        btn.addTarget(self, action: #selector(openModal), for: .touchUpInside)
        stack.addArrangedSubview(btn); space(26)
        let f = UILabel(); f.text = d["foot"] as? String; f.textColor = UIColor(white: 1, alpha: 0.35); f.font = .systemFont(ofSize: 13); f.textAlignment = .center
        stack.addArrangedSubview(f)
    }

    @objc private func openModal() {
        guard modal == nil, let d = NativeContent.json("donate") as? [String: Any], let m = d["modal"] as? [String: Any] else { return }
        let dim = UIView(frame: view.bounds); dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.backgroundColor = UIColor(red: 0.016, green: 0.016, blue: 0.04, alpha: 0.94)
        let card = UIView(); card.translatesAutoresizingMaskIntoConstraints = false
        let sc = UIScrollView(); sc.translatesAutoresizingMaskIntoConstraints = false; sc.showsVerticalScrollIndicator = false
        dim.addSubview(sc); sc.addSubview(card)
        let x = UIButton(type: .system); x.setImage(UIImage(systemName: "xmark", withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold)), for: .normal)
        x.tintColor = .white; x.translatesAutoresizingMaskIntoConstraints = false
        x.addTarget(self, action: #selector(closeModal), for: .touchUpInside); dim.addSubview(x)

        func label(_ t: String?, _ size: CGFloat, _ w: UIFont.Weight, _ a: CGFloat, kern: CGFloat = 0) -> UILabel {
            let l = UILabel(); l.numberOfLines = 0; l.textAlignment = .center
            l.attributedText = NSAttributedString(string: t ?? "", attributes: [.font: UIFont.systemFont(ofSize: size, weight: w), .kern: kern, .foregroundColor: UIColor(white: 1, alpha: a)])
            return l
        }
        let heart = UIImageView(image: UIImage(systemName: "heart.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .regular)))
        heart.tintColor = UIColor(red: 1, green: 0.4, blue: 0.55, alpha: 1); heart.contentMode = .center
        let qr = UIImageView(image: NativeContent.image("donate_qr")); qr.contentMode = .scaleAspectFill
        qr.layer.cornerRadius = 18; qr.clipsToBounds = true; qr.backgroundColor = .white
        qr.translatesAutoresizingMaskIntoConstraints = false
        qr.widthAnchor.constraint(equalToConstant: 200).isActive = true; qr.heightAnchor.constraint(equalToConstant: 200).isActive = true
        let qw = UIStackView(arrangedSubviews: [qr]); qw.alignment = .center; qw.axis = .vertical
        let chips = UIStackView(); chips.axis = .horizontal; chips.spacing = 7; chips.distribution = .equalSpacing
        for c in (m["chips"] as? [String]) ?? [] {
            let l = PaddedLabel(); l.text = c; l.font = .systemFont(ofSize: 12); l.textColor = UIColor(white: 1, alpha: 0.85)
            l.backgroundColor = UIColor(white: 1, alpha: 0.1); l.layer.cornerRadius = 13; l.clipsToBounds = true; chips.addArrangedSubview(l)
        }
        let cw = UIStackView(arrangedSubviews: [chips]); cw.alignment = .center; cw.axis = .vertical
        let save = UIButton(type: .system); save.setTitle(m["save"] as? String, for: .normal)
        save.setTitleColor(.black, for: .normal); save.backgroundColor = dualYellow; save.layer.cornerRadius = 22
        save.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold); save.heightAnchor.constraint(equalToConstant: 44).isActive = true
        save.addTarget(self, action: #selector(saveQR(_:)), for: .touchUpInside)
        let later = UIButton(type: .system); later.setTitle(m["later"] as? String, for: .normal)
        later.setTitleColor(UIColor(white: 1, alpha: 0.85), for: .normal); later.backgroundColor = UIColor(white: 1, alpha: 0.1); later.layer.cornerRadius = 22
        later.titleLabel?.font = .systemFont(ofSize: 16); later.heightAnchor.constraint(equalToConstant: 44).isActive = true
        later.addTarget(self, action: #selector(later(_:)), for: .touchUpInside)
        let btns = UIStackView(arrangedSubviews: [save, later]); btns.axis = .horizontal; btns.spacing = 10; btns.distribution = .fillEqually

        let col = UIStackView(arrangedSubviews: [heart, label(m["en"] as? String, 11, .medium, 0.45, kern: 3), label(m["title"] as? String, 24, .semibold, 1),
                                                label(m["lead"] as? String, 14, .regular, 0.65), label(m["quote"] as? String, 14, .regular, 0.85),
                                                qw, label(m["scan"] as? String, 12, .regular, 0.45), cw, btns])
        col.axis = .vertical; col.spacing = 12; col.setCustomSpacing(20, after: cw)
        col.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(col)
        NSLayoutConstraint.activate([
            sc.topAnchor.constraint(equalTo: dim.safeAreaLayoutGuide.topAnchor, constant: 40), sc.bottomAnchor.constraint(equalTo: dim.safeAreaLayoutGuide.bottomAnchor),
            sc.leadingAnchor.constraint(equalTo: dim.leadingAnchor), sc.trailingAnchor.constraint(equalTo: dim.trailingAnchor),
            card.topAnchor.constraint(equalTo: sc.contentLayoutGuide.topAnchor), card.bottomAnchor.constraint(equalTo: sc.contentLayoutGuide.bottomAnchor),
            card.centerXAnchor.constraint(equalTo: sc.frameLayoutGuide.centerXAnchor),
            card.widthAnchor.constraint(equalTo: sc.frameLayoutGuide.widthAnchor, multiplier: 0.84),
            col.topAnchor.constraint(equalTo: card.topAnchor, constant: 10), col.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            col.leadingAnchor.constraint(equalTo: card.leadingAnchor), col.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            x.topAnchor.constraint(equalTo: dim.safeAreaLayoutGuide.topAnchor, constant: 6), x.trailingAnchor.constraint(equalTo: dim.trailingAnchor, constant: -14),
            x.widthAnchor.constraint(equalToConstant: 40), x.heightAnchor.constraint(equalToConstant: 40)])
        dim.alpha = 0; view.addSubview(dim); modal = dim
        UIView.animate(withDuration: 0.3) { dim.alpha = 1 }
    }

    @objc private func closeModal() {
        guard let m = modal else { return }
        modal = nil
        UIView.animate(withDuration: 0.25, animations: { m.alpha = 0 }) { _ in m.removeFromSuperview() }
    }

    /// 「下次一定」：收起弹窗，在网页那边弹一句提示（和以前一样）
    @objc private func later(_ b: UIButton) {
        closeModal()
        NativePageToast.say("谢谢你，下次再说 ♥", over: self)
    }

    /// 保存赞赏码：交给系统分享面板（可以「存储图像」/ 发给别人 / 存到文件）
    @objc private func saveQR(_ b: UIButton) {
        guard let img = NativeContent.image("donate_qr"), let data = img.jpegData(compressionQuality: 0.95) else { return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("澄影赞赏码.jpg")
        try? data.write(to: url)
        let a = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        a.popoverPresentationController?.sourceView = b; a.popoverPresentationController?.sourceRect = b.bounds
        present(a, animated: true)
    }
}

/// 简单的页内提示条（原生页面自己用）
enum NativePageToast {
    static func say(_ t: String, over vc: UIViewController) {
        let l = PaddedLabel(); l.text = t; l.textColor = .white; l.font = .systemFont(ofSize: 14, weight: .medium)
        l.backgroundColor = UIColor(white: 0.12, alpha: 0.94); l.layer.cornerRadius = 16; l.clipsToBounds = true
        l.inset = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        l.translatesAutoresizingMaskIntoConstraints = false; l.alpha = 0
        vc.view.addSubview(l)
        NSLayoutConstraint.activate([l.centerXAnchor.constraint(equalTo: vc.view.centerXAnchor),
                                     l.bottomAnchor.constraint(equalTo: vc.view.safeAreaLayoutGuide.bottomAnchor, constant: -40)])
        UIView.animate(withDuration: 0.25, animations: { l.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 1.6, options: [], animations: { l.alpha = 0 }) { _ in l.removeFromSuperview() }
        }
    }
}

/// 启动后的「澄影 x.y.z 更新」弹窗：每个版本只弹一次（看过的版本号记在 lucida.seenVer 里，和网页共用同一份存档）
final class UpdateDialog: UIViewController {
    static func showIfNeeded(on host: UIViewController) {
        let ver = SharedApp.version
        if NativeKV.shared.get("lucida.seenVer") == ver { return }
        guard let ups = NativeContent.json("updates") as? [[String: Any]], let first = ups.first else { return }
        NativeKV.shared.setNative("lucida.seenVer", ver)
        let d = UpdateDialog(); d.entry = first
        d.modalPresentationStyle = .overFullScreen; d.modalTransitionStyle = .crossDissolve
        host.present(d, animated: true)
    }

    var entry: [String: Any] = [:]

    static func bullet(_ html: String) -> UIView {
        let dot = UILabel(); dot.text = "•"; dot.textColor = dualYellow; dot.font = .systemFont(ofSize: 14)
        dot.setContentHuggingPriority(.required, for: .horizontal)
        let t = UILabel(); t.numberOfLines = 0
        t.attributedText = NativeContent.rich(html, size: 14, color: UIColor(white: 1, alpha: 0.78), bold: .white, lineSpacing: 3)
        let r = UIStackView(arrangedSubviews: [dot, t]); r.axis = .horizontal; r.spacing = 8; r.alignment = .firstBaseline
        let w = UIView(); r.translatesAutoresizingMaskIntoConstraints = false; w.addSubview(r)
        NSLayoutConstraint.activate([r.topAnchor.constraint(equalTo: w.topAnchor, constant: 6), r.bottomAnchor.constraint(equalTo: w.bottomAnchor),
                                     r.leadingAnchor.constraint(equalTo: w.leadingAnchor), r.trailingAnchor.constraint(equalTo: w.trailingAnchor)])
        return w
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        overrideUserInterfaceStyle = .dark
        view.backgroundColor = UIColor(white: 0, alpha: 0.5)
        let card = UIView(); card.backgroundColor = UIColor(white: 0.1, alpha: 0.96)
        card.layer.cornerRadius = 26; card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 1; card.layer.borderColor = UIColor(white: 1, alpha: 0.12).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(card)
        let t = UILabel(); t.text = "澄影 \(SharedApp.version) 更新"; t.textColor = .white; t.font = .systemFont(ofSize: 20, weight: .semibold); t.textAlignment = .center
        let d = UILabel(); d.text = "更新时间：" + ((entry["d"] as? String) ?? ""); d.textColor = UIColor(white: 1, alpha: 0.5); d.font = .systemFont(ofSize: 12); d.textAlignment = .center
        let body = UIStackView(); body.axis = .vertical; body.spacing = 0
        for it in (entry["items"] as? [String]) ?? [] { body.addArrangedSubview(UpdateDialog.bullet(it)) }
        let sc = UIScrollView(); sc.showsVerticalScrollIndicator = false; body.translatesAutoresizingMaskIntoConstraints = false; sc.addSubview(body)
        let ok = UIButton(type: .system); ok.setTitle("知道了", for: .normal); ok.setTitleColor(.black, for: .normal)
        ok.titleLabel?.font = .systemFont(ofSize: 17, weight: .semibold); ok.backgroundColor = dualYellow
        ok.layer.cornerRadius = 22; ok.heightAnchor.constraint(equalToConstant: 46).isActive = true
        ok.addTarget(self, action: #selector(done), for: .touchUpInside)
        let col = UIStackView(arrangedSubviews: [t, d, sc, ok]); col.axis = .vertical; col.spacing = 8; col.setCustomSpacing(12, after: d); col.setCustomSpacing(16, after: sc)
        col.translatesAutoresizingMaskIntoConstraints = false; card.addSubview(col)
        let h = sc.heightAnchor.constraint(equalTo: body.heightAnchor); h.priority = .defaultHigh
        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor), card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.88), card.widthAnchor.constraint(lessThanOrEqualToConstant: 360),
            card.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.78),
            col.topAnchor.constraint(equalTo: card.topAnchor, constant: 22), col.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),
            col.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20), col.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            body.topAnchor.constraint(equalTo: sc.contentLayoutGuide.topAnchor), body.bottomAnchor.constraint(equalTo: sc.contentLayoutGuide.bottomAnchor),
            body.leadingAnchor.constraint(equalTo: sc.frameLayoutGuide.leadingAnchor), body.trailingAnchor.constraint(equalTo: sc.frameLayoutGuide.trailingAnchor),
            body.widthAnchor.constraint(equalTo: sc.frameLayoutGuide.widthAnchor), h])
    }

    @objc private func done() { dismiss(animated: true) }
}
