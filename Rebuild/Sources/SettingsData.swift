// 自动生成，请勿手改 —— 改 tools/gen_settings.py 后重新生成。
import Foundation

extension SettingsRegistry {
    static func build_account() -> SCollection {
        var groups: [SGroup] = []
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "acct", title: "登录账号", sub: "登录与会员功能暂未加入", type: .link, scope: .both, status: .soon, def: "", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "person.crop.circle", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        return SCollection(id: "account", title: "账号", kind: .inline, summary: "", intro: "", icon: "", groups: groups)
    }

    static func build_appearance() -> SCollection {
        var groups: [SGroup] = []
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "mid", title: "原中版", sub: "默认皮肤", short: "原中版"))
                opts.append(SOption(v: "fish", title: "大肥鱼", sub: "带角色的皮肤", short: "大肥鱼"))
                items.append(SItem(id: "skin", title: "外观 / 皮肤", sub: "", type: .radio, scope: .both, status: .soon, def: "mid", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "paintbrush", min: 0, max: 0))
            }
            groups.append(SGroup(head: "皮肤", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "glass", title: "默认（液态玻璃）", sub: "面板使用半透明玻璃效果", short: "默认（液态玻璃）"))
                opts.append(SOption(v: "dark", title: "黑色面板 UI", sub: "纯黑色面板，去掉玻璃和模糊，更省性能", short: "黑色面板 UI"))
                opts.append(SOption(v: "light", title: "白色面板 UI", sub: "纯白色面板，去掉玻璃和模糊，更省性能", short: "白色面板 UI"))
                items.append(SItem(id: "panelTheme", title: "面板样式", sub: "", type: .radio, scope: .both, status: .soon, def: "glass", options: opts, notes: ["选中纯色面板后所有界面改成纯色，去掉玻璃和模糊，更省性能，适合老设备。选默认就是玻璃效果。"], dest: "", inline: true, reconfigure: false, icon: "rectangle.fill", min: 0, max: 0))
            }
            groups.append(SGroup(head: "面板", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "glass", title: "液态玻璃界面", sub: "iOS 26 及以上使用系统原生液态玻璃；低版本自动用普通毛玻璃", type: .toggle, scope: .both, status: .live, def: "0", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "drop", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "uiScale", title: "界面大小", sub: "缩放全部界面（栏、面板、设置页、相册等；取景画面本身不变）。设置页自己最小只缩到 30%，保证你总能回来改。", type: .slider, scope: .both, status: .soon, def: "100", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "arrow.up.left.and.arrow.down.right", min: 1, max: 200))
            }
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "fontScale", title: "字体大小", sub: "缩放全部界面文字。设置页里最小只缩到 30%，保证看得见。", type: .slider, scope: .both, status: .soon, def: "100", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "textformat.size", min: 1, max: 200))
            }
            groups.append(SGroup(head: "大小与字体", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "uiReset", title: "每一次打开都重置界面大小和字体大小", sub: "调得太大点不到设置时，重启 App 就恢复 100%", type: .toggle, scope: .both, status: .soon, def: "1", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "arrow.counterclockwise", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "0", title: "无", sub: "不显示灵动岛（录制时仅显示计时）", short: "无"))
                opts.append(SOption(v: "17", title: "iPhone 17 Pro", sub: "标准灵动岛", short: "iPhone 17 Pro"))
                opts.append(SOption(v: "18", title: "iPhone 18 Pro", sub: "更小的灵动岛（宽度缩小约 25%）", short: "iPhone 18 Pro"))
                items.append(SItem(id: "island", title: "灵动岛样式", sub: "", type: .radio, scope: .both, status: .soon, def: "17", options: opts, notes: ["用于调整相机界面顶部灵动岛（含录制计时）的外观，选中后立即生效。"], dest: "", inline: false, reconfigure: false, icon: "capsule", min: 0, max: 0))
            }
            groups.append(SGroup(head: "灵动岛", foot: "", items: items))
        }
        return SCollection(id: "appearance", title: "界面与外观", kind: .page, summary: "皮肤 · 面板 · 大小 · 字体", intro: "皮肤、面板、大小和字体的设置还在适配中，现在只有「液态玻璃 / 毛玻璃界面」能用。", icon: "paintbrush", groups: groups)
    }

    static func build_photo() -> SCollection {
        var groups: [SGroup] = []
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "15", title: "15 帧", sub: "最省内存和电量", short: "15 帧"))
                opts.append(SOption(v: "30", title: "30 帧（推荐）", sub: "流畅，内存适中", short: "30 帧"))
                opts.append(SOption(v: "60", title: "60 帧", sub: "最顺滑；每帧像素会比 30 帧略小", short: "60 帧"))
                items.append(SItem(id: "sLiveFps", title: "实况帧率", sub: "", type: .radio, scope: .single, status: .soon, def: "30", options: opts, notes: [], dest: "", inline: true, reconfigure: false, icon: "speedometer", min: 0, max: 0))
            }
            groups.append(SGroup(head: "实况帧率", foot: "只影响之后拍的实况，也决定编辑后实况视频重新生成时的帧率。已拍好的 15 帧实况无法凭空补帧。", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "3", title: "3 秒（默认）", sub: "快门前 1.5 秒 + 快门后 1.5 秒", short: "3 秒"))
                opts.append(SOption(v: "5", title: "5 秒", sub: "快门前 1.5 秒 + 快门后 3.5 秒", short: "5 秒"))
                opts.append(SOption(v: "6", title: "6 秒", sub: "快门前 1.5 秒 + 快门后 4.5 秒", short: "6 秒"))
                opts.append(SOption(v: "8", title: "8 秒", sub: "快门前 1.5 秒 + 快门后 6.5 秒；建议配 15～30 帧", short: "8 秒"))
                items.append(SItem(id: "sLiveDur", title: "实况时长", sub: "", type: .radio, scope: .single, status: .soon, def: "3", options: opts, notes: [], dest: "", inline: true, reconfigure: false, icon: "timer", min: 0, max: 0))
            }
            groups.append(SGroup(head: "实况时长", foot: "只影响之后拍的实况。快门前固定记录 1.5 秒，其余时间在按下快门后继续记录；时间越长，合成越久。", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "0", title: "只存实况", sub: "只保存一个实况照片（默认）", short: "只存实况"))
                opts.append(SOption(v: "1", title: "实况 + 静态照片", sub: "实况之外，再多存一张同一瞬间的静态照片", short: "实况 + 静态照片"))
                items.append(SItem(id: "sLiveStill", title: "实况保存方式", sub: "", type: .radio, scope: .single, status: .soon, def: "0", options: opts, notes: ["选「实况 + 静态照片」时，每次拍摄会在系统相册里多一张同一瞬间的静态照片。"], dest: "", inline: false, reconfigure: false, icon: "livephoto", min: 0, max: 0))
            }
            groups.append(SGroup(head: "实况保存", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "sLiveTimer", title: "实况计时显示", sub: "拍实况时在取景框左上角显示已经拍到第几秒、有没有拍完", type: .toggle, scope: .single, status: .soon, def: "1", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "clock", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        return SCollection(id: "photo", title: "拍照与实况", kind: .inline, summary: "", intro: "", icon: "", groups: groups)
    }

    static func build_video() -> SCollection {
        var groups: [SGroup] = []
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "audio", title: "录像时录制声音", sub: "关闭后录下来的视频没有声音", type: .toggle, scope: .both, status: .live, def: "1", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "mic", min: 0, max: 0))
            }
            groups.append(SGroup(head: "录制", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "direct", title: "直录模式", sub: "", type: .toggle, scope: .both, status: .soon, def: "1", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "video", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "录像直接使用摄像头原始画面、由硬件编码，4K 与 60 帧最稳定。直录时录制中不能变焦；已放大、或所选比例与镜头原生画面不同时，会自动改用画布录制（4K 下帧率可能偏低）。", items: items))
        }
        return SCollection(id: "video", title: "录像", kind: .inline, summary: "", intro: "", icon: "", groups: groups)
    }

    static func build_palette() -> SCollection {
        var groups: [SGroup] = []
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "order", title: "调色盘预设顺序", sub: "拖动调整 13 个预设的顺序，调色盘里左右滑动就按这个顺序切换；「标准」固定在第一位", type: .link, scope: .both, status: .live, def: "", options: opts, notes: [], dest: "order", inline: false, reconfigure: false, icon: "circle.hexagongrid", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        return SCollection(id: "palette", title: "调色盘", kind: .inline, summary: "", intro: "", icon: "", groups: groups)
    }

    static func build_zoom() -> SCollection {
        var groups: [SGroup] = []
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "0", title: "1× → 10×　快速变焦", sub: "手指横向滑动约 1/3 屏宽，变焦从 1× → 10×", short: "1× → 10×"))
                opts.append(SOption(v: "1", title: "1× → 15×　快速变焦", sub: "手指横向滑动约 1/3 屏宽，变焦从 1× → 15×", short: "1× → 15×"))
                opts.append(SOption(v: "2", title: "1× → 20×　快速变焦", sub: "手指横向滑动约 1/3 屏宽，变焦从 1× → 20×", short: "1× → 20×"))
                opts.append(SOption(v: "3", title: "1× → 25×　快速变焦", sub: "手指横向滑动约 1/3 屏宽，变焦从 1× → 25×", short: "1× → 25×"))
                opts.append(SOption(v: "4", title: "1× → 30×　极速变焦", sub: "手指横向滑动约 1/3 屏宽，变焦从 1× → 30×", short: "1× → 30×"))
                items.append(SItem(id: "zoomSpeed", title: "变焦速度", sub: "", type: .radio, scope: .both, status: .soon, def: "4", options: opts, notes: ["用于调节变焦转盘的跟手程度：档位越高，手指滑动同样距离，变焦变化越大。"], dest: "", inline: false, reconfigure: false, icon: "slider.horizontal.3", min: 0, max: 0))
            }
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "off", title: "关闭 0.5×", sub: "设备没有超广角镜头时选这个，最小变焦为 1×", short: "关闭"))
                opts.append(SOption(v: "0.6", title: "开启 0.6×", sub: "适用于超广角为 0.6× 的安卓设备", short: "0.6×"))
                opts.append(SOption(v: "0.5", title: "开启 0.5×", sub: "标准超广角（iPhone 等，默认）", short: "0.5×"))
                items.append(SItem(id: "uwScale", title: "超广角倍数", sub: "", type: .radio, scope: .both, status: .soon, def: "0.5", options: opts, notes: ["不同手机的超广角倍数不同。选对后，变焦条、转盘的最小倍数和画面视野会与镜头一致；若设备自己的最小变焦更高，会自动取更高的值。"], dest: "", inline: false, reconfigure: false, icon: "eye", min: 0, max: 0))
            }
            groups.append(SGroup(head: "变焦", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "auto", title: "自动", sub: "先按机型推测，第一次切到长焦时再用画面比对校准", short: "自动"))
                opts.append(SOption(v: "2", title: "2×", sub: "iPhone 11 / 12 / 13 / 14 / 15 / 16 双摄", short: "2×"))
                opts.append(SOption(v: "2.5", title: "2.5×", sub: "iPhone 12 Pro Max", short: "2.5×"))
                opts.append(SOption(v: "3", title: "3×", sub: "iPhone 13 Pro、14 Pro、15 Pro", short: "3×"))
                opts.append(SOption(v: "4", title: "4×", sub: "iPhone 17 Pro 系列", short: "4×"))
                opts.append(SOption(v: "5", title: "5×", sub: "iPhone 15 Pro Max、16 Pro 系列", short: "5×"))
                items.append(SItem(id: "teleScale", title: "长焦镜头倍数", sub: "", type: .radio, scope: .both, status: .soon, def: "auto", options: opts, notes: ["手机有长焦镜头时，变焦到这个倍数，就会换成长焦镜头；再往上放大（例如 30×）是在长焦画面上继续数码放大，比主摄直接放大更清晰。自动识别不准时请在这里手动选。"], dest: "", inline: false, reconfigure: false, icon: "scope", min: 0, max: 0))
            }
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "5", title: "大于 5× 变焦显示取景框", sub: "较早出现", short: ">5×"))
                opts.append(SOption(v: "10", title: "大于 10× 变焦显示取景框", sub: "默认", short: ">10×"))
                opts.append(SOption(v: "20", title: "大于 20× 变焦显示取景框", sub: "只在很高倍数时出现", short: ">20×"))
                opts.append(SOption(v: "25", title: "大于 25× 变焦显示取景框", sub: "几乎只在最大倍数附近出现", short: ">25×"))
                opts.append(SOption(v: "off", title: "不显示取景框", sub: "高倍变焦时不显示左上角的小取景框", short: "关闭"))
                items.append(SItem(id: "zoomFrame", title: "变焦放大取景框", sub: "", type: .radio, scope: .both, status: .soon, def: "10", options: opts, notes: ["放大到设定倍数以后，取景画面左上角会出现一个小取景框：整幅画面里用黄色方框标出现在放大到的位置，方便在高倍数下找准目标。"], dest: "", inline: false, reconfigure: false, icon: "viewfinder", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "live", title: "边变焦边切镜头", sub: "三颗镜头（超广角 / 主摄 / 长焦）同时开着，跨过倍数时画面柔和淡入淡出，不黑屏；到长焦倍数（如 3×）就换长焦。手机不让同时开多颗时，自动改为「定格 → 换镜头 → 淡入」", short: "边变焦边切"))
                opts.append(SOption(v: "after", title: "数码接力切镜头", sub: "0.5× 时点长焦倍数（≥5×）：不经主摄，先用超广角数码放大到位，停稳 1 秒再淡入长焦；在长焦点 0.5×：先开超广角（对应倍数）再数码缩回。每次都「预热 → 交换画面」，不黑屏，允许少量等待", short: "数码接力"))
                opts.append(SOption(v: "orig", title: "原版（澄影 23）", sub: "超广角 ↔ 主摄的切换方式原封不动，不预热；长焦在变焦停住后才切", short: "原版"))
                items.append(SItem(id: "lensSwitch", title: "倍率镜头切换", sub: "", type: .radio, scope: .both, status: .soon, def: "orig", options: opts, notes: ["长焦从 10× 起使用：3×~10× 之间用主摄数码放大。三种方式都能用上长焦。\n手机允许同时开多颗镜头时，「边变焦边切」和「数码接力」用「预热」瞬间换画面；iPhone 通常一次只能开一颗镜头，这时三种方式的长焦都是「变焦停住后：定格画面 → 换镜头 → 淡入」，变焦途中不会去开摄像头。往更广的方向变焦（例如 30× 退回 2×）时长焦拍不到，会立刻换。"], dest: "", inline: false, reconfigure: false, icon: "arrow.right.to.line", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "变焦到超广角 / 主摄 / 长焦（10× 起）的倍数时怎么换镜头。三颗镜头会提前同时打开待命，多耗一点电；4K 或手机不支持同时开多颗镜头时自动不启用。", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "30", title: "不扩充（最高 30×）", sub: "原来的范围", short: "最高 30×"))
                opts.append(SOption(v: "50", title: "扩充到 50×", sub: "超出镜头本身的部分为数码放大", short: "扩充到 50×"))
                opts.append(SOption(v: "80", title: "扩充到 80×", sub: "画质会下降，但变焦动作保持顺滑", short: "扩充到 80×"))
                opts.append(SOption(v: "100", title: "扩充到 100×", sub: "最大范围，数码放大最多", short: "扩充到 100×"))
                items.append(SItem(id: "zoomRange", title: "变焦倍率扩充", sub: "", type: .radio, scope: .both, status: .soon, def: "30", options: opts, notes: [], dest: "", inline: true, reconfigure: false, icon: "plus.magnifyingglass", min: 0, max: 0))
            }
            groups.append(SGroup(head: "变焦倍率扩充", foot: "选择转盘、双指和滚轮变焦的最高倍数。超过镜头本身的部分是数码放大。", items: items))
        }
        return SCollection(id: "zoom", title: "变焦与镜头", kind: .page, summary: "变焦 · 镜头 · 倍率扩充", intro: "变焦与镜头的设置还在逐项适配中，暂时都不可用。", icon: "plus.magnifyingglass", groups: groups)
    }

    static func build_pano() -> SCollection {
        var groups: [SGroup] = []
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "soft", title: "柔和羽化（推荐）", sub: "接缝处按离画面中心远近柔和过渡，整体自然、没有硬接缝（第一版的效果）", short: "柔和羽化"))
                opts.append(SOption(v: "detail", title: "细节优先（两频段）", sub: "低频柔和、细节取最近一张，近处物体更少重影，但接缝处可能出现切割线", short: "细节优先"))
                items.append(SItem(id: "panoBlend", title: "360° 全景拼接融合", sub: "", type: .radio, scope: .both, status: .soon, def: "soft", options: opts, notes: [], dest: "", inline: true, reconfigure: false, icon: "waveform.path", min: 0, max: 0))
            }
            groups.append(SGroup(head: "360° 全景拼接融合", foot: "", items: items))
        }
        return SCollection(id: "pano", title: "全景", kind: .page, summary: "拼接融合", intro: "全景拍摄暂未加入，先保留设置入口。", icon: "pano", groups: groups)
    }

    static func build_device() -> SCollection {
        var groups: [SGroup] = []
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "cams", title: "摄像头检测", sub: "列出这台设备的所有摄像头、是否支持多摄同时工作", type: .link, scope: .both, status: .live, def: "", options: opts, notes: [], dest: "cams", inline: false, reconfigure: false, icon: "camera", min: 0, max: 0))
            }
            groups.append(SGroup(head: "设备", foot: "", items: items))
        }
        return SCollection(id: "device", title: "设备与检测", kind: .page, summary: "摄像头检测", intro: "", icon: "camera", groups: groups)
    }

    static func build_dual() -> SCollection {
        var groups: [SGroup] = []
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "3", title: "3 秒", sub: "", short: "3 秒"))
                opts.append(SOption(v: "5", title: "5 秒", sub: "", short: "5 秒"))
                opts.append(SOption(v: "6", title: "6 秒", sub: "", short: "6 秒"))
                opts.append(SOption(v: "8", title: "8 秒", sub: "", short: "8 秒"))
                items.append(SItem(id: "liveDur", title: "实况时长", sub: "快门前固定记录 1.5 秒", type: .seg, scope: .dual, status: .live, def: "3", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "0", title: "只存实况", sub: "", short: "只存实况"))
                opts.append(SOption(v: "1", title: "实况 + 静态照片", sub: "", short: "实况 + 静态照片"))
                items.append(SItem(id: "liveStill", title: "实况保存方式", sub: "", type: .seg, scope: .dual, status: .live, def: "0", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "liveTimer", title: "实况计时显示", sub: "拍实况时在取景框左上角显示已经拍到第几秒、有没有拍完", type: .toggle, scope: .dual, status: .live, def: "1", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "full", title: "片门全开", sub: "前后摄像头都用 4:3 整块传感器规格，成品 3:4；帧率尽量保持所选值", type: .toggle, scope: .dual, status: .live, def: "0", options: opts, notes: [], dest: "", inline: false, reconfigure: true, icon: "", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "fullRate", title: "满帧画面运行录制", sub: "开：不因手机发烫自动降帧，取景和录制都按所选帧率；关：发烫时自动降到 30 帧、60 帧取景隔帧刷新，降低功耗，保证录完的视频流畅", type: .toggle, scope: .dual, status: .live, def: "0", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "0", title: "无", sub: "", short: "无"))
                opts.append(SOption(v: "1", title: "白色", sub: "", short: "白色"))
                opts.append(SOption(v: "2", title: "黑色", sub: "", short: "黑色"))
                items.append(SItem(id: "border", title: "小窗边框", sub: "", type: .seg, scope: .dual, status: .live, def: "0", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "mirror", title: "前置画面镜像", sub: "", type: .toggle, scope: .dual, status: .live, def: "1", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                opts.append(SOption(v: "30", title: "30 帧", sub: "", short: "30 帧"))
                opts.append(SOption(v: "60", title: "60 帧", sub: "", short: "60 帧"))
                opts.append(SOption(v: "120", title: "120 帧", sub: "", short: "120 帧"))
                items.append(SItem(id: "pipDragFps", title: "小窗滑动帧率", sub: "拖动双摄小窗时的画面刷新帧率；越高越顺滑，也更耗电。受屏幕刷新率和前置摄像头帧率限制，120 帧不一定能达到。", type: .seg, scope: .dual, status: .live, def: "60", options: opts, notes: [], dest: "", inline: false, reconfigure: false, icon: "", min: 0, max: 0))
            }
            groups.append(SGroup(head: "", foot: "", items: items))
        }
        return SCollection(id: "dual", title: "双摄设置", kind: .page, summary: "实况 · 片门 · 小窗 · 镜像", intro: "这里的设置只作用于双摄（前后摄像头同时拍摄）。单摄的实况设置在「拍照与实况」里。", icon: "rectangle.on.rectangle", groups: groups)
    }

    static func build_support() -> SCollection {
        var groups: [SGroup] = []
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "donate", title: "赞赏", sub: "支持作者", type: .link, scope: .both, status: .live, def: "", options: opts, notes: [], dest: "donate", inline: false, reconfigure: false, icon: "heart", min: 0, max: 0))
            }
            groups.append(SGroup(head: "支持", foot: "", items: items))
        }
        return SCollection(id: "support", title: "支持", kind: .page, summary: "赞赏", intro: "", icon: "heart", groups: groups)
    }

    static func build_about() -> SCollection {
        var groups: [SGroup] = []
        do {
            var items: [SItem] = []
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "log", title: "故障报错日志", sub: "", type: .link, scope: .both, status: .live, def: "", options: opts, notes: [], dest: "log", inline: false, reconfigure: false, icon: "doc.text", min: 0, max: 0))
            }
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "version", title: "版本更新", sub: "{version}", type: .link, scope: .both, status: .live, def: "", options: opts, notes: [], dest: "version", inline: false, reconfigure: false, icon: "arrow.down.to.line", min: 0, max: 0))
            }
            do {
                var opts: [SOption] = []
                items.append(SItem(id: "about", title: "关于澄影", sub: "", type: .link, scope: .both, status: .live, def: "", options: opts, notes: [], dest: "about", inline: false, reconfigure: false, icon: "info.circle", min: 0, max: 0))
            }
            groups.append(SGroup(head: "关于", foot: "", items: items))
        }
        return SCollection(id: "about", title: "关于", kind: .inline, summary: "", intro: "", icon: "", groups: groups)
    }

    static func buildAll() -> [SCollection] {
        var all: [SCollection] = []
        all.append(build_account())
        all.append(build_appearance())
        all.append(build_photo())
        all.append(build_video())
        all.append(build_palette())
        all.append(build_zoom())
        all.append(build_pano())
        all.append(build_device())
        all.append(build_dual())
        all.append(build_support())
        all.append(build_about())
        return all
    }

    /// 只有存储键、没有设置页入口的键：(id, 默认值)
    static let extraDefaults: [(String, String)] = [
        ("logOn", "1"),
        ("nativeSave", "1"),
    ]
}
