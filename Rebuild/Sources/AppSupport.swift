import Foundation

/// 版本号规则：加设置 +0.0.1 · 加功能 +0.1.0 · 大更新 +1.0.0（满 10 进一）
enum AppInfo {
    static let version = "1.4.0"
    static let build = "5"
    static let name = "澄影重构版"
}

/// 临时输出目录（拍到的照片 / 视频先写在这里，再存进系统相册）
enum AppDirs {
    static let outDir: URL = {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("lucida-out", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }()
}

/// 原生存储：所有设置存在 Application Support/lucida-kv.json（升级、清缓存都不会丢）
final class NativeKV {
    static let shared = NativeKV()
    private var items: [String: String] = [:]
    private let lock = NSLock()
    private let q = DispatchQueue(label: "lucida.kv.io")
    private var pending: DispatchWorkItem?

    private var fileURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("lucida-kv.json")
    }
    private init() {
        if let data = try? Data(contentsOf: fileURL), let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            items = (o["items"] as? [String: String]) ?? [:]
        }
    }
    func get(_ k: String) -> String? { lock.lock(); defer { lock.unlock() }; return items[k] }
    func setNative(_ k: String, _ v: String) {
        lock.lock(); items[k] = v; lock.unlock()
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.writeNow() }
        pending = w; q.asyncAfter(deadline: .now() + 0.4, execute: w)
    }
    private func writeNow() {
        lock.lock(); let obj: [String: Any] = ["items": items]; lock.unlock()
        if let data = try? JSONSerialization.data(withJSONObject: obj) { try? data.write(to: fileURL, options: .atomic) }
    }
}
