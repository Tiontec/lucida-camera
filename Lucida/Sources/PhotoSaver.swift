import Foundation
import Photos
import ImageIO

enum PhotoSaver {
    /// 申请「只添加」权限（保存用）
    static func auth(_ done: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { s in
            DispatchQueue.main.async { done(s == .authorized || s == .limited) }
        }
    }

    /// 把一个照片 / 视频文件写入系统相册
    static func save(file: URL, isVideo: Bool, completion: @escaping (Bool, String?) -> Void) {
        auth { ok in
            guard ok else { completion(false, "没有系统相册权限（设置 → 澄影 → 照片 → 允许添加）"); return }
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                let o = PHAssetResourceCreationOptions()
                o.shouldMoveFile = false
                req.addResource(with: isVideo ? .video : .photo, fileURL: file, options: o)
            }, completionHandler: { success, err in
                DispatchQueue.main.async { completion(success, err?.localizedDescription) }
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
