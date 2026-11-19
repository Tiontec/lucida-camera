import UIKit

/// 原生日志收集器（和安卓 AppLog.java 同名同接口）。
/// 内核里直接调用：AppLog.info("引擎", "…") / AppLog.warn(…) / AppLog.error(…)。任意线程都能调。
/// - 内存环形缓冲 800 条；最近 200 条持久化到 Application Support/lucida-log.json（App 被杀、闪退后下次启动还能看到，标「上次运行」）。
/// - 自动记录：启动信息、进入后台 / 回到前台、内存警告、设备发热状态变化、未捕获的 ObjC 异常（AVFoundation 常见的崩溃原因）。
/// - 日志页（M3 做）用 entries(_:) / text(_:) / exportFile(_:) / clear()。
enum LogLevel: Int {
    case info = 0, warn = 1, error = 2
    var letter: String { switch self { case .info: return "I"; case .warn: return "W"; case .error: return "E" } }
    var title: String { switch self { case .info: return "信息"; case .warn: return "警告"; case .error: return "错误" } }
}

/// 日志页的筛选：全部 / 错误 / 警告 / 信息
enum LogFilter: Int {
    case all = 0, error, warn, info
    var title: String { switch self { case .all: return "全部"; case .error: return "错误"; case .warn: return "警告"; case .info: return "信息" } }
    func accepts(_ l: LogLevel) -> Bool {
        switch self {
        case .all: return true
        case .error: return l == .error
        case .warn: return l == .warn
        case .info: return l == .info
        }
    }
}

struct LogEntry {
    let time: TimeInterval   // 1970 起的秒
    let level: LogLevel
    let tag: String
    let msg: String
    var prev: Bool           // true = 上一次运行留下的
}

final class AppLog {
    static let shared = AppLog()
    static let capacity = 800          // 内存最多保留条数
    static let persistCount = 200      // 落盘条数
    static let maxMessageLength = 3000 // 单条最长字数
    /// 有新日志时（主线程，最多每 0.3 秒一次）发出，日志页可据此刷新
    static let didChange = Notification.Name("lucida.AppLog.didChange")

    // MARK: 对外接口
    static func info(_ tag: String, _ msg: String) { shared.add(.info, tag, msg, force: false) }
    static func warn(_ tag: String, _ msg: String) { shared.add(.warn, tag, msg, force: false) }
    static func error(_ tag: String, _ msg: String) { shared.add(.error, tag, msg, force: false) }

    /// 可选：在 AppDelegate.didFinishLaunching 里调一次，让启动信息和崩溃钩子尽早生效（不调的话第一次写日志时自动启动）
    static func boot() { _ = shared }

    /// 记录开关（日志页里的「记录日志」）。关闭后不再记录新日志
    static var enabled: Bool {
        get { shared.isOn }
        set { shared.setOn(newValue) }
    }

    static func entries(_ f: LogFilter = .all) -> [LogEntry] {
        shared.lock.lock(); let all = shared.buf; shared.lock.unlock()
        return f == .all ? all : all.filter { f.accepts($0.level) }
    }

    static func count(_ f: LogFilter = .all) -> Int { entries(f).count }

    /// 整理成可复制 / 导出的文字
    static func text(_ f: LogFilter = .all) -> String {
        let list = entries(f)
        let df = DateFormatter(); df.dateFormat = "MM-dd HH:mm:ss.SSS"
        var s = "\(AppInfo.name) \(AppInfo.version)（\(AppInfo.build)） · \(machine()) · iOS \(UIDevice.current.systemVersion)\n"
        s += "筛选：\(f.title) · 共 \(list.count) 条\n\n"
        var lastPrev: Bool? = nil
        for e in list {
            if lastPrev != e.prev { s += e.prev ? "—— 上次运行 ——\n" : "—— 本次运行 ——\n"; lastPrev = e.prev }
            let when = df.string(from: Date(timeIntervalSince1970: e.time))
            s += "\(when) \(e.level.letter)/\(e.tag)：\(e.msg)\n"
        }
        return s
    }

    /// 写成临时 txt 文件（交给系统分享面板）；失败返回 nil
    static func exportFile(_ f: LogFilter = .all) -> URL? {
        let df = DateFormatter(); df.dateFormat = "yyyyMMdd-HHmmss"
        let url = AppDirs.outDir.appendingPathComponent("lucida-log-" + df.string(from: Date()) + ".txt")
        do { try text(f).write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    static func clear() {
        shared.lock.lock(); shared.buf.removeAll(); shared.lock.unlock()
        try? FileManager.default.removeItem(at: shared.fileURL)
        shared.add(.info, "日志", "日志已清空", force: true)
    }

    /// 立刻把最近 200 条写到磁盘（进后台时会自动调）
    static func flush() { shared.writeNow() }

    // MARK: 内部
    fileprivate let lock = NSLock()
    fileprivate var buf: [LogEntry] = []
    private var on = true
    private var pending: DispatchWorkItem?
    private var notifyPending = false
    private let io = DispatchQueue(label: "lucida.log.io", qos: .utility)
    private static var prevHandler: NSUncaughtExceptionHandler?

    fileprivate var fileURL: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d.appendingPathComponent("lucida-log.json")
    }

    fileprivate var isOn: Bool { lock.lock(); defer { lock.unlock() }; return on }
    fileprivate func setOn(_ v: Bool) {
        if !v { add(.info, "日志", "日志记录已关闭", force: true) }
        lock.lock(); on = v; lock.unlock()
        SettingsStore.set("logOn", v ? "1" : "0")
        if v { add(.info, "日志", "日志记录已开启", force: true) }
    }

    private init() {
        on = SettingsStore.get("logOn") == "1"
        buf = loadFromDisk()
        add(.info, "App", "—— 新的一次运行 · \(AppInfo.name) \(AppInfo.version)（\(AppInfo.build)） · \(AppLog.machine()) · iOS \(UIDevice.current.systemVersion)", force: true)
        installObservers()
        installCrashHook()
    }

    private static func machine() -> String {
        var sys = utsname(); uname(&sys)
        let mirror = Mirror(reflecting: sys.machine)
        return mirror.children.reduce("") { acc, e in
            guard let v = e.value as? Int8, v != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(v)))
        }
    }

    fileprivate func add(_ level: LogLevel, _ tag: String, _ msg: String, force: Bool) {
        lock.lock(); let enabled = on; lock.unlock()
        if !enabled && !force { return }
        var m = msg
        if m.count > AppLog.maxMessageLength { m = String(m.prefix(AppLog.maxMessageLength)) + "…" }
        let e = LogEntry(time: Date().timeIntervalSince1970, level: level, tag: tag, msg: m, prev: false)
        lock.lock()
        buf.append(e)
        if buf.count > AppLog.capacity { buf.removeFirst(buf.count - AppLog.capacity) }
        lock.unlock()
        schedulePersist(urgent: level == .error)
        notifyChanged()
    }

    private func schedulePersist(urgent: Bool) {
        lock.lock()
        pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.writeNow() }
        pending = w
        lock.unlock()
        io.asyncAfter(deadline: .now() + (urgent ? 0.15 : 1.0), execute: w)
    }

    fileprivate func writeNow() {
        lock.lock(); let slice = Array(buf.suffix(AppLog.persistCount)); lock.unlock()
        var arr: [[String: Any]] = []
        for e in slice { arr.append(["t": Int((e.time * 1000).rounded()), "l": e.level.rawValue, "g": e.tag, "m": e.msg]) }
        guard let data = try? JSONSerialization.data(withJSONObject: arr) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func loadFromDisk() -> [LogEntry] {
        guard let data = try? Data(contentsOf: fileURL),
              let arr = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [] }
        var out: [LogEntry] = []
        for o in arr {
            let t = (o["t"] as? NSNumber)?.doubleValue ?? 0
            let l = LogLevel(rawValue: (o["l"] as? NSNumber)?.intValue ?? 0) ?? .info
            let g = (o["g"] as? String) ?? ""
            let m = (o["m"] as? String) ?? ""
            out.append(LogEntry(time: t / 1000, level: l, tag: g, msg: m, prev: true))
        }
        return out
    }

    private func notifyChanged() {
        lock.lock()
        if notifyPending { lock.unlock(); return }
        notifyPending = true
        lock.unlock()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self else { return }
            self.lock.lock(); self.notifyPending = false; self.lock.unlock()
            NotificationCenter.default.post(name: AppLog.didChange, object: nil)
        }
    }

    private func installObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { [weak self] _ in
            self?.add(.warn, "系统", "收到内存警告（系统认为内存紧张，App 可能随后被关闭）", force: false)
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.add(.info, "系统", "进入后台", force: false)
            self?.writeNow()
        }
        nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.add(.info, "系统", "回到前台", force: false)
        }
        nc.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: nil) { [weak self] _ in
            var name = "未知"
            var lv = LogLevel.info
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: name = "正常"
            case .fair: name = "轻微发热"
            case .serious: name = "严重发热"; lv = .warn
            case .critical: name = "危急发热"; lv = .warn
            @unknown default: break
            }
            self?.add(lv, "系统", "设备温度状态：" + name, force: false)
        }
    }

    /// 未捕获的 ObjC 异常（比如 AVAssetWriter 用法不对）：先把原因写进日志并落盘，再交给原来的处理器
    private func installCrashHook() {
        AppLog.prevHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { ex in
            let stack = ex.callStackSymbols.prefix(15).joined(separator: "\n")
            AppLog.shared.add(.error, "崩溃", "未捕获的异常 \(ex.name.rawValue)：\(ex.reason ?? "")\n" + stack, force: true)
            AppLog.shared.writeNow()
            AppLog.prevHandler?(ex)
        }
    }
}
