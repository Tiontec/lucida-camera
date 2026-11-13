import UIKit
import WebKit
import Photos
import AVFoundation

/// 网页 ↔ 原生：window.webkit.messageHandlers.lucida.postMessage({type:...}) 返回 Promise。
///
/// 消息类型：
///   chunk     {id,i,data(base64)}                         分块上传文件（网页 → 原生），避免一次传超大 base64
///   saveFile  {id,name,mime,mode,format}                  存到系统相册（照片/视频）或弹出分享面板（其它文件）
///   pickMedia {live,limit}                                原生选择器：导入照片 / 视频 / 实况（含配对视频）
///   capture   {position,zoom,format,orientation}          原生相机拍一张（JPEG / HEIF / ProRAW），同时写入系统相册
///   focus     {x,y,lock,release,label,position,angle}     点按对焦 / 长按锁定 AE·AF（原生设置摄像头对焦点）
///   haptic    {style}                                     触感
///   probe     {}                                          重新检测设备摄像头
///   dualCamOpen {mode:"photo"|"video"}                    进入原生双摄相机（前后摄像头同时拍照 / 录像）；关闭后返回
///                                                         {ok:true,items:[{kind,url,name,saved}]} 或 {ok:false,code:"unsupported"|"denied"|"error",error}
///   dualCamClean {names:[...]}                            网页导入完后，删掉原生留下的临时文件（names 为空 = 全删双摄文件）
final class NativeBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var host: WebViewController?
    private let io = DispatchQueue(label: "lucida.bridge.io")

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else {
            replyHandler(nil, "bad message"); return
        }
        let reply: (Any?, String?) -> Void = { v, e in DispatchQueue.main.async { replyHandler(v, e) } }
        switch type {
        case "chunk":    handleChunk(body, reply)
        case "saveFile": handleSave(body, reply)
        case "pickMedia":
            guard let vc = host else { reply(nil, "no host"); return }
            LivePicker.present(on: vc, live: (body["live"] as? Bool) ?? false,
                               limit: (body["limit"] as? Int) ?? 0) { files in reply(["files": files], nil) }
        case "capture":
            NativeCamera.shared.capture(body: body) { result in reply(result, nil) }
        case "focus":
            NativeFocus.apply(body) { ok in reply(["ok": ok], nil) }
        case "haptic":
            let style = (body["style"] as? String) ?? "light"
            let g: UIImpactFeedbackGenerator
            switch style {
            case "heavy": g = UIImpactFeedbackGenerator(style: .heavy)
            case "medium": g = UIImpactFeedbackGenerator(style: .medium)
            default: g = UIImpactFeedbackGenerator(style: .light)
            }
            g.impactOccurred(); reply(true, nil)
        case "probe":
            reply(DeviceProbe.info(), nil)
        case "dualCamOpen":
            openDualCam(mode: (body["mode"] as? String) ?? "photo", reply)
        case "dualCamClean":
            let names = (body["names"] as? [String]) ?? []
            io.async {
                let fm = FileManager.default
                let all = (try? fm.contentsOfDirectory(atPath: SchemeHandler.outDir.path)) ?? []
                for n in all where n.hasPrefix("澄影双摄_") && (names.isEmpty || names.contains(n)) {
                    try? fm.removeItem(at: SchemeHandler.outDir.appendingPathComponent(n))
                }
                reply(true, nil)
            }
        default:
            reply(nil, "unknown type: \(type)")
        }
    }

    // MARK: 原生双摄
    private var dualOpen = false
    private func openDualCam(mode: String, _ reply: @escaping (Any?, String?) -> Void) {
        guard let vc = host else { reply(["ok": false, "code": "error", "error": "没有宿主界面"], nil); return }
        guard !dualOpen else { reply(["ok": false, "code": "error", "error": "原生双摄已经打开"], nil); return }
        guard DualCamEngine.isSupported else {
            reply(["ok": false, "code": "unsupported", "error": "这台 iPhone 不支持前后摄像头同时工作（需要 iPhone XS / XR 及以后的机型）"], nil); return
        }
        dualOpen = true
        let d = DualCamViewController()
        d.startMode = mode == "video" ? .video : .photo
        d.modalPresentationStyle = .fullScreen
        d.onFinish = { [weak self] items, code, msg in
            self?.dualOpen = false
            if let code = code { reply(["ok": false, "code": code, "error": msg ?? ""], nil); return }
            let arr: [[String: Any]] = items.map {
                ["kind": $0.kind, "url": "lucida://file/" + $0.url.lastPathComponent,
                 "name": $0.url.lastPathComponent, "saved": $0.saved]
            }
            reply(["ok": true, "items": arr], nil)
        }
        vc.present(d, animated: true)
    }

    // MARK: 分块上传
    private func upURL(_ id: String) -> URL {
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return SchemeHandler.outDir.appendingPathComponent("up-" + safe)
    }

    private func handleChunk(_ b: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard let id = b["id"] as? String, let i = b["i"] as? Int, let s = b["data"] as? String,
              let d = Data(base64Encoded: s) else { reply(nil, "bad chunk"); return }
        io.async {
            let u = self.upURL(id)
            do {
                if i == 0 { try d.write(to: u, options: .atomic) }
                else {
                    let h = try FileHandle(forWritingTo: u)
                    h.seekToEndOfFile(); h.write(d); h.closeFile()
                }
                reply(true, nil)
            } catch { reply(nil, "写入失败：\(error.localizedDescription)") }
        }
    }

    // MARK: 保存
    private enum Kind { case image, video, other }
    private func kind(ext: String) -> Kind {
        switch ext.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "dng", "gif", "webp", "tif", "tiff": return .image
        case "mov", "mp4", "m4v": return .video
        default: return .other
        }
    }

    private func handleSave(_ b: [String: Any], _ reply: @escaping (Any?, String?) -> Void) {
        guard let id = b["id"] as? String else { reply(nil, "bad save"); return }
        let name = ((b["name"] as? String) ?? "澄影").replacingOccurrences(of: "/", with: "_")
        let mode = (b["mode"] as? String) ?? "auto"
        let format = (b["format"] as? String) ?? "jpeg"
        let ext = (name as NSString).pathExtension
        let src = upURL(id)
        let dst = SchemeHandler.outDir.appendingPathComponent(UUID().uuidString + "-" + name)
        do { try FileManager.default.moveItem(at: src, to: dst) } catch { reply(nil, "没有找到上传的文件"); return }
        let k = kind(ext: ext)
        if mode == "share" || k == .other {
            DispatchQueue.main.async {
                self.share(dst) { reply(["ok": true, "mode": "share"], nil) }
            }
            return
        }
        var file = dst
        if k == .image, format == "heif", ["jpg", "jpeg", "png"].contains(ext.lowercased()),
           let h = PhotoSaver.transcodeToHEIC(dst) { file = h }
        PhotoSaver.save(file: file, isVideo: k == .video) { ok, msg in
            if ok { reply(["ok": true, "mode": "photos", "heic": file != dst], nil) }
            else { reply(nil, msg ?? "保存失败") }
        }
    }

    private func share(_ url: URL, done: @escaping () -> Void) {
        guard let vc = host else { done(); return }
        let a = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        a.popoverPresentationController?.sourceView = vc.view
        a.popoverPresentationController?.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.maxY - 40, width: 1, height: 1)
        a.completionWithItemsHandler = { _, _, _, _ in done() }
        vc.present(a, animated: true)
    }
}
