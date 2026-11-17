import UIKit
import Photos
import AVFoundation

/// 原生双摄相机界面：取景（引擎合成的画面）+ 顶部 / 底部控件 + 变焦转盘 + 调色面板 + 设置 + 相册。
final class DualCamViewController: UIViewController, UIGestureRecognizerDelegate {
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
    private let toastBox = DualToastView()
    private let hintStack = UIStackView()          // 取景框左上角：实况计时 + 提示条，从上往下排
    private let timerLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let specPill = DualPillButton()
    private let specPanel = UIView()
    private var specSegs: [GlassSegmented] = []
    private let specBack = DualBackdrop(radius: 20)
    private var roundBtns: [DualCircleButton] = []
    private var btnBack: DualCircleButton!, btnLive: DualCircleButton!, btnPalette: DualCircleButton!, btnSettings: DualCircleButton!
    private var btnLayout: DualCircleButton!, btnShape: DualCircleButton!, btnMirror: DualCircleButton!, btnTorch: DualCircleButton!, btnSwap: DualCircleButton!
    private let palette = DualPalettePanel()
    private let readout = UILabel(), presetLabel = UILabel()
    private var paletteOpen = false
    private let pageDots = PresetDots()
    // 实况连拍：每张各自一行进度（取景框左上角），全部拍完 / 存完后一起消失
    private final class LiveTask {
        let n: Int, t0 = Date(), total: Double, photo: URL
        var stillDone = false, stillOK = false
        var liveDone = false, mov: URL?, stillAt = 0.0, err: String?
        var phase = 0                      // 0 录制中 · 1 合成保存中 · 2 完成 · 3 失败
        var note = ""
        let row = PaddedLabel()
        init(n: Int, total: Double, photo: URL) { self.n = n; self.total = total; self.photo = photo }
    }
    private var liveTasks: [LiveTask] = []
    private var liveSeq = 0
    private let liveStack = UIStackView()
    private var liveTick: Timer?
    private var liveHideToken = 0
    private let focusBox = FocusIndicator()
    private var focusBack = true, biasBase: Float = 0, exposureDragging = false, pipDragging = false
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
        engine.onPressure = { [weak self] m in self?.say(m, 3.5) }
        applyGlass()
        refreshThumb()
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
                        self.engine.fullRate = self.st.fullRate
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
        palette.frame = CGRect(x: 8, y: H - bot - 286, width: W - 16, height: 280)
        presetLabel.frame = CGRect(x: (W - 130) / 2, y: palette.frame.minY - 62, width: 130, height: 26)
        pageDots.frame = CGRect(x: (W - 220) / 2, y: palette.frame.minY - 32, width: 220, height: 20)
        spinner.center = stage.center
        layoutBottom()
    }

    // MARK: - 界面搭建

    private func rb(_ sym: String, _ size: CGFloat = 40, _ sel: Selector) -> DualCircleButton {
        let b = DualCircleButton(symbol: sym, size: size)
        b.addTarget(self, action: sel, for: .touchUpInside)
        roundBtns.append(b); return b
    }

    private func buildUI() {
        stage.backgroundColor = .black; stage.clipsToBounds = true
        stage.layer.addSublayer(engine.previewLayer)
        view.addSubview(stage)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panStage(_:))); pan.delegate = self
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapStage(_:)))
        let dbl = UITapGestureRecognizer(target: self, action: #selector(doubleTapStage(_:))); dbl.numberOfTapsRequired = 2
        tap.require(toFail: dbl)
        let lp = UILongPressGestureRecognizer(target: self, action: #selector(longPressStage(_:))); lp.minimumPressDuration = 0.5
        let swipeL = UISwipeGestureRecognizer(target: self, action: #selector(swipePreset(_:))); swipeL.direction = .left
        let swipeR = UISwipeGestureRecognizer(target: self, action: #selector(swipePreset(_:))); swipeR.direction = .right
        [pan, tap, dbl, lp, swipeL, swipeR].forEach { stage.addGestureRecognizer($0) }
        view.addSubview(zoomCtl)
        zoomCtl.onZoom = { [weak self] z in guard let self = self else { return }; self.engine.setZoom(back: self.mainIsBack, z) }
        zoomCtl.onSettle = { [weak self] z in self?.zoomSettled(z) }

        // 顶部
        btnBack = rb("chevron.left", 40, #selector(closeTapped))
        btnLive = rb("livephoto", 40, #selector(toggleLive))
        btnPalette = rb("circle.hexagongrid.fill", 40, #selector(togglePalette))
        btnSettings = rb("gearshape.fill", 40, #selector(openSettings))
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
        for l in [readout] {
            l.textColor = .white; l.font = .systemFont(ofSize: 13, weight: .semibold); l.textAlignment = .center
            l.backgroundColor = UIColor(white: 0, alpha: 0.45); l.layer.cornerRadius = 13; l.clipsToBounds = true; l.isHidden = true
            l.translatesAutoresizingMaskIntoConstraints = false; stage.addSubview(l)
            l.centerXAnchor.constraint(equalTo: stage.centerXAnchor).isActive = true
            l.heightAnchor.constraint(equalToConstant: 26).isActive = true
        }
        readout.topAnchor.constraint(equalTo: stage.topAnchor, constant: 10).isActive = true
        readout.widthAnchor.constraint(greaterThanOrEqualToConstant: 190).isActive = true
        presetLabel.textColor = .white; presetLabel.font = .systemFont(ofSize: 13, weight: .semibold); presetLabel.textAlignment = .center
        presetLabel.backgroundColor = UIColor(white: 0, alpha: 0.45); presetLabel.layer.cornerRadius = 13; presetLabel.clipsToBounds = true; presetLabel.isHidden = true
        view.addSubview(presetLabel)
        pageDots.isUserInteractionEnabled = false; pageDots.isHidden = true
        view.addSubview(pageDots)
        // 实况进度（取景框左上角，一张一行）
        liveStack.axis = .vertical; liveStack.spacing = 4; liveStack.alignment = .leading
        liveStack.translatesAutoresizingMaskIntoConstraints = false
        // 左上角提示区：以后所有提示都出现在这里（实况计时在上，提示条在下）
        toastBox.translatesAutoresizingMaskIntoConstraints = false
        hintStack.axis = .vertical; hintStack.spacing = 6; hintStack.alignment = .leading
        hintStack.translatesAutoresizingMaskIntoConstraints = false
        hintStack.addArrangedSubview(liveStack); hintStack.addArrangedSubview(toastBox)
        stage.addSubview(hintStack)
        NSLayoutConstraint.activate([hintStack.topAnchor.constraint(equalTo: stage.topAnchor, constant: 10),
            hintStack.leadingAnchor.constraint(equalTo: stage.leadingAnchor, constant: 12),
            toastBox.widthAnchor.constraint(lessThanOrEqualTo: stage.widthAnchor, multiplier: 0.6)])
        focusBox.isHidden = true; stage.addSubview(focusBox)
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
        specPanel.isHidden = true
        specPanel.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(specPanel)
        specBack.translatesAutoresizingMaskIntoConstraints = false; specPanel.addSubview(specBack)
        let defs: [(String, [String], Int)] = [
            ("分辨率", ["720p", "1080p", "4K"], [720, 1080, 2160].firstIndex(of: st.res) ?? 1),
            ("帧率", ["24", "30", "60"], [24, 30, 60].firstIndex(of: st.fps) ?? 1),
            ("照片格式", ["JPEG", "HEIF", "ProRAW"], st.heif ? 1 : 0)]
        let col = UIStackView(); col.axis = .vertical; col.spacing = 10; col.translatesAutoresizingMaskIntoConstraints = false
        specPanel.addSubview(col)
        for (i, d) in defs.enumerated() {
            let l = UILabel(); l.text = d.0; l.textColor = UIColor(white: 1, alpha: 0.75); l.font = .systemFont(ofSize: 13); l.widthAnchor.constraint(equalToConstant: 60).isActive = true
            let s = GlassSegmented(items: d.1, selected: d.2)
            s.onChange = { [weak self] idx in self?.specChanged(i, idx) }
            s.heightAnchor.constraint(equalToConstant: 34).isActive = true
            specSegs.append(s)
            let r = UIStackView(arrangedSubviews: [l, s]); r.spacing = 8; r.alignment = .center; col.addArrangedSubview(r)
        }
        let note = UILabel(); note.text = "ProRAW 需要单摄像头模式，双摄同时拍摄时系统不支持"; note.font = .systemFont(ofSize: 11)
        note.textColor = UIColor(white: 1, alpha: 0.45); note.numberOfLines = 0; col.addArrangedSubview(note)
        NSLayoutConstraint.activate([
            specPanel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50),
            specPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            specPanel.widthAnchor.constraint(equalToConstant: 310),
            specBack.topAnchor.constraint(equalTo: specPanel.topAnchor), specBack.bottomAnchor.constraint(equalTo: specPanel.bottomAnchor),
            specBack.leadingAnchor.constraint(equalTo: specPanel.leadingAnchor), specBack.trailingAnchor.constraint(equalTo: specPanel.trailingAnchor),
            col.topAnchor.constraint(equalTo: specPanel.topAnchor, constant: 14), col.bottomAnchor.constraint(equalTo: specPanel.bottomAnchor, constant: -14),
            col.leadingAnchor.constraint(equalTo: specPanel.leadingAnchor, constant: 14), col.trailingAnchor.constraint(equalTo: specPanel.trailingAnchor, constant: -14)])
    }

    private func applyGlass() {
        let g = st.glass
        roundBtns.forEach { $0.setGlass(g) }
        zoomCtl.glass = g
        palette.glass = g
        specSegs.forEach { $0.glass = g }
        specBack.apply(glass: g, flat: UIColor(white: 0.1, alpha: 0.94))
        specPill.setGlass(g)
        toastBox.setGlass(g)
        thumb.layer.cornerCurve = .continuous
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
        btnPalette.active = !(st.gradeBack.isNeutral && st.gradeFront.isNeutral) || paletteOpen
        updatePaletteGlyph()
        btnTorch.active = torchOn; btnMirror.active = st.mirror
        btnLayout.setSymbol(engine.layout.style == .pip ? "rectangle.split.1x2" : "pip", size: 34)
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
        focusBox.hide(); engine.resetFocus(back: focusBack)
        var l = engine.layout; l.backIsMain.toggle(); engine.layout = l; st.backIsMain = l.backIsMain
        syncZoomRange(resetTo: nil)
    }
    @objc private func toggleSpecPanel() { setSpecPanel(specPanel.isHidden) }

    /// 规格面板展开 / 收起：开了液态玻璃就像史莱姆一样 Q 弹地从「帧率画质」那颗胶囊下面弹出、再缩回到那里；没开就直接显示 / 隐藏。
    /// 玻璃本身用「在动画里把 effect 设成 / 取消」来出现和消失（只改透明度的话，玻璃会在原地留几帧残影）。
    private var specAnimating = false
    private var specGen = 0
    /// 收起状态：整块缩成一小点，落在胶囊下沿的中点（不盖住胶囊）
    private func specCollapsed() -> CGAffineTransform {
        let pill = specPill.convert(specPill.bounds, to: view)
        let px = pill.midX, py = pill.maxY - 2, c = specPanel.center, s: CGFloat = 0.1
        return CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: (1 - s) * (px - c.x), ty: (1 - s) * (py - c.y))
    }
    private func setSpecPanel(_ open: Bool) {
        if open == !specPanel.isHidden && !specAnimating { return }
        specPanel.layer.removeAllAnimations(); specBack.layer.removeAllAnimations()
        specGen += 1; let gen = specGen
        guard st.glass else { specPanel.transform = .identity; specPanel.alpha = 1; specPanel.isHidden = !open; return }
        view.layoutIfNeeded()
        specAnimating = true
        if open {
            specBack.effect = nil; specBack.backgroundColor = nil
            specPanel.isHidden = false; specPanel.alpha = 1
            specPanel.transform = specCollapsed()
            UIView.animate(withDuration: 0.75, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 1.0, options: [.allowUserInteraction]) {
                self.specPanel.transform = .identity
            } completion: { _ in if gen == self.specGen { self.specAnimating = false } }
            UIView.animate(withDuration: 0.3, delay: 0, options: [.allowUserInteraction]) {
                self.specBack.effect = dualGlassEffect()
            }
        } else {
            UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseOut]) {
                self.specPanel.transform = CGAffineTransform(scaleX: 1.04, y: 0.96)
            } completion: { _ in
                guard gen == self.specGen else { return }
                UIView.animate(withDuration: 0.42, delay: 0, usingSpringWithDamping: 0.62, initialSpringVelocity: 0.8, options: []) {
                    self.specPanel.transform = self.specCollapsed()
                    self.specBack.effect = nil          // 玻璃一起「化掉」
                    self.specPanel.alpha = 0
                } completion: { _ in
                    guard gen == self.specGen else { return }
                    self.specAnimating = false
                    self.specPanel.isHidden = true; self.specPanel.transform = .identity; self.specPanel.alpha = 1
                    self.specBack.apply(glass: true, flat: UIColor(white: 0.1, alpha: 0.94))
                }
            }
        }
    }
    private func specChanged(_ tag: Int, _ idx: Int) {
        switch tag {
        case 0: st.res = [720, 1080, 2160][idx]
        case 1: st.fps = [24, 30, 60][idx]
        default:
            if idx == 2 { specSegs[2].select(st.heif ? 1 : 0); say("双摄同时拍摄时系统不支持 ProRAW"); return }
            st.heif = idx == 1; syncSpecPill(); return
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
            self.specSegs[0].select([720, 1080, 2160].firstIndex(of: self.st.res) ?? 1)
            self.specSegs[1].select([24, 30, 60].firstIndex(of: self.st.fps) ?? 1)
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
        setSpecPanel(false)
        let v = DualSettingsViewController()
        v.onChange = { [weak self] recfg in
            guard let self = self else { return }
            var l = self.engine.layout; l.border = self.st.border; l.mirrorFront = self.st.mirror; self.engine.layout = l
            self.engine.fullRate = self.st.fullRate
            self.applyGlass(); self.syncSpecPill(); self.syncButtons()
            if recfg { self.view.setNeedsLayout(); self.view.layoutIfNeeded(); self.applySpec() }
        }
        v.modalPresentationStyle = .pageSheet
        present(v, animated: true)
    }

    @objc private func openAlbum() {
        let a = DualAlbumViewController(); a.items = items
        a.onImport = { [weak self] in self?.closeTapped() }
        a.onClose = { [weak self] in self?.refreshThumb() }
        a.modalPresentationStyle = .fullScreen
        present(a, animated: true)
    }

    // MARK: - 调色

    @objc private func togglePalette() { setPalette(!paletteOpen) }
    private func setPalette(_ on: Bool) {
        paletteOpen = on; palette.isHidden = !on; bottomBar.isHidden = on; zoomCtl.isHidden = on
        readout.isHidden = !on; presetLabel.isHidden = !on; pageDots.isHidden = !on
        if on { focusBox.hide() }
        if on { palette.syncFromState(); paletteChanged() }
        syncButtons()
    }
    /// 正在显示 / 修改的那套调色（前置选「前置」，其余显示后置的）
    private var shownGrade: GradeState { st.gradeTarget == 1 ? st.gradeFront : st.gradeBack }
    private var gradeTargets: [GradeState] {
        switch st.gradeTarget { case 0: return [st.gradeBack]; case 1: return [st.gradeFront]; default: return [st.gradeBack, st.gradeFront] }
    }
    /// 数值显示（和主页面一样：0 显示成「00」，负数带负号）
    private static func sgn(_ v: Double) -> String {
        let n = Int((v * 100).rounded()); return n == 0 ? "00" : "\(n)"
    }
    private func updatePaletteGlyph() {
        let s = shownGrade.snapshot()
        btnPalette.setImage(PaletteGlyph.image(size: 26, x: s.x, y: s.y), for: .normal)
    }
    private func paletteChanged() {
        let s = shownGrade.snapshot()
        readout.text = "色调 \(Self.sgn(s.y))   颜色 \(Self.sgn(s.x))   调色盘 \(Int((s.str * 100).rounded()))"
        let i = shownGrade.presetIndex
        presetLabel.text = "  \(s.preset.name)  "
        pageDots.set(index: PresetOrder.indices.firstIndex(of: i) ?? 0, count: PresetOrder.indices.count)
        updatePaletteGlyph()
    }
    @objc private func swipePreset(_ g: UISwipeGestureRecognizer) {
        guard paletteOpen else { return }
        // 按「更多设置 → 调色盘预设顺序」里排好的顺序切换
        let order = PresetOrder.indices, n = order.count, pos = order.firstIndex(of: shownGrade.presetIndex) ?? 0
        let ni = order[g.direction == .left ? (pos + 1) % n : (pos - 1 + n) % n]
        gradeTargets.forEach { $0.selectPreset(ni) }
        palette.syncFromState(); paletteChanged()
    }

    // MARK: - 小窗：拖动 / 点按互换

    private func pipRect() -> CGRect {
        let L = engine.layout; guard L.style == .pip else { return .zero }
        return L.rects(stage.bounds.width, stage.bounds.height).second
    }
    /// 主画面占取景框的哪一块（画中画 = 整个取景框；上下分屏 = 上半）
    private func mainRect() -> CGRect { engine.layout.rects(stage.bounds.width, stage.bounds.height).main }

    private func inPip(_ p: CGPoint) -> Bool { engine.layout.style == .pip && pipRect().insetBy(dx: -10, dy: -10).contains(p) }

    /// 拖动：落在小窗上 = 移动小窗；已经有对焦框时 = 上下拖动调曝光
    @objc private func panStage(_ g: UIPanGestureRecognizer) {
        let W = stage.bounds.width, H = stage.bounds.height
        switch g.state {
        case .began:
            let p = g.location(in: stage)
            pipDragging = inPip(p); exposureDragging = !pipDragging && focusBox.isVisible
            if exposureDragging { biasBase = focusBox.bias; focusBox.keepAlive() }
        case .changed:
            if pipDragging {
                let t = g.translation(in: stage); g.setTranslation(.zero, in: stage)
                var l = engine.layout
                let w = (W * l.pipW).rounded(), h = (w * 4 / 3).rounded(), m = (W * 0.04).rounded()
                let rx = max(1, W - w - 2 * m), ry = max(1, H - h - 2 * m)
                l.pipX = min(1, max(0, l.pipX + t.x / rx)); l.pipY = min(1, max(0, l.pipY + t.y / ry))
                engine.layout = l
            } else if exposureDragging {
                // 上拉 = 变亮，下拉 = 变暗
                let (lo, hi) = engine.biasRange(back: focusBack)
                let dy = Float(-g.translation(in: stage).y / (H * 0.4))
                let v = min(hi, max(lo, biasBase + dy * (hi - lo)))
                focusBox.bias = v; focusBox.range = (lo, hi); focusBox.setNeedsDisplay()
                engine.setBias(back: focusBack, v)
                focusBox.keepAlive()
            }
        case .ended, .cancelled:
            if exposureDragging { focusBox.keepAlive() }
            pipDragging = false; exposureDragging = false
        default: break
        }
    }

    /// 单点：点小窗 = 互换主 / 小窗；点主画面 = 对焦 + 测光
    @objc private func tapStage(_ g: UITapGestureRecognizer) {
        setSpecPanel(false)
        let p = g.location(in: stage)
        if engine.layout.style == .pip && pipRect().contains(p) { swapMain(); return }
        guard !paletteOpen else { return }
        focusAt(p, lock: false)
    }

    /// 双击小窗：放大 / 缩小
    @objc private func doubleTapStage(_ g: UITapGestureRecognizer) {
        let p = g.location(in: stage)
        guard engine.layout.style == .pip, pipRect().contains(p) else { return }
        var l = engine.layout
        l.pipW = l.pipW > 0.4 ? 0.32 : 0.55
        engine.layout = l
        say(l.pipW > 0.4 ? "小窗已放大" : "小窗已缩小")
    }

    /// 长按：锁定对焦和曝光（再长按 / 再点一下解除）
    @objc private func longPressStage(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, !paletteOpen else { return }
        let p = g.location(in: stage)
        if inPip(p) { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        focusAt(p, lock: true)
    }

    private func focusAt(_ p: CGPoint, lock: Bool) {
        let r = mainRect()
        guard r.contains(p), ready else { return }
        focusBack = mainIsBack
        let nx = (p.x - r.minX) / r.width, ny = (p.y - r.minY) / r.height
        let dp = engine.devicePoint(back: focusBack, nx: nx, ny: ny, rectAspect: r.width / r.height)
        engine.focus(back: focusBack, at: dp, lock: lock)
        let (lo, hi) = engine.biasRange(back: focusBack)
        focusBox.range = (lo, hi)
        focusBox.show(at: p, in: stage.bounds, locked: lock)
        if !lock { engine.setBias(back: focusBack, 0) }
        say(lock ? "已锁定对焦和曝光（再点一下解除）" : "对焦 · 上下拖动调曝光", 1.6)
    }

    // MARK: - 拍摄

    @objc private func shutterTapped() {
        guard ready, !reconfiguring else { return }
        if mode == .photo { takePhoto() }
        else if engine.isRecording { stopRecording() }
        else if liveTasks.contains(where: { $0.phase < 2 }) { say("还有实况在拍 / 合成，等它们完成再录像") }
        else { startRecording() }
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
        var task: LiveTask?
        if live {
            // 实况可以连拍：上一张还没拍完 / 合成完，也可以继续按快门，每张各自排队，左上角各有一行进度
            liveSeq += 1
            let t = LiveTask(n: liveSeq, total: max(1.0, st.liveDur), photo: url)
            task = t; liveTasks.append(t); saving += 1
            addLiveRow(t)
            engine.captureLive(totalSeconds: st.liveDur) { [weak self] mov, still, err in
                DispatchQueue.main.async { self?.liveCaptured(t, mov, still, err) }
            }
        }
        engine.takePhoto(to: url, heif: heif) { [weak self] ok, err in
            DispatchQueue.main.async {
                guard let self = self else { return }
                if !ok { self.say("拍照失败：\(err ?? "未知错误")") }
                if let t = task { t.stillDone = true; t.stillOK = ok; self.liveTryFinish(t) }
                else if ok { self.store(url, isVideo: false) }
            }
        }
    }

    /// 实况视频收完（或失败）
    private func liveCaptured(_ t: LiveTask, _ mov: URL?, _ still: Double, _ err: String?) {
        t.liveDone = true; t.mov = mov; t.stillAt = still; t.err = err
        if mov != nil { t.phase = 1 } else { t.note = err ?? "" }
        refreshLiveRows()
        liveTryFinish(t)
    }

    /// 静态照片和实况视频都有结果之后，才一起存进系统相册
    private func liveTryFinish(_ t: LiveTask) {
        guard t.liveDone, t.stillDone else { return }
        guard t.stillOK else {
            t.phase = 3; t.note = "照片没拍成"; saving -= 1
            liveTaskEnded(t, msg: "实况失败：照片没拍成"); return
        }
        guard let mov = t.mov else {
            // 实况没录成：退回存一张静态照片
            t.phase = 3; t.note = "\(t.err ?? "")，已存静态照片"
            store(t.photo, isVideo: false)
            saving -= 1
            liveTaskEnded(t, msg: "实况失败：\(t.err ?? "")，已保存静态照片"); return
        }
        t.phase = 1; refreshLiveRows()
        LivePhotoSaver.saveWithID(photo: t.photo, video: mov, duration: t.total, still: t.stillAt) { [weak self] ok, msg, id in
            guard let self = self else { return }
            self.saving -= 1
            self.items.append(Item(kind: "photo", url: t.photo, saved: ok))
            DualLibrary.add(id)
            self.updateThumb(t.photo)
            t.phase = ok ? 2 : 3; if !ok { t.note = msg ?? "" }
            if ok, self.st.liveAlsoStill { PhotoSaver.save(file: t.photo, isVideo: false) { _, _ in } }
            self.liveTaskEnded(t, msg: ok ? "实况照片已存入系统相册" : "实况没存进系统相册：\(msg ?? "")")
        }
    }

    // MARK: - 实况进度（取景框左上角）

    private func addLiveRow(_ t: LiveTask) {
        t.row.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold); t.row.textColor = .white
        t.row.layer.cornerRadius = 12; t.row.clipsToBounds = true
        liveStack.addArrangedSubview(t.row)
        liveHideToken += 1                                   // 又来了新的一张，先别收
        refreshLiveRows()
        if liveTick == nil {
            liveTick = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.refreshLiveRows() }
        }
    }

    private func refreshLiveRows() {
        let show = st.liveTimer
        liveStack.isHidden = !show || liveTasks.isEmpty
        let pre = 1.5
        for t in liveTasks {
            switch t.phase {
            case 0:
                let e = min(t.total, min(pre, t.total / 2) + Date().timeIntervalSince(t.t0))
                t.row.text = String(format: "● 实况 #%d  录制 %.1f / %.1f 秒", t.n, e, t.total)
                t.row.backgroundColor = UIColor(red: 0.9, green: 0.15, blue: 0.15, alpha: 0.9)
            case 1:
                t.row.text = "◐ 实况 #\(t.n)  合成保存中…"
                t.row.backgroundColor = UIColor(red: 0.85, green: 0.5, blue: 0.1, alpha: 0.92)
            case 2:
                t.row.text = "✓ 实况 #\(t.n)  已存入"
                t.row.backgroundColor = UIColor(red: 0.1, green: 0.6, blue: 0.3, alpha: 0.92)
            default:
                t.row.text = "✕ 实况 #\(t.n)  失败" + (t.note.isEmpty ? "" : "：\(t.note)")
                t.row.backgroundColor = UIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 0.92)
            }
        }
        if !liveTasks.contains(where: { $0.phase == 0 }) { liveTick?.invalidate(); liveTick = nil }
    }

    /// 一张实况收尾。所有实况都完成了，进度条才一起收起来
    private func liveTaskEnded(_ t: LiveTask, msg: String) {
        refreshLiveRows()
        if !st.liveTimer || t.phase == 3 { say(msg, 2.6) }
        guard !liveTasks.contains(where: { $0.phase < 2 }) else { return }
        liveHideToken += 1
        let tok = liveHideToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self = self, self.liveHideToken == tok, !self.liveTasks.contains(where: { $0.phase < 2 }) else { return }
            for x in self.liveTasks { self.liveStack.removeArrangedSubview(x.row); x.row.removeFromSuperview() }
            self.liveTasks.removeAll()
            self.liveStack.isHidden = true
        }
    }

    // MARK: - 手势代理：拖动只在需要的时候才接管

    func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard g is UIPanGestureRecognizer else { return true }
        if paletteOpen { return false }
        let p = g.location(in: stage)
        return inPip(p) || focusBox.isVisible
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
        PhotoSaver.saveWithID(file: url, isVideo: isVideo) { [weak self] ok, msg, id in
            guard let self = self else { return }
            self.saving -= 1
            self.items.append(Item(kind: isVideo ? "video" : "photo", url: url, saved: ok))
            DualLibrary.add(id)
            self.updateThumb(url)
            self.say(ok ? (isVideo ? "视频已存入系统相册" : "照片已存入系统相册") : "没存进系统相册：\(msg ?? "")（仍会导入澄影相册）")
        }
    }

    /// 相册入口的缩略图 = 系统相册里最近一张双摄拍的（重开 App 也在；删掉后自动换成上一张）
    private func refreshThumb() {
        guard PhotoSaver.canRead else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let latest = DualLibrary.fetch().first
            guard let a = latest else {
                DispatchQueue.main.async { self?.thumb.setImage(UIImage(systemName: "photo.on.rectangle"), for: .normal) }
                return
            }
            let o = PHImageRequestOptions(); o.isSynchronous = true; o.deliveryMode = .highQualityFormat; o.resizeMode = .fast
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 180, height: 180), contentMode: .aspectFill, options: o) { im, _ in
                DispatchQueue.main.async { if let im = im { self?.thumb.setImage(im, for: .normal) } }
            }
        }
    }

    private func updateThumb(_ u: URL) {
        guard let it = items.last else { return }
        DispatchQueue.global(qos: .utility).async {
            let im = DualAlbumViewController.thumb(it)
            DispatchQueue.main.async { if let im = im { self.thumb.setImage(im, for: .normal) } }
        }
    }

    /// 提示一律出现在取景框左上角
    private func say(_ t: String, _ sec: Double = 2.2) {
        toastBox.show(t)
        let token = Int(Date().timeIntervalSince1970 * 1000); toastBox.tag = token
        DispatchQueue.main.asyncAfter(deadline: .now() + sec) { [weak self] in
            guard let self = self, self.toastBox.tag == token else { return }
            self.toastBox.hide()
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
                        PhotoSaver.saveWithID(file: u, isVideo: true) { ok, _, id in
                            self.saving -= 1; self.items.append(Item(kind: "video", url: u, saved: ok)); DualLibrary.add(id); self.finish(code: nil, msg: nil)
                        }
                    } else { self.finish(code: nil, msg: nil) }
                }
            }
            return
        }
        if saving > 0 { say("还有 \(saving) 项在合成保存，稍等一下再关闭…", 3) }
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

/// 预设页码圆点：最多显示 5 个，当前的白色放大；窗口没到头时，边上的点缩小，表示后面还有（和主页面同款）
final class PresetDots: UIView {
    private var index = 0, count = 1
    func set(index: Int, count: Int) { self.index = index; self.count = max(1, count); setNeedsDisplay() }
    override init(frame: CGRect) { super.init(frame: frame); backgroundColor = .clear; isOpaque = false }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        guard let c = UIGraphicsGetCurrentContext() else { return }
        let n = min(5, count), s0 = max(0, min(count - n, index - 2)), gap: CGFloat = 14
        let x0 = (bounds.width - gap * CGFloat(n - 1)) / 2
        for k in 0..<n {
            let i = s0 + k, on = i == index
            let edge = (k == 0 && s0 > 0) || (k == n - 1 && s0 + n < count)
            let r: CGFloat = on ? 4 : (edge ? 2.2 : 3)
            c.setFillColor(UIColor(white: 1, alpha: on ? 1 : 0.4).cgColor)
            c.fillEllipse(in: CGRect(x: x0 + gap * CGFloat(k) - r, y: bounds.height / 2 - r, width: r * 2, height: r * 2))
        }
    }
}


/// 带内边距的标签（取景框左上角的实况进度条用）
final class PaddedLabel: UILabel {
    var inset = UIEdgeInsets(top: 4, left: 11, bottom: 4, right: 11)
    override func drawText(in rect: CGRect) { super.drawText(in: rect.inset(by: inset)) }
    override var intrinsicContentSize: CGSize {
        let s = super.intrinsicContentSize
        return CGSize(width: s.width + inset.left + inset.right, height: s.height + inset.top + inset.bottom)
    }
}
