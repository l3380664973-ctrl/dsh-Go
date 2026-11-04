# iOS 远程客户端移植说明

> 分支：`ios-remote-client`（基于 `main` @ `3a01884` / v1.0.9）
> 目标：iPhone 上以**原生界面**遥控电脑或服务器上的 DSH；不做 web 界面，不在 iOS 上跑本机引擎。

## 1. 为什么是「只做远程客户端」

iOS 不允许在 App 内跑 Linux 用户态、`fork/exec`、`ptrace`，所以 DSH Go 的本机引擎（打补丁的 DSH + PRoot 里的 Ubuntu）在 iOS 上不可能实现。项目自己的路线图也是这个结论（`docs/roadmap.md` P4）：

> iOS：只做远程客户端（iOS 不允许本地运行 Linux 环境）。

这不是能力的削减，而是架构本来就分好的两条路：`HostKind.local` 之外还有 `HostKind.ssh` 和 `HostKind.relay`，两者都在纯 Dart 里实现。

## 2. 连接层为什么能原样复用

`packages/dsh_client/lib/src/carrier.dart` 定义了唯一的传输接口 `DshCarrier`，会话、流式输出、审批、重连、resync 全部建立在它之上。三种实现对应三种主机：

| carrier | 位置 | 主机形态 |
| --- | --- | --- |
| `DshHttpCarrier` | `packages/dsh_client` | `dsh web`（本机引擎，或 SSH 端口转发后的 127.0.0.1） |
| `DshSshCarrier` | `app/lib/remote/ssh/` | SSH 主机：`dartssh2` 登录 → 远端 `nohup dsh web --host 127.0.0.1 --port 0 --no-open` → 本地转发 |
| `RemoteTunnelCarrier` | `packages/dsh_remote` | DSH Remote：Relay WebSocket + WebRTC DataChannel，Noise IK 端到端加密 |

两个包都是**纯 Dart**（`dsh_remote` 只依赖 `dsh_client` + `cryptography` + `crypto`），iOS 上无需任何改动。`dartssh2`、`xterm`、`flutter_secure_storage`、`flutter_webrtc` 也都有 iOS 实现。

已在 Windows 上实测（详见 `LOCAL-SETUP.zh.md` 7.7 节）：18 个 live 集成测试全过，覆盖鉴权、RPC、mux 流式、watch/resync、附件、凭据、插件桥、原生面板与点击回调。

## 3. 平台差异清单

### 复用（不改代码）

- `packages/dsh_client`（约 50 个源文件）、`packages/dsh_remote`（约 15 个）
- `app/lib/ui`（511 个 dart 文件的 Material 界面）、`app/lib/state`（98 个，Riverpod）
- `app/lib/remote/`（SSH 与 relay 两条路径的接线）

### 裁掉（Android 专有，iOS 上不存在对等能力）

| 模块 | 通道 / 原因 |
| --- | --- |
| `app/lib/runtime/` | `dsh/runtime`：PRoot + Linux 用户态 |
| `app/lib/phone/` | `dsh/phone`：无障碍读屏与点按、Shizuku/Sui/root/ADB |
| `app/lib/pets/overlay_channel.dart` | `dsh/pet_overlay`：App 外悬浮窗 |
| `app/lib/update/installer.dart` | APK 安装 |
| `app/lib/notify/`（Android 前台服务部分） | `dsh/notify`；iOS 走 `UNUserNotificationCenter` |
| `app/lib/usage/usage_net.dart`、`performance/refresh_rate.dart` | 平台专有统计与刷新率 |
| `state/app_icon_state.dart`、`icon_shortcut_state.dart`、`links/launcher_entries.dart` | 桌面图标、快捷方式 |

`app/android` 下有 272 个 Kotlin 文件 / 2.1 MB，iOS 端只需要其中极小一部分的等价物（见 M3）。

### 新增

| 文件 | 作用 |
| --- | --- |
| `app/lib/platform/app_platform.dart` | **能力开关的唯一来源**：`supportsLocalEngine`、`supportsPhoneControl`、`supportsPetOverlay`、`supportsApkUpdate`、`supportsBackgroundGuide`、`supportsSystemAccess`、`supportsRefreshRateOverride`、`supportsVoiceInput`、`supportsLocalNotifications`、`supportsLauncherIconCustomisation` |
| `app/ios/` | Xcode 工程（`flutter create --platforms=ios` 生成） |
| `.github/workflows/ios-unsigned-build.yml` | macOS runner 出未签名 IPA |

## 4. 门控方式

Android 专属功能不是删掉，而是**入口不展示**：

- `ui/settings/settings_screen.dart`：手机操控、通知、语音、刷新率、后台运行、系统权限、本机引擎这几项按能力开关隐藏
- `ui/remote/host_switcher.dart`：iOS 上不出现「本机」这一行
- `ui/onboarding/runtime_choice.dart`：首次引导只有「远程主机」，且默认选中
- `ui/remote/remote_screen.dart`：不出现「切回手机」
- `ui/pets/pet_settings_page.dart`：不出现「App 外显示」
- `ui/settings/appearance/appearance_page.dart`：不出现「应用图标 / 图片快捷方式」

底层通道缺失不会崩：`app/lib` 里已有 **54 处** `MissingPluginException` 处理，缺通道时按 no-op 降级。

## 5. 里程碑

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| **M0** | `ios/` 工程、能力开关层、入口门控、`flutter analyze` 通过、GH Actions 工作流 | ✅ 已完成（见下） |
| **M1** | 远程-only 收口：iOS 上默认主机强制为远程、引导与空态文案、iOS 上禁用本机引擎相关 provider、隐藏空白版入口（`AdaptiveRail.onWeb`） | ✅ 已完成（见下） |
| **M2** | DSH Remote 路径的 iOS 验证（`flutter_webrtc` 的 ICE/TURN 在 iOS 上未验证，上游只在 Android 上跑过 P2P 探针） | 待做 |
| **M3** | iOS 平台层：本地通知（`UNUserNotificationCenter`）、后台重连策略、深链回跳、语音输入、`webview_flutter_wkwebview` 内嵌网页 | 待做 |
| **M4** | Cupertino 细节（`ui/theme/app_theme.dart` 已有 `TargetPlatform` 分支）、TestFlight / 自签分发 | 待做 |

### M0 实际产出（已验证）

| 项 | 结果 |
| --- | --- |
| `app/ios/` | Flutter 3.47.7 生成，bundle id `io.github.ccch1mneyyy.dshApp`，部署目标 iOS 15.0 |
| `app/ios/Podfile` | 手写标准模板（`flutter create` 不生成；`pod install` / CI 需要它） |
| `app/ios/Runner/Info.plist` | 显示名 DSH Go、`dshgo://` URL scheme、本地网络/相册/相机/麦克风/语音识别用途说明、`NSAllowsLocalNetworking` |
| `app/lib/platform/app_platform.dart` | 能力开关层 |
| 入口门控 | 6 个文件（见上表） |
| `app/pubspec.yaml` | 增加 `webview_flutter_wkwebview` |
| `flutter analyze` | **No issues found**（169 秒，全量 1724 个 dart 文件） |
| CI | `.github/workflows/ios-unsigned-build.yml`（macOS 15 + Flutter 3.47.7 → 未签名 IPA + SHA256 artifact） |

### M1 实际产出（已验证）

iOS 上没有任何路径能走进本机引擎：

| 位置 | 处理 |
| --- | --- |
| `state/hosts_state.dart` | 新增 `HostRef.unusableHere`：iOS 上占位的「本机」= 还没有主机 |
| `ui/chat/chat_screen.dart` | 空态在 iOS 上给的是「添加远程主机 → 远程主机页」，不是「安装运行环境」（`idleOrRemote`） |
| `ui/shell/root_gate.dart` | iOS 首启**跳过整套 onboarding**（没有运行环境要装、没有无障碍要授权）；`_maybeAutoStart` 直接返回，不启动引擎 |
| `ui/remote/remote_screen.dart` | iOS 上新加的 SSH 主机立即生效（本地没有东西要和它抢） |
| `ui/shell/adaptive/adaptive_rail.dart` + `home_shell.dart` | 「网页版」键改成可空，iOS 上不渲染 |
| `ui/shell/quick_panel.dart` + `ui/settings/quick_panel_items_sheet.dart` | 快捷入口及其设置面板都过滤掉「本机网页版 / 本机引擎」 |
| `ui/settings/index/settings_pages.dart` | `dshgo://open/` 深链里的 引擎/后台/系统权限/手机操控 在 iOS 上落到远程主机页 |
| `ui/update/update_tiles.dart` | APK 自更新的两行在 iOS 上不渲染 |

注意：这些模块的**代码仍在树里**（同一份树也要构建 Android，且上游不接受外部 PR），只是 iOS 上不可达；`app/android` 的 Kotlin 与 `runtime/` 不参与 iOS 构建。

验证：`flutter analyze` → No issues found；定向测试 137 + 81 + 165 全过；10 个 update golden 在原始 `main` 上同样失败（字体替换所致）。

## 6. 构建

iOS 包**只能**在 macOS + Xcode 上产出（Windows / Linux 都不行）。

### 云构建（已跑通，2026-11-03）

`workflow_dispatch` 跑 `ios-unsigned-build-intel`，在 GitHub 的 Intel macOS runner 上出未签名包；run `41485265586` 的 11 步全部通过，产物 26.4 MB：

| 校验项 | 结果 |
| --- | --- |
| SHA256 | `35311009364cc48fc167199d9007fb5cc9c3a4c8ce688b8acde51134d12db1e4`（与工作流自算一致） |
| `CFBundleIdentifier` | `io.github.ccch1mneyyy.dshApp` |
| 显示名 / 版本 | DSH Go / 1.0.9 (1) |
| `MinimumOSVersion` | 15.0 |
| URL scheme | `dshgo` ✓ |
| 权限用途文案 | 本地网络 / 相册 / 相机 / 麦克风 / 语音识别 ✓ |
| `Frameworks/` | Flutter、App（32 MB AOT）、objective_c、**WebRTC（12 MB）** → DSH Remote 的 P2P 栈确实编进去了 |

出包时撞到的三个坑（都已在仓库里修好，值得记住）：

| # | 现象 | 原因 | 修法 |
| --- | --- | --- | --- |
| 1 | 排队 15 分钟后 job 被取消、0 步执行 | 免费额度下 `macos-15`（arm64）容量不足，annotation 明写 "may experience longer queue times" | 改用 `macos-15-intel`，立即拿到机器；两个变体都留在仓库 |
| 2 | `Swift Compiler Error: ... 'NWPath' has no member 'isUltraConstrained'` | `connectivity_plus` 7.3.2 用了更新 iOS SDK 才有的 API，runner 是 Xcode 16.4 | `tooling/ios-ci-plugin-patches.sh` 把该调用改成 `false`（幂等；App 不依赖 ultra-constrained 语义） |
| 3 | `Error (Xcode): The sandbox is not in sync with the Podfile.lock` | 手写 Podfile 与 Flutter 3.47 的 Swift Package Manager 混用 | 删掉 Podfile：3.47 下所有 iOS 插件都是 Swift Package，本就不需要 CocoaPods |

### 本地 Mac

```bash
cd app && flutter pub get
flutter build ios --release     # 需要 Xcode 登录的开发者账号
```

装到手机上：用 AltStore / SideStore / Sideloadly 自签（免费 Apple ID 签的包 7 天过期），或把未签名 IPA 交给有开发者账号的机器重签。

### 模拟器实跑（不需要 Apple ID、不需要 iPhone）

`ios-simulator-screenshot` 工作流在 macOS runner 上启动 Apple 官方的 iOS 模拟器，装上 App、启动、截图并上传，不需要任何签名。run `41668873817` 通过，结果：

| 观察点 | 结果 |
| --- | --- |
| 安装 | 模拟器桌面上出现 **DSH Go** 图标 |
| 首帧 | 启动后 **10~30 秒**才出画面（debug + JIT；release 会快得多），所以早期在 20 秒抓的图是白屏，不是故障 |
| 界面 | 顶栏「New chat · Not connected」+「Choose model」，空态「Keep using DSH…on your phone」+ **Manage remote hosts** 按钮，底部输入条「Connect to the engine to send」，宠物渲染正常 |
| M1 收口 | **空态给的是「管理远程主机」，不是「安装运行环境」** —— iOS 远程-only 的收口在真渲染下成立 |
| 语言 | 跟随系统（模拟器是英文环境），中文跟随系统时会切中文 |

踩过的两个 CI 坑：`--console-pty` 不清场子会让步骤永久挂住；macOS 自带环境**没有 GNU `timeout`**（报 `timeout: command not found`），改用 kill + wait。

截图存放在工作机 `Z:\DSH-Go-ipa\ios-screenshots\`（10s/30s/60s 三张）。

## 7. 已知阻塞与风险

0. **上游没有 iOS 端**：仓库 10 个 release 全部只有 `arm64.apk`，没有 IPA，也没有 ios 分支。上游 issue #264（open）是自己做的 iOS 远程客户端可行性分析，明确「只做远程客户端」，但**没有落地代码**——本分支就是那份分析的实现。
1. **没有 Mac 就打不出包**（当前工作机是 Windows）。选项：借 Mac、云 Mac、或上面的 GH Actions 出未签名 IPA 再自签。费用与流程见技术方案文档。
2. **WebRTC 在 iOS 上未验证**：`packages/dsh_remote/README.md` 状态表只写了 "Real P2P and Relay-only probes pass on Android 35 x86_64"。M1 先做 SSH 路径可完全绕开这个风险。
3. **iOS 后台限制**：长回合切后台可能断流，靠 `DshMux` 的退避重连 + 回前台 resync 兜底，M3 再补通知。
4. **合规**：主体 AGPL-3.0（分发需开源修改）；`sdk/`、`examples/` 为 MIT；`ASSETS.md` 里 Deepy、鲸娘、DSH Go 名称与标识**不在开源授权内**，自用无碍、公开发布需换素材。
5. **上游不接受外部 PR**（`AGENTS.md`）：这个分支只能自维护，无法合入上游。

## 8. 移植过程中发现的上游问题（未提交 issue）

1. `runtime/bridge/dsh-go-bridge/package.json` 的 `files` 清单缺 `lib/session-deletion.js`，而 `lib/index.js` 直接 import 它 → 从仓库打包安装后插件必然 `failed to import`。
2. `dsh-go-bridge` 未发布到 npm（`registry.npmjs.org/dsh-go-bridge` 为 Not found），只随 Android 运行时打包。桌面主机要手工安装才有完整功能；不装时 `/dsh-go/v1/*` 返回 405，客户端降级为 `unsupported`。
3. `dsh-go-example-weather` 要求 `@deepseek-ai/dsh-tools >=0.2.1-rc.2`，而 dsh 0.2.0-rc.2 会被版本闸门拒绝（`examples/plugins/dsh-go-example-quick`、`-usage` 不受影响）。
