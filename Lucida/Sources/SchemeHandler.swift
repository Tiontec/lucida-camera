import Foundation
import WebKit

/// 自定义协议 lucida://
///   lucida://app/<path>   → App 包里 web/ 目录下的网页文件
///   lucida://file/<name>  → 临时目录里原生生成的文件（导入的实况、原生拍摄的照片等），支持 Range（视频播放需要）
/// 用自定义协议而不是 file://，这样 localStorage / IndexedDB（澄影相册）有稳定的来源，getUserMedia 也能用。
final class SchemeHandler: NSObject, WKURLSchemeHandler {
    static let outDir: URL = {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("lucida-out", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()

    private static let mimes: [String: String] = [
        "html": "text/html; charset=utf-8", "js": "text/javascript; charset=utf-8", "css": "text/css; charset=utf-8",
        "json": "application/json", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
        "heic": "image/heic", "heif": "image/heif", "dng": "image/x-adobe-dng", "gif": "image/gif",
        "svg": "image/svg+xml", "webp": "image/webp", "mov": "video/quicktime", "mp4": "video/mp4",
        "m4v": "video/mp4", "woff2": "font/woff2", "txt": "text/plain; charset=utf-8"
    ]

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(URLError(.badURL)); return
        }
        let fileURL: URL
        if url.host == "file" {
            fileURL = SchemeHandler.outDir.appendingPathComponent(url.lastPathComponent)
        } else {
            var p = url.path
            if p.isEmpty || p == "/" { p = "/index.html" }
            let rel = String(p.dropFirst())
            if rel.contains("..") { urlSchemeTask.didFailWithError(URLError(.badURL)); return }
            guard let base = Bundle.main.resourceURL?.appendingPathComponent("web") else {
                urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist)); return
            }
            fileURL = base.appendingPathComponent(rel)
        }
        guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else {
            let r = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: ["Access-Control-Allow-Origin": "*"])!
            urlSchemeTask.didReceive(r); urlSchemeTask.didFinish(); return
        }
        let mime = SchemeHandler.mimes[fileURL.pathExtension.lowercased()] ?? "application/octet-stream"
        var headers = ["Content-Type": mime, "Accept-Ranges": "bytes",
                       "Access-Control-Allow-Origin": "*", "Cache-Control": "no-cache"]
        let total = data.count
        var status = 200
        var body = data
        if let rng = urlSchemeTask.request.value(forHTTPHeaderField: "Range"), rng.hasPrefix("bytes=") {
            let parts = rng.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            var a = Int(parts.first ?? "") ?? 0
            var b = parts.count > 1 ? (Int(parts[1]) ?? total - 1) : total - 1
            if parts.first == "" { a = max(0, total - (Int(parts.last ?? "") ?? 0)); b = total - 1 }   // bytes=-N
            a = min(max(0, a), max(0, total - 1)); b = min(max(a, b), total - 1)
            if total > 0 {
                body = data.subdata(in: a..<(b + 1))
                headers["Content-Range"] = "bytes \(a)-\(b)/\(total)"
                status = 206
            }
        }
        headers["Content-Length"] = String(body.count)
        let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        urlSchemeTask.didReceive(resp)
        urlSchemeTask.didReceive(body)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    /// 清理上次留下的临时文件
    static func cleanOutDir() {
        let fm = FileManager.default
        if let list = try? fm.contentsOfDirectory(at: outDir, includingPropertiesForKeys: nil) {
            for f in list { try? fm.removeItem(at: f) }
        }
    }
}
