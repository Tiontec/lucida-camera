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
    private var gen = 0                            // 会话代数：重建后，旧会话迟到的输出直接丢掉
    private var restarts = 0
    private var dead = false
    private var lastOutSeen = 0, stalled = 0, errStreak = 0
    private var audio: [CMSampleBuffer] = []       // 未压缩的 PCM 音频样本（最近约 2.2 秒 + 未收完实况要用的部分）
    private let lock = NSLock()
    private var samples: [Sample] = []
    private var holds: [UUID: CMTime] = [:]       // 每张还没收完的实况登记它要用到的最早时间点，库里不能清掉
    private var inCount = 0, outCount = 0, lastErr: OSStatus = 0
    /// 诊断：送进 / 吐出多少帧、最近一次错误码
    var diag: String { lock.lock(); defer { lock.unlock() }; return "送入\(inCount) 输出\(outCount) 库存\(samples.count) 重启\(restarts) 错误\(lastErr)" }
    private var forceKey = true                    // 下一帧要求是关键帧（刚开始 / 画面中断过之后）

    init?(size: CGSize) {
        self.size = size
        guard let sess = LiveEncoder.makeSession(size) else { return nil }
        session = sess
    }

    private static func makeSession(_ size: CGSize) -> VTCompressionSession? {
        var s: VTCompressionSession?
        let st = VTCompressionSessionCreate(allocator: nil, width: Int32(size.width), height: Int32(size.height),
                                            codecType: kCMVideoCodecType_H264, encoderSpecification: nil,
                                            imageBufferAttributes: nil, compressedDataAllocator: nil,
                                            outputCallback: nil, refcon: nil, compressionSessionOut: &s)
        guard st == noErr, let sess = s else { return nil }
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: Int(size.width * size.height * 8)))
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 0.5))
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: NSNumber(value: 30))
        VTCompressionSessionPrepareToEncodeFrames(sess)
        return sess
    }

    /// 编码器停了（连续很多帧送进去却没有输出 / 连续报错）：丢掉旧会话，建一个新的。旧样本和新会话的参数集不同，接不上，清库重来。
    private func restartSession() {
        AppLog.warn("实况", "编码器卡住，重建 VT 会话（已重建 \(restarts) 次）")
        if let old = session { VTCompressionSessionInvalidate(old) }
        session = LiveEncoder.makeSession(size)
        lock.lock()
        gen += 1; restarts += 1; samples.removeAll(); stalled = 0; errStreak = 0; lastOutSeen = outCount
        lock.unlock()
        forceKey = true
    }

    // MARK: 送画面

    /// 送一帧进去（在取景回调所在的线程调用；编码是异步的，结果在 append 里入库）
    func encode(_ pb: CVPixelBuffer, pts: CMTime) {
        if dead { return }
        // 看门狗：送进去 45 帧（约 1.5 秒）一帧都没吐出来，或连续 5 次报错 → 重建编码器
        lock.lock()
        if outCount == lastOutSeen { stalled += 1 } else { lastOutSeen = outCount; stalled = 0 }
        let needRestart = stalled >= 45 || errStreak >= 5
        lock.unlock()
        if needRestart || (session == nil && stalled % 30 == 0) { restartSession() }
        guard let sess = session else { return }
        let myGen: Int = { lock.lock(); defer { lock.unlock() }; return gen }()
        let props: CFDictionary? = forceKey ? ([kVTEncodeFrameOptionKey_ForceKeyFrame as String: NSNumber(value: true)] as CFDictionary) : nil
        forceKey = false
        var flags = VTEncodeInfoFlags()
        lock.lock(); inCount += 1; lock.unlock()
        let es = VTCompressionSessionEncodeFrame(sess, imageBuffer: pb, presentationTimeStamp: pts, duration: CMTime(value: 1, timescale: 30),
                                            frameProperties: props, infoFlagsOut: &flags) { [weak self] status, _, sb in
            guard let self = self else { return }
            guard status == noErr, let sb = sb else { if status != noErr { self.lock.lock(); self.lastErr = status; self.errStreak += 1; self.lock.unlock() }; return }
            self.append(sb, gen: myGen)
        }
        if es != noErr { lock.lock(); lastErr = es; errStreak += 1; lock.unlock() }
    }

    private func append(_ sb: CMSampleBuffer, gen g: Int) {
        let pts = CMSampleBufferGetPresentationTimeStamp(sb)
        var key = true
        if let arr = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false), CFArrayGetCount(arr) > 0 {
            let d = unsafeBitCast(CFArrayGetValueAtIndex(arr, 0), to: CFDictionary.self)
            if let v = CFDictionaryGetValue(d, Unmanaged.passUnretained(kCMSampleAttachmentKey_NotSync).toOpaque()) {
                key = !CFBooleanGetValue(unsafeBitCast(v, to: CFBoolean.self))
            }
        }
        lock.lock()
        guard g == gen else { lock.unlock(); return }
        outCount += 1; errStreak = 0
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
        // 音频：留到和视频同一个起点（再多留一点点余量）
        if let firstV = samples.first {
            let keepFrom = CMTimeSubtract(firstV.pts, CMTime(seconds: 0.1, preferredTimescale: 600))
            while let a = audio.first, CMTimeCompare(CMTimeAdd(CMSampleBufferGetPresentationTimeStamp(a), CMSampleBufferGetDuration(a)), keepFrom) < 0 { audio.removeFirst() }
        }
    }

    /// 送一段麦克风音频（未压缩 PCM）。在写 MOV 时才压成 AAC。
    func appendAudio(_ sb: CMSampleBuffer) {
        lock.lock(); defer { lock.unlock() }
        audio.append(sb)
        if audio.count > 600 { audio.removeFirst(audio.count - 600) }     // 兜底：不让它无限涨
    }

    /// 画面中断过（录像 / 关过实况再打开）：旧样本和新画面接不上，清空重来，下一帧强制关键帧
    func reset() {
        lock.lock(); samples.removeAll(); audio.removeAll(); forceKey = true; lock.unlock()
    }

    // MARK: 登记 / 取用

    func hold(_ id: UUID, from t: CMTime) { lock.lock(); holds[id] = t; lock.unlock() }
    func release(_ id: UUID) { lock.lock(); holds[id] = nil; lock.unlock() }

    /// 等编码器把 t 之前（含）的帧都吐出来。不用 CompleteFrames（编码器出问题时它会一直卡住、把后面所有实况都堵死），改成最多等 1.5 秒
    func finish(until t: CMTime) {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            lock.lock(); let last = samples.last?.pts; lock.unlock()
            if let l = last, CMTimeCompare(l, CMTimeSubtract(t, CMTime(value: 1, timescale: 20))) >= 0 { return }
            usleep(15_000)
        }
    }

    /// 停掉编码（样本库保留，已登记的实况还要从里面取）
    func shutdown() {
        dead = true
        guard let s = session else { return }
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

    /// 取和 [start, end] 重叠的音频样本
    func audioClip(from start: CMTime, until end: CMTime) -> [CMSampleBuffer] {
        lock.lock(); defer { lock.unlock() }
        return audio.filter {
            let p = CMSampleBufferGetPresentationTimeStamp($0)
            let e = CMTimeAdd(p, CMSampleBufferGetDuration($0))
            return CMTimeCompare(e, start) > 0 && CMTimeCompare(p, end) <= 0
        }
    }

    // MARK: 写文件

    /// 把一段压缩样本直通写成 MOV（不重新编码）。成功返回 nil，失败返回原因。
    static func writeMOV(_ clip: [Sample], audio: [CMSampleBuffer] = [], to url: URL) -> String? {
        guard let first = clip.first, let fmt = CMSampleBufferGetFormatDescription(first.sb) else { return "实况缓存里没有画面" }
        try? FileManager.default.removeItem(at: url)
        do {
            let w = try AVAssetWriter(outputURL: url, fileType: .mov)
            let vi = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: fmt)
            vi.expectsMediaDataInRealTime = false
            guard w.canAdd(vi) else { return "无法创建实况视频" }
            w.add(vi)
            // 声音：PCM → AAC（有就加；加不上也不影响视频）
            var ai: AVAssetWriterInput?
            if let a0 = audio.first, let afmt = CMSampleBufferGetFormatDescription(a0),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(afmt)?.pointee {
                let ch = max(1, min(2, Int(asbd.mChannelsPerFrame)))
                let set: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVNumberOfChannelsKey: ch,
                                          AVSampleRateKey: asbd.mSampleRate > 0 ? asbd.mSampleRate : 44100, AVEncoderBitRateKey: 96_000]
                let inp = AVAssetWriterInput(mediaType: .audio, outputSettings: set, sourceFormatHint: afmt)
                inp.expectsMediaDataInRealTime = false
                if w.canAdd(inp) { w.add(inp); ai = inp }
            }
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
            if let ai = ai {
                for a in audio {
                    let p = CMSampleBufferGetPresentationTimeStamp(a)
                    var t = CMTimeSubtract(p, base)
                    if CMTimeCompare(t, .zero) < 0 { t = .zero }             // 比视频起点早一点的那一小段：贴到 0
                    if CMTimeCompare(t, lastEnd) > 0 { break }
                    var n = 0
                    while !ai.isReadyForMoreMediaData && n < 2000 { usleep(2000); n += 1 }
                    guard ai.isReadyForMoreMediaData else { break }
                    var timing = CMSampleTimingInfo()
                    guard CMSampleBufferGetSampleTimingInfo(a, at: 0, timingInfoOut: &timing) == noErr else { continue }
                    timing.presentationTimeStamp = t; timing.decodeTimeStamp = .invalid
                    var out: CMSampleBuffer?
                    guard CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: a, sampleTimingEntryCount: 1,
                                                                sampleTimingArray: &timing, sampleBufferOut: &out) == noErr, let o = out else { continue }
                    if !ai.append(o) { break }
                }
                ai.markAsFinished()
            }
            w.endSession(atSourceTime: lastEnd)
            let sem = DispatchSemaphore(value: 0)
            w.finishWriting { sem.signal() }
            sem.wait()
            return w.status == .completed ? nil : (w.error?.localizedDescription ?? "实况合成失败")
        } catch { return error.localizedDescription }
    }
}
