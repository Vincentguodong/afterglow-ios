#!/usr/bin/env bash
# Build and install with Xcode's Personal Team. No credentials are read by this script.
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
mode="open"
afterglow_team="${APPLE_TEAM_ID:-}"
afterglow_bundle="${APP_BUNDLE_ID:-}"
afterglow_device="${IPHONE_UDID:-}"

usage() {
  cat <<'TEXT'
余光 · 免费个人开发安装

用法：
  bash Scripts/install-free.sh --open      检查环境并打开 Xcode 工程（默认）
  bash Scripts/install-free.sh --check     只检查本机 Xcode 和 iOS SDK
  bash Scripts/install-free.sh --devices   显示 Xcode 可用的运行设备
  bash Scripts/install-free.sh --install --team TEAM_ID --bundle YOUR_BUNDLE_ID --device IPHONE_UDID

也可通过 APPLE_TEAM_ID、APP_BUNDLE_ID、IPHONE_UDID 环境变量提供这三个值。
首次安装请先在 Xcode 登录 Apple Account，选择 Personal Team，连接并信任 iPhone。
免费配置描述文件 7 天过期；到期后用同一 Team 和 Bundle ID 重新安装。
TEXT
}

fail() { printf '%s\n' "$*" >&2; exit 1; }
take_value() { [[ $# -ge 2 && -n "$2" && "$2" != --* ]] || fail "参数 $1 缺少值。"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --open) mode=open; shift ;;
    --check) mode=check; shift ;;
    --devices) mode=devices; shift ;;
    --install) mode=install; shift ;;
    --team) take_value "$@"; afterglow_team="$2"; shift 2 ;;
    --bundle) take_value "$@"; afterglow_bundle="$2"; shift 2 ;;
    --device) take_value "$@"; afterglow_device="$2"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage >&2; fail "未知参数：$1" ;;
  esac
done

[[ "$(uname -s)" == Darwin ]] || fail "需要在 Mac 上执行。当前环境不能运行 Xcode 或给 iPhone 原生 App 签名；请参阅 Docs/FREE_INSTALL.md。"
[[ -d "$project_root/Afterglow.xcodeproj" ]] || fail "没有找到 Afterglow.xcodeproj。请完整解压工程后再运行。"

# Use a full Xcode for this process only; never alter the machine-wide selection.
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  selected_developer="$(xcode-select -p 2>/dev/null || true)"
  if [[ "$selected_developer" == */CommandLineTools || -z "$selected_developer" ]]; then
    if [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
      export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    else
      fail "请先从 Mac App Store 安装完整 Xcode；仅安装 Command Line Tools 不足以构建 iPhone App。"
    fi
  fi
fi

if ! xcodebuild -version; then
  fail "Xcode 尚未就绪。请先打开 Xcode，完成它要求的许可确认或组件安装，再重试。本脚本不会代替你接受条款。"
fi
if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  fail "请先打开 Xcode，完成首次启动配置及 iOS 平台组件安装，再重试。"
fi
if ! ios_sdk_version="$(xcrun --sdk iphoneos --show-sdk-version 2>/dev/null)"; then
  fail "未找到 iOS SDK。请在 Xcode 的 Settings 中安装 iOS 平台支持。"
fi
printf 'iOS SDK：%s\n' "$ios_sdk_version"

cd "$project_root"
case "$mode" in
  check)
    printf '%s\n' "环境检查通过。尚未进行编译、签名或安装。"
    exit 0
    ;;
  open)
    open "$project_root/Afterglow.xcodeproj"
    cat <<'TEXT'

Xcode 工程已打开。首次安装只需完成以下步骤：
1. Xcode → Settings → Accounts，登录自己的 Apple Account。
2. 选中 Afterglow target → Signing & Capabilities → Team，选择 Personal Team。
3. 把 Bundle Identifier 改为自己的唯一标识，例如 com.yourname.afterglow。
4. 连接并解锁 iPhone，按系统提示信任电脑；在 iPhone 开启 Developer Mode。
5. Xcode 顶部选择你的 iPhone，点击 ▶ Run（⌘R）。

免费签名 7 天过期。后续仍使用同一个 Team 和 Bundle ID，再次 Run 即可更新安装。
原生 App 的照片与网页版胶卷分别存储；需要迁移的照片先从网页版导出。
详细说明见 Docs/FREE_INSTALL.md。
TEXT
    exit 0
    ;;
  devices)
    xcodebuild -project Afterglow.xcodeproj -scheme Afterglow -showdestinations
    printf '%s\n' "请从可用 iOS 真机项复制 id，用于 --device；不要使用模拟器或占位目的地。"
    exit 0
    ;;
esac

[[ "$afterglow_team" =~ ^[A-Za-z0-9]{10}$ ]] || fail "--team 应为 Xcode 中所选 Personal Team 的 10 位 Team ID。也可直接在 Xcode 选择 Team 后点击 Run。"
[[ "$afterglow_bundle" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ && "$afterglow_bundle" != com.example.* ]] || fail "--bundle 应为自己的唯一 Bundle ID，例如 com.yourname.afterglow；不要使用 com.example。"
[[ "$afterglow_device" =~ ^[A-Fa-f0-9-]{20,40}$ ]] || fail "--device 应为连接 iPhone 的 UDID。用 --devices 查看可用真机的 id。"
xcrun --find devicectl >/dev/null 2>&1 || fail "当前 Xcode 不含 devicectl。请更新 Xcode，或在 Xcode 中直接点击 Run 安装。"

derived_data="$project_root/build/PersonalTeam"
build_log="$project_root/build/PersonalTeam-build.log"
mkdir -p "$project_root/build"
printf '%s\n' "正在构建供已连接 iPhone 使用的开发版本。Xcode 会使用你已登录的账号管理签名。"
if ! xcodebuild -project Afterglow.xcodeproj -scheme Afterglow -configuration Debug \
  -destination "platform=iOS,id=$afterglow_device" \
  -derivedDataPath "$derived_data" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  CODE_SIGN_STYLE=Automatic CODE_SIGNING_ALLOWED=YES \
  DEVELOPMENT_TEAM="$afterglow_team" PRODUCT_BUNDLE_IDENTIFIER="$afterglow_bundle" \
  build 2>&1 | tee "$build_log"; then
  fail "构建未完成，尚未安装。请查看 build/PersonalTeam-build.log；首次签名问题通常可在 Xcode 的 Signing & Capabilities 中处理。"
fi

app_path="$derived_data/Build/Products/Debug-iphoneos/Afterglow.app"
[[ -d "$app_path" ]] || fail "构建命令结束，但没有找到 Afterglow.app；尚未安装。"
/usr/bin/codesign --verify --strict "$app_path" || fail "App 签名校验未通过，已停止安装。"
actual_bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Info.plist")"
[[ "$actual_bundle" == "$afterglow_bundle" ]] || fail "生成 App 的 Bundle ID 与指定值不一致，已停止安装。"

xcrun devicectl device install app --device "$afterglow_device" "$app_path"
printf '%s\n' "安装命令已成功完成。正在尝试打开余光…"
if ! xcrun devicectl device process launch --device "$afterglow_device" "$afterglow_bundle"; then
  printf '%s\n' "App 已安装，但自动打开未成功。请解锁 iPhone，检查 Developer Mode 或系统信任提示，再轻点余光图标。" >&2
  exit 2
fi
printf '%s\n' "余光已安装并收到启动成功回执。请在手机上允许相机权限并完成一次拍照、冲洗和导出检查。"
