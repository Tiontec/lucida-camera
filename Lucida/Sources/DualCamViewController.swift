import UIKit
import AVFoundation

/// 原生双摄相机界面（全屏、竖屏）：前后摄像头同时工作，拍照 / 录像（带声音），画中画 / 上下分屏。
/// 拍完直接存进系统相册，同时把文件交给网页导入澄影相册。
final class DualCamViewController: UIViewController {
    enum Mode { case photo, video }

    struct Item { var kind: String; var url: URL; var saved: Bool }

    var startMode: Mode = .photo
    /// (拍到的东西, 错误代码, 错误说明)；代码："unsupported" / "denied" / "error"
    var onFinish: (([Item], String?, String?) -> Void)?

    private let engine = DualCamEngine()
    private var mode: Mode = .photo
    private var items: [Item] = []
    private var finished = false
    private var ready = false
    private var timerLabel = UILabel()
    private var recTimer: Timer?
    private var recStart = Date()
    private var saving = 0

    private let stage = UIView()          // 9:16 的取景区域
    private let mainHolder = UIView()
    private let pipHolder = UIView()
    private let shutter = UIButton(type: .custom)
    private let ring = UIView()
    private let thumbBtn = UIButton(type: .system)
    private let tabPhoto = UIButton(type: .system)
    private let tabVideo = UIButton(type: .system)
    private let toast = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        mode = startMode
        buildUI()
        spinner.startAnimating()
        requestPermissions { [weak self] videoOK, audioOK in
            guard let self = self else { return }
            guard videoOK else { self.finish(code: "denied", msg: "没有相机权限"); return }
            self.engine.sessionQueue.async {
                do {
                    try self.engine.configure(wantAudio: audioOK)
                    DispatchQueue.main.async { self.attachPreviews(); self.engine.start() }
                } catch let e as DualError {
                    switch e {
                    case .unsupported(let m): DispatchQueue.main.async { self.finish(code: "unsupported", msg: m) }
                    case .failed(let m): DispatchQueue.main.async { self.finish(code: "error", msg: m) }
                    }
                } catch {
                    DispatchQueue.main.async { self.finish(code: "error", msg: error.localizedDescription) }
                }
            }
        }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(runtimeError(_:)), name: .AVCaptureSessionRuntimeError, object: engine.session)
        nc.addObserver(self, selector: #selector(interrupted(_:)), name: .AVCaptureSessionWasInterrupted, object: engine.session)
        nc.addObserver(self, selector: #selector(interruptionEnded(_:)), name: .AVCaptureSessionInterruptionEnded, object: engine.session)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    private func requestPermissions(_ done: @escaping (Bool, Bool) -> Void) {
        func ask(_ type: AVMediaType, _ cb: @escaping (Bool) -> Void) {
            switch AVCaptureDevice.authorizationStatus(for: type) {
            case .authorized: cb(true)
            case .notDetermined: AVCaptureDevice.requestAccess(for: type) { ok in DispatchQueue.main.async { cb(ok) } }
            default: cb(false)
            }
        }
        ask(.video) { v in
            guard v else { done(false, false); return }
            ask(.audio) { a in done(true, a) }
        }
    }

    // MARK: - 界面

    private func buildUI() {
        stage.backgroundColor = .black
        stage.clipsToBounds = true
        stage.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stage)
        // 9:16 取景区，贴着顶部居中（高屏幕下方留给控制区）
        let ratio = stage.heightAnchor.constraint(equalTo: stage.widthAnchor, multiplier: 16.0 / 9.0)
        ratio.priority = .required
        let wMax = stage.widthAnchor.constraint(equalTo: view.widthAnchor)
        wMax.priority = .defaultHigh
        let hMax = stage.heightAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, constant: -150)
        NSLayoutConstraint.activate([
            stage.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stage.topAnchor.constraint(equalTo: view.topAnchor),
            ratio, wMax, hMax,
            stage.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor)
        ])
        for h in [mainHolder, pipHolder] { h.backgroundColor = .black; h.clipsToBounds = true; stage.addSubview(h) }
        pipHolder.layer.borderColor = UIColor(white: 1, alpha: 0.92).cgColor
        pipHolder.layer.borderWidth = 2
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panPip(_:)))
        pipHolder.addGestureRecognizer(pan)
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapPip))
        pipHolder.addGestureRecognizer(tap)

        // 顶部按钮
        let top = UIStackView()
        top.axis = .horizontal; top.distribution = .equalSpacing; top.alignment = .center
        top.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(top)
        NSLayoutConstraint.activate([
            top.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 14),
            top.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -14),
            top.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6)
        ])
        top.addArrangedSubview(roundBtn("xmark", #selector(closeTapped)))
        top.addArrangedSubview(roundBtn("rectangle.split.1x2", #selector(toggleStyle)))
        top.addArrangedSubview(roundBtn("arrow.triangle.2.circlepath", #selector(swapMain)))
        top.addArrangedSubview(roundBtn("arrow.left.and.right.righttriangle.left.righttriangle.right", #selector(toggleMirror)))
        top.addArrangedSubview(roundBtn("bolt.fill", #selector(toggleTorch)))

        timerLabel.text = "● 00:00"
        timerLabel.textColor = .white
        timerLabel.font = .monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        timerLabel.backgroundColor = UIColor(red: 0.9, green: 0.1, blue: 0.1, alpha: 0.85)
        timerLabel.textAlignment = .center
        timerLabel.layer.cornerRadius = 12; timerLabel.clipsToBounds = true
        timerLabel.isHidden = true
        timerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(timerLabel)
        NSLayoutConstraint.activate([
            timerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            timerLabel.topAnchor.constraint(equalTo: top.bottomAnchor, constant: 10),
            timerLabel.widthAnchor.constraint(equalToConstant: 92), timerLabel.heightAnchor.constraint(equalToConstant: 26)
        ])

        // 底部：模式 + 快门 + 缩略图
        let bottom = UIView()
        bottom.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bottom)
        NSLayoutConstraint.activate([
            bottom.leadingAnchor.constraint(equalTo: view.leadingAnchor), bottom.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottom.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            bottom.heightAnchor.constraint(equalToConstant: 150)
        ])
        for (b, t, sel) in [(tabPhoto, "照片", #selector(selectPhoto)), (tabVideo, "视频", #selector(selectVideo))] {
            b.setTitle(t, for: .normal); b.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
            b.addTarget(self, action: sel, for: .touchUpInside)
            b.translatesAutoresizingMaskIntoConstraints = false
            bottom.addSubview(b)
        }
        NSLayoutConstraint.activate([
            tabPhoto.centerXAnchor.constraint(equalTo: bottom.centerXAnchor, constant: -36),
            tabVideo.centerXAnchor.constraint(equalTo: bottom.centerXAnchor, constant: 36),
            tabPhoto.topAnchor.constraint(equalTo: bottom.topAnchor, constant: 4),
            tabVideo.topAnchor.constraint(equalTo: bottom.topAnchor, constant: 4)
        ])
        ring.layer.borderColor = UIColor.white.cgColor; ring.layer.borderWidth = 4; ring.layer.cornerRadius = 36
        ring.isUserInteractionEnabled = false
        ring.translatesAutoresizingMaskIntoConstraints = false
        shutter.layer.cornerRadius = 30; shutter.backgroundColor = .white
        shutter.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        shutter.translatesAutoresizingMaskIntoConstraints = false
        bottom.addSubview(ring); bottom.addSubview(shutter)
        NSLayoutConstraint.activate([
            ring.centerXAnchor.constraint(equalTo: bottom.centerXAnchor), ring.bottomAnchor.constraint(equalTo: bottom.bottomAnchor, constant: -22),
            ring.widthAnchor.constraint(equalToConstant: 72), ring.heightAnchor.constraint(equalToConstant: 72),
            shutter.centerXAnchor.constraint(equalTo: ring.centerXAnchor), shutter.centerYAnchor.constraint(equalTo: ring.centerYAnchor),
            shutter.widthAnchor.constraint(equalToConstant: 60), shutter.heightAnchor.constraint(equalToConstant: 60)
        ])
        thumbBtn.setTitle("0", for: .normal)
        thumbBtn.setTitleColor(.white, for: .normal)
        thumbBtn.titleLabel?.font = .systemFont(ofSize: 17, weight: .bold)
        thumbBtn.backgroundColor = UIColor(white: 1, alpha: 0.16)
        thumbBtn.layer.cornerRadius = 12
        thumbBtn.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        thumbBtn.translatesAutoresizingMaskIntoConstraints = false
        bottom.addSubview(thumbBtn)
        NSLayoutConstraint.activate([
            thumbBtn.centerYAnchor.constraint(equalTo: ring.centerYAnchor), thumbBtn.trailingAnchor.constraint(equalTo: bottom.trailingAnchor, constant: -34),
            thumbBtn.widthAnchor.constraint(equalToConstant: 48), thumbBtn.heightAnchor.constraint(equalToConstant: 48)
        ])

        toast.textColor = .white; toast.font = .systemFont(ofSize: 14, weight: .medium)
        toast.backgroundColor = UIColor(white: 0, alpha: 0.6); toast.textAlignment = .center
        toast.layer.cornerRadius = 14; toast.clipsToBounds = true; toast.alpha = 0; toast.numberOfLines = 2
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor), toast.bottomAnchor.constraint(equalTo: bottom.topAnchor, constant: -8),
            toast.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -40)
        ])
        spinner.color = .white; spinner.center = view.center
        spinner.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
        view.addSubview(spinner)
        paintMode()
    }

    private func roundBtn(_ symbol: String, _ sel: Selector) -> UIButton {
        let b = UIButton(type: .system)
        b.setImage(UIImage(systemName: symbol), for: .normal)
        b.tintColor = .white
        b.backgroundColor = UIColor(white: 0, alpha: 0.4)
        b.layer.cornerRadius = 20
        b.addTarget(self, action: sel, for: .touchUpInside)
        b.translatesAutoresizingMaskIntoConstraints = false
        b.widthAnchor.constraint(equalToConstant: 40).isActive = true
        b.heightAnchor.constraint(equalToConstant: 40).isActive = true
        return b
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPreviews()
    }

    private func attachPreviews() {
        guard let bl = engine.backPreview, let fl = engine.frontPreview else { return }
        spinner.stopAnimating()
        mainHolder.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        pipHolder.layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        mainHolder.layer.addSublayer(bl)
        pipHolder.layer.addSublayer(fl)
        ready = true
        layoutPreviews()
    }

    /// 预览的摆放和成品里的摆放用同一份 DualLayout 算出来
    private func layoutPreviews() {
        guard ready, let bl = engine.backPreview, let fl = engine.frontPreview else { return }
        let L = engine.layout, W = stage.bounds.width, H = stage.bounds.height
        guard W > 0 else { return }
        let (mr, sr) = L.rects(W, H)
        mainHolder.frame = mr; pipHolder.frame = sr
        let mainIsBack = L.backIsMain
        let mainLayer = mainIsBack ? bl : fl, secLayer = mainIsBack ? fl : bl
        if mainLayer.superlayer !== mainHolder.layer { mainLayer.removeFromSuperlayer(); mainHolder.layer.addSublayer(mainLayer) }
        if secLayer.superlayer !== pipHolder.layer { secLayer.removeFromSuperlayer(); pipHolder.layer.addSublayer(secLayer) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        mainLayer.frame = mainHolder.bounds; secLayer.frame = pipHolder.bounds
        CATransaction.commit()
        pipHolder.layer.cornerRadius = L.style == .pip ? sr.width * 0.16 : 0
        pipHolder.layer.borderWidth = L.style == .pip ? max(2, W * 0.006) : 0
    }

    // MARK: - 操作

    @objc private func panPip(_ g: UIPanGestureRecognizer) {
        var L = engine.layout
        guard L.style == .pip else { return }
        let W = stage.bounds.width, H = stage.bounds.height
        let (_, sr) = L.rects(W, H)
        let m = W * 0.04
        let rx = max(1, W - sr.width - 2 * m), ry = max(1, H - sr.height - 2 * m)
        let t = g.translation(in: stage)
        g.setTranslation(.zero, in: stage)
        L.pipX = min(1, max(0, L.pipX + t.x / rx)); L.pipY = min(1, max(0, L.pipY + t.y / ry))
        engine.layout = L
        layoutPreviews()
    }

    @objc private func tapPip() {
        var L = engine.layout
        if L.style == .pip { L.pipW = L.pipW < 0.4 ? 0.46 : 0.32 }
        engine.layout = L; layoutPreviews()
    }

    @objc private func toggleStyle() {
        guard !engine.isRecording else { say("录像中不能切换布局"); return }
        var L = engine.layout
        L.style = L.style == .pip ? .split : .pip
        engine.layout = L; layoutPreviews()
        say(L.style == .pip ? "画中画" : "上下分屏")
    }

    @objc private func swapMain() {
        var L = engine.layout
        L.backIsMain.toggle()
        engine.layout = L; layoutPreviews()
    }

    @objc private func toggleMirror() {
        var L = engine.layout
        L.mirrorFront.toggle()
        engine.layout = L
        say(L.mirrorFront ? "前置镜像：开（和预览一致）" : "前置镜像：关")
    }

    private var torchOn = false
    @objc private func toggleTorch() {
        torchOn.toggle()
        engine.setTorch(torchOn)
        say(torchOn ? "手电筒：开" : "手电筒：关")
    }

    @objc private func selectPhoto() { guard !engine.isRecording else { return }; mode = .photo; paintMode() }
    @objc private func selectVideo() { guard !engine.isRecording else { return }; mode = .video; paintMode() }

    private func paintMode() {
        tabPhoto.setTitleColor(mode == .photo ? UIColor.systemYellow : UIColor(white: 1, alpha: 0.7), for: .normal)
        tabVideo.setTitleColor(mode == .video ? UIColor.systemYellow : UIColor(white: 1, alpha: 0.7), for: .normal)
        shutter.backgroundColor = mode == .video ? UIColor(red: 0.92, green: 0.2, blue: 0.2, alpha: 1) : .white
    }

    @objc private func shutterTapped() {
        guard ready else { return }
        if mode == .photo { takePhoto() } else { engine.isRecording ? stopRecording() : startRecording() }
    }

    private func newFile(_ ext: String) -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        return SchemeHandler.outDir.appendingPathComponent("澄影双摄_\(f.string(from: Date()))_\(Int.random(in: 100...999)).\(ext)")
    }

    private func takePhoto() {
        let url = newFile("jpg")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let flash = UIView(frame: stage.bounds); flash.backgroundColor = .white; stage.addSubview(flash)
        UIView.animate(withDuration: 0.25, animations: { flash.alpha = 0 }) { _ in flash.removeFromSuperview() }
        engine.takePhoto(to: url) { [weak self] ok, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if ok { self.store(url, isVideo: false) } else { self.say("拍照失败：\(err ?? "未知错误")") }
            }
        }
    }

    private func startRecording() {
        let url = newFile("mp4")
        engine.startRecording(to: url, audio: true)
        recStart = Date()
        timerLabel.isHidden = false; timerLabel.text = "● 00:00"
        recTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let s = Int(Date().timeIntervalSince(self.recStart))
            self.timerLabel.text = String(format: "● %02d:%02d", s / 60, s % 60)
        }
        shutter.layer.cornerRadius = 10
        UIView.animate(withDuration: 0.2) { self.shutter.transform = CGAffineTransform(scaleX: 0.55, y: 0.55) }
        say(engine.hasAudio ? "开始录像（带声音）" : "开始录像（没有麦克风权限，只录画面）")
    }

    private func stopRecording() {
        recTimer?.invalidate(); recTimer = nil
        timerLabel.isHidden = true
        shutter.layer.cornerRadius = 30
        UIView.animate(withDuration: 0.2) { self.shutter.transform = .identity }
        engine.stopRecording { [weak self] url, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let u = url { self.store(u, isVideo: true) } else { self.say("录像失败：\(err ?? "未知错误")") }
            }
        }
    }

    /// 存进系统相册 + 记入结果
    private func store(_ url: URL, isVideo: Bool) {
        saving += 1
        PhotoSaver.save(file: url, isVideo: isVideo) { [weak self] ok, msg in
            guard let self = self else { return }
            self.saving -= 1
            self.items.append(Item(kind: isVideo ? "video" : "photo", url: url, saved: ok))
            self.thumbBtn.setTitle("\(self.items.count)", for: .normal)
            self.say(ok ? (isVideo ? "视频已存入系统相册" : "照片已存入系统相册") : "没存进系统相册：\(msg ?? "")（仍会导入澄影相册）")
        }
    }

    private func say(_ t: String) {
        toast.text = "  \(t)  "
        toast.alpha = 1
        let token = Date().timeIntervalSince1970
        toast.tag = Int(token)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self = self, self.toast.tag == Int(token) else { return }
            UIView.animate(withDuration: 0.3) { self.toast.alpha = 0 }
        }
    }

    // MARK: - 关闭

    @objc private func closeTapped() {
        if engine.isRecording { stopRecordingThenClose(); return }
        finish(code: nil, msg: nil)
    }

    private func stopRecordingThenClose() {
        recTimer?.invalidate(); recTimer = nil
        engine.stopRecording { [weak self] url, _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if let u = url {
                    self.saving += 1
                    PhotoSaver.save(file: u, isVideo: true) { ok, _ in
                        self.saving -= 1
                        self.items.append(Item(kind: "video", url: u, saved: ok))
                        self.finish(code: nil, msg: nil)
                    }
                } else { self.finish(code: nil, msg: nil) }
            }
        }
    }

    private func finish(code: String?, msg: String?) {
        guard !finished else { return }
        if saving > 0 {   // 还有文件在写进系统相册：等一下
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.finish(code: code, msg: msg) }
            return
        }
        finished = true
        if torchOn { engine.setTorch(false) }
        engine.stop()
        let result = items
        dismiss(animated: true) { [weak self] in
            // 拍到过东西就按成功算；一张都没有才带上错误
            self?.onFinish?(result, result.isEmpty ? code : nil, result.isEmpty ? msg : nil)
        }
    }

    // MARK: - 系统事件

    @objc private func runtimeError(_ n: Notification) {
        engine.sessionQueue.async { [weak self] in
            guard let self = self, !self.finished else { return }
            if !self.engine.session.isRunning { self.engine.session.startRunning() }
        }
    }
    @objc private func interrupted(_ n: Notification) { DispatchQueue.main.async { self.say("相机被系统暂时占用…") } }
    @objc private func interruptionEnded(_ n: Notification) { DispatchQueue.main.async { self.say("相机已恢复") } }
}
