# 澄影重构版 —— 交接工作流（给接手的 AI）

> 这份文档是交接，不是分工。接手的人接的是"整个项目的继续推进"：目标、现状、规则、流程、踩过的坑、下一步。
> 读完这份文件再动手。当前版本：**2.7.1**（以 `project.yml` 和 `AppSupport.swift` 为准，两处必须一致）。

---

## 0. 接手第一步（必做）
1. 读 `PROGRESS.md`（每个版本做了什么、还差什么）、`DEV_NOTES.md`（打包规矩和检查方法）、本文件。
2. 解压两个工程包到工作目录（见第 2 节）。**不要**直接在对话里凭记忆写代码。
3. 跑一遍检查，确认起点是干净的（见第 5 节）。起点不干净就先修起点，不要叠新功能。
4. 和用户确认本轮要做的版本号和范围，再动手。

---

## 1. 项目与用户
- **项目**：澄影（Lucida）相机 App 的"重构版"，有两个原生工程：
  - iOS：Swift，XcodeGen（`project.yml`），GitHub Actions 构建。
  - 安卓：Java，Gradle（`app/`），GitHub Actions 构建。
- **用户**：非专业开发者，中文交流。他会在真机上测试，然后把结果或日志发回来。
- **用户的明确偏好**（违反会被投诉，务必遵守）：
  - 用中文，说话直白，不堆术语。每一步做了什么、为什么，要写出来说清楚。
  - 说"能做/不能做"要诚实，**做不到的不要假装做了**。没编译、没真机验证的，要写明。
  - 每次发包：压缩包名必须带版本号，例如 `LucidaRebuild-ios-2.6.0.zip`、`lucida-rebuild-android-project-2.6.0.zip`。安卓和苹果都要带。
  - 交付时要有：`CHANGES.md`（本版改了什么、没改什么、测试清单，苹果安卓分开写）。
  - 用户说"先别动手"的，就只分析不改代码。
  - 用户说"给其他模型做"的（专业模式等），不要自己做，等用户要求再写说明书。
- **颜色**：强调色 = 黄色（原中版，`#FFD60A`）；大肥鱼皮肤 = 蓝色（`#7FB6FF`）；**克劳德主题色 = 橙色 `#FF8A3D`**（用于澄影相册的标记框）。

---

## 2. 文件在哪里（交接时的文件位置）
- 当前输出目录：`/mnt/user-data/outputs/`
  - `LucidaRebuild-ios-2.5.0.zip`、`lucida-rebuild-android-project-2.5.0.zip`（当前版本，两个工程完整）
  - 历史版本 2.2.0 ~ 2.4.0 的同名包（只作参考）
  - `liquid-glass-skill-2.3.0.zip`（液态玻璃技能包，已修复）
  - `B_delivery_*.zip`（早期的分段交付，已被合并，只作参考）
- 参考资料（旧版 11.6.x 网页与素材）：在 `lucida-claudeB-package.zip` 里的 `reference/` 目录。
  - 旧 web 界面：`old_ios_11.6.x_working_tree.zip` 里的 `Lucida/Resources/web/index.html`（约 2MB，里面有内嵌的皮肤图片 base64）。
  - 参考文案：`reference/content/` 下的 `settings.json`、`updates.json`、`about.json`、`donate.json`。
- 工作目录的解压方法：
  ```
  mkdir -p work && cd work
  unzip -q /mnt/user-data/outputs/LucidaRebuild-ios-2.5.0.zip -d ios
  unzip -q /mnt/user-data/outputs/lucida-rebuild-android-project-2.5.0.zip -d android
  ```
  **注意**：压缩包的根目录就是工程根（`.github/`、`project.yml`、`app/`…）。不要再套一层文件夹。

---

## 3. 代码地图（改哪里找哪里）

### iOS（`ios/Rebuild/Sources/`）
| 功能 | 文件 | 备注 |
|---|---|---|
| 相机主界面（快门、变焦、皮肤、设置回调） | `DualCamViewController.swift` | `applySkin()` 在这里；设置变更回调里调用 `applySkin()` |
| 相机引擎（取景合成、拍照、实况抓帧、数码变焦） | `DualCamEngine.swift` | `digitalCrop()` 软件变焦；`ciPhoto` 是拍照专用的图像上下文；`captureLive` / `finishJob` 是实况 |
| 实况编码器（持续 H.264 + 样本库） | `LiveEncoder.swift` | 看门狗在 `encode()`；`finish(until:timeout:)`；`writeMOV` |
| 实况保存到相册 | `LivePhotoSaver.swift`、`PhotoSaver.swift` | |
| 玻璃效果（毛玻璃、液态按压光团） | `DualGlass.swift` | `dualYellow` 是计算属性，随皮肤变；`DualBackdrop.apply`；`LiquidTouchFX` |
| 变焦条（胶囊 + 转盘） | `DualZoomControl.swift` | `STOPS` 档位；`buildTicks()` 补主刻度 |
| 相册 | `DualAlbumViewController.swift`、`DualLibrary.swift` | `DualLibrary.fetch()` 读整个系统相册；`DualLibrary.ids` 是澄影拍的；`AlbumCell.set(mine:)` 橙框 |
| 设置 | `SettingsRegistry.swift`、`SettingsData.swift`（**生成**）、`SettingsStore.swift`、`SettingsPages.swift`、`SettingsPagesM3.swift`、`SettingsRows.swift` | 注册表由 `tools/gen_settings.py` 生成 |
| 面板样式、颜色 | `PanelTheme.swift`（`PanelPalette`） | |
| 灵动岛样式 | `DualIslandStyle.swift` | 只有样式和宽度，相机里排版没接 |
| 文案（更新记录、关于、赞赏） | `ContentData.swift`（**生成**） | 由 `tools/gen_content.py` 从 `tools/content_src/*.json` 生成 |
| 版本号 | `AppSupport.swift`（`AppInfo`）、`project.yml` | 两处都要改 |
| 日志 | `AppLog.swift` | 设置 → 故障报错日志 |

### 安卓（`app/src/main/java/com/lucida/camera/`）
| 功能 | 文件 | 备注 |
|---|---|---|
| 相机主界面、Camera2 预览请求、变焦下发 | `DualCameraActivity.java` | `fillReq()`、`pushReq()`、`reqZoom()`、`syncDial()`（变焦条范围）；`applySkin` 在 onCreate 后调用 |
| 液态玻璃（新，AGSL） | `GlassSdf.java` | 调参常量在文件顶部；`supported()` = Android 13+ |
| 固态玻璃（旧的液态，mesh 折射）、玻璃入口 | `GlassRefract.java` | `draw()` 里选择分支：liquid2 + 13+ 用 GlassSdf，否则 mesh |
| 玻璃样式变量、强调色、皮肤、橙框 | `DualUi.java` | `YELLOW` 是可变静态字段；`applySkin()`；`mineFrame()` |
| 相册数据、系统相册查询、权限 | `DualLibrary.java`（`load`、`appendSystem`、`readPerms`、`canReadSystem`、`delete`）；`DualAlbum.java`（界面） | `Entry.system` 标记系统相册项 |
| 变焦条 | `ZoomBar.java` | `setRange(lo, hi, …)`；`buildTicks()` 补主刻度 |
| 设置 | `SettingsRegistry.java`、`SettingsData.java`（**生成**）、`SettingsStore.java`、`SettingsPageView.java`、`SettingsUi.java`、`SettingsPagesM3.java`、`DualSettingsView.java` | `DualSettingsView.changed()` 刷新皮肤；`onAttachedToWindow` 提高刷新率 |
| 面板样式颜色 | `PanelTheme.java` | |
| 文案 | `ContentData.java`（**生成**） | |
| 清单权限 | `app/src/main/AndroidManifest.xml` | READ_MEDIA_* / READ_EXTERNAL_STORAGE |

### 资源
- iOS：`Rebuild/Resources/Assets.xcassets/`（AppIcon、LaunchIcon、LaunchBG、SkinMasc、AboutLogo、AboutDev、DonateQR 等）
- 安卓：`app/src/main/res/`（`mipmap-*/ic_launcher.png`、`drawable-nodpi/launch_icon.png`、`skinmasc.png`、`about_*.jpg`、`donate_qr.jpg`）

### 工具（`tools/`，两个工程包里都有一份）
- `gen_settings.py <根目录>`：生成两端的 `SettingsData`。**改设置只改这个文件**。
- `gen_content.py <根目录>`：生成两端的 `ContentData`。改文案改 `tools/content_src/*.json`。
- `swift_lint.py Rebuild/Sources`：跨文件重复类型、同类型重名成员、selector 是否存在。
- `swift_refs.py Rebuild/Sources`：`类型.成员` 引用是否存在。
- `java_refs.py app/src/main/java`：Java 的括号和引用检查。
- `swift_balance.py 文件…`：括号和引号配对。
- `make_icons.py <原图> <根目录>`：图标生成（补黑角、圆角、开屏图、安卓 mipmap）。

---

## 4. 当前状态（2.7.1）

> 2.6.0 起的新增：变焦放大取景框（2.6.0）、相册导入（2.7.0）、变焦上限即时生效 + 单摄片门全开（2.7.1）。下面的「已做 / 没做」以 PROGRESS.md 为准，那份是每版都更新的。

### 已经做完、并且用户已经测过或能确认的
- 相册读取系统相册全部照片和视频（iOS 直接可用；安卓需要授权，授权后重新打开相册）。删除会同时删系统相册里的那一份。
- 安卓液态玻璃（AGSL，Android 13+）与固态玻璃（旧的液态）并存；界面风格里有「毛玻璃 / 固态玻璃 / 液态玻璃 / 默认面板」（安卓），iOS 是「毛玻璃 / 液态玻璃（系统原生）/ 默认面板」。iOS 的液态玻璃不要动，用户说"已经很完美"。
- 设置页刷新率：安卓打开设置页时提到最高刷新率；iOS 的 `CADisableMinimumFrameDurationOnPhone` 已开。
- 前置镜像默认开。
- 实况：iOS 拍照合成用独立 `CIContext`；看门狗在有实况在等时不重建；收尾等待 4 秒；回传实际时长；每张实况打日志。**效果未在真机上验证**。
- 变焦扩充到 100×（两端）：硬件到顶后软件裁剪。安卓用 `CONTROL_ZOOM_RATIO` 与 `SCALER_CROP_REGION` 互斥。
- 图标与开屏：新图标，黑角平滑补色，开屏透明背景 + LaunchBG。
- 版本号体系、更新记录分段（新版本默认展开，旧版 11.x 默认折叠）。

### 2.5.0 新做的，**需要真机确认**
- 变焦条 100 刻度（两端）：原因是递推步长跳过了 100，现在补上主刻度。
- iOS 底部胶囊 50/80/100（设置上限够大时显示）。
- 皮肤「大肥鱼」（两端 MVP）：强调色、深蓝背景、吉祥物图。**吉祥物位置是近似的**，与 11.6.x 不一致；顶部按钮、弹窗的蓝色玻璃样式没做。
- 相册澄影橙框（两端）：`#FF8A3D`，2.5pt 细框。

### 没做（按优先级）
1. **相册「导入」按钮**（用户要求）：现在是把本次拍的照片导入澄影相册，方向不对。要改为：从系统相册 / 文件选择照片和视频，**复制到澄影自己的存储**（用户明确要求"放到澄影的储存里"）。两端都要做。iOS 用 PHPicker + UIDocumentPicker；安卓用 Photo Picker / SAF。导入后要出现在澄影相册里。
2. **设置里剩下的灰色项**（用户要求"尽量弄完整"）：
   - 直录模式（录像直接用原始画面）— 建议给 Opus 5.5
   - 倍率镜头切换（三种切换方式）— 建议给 Opus 5.5 / Fable 5.2
   - 界面大小、字体大小、每次打开重置 — 要缩放整个界面，建议给 Opus
   - 变焦放大取景框：设置能选，相机里还没画黄色小框。**接手者可以做**
   - 灵动岛样式：设置能选，相机里的排版还没接（`DualIslandStyle.swift` 已提供宽度）。**接手者可以做**
   - 全景拼接融合：依赖 360 全景（没有）
   - 登录账号：暂不做（用户未要求）
   - 单摄实况「只存实况」（iOS 原生 Live Photo 写入）— 建议给 Opus 5.5
3. **功能面板（11.6.x 对照）**：
   - 滤镜影调：没有。接手者可以做（移植滤镜参数）。
   - 皮肤：大肥鱼本版只是 MVP，细节要补。
   - AI 扩图、空间重构、360 全景、电影模式：建议给 Opus 5.5 / Fable 5.2。
   - **专业模式：已决定交给其他模型。不要自己做。** 用户要求"现在先不用出说明书"，等用户要求再出。
4. **实况真机耗时**：等用户的真机日志（设置 → 故障报错日志，搜「实况」，`第 xxxx：` 开头的行）。

### 已知风险 / 未验证
- **iOS 没有编译过**。只做了括号、重复、引用检查。第一次 Xcode 编译最容易出错的：`SettingsStore.swift` 的 UserDefaults 迁移段、`DualIslandStyle.swift`、`DualAlbumViewController.swift` 的 `mineFrame`（lazy var）、`DualCamViewController.swift` 的 `applySkin()`。
- **安卓 `DualCameraActivity.java` 太大没有整体编译**，只做了括号和引用检查。`DualUi.applySkin`、`DualAlbum` 的 `setForeground`、`ZoomBar` 的刻度补充、`DualLibrary` 的 MediaStore 查询，都没有用桩编译过（桩覆盖不了）。
- **AGSL 液态玻璃源码没有编译器验证**（字符串在 `GlassSdf.java`）。数值模拟（numpy）验证过公式和参数，但真机上的效果要调。
- 相册安卓：授权回调没接回相册，要重新打开相册才生效（有意简化）。
- 实况效果、皮肤位置、变焦 100 刻度，都要真机确认。

---

## 5. 每次交付的标准流程（照做，不要跳步）
1. **起点检查**：解压工程，跑下面的检查，全部 0 个问题才开始改。
2. **改代码**：小步改，每改一处用精确字符串替换（先 `assert count == 1`），替换失败就停下，不要硬写。
3. **改完立刻检查**：
   ```
   python3 tools/swift_balance.py <改过的 swift 文件>
   python3 tools/swift_lint.py ios/Rebuild/Sources
   python3 tools/swift_refs.py ios/Rebuild/Sources
   python3 tools/java_refs.py android/app/src/main/java
   ```
   Java 的括号要单独查（去掉字符串和注释后数 `{}` `()`）。
4. **改了设置** → `python3 tools/gen_settings.py <根目录>`。**改了文案** → 改 `tools/content_src/updates.json`（新版本记录放最前，`"group": "new"`，旧的是 `"old"`），再 `python3 tools/gen_content.py <根目录>`。两个生成器都要跑完，并且可复现（再跑一次结果逐字节一致）。
5. **版本号**（三处要一致）：
   - iOS：`project.yml` 的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`（build +1）；`AppSupport.swift` 的 `AppInfo.version` / `AppInfo.build`。
   - 安卓：`app/build.gradle` 的 `versionName` 和 `versionCode`（规则：2.5.0 → 25000，即 主×10000 + 次×100 + 补丁）。
   - 规则：加设置 +0.0.1；加功能 +0.1.0；大更新 +1.0.0。
6. **文档**：
   - `CHANGES.md`：本版改了什么（分点）、没改什么、检查结果、测试清单（iOS 和安卓分开，每条写"预期"）。
   - `PROGRESS.md`：更新"做了什么 / 还差什么 / 待用户确认"。
   - `STATUS.md`：顶部加本版一段。
   - `DEV_NOTES.md`：只有规矩变了才改。
7. **打包**：
   - 每个工程：`cd <工程目录> && zip -qr ../<名字>-<版本>.zip .`（注意是 `.`，根目录直接是工程内容）。
   - 名字：`LucidaRebuild-ios-<版本>.zip`、`lucida-rebuild-android-project-<版本>.zip`。
   - 解压回来到一个新目录，再跑一遍检查；`find . -type f -size 0` 必须为空；`unzip -Z1 | awk -F/ '{print $1}' | sort -u` 看根目录。
8. **输出**：复制到 `/mnt/user-data/outputs/`，`cmp` 确认一致，用 `present_files` 发给用户。**只写文件名不发文件，用户界面上看不到**（这个已经踩过）。
9. **回复用户**：说清楚：做了什么、哪些没做、哪些没验证、请他测什么。

---

## 6. 踩过的坑（必须记住）
- **压缩包结构**：外面不能多套一层文件夹。这导致过 GitHub 构建失败。
- **shell**：这里的 `sh` 不支持花括号展开 `{a,b}`，也不支持 `<(...)`。`cut -c` / `head -c` 会截断中文字节导致输出乱码或工具报错。**用 Python 处理中文文本**。
- **Python 替换**：先 `assert s.count(old) == 1`，再替换。替换失败就停，不要静默继续。
- **安卓 Camera2**：`CaptureRequest.Builder.set(key, null)` 在 vivo 等定制 ROM 上会 NPE，**一律不写 null**；要清掉某项就是新建请求、不写它。`CONTROL_ZOOM_RATIO` 和 `SCALER_CROP_REGION` 不能混用（设了 ZOOM_RATIO 后裁剪区会被忽略）。
- **iOS Swift 命名**：UIKit 子类里不要用 `editing`、`selected`、`enabled`、`frame`、`text` 等做自己的属性名（编译冲突）。编辑态已改名 `editingPanel`。
- **同一个属性只定义一次**：`DualSettings` 的属性在 `DualSettings.swift` 定义后，`extension DualSettings` 里不能再写（`countVibrate` 曾重复）。写之前 `grep "var 名字"`。
- **生成文件不手改**：`SettingsData.*`、`ContentData.*`。改源头再生成。
- **变焦刻度**：递推步长会跳过整数（100 就被跳过）。补刻度的逻辑已加，改刻度时注意这一点。
- **安卓变焦上限**：`ZoomBar.setRange(lo, hi)` 的 hi 来自 `zoomMax`/`extMax`，这些要跟设置里的变焦扩充（`zoomRange`）走，不要再被硬件上限封顶。
- **iOS 数码变焦**：在 `DualCamEngine` 的 `digitalCrop()`，后置画面经 `compose` 和 `composeMain` 两个入口。新增后置画面的合成入口时，记得也过 `digitalCrop`。
- **液态玻璃（安卓）**：控件背后的裁剪图必须带边距（8dp），否则采样越界会出块状伪影。位移不要超过 6dp。
- **图标**：原图四角是纯黑，要从四角泛洪补色，不要用最近邻复制（会有条纹）。
- **工具 `tools/`**：用 `python3 tools/xxx.py` 跑，路径要对。

---

## 7. 沟通规则（用户反复强调）
- 用户说"你先去做 X"，就只做 X，做完汇报，不要擅自扩大。
- 用户说"记住你做了哪些"，就更新 `PROGRESS.md`。
- 用户要"看一下有没有 / 能不能"，先查代码和文件，给出事实，不要凭印象。
- 说"改完了"要有证据（改了哪个文件、哪一行、检查过什么）；没改就说没改。
- 不要把"没验证"说成"已完成"。
- 每次回复里，主动告诉用户下一步需要他做什么（测哪里、发什么日志）。

---

## 8. 下一版（2.6.0）建议顺序（请先和用户确认范围）
1. 相册导入（两端，复制到澄影存储，导入后显示在澄影相册）。
2. 变焦放大取景框（两端，相机里画黄色小框；按设置的 10/20/25/30/50/80/100 阈值）。
3. 灵动岛排版（iOS，按 `DualIslandStyle` 的宽度画岛；「无」档只显示计时胶囊）。
4. 滤镜影调（移植 11.6.x 的滤镜参数）。
5. 皮肤细节（吉祥物位置按 CSS 精确还原；顶部按钮、弹窗的大肥鱼样式）。
6. 其余设置项与功能面板：建议转交 Opus 5.5 / Fable 5.2（直录、镜头切换、界面缩放、全景、AI 扩图、空间重构、电影模式）；专业模式等用户指示。

**每一项做完都要**：更新 `PROGRESS.md`，写 `CHANGES.md`（测试清单），按第 5 节打包。
