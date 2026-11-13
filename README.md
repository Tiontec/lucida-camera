# 澄影 · iOS 原生 App 工程（11.1.5）

网页（`Lucida/Resources/web/index.html`，= 手机版 11.1.5 + 原生接口）装进 WKWebView 外壳里，界面和调色算法都还是澄影自己的；
原生这一层负责网页做不到的事：写入系统相册、真正的实况照片、HEIF / ProRAW 原生拍摄、摄像头检测、原生点按对焦。液态玻璃只用网页自带的那套（11.1.2 起原生玻璃叠层已整体去掉）。

## 一、用 GitHub 自动打包 IPA（不需要 Mac）

1. 在 GitHub 新建一个仓库，把本文件夹里的**全部内容**（包括隐藏的 `.github` 文件夹）上传到仓库根目录。
2. 打开仓库 → **Actions** → 左边选「澄影 iOS 自动打包」→ **Run workflow**（上传后也会自动运行）。
3. 跑完（约 5～10 分钟）在这次运行页面最下面的 **Artifacts** 下载 `Lucida-unsigned-ipa`，解压得到 `Lucida-unsigned.ipa`。
4. 这是**未签名**的 IPA：用 AltStore / Sideloadly / TrollStore / 爱思助手 等工具用你自己的 Apple ID 或证书签名安装即可。

运行器默认是 `macos-15`（不再需要 iOS 26 SDK）；想换别的运行器，手动运行时在 `runner` 里填名字即可。

### 想直接出已签名的 IPA（可选）
在仓库 Settings → Secrets and variables → Actions 里添加：
`IOS_CERT_P12_BASE64`（.p12 证书 base64）、`IOS_CERT_PASSWORD`、`IOS_PROFILE_BASE64`（.mobileprovision base64）；
可选变量 `IOS_EXPORT_METHOD`（`ad-hoc` / `development` / `app-store`，默认 ad-hoc）。填了才会运行 `signed-ipa` 任务，产物名 `Lucida-signed-ipa`。
描述文件里的 Bundle ID 需要是 `com.lucida.camera`（想换就改 `project.yml` 里的 `PRODUCT_BUNDLE_IDENTIFIER` 和工作流里的同名项）。

## 二、本机 Xcode 打开
```
brew install xcodegen
xcodegen generate
open Lucida.xcodeproj
```

## 三、更新网页
把新的手机版（原生版）HTML 覆盖 `Lucida/Resources/web/index.html` 再提交即可，不用改 Swift。

## 四、目录
```
project.yml                     XcodeGen 工程描述（Info.plist 权限说明、图标、版本都在这里）
.github/workflows/ios.yml       自动打包工作流
Lucida/Sources/
  AppDelegate.swift             入口
  WebViewController.swift       WKWebView 外壳（相机 / 麦克风 / 陀螺仪放行、弹窗、外链）
  SchemeHandler.swift           lucida:// 协议：网页文件 + 原生导出的临时文件（支持 Range）
  NativeBridge.swift            网页 ↔ 原生消息（分块上传、保存、导入、原生拍摄、原生对焦、触感）
  PhotoSaver.swift              写入系统相册、JPEG→HEIC
  LivePhotoSaver.swift          实况照片：内容标识符 + still-image-time 元数据 + PHAssetCreationRequest
  LivePicker.swift              系统选择器导入照片 / 视频 / 实况（连配对视频）
  NativeCamera.swift            AVCapturePhotoOutput：JPEG / HEIF / Apple ProRAW，虚拟多摄变焦
  DeviceProbe.swift             开机检测摄像头、屏幕比例
  NativeFocus.swift             点按对焦 / 长按锁定 AE·AF（原生设置摄像头对焦点）
Lucida/Resources/               图标（已去黑边，1024 满版）、启动图、网页
```
---

## 下载安装包

所有历史版本都在 **[Releases](https://github.com/Tiontec/lucida-camera/releases)**：

| 版本 | 主要内容 |
|---|---|
| v11.1.5 | 原生双摄引擎、键盘避让、对焦更新 |
| v11.1.3 | 新增原生对焦模块，移除原生玻璃叠层 |
| v11.1.1 | 液态玻璃可见性修复 |
| v11.1.0 | 首个版本 |

每个版本包含两个文件：

- `Lucida-unsigned-<版本>.ipa` —— 未签名安装包，用 Sideloadly / AltStore / TrollStore 自签后安装
- `Lucida-<版本>-web.html` —— 该版本内置的网页源文件，浏览器可直接打开

## 协议与作者

本项目由 **雾峥奕** 创作，以《澄影非商业开源许可协议 1.0》开源。

| | |
|---|---|
| ✅ 允许 | 学习、研究、修改、非商业分享、自行打包安装 |
| ✅ 必须 | 保留作者署名；衍生作品沿用同一协议；分发时附带协议全文 |
| ❌ 禁止 | **任何商业用途**、**倒卖 / 转售 / 付费分发**、冒充原创、违法用途 |

完整条款见 [LICENSE](LICENSE)。

> 简单说：随便改、随便玩、随便传，但**不能拿去卖钱**，也不能说是你写的。
