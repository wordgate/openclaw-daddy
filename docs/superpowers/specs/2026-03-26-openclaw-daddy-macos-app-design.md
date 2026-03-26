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

### SwiftTerm Integration

SwiftTerm provides `TerminalView` (an `NSView` subclass). Integration with SwiftUI requires:

**NSViewRepresentable bridge:**
```swift
struct SwiftTermView: NSViewRepresentable {
    let ptyFd: Int32  // file descriptor from forkpty
    func makeNSView(context:) -> TerminalView { ... }
    func updateNSView(_:context:) { ... }
}
```

**Multi-instance concerns:**
- Each sidebar item (profile or free terminal) owns its own `TerminalView` instance + PTY fd
- Only the selected tab's `TerminalView` is in the view hierarchy at a time (NavigationSplitView detail swaps)
- Non-visible terminals: PTY continues running, SwiftTerm buffers output in memory. When user switches back, the scrollback is already populated — no re-render needed
- Memory: each TerminalView with 10K line scrollback ≈ 2-5MB. 10 tabs ≈ 20-50MB — acceptable

**Resize handling:**
- SwiftTerm calls `TerminalViewDelegate.sizeChanged(source:newCols:newRows:)` on resize
- Bridge must call `ioctl(ptyFd, TIOCSWINSZ, &winsize)` to propagate terminal size to the child process
- This is critical — without it, `ncurses` apps, `vim`, `htop` etc. break in free terminals

**Input handling:**
- SwiftTerm captures keyboard input and writes to the PTY fd
- For profile terminals: input is forwarded to the openclaw process (read-write, not read-only)
- This allows users to interact with openclaw if it accepts stdin commands

---

## Configuration

**Source of truth:** `~/.openclaw-daddy/config.yaml`

The Settings UI is a visual editor for this file. Users can also edit the file directly — the app watches for changes via FSEvents (debounced with 500ms delay) and reloads automatically. Changes to running profiles require manual restart (no auto-restart to avoid unexpected interruption).

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

**`restart_delay`** is a global-only setting; per-profile override is out of scope for v1.

**Process launch:** `/bin/bash -l -c "{command}"` — login shell ensures user environment (nvm, etc.) is loaded.

### Config Validation & Error Handling

**On load (app start or FSEvents reload):**

| Error | Behavior |
|-------|----------|
| File missing | Generate default config (see First Launch), show Settings |
| YAML parse error | Show alert with line number, keep previous valid config in memory |
| Missing required field (`name`, `command`) | Skip that profile, show warning badge on Settings icon |
| `command` binary not found in PATH | Allow config to load, show ⚠️ in sidebar; fail at process start time with clear message in terminal: `"Error: 'openclaw' not found in PATH. Check profile path settings."` |
| Duplicate profile names | Append suffix: `Gateway`, `Gateway (2)` |

**Config schema version:**

```yaml
version: 1  # schema version, for future migration
global:
  ...
```

When `version` is missing, assume `1`. Future versions bump this and include a migration function in ConfigManager. App refuses to load configs with `version` higher than it supports, showing "Please update OpenclawDaddy."

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

**Detectable & requestable** (API triggers system prompt): Camera, Microphone, Location, Notifications — show actual status, offer "Request" button.

**Detectable but not requestable** (can query status, but must direct user to System Settings): Screen Recording (`CGPreflightScreenCaptureAccess()`), Accessibility (`AXIsProcessTrusted()`) — show status, offer "Open Settings" button. `CGRequestScreenCaptureAccess()` opens System Settings directly.

**Non-detectable** (no API to query status): Full Disk Access, Input Monitoring, Automation — show "Unknown", offer "Open Settings" link to relevant System Settings pane.

Note: Notifications are requested via `UNUserNotificationCenter.current().requestAuthorization()` — no Info.plist key required on macOS.

Status refreshes when app returns to foreground.

### Menu Bar

```
┌─ OpenclawDaddy ────────────┐
│  Gateway          🟢 Running │
│  Worker           🟢 Running │
│  Monitor          ⚫ Stopped │
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

- Closing the main window does NOT quit the app — it continues in menu bar. Implemented via `AppDelegate.applicationShouldTerminateAfterLastWindowClosed` returning `false`. App remains Dock-visible (do NOT set `LSUIElement`).
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
Process Monitoring (DispatchSource.makeProcessSource + waitpid)
  ├─ Note: Use raw posix_openpt/forkpty + execve, NOT Foundation Process
  │   (Foundation Process cannot bind to a caller-supplied PTY fd)
  │   Monitor via DispatchSource.makeProcessSource(identifier:pid, flags:.exit)
  ├─ Normal exit (exit 0) → ⚫ Stopped, no restart
  ├─ Abnormal exit (exit != 0 / signal)
  │   ├─ Status → 🔴 Crashed
  │   ├─ Terminal shows: "[Process crashed, restarting in Ns...]"
  │   ├─ Wait `restart_delay` seconds (from config, default 3s)
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
└── README.md
# Note: SwiftTerm and Yams are added as Xcode Package Dependencies
# (File > Add Package Dependencies) pointing at their GitHub URLs.
# There is no top-level Package.swift — this is an .xcodeproj app, not an SPM package.
```

---

## Info.plist Permission Declarations

```xml
<!-- Camera and Microphone require usage description strings on macOS -->
<key>NSCameraUsageDescription</key>
<string>OpenclawDaddy needs camera access for openclaw processes.</string>
<key>NSMicrophoneUsageDescription</key>
<string>OpenclawDaddy needs microphone access for openclaw processes.</string>
<key>NSLocationUsageDescription</key>
<string>OpenclawDaddy needs location access for openclaw processes.</string>
```

**Note:** Screen Recording, Accessibility, Full Disk Access, and Input Monitoring do NOT use Info.plist usage description keys on macOS. They are managed entirely through System Settings. Screen Recording is triggered via `CGRequestScreenCaptureAccess()` which opens System Settings directly.

---

## First Launch

When `~/.openclaw-daddy/config.yaml` does not exist:

1. App creates `~/.openclaw-daddy/` directory
2. Writes a default config with one example profile (commented out):

```yaml
global:
  restart_delay: 3
  extra_path:
    - /usr/local/bin
    - /opt/homebrew/bin

profiles: []
  # - name: "Example"
  #   command: "openclaw --profile example run"
  #   autostart: true
  #   path: []
  #   env: {}
```

3. Opens the Settings window automatically so the user can add their first profile
4. Sidebar shows an empty state with a prompt: "No profiles configured. Add one in Settings or edit ~/.openclaw-daddy/config.yaml"

---

## Permission Inheritance Verification

The core assumption is that child processes forked from the .app inherit its TCC (Transparency, Consent, and Control) permissions. This needs verification:

**Expected to work:**
- Camera, Microphone, Location, Notifications — these are granted to the app bundle identifier, child processes inherit
- Accessibility — granted to the app binary, child processes should inherit via parent PID

**Needs runtime verification (macOS 14+):**
- Screen Recording — Apple tightened this in Sonoma. If child processes do NOT inherit, fallback strategy:
  1. Try `CGRequestScreenCaptureAccess()` from child process context
  2. If that fails, the .app main process captures and passes to child via IPC
  3. Document this as a known limitation if neither works

**Implementation approach:**
- Add a "Test Permissions" button in the Permissions panel that spawns a short-lived child process to verify each permission actually works from a subprocess context
- Log results to help diagnose permission issues

---

## Logging

**Terminal buffer:** SwiftTerm keeps an in-memory scrollback buffer (default ~10,000 lines). This is lost on app restart.

**Persistent logs (optional, per-profile):**

```yaml
profiles:
  - name: "Gateway"
    command: "openclaw --profile gateway run"
    log_file: "~/.openclaw-daddy/logs/gateway.log"  # optional, omit to disable
```

- When `log_file` is set, stdout/stderr is tee'd to the file alongside the terminal
- Log files are rotated by date: `gateway-2026-03-26.log`
- No automatic cleanup for v1; user manages disk space manually
- Default: logging disabled (no `log_file` key)

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| ⌘T | New free terminal tab |
| ⌘W | Close current tab (with confirmation if shell running) |
| ⌘1-9 | Switch to sidebar item 1-9 |
| ⌘⇧R | Restart selected profile process |
| ⌘⇧S | Stop selected profile process |
| ⌘⇧A | Start all profiles |
| ⌘, | Open Settings |
| ⌘N | Add new profile (opens Settings with new profile form) |

These follow standard macOS conventions where possible (⌘T for new tab, ⌘W for close, ⌘, for settings).

---

## App State Restoration

On quit + relaunch:

- **Restored:** which sidebar item was selected, window size/position, free terminal tab count (but not their shell state — new shells are spawned)
- **Not restored:** terminal scrollback content, in-flight shell sessions
- Implementation: `@SceneStorage` for selection state, `NSWindow.setFrameAutosaveName` for window geometry
- Profile processes are re-launched per `autostart` setting — state restoration doesn't override this

---

## Edge Cases

**openclaw crashes immediately on start (exit within 1s):**
- Keepalive still applies, but terminal shows: `"[Process exited with code N after <1s, restarting in 3s...]"`
- After 10 consecutive sub-1s crashes, escalate: show macOS notification "Gateway is crash-looping" and change sidebar status to 🟡 (warning)
- Process keeps restarting but user is made aware

**App force-killed (SIGKILL / Activity Monitor):**
- Child processes become orphans, adopted by PID 1
- On next app launch: no cleanup needed — orphan openclaw processes run independently
- Not ideal but acceptable; user can `killall openclaw` if needed
- Future: write PID file per profile to `~/.openclaw-daddy/pids/`, check on startup

**Disk full / config write failure:**
- Settings UI shows save error inline: "Failed to save config: disk full"
- Previous config remains on disk and in memory

**Multiple app instances:**
- Prevent via `NSRunningApplication` check on launch
- If already running: activate existing instance, exit new one

---

## Terminal Tab Lifecycle

**Profile terminals:**
- Cannot be closed while the process is running (close button grayed out)
- After process stops: terminal stays visible with output, user can close the tab

**Free terminals:**
- Close tab: if shell is running, show confirmation dialog "Shell is still running. Close anyway?"
- If confirmed: send SIGTERM to shell, close tab after exit
- If shell has already exited (user typed `exit`): close immediately, no prompt

---

## App Signing & Distribution

**For local development (default):**
- Build with Xcode, sign with personal team (automatic signing)
- First launch: right-click > Open to bypass Gatekeeper
- Sufficient for the primary use case (developer's own machine)

**For distribution to other machines:**
- Requires Apple Developer ID certificate ($99/year)
- Sign with `codesign --deep --force --sign "Developer ID Application: ..."`
- Notarize with `xcrun notarytool submit`
- Without notarization: recipients must manually allow in System Settings > Privacy & Security

**v1 scope:** local development signing only. Distribution signing documented but not automated.

---

## Out of Scope (for v1)

- Split pane / multi-terminal view in a single detail area
- Terminal theming / font customization
- Profile groups or dependency ordering
- Remote process management
- Auto-update mechanism
- Port conflict detection between profiles
- Automated notarization pipeline
