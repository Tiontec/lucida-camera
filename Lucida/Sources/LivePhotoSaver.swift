import Foundation
import AVFoundation
import Photos
import ImageIO
import CoreMedia

/// 实况照片（Live Photo）写入。
/// 系统认定「实况」靠三样东西：
///   1. 照片（JPEG / HEIC）的 MakerApple 字典里 key "17" = 内容标识符（UUID）
///   2. 视频（MOV）的元数据 com.apple.quicktime.content.identifier = 同一个 UUID
///   3. 视频里有一条 still-image-time 定时元数据轨，标出「静帧」所在的时间点
/// 做好后用 PHAssetCreationRequest 同时加 .photo + .pairedVideo 两个资源。
enum LivePhotoSaver {

    /// 网页 saveLivePhoto 消息：{id, photo(b64), photoName, video(b64), videoName, videoMime, duration}
    static func saveFromWeb(_ body: [String: Any], completion: @escaping (Bool, String?) -> Void) {
        guard let ps = body["photo"] as? String, let vs = body["video"] as? String,
              let pd = Data(base64Encoded: ps), let vd = Data(base64Encoded: vs) else {
            completion(false, "实况数据不完整"); return
        }
        let pn = (body["photoName"] as? String) ?? "photo.jpg"
        let vn = (body["videoName"] as? String) ?? "video.mov"
        let dir = SchemeHandler.outDir
        let tag = UUID().uuidString
        let pu = dir.appendingPathComponent(tag + "-" + pn.replacingOccurrences(of: "/", with: "_"))
        let vu = dir.appendingPathComponent(tag + "-" + vn.replacingOccurrences(of: "/", with: "_"))
        do { try pd.write(to: pu); try vd.write(to: vu) } catch { completion(false, "写入临时文件失败"); return }
        let dur = (body["duration"] as? Double) ?? 0
        save(photo: pu, video: vu, duration: dur, completion: completion)
    }

    static func save(photo: URL, video: URL, duration: Double, completion: @escaping (Bool, String?) -> Void) {
        let id = UUID().uuidString
        let dir = SchemeHandler.outDir
        guard let photoOut = tagPhoto(photo, identifier: id, into: dir) else { completion(false, "照片写入标识失败"); return }
        let movOut = dir.appendingPathComponent(UUID().uuidString + ".mov")
        // 静帧取视频中间（实况封面通常在中间）
        let still = CMTime(seconds: max(0, duration / 2), preferredTimescale: 600)
        tagVideo(input: video, output: movOut, identifier: id, still: still) { ok, msg in
            guard ok else { completion(false, msg ?? "视频处理失败"); return }
            PhotoSaver.auth { granted in
                guard granted else { completion(false, "没有系统相册权限"); return }
                PHPhotoLibrary.shared().performChanges({
                    let req = PHAssetCreationRequest.forAsset()
                    req.addResource(with: .photo, fileURL: photoOut, options: nil)
                    let o = PHAssetResourceCreationOptions(); o.shouldMoveFile = false
                    req.addResource(with: .pairedVideo, fileURL: movOut, options: o)
                }, completionHandler: { success, err in
                    DispatchQueue.main.async { completion(success, err?.localizedDescription) }
                })
            }
        }
    }

    // MARK: 照片：写入内容标识符
    private static func tagPhoto(_ src: URL, identifier: String, into dir: URL) -> URL? {
        guard let s = CGImageSourceCreateWithURL(src as CFURL, nil) else { return nil }
        let out = dir.appendingPathComponent(UUID().uuidString + ".jpg")
        guard let d = CGImageDestinationCreateWithURL(out as CFURL, "public.jpeg" as CFString, 1, nil) else { return nil }
        var props = (CGImageSourceCopyPropertiesAtIndex(s, 0, nil) as? [String: Any]) ?? [:]
        var maker = (props[kCGImagePropertyMakerAppleDictionary as String] as? [String: Any]) ?? [:]
        maker["17"] = identifier
        props[kCGImagePropertyMakerAppleDictionary as String] = maker
        props[kCGImageDestinationLossyCompressionQuality as String] = 0.95
        CGImageDestinationAddImageFromSource(d, s, 0, props as CFDictionary)
        return CGImageDestinationFinalize(d) ? out : nil
    }

    // MARK: 视频：直通重封装 + 标识符 + still-image-time
    private static func tagVideo(input: URL, output: URL, identifier: String, still: CMTime,
                                 completion: @escaping (Bool, String?) -> Void) {
        let asset = AVURLAsset(url: input)
        guard let vTrack = asset.tracks(withMediaType: .video).first else { completion(false, "视频里没有画面轨（webm 不支持，请用 mp4 / mov）"); return }
        do {
            try? FileManager.default.removeItem(at: output)
            let reader = try AVAssetReader(asset: asset)
            let writer = try AVAssetWriter(outputURL: output, fileType: .mov)

            let idItem = AVMutableMetadataItem()
            idItem.keySpace = AVMetadataKeySpace.quickTimeMetadata
            idItem.key = AVMetadataKey.quickTimeMetadataKeyContentIdentifier as NSString
            idItem.value = identifier as NSString
            idItem.dataType = "com.apple.metadata.datatype.UTF-8"
            writer.metadata = [idItem]

            // 视频轨（压缩样本直通，不重新编码）
            let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: nil)
            guard reader.canAdd(vOut) else { completion(false, "无法读取视频"); return }
            reader.add(vOut)
            let hint: CMFormatDescription? = (vTrack.formatDescriptions.first).map { $0 as! CMFormatDescription }
            let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: hint)
            vIn.transform = vTrack.preferredTransform
            vIn.expectsMediaDataInRealTime = false
            guard writer.canAdd(vIn) else { completion(false, "无法写入视频"); return }
            writer.add(vIn)

            // 声音轨（有就带上）
            var aOut: AVAssetReaderTrackOutput?
            var aIn: AVAssetWriterInput?
            if let aTrack = asset.tracks(withMediaType: .audio).first {
                let o = AVAssetReaderTrackOutput(track: aTrack, outputSettings: nil)
                let ahint: CMFormatDescription? = (aTrack.formatDescriptions.first).map { $0 as! CMFormatDescription }
                let i = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: ahint)
                i.expectsMediaDataInRealTime = false
                if reader.canAdd(o), writer.canAdd(i) { reader.add(o); writer.add(i); aOut = o; aIn = i }
            }

            // still-image-time 定时元数据轨
            let spec: [String: Any] = [
                kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String: "mdta/com.apple.quicktime.still-image-time",
                kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String: "com.apple.metadata.datatype.int8"
            ]
            var mfd: CMFormatDescription?
            CMMetadataFormatDescriptionCreateWithMetadataSpecifications(
                allocator: kCFAllocatorDefault, metadataType: kCMMetadataFormatType_Boxed,
                metadataSpecifications: [spec] as CFArray, formatDescriptionOut: &mfd)
            let mIn = AVAssetWriterInput(mediaType: .metadata, outputSettings: nil, sourceFormatHint: mfd)
            let adaptor = AVAssetWriterInputMetadataAdaptor(assetWriterInput: mIn)
            writer.add(mIn)

            guard reader.startReading() else { completion(false, reader.error?.localizedDescription ?? "读取失败"); return }
            guard writer.startWriting() else { completion(false, writer.error?.localizedDescription ?? "写入失败"); return }
            writer.startSession(atSourceTime: .zero)

            let stillItem = AVMutableMetadataItem()
            stillItem.keySpace = AVMetadataKeySpace.quickTimeMetadata
            stillItem.key = "com.apple.quicktime.still-image-time" as NSString
            stillItem.value = NSNumber(value: 0)
            stillItem.dataType = "com.apple.metadata.datatype.int8"
            adaptor.append(AVTimedMetadataGroup(items: [stillItem],
                                                timeRange: CMTimeRange(start: still, duration: CMTime(value: 1, timescale: 100))))
            mIn.markAsFinished()

            let group = DispatchGroup()
            func pump(_ out: AVAssetReaderTrackOutput, _ inp: AVAssetWriterInput, _ qn: String) {
                group.enter()
                let q = DispatchQueue(label: qn)
                inp.requestMediaDataWhenReady(on: q) {
                    while inp.isReadyForMoreMediaData {
                        if let sb = out.copyNextSampleBuffer() { inp.append(sb) }
                        else { inp.markAsFinished(); group.leave(); return }
                    }
                }
            }
            pump(vOut, vIn, "lucida.live.v")
            if let o = aOut, let i = aIn { pump(o, i, "lucida.live.a") }
            group.notify(queue: .global()) {
                writer.finishWriting {
                    if writer.status == .completed { completion(true, nil) }
                    else { completion(false, writer.error?.localizedDescription ?? "封装失败") }
                }
            }
        } catch {
            completion(false, error.localizedDescription)
        }
    }
}
