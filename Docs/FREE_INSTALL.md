# 把余光装到自己的 iPhone：免费个人开发安装

你不需要付费 Apple Developer 会员就能用 Xcode 把原生 App 安装到自己的 iPhone。需要一台能运行合适版本 Xcode 的 Mac、自己的 Apple Account，以及与 Mac 连接的 iPhone。安装后会出现真正的“余光”App 图标，使用 SwiftUI、AVFoundation 和系统照片权限，不依赖 Safari。

本仓库提供实验性原生工程和安装助手，尚未完成 Xcode 编译、签名和真机验证，不提供已验证的 IPA。源码 ZIP 需要先在 Xcode 中构建。

## 首次安装：在 Mac 上完成

1. 从 [Apple 的 Xcode 页面](https://developer.apple.com/xcode/)进入 Mac App Store 安装完整 Xcode。选择支持你手机当前 iOS 版本的 Xcode；只安装 Command Line Tools 不够。首次打开时按 Apple 界面提示完成所需许可确认和 iOS 平台组件安装。
2. 完整解压工程，双击 `Start-Afterglow.command`。助手检查 Xcode/iOS SDK 并打开工程。你也可以直接双击 `Afterglow.xcodeproj`，跳过助手。
3. 在 **Xcode → Settings → Apple Accounts（部分版本叫 Accounts）** 登录自己的 Apple Account。密码和验证码只输入 Apple/Xcode 的官方登录界面，不写入脚本、提交记录或 Issue。
4. 选中左侧工程，再选择 **Afterglow target → Signing & Capabilities**。勾选 **Automatically manage signing**；Team 选择带 **Personal Team** 的自己的账号。把 Bundle Identifier 从示例值改为自己的唯一名称，例如 `com.yourname.afterglow`。以后保持这个值不变。
5. 用数据线连接 iPhone 并解锁，按手机提示信任这台 Mac。在 Xcode 的设备界面完成配对。按系统要求，在 iPhone **设置 → 隐私与安全性 → 开发者模式（Developer Mode）** 中开启，重启并完成手机上的确认。若没有这项，先让 Xcode 识别和配对这台 iPhone，再检查。
6. 在 Xcode 顶部运行目的地选择**你的真实 iPhone**，点击 **▶ Run** 或按 **⌘R**。Xcode 构建、生成开发签名并安装。初次构建可能需要下载或准备匹配的设备支持。
7. 在手机打开余光，允许相机权限。拍一张照片，进入暗房调节，再冲洗入卷；导出时按系统提示允许添加到相册。若拒绝相机权限，仍可导入照片或使用示例。

如果 macOS 阻止 `.command` 文件打开，直接在 Xcode 打开 `.xcodeproj` 即可。无需关闭 Gatekeeper，也不要移除系统安全保护。

## 免费方式的范围

Apple 当前规定，Personal Team 的开发配置描述文件在签发 **7 天后过期**；到期后需重新构建并安装。每台设备最多安装 3 个此类 App，最多注册 3 台设备和 10 个 App ID，相关注册也按 Apple 的免费开发期限管理。这个路径适合自己测试和使用；它不会产生 TestFlight 公共下载链接。

更新或续签时，继续使用同一个 Apple Account、Team 和 Bundle Identifier，在 Xcode 再次按 ⌘R。不要为了续签先删除手机里的 App；删除会移除本机胶卷。仍建议把重要作品导出到系统相册。

## 可选：命令行重复构建、安装

首次账号登录、设备信任和签名设置完成后，可使用附带脚本。命令中的值需要替换为你的真实信息；脚本不保存账号密码。

```bash
# 只检查 Xcode 和 iOS SDK，不构建、不安装
bash Scripts/install-free.sh --check

# 查看 Xcode 已识别的真机和模拟器；复制真机项的 id
bash Scripts/install-free.sh --devices

# 构建、校验开发签名、安装到指定 iPhone，并尝试启动
bash Scripts/install-free.sh --install \
  --team YOURTEAMID \
  --bundle com.yourname.afterglow \
  --device YOUR_IPHONE_UDID
```

`--team` 是 10 位 Team ID；`--device` 使用真机 UDID，不用设备显示名称或模拟器 ID。也可通过 `APPLE_TEAM_ID`、`APP_BUNDLE_ID`、`IPHONE_UDID` 三个环境变量提供。若不确定 Team ID，直接用 Xcode 的 Team 下拉选择和 Run 更方便。

构建日志在 `build/PersonalTeam-build.log`，开发 `.app` 在 `build/PersonalTeam/Build/Products/Debug-iphoneos/Afterglow.app`。这不是可供陌生手机自由安装的通用 IPA。脚本只对当前进程选择 Xcode，不修改全局开发工具路径，不自动接受 Apple 条款，不删除照片或旧工程。

## 只有 Windows 或只有 iPhone

这份 SwiftUI 工程需要 macOS / Xcode 来编译和签名。仅有 Windows 或 iPhone 时，需要自行取得可用的 Mac 构建环境，才能完成这些步骤。

## 常见问题

| 现象 | 处理 |
| --- | --- |
| Xcode 显示 “Signing requires a development team” | 在 Afterglow target 的 Signing & Capabilities 选自己的 Personal Team。 |
| Bundle ID 被占用 | 改成自己的唯一标识，并在之后的更新中保持不变。 |
| 手机不出现在目的地列表 | 解锁、信任电脑、检查数据线和配对；查看 Xcode 给出的设备不可用原因。 |
| 手机系统版本比 Xcode 支持的更新 | 更新到支持该 iOS 的 Xcode，并安装所需平台/设备支持。 |
| 到期后 App 不能打开 | 保持同一个 Team 和 Bundle ID，再次 Run 或执行安装脚本。 |
| 免费设备/App 数量达到上限 | 在 Xcode 查看 Apple 返回的具体限制；不要为了测试随意创建新的 Bundle ID。 |

## Apple 官方依据

Apple 的工具界面和限制可能变化，请以当前官方说明为准。

- [Developer account overview：Personal Team 及 7 天限制](https://developer.apple.com/help/account/basics/about-your-developer-account/)
- [Apple Developer Program：免费设备测试与会员分发能力](https://developer.apple.com/programs/)
- [Run an app on a device](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html)
- [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
- [Get to know Developer Mode（Apple WWDC）](https://developer.apple.com/videos/play/wwdc2022/110344/)
- [Interacting with devices using the command line](https://developer.apple.com/documentation/xcode/interacting-with-devices-using-the-command-line)
