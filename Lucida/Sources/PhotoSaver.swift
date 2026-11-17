import Foundation
import Photos
import ImageIO

enum PhotoSaver {
    /// 申请系统相册权限（保存 + 读取）。双摄相册要读回系统相册里的内容，所以一次要「读取和写入」；
    /// 用户只给了「只添加」也照样能保存（只是双摄相册读不回来，退回只显示本次拍摄）。
    static func auth(_ done: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { s in
            DispatchQueue.main.async {
                if s == .authorized || s == .limited { done(true); return }
                done(PHPhotoLibrary.authorizationStatus(for: .addOnly) == .authorized)
            }
        }
    }

    /// 能不能读取系统相册（双摄相册用）
    static var canRead: Bool {
        let s = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return s == .authorized || s == .limited
    }

    /// 把一个照片 / 视频文件写入系统相册
    static func save(file: URL, isVideo: Bool, completion: @escaping (Bool, String?) -> Void) {
        saveWithID(file: file, isVideo: isVideo) { ok, msg, _ in completion(ok, msg) }
    }

    /// 同上，并且把新资源在系统相册里的 localIdentifier 交回来（双摄相册靠它认出「这是澄影双摄拍的」）
    static func saveWithID(file: URL, isVideo: Bool, completion: @escaping (Bool, String?, String?) -> Void) {
        auth { ok in
            guard ok else { completion(false, "没有系统相册权限（设置 → 澄影 → 照片 → 读取和写入）", nil); return }
            var newID: String?
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                let o = PHAssetResourceCreationOptions()
                o.shouldMoveFile = false
                req.addResource(with: isVideo ? .video : .photo, fileURL: file, options: o)
                newID = req.placeholderForCreatedAsset?.localIdentifier
            }, completionHandler: { success, err in
                DispatchQueue.main.async { completion(success, err?.localizedDescription, success ? newID : nil) }
            })
        }
    }

    /// JPEG / PNG → HEIC（保留 EXIF / 方向）
    static func transcodeToHEIC(_ src: URL, quality: CGFloat = 0.9) -> URL? {
        guard let s = CGImageSourceCreateWithURL(src as CFURL, nil) else { return nil }
        let out = SchemeHandler.outDir.appendingPathComponent(UUID().uuidString + ".heic")
        guard let d = CGImageDestinationCreateWithURL(out as CFURL, "public.heic" as CFString, 1, nil) else { return nil }
        var props = (CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any]) ?? [:]
        props[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImageFromSource(d, s, 0, props as CFDictionary)
        return CGImageDestinationFinalize(d) ? out : nil
    }

    /// 任意图片数据 → JPEG 文件（给网页相册预览 / 编辑用）
    static func jpegFile(from data: Data, quality: CGFloat = 0.92) -> URL? {
        guard let s = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let out = SchemeHandler.outDir.appendingPathComponent(UUID().uuidString + ".jpg")
        guard let d = CGImageDestinationCreateWithURL(out as CFURL, "public.jpeg" as CFString, 1, nil) else { return nil }
        var props = (CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [CFString: Any]) ?? [:]
        props[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImageFromSource(d, s, 0, props as CFDictionary)
        return CGImageDestinationFinalize(d) ? out : nil
    }
}
