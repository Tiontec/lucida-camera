import Foundation
import Photos

/// 双摄相册和系统相册的桥：
///  · 每次用双摄拍到的照片 / 实况 / 视频存进系统相册时，把它在系统里的 localIdentifier 登记下来（UserDefaults，重开 App 还在）
///  · 双摄相册 = 按登记表去系统相册里取这些资源。所以在「照片」App 里删掉的，这里自然不再出现（系统 → 双摄的删除同步）；
///    在双摄相册里删，是直接删系统相册里的那一份（双摄 → 系统的删除同步），系统会弹出它自己的确认框。
enum DualLibrary {
    private static let key = "lucida.dual.assets"

    /// 旧 → 新
    static var ids: [String] {
        get { (UserDefaults.standard.array(forKey: key) as? [String]) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }

    static func add(_ id: String?) {
        guard let id = id, !id.isEmpty else { return }
        var a = ids
        if !a.contains(id) { a.append(id); ids = a }
    }

    static func remove(_ gone: [String]) {
        guard !gone.isEmpty else { return }
        let s = Set(gone)
        ids = ids.filter { !s.contains($0) }
    }

    /// 只留下仍然存在的那些（系统相册里已被删掉的从登记里去掉）
    static func prune(keeping alive: Set<String>) {
        ids = ids.filter { alive.contains($0) }
    }

    /// 取出登记过的、仍在系统相册里的资源，新 → 旧。没有读取权限时返回空。
    /// 相册里显示的内容：系统相册里全部的照片和视频（新的在前，最多 2000 条）。
    /// 澄影拍的动态照片还是靠 ids 识别（DualAlbum 里的 AlbumCell 用 PHAsset.mediaSubtypes 判断实况）。
    static func fetch() -> [PHAsset] {
        guard PhotoSaver.canRead else { return [] }
        let opts = PHFetchOptions()
        opts.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        opts.predicate = NSPredicate(format: "mediaType == %d || mediaType == %d",
                                     PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue)
        opts.fetchLimit = 2000
        let res = PHAsset.fetchAssets(with: opts)
        var out: [PHAsset] = []
        out.reserveCapacity(res.count)
        res.enumerateObjects { a, _, _ in out.append(a) }
        return out
    }

    /// 从系统相册删除（系统会弹确认框）。completion(是否真的删了)
    static func delete(_ assets: [PHAsset], completion: @escaping (Bool) -> Void) {
        guard !assets.isEmpty else { completion(true); return }
        let gone = assets.map { $0.localIdentifier }
        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }, completionHandler: { ok, _ in
            DispatchQueue.main.async {
                if ok { remove(gone) }
                completion(ok)
            }
        })
    }

    static func isLive(_ a: PHAsset) -> Bool { a.mediaSubtypes.contains(.photoLive) }
}
