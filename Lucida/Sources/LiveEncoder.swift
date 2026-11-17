import Foundation
import AVFoundation
import VideoToolbox
import CoreMedia

/// 实况用的「连续编码器 + 压缩样本库」。
///
/// 以前每按一次快门就开一路独立的硬件编码，同时按得多了：硬件编码路数有限、每路还各自攒一堆没压缩的 720p 画面 → 内存暴涨 → 卡住 / 闪退。
/// 现在只有一路 H.264 硬件编码，一直在把取景画面压成很小的码流（每秒不到 1MB），放在样本库里。
/// 每张实况只是库里的一个时间窗口（快门前 1.5 秒 → 总时长），收到点之后把这一段压缩样本直通写成 MOV（不重新编码，几十毫秒）。
/// 所以不管连按多少下，内存只和「最早那张还没收完的实况到现在」的时长有关，编码路数永远是一路。
final class LiveEncoder {
    struct Sample { let sb: CMSampleBuffer; let pts: CMTime; let key: Bool }

    let size: CGSize
    private var session: VTCompressionSession?
    private let lock = NSLock()
    private var samples: [Sample] = []
    private var holds: [UUID: CMTime] = [:]       // 每张还没收完的实况登记它要用到的最早时间点，库里不能清掉
    private var forceKey = true                    // 下一帧要求是关键帧（刚开始 / 画面中断过之后）

    init?(size: CGSize) {
        self.size = size
        var s: VTCompressionSession?
        let st = VTCompressionSessionCreate(allocator: nil, width: Int32(size.width), height: Int32(size.height),
                                            codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
                                            imageBufferAttributes: nil, compressedDataAllocator: nil,
                                            outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard st == noErr, let sess = s else { return nil }
        session = sess
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: Int(size.width * size.height * 8)))
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 0.5))
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: 30))
        VTCompressionSessionPrepareToEncodeFrames(sess)
    }

    // MARK: 送画面

    /// 送一帧进去（在取景回调所在的线程调用；编码是异步的，结果在 append 里入库）
    func encode(_ pb: CVPixelBuffer, pts: CMTime) {
        guard let sess = session else { return }
        let props: CFDictionary? = forceKey ? ([kVTEncodeFrameOptionKey_ForceKeyFrame as String: NSNumber(value: true)] as CFDictionary) : nil
        forceKey = false
        var flags = VTEncodeInfoFlags()
        _ = VTCompressionSessionEncodeFrame(sess, imageBuffer: pb, presentationTimeStamp: pts, duration: CMTime(value: 1, timescale: 30),
                                            frameProperties: props, infoFlagsOut: &flags) { [weak self] status, _, sb in
            guard status == noErr, let sb = sb, let self = self else { return }
            self.append(sb)
        }
    }

    private func append(_ sb: CMSampleBuffer) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        var key = true
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false), CFArrayGetCount(arr) > 0 {
            let d = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFDictionary.self)
            if let v = CFDictionaryGetValue(d, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()) {
                key = !CFBooleanGetValue(unsafeBitCast(v, to: CFBoolean.self))
            }
        }
        lock.lock()
        samples.append(Sample(sb: sb, pts: pts, key: key))
        trimLocked()
        lock.unlock()
    }

    /// 清掉用不着的旧样本：保留最近 2.2 秒（快门前 1.5 秒 + 往前找关键帧的余量），以及所有未收完的实况要用的部分；总是从关键帧处裁
    private func trimLocked() {
        guard let last = samples.last else { return }
        var cutoff = CMTimeSubtract(last.pts, CMTime(seconds: 2.2, preferredTimescale: 600))
        for h in holds.values where CMTimeCompare(h, cutoff) < 0 { cutoff = h }
        var k = -1
        for (i, s) in samples.enumerated() {
            if CMTimeCompare(s.pts, cutoff) > 0 { break }
            if s.key { k = i }
        }
        if k > 0 { samples.removeFirst(k) }
    }

    /// 画面中断过（录像 / 关过实况再打开）：旧样本和新画面接不上，清空重来，下一帧强制关键帧
    func reset() {
        lock.lock(); samples.removeAll(); forceKey = true; lock.unlock()
    }

    // MARK: 登记 / 取用

    func hold(_ id: UUID, from t: CMTime) { lock.lock(); holds[id] = t; lock.unlock() }
    func release(_ id: UUID) { lock.lock(); holds[id] = nil; lock.unlock() }

    /// 等编码器把 t 之前（含）的帧都吐出来
    func finish(until t: CMTime) {
        if let s = session { VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: t) }
    }

    /// 停掉编码（样本库保留，已登记的实况还要从里面取）
    func shutdown() {
        guard let s = session else { return }
        VTCompressionSessionCompleteFrames(s, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(s)
        session = nil
    }

    /// 取 [start, end] 的样本；起点退到 start 之前最近的关键帧（保证能解码）
    func clip(from start: CMTime, until end: CMTime) -> [Sample] {
        lock.lock(); defer { lock.unlock() }
        var k = 0
        for (i, s) in samples.enumerated() {
            if CMTimeCompare(s.pts, start) > 0 { break }
            if s.key { k = i }
        }
        while k < samples.count && !samples[k].key { k += 1 }
        guard k < samples.count else { return [] }
        var out: [Sample] = []
        for i in k..<samples.count {
            if CMTimeCompare(samples[i].pts, end) > 0 { break }
            out.append(samples[i])
        }
        return out
    }

    // MARK: 写文件

    /// 把一段压缩样本直通写成 MOV（不重新编码）。成功返回 nil，失败返回原因。
    static func writeMOV(_ clip: [Sample], to url: URL) -> String? {
        guard let first = clip.first, let fmt = CMSampleBufferGetFormatDescription(first.sb) else { return "实况缓存里没有画面" }
        try? FileManager.default.removeItem(at: url)
        do {
            let w = try AVAssetWriter(outputURL: url, fileType: .mov)
            let vi = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: fmt)
            vi.expectsMediaDataInRealTime = false
            guard w.canAdd(vi) else { return "无法创建实况视频" }
            w.add(vi)
            guard w.startWriting() else { return w.error?.localizedDescription ?? "无法写入" }
            w.startSession(atSourceTime: .zero)
            let base = first.pts
            var lastEnd = CMTime.zero
            for s in clip {
                var n = 0
                while !vi.isReadyForMoreMediaData && n < 2000 { usleep(2000); n += 1 }
                guard vi.isReadyForMoreMediaData else { break }
                let t = CMTimeSubtract(s.pts, base)
                var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: t, decodeTimeStamp: t)
                var out: CMSampleBuffer?
                guard CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: s.sb, sampleTimingEntryCount: 1,
                                                            sampleTimingArray: &timing, sampleBufferOut: &out) == noErr, let o = out else { continue }
                if !vi.append(o) { break }
                lastEnd = CMTimeAdd(t, timing.duration)
            }
            vi.markAsFinished()
            w.endSession(atSourceTime: lastEnd)
            let sem = DispatchSemaphore(value: 0)
            w.finishWriting { sem.signal() }
            sem.wait()
            return w.status == .completed ? nil : (w.error?.localizedDescription ?? "实况合成失败")
        } catch { return error.localizedDescription }
    }
}
