import UIKit
import AVFoundation
import CoreMedia

// 设置里的五个独立页面（设置页的 dest）：故障报错日志 / 摄像头检测 / 版本更新 / 关于澄影 / 赞赏。
// 都画在设置页的滚动区里（SettingsPageViewController.stack），颜色走 PanelPalette，文案来自 ContentData。

extension SettingsPageViewController {
    static let m3Dests: Set<String> = ["log", "cams", "version", "about", "donate"]

    func m3Title(_ dest: String) -> String {
        switch dest {
        case "log": return "故障报错日志"
        case "cams": return "摄像头检测"
        case "version": return "版本更新"
        case "about": return "关于澄影"
        case "donate": return "赞赏"
        default: return "设置"
        }
    }

    func buildM3(_ dest: String) {
        switch dest {
        case "log": buildLog()
        case "cams": buildCams()
        case "version": buildVersion()
        case "about": buildAbout()
        case "donate": buildDonate()
        default: break
        }
    }

    private func m3Card() -> SettingsCard { SettingsCard(glass: st.glass) }

    /// 可点的行（SettingsRowView 的 onTap 要单独设置，这里合成一步）
    private func tapRow(_ title: String, sub: String = "", accessory: UIView? = nil, _ action: @escaping () -> Void) -> SettingsRowView {
        let r = SettingsRowView(title: title, sub: sub, accessory: accessory)
        r.onTap = action
        return r
    }

    private func m3Add(_ v: UIView, after s: CGFloat = 18) {
        stack.addArrangedSubview(v)
        spaceAfterLast(s)
    }

    // MARK: - 故障报错日志

    private static let logDF: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss"; return f
    }()

    func buildLog() {
        if logObserver == nil {
            logObserver = NotificationCenter.default.addObserver(forName: AppLog.didChange, object: nil, queue: .main) { [weak self] _ in
                guard let self = self, case .page(let d) = self.kind, d == "log" else { return }
                self.rebuild()
            }
        }

        // 记录开关
        let sw = GlassSwitch(on: AppLog.enabled)
        sw.glass = st.glass
        sw.widthAnchor.constraint(equalToConstant: 50).isActive = true
        sw.heightAnchor.constraint(equalToConstant: 28).isActive = true
        sw.onChange = { v in AppLog.enabled = v }
        let c1 = m3Card()
        c1.addRow(SettingsRowView(title: "记录日志", sub: "关闭后不再记录新的日志；已经记下的保留", accessory: sw, interactiveAccessory: true))
        m3Add(c1)

        // 筛选
        let seg = GlassSegmented(items: ["全部", "警告及以上", "错误"], selected: logFilter)
        seg.glass = st.glass
        seg.heightAnchor.constraint(equalToConstant: 38).isActive = true
        seg.onChange = { [weak self] i in
            DispatchQueue.main.async { self?.logFilter = i; self?.rebuild() }
        }
        let c2 = m3Card()
        c2.addRow(SettingsControlRow(title: "显示", sub: "", control: seg))
        m3Add(c2, after: 8)

        // 列表（最新的在前，最多显示 120 条）
        let all = AppLog.entries(.all).reversed()
        let filtered = all.filter { e in
            switch logFilter {
            case 1: return e.level != .info
            case 2: return e.level == .error
            default: return true
            }
        }
        if filtered.isEmpty {
            m3Add(SettingsText.note("还没有记录。出现问题时会自动记在这里。"), after: 18)
        } else {
            let shown = Array(filtered.prefix(120))
            let c3 = m3Card()
            for e in shown { c3.addRow(logRow(e)) }
            m3Add(c3, after: 6)
            if filtered.count > shown.count {
                m3Add(SettingsText.note("共 \(filtered.count) 条，这里只显示最近 \(shown.count) 条；导出可以看全部。"), after: 18)
            } else {
                spaceAfterLast(18)
            }
        }

        // 操作
        let c4 = m3Card()
        c4.addRow(tapRow("导出全部日志", sub: "导出为文本，可以发给开发者排查问题", accessory: chevron()) { [weak self] in
            self?.exportLog()
        })
        let clear = SettingsRowView(title: "清空日志", sub: "只清空记录，不影响设置", accessory: nil)
        clear.titleColor = PanelPalette.danger
        clear.restyle()
        clear.onTap = { [weak self] in self?.confirmClearLog() }
        c4.addRow(clear)
        m3Add(c4, after: 18)
    }

    private func logRow(_ e: LogEntry) -> UIView {
        let key = "\(e.time)|\(e.tag)|\(e.msg.prefix(40))"
        let expanded = expandedLogKeys.contains(key)
        let levelColor: UIColor = {
            switch e.level {
            case .error: return PanelPalette.danger
            case .warn: return dualYellow
            case .info: return PanelPalette.sub
            }
        }()
        let levelL = UILabel()
        levelL.text = e.level.title
        levelL.textColor = levelColor
        levelL.font = .systemFont(ofSize: 12.5, weight: .semibold)
        let when = SettingsPageViewController.logDF.string(from: Date(timeIntervalSince1970: e.time))
        let title = when + "  " + e.tag + (e.prev ? "  · 上次运行" : "")
        let shownMsg = expanded ? e.msg : SettingsPageViewController.collapse(e.msg)
        let row = SettingsRowView(title: title, sub: shownMsg, accessory: levelL)
        row.titleL.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        row.accessibilityValue = e.msg                       // 长按复制时取完整内容
        row.onTap = { [weak self] in
            guard let self = self else { return }
            if self.expandedLogKeys.contains(key) { self.expandedLogKeys.remove(key) } else { self.expandedLogKeys.insert(key) }
            self.rebuild()
        }
        let press = UILongPressGestureRecognizer(target: self, action: #selector(logLongPress(_:)))
        row.addGestureRecognizer(press)
        return row
    }

    /// 折叠显示：最多两行、约 120 字
    static func collapse(_ s: String) -> String {
        let firstTwo = s.split(separator: "\n", omittingEmptySubsequences: false).prefix(2).joined(separator: "\n")
        if firstTwo.count > 120 || s.split(separator: "\n").count > 2 {
            return String(firstTwo.prefix(120)) + "…（点一下展开）"
        }
        return s
    }

    @objc func logLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began, let v = g.view as? SettingsRowView, let text = v.accessibilityValue else { return }
        UIPasteboard.general.string = v.titleL.text.map { $0 + "\n" + text } ?? text
        showToast("已复制这一条")
    }

    private func exportLog() {
        guard let url = AppLog.exportFile(.all) else { showToast("导出失败"); return }
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = view
        present(vc, animated: true)
    }

    private func confirmClearLog() {
        let a = UIAlertController(title: "清空日志？", message: "已经记下的日志会全部删除，不能恢复。", preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "取消", style: .cancel))
        a.addAction(UIAlertAction(title: "清空", style: .destructive) { [weak self] _ in
            AppLog.clear()
            self?.expandedLogKeys.removeAll()
            self?.rebuild()
        })
        present(a, animated: true)
    }

    // MARK: - 摄像头检测（只查询，不碰相机会话）

    func camsReport() -> [(name: String, sub: String)] {
        let types: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera,
                                                   .builtInDualCamera, .builtInDualWideCamera, .builtInTripleCamera]
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: .video, position: .unspecified).devices
        return devices.map { d -> (name: String, sub: String) in
            let pos: String
            switch d.position {
            case .back: pos = "后置"
            case .front: pos = "前置"
            default: pos = "未知位置"
            }
            var maxW = 0, maxH = 0, maxFps = 0.0
            for f in d.formats {
                let dim = CMVideoFormatDescriptionGetDimensions(f.formatDescription)
                if Int(dim.width) * Int(dim.height) > maxW * maxH { maxW = Int(dim.width); maxH = Int(dim.height) }
                for r in f.videoSupportedFrameRateRanges { maxFps = max(maxFps, r.maxFrameRate) }
            }
            var lines: [String] = []
            lines.append("位置：\(pos) · 类型：\(typeName(d.deviceType))")
            lines.append("最大分辨率：\(maxW)×\(maxH) · 最高帧率：\(Int(maxFps)) fps")
            lines.append(String(format: "当前视场角：%.1f°", d.activeFormat.videoFieldOfView))
            if !d.constituentDevices.isEmpty {
                lines.append("组成镜头：" + d.constituentDevices.map { $0.localizedName }.joined(separator: " + "))
            }
            lines.append("ID：" + String(d.uniqueID.prefix(12)) + "…")
            return (name: d.localizedName, sub: lines.joined(separator: "\n"))
        }
    }

    private func typeName(_ t: AVCaptureDevice.DeviceType) -> String {
        switch t {
        case .builtInWideAngleCamera: return "广角"
        case .builtInUltraWideCamera: return "超广角"
        case .builtInTelephotoCamera: return "长焦"
        case .builtInDualCamera: return "双摄（虚拟）"
        case .builtInDualWideCamera: return "双广角（虚拟）"
        case .builtInTripleCamera: return "三摄（虚拟）"
        default: return "其它"
        }
    }

    func buildCams() {
        let items = camsReport()
        let multi = AVCaptureMultiCamSession.isMultiCamSupported
        let c0 = m3Card()
        c0.addRow(SettingsRowView(title: "摄像头数量", value: "\(items.count) 个"))
        c0.addRow(SettingsRowView(title: "多摄同时工作", sub: "系统是否允许前后摄像头同时开启（双摄功能需要）", value: multi ? "支持" : "不支持"))
        m3Add(c0, after: 18)

        if items.isEmpty {
            m3Add(SettingsText.note("没有查到摄像头。"), after: 18)
        } else {
            m3Add(SettingsText.subhead("每颗摄像头"), after: 6)
            let c1 = m3Card()
            for it in items { c1.addRow(SettingsRowView(title: it.name, sub: it.sub)) }
            m3Add(c1, after: 18)
        }

        let c2 = m3Card()
        c2.addRow(tapRow("复制检测结果", sub: "纯文本，方便粘贴发给我们排查", accessory: chevron()) { [weak self] in
            guard let self = self else { return }
            let body = self.camsReport().map { "【\($0.name)】\n\($0.sub)" }.joined(separator: "\n\n")
            let head = "澄影 \(AppInfo.version)（build \(AppInfo.build)）· 多摄同时：\(multi ? "支持" : "不支持")\n\n"
            UIPasteboard.general.string = head + body
            self.showToast("已复制检测结果")
        })
        m3Add(c2, after: 18)
    }

    // MARK: - 版本更新

    func buildVersion() {
        let c0 = m3Card()
        c0.addRow(SettingsRowView(title: "当前版本", value: "\(AppInfo.version)（build \(AppInfo.build)）"))
        let check = SettingsRowView(title: "检查更新", sub: "暂未开放，需要的话请到发布的地方手动下载", value: "暂未开放")
        check.alpha = 0.45
        check.onTap = { [weak self] in self?.showToast("检查更新暂未开放") }
        c0.addRow(check)
        m3Add(c0, after: 22)

        // 新版本记录：默认展开
        let news = ContentData.updates.filter { $0.group == "new" }
        m3Add(SettingsText.subhead("新版本记录"), after: 8)
        if news.isEmpty {
            m3Add(SettingsText.note("新版本的更新记录正在整理，稍后在这里显示。"), after: 18)
        } else {
            for e in news { m3UpdateEntry(e) }
        }

        // 旧版记录（11.x）：默认折叠，点一下展开
        let olds = ContentData.updates.filter { $0.group == "old" }
        let arrow = chevron()
        arrow.transform = versionOldExpanded ? CGAffineTransform(rotationAngle: CGFloat.pi / 2) : .identity
        let c1 = m3Card()
        c1.addRow(tapRow("旧版记录（11.x）", sub: "共 \(olds.count) 条，点一下\(versionOldExpanded ? "收起" : "展开")", accessory: arrow) { [weak self] in
            guard let self = self else { return }
            self.versionOldExpanded.toggle()
            self.rebuild()
        })
        m3Add(c1, after: 18)
        if versionOldExpanded {
            for e in olds { m3UpdateEntry(e) }
        }
    }

    /// 一个版本：小标题 + 卡片（每条一行）
    private func m3UpdateEntry(_ entry: UpdateEntry) {
        m3Add(SettingsText.subhead("v\(entry.version)　\(entry.date)"), after: 6)
        let c = m3Card()
        for it in entry.items {
            if it.title.isEmpty {
                c.addRow(SettingsRowView(title: it.body, sub: ""))
            } else {
                c.addRow(SettingsRowView(title: it.title, sub: it.body))
            }
        }
        m3Add(c, after: 16)
    }

    // MARK: - 关于澄影

    private func centeredStack(_ views: [UIView], spacing: CGFloat) -> UIStackView {
        let s = UIStackView(arrangedSubviews: views)
        s.axis = .vertical; s.alignment = .center; s.spacing = spacing
        return s
    }

    private func roundImage(_ name: String, size: CGFloat, radius: CGFloat) -> UIImageView {
        let iv = UIImageView(image: UIImage(named: name))
        iv.contentMode = .scaleAspectFill
        iv.clipsToBounds = true
        iv.layer.cornerRadius = radius; iv.layer.cornerCurve = .continuous
        iv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([iv.widthAnchor.constraint(equalToConstant: size), iv.heightAnchor.constraint(equalToConstant: size)])
        return iv
    }

    func buildAbout() {
        let logo = roundImage("AboutLogo", size: 96, radius: 22)
        let title = UILabel(); title.text = ContentData.aboutTitle
        title.textColor = PanelPalette.text; title.font = .systemFont(ofSize: 26, weight: .bold)
        let ver = UILabel(); ver.text = ContentData.aboutVerPrefix + AppInfo.version
        ver.textColor = PanelPalette.sub; ver.font = .systemFont(ofSize: 14)
        let hero = centeredStack([logo, title, ver], spacing: 10)
        hero.setCustomSpacing(14, after: logo)
        m3Add(hero, after: 22)

        for sec in ContentData.aboutSections {
            let h = UILabel(); h.text = sec.heading
            h.textColor = dualYellow; h.font = .systemFont(ofSize: 16, weight: .semibold)
            m3Add(SettingsText.pad(h, left: 10, right: 10), after: 4)
            m3Add(SettingsText.body(sec.paragraph), after: 16)
        }

        let devImg = roundImage("AboutDev", size: 56, radius: 28)
        let dn = UILabel(); dn.text = ContentData.devName
        dn.textColor = PanelPalette.text; dn.font = .systemFont(ofSize: 17, weight: .semibold)
        let ds = UILabel(); ds.text = ContentData.devSub
        ds.textColor = PanelPalette.sub; ds.font = .systemFont(ofSize: 12)
        let names = UIStackView(arrangedSubviews: [dn, ds]); names.axis = .vertical; names.spacing = 3
        let devRow = UIStackView(arrangedSubviews: [devImg, names]); devRow.axis = .horizontal; devRow.spacing = 14; devRow.alignment = .center
        devRow.translatesAutoresizingMaskIntoConstraints = false
        let devBox = UIView(); devBox.addSubview(devRow)
        NSLayoutConstraint.activate([
            devRow.topAnchor.constraint(equalTo: devBox.topAnchor, constant: 14), devRow.bottomAnchor.constraint(equalTo: devBox.bottomAnchor, constant: -14),
            devRow.leadingAnchor.constraint(equalTo: devBox.leadingAnchor, constant: 16), devRow.trailingAnchor.constraint(lessThanOrEqualTo: devBox.trailingAnchor, constant: -16)])
        let c = m3Card(); c.addRow(devBox)
        m3Add(c, after: 18)
    }

    // MARK: - 赞赏

    func buildDonate() {
        let hero = UILabel(); hero.text = ContentData.donateHeroTitle
        hero.textColor = PanelPalette.text; hero.font = .systemFont(ofSize: 24, weight: .bold); hero.textAlignment = .center
        let sub = UILabel(); sub.text = ContentData.donateHeroSub
        sub.textColor = PanelPalette.sub; sub.font = .systemFont(ofSize: 14); sub.textAlignment = .center
        let en = UILabel(); en.text = ContentData.donateEn
        en.textColor = dualYellow; en.font = .systemFont(ofSize: 11, weight: .semibold); en.textAlignment = .center
        let head = centeredStack([en, hero, sub], spacing: 6)
        m3Add(head, after: 20)

        let lead = UILabel(); lead.text = ContentData.donateModalTitle + "\n" + ContentData.donateLead
        lead.textColor = PanelPalette.text; lead.font = .systemFont(ofSize: 15); lead.numberOfLines = 0; lead.textAlignment = .center
        m3Add(SettingsText.pad(lead, left: 16, right: 16), after: 10)

        let quote = UILabel(); quote.text = ContentData.donateQuote
        quote.textColor = PanelPalette.sub; quote.font = .systemFont(ofSize: 13); quote.numberOfLines = 0; quote.textAlignment = .center
        m3Add(SettingsText.pad(quote, left: 16, right: 16), after: 18)

        let qr = roundImage("DonateQR", size: 260, radius: 18)
        qr.isUserInteractionEnabled = true
        qr.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(qrLongPress(_:))))
        let qrBox = UIView(); qrBox.addSubview(qr)
        qr.centerXAnchor.constraint(equalTo: qrBox.centerXAnchor).isActive = true
        qr.topAnchor.constraint(equalTo: qrBox.topAnchor).isActive = true
        qr.bottomAnchor.constraint(equalTo: qrBox.bottomAnchor).isActive = true
        m3Add(qrBox, after: 10)

        let scan = UILabel(); scan.text = ContentData.donateScan
        scan.textColor = PanelPalette.note; scan.font = .systemFont(ofSize: 12.5); scan.textAlignment = .center
        m3Add(scan, after: 14)

        let chips = UIStackView(arrangedSubviews: ContentData.donateChips.map { chip($0) })
        chips.axis = .horizontal; chips.spacing = 8; chips.distribution = .fillEqually
        m3Add(SettingsText.pad(chips, left: 16, right: 16), after: 20)

        let c = m3Card()
        c.addRow(tapRow(ContentData.donateSave, sub: "长按上面的二维码也可以保存", accessory: chevron()) { [weak self] in
            self?.saveQR()
        })
        m3Add(c, after: 18)

        let foot = UILabel(); foot.text = ContentData.donateFoot
        foot.textColor = PanelPalette.note; foot.font = .systemFont(ofSize: 12); foot.textAlignment = .center
        m3Add(foot, after: 10)
    }

    private func chip(_ text: String) -> UIView {
        let l = UILabel(); l.text = text
        l.textColor = PanelPalette.text; l.font = .systemFont(ofSize: 12.5); l.textAlignment = .center
        l.numberOfLines = 2; l.adjustsFontSizeToFitWidth = true; l.minimumScaleFactor = 0.8
        let box = UIView()
        box.backgroundColor = PanelPalette.hover
        box.layer.cornerRadius = 12; box.layer.cornerCurve = .continuous
        l.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(l)
        NSLayoutConstraint.activate([
            l.topAnchor.constraint(equalTo: box.topAnchor, constant: 9), l.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -9),
            l.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 6), l.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -6)])
        return box
    }

    @objc func qrLongPress(_ g: UILongPressGestureRecognizer) {
        if g.state == .began { saveQR() }
    }

    private func saveQR() {
        guard let img = UIImage(named: "DonateQR") else { showToast("赞赏码找不到"); return }
        UIImageWriteToSavedPhotosAlbum(img, self, #selector(qrSaved(_:didFinishSavingWithError:contextInfo:)), nil)
    }

    @objc func qrSaved(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeMutableRawPointer?) {
        showToast(error == nil ? "已保存到系统相册" : "保存失败：请在系统设置里允许澄影添加照片")
    }
}
