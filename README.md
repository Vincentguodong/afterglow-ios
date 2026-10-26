# 余光 AFTERGLOW

一个使用 SwiftUI、AVFoundation 和 Core Image 的原生 iPhone 胶片摄影实验项目：胶片色彩、数字暗房和触感转盘。照片在设备上处理；没有账号系统、广告、分析 SDK 或照片上传服务。

**状态：实验性源码发布。**当前版本为 1.1.0 / build 2，最低支持 iOS 17。尚未完成 Xcode 编译、XCTest 执行、签名或真机验证；仓库不提供已验证的 `.app`、IPA 或 TestFlight 下载。源码检查不能替代真机测试。

## 功能

- 六款胶片配方：日落、青野、霓虹、海岸、玫瑰、银盐。
- 曝光、颗粒、色温转盘；触感反馈与 VoiceOver 调节。
- 前后摄切换、实时滤镜、构图网格、1×/2× 数码变焦。
- 暗房褪色、暗角、漏光、原片对比和配方重置。
- PhotosPicker 导入，自动保存草稿与配方，本机胶卷持久化。
- 原片与冲洗 JPEG 分开保留，可从原片再次编辑；支持相册导出和系统分享。
- 以 iPhone 17 Pro Max 竖屏为主要布局目标，采用安全区与自适应转盘布局。

## 安装到自己的 iPhone

需要 Mac、支持手机当前 iOS 版本的完整 Xcode、普通 Apple Account 和 iPhone。

1. 下载或克隆仓库，打开 `Afterglow.xcodeproj`；也可以双击 `Start-Afterglow.command`，检查环境并打开工程。
2. 在 Xcode → Settings → Apple Accounts（部分版本叫 Accounts）登录自己的账号。
3. 选择 Afterglow target → Signing & Capabilities，启用自动签名，选择自己的 **Personal Team**。
4. 把示例 Bundle Identifier 改为自己的唯一标识；后续更新保持同一个账号、Team 和标识。
5. 连接并解锁 iPhone，完成信任、配对与 Developer Mode 设置；在 Xcode 选择真实手机，点击 **▶ Run**。

免费 Personal Team 配置描述文件在签发 7 天后过期，届时需要重新构建安装。更新时不要先删除 App，以免丢失本机胶卷。详细步骤与排错见 [免费安装说明](Docs/FREE_INSTALL.md)。

## 检查与测试

```bash
# 配置、资源和工程引用检查；安装 tree-sitter 与 tree-sitter-swift 后可额外检查 Swift 语法
python3 Scripts/check_source.py

# 公开前检查敏感资料与不应提交的文件
python3 Scripts/check_public_source.py

# 在 Mac 上检查 Xcode 与 iOS SDK
bash Scripts/install-free.sh --check

# 在 Mac 的 Xcode / iOS 模拟器环境执行 XCTest
bash Scripts/test.sh
```

`Scripts/test.sh` 默认选择 iPhone 17 Pro Max 模拟器。若未安装该模拟器，可通过 `SIMULATOR_DESTINATION` 设置已有的 iOS 模拟器。

XCTest 源码覆盖配方、图像处理、原片保存、草稿恢复和删除行为等；**尚未执行这些测试**。测试范围和待验证项目见 [验证说明](Docs/VALIDATION.md)。

## 限制与隐私

- 输出最长边 4096 像素的 sRGB JPEG。相机“原片”是未添加胶片效果的裁切 JPEG，不是传感器 RAW。
- 曝光和色温转盘控制图像处理，不是硬件快门或 ISO。
- 不含视频、RAW、Live Photos、Camera Control 或独立超广角 / 长焦镜头选择。
- 导入的原片按原始字节保存；**分享原片会保留文件可能包含的 EXIF、GPS 等元数据**。
- 本地照片可能随设备备份保存，具体由系统与用户设置决定；系统分享目的地由用户选择。

详见 [隐私说明](PRIVACY.md)。首次运行应使用非敏感样片验证相机方向、照片保存、权限处理与恢复行为。

## 资源与许可

应用源码与自绘图标采用 [MIT License](LICENSE)。内置示例照片由 AI 生成；资源来源及范围见 [资源说明](Docs/ASSETS.md)。原生 App 使用系统字体与 SF Symbols，不打包第三方字体或运行时依赖。

[可选 TestFlight 发布流程](Docs/TESTFLIGHT.md) 面向自行维护的发布版本，需要发布者自己的开发团队、签名和审核配置。
