# OpenclawDaddy macOS App Design

## Overview

A native macOS .app wrapper for the `openclaw` command-line tool. The primary purpose is to serve as a **permission carrier** — allowing openclaw processes to inherit macOS permissions (screen recording, accessibility, etc.) from the .app bundle. Secondary purpose is lightweight process management with built-in terminal emulation.

## Goals

1. Wrap multiple `openclaw` instances under one .app for macOS permission delegation
2. Provide keepalive process management for each profile
3. Embed full terminal emulation (SwiftTerm) so users can see real-time process output
4. Support general-purpose terminal tabs (not tied to a profile)
5. Offer a permissions dashboard to view/request macOS permissions
6. Menu bar presence for background operation

## Tech Stack

- **Swift + SwiftUI** — native macOS UI
- **SwiftTerm** — terminal emulator component (SPM)
- **Yams** — YAML parsing (SPM)
- **Minimum macOS:** 13 (Ventura)
- **Sandbox:** disabled (required for child process permission inheritance)

---

## Architecture

```
OpenclawDaddy.app
├── SwiftUI App (main process)
│   ├── MainWindow (NavigationSplitView)
│   │   ├── Sidebar: Profile list + status indicators, Terminal tabs
│   │   └── Detail: SwiftTerm terminal view
│   ├── SettingsWindow
│   │   ├── Profile management (CRUD, visual editor for config.yaml)
│   │   └── Permissions status panel
│   └── MenuBar icon + dropdown
├── ProcessManager (process lifecycle core)
│   ├── Start/monitor child processes per profile
│   ├── Keepalive: fixed 3s delay restart on crash, infinite retry
│   └── PTY-based process launch for full terminal emulation
└── ConfigManager
    └── Read/write ~/.openclaw-daddy/config.yaml + FSEvents file watching
```

---

## Configuration

**Source of truth:** `~/.openclaw-daddy/config.yaml`

The Settings UI is a visual editor for this file. Users can also edit the file directly — the app watches for changes via FSEvents and reloads automatically. Changes to running profiles require manual restart (no auto-restart to avoid unexpected interruption).

```yaml
global:
  restart_delay: 3          # seconds to wait before restarting a crashed process
  extra_path:               # appended to PATH for all profiles
    - /usr/local/bin
    - /opt/homebrew/bin

profiles:
  - name: "Gateway"
    command: "openclaw --profile gateway run"
    autostart: true         # start when app launches
    path:                   # profile-specific additional PATH entries
      - /Users/david/.nvm/versions/node/v20/bin
    env:                    # optional extra environment variables
      OPENCLAW_PORT: "8080"

  - name: "Worker"
    command: "openclaw --profile worker run"
    autostart: true
    path: []

  - name: "Monitor"
    command: "openclaw --profile monitor run"
    autostart: false
```

**PATH construction:** system PATH + `global.extra_path` + `profile.path`

**Process launch:** `/bin/bash -l -c "{command}"` — login shell ensures user environment (nvm, etc.) is loaded.

---

## UI Layout

### Main Window (NavigationSplitView)

```
┌─ Sidebar ──────────┬─ Detail ──────────────────────┐
│                     │                                │
│  PROFILES           │  ┌──────────────────────────┐  │
│  ● Gateway    🟢    │  │ $ openclaw --profile      │  │
│  ● Worker     🟢    │  │ gateway run               │  │
│  ● Monitor    ⚫    │  │ [2026-03-26] Starting...  │  │
│                     │  │ Listening on :8080         │  │
│  TERMINALS          │  │ Connection accepted...     │  │
│  ○ Shell 1          │  │ █                          │  │
│                     │  └──────────────────────────┘  │
│  [+] New Terminal   │                                │
│  [+] New Profile    │  [▶ Start] [■ Stop] [↻ Restart]│
└─────────────────────┴────────────────────────────────┘
```

### Sidebar Items

- **Profile entries:** bound to a command, managed by keepalive, status indicator (🟢 Running / 🔴 Crashed / ⚫ Stopped)
- **Terminal entries:** free interactive shell (`$SHELL`), no keepalive, user can type commands freely
- Both types use PTY + SwiftTerm, both inherit .app permissions

### Settings Window

**Profiles tab:** visual CRUD editor for `config.yaml` profiles (name, command, path, env, autostart)

**Permissions tab:**

```
┌─ Permissions ──────────────────────────┐
│                                        │
│  ● Screen Recording      ✅ Granted    │
│  ● Accessibility          ❌ Denied    │  → [Open Settings]
│  ● Camera                ✅ Granted    │
│  ● Microphone            ⚪ Not Asked  │  → [Request]
│  ● Full Disk Access      ⚠️ Unknown   │  → [Open Settings]
│  ● Input Monitoring      ⚠️ Unknown   │  → [Open Settings]
│  ● Location              ⚪ Not Asked  │  → [Request]
│  ● Notifications         ✅ Granted    │
│                                        │
│  [Open System Settings]                │
└────────────────────────────────────────┘
```

Detectable permissions (API-queryable): Screen Recording, Accessibility, Camera, Microphone, Location, Notifications — show actual status, offer "Request" button.

Non-detectable permissions: Full Disk Access, Input Monitoring, Automation — show "Unknown", offer "Open Settings" link to relevant System Settings pane.

Status refreshes when app returns to foreground.

### Menu Bar

```
┌─ OpenclawDaddy ────────────┐
│  Gateway          🟢 运行中 │
│  Worker           🟢 运行中 │
│  Monitor          ⚫ 已停止 │
│  ─────────────────────────  │
│  Start All                  │
│  Stop All                   │
│  ─────────────────────────  │
│  Open Window                │
│  Settings...                │
│  ─────────────────────────  │
│  Quit                       │
└─────────────────────────────┘
```

- Closing the main window does NOT quit the app — it continues in menu bar
- Menu bar icon changes appearance when any process is crashed
- Clicking a profile name opens the main window focused on that terminal
- Quit via menu bar Quit or ⌘Q

---

## Process Lifecycle

```
App Launch
  ├─ Read config.yaml
  ├─ Start autostart=true profiles
  │
Profile Process Start
  ├─ Build PATH (system + global + profile)
  ├─ Create PTY via posix_openpt
  ├─ Fork child: /bin/bash -l -c "{command}"
  ├─ Bind SwiftTerm to PTY file descriptor
  ├─ Status → 🟢 Running
  │
Process Monitoring (waitpid / SIGCHLD)
  ├─ Normal exit (exit 0) → ⚫ Stopped, no restart
  ├─ Abnormal exit (exit != 0 / signal)
  │   ├─ Status → 🔴 Crashed
  │   ├─ Terminal shows: "[Process crashed, restarting in 3s...]"
  │   ├─ Wait 3 seconds
  │   └─ Restart → 🟢 Running
  └─ User manual Stop
      ├─ Send SIGTERM
      ├─ Wait 5 seconds for graceful exit
      ├─ Send SIGKILL if still running
      └─ Status → ⚫ Stopped, no restart

App Quit
  ├─ SIGTERM to all child processes
  ├─ Wait 5 seconds
  ├─ SIGKILL remaining
  └─ Exit
```

---

## Project Structure

```
openclaw-daddy/
├── OpenclawDaddy.xcodeproj
├── OpenclawDaddy/
│   ├── App/
│   │   ├── OpenclawDaddyApp.swift      # App entry, menu bar setup
│   │   └── AppDelegate.swift           # Close-window-not-quit behavior
│   ├── Views/
│   │   ├── MainWindow.swift            # NavigationSplitView container
│   │   ├── SidebarView.swift           # Profile/Terminal list
│   │   ├── TerminalView.swift          # SwiftTerm NSViewRepresentable wrapper
│   │   ├── SettingsView.swift          # Config editor + permissions panel
│   │   └── MenuBarView.swift           # Menu bar dropdown
│   ├── Models/
│   │   ├── Profile.swift               # Profile data model
│   │   └── AppConfig.swift             # Config file model
│   ├── Services/
│   │   ├── ProcessManager.swift        # Process start/monitor/keepalive
│   │   ├── PTYManager.swift            # PTY creation and management
│   │   ├── ConfigManager.swift         # YAML read/write + FSEvents watch
│   │   └── PermissionManager.swift     # Permission detection and requests
│   ├── Resources/
│   │   └── Assets.xcassets
│   └── Info.plist                      # Permission usage descriptions
└── Package.swift                       # SPM dependencies (SwiftTerm, Yams)
```

---

## Info.plist Permission Declarations

```xml
<key>NSScreenCaptureUsageDescription</key>
<string>OpenclawDaddy needs screen recording access for openclaw processes.</string>
<key>NSCameraUsageDescription</key>
<string>OpenclawDaddy needs camera access for openclaw processes.</string>
<key>NSMicrophoneUsageDescription</key>
<string>OpenclawDaddy needs microphone access for openclaw processes.</string>
<key>NSLocationUsageDescription</key>
<string>OpenclawDaddy needs location access for openclaw processes.</string>
```

---

## Out of Scope (for v1)

- Split pane / multi-terminal view in a single detail area
- Terminal theming / font customization
- Profile groups or dependency ordering
- Remote process management
- Auto-update mechanism
