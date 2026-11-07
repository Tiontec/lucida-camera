# 澄影 · iOS 原生 App 工程（11.1.0）

网页（`Lucida/Resources/web/index.html`，= 手机版 11.1.0 + 原生接口）装进 WKWebView 外壳里，界面和调色算法都还是澄影自己的；
原生这一层负责网页做不到的事：写入系统相册、真正的实况照片、HEIF / ProRAW 原生拍摄、摄像头检测、原生液态玻璃叠层。

## 一、用 GitHub 自动打包 IPA（不需要 Mac）

1. 在 GitHub 新建一个仓库，把本文件夹里的**全部内容**（包括隐藏的 `.github` 文件夹）上传到仓库根目录。
2. 打开仓库 → **Actions** → 左边选「澄影 iOS 自动打包」→ **Run workflow**（上传后也会自动运行）。
3. 跑完（约 5～10 分钟）在这次运行页面最下面的 **Artifacts** 下载 `Lucida-unsigned-ipa`，解压得到 `Lucida-unsigned.ipa`。
4. 这是**未签名**的 IPA：用 AltStore / Sideloadly / TrollStore / 爱思助手 等工具用你自己的 Apple ID 或证书签名安装即可。

要原生液态玻璃：运行器默认是 `macos-26`（Xcode 26）。如果 GitHub 上没有这个运行器，手动运行时把 `runner` 填成 `macos-15`，
这时照样能打包，只是编译里不含 iOS 26 的 `UIGlassEffect`，原生玻璃开关会自动不出现，网页自带的玻璃照常用。

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
  NativeBridge.swift            网页 ↔ 原生消息（分块上传、保存、导入、原生拍摄、触感、玻璃）
  PhotoSaver.swift              写入系统相册、JPEG→HEIC
  LivePhotoSaver.swift          实况照片：内容标识符 + still-image-time 元数据 + PHAssetCreationRequest
  LivePicker.swift              系统选择器导入照片 / 视频 / 实况（连配对视频）
  NativeCamera.swift            AVCapturePhotoOutput：JPEG / HEIF / Apple ProRAW，虚拟多摄变焦
  DeviceProbe.swift             开机检测摄像头、屏幕比例
  GlassOverlay.swift            UIGlassEffect 原生液态玻璃叠层（iOS 26 + Xcode 26）
Lucida/Resources/               图标（已去黑边，1024 满版）、启动图、网页
```
