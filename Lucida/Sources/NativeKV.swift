import UIKit
import WebKit

/// 原生存储（长期计划 A2）：网页里所有 `lucida.*` 设置的权威存档放在原生（Application Support/lucida-kv.json），
/// 网页的 localStorage 只是镜像：页面启动前原生把存档注入网页，网页之后每次改动都同步回原生。
/// 好处：升级 / 系统清理网页缓存也不会丢设置；原生界面（如双摄的预设顺序）能和网页读写同一份数据。
final class NativeKV: NSObject {
    static let shared = NativeKV()
    private var items: [String: String] = [:]
    private(set) var seeded = false
    private var nativeChanged: [String: String] = [:]      // 原生一侧改过、还没通知网页的键
    private let q = DispatchQueue(label: "lucida.kv.io")
    private var pending: DispatchWorkItem?
    private let lock = NSLock()

    private var fileURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("lucida-kv.json")
    }

    private override init() {
        super.init()
        if let data = try? Data(contentsOf: fileURL),
           let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            seeded = (o["seeded"] as? Bool) ?? false
            items = (o["items"] as? [String: String]) ?? [:]
        }
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(flush), name: UIApplication.didEnterBackgroundNotification, object: nil)
        nc.addObserver(self, selector: #selector(flush), name: UIApplication.willTerminateNotification, object: nil)
    }

    // MARK: 读写
    func get(_ k: String) -> String? { lock.lock(); defer { lock.unlock() }; return items[k] }

    /// 网页那边的改动（已经在 localStorage 里了，不需要再通知网页）
    fileprivate func webSet(_ k: String, _ v: String) { lock.lock(); items[k] = v; lock.unlock(); schedule() }
    fileprivate func webRemove(_ k: String) { lock.lock(); items[k] = nil; lock.unlock(); schedule() }
    fileprivate func webClear() { lock.lock(); items.removeAll(); lock.unlock(); schedule() }
    fileprivate func webSeed(_ all: [String: String]) {
        lock.lock(); for (k, v) in all where items[k] == nil { items[k] = v }; seeded = true; lock.unlock(); schedule()
    }

    /// 原生界面的改动：存档，并记下来，网页下次回到前台时通知它
    func setNative(_ k: String, _ v: String) {
        lock.lock(); items[k] = v; nativeChanged[k] = v; lock.unlock(); schedule()
    }
    func takeNativeChanges() -> [String: String] {
        lock.lock(); defer { lock.unlock() }; let c = nativeChanged; nativeChanged = [:]; return c
    }

    /// 注入网页的启动脚本：window.__LUCIDA_KV__ = {seeded, items}
    func injectionScript() -> String {
        lock.lock(); let obj: [String: Any] = ["seeded": seeded, "items": items]; lock.unlock()
        let data = (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
        return "window.__LUCIDA_KV__=" + (String(data: data, encoding: .utf8) ?? "{}") + ";"
    }

    // MARK: 落盘（合并短时间内的多次改动）
    private func schedule() {
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.writeNow() }
        pending = w
        q.asyncAfter(deadline: .now() + 0.4, execute: w)
    }
    @objc func flush() { pending?.cancel(); q.sync { writeNow() } }
    private func writeNow() {
        lock.lock(); let obj: [String: Any] = ["seeded": seeded, "items": items]; lock.unlock()
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// 接收网页发来的存储改动（window.webkit.messageHandlers.lucidaKV）
final class NativeKVHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let b = m.body as? [String: Any], let op = b["op"] as? String else { return }
        switch op {
        case "set": if let k = b["k"] as? String, let v = b["v"] as? String { NativeKV.shared.webSet(k, v) }
        case "del": if let k = b["k"] as? String { NativeKV.shared.webRemove(k) }
        case "clr": NativeKV.shared.webClear()
        case "seed": if let it = b["items"] as? [String: String] { NativeKV.shared.webSeed(it) }
        default: break
        }
    }
}
