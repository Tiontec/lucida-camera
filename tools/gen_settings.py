#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
设置注册表生成器（Claude B）
单一数据源 → 同时生成
  iOS     : ios/Rebuild/Sources/SettingsData.swift
  Android : android/app/src/main/java/com/lucida/camera/SettingsData.java
改设置的文案 / 顺序 / 默认值 / 状态（live / soon）只改这个文件，然后：
  python3 tools/gen_settings.py <工程根目录，里面有 ios 和 android 两个文件夹>
iOS 与安卓因此永远一致。
"""
import sys, os

class PV:
    """两端不同的文案：PV(ios文案, android文案)"""
    def __init__(self, ios, android): self.ios, self.android = ios, android

def T(x, plat):
    return (x.ios if plat == "ios" else x.android) if isinstance(x, PV) else x

def opt(v, title, sub="", short=None, soon=False, plat="both"):
    return dict(v=v, title=title, sub=sub, short=short if short is not None else title, soon=soon, plat=plat)

def item(id, title, type, **kw):
    d = dict(id=id, title=title, type=type, sub="", scope="both", status="live", default="",
             options=[], notes=[], dest="", inline=False, reconfigure=False, icon="",
             min=0, max=0, platform="both")
    d.update(kw); return d

def group(items, head="", foot=""):
    return dict(head=head, foot=foot, items=items)

def coll(id, title, kind, groups, summary="", intro="", icon=""):
    return dict(id=id, title=title, kind=kind, groups=groups, summary=summary, intro=intro, icon=icon)

# ───────────────────────── 数据 ─────────────────────────
SOON = "soon"; LIVE = "live"

C = []

# 1. 账号（登录暂缓）
C.append(coll("account", "账号", "inline", [
    group([item("acct", "登录账号", "link", sub="等登录与会员功能上线后开放", status=SOON, icon="person.crop.circle")])
]))

# 2. 界面与外观 ▶
C.append(coll("appearance", "界面与外观", "page", summary="皮肤 · 面板 · 大小 · 字体", icon="paintbrush",
  intro="界面风格和面板样式现在可以用；皮肤、大小和字体的设置还在适配中。", groups=[
    group([item("glassStyle", "界面风格", "radio", default="plain", inline=True, icon="drop", options=[
        opt("frosted", "毛玻璃", "半透明深色 + 高光描边", short="毛玻璃"),
        opt("liquid", "液态玻璃", "iOS 26 及以上用系统原生液态玻璃；低版本自动用普通毛玻璃", short="液态玻璃", plat="ios"),
        opt("solid", "固态玻璃", "上一版的液态玻璃：取景画面按透镜折弯（原样保留）", short="固态玻璃", plat="android"),
        opt("liquid2", "液态玻璃", "新：SDF 圆角折射 + 边缘高光（安卓 13 及以上；低版本自动用固态玻璃）", short="液态玻璃", plat="android"),
        opt("plain", "默认面板", "关掉玻璃和模糊，取景和设置都用普通的深色样式（默认）", short="默认面板")],
        foot=PV("选毛玻璃 / 液态玻璃即开启玻璃效果；选默认面板就是关掉玻璃和模糊。", "选毛玻璃 / 液态玻璃即开启玻璃效果；选默认面板就是关掉玻璃和模糊。"))],
        head="界面风格"),
    group([item("skin", "外观 / 皮肤", "radio", default="mid", icon="paintbrush", options=[
        opt("mid", "原中版", "默认皮肤"),
        opt("fish", "大肥鱼", "带角色的皮肤")])], head="皮肤"),
    group([item("panelTheme", "面板样式", "radio", default="glass", icon="rectangle.fill", inline=True,
        options=[opt("glass", PV("默认（液态玻璃）", "默认（毛玻璃）"), "面板使用半透明玻璃效果"),
                 opt("dark", "黑色面板 UI", "纯黑色面板，去掉玻璃和模糊，更省性能"),
                 opt("light", "白色面板 UI", "纯白色面板，去掉玻璃和模糊，更省性能")],
        notes=["选中纯色面板后所有界面改成纯色，去掉玻璃和模糊，更省性能，适合老设备。选默认就是玻璃效果。"])],
        head="面板"),
    group([item("uiScale", "界面大小", "slider", status=SOON, default="100", min=1, max=200, icon="arrow.up.left.and.arrow.down.right",
                sub="等界面大小功能完成后开放。开放后会缩放全部界面（栏、面板、设置页、相册等；取景画面本身不变），设置页自己最小只缩到 30%。"),
           item("fontScale", "字体大小", "slider", status=SOON, default="100", min=1, max=200, icon="textformat.size",
                sub="等字体大小功能完成后开放。开放后会缩放全部界面文字，设置页里最小只缩到 30%。")], head="大小与字体"),
    group([item("uiReset", "每一次打开都重置界面大小和字体大小", "switch", status=SOON, default="1", icon="arrow.counterclockwise",
                sub="等界面大小和字体大小功能完成后开放。调得太大点不到设置时，重启 App 就恢复 100%")]),
    group([item("island", "灵动岛样式", "radio", default="17", platform="ios", icon="capsule", options=[
        opt("0", "无", "不显示灵动岛（录制时仅显示计时）"),
        opt("17", "iPhone 17 Pro", "标准灵动岛", short="iPhone 17 Pro"),
        opt("18", "iPhone 18 Pro", "更小的灵动岛（宽度缩小约 25%）", short="iPhone 18 Pro")],
        notes=["用于调整相机界面顶部灵动岛（含录制计时）的外观，选中后立即生效。"])], head="灵动岛"),
]))

# 2b. 取景与拍摄（A 在 1.3.0–1.5.0 新做的功能：画幅 / 闪光灯 / 倒计时 / 网格线 / 水平仪；都已 live）
C.append(coll("shoot", "取景与拍摄", "inline", [
    group([item("ratio", "画幅比例", "seg", default="16:9", reconfigure=True, icon="aspectratio",
                sub="取景、拍照、录像、实况的成品都按这个比例。片门全开时固定为 4:3",
                options=[opt("16:9", "16:9"), opt("4:3", "4:3"), opt("1:1", "1:1")])]),
    group([item("sFull", "片门全开（单摄）", "switch", scope="single", default="0", reconfigure=True, icon="rectangle.expand.vertical", sub="单摄时用 4:3 整块传感器规格，成品 3:4。双摄的片门全开在「双摄设置」里，两者互不影响")]),
    group([item("flash", "闪光灯", "seg", default="0", icon="bolt",
                sub="拍照补光；自动 = 暗处才闪；拍实况时不起作用",
                options=[opt("0", "关"), opt("1", "自动"), opt("2", "开")])]),
    group([item("timerSec", "倒计时拍摄", "seg", default="0", icon="timer",
                sub="点快门后倒数，数到 0 自动拍；倒数中再点一下快门取消",
                options=[opt("0", "关"), opt("3", "3 秒"), opt("5", "5 秒"), opt("10", "10 秒")])]),
    group([item("countVibrate", "倒计时震动", "switch", default="1", icon="iphone.radiowaves.left.and.right",
                sub="倒计时每数一秒轻震一下；关掉就只有数字，没有震动")], head="倒计时"),
    group([item("grid", "取景网格线", "switch", default="0", icon="grid",
                sub="在取景框里画三分线，方便构图"),
           item("level", "水平仪", "switch", default="0", icon="level",
                sub="取景框中间显示水平线：竖拿手机时线跟地平线平行，歪在 0.8° 内变黄；手机平放俯拍时变成圆圈 + 小圆点")]),
]))

# 3. 拍照与实况（单摄）
C.append(coll("photo", "拍照与实况", "inline", [
    group([item("sLiveFps", "实况帧率", "radio", scope="single", default="30", inline=True, icon="speedometer", options=[
        opt("15", "15 帧", "最省内存和电量"),
        opt("30", "30 帧（推荐）", "流畅，内存适中", short="30 帧"),
        opt("60", "60 帧", "最顺滑；每帧像素会比 30 帧略小")])],
        head="实况帧率", foot="只影响之后拍的实况，也决定编辑后实况视频重新生成时的帧率。已拍好的 15 帧实况无法凭空补帧。"),
    group([item("sLiveDur", "实况时长", "radio", scope="single", default="3", inline=True, icon="timer", options=[
        opt("3", "3 秒（默认）", PV("快门前 1.5 秒 + 快门后 1.5 秒", "从按下快门开始录 3 秒"), short="3 秒"),
        opt("5", "5 秒", PV("快门前 1.5 秒 + 快门后 3.5 秒", "从按下快门开始录 5 秒")),
        opt("6", "6 秒", PV("快门前 1.5 秒 + 快门后 4.5 秒", "从按下快门开始录 6 秒")),
        opt("8", "8 秒", PV("快门前 1.5 秒 + 快门后 6.5 秒；建议配 15～30 帧", "从按下快门开始录 8 秒"))])],
        head="实况时长",
        foot=PV("只影响之后拍的实况。快门前固定记录 1.5 秒，其余时间在按下快门后继续记录；时间越长，合成越久。",
                "只影响之后拍的实况。安卓的动态照片从按下快门开始录，没有快门前 1.5 秒；时间越长，合成越久。")),
    group([item("sLiveStill", "实况保存方式", "radio", scope="single", default="pair", icon="livephoto", options=[
        opt("pair", "照片 + 视频", "实况存成一张照片和一段 3 秒视频两个文件，苹果 / 安卓都一样，都能保存", short="照片 + 视频"),
        opt("native", "只存实况", "优先适配 iPhone：保存时按 iPhone 实况照片的格式存入系统相册（需要原生 App 壳）", short="只存实况", plat="ios")],
        notes=["原生 App：保存时会把照片 + 视频交给系统，写成系统「实况照片」。"])],
        head="实况保存"),
    group([item("sLiveTimer", "实况计时显示", "switch", scope="single", default="1", icon="clock",
                sub="拍实况时在取景框左上角显示已经拍到第几秒、有没有拍完")]),
]))

# 4. 录像
C.append(coll("video", "录像", "inline", [
    group([item("audio", "录像时录制声音", "switch", default="1", icon="mic",
                sub="关闭后录下来的视频没有声音")], head="录制"),
    group([item("direct", "直录模式", "switch", status=SOON, default="1", icon="video", sub="等直录模式完成后开放")],
          foot="录像直接使用摄像头原始画面、由硬件编码，4K 与 60 帧最稳定。直录时录制中不能变焦；已放大、或所选比例与镜头原生画面不同时，会自动改用画布录制（4K 下帧率可能偏低）。"),
]))

# 5. 调色盘（预设顺序入口，已有页面）
C.append(coll("palette", "调色盘", "inline", [
    group([item("order", "调色盘预设顺序", "link", dest="order", icon="circle.hexagongrid",
                sub="拖动调整 13 个预设的顺序，调色盘里左右滑动就按这个顺序切换；「标准」固定在第一位")])
]))

# 6. 变焦与镜头 ▶
ZS = [("0", "1× → 10×", "快速变焦"), ("1", "1× → 15×", "快速变焦"), ("2", "1× → 20×", "快速变焦"),
      ("3", "1× → 25×", "快速变焦"), ("4", "1× → 30×", "极速变焦")]
C.append(coll("zoom", "变焦与镜头", "page", summary="变焦 · 镜头 · 倍率扩充", icon="plus.magnifyingglass",
  intro="变焦与镜头的设置还在逐项适配中，暂时都不可用。", groups=[
    group([
        item("zoomSpeed", "变焦速度", "radio", default="4", icon="slider.horizontal.3",
             options=[opt(v, "%s　%s" % (a, b), "手指横向滑动约 1/3 屏宽，变焦从 %s" % a, short=a) for v, a, b in ZS],
             notes=["用于调节变焦转盘的跟手程度：档位越高，手指滑动同样距离，变焦变化越大。"]),
        item("uwScale", "超广角倍数", "radio", default="0.5", icon="eye", options=[
            opt("off", "关闭 0.5×", "设备没有超广角镜头时选这个，最小变焦为 1×", short="关闭"),
            opt("0.6", "开启 0.6×", "适用于超广角为 0.6× 的安卓设备", short="0.6×"),
            opt("0.5", "开启 0.5×", "标准超广角（iPhone 等，默认）", short="0.5×")],
             notes=["不同手机的超广角倍数不同。选对后，变焦条、转盘的最小倍数和画面视野会与镜头一致；若设备自己的最小变焦更高，会自动取更高的值。"]),
    ], head="变焦"),
    group([
        item("teleScale", "长焦镜头倍数", "radio", default="auto", icon="scope", options=[
            opt("auto", "自动", "先按机型推测，第一次切到长焦时再用画面比对校准", short="自动"),
            opt("2", "2×", "iPhone 11 / 12 / 13 / 14 / 15 / 16 双摄", short="2×"),
            opt("2.5", "2.5×", "iPhone 12 Pro Max", short="2.5×"),
            opt("3", "3×", "iPhone 13 Pro、14 Pro、15 Pro", short="3×"),
            opt("4", "4×", "iPhone 17 Pro 系列", short="4×"),
            opt("5", "5×", "iPhone 15 Pro Max、16 Pro 系列", short="5×")],
             notes=["手机有长焦镜头时，变焦到这个倍数，就会换成长焦镜头；再往上放大（例如 30×）是在长焦画面上继续数码放大，比主摄直接放大更清晰。自动识别不准时请在这里手动选。"]),
        item("zoomFrame", "变焦放大取景框", "radio", default="10", icon="viewfinder", options=[
            opt("10", "大于 10× 变焦显示取景框", "默认", short=">10×"),
            opt("20", "大于 20× 变焦显示取景框", "较晚出现", short=">20×"),
            opt("25", "大于 25× 变焦显示取景框", "", short=">25×"),
            opt("30", "大于 30× 变焦显示取景框", "", short=">30×"),
            opt("50", "大于 50× 变焦显示取景框", "", short=">50×"),
            opt("80", "大于 80× 变焦显示取景框", "", short=">80×"),
            opt("100", "大于 100× 变焦显示取景框", "只在最大倍数附近出现", short=">100×")],
             notes=["放大到设定倍数后，取景画面左上角出现一个小方框，用黄色方框标出画面现在放大到的位置，方便在高倍数下找准目标。"]),
    ]),
    group([item("lensSwitch", "倍率镜头切换", "radio", status=SOON, default="orig", icon="arrow.right.to.line", sub="等倍率镜头切换功能完成后开放，下面三种切换方式都还没有接入", options=[
        opt("live", "边变焦边切镜头", "三颗镜头（超广角 / 主摄 / 长焦）同时开着，跨过倍数时画面柔和淡入淡出，不黑屏；到长焦倍数（如 3×）就换长焦。手机不让同时开多颗时，自动改为「定格 → 换镜头 → 淡入」", short="边变焦边切"),
        opt("after", "数码接力切镜头", "0.5× 时点长焦倍数（≥5×）：不经主摄，先用超广角数码放大到位，停稳 1 秒再淡入长焦；在长焦点 0.5×：先开超广角（对应倍数）再数码缩回。每次都「预热 → 交换画面」，不黑屏，允许少量等待", short="数码接力"),
        opt("orig", "原版（澄影 23）", "超广角 ↔ 主摄的切换方式原封不动，不预热；长焦在变焦停住后才切", short="原版")],
        notes=["长焦从 10× 起使用：3×~10× 之间用主摄数码放大。三种方式都能用上长焦。\n手机允许同时开多颗镜头时，「边变焦边切」和「数码接力」用「预热」瞬间换画面；iPhone 通常一次只能开一颗镜头，这时三种方式的长焦都是「变焦停住后：定格画面 → 换镜头 → 淡入」，变焦途中不会去开摄像头。往更广的方向变焦（例如 30× 退回 2×）时长焦拍不到，会立刻换。"])],
        foot="变焦到超广角 / 主摄 / 长焦（10× 起）的倍数时怎么换镜头。三颗镜头会提前同时打开待命，多耗一点电；4K 或手机不支持同时开多颗镜头时自动不启用。"),
    group([item("zoomRange", "变焦倍率扩充", "radio", default="30", inline=True, icon="plus.magnifyingglass", options=[
        opt("30", "不扩充（最高 30×）", "原来的范围", short="最高 30×"),
        opt("50", "扩充到 50×", "超出镜头本身的部分为数码放大", short="扩充到 50×"),
        opt("80", "扩充到 80×", "画质会下降，但变焦动作保持顺滑", short="扩充到 80×"),
        opt("100", "扩充到 100×", "最大范围，数码放大最多", short="扩充到 100×")])],
        head="变焦倍率扩充", foot="选择转盘、双指和滚轮变焦的最高倍数。超过镜头本身的部分是数码放大。"),
]))

# 7. 全景 ▶（暂缓）
C.append(coll("pano", "全景", "page", summary="拼接融合", icon="pano",
  intro="全景拍摄暂未加入，先保留设置入口。", groups=[
    group([item("panoBlend", "360° 全景拼接融合", "radio", status=SOON, default="soft", inline=True, icon="waveform.path", sub="等全景拍摄功能完成后开放（全景拍摄暂未加入）", options=[
        opt("soft", "柔和羽化（推荐）", "接缝处按离画面中心远近柔和过渡，整体自然、没有硬接缝（第一版的效果）", short="柔和羽化"),
        opt("detail", "细节优先（两频段）", "低频柔和、细节取最近一张，近处物体更少重影，但接缝处可能出现切割线", short="细节优先")])],
        head="360° 全景拼接融合")
]))

# 8. 设备与检测 ▶
C.append(coll("device", "设备与检测", "page", summary="摄像头检测", icon="camera", groups=[
    group([item("cams", "摄像头检测", "link", dest="cams", icon="camera",
                sub="列出这台设备的所有摄像头、是否支持多摄同时工作")], head="设备")
]))

# 9. 双摄设置 ▶（新集合：只作用于双摄）
C.append(coll("dual", "双摄设置", "page", summary="实况 · 片门 · 小窗 · 镜像", icon="rectangle.on.rectangle",
  intro="这里的设置只作用于双摄（前后摄像头同时拍摄）。单摄的实况设置在「拍照与实况」里。", groups=[
    group([item("liveDur", "实况时长", "seg", scope="dual", default="3",
                sub=PV("快门前固定记录 1.5 秒", "从按下快门开始录"),
                options=[opt("3", "3 秒"), opt("5", "5 秒"), opt("6", "6 秒"), opt("8", "8 秒")])]),
    group([item("liveStill", "实况保存方式", "seg", scope="dual", default="0",
                options=[opt("0", PV("只存实况", "动态照片（单文件）")), opt("1", PV("实况 + 静态照片", "照片 + 视频分开"))],
                notes=[PV("", "安卓没有苹果那种实况照片：动态照片 = 一张 JPEG 里内嵌从按下快门开始的短视频，Google 相册等支持动态照片的相册可播放；没有快门前 1.5 秒。")])]),
    group([item("liveTimer", "实况计时显示", "switch", scope="dual", default="1",
                sub="拍实况时在取景框左上角显示已经拍到第几秒、有没有拍完")]),
    group([item("full", "片门全开", "switch", scope="dual", default="0", reconfigure=True,
                sub=PV("前后摄像头都用 4:3 整块传感器规格，成品 3:4；帧率尽量保持所选值", "前后摄像头都用 4:3 最大规格，成品 3:4；帧率尽量保持所选值"))]),
    group([item("fullRate", "满帧画面运行录制", "switch", scope="dual", default="0",
                sub=PV("开：不因手机发烫自动降帧，取景和录制都按所选帧率；关：发烫时自动降到 30 帧、60 帧取景隔帧刷新，降低功耗，保证录完的视频流畅",
                       "开：手机发热也不降帧，按你选的帧率显示和录制（可能更烫、更耗电）；关：过热时自动降到 30 帧保护手机"))]),
    group([item("border", "小窗边框", "seg", scope="dual", default="0",
                options=[opt("0", "无"), opt("1", "白色"), opt("2", "黑色")])]),
    group([item("mirror", "前置画面镜像", "switch", scope="dual", default="1")]),
    group([item("pipDragFps", "小窗滑动帧率", "seg", scope="dual", default="60",
                sub="拖动双摄小窗时的画面刷新帧率；越高越顺滑，也更耗电。受屏幕刷新率和前置摄像头帧率限制，120 帧不一定能达到。",
                options=[opt("30", "30 帧"), opt("60", "60 帧"), opt("120", "120 帧")])],
        foot=PV("说明：同时开前后摄像头时，系统不提供 ProRAW；小窗滑动帧率 120 需要支持 120Hz 的屏幕；录下来的视频帧率以「帧率」档位为准。",
                "说明：多摄同时工作时系统不提供 RAW；动态照片声音跟随「录像时录制声音」。")),
]))

# 10. 支持 ▶
C.append(coll("support", "支持", "page", summary="赞赏", icon="heart", groups=[
    group([item("donate", "赞赏", "link", dest="donate", icon="heart", sub="支持作者")], head="支持")
]))

# 11. 关于
C.append(coll("about", "关于", "inline", [
    group([item("log", "故障报错日志", "link", dest="log", icon="doc.text"),
           item("version", "版本更新", "link", dest="version", icon="arrow.down.to.line", sub="{version}"),
           item("about", "关于澄影", "link", dest="about", icon="info.circle")], head="关于")
]))

# 只有存储键、没有设置页入口的键（B 先把键和默认值定好，方便以后接线）
EXTRA_KEYS = [
    # id, 默认, 说明, 平台
    ("logOn", "1", "记录故障日志（日志页里的开关）", "both"),
    ("nativeSave", "1", "直接保存进系统相册（重构版本来就如此；暂不提供设置入口）", "ios"),
]

# ───────────────────────── 生成 ─────────────────────────
def sw_str(s):
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'

def visible_opts(it, plat):
    return [o for o in it["options"] if o.get("plat", "both") in ("both", plat)]

def keep(it, plat):
    return it["platform"] in ("both", plat)

def prune(plat):
    out = []
    for c in C:
        gs = []
        for g in c["groups"]:
            its = [i for i in g["items"] if keep(i, plat)]
            if its: gs.append(dict(g, items=its))
        if gs: out.append(dict(c, groups=gs))
    return out

def gen_swift():
    global PLAT; PLAT = "ios"
    L = []
    w = L.append
    w("// 自动生成，请勿手改 —— 改 tools/gen_settings.py 后重新生成。")
    w("import Foundation")
    w("")
    w("extension SettingsRegistry {")
    names = []
    for c in prune("ios"):
        fn = "build_" + c["id"]; names.append(fn)
        w("    static func %s() -> SCollection {" % fn)
        w("        var groups: [SGroup] = []")
        for g in c["groups"]:
            w("        do {")
            w("            var items: [SItem] = []")
            for it in g["items"]:
                w("            do {")
                w("                var opts: [SOption] = []")
                for o in visible_opts(it, PLAT):
                    w("                opts.append(SOption(v: %s, title: %s, sub: %s, short: %s, soon: %s))" % (
                        sw_str(o["v"]), sw_str(T(o["title"], "ios")), sw_str(T(o["sub"], "ios")), sw_str(T(o["short"], "ios")),
                        "true" if o["soon"] else "false"))
                notes = [T(n, "ios") for n in it["notes"] if T(n, "ios")]
                w("                items.append(SItem(id: %s, title: %s, sub: %s, type: .%s, scope: .%s, status: .%s, def: %s, options: opts, notes: [%s], dest: %s, inline: %s, reconfigure: %s, icon: %s, min: %d, max: %d))" % (
                    sw_str(it["id"]), sw_str(T(it["title"], "ios")), sw_str(T(it["sub"], "ios")), {"switch": "toggle"}.get(it["type"], it["type"]), it["scope"], it["status"],
                    sw_str(it["default"]), ", ".join(sw_str(n) for n in notes), sw_str(it["dest"]),
                    "true" if it["inline"] else "false", "true" if it["reconfigure"] else "false", sw_str(it["icon"]), it["min"], it["max"]))
                w("            }")
            w("            groups.append(SGroup(head: %s, foot: %s, items: items))" % (sw_str(T(g["head"], "ios")), sw_str(T(g["foot"], "ios"))))
            w("        }")
        w("        return SCollection(id: %s, title: %s, kind: .%s, summary: %s, intro: %s, icon: %s, groups: groups)" % (
            sw_str(c["id"]), sw_str(c["title"]), c["kind"], sw_str(c["summary"]), sw_str(c["intro"]), sw_str(c["icon"])))
        w("    }")
        w("")
    w("    static func buildAll() -> [SCollection] {")
    w("        var all: [SCollection] = []")
    for n in names: w("        all.append(%s())" % n)
    w("        return all")
    w("    }")
    w("")
    w("    /// 只有存储键、没有设置页入口的键：(id, 默认值)")
    w("    static let extraDefaults: [(String, String)] = [")
    for k, d, _, p in EXTRA_KEYS:
        if p in ("both", "ios"): w("        (%s, %s)," % (sw_str(k), sw_str(d)))
    w("    ]")
    w("}")
    return "\n".join(L) + "\n"

def jv(s): return sw_str(s)

def gen_java():
    global PLAT; PLAT = "android"
    L = []
    w = L.append
    w("package com.lucida.camera;")
    w("")
    w("import java.util.ArrayList;")
    w("import java.util.List;")
    w("")
    w("/** 自动生成，请勿手改 —— 改 tools/gen_settings.py 后重新生成。每个集合一个方法，避免超出 Java 单方法 64KB 限制。 */")
    w("final class SettingsData {")
    w("    private SettingsData() {}")
    w("")
    names = []
    for c in prune("android"):
        fn = "build_" + c["id"]; names.append(fn)
        w("    static SettingsRegistry.Collection %s() {" % fn)
        w("        List<SettingsRegistry.Group> groups = new ArrayList<SettingsRegistry.Group>();")
        for g in c["groups"]:
            w("        {")
            w("            List<SettingsRegistry.Item> items = new ArrayList<SettingsRegistry.Item>();")
            for it in g["items"]:
                w("            {")
                w("                List<SettingsRegistry.Option> opts = new ArrayList<SettingsRegistry.Option>();")
                for o in visible_opts(it, PLAT):
                    w("                opts.add(new SettingsRegistry.Option(%s, %s, %s, %s, %s));" % (
                        jv(o["v"]), jv(T(o["title"], "android")), jv(T(o["sub"], "android")), jv(T(o["short"], "android")),
                        "true" if o["soon"] else "false"))
                notes = [T(n, "android") for n in it["notes"] if T(n, "android")]
                w("                List<String> notes = new ArrayList<String>();")
                for n in notes: w("                notes.add(%s);" % jv(n))
                w("                items.add(new SettingsRegistry.Item(%s, %s, %s, SettingsRegistry.%s, SettingsRegistry.%s, SettingsRegistry.%s, %s, opts, notes, %s, %s, %s, %s, %d, %d));" % (
                    jv(it["id"]), jv(T(it["title"], "android")), jv(T(it["sub"], "android")),
                    {"switch": "T_SWITCH", "seg": "T_SEG", "link": "T_LINK", "radio": "T_RADIO", "slider": "T_SLIDER", "info": "T_INFO"}[it["type"]],
                    {"dual": "SC_DUAL", "single": "SC_SINGLE", "both": "SC_BOTH"}[it["scope"]],
                    {"live": "S_LIVE", "soon": "S_SOON"}[it["status"]],
                    jv(it["default"]), jv(it["dest"]), "true" if it["inline"] else "false", "true" if it["reconfigure"] else "false",
                    jv(it["icon"]), it["min"], it["max"]))
                w("            }")
            w("            groups.add(new SettingsRegistry.Group(%s, %s, items));" % (jv(T(g["head"], "android")), jv(T(g["foot"], "android"))))
            w("        }")
        w("        return new SettingsRegistry.Collection(%s, %s, SettingsRegistry.%s, %s, %s, %s, groups);" % (
            jv(c["id"]), jv(c["title"]), "K_INLINE" if c["kind"] == "inline" else "K_PAGE", jv(c["summary"]), jv(c["intro"]), jv(c["icon"])))
        w("    }")
        w("")
    w("    static List<SettingsRegistry.Collection> buildAll() {")
    w("        List<SettingsRegistry.Collection> all = new ArrayList<SettingsRegistry.Collection>();")
    for n in names: w("        all.add(%s());" % n)
    w("        return all;")
    w("    }")
    w("")
    w("    /** 只有存储键、没有设置页入口的键：{id, 默认值} */")
    w("    static final String[][] EXTRA_DEFAULTS = {")
    for k, d, _, p in EXTRA_KEYS:
        if p in ("both", "android"): w("        {%s, %s}," % (jv(k), jv(d)))
    w("    };")
    w("}")
    return "\n".join(L) + "\n"

def targets(root):
    """自动识别：
       - 根目录里同时有 ios/ 和 android/（合并目录）→ 两边都写；
       - 根目录本身就是 iOS 工程（有 Rebuild/Sources）→ 只写 iOS；
       - 根目录本身就是安卓工程（有 app/src/main/java/com/lucida/camera）→ 只写安卓。"""
    out = []
    ios_dir = os.path.join(root, "Rebuild/Sources")
    and_dir = os.path.join(root, "app/src/main/java/com/lucida/camera")
    if os.path.isdir(ios_dir): out.append((os.path.join(ios_dir, "SettingsData.swift"), gen_swift))
    if os.path.isdir(and_dir): out.append((os.path.join(and_dir, "SettingsData.java"), gen_java))
    ios2 = os.path.join(root, "ios/Rebuild/Sources"); and2 = os.path.join(root, "android/app/src/main/java/com/lucida/camera")
    if os.path.isdir(ios2): out.append((os.path.join(ios2, "SettingsData.swift"), gen_swift))
    if os.path.isdir(and2): out.append((os.path.join(and2, "SettingsData.java"), gen_java))
    return out

def main():
    root = sys.argv[1] if len(sys.argv) > 1 else "."
    outs = targets(root)
    if not outs:
        print("在 %s 下没找到 iOS（Rebuild/Sources）或安卓（app/src/main/java/com/lucida/camera）工程目录" % root); sys.exit(1)
    for p, g in outs:
        open(p, "w", encoding="utf-8").write(g())
        print("写入", p)

if __name__ == "__main__":
    main()
