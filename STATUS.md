# 状态（11.3.0 · 长期计划 A1 共享数据）
- 本版只做「共享数据」：预设 / 质感 / 颗粒 / 强度系数统一放在 `shared/lucida-shared.json`，网页、iOS（SharedData.swift）、安卓（SharedData.java）都由 `tools/gen_shared.py` 生成；用户可见功能不变。
- 已验证：网页新旧版 28080 组参数完全一致；安卓 GradeState 与网页 22464 组最大误差 4e-8（在 JVM 上实际跑过）；iOS 生成文件与 json 逐项一致（脚本解析对照），**但 Swift 未编译、未运行**。
- 进度见 PLAN.md。

# 实现状态（如实说明）

本工程是在 Linux 沙盒里写的：**没有 Swift 编译器、没有 Xcode、没有 iPhone**，所以 Swift 代码没有编译过，也没有在真机上跑过。
网页这一侧（原生接口的调用、保存位置开关、格式选择、下载拦截、导入、验证码动画）已用模拟的原生接口在浏览器里测过。
第一次在 GitHub Actions 上编译，如果有语法 / API 报错，把 Actions 日志发给我，我按报错修。

| 需求 | 状态 |
|---|---|
| **原生双摄（11.1.5 新增）** | DualCamEngine（AVCaptureMultiCamSession 前后摄像头同时工作，CoreImage 合成画中画/上下分屏，拍照 JPEG；录像 AVAssetWriter H.264+AAC 带声音）+ DualCamViewController（全屏竖屏：关闭 / 布局 / 互换主画面 / 前置镜像 / 手电 / 照片·视频切换 / 快门 / 小窗拖动·点按放大），入口：设置里「原生双摄」+「自动使用原生双摄」开关；拍完存系统相册并导入澄影相册。**Swift 只做了语法检查（tree-sitter），从未在 Xcode 编译、从未在真机运行；不支持的机型（XS/XR 以前）会回退到网页「连拍合成」** |
| 登录验证码键盘（11.1.5） | KeyboardPin：钉住 WKWebView 的 contentInset/contentOffset，网页只把输入行上移。**未在真机验证** |
| App 名「澄影」、App 图标 | 11.1.3：图标换成你给的 C21530F6 原图，等比缩放进 1024 方形、**不裁切**（原图四角本来是黑底，所以四角是黑的，系统会再套圆角）；启动图用 DC8119F7 的镜头图标 |
| 实况接系统接口 + 保存位置开关（澄影相册 / 系统相册） | 代码已写（LivePhotoSaver，内容标识符 + still-image-time + 配对视频）；开关在 更多设置 → 苹果原生。11.1.3：实况时长可选 3 / 5 / 6 / 8 秒，静帧时间点由网页传来（`still`，对准按下快门那一刻）。**未在真机验证** |
| 调色盘视频 60 帧 | 网页本来就按 60 帧请求；实际帧率取决于相机输出，**未在真机验证** |
| 液态玻璃接原生 | **已按你要求整体删除**（11.1.2）：原生壳里不再有任何玻璃叠层，只保留网页自带的那套玻璃 |
| 点按对焦 / 长按锁定 AE·AF（录像也可用） | 11.1.3 新增 NativeFocus：iPhone 的网页取景没有对焦接口，改由原生直接设置摄像头对焦点 / 曝光点。**网页取景是系统另一个进程在用这颗摄像头，原生设置能否生效取决于系统，未在真机验证**；失败会回到「系统自动对焦」提示 |
| 全部摄像头预热 / 开机检测摄像头 / 一次开多颗 | 已做：DeviceProbe 开机检测并注入网页，网页检测完 1.8 秒内开始预热三颗镜头（沿用「边变焦边切镜头」的待命池）。网页里同时开多颗镜头在 WKWebView 里能否稳定，**未在真机验证** |
| 非线性变焦 | 网页变焦本来就是按对数曲线；原生相机拍摄时倍率换算成虚拟多摄设备倍率 |
| 格式 JPEG / HEIF / ProRAW | 已做：规格面板里的「照片格式」。HEIF = 存进系统相册时转 HEIC；ProRAW = 拍照时释放网页取景、原生相机拍 DNG + JPEG 同时写入系统相册，约 1～2 秒，**未在真机验证** |
| 屏幕比例自动选最合适取景比例 | 已做：第一次打开按屏幕选 16:9 或 4:3，之后听用户的 |
| 连续曲率圆角 | **已按你要求去掉**，回到原来的圆角 |


## 11.1.6 补丁（本次）
| 项目 | 状态 |
|---|---|
| 原生双摄变焦转盘 | 新文件 `ZoomDialView.swift`：横向对数刻度，拖动 + 惯性，点读数回 1×，点刻度跳转；控制「当前主画面」那颗摄像头的 `videoZoomFactor`，两颗各记各的倍数。范围取当前规格的 `videoMaxZoomFactor`（上限 10×）。双摄用的是广角镜头，没有 0.5× 超广角。**只做了语法检查，未在 Xcode 编译、未真机验证** |
| 「片门全开」开关 | 双摄界面顶部第 6 个按钮（亮黄 = 开），记住上次选择。开启后前后摄都改用 4:3 的最大「系统允许同时工作」规格（`isMultiCamSupported`），取景区变 3:4，拍照 / 录像成品也是 3:4（长边最大 2880）。**多摄模式下系统不开放传感器的真正全幅（如 4032×3024），实际规格以界面提示为准；这台设备不支持时自动退回原设置并提示。未真机验证** |
| 4K 24 帧录像闪退 | 网页层：4K 画布录制限制 2560 长边、录像体积到内存安全上限自动停止保存。`WebViewController` 已有「网页进程被回收自动重载」。**无法在这里复现，只能降低风险，未真机验证**；真 4K 请走「直录」（不放大、前置不镜像、不调色） |

## 11.1.7 / 11.1.8
| 项目 | 状态 |
|---|---|
| 屏幕比例 / 界面缩小（Pro Max）| 网页加了自动适配脚本（检测屏幕比例，页面比屏幕宽时锁定视口，取景只做等比铺满）；`WebViewController` 锁死缩放、网页始终铺满窗口。**这里没有 Pro Max 真机，只在浏览器模拟 390×844 / 430×932 / 440×956 验证过布局，未真机验证；如果仍有问题，请把 更多设置 里的页面尺寸或截图发我** |

## 11.1.8 双摄全面改为原生（UIKit / AVFoundation / CoreImage，无 HTML）
- DualCamEngine：AVCaptureMultiCamSession；分辨率 720p/1080p/4K × 帧率 24/30/60，前后摄各自挑「可同时工作」的规格，带宽不够自动降档并提示；片门全开前后摄都优先 4:3；超广角/广角镜头；合成预览（AVSampleBufferDisplayLayer，所见即所得）；调色、小窗圆角/边框（无/白/黑）；JPEG/HEIF；录像 H.264/HEVC+AAC；实况（1.5s 环形缓存 + 边拍边写）。
- DualZoomControl：主页面变焦胶囊 + 弧形转盘的逐行移植（弹簧/磁吸/橡皮筋/惯性）。
- DualCamViewController：顶部 返回+规格胶囊面板 / 实况 / 调色盘 / 设置；底部纯黑平面栏；DualPalettePanel；DualSettingsViewController；DualAlbumViewController；液态玻璃（iOS 26 UIGlassEffect，低版本毛玻璃）。
- 未验证：本环境无 Swift 编译器，只做了语法检查，需 Xcode 编译并真机测试。
- 限制：多摄会话不提供 ProRAW / 真长焦；实况无声音。

## 11.2.0 双摄调色板 / 液态玻璃 / 手势 / 相册（全部原生）
- 调色板（DualPalettePanel）：悬浮深色圆角面板；返回 / 二维色盘（圆点）+ 强度滑条 / 复位 / 快门；底部「调色板 / 质感 / 颗粒」页签；页签上方「后置 / 前置 / 同时」选择（`DualSettings.gradeTarget`，前后各一套 `gradeBack` / `gradeFront`，引擎合成时各用各的）；左右滑动换预设，预设名胶囊 + 页码圆点；每条滑条后面有复位按钮。
- 调色板图标 `PaletteGlyph`：圆角方块点阵，开启黄 / 关闭白，中心点跟着色盘位置。
- 液态玻璃（DualGlass.swift）：`UIGlassEffect`（iOS 26，`#if compiler(>=6.2)` + `#available`），低版本毛玻璃；规格面板、调色底板、设置里的分段 / 开关 / 滑条、所有圆按钮；变焦胶囊两端裁切 / 鼓出修复。
- 实况计时：取景框左上角（`liveTimerLabel`），设置里「实况计时显示」开关。
- 手势（DualCamViewController）：双击小窗放大 / 缩小；单击小窗互换；单击主画面对焦测光；对焦后上下拖动调曝光（`setExposureTargetBias`）；长按锁定 AE/AF（`DualFocusIndicator.swift`）。前后摄都支持。
- 相册：最新在左上；2 列 × 3 行 = 每屏 6 张；双指捏合 / 张开缩放。
- 4K60 前置掉帧：`systemPressureState` + `thermalState` 触发降到 30 帧；60 帧下取景渲染减半。
- **未验证**：本环境无 Swift 编译器，只做了语法检查 + 符号交叉检查，需 Xcode 编译并真机测试；前置摄像头对焦点坐标映射为推算、未真机验证；4K60 前置掉帧的根因在这里无法复现，只做了降风险处理；液态玻璃仅 iOS 26+。

## 11.2.1（11 月 16 日改进）
- **编译错误修复**：`GlassSegmented.selected` 与 `UIControl.selected` 撞名 → `selectedIndex`（你修过的那处，已并入）。
- 版本号三处同步：`project.yml` MARKETING_VERSION / CURRENT_PROJECT_VERSION（30，大于上一版）、`DeviceProbe.swift`、README；脚本 `tools/bump_version.py` 一次改完并校验。
- 开关（GlassSwitch）：50×28 紧凑尺寸；按住 / 点击 / 拖动时旋钮变液态玻璃水滴，松手变纯白旋钮（未开玻璃时只有白旋钮）。
- 调色盘：颜色部分照抄主页面着色器（`GradeMath` → 33³ 的 3D 查找表 → `CIColorCube`）；质感 = 标准 / 柔肤 / 光晕 / 胶片 + 强度（各自记忆），颗粒 = 强度；锐化 / 柔化 / 光晕 / 颗粒是 CoreImage 空间滤镜，**与主页面着色器是近似、不是逐像素一致**。前后摄各一套并保存到 UserDefaults。
- 预设顺序：更多设置 → 调色盘预设顺序（`PresetOrder`，拖动排序，标准固定第一，可恢复默认），左右滑动按此顺序。
- 满帧画面运行录制：`DualSettings.fullRate` → `DualCamEngine.fullRate`（开 = 不降帧、取景不隔帧）。
- 提示条：`DualToastView`，统一放取景框左上角（与实况计时同一个 UIStackView），玻璃 / 深色面板随液态玻璃开关。
- 液态玻璃：顶部规格胶囊 `DualPillButton`（之前玻璃层没设 frame，所以看不见）；规格面板展开 / 收回的 Q 弹动画（仅玻璃开启时）。
- **未经编译**：本次新增 / 改动的 Swift 没有过 Xcode；最没把握的 3 处：`DualSettings.swift`（GradeState.apply 的 CoreImage 链）、`DualGlass.swift`（GlassSwitch 手势与动画）、`DualCamViewController.swift`（setSpecPanel / hintStack）。
