# 开发说明（给下一个接手的人 / 下一次对话的我）

A 已经不在了，从 2.2.0 起所有开发、合并、打包都由同一个人负责（B）。这份文件把不能丢的约定写下来。

## 1. 打包规矩（上次就是栽在这里）
- 压缩包里的文件必须**直接放在压缩包根目录**，不要外面再套一层文件夹。根目录要有：
  - iOS：`.github/`、`.gitignore`、`project.yml`、`Rebuild/`、`README.md`、`STATUS.md`、`PLAN.md`
  - 安卓：`.github/`、`.gitignore`、`build.gradle`、`settings.gradle`、`gradle.properties`、`app/`、`README.md`、`STATUS.md`、`PLAN.md`
- 原因：GitHub Actions 的 `.github/workflows` 和 `xcodegen generate` / `gradle` 都在仓库根目录找东西；多套一层就什么都不会跑。
- 压缩包名：安卓 `lucida-rebuild-android-project`，iOS `LucidaRebuild-ios`。
- 打包前：每个文件看大小、不能有 0 字节；清掉 `__pycache__`、`.DS_Store`；解压回来再跑一遍检查。

## 2. 版本号（三处要一致）
- iOS：`ios/project.yml` 的 `MARKETING_VERSION` 和 `CURRENT_PROJECT_VERSION`，加上 `AppSupport.swift` 里的 `AppInfo.version` / `AppInfo.build`。
- 安卓：`app/build.gradle` 的 `versionCode`（2.2.0 = 22000）和 `versionName`。
- 规则：加设置 +0.0.1 · 加功能 +0.1.0 · 大更新 +1.0.0。
- 当前：**2.2.0**（iOS build 13，安卓 versionCode 22000）。

## 3. 没有编译器时怎么检查（`tools/` 里）
| 脚本 | 查什么 |
|---|---|
| `swift_balance.py 文件…` | 括号 / 引号配对 |
| `swift_lint.py Rebuild/Sources` | 跨文件重复类型、**同一类型（含所有 extension）里的重名成员**、`#selector` 指向不存在的方法 |
| `swift_refs.py Rebuild/Sources` | `类型.成员`、`st.成员` 引用的成员是否真的存在 |
| `java_refs.py app/src/main/java` | 括号、`类名.成员`、`DualPrefs` 字段、`new 类(..).成员` |
这些检查器都用「故意塞错误」验证过确实能抓到。**每次交付前三项都要是 0 个问题。**
- 安卓整个工程没法在这里编译（没有 android.jar）；只能对「不依赖 SDK 的文件」用桩编译，其余靠 `java_refs.py` 和人工核对。

## 4. 编译错误教训
- UIKit 类里**不要用 `editing`、`selected`、`enabled`、`highlighted`、`frame`、`bounds`、`text`…这类名字做自己的属性**（`UIViewController.isEditing`/`setEditing` 会冲突）。面板里的编辑状态现在叫 `editingPanel`。
- 同一个类型的属性**只能定义一次**：`DualSettings` 在 `DualSettings.swift` 里定义了的属性，`SettingsStore.swift` 的 `extension DualSettings` 里就不能再写（`countVibrate` 就是这样重复的）。写之前先 `grep "var 名字" *.swift`。
- 生成文件（`SettingsData.*`、`ContentData.*`）不要手改，改 `tools/gen_settings.py` / `tools/content_src/*.json`，然后运行：
  `python3 tools/gen_settings.py .` 和 `python3 tools/gen_content.py .`（在 iOS 或安卓工程根目录里运行就只写那一边）。
- shell 里不要用花括号展开（`{a,b}`）和 `<(...)`，这里的 sh 不支持，会静默失败。
- 不要用 `cut -c`、`head -c` 截中文输出，会截到半个字符导致输出丢失。

## 5. 安卓相机的约定（来自 vivo 闪退分析）
- `CaptureRequest.Builder.set(key, null)` **在定制 ROM 上会 NPE，一律不写 null**：要「清掉」某项就是不写它；`pushReq()` 每次新建构建器。
- 每一项都用 `safeSet()` 写，单项失败只跳过。
- 完整请求建不出来时，用最简请求（只留目标 + 连续对焦）兜底并提示用户。
- 合成摄像头（zoomMin < 0.98）不主动切镜头，交给系统。

## 6. 用户已经做的决定（不要再问）
- iOS 液态玻璃：按压的光团 + 拉伸现在对所有玻璃样式启用；系统 `isInteractive` 关掉（背后的玻璃视图不接收触摸，系统的触发不了）。
- **下一版要做**：
  1. 安卓液态玻璃：用 Compose + AndroidLiquidGlass（Kyant0）重写，用户已同意引入新依赖；
  2. 实况录入慢：用户会发以前的工程，对着旧工程改（快速版本）；
  3. 设置页 120Hz 流畅度；
  4. 澄影相册读取系统相册并支持删除；
  5. 安卓变焦滑条统一到「变焦倍率扩充」设置的倍数（设置选几倍就要有几倍，不够的用数码变焦补足）。

## 7. 已知没验证的地方
- iOS 没编译过；安卓只对部分文件用桩编译过。**每次交付都要提醒用户先编译一次再测。**
- 灵动岛标准宽度 `dualIslandStandardWidth = 126` 是估计值，需要实机校准。
