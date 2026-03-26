# 🦞 OpenclawDaddy（钓钓虾）

[![Build](https://github.com/wordgate/openclaw-daddy/actions/workflows/build.yml/badge.svg)](https://github.com/wordgate/openclaw-daddy/actions/workflows/build.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue.svg)]()

**一键解决 openclaw 在 macOS 上的权限问题。** 录屏、辅助功能、摄像头、麦克风 — 全部搞定，开箱即用。

> The missing macOS permission wrapper for [openclaw](https://openclaw.ai). Screen recording, accessibility, camera, microphone — all permissions inherited automatically.

---

## 为什么需要 OpenclawDaddy？

[openclaw](https://openclaw.ai) 是强大的 AI 助手平台，支持多渠道消息、浏览器控制、屏幕录制等高级功能。但在 macOS 上通过命令行 (`npm -g`) 安装运行时，有一个致命问题：

**命令行进程无法获得 macOS 系统权限。**

macOS 的录屏、辅助功能、摄像头等权限只授予 `.app` 应用程序。通过终端运行的 `openclaw` 进程无法获得这些权限，导致浏览器控制、屏幕捕获等核心功能无法使用。

**OpenclawDaddy 解决了这个问题。** 它将 openclaw 包装在原生 macOS `.app` 中，让 openclaw 进程自动继承 app 的所有权限授权。

## Why OpenclawDaddy?

openclaw is a powerful AI assistant platform with multi-channel messaging, browser control, screen recording, and more. But when installed via `npm -g` on macOS, there's a critical limitation:

**CLI processes cannot receive macOS system permissions.**

macOS grants screen recording, accessibility, camera, and microphone permissions only to `.app` bundles. openclaw running from Terminal cannot access these permissions, breaking browser control, screen capture, and other core features.

**OpenclawDaddy fixes this.** It wraps openclaw in a native macOS `.app`, so openclaw processes automatically inherit all permission grants.

---

## Features | 功能

### 🔐 Permission Delegation | 权限委托
- openclaw processes inherit all macOS permissions from the app bundle
- Screen Recording, Accessibility, Camera, Microphone, Full Disk Access
- Visual permissions dashboard — see what's granted, request what's missing
- openclaw 进程自动继承 app 的所有 macOS 权限
- 可视化权限面板 — 一目了然，一键申请

### 🔄 Process Keepalive | 进程保活
- All openclaw profiles auto-start and stay running
- Automatic restart on crash with configurable delay
- Crash-loop detection (10 consecutive sub-1s crashes)
- macOS notification on crash-loop
- 所有 profile 自动启动，崩溃自动重启
- 智能崩溃循环检测 + 系统通知

### 📺 Embedded Terminal | 内嵌终端
- Dark-themed terminal (Tango Dark palette) for each profile
- Real-time process output with full ANSI color support
- Free shell tabs that also inherit app permissions
- 暗色主题终端，实时输出，支持 ANSI 颜色
- 自由 Shell 标签页同样继承权限

### 🔍 Profile Discovery | Profile 发现
- Automatically discovers openclaw profiles from `~/.openclaw-*/`
- Create new profiles via `openclaw onboard` directly in embedded terminal
- No manual configuration needed — openclaw is the source of truth
- 自动扫描发现已有 profile
- 在内嵌终端中直接创建新 profile
- 无需手动配置 — openclaw 为真理源

### 🖥️ Menu Bar Presence | 菜单栏常驻
- Background operation with menu bar icon
- Quick status overview for all profiles
- Click to jump to any profile
- Start All / Stop All from menu bar
- 后台运行，菜单栏图标
- 一键查看所有 profile 状态

### 🌐 Localization | 多语言
- English + 简体中文
- Follows system language automatically

---

## Installation | 安装

### Download | 下载

Download the latest `.dmg` from [Releases](https://github.com/wordgate/openclaw-daddy/releases).

从 [Releases](https://github.com/wordgate/openclaw-daddy/releases) 下载最新 `.dmg` 安装包。

### Requirements | 系统要求

- macOS 13.0 (Ventura) or later
- [openclaw](https://openclaw.ai) installed (`curl -fsSL https://openclaw.ai/install.sh | bash`)

### Build from Source | 从源码构建

```bash
# Prerequisites
brew install xcodegen

# Clone and build
git clone https://github.com/wordgate/openclaw-daddy.git
cd openclaw-daddy
xcodegen generate
xcodebuild -scheme OpenclawDaddy -configuration Release -arch arm64 -arch x86_64 ONLY_ACTIVE_ARCH=NO build
```

---

## Usage | 使用

1. **Install openclaw** — If not installed, click "Install openclaw" in Settings → General
2. **Create a profile** — Click "Add Profile" in sidebar, follow the `openclaw onboard` wizard
3. **Grant permissions** — Go to Settings → Permissions, grant Screen Recording, Accessibility, etc.
4. **Done!** — All profiles auto-start and stay alive. openclaw now has full macOS permissions.

1. **安装 openclaw** — 如未安装，在设置 → 通用中点击「安装 openclaw」
2. **创建 Profile** — 点击侧边栏「添加配置」，跟随 `openclaw onboard` 引导
3. **授权权限** — 进入设置 → 权限，授予录屏、辅助功能等权限
4. **完成！** — 所有 profile 自动启动并保活，openclaw 获得完整 macOS 权限。

---

## How It Works | 工作原理

OpenclawDaddy is a native macOS `.app` built with Swift and SwiftUI. It spawns openclaw processes as child processes using pseudo-terminals (PTY). Because these child processes are forked from the `.app` bundle, they automatically inherit all macOS TCC (Transparency, Consent, and Control) permissions granted to the app.

```
┌─────────────────────────────────────┐
│  OpenclawDaddy.app                  │
│  ┌─────────────────────────────────┐│
│  │ macOS Permissions               ││
│  │ ✅ Screen Recording             ││
│  │ ✅ Accessibility                ││
│  │ ✅ Camera / Microphone          ││
│  └─────────────────────────────────┘│
│                                     │
│  ┌──────────┐  ┌──────────┐        │
│  │ openclaw  │  │ openclaw  │  ...  │
│  │ --profile │  │ --profile │       │
│  │ gateway   │  │ worker    │       │
│  └──────────┘  └──────────┘        │
│  (inherits permissions)             │
└─────────────────────────────────────┘
```

---

## Tech Stack | 技术栈

- **Swift + SwiftUI** — Native macOS UI
- **[SwiftTerm](https://github.com/migueldeicaza/SwiftTerm)** — Terminal emulator
- **[Yams](https://github.com/jpsim/Yams)** — YAML configuration
- **XcodeGen** — Project generation

---

## Contributing | 贡献

Contributions are welcome! Please open an issue or pull request.

欢迎贡献代码！请提交 Issue 或 Pull Request。

---

## Disclaimer | 声明

OpenclawDaddy is a **community third-party tool**, not an official openclaw product. It is independently developed and maintained. [openclaw](https://openclaw.ai) is a trademark of its respective owners.

OpenclawDaddy（钓钓虾）是**社区第三方工具**，非 openclaw 官方产品。独立开发和维护。

---

## Acknowledgements | 致谢

- [openclaw](https://openclaw.ai) — The AI assistant platform this app wraps
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) — Terminal emulator by Miguel de Icaza
- [Yams](https://github.com/jpsim/Yams) — YAML parser for Swift

---

> 🚀 Maintained by the [Kaitu.io](https://kaitu.io) team — 由[开途加速器](https://kaitu.io)团队维护

## License

[MIT](LICENSE)
