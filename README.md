# 澄影重构版 · iOS（1.0.0）

没有网页：全部是原生界面。从澄影 11.6.0 的原生双摄系统提取而来，之后在它上面一步步加功能、加设置。

- Bundle ID：`com.lucida.rebuild.ios`
- 版本号规则：加设置 +0.0.1 · 加功能 +0.1.0 · 大更新 +1.0.0（满 10 进一，0.9.0 + 0.1.0 → 1.0.0）
- 打包：把本文件夹全部内容（含 `.github`）传到 GitHub，Actions → 「澄影重构版 iOS 自动打包」→ Run workflow，下载 `LucidaRebuild-unsigned-ipa`，用 AltStore / Sideloadly 等自行签名。
- 本机：`brew install xcodegen && xcodegen generate && open LucidaRebuild.xcodeproj`

路线见 `PLAN.md`，当前进度见 `STATUS.md`。
