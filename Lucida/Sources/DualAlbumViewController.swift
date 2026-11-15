import UIKit
import AVKit

/// 双摄相册：这次拍到的照片 / 视频，最新的排在左上角。默认一页 6 张大图（2 列），双指捏合 / 张开像苹果相册一样改列数；
/// 点开全屏查看，可左右翻页、双指缩放、双击放大。「导入」= 关闭相机并把它们导入澄影相册。
final class DualAlbumViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var items: [DualCamViewController.Item] = []        // 拍摄顺序（旧 → 新）
    var onImport: (() -> Void)?
    private var shown: [DualCamViewController.Item] { items.reversed() }    // 新 → 旧
    private var cv: UICollectionView!
    private var cols = 2
    private var cache = NSCache<NSNumber, UIImage>()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black; overrideUserInterfaceStyle = .dark
        let back = DualCircleButton(symbol: "chevron.down", size: 38); back.setGlass(DualSettings.shared.glass)
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        let t = UILabel(); t.text = "相册 \(items.count) 项"; t.textColor = .white; t.font = .systemFont(ofSize: 17, weight: .semibold)
        let imp = UIButton(type: .system); imp.setTitle("导入", for: .normal); imp.tintColor = dualYellow
        imp.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        imp.addTarget(self, action: #selector(doImport), for: .touchUpInside)
        let bar = UIView(); bar.translatesAutoresizingMaskIntoConstraints = false
        [back, t, imp].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview($0) }
        let lay = UICollectionViewFlowLayout(); lay.minimumInteritemSpacing = 2; lay.minimumLineSpacing = 2
        cv = UICollectionView(frame: .zero, collectionViewLayout: lay); cv.backgroundColor = .black
        cv.dataSource = self; cv.delegate = self; cv.translatesAutoresizingMaskIntoConstraints = false
        cv.register(AlbumCell.self, forCellWithReuseIdentifier: "c")
        cv.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        view.addSubview(bar); view.addSubview(cv)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 52),
            back.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 14), back.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            t.centerXAnchor.constraint(equalTo: bar.centerXAnchor), t.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            imp.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -16), imp.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
            cv.topAnchor.constraint(equalTo: bar.bottomAnchor), cv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: view.trailingAnchor), cv.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        if items.isEmpty {
            let e = UILabel(); e.text = "还没有拍摄内容"; e.textColor = UIColor(white: 1, alpha: 0.5); e.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(e); e.centerXAnchor.constraint(equalTo: view.centerXAnchor).isActive = true; e.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true
        }
    }
    @objc private func close() { dismiss(animated: true) }
    @objc private func doImport() { dismiss(animated: true) { self.onImport?() } }

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

    func collectionView(_ c: UICollectionView, numberOfItemsInSection s: Int) -> Int { items.count }
    func collectionView(_ c: UICollectionView, layout l: UICollectionViewLayout, sizeForItemAt i: IndexPath) -> CGSize {
        let w = floor((c.bounds.width - CGFloat(cols - 1) * 2) / CGFloat(cols)); return CGSize(width: w, height: w)
    }
    func collectionView(_ c: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        let cell = c.dequeueReusableCell(withReuseIdentifier: "c", for: ip) as! AlbumCell
        let it = shown[ip.item]
        cell.tag = ip.item
        cell.isVideo = it.kind == "video"
        if let im = cache.object(forKey: NSNumber(value: ip.item)) { cell.iv.image = im } else {
            cell.iv.image = nil
            DispatchQueue.global(qos: .userInitiated).async {
                let im = DualAlbumViewController.thumb(it, max: 700)
                DispatchQueue.main.async {
                    if let im = im { self.cache.setObject(im, forKey: NSNumber(value: ip.item)) }
                    if cell.tag == ip.item { cell.iv.image = im }
                }
            }
        }
        return cell
    }
    func collectionView(_ c: UICollectionView, didSelectItemAt ip: IndexPath) {
        let v = DualPhotoViewer(); v.items = shown; v.start = ip.item
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
    private let badge = UIImageView(image: UIImage(systemName: "play.circle.fill"))
    var isVideo = false { didSet { badge.isHidden = !isVideo } }
    override init(frame: CGRect) {
        super.init(frame: frame)
        iv.contentMode = .scaleAspectFill; iv.clipsToBounds = true; iv.backgroundColor = UIColor(white: 0.15, alpha: 1)
        iv.frame = contentView.bounds; iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(iv)
        badge.tintColor = .white; badge.frame = CGRect(x: 8, y: frame.height - 32, width: 24, height: 24); badge.autoresizingMask = [.flexibleTopMargin]
        contentView.addSubview(badge); badge.isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }
}

/// 全屏查看：左右翻页，双指缩放，双击放大 / 还原；视频点中间播放
final class DualPhotoViewer: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var items: [DualCamViewController.Item] = []
    var start = 0
    private var cv: UICollectionView!
    private var didScroll = false

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
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !didScroll, !items.isEmpty { didScroll = true; cv.layoutIfNeeded(); cv.scrollToItem(at: IndexPath(item: start, section: 0), at: .centeredHorizontally, animated: false) }
    }
    override var prefersStatusBarHidden: Bool { true }
    @objc private func close() { dismiss(animated: true) }
    func collectionView(_ c: UICollectionView, numberOfItemsInSection s: Int) -> Int { items.count }
    func collectionView(_ c: UICollectionView, layout l: UICollectionViewLayout, sizeForItemAt i: IndexPath) -> CGSize { c.bounds.size }
    func collectionView(_ c: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        let cell = c.dequeueReusableCell(withReuseIdentifier: "z", for: ip) as! ZoomCell
        let it = items[ip.item]
        cell.show(it) { [weak self] in
            let p = AVPlayerViewController(); p.player = AVPlayer(url: it.url)
            self?.present(p, animated: true) { p.player?.play() }
        }
        return cell
    }
}

private final class ZoomCell: UICollectionViewCell, UIScrollViewDelegate {
    private let sv = UIScrollView(), iv = UIImageView()
    private let play = UIButton(type: .system)
    private var onPlay: (() -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        sv.delegate = self; sv.minimumZoomScale = 1; sv.maximumZoomScale = 5
        sv.showsHorizontalScrollIndicator = false; sv.showsVerticalScrollIndicator = false
        sv.frame = contentView.bounds; sv.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(sv)
        iv.contentMode = .scaleAspectFit; sv.addSubview(iv)
        let dt = UITapGestureRecognizer(target: self, action: #selector(dbl(_:))); dt.numberOfTapsRequired = 2
        sv.addGestureRecognizer(dt)
        play.setImage(UIImage(systemName: "play.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 64)), for: .normal)
        play.tintColor = .white; play.addTarget(self, action: #selector(tapPlay), for: .touchUpInside)
        contentView.addSubview(play)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layoutSubviews() {
        super.layoutSubviews()
        if sv.zoomScale == 1 { iv.frame = sv.bounds }
        play.frame = CGRect(x: bounds.midX - 40, y: bounds.midY - 40, width: 80, height: 80)
    }
    func show(_ it: DualCamViewController.Item, onPlay: @escaping () -> Void) {
        self.onPlay = onPlay
        sv.zoomScale = 1
        play.isHidden = it.kind != "video"
        iv.image = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let im = DualAlbumViewController.thumb(it, max: 3000)
            DispatchQueue.main.async { self.iv.image = im }
        }
    }
    @objc private func tapPlay() { onPlay?() }
    func viewForZooming(in scrollView: UIScrollView) -> UIView? { play.isHidden ? iv : nil }
    func scrollViewDidZoom(_ s: UIScrollView) {
        // 缩小到比屏幕小时居中
        let dx = max(0, (s.bounds.width - iv.frame.width) / 2), dy = max(0, (s.bounds.height - iv.frame.height) / 2)
        iv.center = CGPoint(x: iv.frame.width / 2 + dx, y: iv.frame.height / 2 + dy)
    }
    @objc private func dbl(_ g: UITapGestureRecognizer) {
        guard play.isHidden else { return }
        if sv.zoomScale > 1.01 { sv.setZoomScale(1, animated: true) }
        else {
            let p = g.location(in: iv), w = sv.bounds.width / 2.5, h = sv.bounds.height / 2.5
            sv.zoom(to: CGRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), animated: true)
        }
    }
}
