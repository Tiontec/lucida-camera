import UIKit
import PhotosUI
import Photos
import UniformTypeIdentifiers

/// 原生选择器：导入照片 / 视频 / 实况。
/// 实况会把「照片 + 配对视频」两个文件一起交给网页（同名不同后缀），网页的导入流程会自动合成一张可编辑的实况。
final class LivePicker: NSObject, PHPickerViewControllerDelegate {
    private static var current: LivePicker?
    private var completion: (([[String: Any]]) -> Void)?

    static func present(on vc: UIViewController, live: Bool, limit: Int,
                        completion: @escaping ([[String: Any]]) -> Void) {
        // 想读到实况的原始资源需要「读写」权限；没给也能选，只是实况会退化为静态照片
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { _ in
            DispatchQueue.main.async {
                var cfg = PHPickerConfiguration(photoLibrary: PHPhotoLibrary.shared())
                cfg.selectionLimit = limit
                cfg.filter = live ? .livePhotos : .any(of: [.images, .videos, .livePhotos])
                cfg.preferredAssetRepresentationMode = .current
                let p = PHPickerViewController(configuration: cfg)
                let me = LivePicker()
                me.completion = completion
                p.delegate = me
                current = me
                vc.present(p, animated: true)
            }
        }
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        let done: ([[String: Any]]) -> Void = { [weak self] files in
            self?.completion?(files); self?.completion = nil; LivePicker.current = nil
        }
        if results.isEmpty { done([]); return }
        var out: [[String: Any]] = []
        let lock = NSLock()
        let group = DispatchGroup()
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let canResource = (status == .authorized || status == .limited)

        for r in results {
            var handled = false
            if canResource, let aid = r.assetIdentifier,
               let asset = PHAsset.fetchAssets(withLocalIdentifiers: [aid], options: nil).firstObject {
                handled = true
                group.enter()
                LivePicker.export(asset: asset) { files in
                    lock.lock(); out.append(contentsOf: files); lock.unlock(); group.leave()
                }
            }
            if !handled {
                group.enter()
                LivePicker.exportProvider(r.itemProvider) { files in
                    lock.lock(); out.append(contentsOf: files); lock.unlock(); group.leave()
                }
            }
        }
        group.notify(queue: .main) { done(out) }
    }

    // MARK: 通过 PHAsset 资源导出（实况：照片 + 配对视频）
    private static func export(asset: PHAsset, done: @escaping ([[String: Any]]) -> Void) {
        let res = PHAssetResource.assetResources(for: asset)
        func pick(_ types: [PHAssetResourceType]) -> PHAssetResource? {
            for t in types { if let r = res.first(where: { $0.type == t }) { return r } }
            return nil
        }
        let isVideoAsset = asset.mediaType == .video
        let photoRes = isVideoAsset ? nil : pick([.fullSizePhoto, .photo])
        let videoRes = isVideoAsset ? pick([.fullSizeVideo, .video]) : pick([.fullSizePairedVideo, .pairedVideo])
        let origName = (photoRes ?? videoRes)?.originalFilename ?? "IMG_\(Int(Date().timeIntervalSince1970))"
        let base = (origName as NSString).deletingPathExtension
        let group = DispatchGroup()
        var files: [[String: Any]] = []
        let lock = NSLock()

        func write(_ r: PHAssetResource, fileName: String, mime: String, kind: String) {
            let disk = UUID().uuidString + "-" + fileName
            let url = SchemeHandler.outDir.appendingPathComponent(disk)
            let o = PHAssetResourceRequestOptions(); o.isNetworkAccessAllowed = true
            group.enter()
            PHAssetResourceManager.default().writeData(for: r, toFile: url, options: o) { err in
                if err == nil {
                    let enc = disk.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? disk
                    lock.lock()
                    files.append(["name": fileName, "url": "lucida://file/" + enc, "mime": mime, "kind": kind])
                    lock.unlock()
                }
                group.leave()
            }
        }
        if let p = photoRes {
            var ext = (p.originalFilename as NSString).pathExtension
            if ext.isEmpty { ext = "jpg" }
            if p.type == .fullSizePhoto { ext = "jpg" }   // 编辑过的完整尺寸版本一般是 JPEG
            let mime = ext.lowercased().hasPrefix("hei") ? "image/heic" : "image/jpeg"
            write(p, fileName: base + "." + ext, mime: mime, kind: "image")
        }
        if let v = videoRes {
            write(v, fileName: base + ".mov", mime: "video/quicktime", kind: "video")
        }
        group.notify(queue: .global()) { done(files) }
    }

    // MARK: 没有相册读权限时：用 NSItemProvider 退化（实况只能拿到静态照片）
    private static func exportProvider(_ p: NSItemProvider, done: @escaping ([[String: Any]]) -> Void) {
        let types: [(String, String, String)] = [("public.movie", "video", "mov"), ("public.image", "image", "jpg")]
        for (uti, kind, defExt) in types where p.hasItemConformingToTypeIdentifier(uti) {
            p.loadFileRepresentation(forTypeIdentifier: uti) { url, _ in
                guard let url = url else { done([]); return }
                var ext = url.pathExtension; if ext.isEmpty { ext = defExt }
                let name = (url.deletingPathExtension().lastPathComponent) + "." + ext
                let disk = UUID().uuidString + "-" + name
                let dst = SchemeHandler.outDir.appendingPathComponent(disk)
                do { try FileManager.default.copyItem(at: url, to: dst) } catch { done([]); return }
                let enc = disk.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? disk
                let mime = kind == "video" ? "video/quicktime" : (ext.lowercased().hasPrefix("hei") ? "image/heic" : "image/jpeg")
                done([["name": name, "url": "lucida://file/" + enc, "mime": mime, "kind": kind]])
            }
            return
        }
        done([])
    }
}
