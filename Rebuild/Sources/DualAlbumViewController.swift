import UIKit
import AVKit
import Photos
import PhotosUI

/// 相册里的一项：系统相册里的资源（正常情况），或者本次拍摄留下的文件（没有系统相册读取权限时的后备）
enum DualEntry {
    case asset(PHAsset)
    case file(DualCamViewController.Item)

    var id: String {
        switch self { case .asset(let a): return a.localIdentifier; case .file(let i): return i.url.path }
    }
    var isVideo: Bool {
        switch self { case .asset(let a): return a.mediaType == .video; case .file(let i): return i.kind == "video" }
    }
    var isLive: Bool {
        if case .asset(let a) = self { return DualLibrary.isLive(a) }
        return false
    }
    var duration: TimeInterval {
        if case .asset(let a) = self { return a.duration }
        return 0
    }
}

/// 双摄相册：澄影双摄拍到的所有照片 / 实况 / 视频（取自系统相册，重开 App 还在，最新的排在左上角）。
/// 默认一页 6 张大图（2 列），双指捏合 / 张开改列数；点开全屏查看（实况可播放、可删除）；「选择」可多选删除；
/// 删除会同时删掉系统相册里的那一份，在「照片」App 里删掉的也会自动从这里消失。「导入」= 关闭相机并把本次拍的导入澄影相册。
final class DualAlbumViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout, PHPhotoLibraryChangeObserver {
    var items: [DualCamViewController.Item] = []        // 本次拍摄（拍摄顺序，旧 → 新）
    var onImport: (() -> Void)?
    var onClose: (() -> Void)?

    private var entries: [DualEntry] = []               // 新 → 旧
    private var libraryMode = false
    private var cv: UICollectionView!
    private var cols = 2
    private let titleLabel = UILabel(), emptyLabel = UILabel()
    private let banner = UIButton(type: .system)
    private var bannerH: NSLayoutConstraint!
    private let selectBtn = UIButton(type: .system), importBtn = UIButton(type: .system)
    private let delBtn = UIButton(type: .system)
    private var selecting = false
    private var picked = Set<String>()
    private let mgr = PHCachingImageManager()
    private let fileCache = NSCache<NSString, UIImage>()

    deinit { PHPhotoLibrary.shared().unregisterChangeObserver(self) }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black; overrideUserInterfaceStyle = .dark
        let back = DualCircleButton(symbol: "chevron.down", size: 38); back.setGlass(DualSettings.shared.glass)
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        titleLabel.textColor = .white; titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        importBtn.setTitle("导入", for: .normal); importBtn.tintColor = dualYellow; importBtn.isHidden = true
        importBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        importBtn.addTarget(self, action: #selector(doImport), for: .touchUpInside)
        selectBtn.setTitle("选择", for: .normal); selectBtn.tintColor = .white
        selectBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        selectBtn.addTarget(self, action: #selector(toggleSelect), for: .touchUpInside)
        let bar = UIView(); bar.translatesAutoresizingMaskIntoConstraints = false
        [back, titleLabel, selectBtn, importBtn].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview($0) }

        banner.setTitle("只显示本次拍摄。要看到以前拍的、并和系统相册同步删除：设置 → 澄影 → 照片 → 读取和写入（点这里打开设置）", for: .normal)
        banner.titleLabel?.numberOfLines = 0; banner.titleLabel?.font = .systemFont(ofSize: 12); banner.tintColor = dualYellow
        banner.contentEdgeInsets = UIEdgeInsets(top: 4, left: 14, bottom: 4, right: 14)
        banner.titleLabel?.textAlignment = .center; banner.clipsToBounds = true
        banner.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        banner.translatesAutoresizingMaskIntoConstraints = false

        let lay = UICollectionViewFlowLayout(); lay.minimumInteritemSpacing = 2; lay.minimumLineSpacing = 2
        cv = UICollectionView(frame: .zero, collectionViewLayout: lay); cv.backgroundColor = .black
        cv.dataSource = self; cv.delegate = self; cv.translatesAutoresizingMaskIntoConstraints = false
        cv.register(AlbumCell.self, forCellWithReuseIdentifier: "c")
        cv.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))

        delBtn.setTitle("删除", for: .normal); delBtn.setTitleColor(.white, for: .normal)
        delBtn.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        delBtn.backgroundColor = UIColor(red: 0.92, green: 0.22, blue: 0.2, alpha: 0.95); delBtn.layer.cornerRadius = 22
        delBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: 26, bottom: 0, right: 26)
        delBtn.addTarget(self, action: #selector(deletePicked), for: .touchUpInside)
        delBtn.translatesAutoresizingMaskIntoConstraints = false; delBtn.isHidden = true

        emptyLabel.text = "还没有拍摄内容"; emptyLabel.textColor = UIColor(white: 1, alpha: 0.5)
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false; emptyLabel.isHidden = true

        view.addSubview(bar); view.addSubview(banner); view.addSubview(cv); view.addSubview(emptyLabel); view.addSubview(delBtn)
        bannerH = banner.heightAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 52),
            back.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14), back.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: bar.centerXAnchor), titleLabel.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            importBtn.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16), importBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            selectBtn.trailingAnchor.constraint(equalTo: importBtn.leadingAnchor, constant: -16), selectBtn.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            banner.topAnchor.constraint(equalTo: bar.bottomAnchor), banner.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: view.trailingAnchor), bannerH,
            cv.topAnchor.constraint(equalTo: banner.bottomAnchor), cv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: view.trailingAnchor), cv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor), emptyLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            delBtn.centerXAnchor.constraint(equalTo: view.centerXAnchor), delBtn.heightAnchor.constraint(equalToConstant: 44),
            delBtn.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -14)])

        PHPhotoLibrary.shared().register(self)
        reload()
        // 第一次打开、还没问过读取权限：问一下，给了就重新载入
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
            PhotoSaver.auth { [weak self] _ in self?.reload() }
        }
    }

    /// 系统相册有变化（比如在「照片」App 里删了东西）：重新取一遍
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [weak self] in self?.reload() }
    }

    private func reload() {
        libraryMode = PhotoSaver.canRead
        if libraryMode { entries = DualLibrary.fetch().map { DualEntry.asset($0) } }
        else { entries = items.reversed().map { DualEntry.file($0) } }
        let alive = Set(entries.map { $0.id })
        picked = picked.filter { alive.contains($0) }
        titleLabel.text = "相册 \(entries.count) 项"
        emptyLabel.isHidden = !entries.isEmpty
        bannerH.constant = libraryMode ? 0 : 52
        banner.isHidden = libraryMode
        selectBtn.isHidden = !libraryMode || entries.isEmpty
        if (!libraryMode || entries.isEmpty) && selecting { selecting = false; selectBtn.setTitle("选择", for: .normal) }
        syncDelete()
        cv?.reloadData()
    }

    @objc private func close() { dismiss(animated: true) { self.onClose?() } }
    @objc private func doImport() { dismiss(animated: true) { self.onImport?() } }
    @objc private func openSettings() {
        if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) }
    }

    @objc private func toggleSelect() {
        selecting.toggle(); picked.removeAll()
        selectBtn.setTitle(selecting ? "取消" : "选择", for: .normal)
        syncDelete(); cv.reloadData()
    }

    private func syncDelete() {
        delBtn.isHidden = !(selecting && !picked.isEmpty)
        delBtn.setTitle("删除（\(picked.count)）", for: .normal)
    }

    @objc private func deletePicked() {
        let list = entries.compactMap { e -> PHAsset? in
            if case .asset(let a) = e, picked.contains(a.localIdentifier) { return a }
            return nil
        }
        DualLibrary.delete(list) { [weak self] ok in
            guard let self = self, ok else { return }
            self.picked.removeAll(); self.selecting = false
            self.selectBtn.setTitle("选择", for: .normal)
            self.reload()
        }
    }

    /// 捏合：张开 = 变大（列数减少），捏紧 = 变小（列数增加）
    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        guard g.state == .changed else { return }
        var n = cols
        if g.scale > 1.25 { n = max(1, cols - 1) } else if g.scale < 0.8 { n = min(6, cols + 1) } else { return }
        g.scale = 1
        guard n != cols else { return }
        cols = n
        UIView.animate(withDuration: 0.3) {
            self.cv.collectionViewLayout.invalidateLayout()
            self.cv.layoutIfNeeded()
        }
    }

    func collectionView(_ c: UICollectionView, numberOfItemsInSection s: Int) -> Int { entries.count }
    func collectionView(_ c: UICollectionView, layout l: UICollectionViewLayout, sizeForItemAt i: IndexPath) -> CGSize {
        let w = floor((c.bounds.width - CGFloat(cols - 1) * 2) / CGFloat(cols)); return CGSize(width: w, height: w)
    }
    func collectionView(_ c: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        let cell = c.dequeueReusableCell(withReuseIdentifier: "c", for: ip) as! AlbumCell
        let e = entries[ip.item]
        cell.entryID = e.id
        cell.iv.image = nil
        cell.set(video: e.isVideo, live: e.isLive, duration: e.duration)
        cell.set(selecting: selecting, picked: picked.contains(e.id))
        let side = floor((c.bounds.width - CGFloat(cols - 1) * 2) / CGFloat(cols))
        switch e {
        case .asset(let a):
            let px = side * UIScreen.main.scale
            let o = PHImageRequestOptions(); o.deliveryMode = .opportunistic; o.resizeMode = .fast; o.isNetworkAccessAllowed = true
            mgr.requestImage(for: a, targetSize: CGSize(width: px, height: px), contentMode: .aspectFill, options: o) { im, _ in
                if cell.entryID == a.localIdentifier, let im = im { cell.iv.image = im }
            }
        case .file(let it):
            let key = it.url.path as NSString
            if let im = fileCache.object(forKey: key) { cell.iv.image = im } else {
                DispatchQueue.global(qos: .userInitiated).async {
                    let im = DualAlbumViewController.thumb(it, max: 700)
                    DispatchQueue.main.async {
                        if let im = im { self.fileCache.setObject(im, forKey: key) }
                        if cell.entryID == e.id { cell.iv.image = im }
                    }
                }
            }
        }
        return cell
    }
    func collectionView(_ c: UICollectionView, didSelectItemAt ip: IndexPath) {
        let e = entries[ip.item]
        if selecting {
            if picked.contains(e.id) { picked.remove(e.id) } else { picked.insert(e.id) }
            syncDelete()
            if let cell = c.cellForItem(at: ip) as? AlbumCell { cell.set(selecting: true, picked: picked.contains(e.id)) }
            return
        }
        let v = DualPhotoViewer(); v.entries = entries; v.start = ip.item
        v.onDeleted = { [weak self] in self?.reload() }
        v.modalPresentationStyle = .fullScreen; present(v, animated: true)
    }

    static func thumb(_ it: DualCamViewController.Item, max: CGFloat = 400) -> UIImage? {
        if it.kind == "video" {
            let g = AVAssetImageGenerator(asset: AVURLAsset(url: it.url)); g.appliesPreferredTrackTransform = true
            g.maximumSize = CGSize(width: max, height: max)
            if let cg = try? g.copyCGImage(at: .zero, actualTime: nil) { return UIImage(cgImage: cg) }
            return nil
        }
        let opts: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceThumbnailMaxPixelSize: max]
        if let src = CGImageSourceCreateWithURL(it.url as CFURL, nil), let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) { return UIImage(cgImage: cg) }
        return nil
    }
}

private final class AlbumCell: UICollectionViewCell {
    let iv = UIImageView()
    var entryID = ""
    private let badge = UIImageView(image: UIImage(systemName: "play.circle.fill"))
    private let live = UIImageView(image: UIImage(systemName: "livephoto"))
    private let dur = UILabel()
    private let dim = UIView(), check = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        iv.contentMode = .scaleAspectFill; iv.clipsToBounds = true; iv.backgroundColor = UIColor(white: 0.15, alpha: 1)
        iv.frame = contentView.bounds; iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(iv)
        badge.tintColor = .white; badge.frame = CGRect(x: 8, y: frame.height - 32, width: 24, height: 24); badge.autoresizingMask = [.flexibleTopMargin]
        contentView.addSubview(badge); badge.isHidden = true
        live.tintColor = .white; live.frame = CGRect(x: 8, y: 8, width: 20, height: 20); live.isHidden = true
        contentView.addSubview(live)
        dur.textColor = .white; dur.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold); dur.textAlignment = .right
        dur.frame = CGRect(x: frame.width - 58, y: frame.height - 26, width: 50, height: 18)
        dur.autoresizingMask = [.flexibleLeftMargin, .flexibleTopMargin]; dur.isHidden = true
        contentView.addSubview(dur)
        dim.backgroundColor = UIColor(white: 0, alpha: 0.35); dim.frame = contentView.bounds; dim.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dim.isHidden = true; contentView.addSubview(dim)
        check.tintColor = .white; check.frame = CGRect(x: frame.width - 32, y: 8, width: 24, height: 24)
        check.autoresizingMask = [.flexibleLeftMargin]; check.isHidden = true
        contentView.addSubview(check)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(video: Bool, live isLive: Bool, duration: TimeInterval) {
        badge.isHidden = !video
        live.isHidden = !isLive
        dur.isHidden = !video || duration <= 0
        if video, duration > 0 { let s = Int(duration.rounded()); dur.text = String(format: "%d:%02d", s / 60, s % 60) }
    }

    func set(selecting: Bool, picked: Bool) {
        check.isHidden = !selecting
        dim.isHidden = !(selecting && picked)
        check.image = UIImage(systemName: picked ? "checkmark.circle.fill" : "circle")
        check.tintColor = picked ? dualYellow : UIColor(white: 1, alpha: 0.9)
    }
}

/// 全屏查看：左右翻页，双指缩放，双击放大 / 还原；实况按住播放（翻到时自动播一次）；视频点中间播放；右上角可删除
final class DualPhotoViewer: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var entries: [DualEntry] = []
    var start = 0
    var onDeleted: (() -> Void)?
    private var cv: UICollectionView!
    private var didScroll = false
    private var playIndex = -1
    private var trash: DualCircleButton!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let lay = UICollectionViewFlowLayout(); lay.scrollDirection = .horizontal; lay.minimumLineSpacing = 0; lay.minimumInteritemSpacing = 0
        cv = UICollectionView(frame: .zero, collectionViewLayout: lay); cv.isPagingEnabled = true; cv.backgroundColor = .black
        cv.dataSource = self; cv.delegate = self; cv.showsHorizontalScrollIndicator = false
        cv.register(ZoomCell.self, forCellWithReuseIdentifier: "z")
        cv.frame = view.bounds; cv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(cv)
        let back = DualCircleButton(symbol: "chevron.left", size: 40); back.setGlass(DualSettings.shared.glass)
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(back)
        back.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14).isActive = true
        back.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6).isActive = true
        trash = DualCircleButton(symbol: "trash", size: 40); trash.setGlass(DualSettings.shared.glass)
        trash.addTarget(self, action: #selector(deleteCurrent), for: .touchUpInside)
        view.addSubview(trash)
        trash.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14).isActive = true
        trash.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6).isActive = true
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didScroll, !entries.isEmpty {
            didScroll = true; cv.layoutIfNeeded()
            cv.scrollToItem(at: IndexPath(item: min(start, entries.count - 1), section: 0), at: .centeredHorizontally, animated: false)
            syncPage()
        }
    }
    override var prefersStatusBarHidden: Bool { true }
    @objc private func close() { dismiss(animated: true) }

    private func currentIndex() -> Int {
        guard !entries.isEmpty else { return 0 }
        return max(0, min(entries.count - 1, Int((cv.contentOffset.x / max(1, cv.bounds.width)).rounded())))
    }

    /// 翻到哪页：删除键只在系统相册资源上出现；当前页是实况就自动播一次，其它页停掉
    private func syncPage() {
        guard !entries.isEmpty else { return }
        let i = currentIndex()
        if case .asset = entries[i] { trash.isHidden = false } else { trash.isHidden = true }
        guard i != playIndex else { return }
        playIndex = i
        for c in cv.visibleCells {
            guard let z = c as? ZoomCell, let ip = cv.indexPath(for: c) else { continue }
            z.setCurrent(ip.item == i)
        }
    }
    func scrollViewDidScroll(_ s: UIScrollView) { if s === cv { syncPage() } }

    @objc private func deleteCurrent() {
        guard !entries.isEmpty, case .asset(let a) = entries[currentIndex()] else { return }
        let idx = currentIndex()
        DualLibrary.delete([a]) { [weak self] ok in
            guard let self = self, ok else { return }
            self.entries.remove(at: idx)
            self.onDeleted?()
            if self.entries.isEmpty { self.dismiss(animated: true); return }
            self.playIndex = -1
            self.cv.deleteItems(at: [IndexPath(item: idx, section: 0)])
            self.syncPage()
        }
    }

    func collectionView(_ c: UICollectionView, numberOfItemsInSection s: Int) -> Int { entries.count }
    func collectionView(_ c: UICollectionView, layout l: UICollectionViewLayout, sizeForItemAt i: IndexPath) -> CGSize { c.bounds.size }
    func collectionView(_ c: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        let cell = c.dequeueReusableCell(withReuseIdentifier: "z", for: ip) as! ZoomCell
        let e = entries[ip.item]
        cell.show(e, current: ip.item == currentIndex() && didScroll) { [weak self] in
            switch e {
            case .file(let it):
                let p = AVPlayerViewController(); p.player = AVPlayer(url: it.url)
                self?.present(p, animated: true) { p.player?.play() }
            case .asset(let a):
                let o = PHVideoRequestOptions(); o.isNetworkAccessAllowed = true
                PHImageManager.default().requestPlayerItem(forVideo: a, options: o) { item, _ in
                    guard let item = item else { return }
                    DispatchQueue.main.async {
                        let p = AVPlayerViewController(); p.player = AVPlayer(playerItem: item)
                        self?.present(p, animated: true) { p.player?.play() }
                    }
                }
            }
        }
        return cell
    }
    func collectionView(_ c: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt ip: IndexPath) {
        (cell as? ZoomCell)?.setCurrent(false)
    }
}

private final class ZoomCell: UICollectionViewCell, UIScrollViewDelegate {
    private let sv = UIScrollView(), iv = UIImageView(), lpv = PHLivePhotoView()
    private let play = UIButton(type: .system)
    private let liveTag = UILabel()
    private var onPlay: (() -> Void)?
    private var assetID: String?
    private var isCurrent = false
    private var content: UIView { lpv.isHidden ? iv : lpv }

    override init(frame: CGRect) {
        super.init(frame: frame)
        sv.delegate = self; sv.minimumZoomScale = 1; sv.maximumZoomScale = 5
        sv.showsHorizontalScrollIndicator = false; sv.showsVerticalScrollIndicator = false
        sv.frame = contentView.bounds; sv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(sv)
        iv.contentMode = .scaleAspectFit; sv.addSubview(iv)
        lpv.contentMode = .scaleAspectFit; lpv.isHidden = true; sv.addSubview(lpv)
        let dt = UITapGestureRecognizer(target: self, action: #selector(dbl(_:))); dt.numberOfTapsRequired = 2
        sv.addGestureRecognizer(dt)
        play.setImage(UIImage(systemName: "play.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 64)), for: .normal)
        play.tintColor = .white; play.addTarget(self, action: #selector(tapPlay), for: .touchUpInside)
        contentView.addSubview(play)
        liveTag.text = "  ◉ 实况 · 按住画面播放  "; liveTag.textColor = .white; liveTag.font = .systemFont(ofSize: 12, weight: .semibold)
        liveTag.backgroundColor = UIColor(white: 0, alpha: 0.45); liveTag.layer.cornerRadius = 11; liveTag.clipsToBounds = true
        liveTag.textAlignment = .center; liveTag.isHidden = true
        contentView.addSubview(liveTag)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        if sv.zoomScale == 1 { iv.frame = sv.bounds; lpv.frame = sv.bounds }
        play.frame = CGRect(x: bounds.midX - 40, y: bounds.midY - 40, width: 80, height: 80)
        liveTag.frame = CGRect(x: bounds.midX - 80, y: safeAreaInsets.top + 14, width: 160, height: 22)
    }

    func show(_ e: DualEntry, current: Bool, onPlay: @escaping () -> Void) {
        self.onPlay = onPlay
        isCurrent = current
        sv.zoomScale = 1
        play.isHidden = !e.isVideo
        liveTag.isHidden = !e.isLive
        iv.image = nil; iv.isHidden = false
        lpv.stopPlayback(); lpv.livePhoto = nil; lpv.isHidden = true
        assetID = e.id
        setNeedsLayout()
        switch e {
        case .file(let it):
            DispatchQueue.global(qos: .userInitiated).async {
                let im = DualAlbumViewController.thumb(it, max: 3000)
                DispatchQueue.main.async { if self.assetID == e.id { self.iv.image = im } }
            }
        case .asset(let a):
            let o = PHImageRequestOptions(); o.deliveryMode = .opportunistic; o.isNetworkAccessAllowed = true
            let big: CGFloat = DualLibrary.isLive(a) ? 1600 : 3000
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: big, height: big), contentMode: .aspectFit, options: o) { im, _ in
                if self.assetID == e.id, let im = im, self.lpv.isHidden { self.iv.image = im }
            }
            if DualLibrary.isLive(a) {
                let lo = PHLivePhotoRequestOptions(); lo.deliveryMode = .highQualityFormat; lo.isNetworkAccessAllowed = true
                PHImageManager.default().requestLivePhoto(for: a, targetSize: CGSize(width: 1600, height: 1600), contentMode: .aspectFit, options: lo) { lp, _ in
                    guard self.assetID == e.id, let lp = lp else { return }
                    self.lpv.livePhoto = lp; self.lpv.isHidden = false; self.iv.isHidden = true
                    self.setNeedsLayout()
                    if self.isCurrent { self.lpv.startPlayback(with: .full) }
                }
            }
        }
    }

    /// 翻到这一页 = 自动播一次实况；翻走 = 停
    func setCurrent(_ on: Bool) {
        isCurrent = on
        if on { if !lpv.isHidden { lpv.startPlayback(with: .full) } } else { lpv.stopPlayback() }
    }

    @objc private func tapPlay() { onPlay?() }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { play.isHidden ? content : nil }
    func scrollViewDidZoom(_ s: UIScrollView) {
        // 缩小到比屏幕小时居中
        let v = content
        let dx = max(0, (s.bounds.width - v.frame.width) / 2), dy = max(0, (s.bounds.height - v.frame.height) / 2)
        v.center = CGPoint(x: v.frame.width / 2 + dx, y: v.frame.height / 2 + dy)
    }
    @objc private func dbl(_ g: UITapGestureRecognizer) {
        guard play.isHidden else { return }
        if sv.zoomScale > 1.01 { sv.setZoomScale(1, animated: true) }
        else {
            let p = g.location(in: content), w = sv.bounds.width / 2.5, h = sv.bounds.height / 2.5
            sv.zoom(to: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: true)
        }
    }
}
