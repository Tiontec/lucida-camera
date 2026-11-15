import UIKit
import AVKit

/// 双摄相册：这次拍到的照片 / 视频网格，点开全屏查看（视频可播放）。「导入」= 关闭相机并把它们导入澄影相册。
final class DualAlbumViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    var items: [DualCamViewController.Item] = []
    var onImport: (() -> Void)?
    private var cv: UICollectionView!
    private var thumbs: [Int: UIImage] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black; overrideUserInterfaceStyle = .dark
        let back = UIButton(type: .system); back.setImage(UIImage(systemName: "chevron.down"), for: .normal); back.tintColor = .white
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        let t = UILabel(); t.text = "相册 \(items.count) 项"; t.textColor = .white; t.font = .systemFont(ofSize: 17, weight: .semibold)
        let imp = UIButton(type: .system); imp.setTitle("导入", for: .normal); imp.tintColor = UIColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)
        imp.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        imp.addTarget(self, action: #selector(doImport), for: .touchUpInside)
        let bar = UIView(); bar.translatesAutoresizingMaskIntoConstraints = false
        [back, t, imp].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; bar.addSubview($0) }
        let lay = UICollectionViewFlowLayout(); lay.minimumInteritemSpacing = 2; lay.minimumLineSpacing = 2
        cv = UICollectionView(frame: .zero, collectionViewLayout: lay); cv.backgroundColor = .black
        cv.dataSource = self; cv.delegate = self; cv.translatesAutoresizingMaskIntoConstraints = false
        cv.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "c")
        view.addSubview(bar); view.addSubview(cv)
        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor), bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor), bar.heightAnchor.constraint(equalToConstant: 48),
            back.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 16), back.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
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

    func collectionView(_ c: UICollectionView, numberOfItemsInSection s: Int) -> Int { items.count }
    func collectionView(_ c: UICollectionView, layout l: UICollectionViewLayout, sizeForItemAt i: IndexPath) -> CGSize {
        let w = (c.bounds.width - 6) / 4; return CGSize(width: w, height: w)
    }
    func collectionView(_ c: UICollectionView, cellForItemAt ip: IndexPath) -> UICollectionViewCell {
        let cell = c.dequeueReusableCell(withReuseIdentifier: "c", for: ip)
        cell.contentView.subviews.forEach { $0.removeFromSuperview() }
        let iv = UIImageView(frame: cell.contentView.bounds); iv.contentMode = .scaleAspectFill; iv.clipsToBounds = true
        iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]; iv.backgroundColor = UIColor(white: 0.15, alpha: 1)
        cell.contentView.addSubview(iv)
        let it = items[ip.item]
        if it.kind == "video" {
            let m = UILabel(frame: CGRect(x: 4, y: cell.bounds.height - 20, width: 40, height: 16)); m.text = "▶"; m.textColor = .white; m.font = .systemFont(ofSize: 12)
            cell.contentView.addSubview(m)
        }
        if let im = thumbs[ip.item] { iv.image = im } else {
            DispatchQueue.global(qos: .utility).async {
                let im = DualAlbumViewController.thumb(it)
                DispatchQueue.main.async { self.thumbs[ip.item] = im; iv.image = im }
            }
        }
        return cell
    }
    static func thumb(_ it: DualCamViewController.Item) -> UIImage? {
        if it.kind == "video" {
            let g = AVAssetImageGenerator(asset: AVURLAsset(url: it.url)); g.appliesPreferredTrackTransform = true
            g.maximumSize = CGSize(width: 400, height: 400)
            if let cg = try? g.copyCGImage(at: .zero, actualTime: nil) { return UIImage(cgImage: cg) }
            return nil
        }
        return UIImage(contentsOfFile: it.url.path)
    }
    func collectionView(_ c: UICollectionView, didSelectItemAt ip: IndexPath) {
        let it = items[ip.item]
        if it.kind == "video" {
            let p = AVPlayerViewController(); p.player = AVPlayer(url: it.url)
            present(p, animated: true) { p.player?.play() }
        } else {
            let v = UIViewController(); v.view.backgroundColor = .black
            let iv = UIImageView(image: UIImage(contentsOfFile: it.url.path)); iv.contentMode = .scaleAspectFit; iv.frame = v.view.bounds
            iv.autoresizingMask = [.flexibleWidth, .flexibleHeight]; iv.isUserInteractionEnabled = true
            iv.addGestureRecognizer(UITapGestureRecognizer(target: v, action: #selector(UIViewController.dismissSelf)))
            v.view.addSubview(iv); v.modalPresentationStyle = .fullScreen; present(v, animated: true)
        }
    }
}
extension UIViewController { @objc func dismissSelf() { dismiss(animated: true) } }
