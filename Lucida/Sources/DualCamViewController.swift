import UIKit
import AVFoundation

/// 圆形图标按钮：普通样式 = 半透明灰底；液态玻璃开启 = iOS 26 系统 UIGlassEffect（低版本退回毛玻璃）
final class DualRoundButton: UIButton {
    private let bg = UIVisualEffectView(effect: nil)
    var active = false { didSet { tintColor = active ? UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1) : .white } }
    init(symbol: String, size: CGFloat) {
        super.init(frame: .zero)
        bg.isUserInteractionEnabled = false; bg.clipsToBounds = true; bg.layer.cornerRadius = size / 2
        insertSubview(bg, at: 0)
        setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.42, weight: .semibold)), for: .normal)
        tintColor = .white
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: size).isActive = true
        heightAnchor.constraint(equalToConstant: size).isActive = true
        setGlass(false)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() { super.layoutSubviews(); bg.frame = bounds; sendSubviewToBack(bg) }
    func setSymbol(_ n: String) {
        setImage(UIImage(systemName: n, withConfiguration: UIImage.SymbolConfiguration(pointSize: bounds.width * 0.42, weight: .semibold)), for: .normal)
    }
    func setGlass(_ on: Bool) {
        if on {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) { bg.effect = UIGlassEffect(); bg.backgroundColor = nil; return }
            #endif
            bg.effect = UIBlurEffect(style: .systemThinMaterialDark); bg.backgroundColor = UIColor(white: 1, alpha: 0.06)
        } else { bg.effect = nil; bg.backgroundColor = UIColor(white: 1, alpha: 0.16) }
    }
}

/// 原生双摄相机界面：取景（引擎合成的画面）+ 顶部 / 底部控件 + 变焦转盘 + 调色面板 + 设置 + 相册。
final class DualCamViewController: UIViewController {
    enum Mode { case photo, video }
    struct Item { var kind: String; var url: URL; var saved: Bool }

    var startMode: Mode = .photo
    var onFinish: (([Item], String?, String?) -> Void)?

    private let engine = DualCamEngine()
    private let st = DualSettings.shared
    private var mode: Mode = .photo
    private var items: [Item] = []
    private var finished = false, ready = false, reconfiguring = false
    private var saving = 0
    private var wantUW = false
    private var torchOn = false
    private var recTimer: Timer?
    private var recStart = Date()
    private let yellow = UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)

    private let stage = UIView()
    private let zoomCtl = DualZoomControl()
    private let bottomBar = UIView()
    private let shutter = UIButton(type: .custom)
    private let shutterRing = UIView()
    private let thumb = UIButton(type: .custom)
    private let tabPhoto = UIButton(type: .system), tabVideo = UIButton(type: .system)
    private let toast = UILabel()
    private let timerLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let specPill = UIButton(type: .system)
    private let specPanel = UIView()
    private var specSegs: [UISegmentedControl] = []
    private var roundBtns: [DualRoundButton] = []
    private var btnBack: DualRoundButton!, btnLive: DualRoundButton!, btnPalette: DualRoundButton!, btnSettings: DualRoundButton!
    private var btnLayout: DualRoundButton!, btnShape: DualRoundButton!, btnMirror: DualRoundButton!, btnTorch: DualRoundButton!, btnSwap: DualRoundButton!
    private let palette = DualPalettePanel()
    private let readout = UILabel(), presetLabel = UILabel()
    private var paletteOpen = false
    private var stageFrame = CGRect.zero
    private var lastAspect: CGFloat = 0
    private var pipDragStart = CGPoint.zero

    override var prefersStatusBarHidden: Bool { true }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        mode = startMode
        engine.layout.backIsMain = st.backIsMain
        engine.layout.mirrorFront = st.mirror
        engine.layout.border = st.border
        engine.layout.style = st.pipStyleSplit ? .split : .pip
        buildUI()
        applyGlass()
        spinner.startAnimating()
        requestPermissions { [weak self] videoOK, audioOK in
            guard let self = self else { return }
            guard videoOK else { self.finish(code: "denied", msg: "没有相机权限"); return }
            self.view.layoutIfNeeded()
            let spec = self.currentSpec()
            self.engine.sessionQueue.async {
                do {
                    let note = try self.engine.configure(spec, wantAudio: audioOK)
                    DispatchQueue.main.async {
                        self.afterConfigured(note)
                        self.engine.start()
                    }
                } catch let e as DualError {
                    switch e {
                    case .unsupported(let m): DispatchQueue.main.async { self.finish(code: "unsupported", msg: m) }
                    case .failed(let m): DispatchQueue.main.async { self.finish(code: "error", msg: m) }
                    }
                } catch { DispatchQueue.main.async { self.finish(code: "error", msg: error.localizedDescription) } }
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
        ask(.video) { v in guard v else { done(false, false); return }; ask(.audio) { a in done(true, a) } }
    }

    private func currentSpec() -> DualSpec {
        var s = DualSpec(); s.res = st.res; s.fps = st.fps; s.full = st.fullSensor; s.ultraWide = wantUW
        s.aspect = stageFrame.height > 0 ? stageFrame.width / stageFrame.height : 9.0 / 16.0
        return s
    }

    private func afterConfigured(_ note: String) {
        spinner.stopAnimating(); ready = true
        engine.liveEnabled = st.liveOn && mode == .photo
        if !note.isEmpty { say(note, 4.5) }
        syncZoomRange(resetTo: nil)
        syncSpecPill(); syncButtons()
        engine.layout.pipRadius = pipRadiusValue()
    }

    // MARK: - 布局

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let W = view.bounds.width, H = view.bounds.height
        let top = view.safeAreaInsets.top, bot = max(view.safeAreaInsets.bottom, 12)
        let barH: CGFloat = 178 + bot
        let stageTop = top + 52
        let avail = H - stageTop - barH
        var sw = W, sh: CGFloat
        if st.fullSensor { sh = min(W * 4 / 3, avail); sw = sh * 3 / 4 }
        else { sh = min(W * 16 / 9, avail) }
        let f = CGRect(x: ((W - sw) / 2).rounded(), y: stageTop, width: sw.rounded(), height: sh.rounded())
        if f != stageFrame {
            stageFrame = f
            stage.frame = f
            engine.previewLayer.frame = stage.bounds
            zoomCtl.frame = CGRect(x: f.minX, y: f.maxY - 160, width: f.width, height: 160)
        }
        bottomBar.frame = CGRect(x: 0, y: H - barH, width: W, height: barH)
        palette.frame = CGRect(x: 0, y: H - 290 - bot, width: W, height: 290 + bot)
        spinner.center = stage.center
        layoutBottom()
    }

    // MARK: - 界面搭建

    private func rb(_ sym: String, _ size: CGFloat = 40, _ sel: Selector) -> DualRoundButton {
        let b = DualRoundButton(symbol: sym, size: size)
        b.addTarget(self, action: sel, for: .touchUpInside)
        roundBtns.append(b); return b
    }

    private func buildUI() {
        stage.backgroundColor = .black; stage.clipsToBounds = true
        stage.layer.addSublayer(engine.previewLayer)
        view.addSubview(stage)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panPip(_:)))
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapStage(_:)))
        let swipeL = UISwipeGestureRecognizer(target: self, action: #selector(swipePreset(_:))); swipeL.direction = .left
        let swipeR = UISwipeGestureRecognizer(target: self, action: #selector(swipePreset(_:))); swipeR.direction = .right
        [pan, tap, swipeL, swipeR].forEach { stage.addGestureRecognizer($0) }
        view.addSubview(zoomCtl)
        zoomCtl.onZoom = { [weak self] z in guard let self = self else { return }; self.engine.setZoom(back: self.mainIsBack, z) }
        zoomCtl.onSettle = { [weak self] z in self?.zoomSettled(z) }

        // 顶部
        btnBack = rb("chevron.left", 40, #selector(closeTapped))
        btnLive = rb("livephoto", 40, #selector(toggleLive))
        btnPalette = rb("circle.hexagongrid.fill", 40, #selector(togglePalette))
        btnSettings = rb("gearshape.fill", 40, #selector(openSettings))
        specPill.setTitleColor(.white, for: .normal); specPill.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        specPill.backgroundColor = UIColor(white: 1, alpha: 0.16); specPill.layer.cornerRadius = 18
        specPill.contentEdgeInsets = UIEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        specPill.addTarget(self, action: #selector(toggleSpecPanel), for: .touchUpInside)
        let right = UIStackView(arrangedSubviews: [btnLive, btnPalette, btnSettings]); right.spacing = 8
        let left = UIStackView(arrangedSubviews: [btnBack, specPill]); left.spacing = 8; left.alignment = .center
        for s in [left, right] {
            s.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(s)
            s.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4).isActive = true
        }
        specPill.heightAnchor.constraint(equalToConstant: 36).isActive = true
        left.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14).isActive = true
        right.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14).isActive = true
        buildSpecPanel()

        // 取景区信息
        for l in [readout, presetLabel] {
            l.textColor = .white; l.font = .systemFont(ofSize: 13, weight: .semibold); l.textAlignment = .center
            l.backgroundColor = UIColor(white: 0, alpha: 0.45); l.layer.cornerRadius = 13; l.clipsToBounds = true; l.isHidden = true
            l.translatesAutoresizingMaskIntoConstraints = false; stage.addSubview(l)
            l.centerXAnchor.constraint(equalTo: stage.centerXAnchor).isActive = true
            l.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
        readout.topAnchor.constraint(equalTo: stage.topAnchor, constant: 10).isActive = true
        readout.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        presetLabel.bottomAnchor.constraint(equalTo: stage.bottomAnchor, constant: -170).isActive = true
        presetLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 90).isActive = true
        timerLabel.textColor = .white; timerLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .semibold)
        timerLabel.backgroundColor = UIColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 1); timerLabel.layer.cornerRadius = 12
        timerLabel.clipsToBounds = true; timerLabel.textAlignment = .center; timerLabel.isHidden = true
        timerLabel.translatesAutoresizingMaskIntoConstraints = false; stage.addSubview(timerLabel)
        timerLabel.topAnchor.constraint(equalTo: stage.topAnchor, constant: 10).isActive = true
        timerLabel.centerXAnchor.constraint(equalTo: stage.centerXAnchor).isActive = true
        timerLabel.widthAnchor.constraint(equalToConstant: 92).isActive = true; timerLabel.heightAnchor.constraint(equalToConstant: 24).isActive = true

        // 底部（纯黑平面）
        bottomBar.backgroundColor = .black
        view.addSubview(bottomBar)
        btnLayout = rb("rectangle.split.1x2", 34, #selector(toggleStyle))
        btnShape = rb("square.on.square", 34, #selector(cycleShape))
        btnMirror = rb("arrow.left.and.right.righttriangle.left.righttriangle.right", 34, #selector(toggleMirror))
        btnTorch = rb("bolt.fill", 34, #selector(toggleTorch))
        btnSwap = rb("arrow.triangle.2.circlepath", 46, #selector(swapMain))
        for b in [btnLayout!, btnShape!, btnMirror!, btnTorch!, btnSwap!] { bottomBar.addSubview(b); b.translatesAutoresizingMaskIntoConstraints = true }
        for (b, t) in [(tabVideo, "视频"), (tabPhoto, "照片")] {
            b.setTitle(t, for: .normal); b.titleLabel?.font = .systemFont(ofSize: 15, weight: .bold)
            b.addTarget(self, action: #selector(tabTapped(_:)), for: .touchUpInside); bottomBar.addSubview(b)
        }
        shutterRing.layer.borderColor = UIColor.white.cgColor; shutterRing.layer.borderWidth = 4; shutterRing.isUserInteractionEnabled = false
        shutter.backgroundColor = .white
        shutter.addTarget(self, action: #selector(shutterTapped), for: .touchUpInside)
        bottomBar.addSubview(shutterRing); bottomBar.addSubview(shutter)
        thumb.backgroundColor = UIColor(white: 0.2, alpha: 1); thumb.layer.cornerRadius = 10; thumb.clipsToBounds = true
        thumb.imageView?.contentMode = .scaleAspectFill; thumb.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal); thumb.tintColor = .white
        thumb.addTarget(self, action: #selector(openAlbum), for: .touchUpInside)
        bottomBar.addSubview(thumb)

        toast.textColor = .white; toast.font = .systemFont(ofSize: 13, weight: .medium); toast.numberOfLines = 0; toast.textAlignment = .center
        toast.backgroundColor = UIColor(white: 0, alpha: 0.7); toast.layer.cornerRadius = 14; toast.clipsToBounds = true; toast.alpha = 0
        view.addSubview(toast)
        spinner.color = .white; view.addSubview(spinner)

        palette.isHidden = true
        palette.onClose = { [weak self] in self?.setPalette(false) }
        palette.onShutter = { [weak self] in self?.shutterTapped() }
        palette.onChange = { [weak self] in self?.paletteChanged() }
        view.addSubview(palette)
        syncSpecPill(); syncButtons(); syncTabs()
    }

    private func layoutBottom() {
        let W = bottomBar.bounds.width, y0: CGFloat = 8
        // 第一行：左 [布局][小窗形状]  中 [视频 照片]  右 [镜像][手电筒]
        btnLayout.frame = CGRect(x: 16, y: y0, width: 34, height: 34)
        btnShape.frame = CGRect(x: 58, y: y0, width: 34, height: 34)
        btnTorch.frame = CGRect(x: W - 50, y: y0, width: 34, height: 34)
        btnMirror.frame = CGRect(x: W - 92, y: y0, width: 34, height: 34)
        tabVideo.frame = CGRect(x: W / 2 - 64, y: y0, width: 64, height: 34)
        tabPhoto.frame = CGRect(x: W / 2, y: y0, width: 64, height: 34)
        // 第二行：缩略图 · 快门 · 翻转
        let cy: CGFloat = 8 + 34 + 16 + 38
        shutterRing.frame = CGRect(x: W / 2 - 38, y: cy - 38, width: 76, height: 76); shutterRing.layer.cornerRadius = 38
        let inset: CGFloat = engine.isRecording ? 22 : 7
        shutter.frame = shutterRing.frame.insetBy(dx: inset, dy: inset)
        shutter.layer.cornerRadius = engine.isRecording ? 8 : shutter.bounds.width / 2
        thumb.frame = CGRect(x: 26, y: cy - 27, width: 54, height: 54)
        btnSwap.frame = CGRect(x: W - 26 - 46, y: cy - 23, width: 46, height: 46)
    }

    private func buildSpecPanel() {
        specPanel.backgroundColor = UIColor(white: 0.1, alpha: 0.94); specPanel.layer.cornerRadius = 18; specPanel.isHidden = true
        specPanel.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(specPanel)
        let defs: [(String, [String], Int)] = [
            ("分辨率", ["720p", "1080p", "4K"], [720, 1080, 2160].firstIndex(of: st.res) ?? 1),
            ("帧率", ["24", "30", "60"], [24, 30, 60].firstIndex(of: st.fps) ?? 1),
            ("照片格式", ["JPEG", "HEIF", "ProRAW"], st.heif ? 1 : 0)]
        let col = UIStackView(); col.axis = .vertical; col.spacing = 10; col.translatesAutoresizingMaskIntoConstraints = false
        specPanel.addSubview(col)
        for (i, d) in defs.enumerated() {
            let l = UILabel(); l.text = d.0; l.textColor = UIColor(white: 1, alpha: 0.7); l.font = .systemFont(ofSize: 13); l.widthAnchor.constraint(equalToConstant: 60).isActive = true
            let s = UISegmentedControl(items: d.1); s.selectedSegmentIndex = d.2; s.tag = i
            s.addTarget(self, action: #selector(specChanged(_:)), for: .valueChanged)
            specSegs.append(s)
            let r = UIStackView(arrangedSubviews: [l, s]); r.spacing = 8; r.alignment = .center; col.addArrangedSubview(r)
        }
        let note = UILabel(); note.text = "ProRAW 需要单摄像头模式，双摄同时拍摄时系统不支持"; note.font = .systemFont(ofSize: 11)
        note.textColor = UIColor(white: 1, alpha: 0.45); note.numberOfLines = 0; col.addArrangedSubview(note)
        NSLayoutConstraint.activate([
            specPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),
            specPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            specPanel.widthAnchor.constraint(equalToConstant: 300),
            col.topAnchor.constraint(equalTo: specPanel.topAnchor, constant: 14), col.bottomAnchor.constraint(equalTo: specPanel.bottomAnchor, constant: -14),
            col.leadingAnchor.constraint(equalTo: specPanel.leadingAnchor, constant: 14), col.trailingAnchor.constraint(equalTo: specPanel.trailingAnchor, constant: -14)])
    }

    private func applyGlass() {
        let g = st.glass
        roundBtns.forEach { $0.setGlass(g) }
        zoomCtl.glass = g
        specPill.backgroundColor = g ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 1, alpha: 0.16)
    }

    // MARK: - 同步状态

    private var mainIsBack: Bool { engine.layout.backIsMain }

    private func syncZoomRange(resetTo z: CGFloat?) {
        let (lo, hi) = engine.zoomRange(back: mainIsBack)
        zoomCtl.setRange(lo: lo, hi: hi, current: z ?? engine.currentZoom(back: mainIsBack))
    }
    private func syncSpecPill() {
        let fmt = st.heif ? "HEIF" : "JPEG"
        let r = engine.spec.res, f = engine.spec.fps
        let shown = ready ? (r == 2160 ? "4K" : "\(r)p") + " · \(f)" : (st.res == 2160 ? "4K" : "\(st.res)p") + " · \(st.fps)"
        specPill.setTitle("\(shown) · \(fmt)" + (st.fullSensor ? " · 片门" : ""), for: .normal)
    }
    private func syncButtons() {
        btnLive.active = st.liveOn; btnLive.isEnabled = mode == .photo; btnLive.alpha = mode == .photo ? 1 : 0.4
        btnPalette.active = !DualSettings.shared.grade.isNeutral || paletteOpen
        btnTorch.active = torchOn; btnMirror.active = st.mirror
        btnLayout.setSymbol(engine.layout.style == .pip ? "rectangle.split.1x2" : "pip")
        btnShape.isEnabled = engine.layout.style == .pip; btnShape.alpha = btnShape.isEnabled ? 1 : 0.4
    }
    private func syncTabs() {
        tabPhoto.setTitleColor(mode == .photo ? yellow : UIColor(white: 1, alpha: 0.75), for: .normal)
        tabVideo.setTitleColor(mode == .video ? yellow : UIColor(white: 1, alpha: 0.75), for: .normal)
        shutter.backgroundColor = mode == .video && !engine.isRecording ? UIColor(red: 0.95, green: 0.2, blue: 0.2, alpha: 1) : .white
    }
    private func pipRadiusValue() -> CGFloat { [0.14, 0.3, 0.0][shapeIdx % 3] }
    private var shapeIdx = 0

    // MARK: - 动作

    @objc private func tabTapped(_ b: UIButton) {
        guard !engine.isRecording else { return }
        mode = b === tabVideo ? .video : .photo
        engine.liveEnabled = st.liveOn && mode == .photo
        syncTabs(); syncButtons()
    }
    @objc private func toggleLive() {
        st.liveOn.toggle(); engine.liveEnabled = st.liveOn && mode == .photo; syncButtons()
        say(st.liveOn ? "实况已开启（\(Int(st.liveDur)) 秒，快门前 1.5 秒；实况无声音）" : "实况已关闭")
    }
    @objc private func toggleStyle() {
        var l = engine.layout; l.style = l.style == .pip ? .split : .pip; engine.layout = l
        st.pipStyleSplit = l.style == .split; syncButtons()
    }
    @objc private func cycleShape() {
        shapeIdx += 1; var l = engine.layout; l.pipRadius = pipRadiusValue(); engine.layout = l
        say(["小窗：圆角", "小窗：大圆角", "小窗：直角"][shapeIdx % 3])
    }
    @objc private func toggleMirror() {
        st.mirror.toggle(); var l = engine.layout; l.mirrorFront = st.mirror; engine.layout = l; syncButtons()
    }
    @objc private func toggleTorch() {
        torchOn.toggle(); engine.setTorch(torchOn); syncButtons()
    }
    @objc private func swapMain() {
        var l = engine.layout; l.backIsMain.toggle(); engine.layout = l; st.backIsMain = l.backIsMain
        syncZoomRange(resetTo: nil)
    }
    @objc private func toggleSpecPanel() { specPanel.isHidden.toggle() }
    @objc private func specChanged(_ s: UISegmentedControl) {
        switch s.tag {
        case 0: st.res = [720, 1080, 2160][s.selectedSegmentIndex]
        case 1: st.fps = [24, 30, 60][s.selectedSegmentIndex]
        default:
            if s.selectedSegmentIndex == 2 { s.selectedSegmentIndex = st.heif ? 1 : 0; say("双摄同时拍摄时系统不支持 ProRAW"); return }
            st.heif = s.selectedSegmentIndex == 1; syncSpecPill(); return
        }
        applySpec()
    }

    private func applySpec(keepZoom: CGFloat? = nil) {
        guard ready, !engine.isRecording, !reconfiguring else { return }
        reconfiguring = true; spinner.startAnimating()
        let spec = currentSpec()
        engine.reconfigure(spec) { [weak self] note, err in
            guard let self = self else { return }
            self.reconfiguring = false; self.spinner.stopAnimating()
            if let e = err { self.say("切换失败：\(e)", 4); self.wantUW = self.engine.spec.ultraWide }
            else if !note.isEmpty { self.say(note, 4.5) }
            self.wantUW = self.engine.spec.ultraWide
            if let z = keepZoom, err == nil { self.engine.setZoom(back: true, z); self.syncZoomRange(resetTo: z) }
            else { self.syncZoomRange(resetTo: nil) }
            self.syncSpecPill()
            for (i, s) in self.specSegs.enumerated() where i < 2 {
                s.selectedSegmentIndex = i == 0 ? ([720, 1080, 2160].firstIndex(of: self.st.res) ?? 1) : ([24, 30, 60].firstIndex(of: self.st.fps) ?? 1)
            }
            self.engine.liveEnabled = self.st.liveOn && self.mode == .photo
        }
    }

    /// 变焦停稳：需要的话在这时切换后置镜头（广角 ⇄ 超广角）
    private func zoomSettled(_ z: CGFloat) {
        guard ready, mainIsBack, !reconfiguring, !engine.isRecording, engine.needsLensSwitch(forBackZoom: z) else { return }
        wantUW = z < 1
        applySpec(keepZoom: z)
    }

    @objc private func openSettings() {
        specPanel.isHidden = true
        let v = DualSettingsViewController()
        v.onChange = { [weak self] recfg in
            guard let self = self else { return }
            var l = self.engine.layout; l.border = self.st.border; l.mirrorFront = self.st.mirror; self.engine.layout = l
            self.applyGlass(); self.syncSpecPill(); self.syncButtons()
            if recfg { self.view.setNeedsLayout(); self.view.layoutIfNeeded(); self.applySpec() }
        }
        v.modalPresentationStyle = .pageSheet
        present(v, animated: true)
    }

    @objc private func openAlbum() {
        let a = DualAlbumViewController(); a.items = items
        a.onImport = { [weak self] in self?.closeTapped() }
        a.modalPresentationStyle = .fullScreen
        present(a, animated: true)
    }

    // MARK: - 调色

    @objc private func togglePalette() { setPalette(!paletteOpen) }
    private func setPalette(_ on: Bool) {
        paletteOpen = on; palette.isHidden = !on; bottomBar.isHidden = on; zoomCtl.isHidden = on
        readout.isHidden = !on; presetLabel.isHidden = !on
        if on { palette.syncFromState(); paletteChanged() }
        syncButtons()
    }
    private func paletteChanged() {
        let s = st.grade.snapshot()
        readout.text = "色调 \(Int((s.y * 100).rounded()))   颜色 \(Int((s.x * 100).rounded()))   调色盘 \(Int((s.str * 100).rounded()))"
        let i = st.grade.presetIndex
        presetLabel.text = "  \(s.preset.name)  (\(i + 1)/\(stylePresets.count))  "
    }
    @objc private func swipePreset(_ g: UISwipeGestureRecognizer) {
        guard paletteOpen else { return }
        let n = stylePresets.count, i = st.grade.presetIndex
        st.grade.selectPreset(g.direction == .left ? (i + 1) % n : (i - 1 + n) % n)
        palette.syncFromState(); paletteChanged()
    }

    // MARK: - 小窗：拖动 / 点按互换

    private func pipRect() -> CGRect {
        let L = engine.layout; guard L.style == .pip else { return .zero }
        return L.rects(stage.bounds.width, stage.bounds.height).second
    }
    @objc private func panPip(_ g: UIPanGestureRecognizer) {
        guard engine.layout.style == .pip else { return }
        let W = stage.bounds.width, H = stage.bounds.height
        if g.state == .began { pipDragStart = g.location(in: stage); if !pipRect().insetBy(dx: -10, dy: -10).contains(pipDragStart) { g.isEnabled = false; g.isEnabled = true; return } }
        guard g.state == .changed else { return }
        let t = g.translation(in: stage); g.setTranslation(.zero, in: stage)
        var l = engine.layout
        let w = (W * l.pipW).rounded(), h = (w * 4 / 3).rounded(), m = (W * 0.04).rounded()
        let rx = max(1, W - w - 2 * m), ry = max(1, H - h - 2 * m)
        l.pipX = min(1, max(0, l.pipX + t.x / rx)); l.pipY = min(1, max(0, l.pipY + t.y / ry))
        engine.layout = l
    }
    @objc private func tapStage(_ g: UITapGestureRecognizer) {
        specPanel.isHidden = true
        if engine.layout.style == .pip && pipRect().contains(g.location(in: stage)) { swapMain() }
    }

    // MARK: - 拍摄

    @objc private func shutterTapped() {
        guard ready, !reconfiguring else { return }
        if mode == .photo { takePhoto() } else { engine.isRecording ? stopRecording() : startRecording() }
    }

    private func newFile(_ ext: String) -> URL {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        return SchemeHandler.outDir.appendingPathComponent("澄影双摄_\(f.string(from: Date()))_\(Int.random(in: 100...999)).\(ext)")
    }

    private func takePhoto() {
        let live = st.liveOn
        let heif = st.heif && !live
        let url = newFile(heif ? "heic" : "jpg")
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let flash = UIView(frame: stage.bounds); flash.backgroundColor = .white; stage.addSubview(flash)
        UIView.animate(withDuration: 0.25, animations: { flash.alpha = 0 }) { _ in flash.removeFromSuperview() }
        if live { engine.captureLive(totalSeconds: st.liveDur) { [weak self] mov, still, err in self?.liveDone(url, mov, still, err) }; say("实况录制中…") }
        engine.takePhoto(to: url, heif: heif) { [weak self] ok, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !ok { self.say("拍照失败：\(err ?? "未知错误")"); return }
                if !live { self.store(url, isVideo: false) }
            }
        }
    }

    private func liveDone(_ photo: URL, _ mov: URL?, _ still: Double, _ err: String?) {
        DispatchQueue.main.async {
            guard let mov = mov else { self.say("实况失败：\(err ?? "")，已保存静态照片"); self.store(photo, isVideo: false); return }
            self.saving += 1
            LivePhotoSaver.save(photo: photo, video: mov, duration: self.st.liveDur, still: still) { ok, msg in
                self.saving -= 1
                self.items.append(Item(kind: "photo", url: photo, saved: ok))
                self.updateThumb(photo)
                self.say(ok ? "实况照片已存入系统相册" : "实况没存进系统相册：\(msg ?? "")")
                if self.st.liveAlsoStill { PhotoSaver.save(file: photo, isVideo: false) { _, _ in } }
            }
        }
    }

    private func startRecording() {
        engine.liveEnabled = false
        engine.startRecording(to: newFile("mp4"), audio: st.audio)
        recStart = Date(); timerLabel.isHidden = false; timerLabel.text = "● 00:00"
        recTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let s = Int(Date().timeIntervalSince(self.recStart)); self.timerLabel.text = String(format: "● %02d:%02d", s / 60, s % 60)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.layoutBottom(); self.syncTabs() }
        say(engine.hasAudio && st.audio ? "开始录像（带声音）" : "开始录像（只录画面）")
    }

    private func stopRecording() {
        recTimer?.invalidate(); recTimer = nil; timerLabel.isHidden = true
        engine.stopRecording { [weak self] url, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.layoutBottom(); self.syncTabs()
                if let u = url { self.store(u, isVideo: true) } else { self.say("录像失败：\(err ?? "未知错误")") }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { self.layoutBottom(); self.syncTabs() }
    }

    private func store(_ url: URL, isVideo: Bool) {
        saving += 1
        PhotoSaver.save(file: url, isVideo: isVideo) { [weak self] ok, msg in
            guard let self = self else { return }
            self.saving -= 1
            self.items.append(Item(kind: isVideo ? "video" : "photo", url: url, saved: ok))
            self.updateThumb(url)
            self.say(ok ? (isVideo ? "视频已存入系统相册" : "照片已存入系统相册") : "没存进系统相册：\(msg ?? "")（仍会导入澄影相册）")
        }
    }

    private func updateThumb(_ u: URL) {
        guard let it = items.last else { return }
        DispatchQueue.global(qos: .utility).async {
            let im = DualAlbumViewController.thumb(it)
            DispatchQueue.main.async { if let im = im { self.thumb.setImage(im, for: .normal) } }
        }
    }

    private func say(_ t: String, _ sec: Double = 2.2) {
        toast.text = "  \(t)  "
        let w = min(view.bounds.width - 40, 320)
        toast.frame = CGRect(x: (view.bounds.width - w) / 2, y: stageFrame.maxY - 230, width: w, height: 0)
        toast.sizeToFit()
        toast.frame = CGRect(x: (view.bounds.width - w) / 2, y: stageFrame.maxY - 230, width: w, height: max(30, toast.frame.height + 8))
        toast.alpha = 1
        let token = Int(Date().timeIntervalSince1970 * 1000); toast.tag = token
        DispatchQueue.main.asyncAfter(deadline: .now() + sec) { [weak self] in
            guard let self = self, self.toast.tag == token else { return }
            UIView.animate(withDuration: 0.3) { self.toast.alpha = 0 }
        }
    }

    // MARK: - 关闭

    @objc private func closeTapped() {
        if engine.isRecording {
            recTimer?.invalidate(); recTimer = nil
            engine.stopRecording { [weak self] url, _ in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if let u = url {
                        self.saving += 1
                        PhotoSaver.save(file: u, isVideo: true) { ok, _ in
                            self.saving -= 1; self.items.append(Item(kind: "video", url: u, saved: ok)); self.finish(code: nil, msg: nil)
                        }
                    } else { self.finish(code: nil, msg: nil) }
                }
            }
            return
        }
        finish(code: nil, msg: nil)
    }

    private func finish(code: String?, msg: String?) {
        guard !finished else { return }
        if saving > 0 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.finish(code: code, msg: msg) }; return }
        finished = true
        if torchOn { engine.setTorch(false) }
        engine.liveEnabled = false
        engine.stop()
        let result = items
        // 这个界面里的相册 / 设置如果还开着，先一起收掉
        let root = presentingViewController
        (root ?? self).dismiss(animated: true) { [weak self] in
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
