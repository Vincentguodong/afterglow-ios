# 可选 TestFlight 发布流程

本仓库提供原生源码和归档脚本，不包含签名构建、发布账号或现成测试链接。正式发布前，先完成 `VALIDATION.md` 中的编译、权限、数据与真机验证。

## 前提

1. 有效的 Apple Developer Program 团队，以及上传构建和管理测试的权限。
2. Mac 上的兼容 Xcode，或自行配置并授权的 macOS 构建环境。
3. 发布者自己的 Bundle ID、Team ID 和 App Store Connect App 记录。
4. 与最终 App 一致的测试说明、支持方式、审核联系人和隐私信息。

签名资料只保存在受保护的本地环境或 CI 密钥存储中；不要提交到 Git。Apple 账号密码仅在 Apple / Xcode 官方界面输入。

## 发布步骤

1. 打开 `Afterglow.xcodeproj`，运行 XCTest 并完成真机验证。
2. 在 Signing & Capabilities 选择自己的 Team 和唯一 Bundle ID。
3. 在 App Store Connect 创建 App，绑定同一个 Bundle ID，并设置自己的名称与 SKU。
4. 在 Xcode 选择合适的 iOS 归档目的地，执行 Product → Archive → Distribute App → App Store Connect → Upload。
5. 等待 Apple 处理构建，填写测试信息与出口合规问卷。当前 Info.plist 的 `ITSAppUsesNonExemptEncryption` 为 `NO`；发布者应按最终代码自行核实。
6. 先通过内部测试验证安装。需要外部测试时，创建外部测试组，补充信息并完成所需 Beta App Review。
7. 如需公开邀请，在相应外部测试组中启用 Public Link；是否公开由发布者决定。

也可使用 `Scripts/release.sh --archive` 归档；`--upload` 会尝试向 App Store Connect 上传。先配置 `APPLE_TEAM_ID`、`APP_BUNDLE_ID` 和所需 `BUILD_NUMBER`。命令执行结束不代表 Apple 已处理或批准构建。

TestFlight 构建有使用期限，审核结果与处理时间由 Apple 决定。只在自己的设备开发测试，可以使用 `FREE_INSTALL.md` 中的 Personal Team 路径。

## 测试说明参考

余光提供六款胶片配方、曝光 / 颗粒 / 色温转盘、暗房微调、本地胶卷和相册导出。请重点验证取景方向、拍摄后编辑、导入大图、原片对比、后台恢复、重启后数据恢复及系统分享。当前支持竖屏与最长边 4096 像素 JPEG 输出，不支持 RAW 或视频。

## 隐私填写

请根据最终构建核实 `PRIVACY.md` 与 Apple App Privacy 信息，提供发布者自己的支持方式和公开隐私政策地址。代码修改、第三方 SDK 或云端服务的加入，都可能改变数据处理范围。

## Apple 官方资料

- [上传构建](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [TestFlight 概览](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
- [外部测试](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/)
- [测试信息](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)
