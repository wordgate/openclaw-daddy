# OpenclawDaddy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS .app that wraps the `openclaw` CLI for permission delegation, with multi-profile process management, embedded terminal emulation, permissions dashboard, and menu bar presence.

**Architecture:** Swift + SwiftUI app using NavigationSplitView with sidebar (profile/terminal list) and detail (SwiftTerm terminal). Processes launched via raw `forkpty` + PTY for full terminal emulation. Config stored in `~/.openclaw-daddy/config.yaml` (YAML via Yams). XcodeGen generates the `.xcodeproj` from version-controlled `project.yml`.

**Tech Stack:** Swift 5.9+, SwiftUI, SwiftTerm (SPM), Yams (SPM), XcodeGen, macOS 13+

**Spec:** `docs/superpowers/specs/2026-03-26-openclaw-daddy-macos-app-design.md`

---

## File Structure

```
openclaw-daddy/
├── project.yml                          # XcodeGen project definition
├── OpenclawDaddy/
│   ├── App/
│   │   ├── OpenclawDaddyApp.swift       # @main App entry, Scene + MenuBarExtra
│   │   └── AppDelegate.swift            # applicationShouldTerminateAfterLastWindowClosed, single-instance guard
│   ├── Models/
│   │   ├── AppConfig.swift              # Codable config model (version, global, profiles)
│   │   ├── Profile.swift                # Profile model (name, command, path, env, autostart, log_file)
│   │   └── SidebarItem.swift            # Enum: .profile(Profile) | .terminal(id)
│   ├── Services/
│   │   ├── ConfigManager.swift          # YAML load/save, FSEvents watch, debounce, validation
│   │   ├── PTYManager.swift             # forkpty wrapper, TIOCSWINSZ, fd lifecycle
│   │   ├── ProcessManager.swift         # @Observable, start/stop/restart, keepalive, crash-loop detection
│   │   ├── PermissionManager.swift      # Query/request macOS permissions, open System Settings
│   │   └── LogManager.swift             # Optional tee to log file with date rotation
│   ├── Views/
│   │   ├── MainWindow.swift             # NavigationSplitView container
│   │   ├── SidebarView.swift            # Profile list + terminal list + status indicators
│   │   ├── TerminalView.swift           # SwiftTerm NSViewRepresentable bridge
│   │   ├── TerminalToolbar.swift        # Start/Stop/Restart buttons for selected item
│   │   ├── SettingsView.swift           # TabView: Profiles editor + Permissions panel
│   │   ├── ProfileEditorView.swift      # Single profile edit form
│   │   ├── PermissionsView.swift        # Permission status rows with action buttons
│   │   ├── MenuBarView.swift            # MenuBarExtra content
│   │   └── EmptyStateView.swift         # "No profiles configured" placeholder
│   ├── Resources/
│   │   ├── Assets.xcassets/             # App icon, menu bar icon
│   │   └── Info.plist                   # Permission usage descriptions
│   └── Entitlements/
│       └── OpenclawDaddy.entitlements   # com.apple.security.app-sandbox = false
├── OpenclawDaddyTests/
│   ├── AppConfigTests.swift             # YAML serialization round-trip (incl GlobalConfig encode)
│   ├── ConfigManagerTests.swift         # Load, save, validation, defaults
│   ├── PTYManagerTests.swift            # Spawn, read/write, resize
│   └── ProcessManagerTests.swift        # Start/stop lifecycle, keepalive
# Note: PermissionManager is not unit-tested — macOS permission APIs
# require runtime context and user interaction. Verified via manual testing.
└── docs/
    └── superpowers/
        ├── specs/...
        └── plans/...
```

---

### Task 1: Project Scaffolding + XcodeGen

**Files:**
- Create: `project.yml`
- Create: `OpenclawDaddy/App/OpenclawDaddyApp.swift`
- Create: `OpenclawDaddy/App/AppDelegate.swift`
- Create: `OpenclawDaddy/Resources/Info.plist`
- Create: `OpenclawDaddy/Entitlements/OpenclawDaddy.entitlements`
- Create: `OpenclawDaddy/Resources/Assets.xcassets/Contents.json`
- Create: `OpenclawDaddy/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json`

- [ ] **Step 1: Install XcodeGen if not present**

Run: `brew list xcodegen || brew install xcodegen`
Expected: xcodegen available

- [ ] **Step 2: Create project.yml**

```yaml
# project.yml
name: OpenclawDaddy
options:
  bundleIdPrefix: com.wordgate
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true

packages:
  SwiftTerm:
    url: https://github.com/migueldeicaza/SwiftTerm
    from: "1.12.0"
  Yams:
    url: https://github.com/jpsim/Yams
    from: "5.0.0"

targets:
  OpenclawDaddy:
    type: application
    platform: macOS
    sources:
      - OpenclawDaddy
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.wordgate.OpenclawDaddy
        PRODUCT_NAME: OpenclawDaddy
        MARKETING_VERSION: "1.0.0"
        CURRENT_PROJECT_VERSION: "1"
        INFOPLIST_FILE: OpenclawDaddy/Resources/Info.plist
        SWIFT_VERSION: "5.9"
        CODE_SIGN_STYLE: Automatic
    dependencies:
      - package: SwiftTerm
      - package: Yams
    entitlements:
      path: OpenclawDaddy/Entitlements/OpenclawDaddy.entitlements

  OpenclawDaddyTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - OpenclawDaddyTests
    dependencies:
      - target: OpenclawDaddy
    settings:
      base:
        SWIFT_VERSION: "5.9"
        TEST_HOST: $(BUILT_PRODUCTS_DIR)/OpenclawDaddy.app/Contents/MacOS/OpenclawDaddy
```

- [ ] **Step 3: Create Info.plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>OpenclawDaddy</string>
    <key>CFBundleDisplayName</key>
    <string>OpenclawDaddy</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleVersion</key>
    <string>$(CURRENT_PROJECT_VERSION)</string>
    <key>CFBundleShortVersionString</key>
    <string>$(MARKETING_VERSION)</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>LSMinimumSystemVersion</key>
    <string>$(MACOSX_DEPLOYMENT_TARGET)</string>
    <key>NSCameraUsageDescription</key>
    <string>OpenclawDaddy needs camera access for openclaw processes.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>OpenclawDaddy needs microphone access for openclaw processes.</string>
    <key>NSLocationUsageDescription</key>
    <string>OpenclawDaddy needs location access for openclaw processes.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright 2026 Wordgate. All rights reserved.</string>
</dict>
</plist>
```

- [ ] **Step 4: Create entitlements (sandbox disabled)**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
```

- [ ] **Step 5: Create minimal App entry point**

```swift
// OpenclawDaddy/App/OpenclawDaddyApp.swift
import SwiftUI

@main
struct OpenclawDaddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            Text("OpenclawDaddy — Loading...")
                .frame(minWidth: 800, minHeight: 500)
        }
        .defaultSize(width: 1000, height: 600)
    }
}
```

```swift
// OpenclawDaddy/App/AppDelegate.swift
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    var processManager: ProcessManager?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Single-instance guard
        let runningApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? ""
        )
        if runningApps.count > 1 {
            runningApps.first { $0 != NSRunningApplication.current }?.activate()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let processManager else { return .terminateNow }
        // Graceful shutdown: SIGTERM all, wait up to 5s, SIGKILL, then allow exit
        processManager.stopAll {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
```

- [ ] **Step 6: Create Assets.xcassets structure**

```json
// OpenclawDaddy/Resources/Assets.xcassets/Contents.json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

```json
// OpenclawDaddy/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json
{
  "images" : [
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

- [ ] **Step 7: Create test directory placeholder**

```swift
// OpenclawDaddyTests/OpenclawDaddyTests.swift
import XCTest

final class OpenclawDaddyTests: XCTestCase {
    func testPlaceholder() {
        XCTAssertTrue(true, "Project builds and tests run")
    }
}
```

- [ ] **Step 8: Generate Xcode project and verify build**

Run: `cd /Users/david/projects/wordgate/openclaw-daddy && xcodegen generate`
Expected: `Generated project: OpenclawDaddy.xcodeproj`

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddy -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddyTests -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`

- [ ] **Step 9: Commit**

```bash
echo "*.xcodeproj/xcuserdata/" >> .gitignore
echo ".build/" >> .gitignore
echo "DerivedData/" >> .gitignore
git add .gitignore project.yml OpenclawDaddy/ OpenclawDaddyTests/
git commit -m "feat: scaffold Xcode project with XcodeGen, SwiftTerm, Yams"
```

---

### Task 2: Data Models (Profile + AppConfig)

**Files:**
- Create: `OpenclawDaddy/Models/Profile.swift`
- Create: `OpenclawDaddy/Models/AppConfig.swift`
- Create: `OpenclawDaddy/Models/SidebarItem.swift`
- Create: `OpenclawDaddyTests/AppConfigTests.swift`

- [ ] **Step 1: Write failing tests for Profile and AppConfig YAML round-trip**

```swift
// OpenclawDaddyTests/AppConfigTests.swift
import XCTest
import Yams
@testable import OpenclawDaddy

final class AppConfigTests: XCTestCase {

    // MARK: - Profile Tests

    func testProfileDecodingFromYAML() throws {
        let yaml = """
        name: "Gateway"
        command: "openclaw --profile gateway run"
        autostart: true
        path:
          - /usr/local/bin
        env:
          OPENCLAW_PORT: "8080"
        """
        let profile = try YAMLDecoder().decode(Profile.self, from: yaml)
        XCTAssertEqual(profile.name, "Gateway")
        XCTAssertEqual(profile.command, "openclaw --profile gateway run")
        XCTAssertTrue(profile.autostart)
        XCTAssertEqual(profile.path, ["/usr/local/bin"])
        XCTAssertEqual(profile.env, ["OPENCLAW_PORT": "8080"])
        XCTAssertNil(profile.logFile)
    }

    func testProfileDecodingMinimalFields() throws {
        let yaml = """
        name: "Worker"
        command: "openclaw --profile worker run"
        """
        let profile = try YAMLDecoder().decode(Profile.self, from: yaml)
        XCTAssertEqual(profile.name, "Worker")
        XCTAssertFalse(profile.autostart)
        XCTAssertEqual(profile.path, [])
        XCTAssertEqual(profile.env, [:])
    }

    func testProfileEncodingRoundTrip() throws {
        let profile = Profile(
            name: "Test",
            command: "echo hello",
            autostart: true,
            path: ["/opt/bin"],
            env: ["KEY": "VAL"],
            logFile: "~/.openclaw-daddy/logs/test.log"
        )
        let yaml = try YAMLEncoder().encode(profile)
        let decoded = try YAMLDecoder().decode(Profile.self, from: yaml)
        XCTAssertEqual(profile.name, decoded.name)
        XCTAssertEqual(profile.command, decoded.command)
        XCTAssertEqual(profile.autostart, decoded.autostart)
        XCTAssertEqual(profile.path, decoded.path)
        XCTAssertEqual(profile.env, decoded.env)
        XCTAssertEqual(profile.logFile, decoded.logFile)
    }

    // MARK: - AppConfig Tests

    func testAppConfigDecodingFullYAML() throws {
        let yaml = """
        version: 1
        global:
          restart_delay: 3
          extra_path:
            - /usr/local/bin
            - /opt/homebrew/bin
        profiles:
          - name: "Gateway"
            command: "openclaw --profile gateway run"
            autostart: true
        """
        let config = try YAMLDecoder().decode(AppConfig.self, from: yaml)
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.global.restartDelay, 3)
        XCTAssertEqual(config.global.extraPath, ["/usr/local/bin", "/opt/homebrew/bin"])
        XCTAssertEqual(config.profiles.count, 1)
        XCTAssertEqual(config.profiles[0].name, "Gateway")
    }

    func testAppConfigDefaultVersion() throws {
        let yaml = """
        global:
          restart_delay: 5
        profiles: []
        """
        let config = try YAMLDecoder().decode(AppConfig.self, from: yaml)
        XCTAssertEqual(config.version, 1)
    }

    func testAppConfigDefaultConfig() {
        let config = AppConfig.makeDefault()
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.global.restartDelay, 3)
        XCTAssertTrue(config.global.extraPath.contains("/usr/local/bin"))
        XCTAssertTrue(config.global.extraPath.contains("/opt/homebrew/bin"))
        XCTAssertTrue(config.profiles.isEmpty)
    }

    func testAppConfigEncodingRoundTrip() throws {
        let config = AppConfig.makeDefault()
        let yaml = try YAMLEncoder().encode(config)
        let decoded = try YAMLDecoder().decode(AppConfig.self, from: yaml)
        XCTAssertEqual(config.version, decoded.version)
        XCTAssertEqual(config.global.restartDelay, decoded.global.restartDelay)
    }

    func testGlobalConfigEncodesToSnakeCase() throws {
        let global = GlobalConfig(restartDelay: 5, extraPath: ["/test"])
        let yaml = try YAMLEncoder().encode(global)
        XCTAssertTrue(yaml.contains("restart_delay"), "Should encode as snake_case, got: \(yaml)")
        XCTAssertTrue(yaml.contains("extra_path"), "Should encode as snake_case, got: \(yaml)")
        XCTAssertFalse(yaml.contains("restartDelay"), "Should NOT use camelCase")
    }

    // MARK: - Validation Tests

    func testDuplicateProfileNamesGetSuffix() {
        var config = AppConfig.makeDefault()
        config.profiles = [
            Profile(name: "Gateway", command: "cmd1"),
            Profile(name: "Gateway", command: "cmd2"),
            Profile(name: "Gateway", command: "cmd3"),
        ]
        let resolved = config.resolvedProfiles()
        XCTAssertEqual(resolved[0].name, "Gateway")
        XCTAssertEqual(resolved[1].name, "Gateway (2)")
        XCTAssertEqual(resolved[2].name, "Gateway (3)")
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddyTests -destination 'platform=macOS' test 2>&1 | grep -E '(error|FAIL|BUILD)'`
Expected: FAIL — `Profile`, `AppConfig` not defined

- [ ] **Step 3: Implement Profile model**

```swift
// OpenclawDaddy/Models/Profile.swift
import Foundation

struct Profile: Codable, Identifiable, Equatable {
    var id: UUID

    var name: String
    var command: String
    var autostart: Bool
    var path: [String]
    var env: [String: String]
    var logFile: String?

    enum CodingKeys: String, CodingKey {
        case name, command, autostart, path, env
        case logFile = "log_file"
    }

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        autostart: Bool = false,
        path: [String] = [],
        env: [String: String] = [:],
        logFile: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.autostart = autostart
        self.path = path
        self.env = env
        self.logFile = logFile
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.command = try container.decode(String.self, forKey: .command)
        self.autostart = try container.decodeIfPresent(Bool.self, forKey: .autostart) ?? false
        self.path = try container.decodeIfPresent([String].self, forKey: .path) ?? []
        self.env = try container.decodeIfPresent([String: String].self, forKey: .env) ?? [:]
        self.logFile = try container.decodeIfPresent(String.self, forKey: .logFile)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(command, forKey: .command)
        try container.encode(autostart, forKey: .autostart)
        try container.encode(path, forKey: .path)
        if !env.isEmpty {
            try container.encode(env, forKey: .env)
        }
        try container.encodeIfPresent(logFile, forKey: .logFile)
    }
}
```

- [ ] **Step 4: Implement AppConfig model**

```swift
// OpenclawDaddy/Models/AppConfig.swift
import Foundation

struct GlobalConfig: Codable, Equatable {
    var restartDelay: Int
    var extraPath: [String]

    enum CodingKeys: String, CodingKey {
        case restartDelay = "restart_delay"
        case extraPath = "extra_path"
    }

    init(restartDelay: Int = 3, extraPath: [String] = []) {
        self.restartDelay = restartDelay
        self.extraPath = extraPath
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.restartDelay = try container.decodeIfPresent(Int.self, forKey: .restartDelay) ?? 3
        self.extraPath = try container.decodeIfPresent([String].self, forKey: .extraPath) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(restartDelay, forKey: .restartDelay)
        try container.encode(extraPath, forKey: .extraPath)
    }
}

struct AppConfig: Codable, Equatable {
    var version: Int
    var global: GlobalConfig
    var profiles: [Profile]

    static let supportedVersion = 1

    init(version: Int = 1, global: GlobalConfig = GlobalConfig(), profiles: [Profile] = []) {
        self.version = version
        self.global = global
        self.profiles = profiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        self.global = try container.decodeIfPresent(GlobalConfig.self, forKey: .global) ?? GlobalConfig()
        self.profiles = try container.decodeIfPresent([Profile].self, forKey: .profiles) ?? []
    }

    static func makeDefault() -> AppConfig {
        AppConfig(
            version: 1,
            global: GlobalConfig(
                restartDelay: 3,
                extraPath: ["/usr/local/bin", "/opt/homebrew/bin"]
            ),
            profiles: []
        )
    }

    /// Returns profiles with duplicate names resolved by appending suffixes
    func resolvedProfiles() -> [Profile] {
        var nameCounts: [String: Int] = [:]
        return profiles.map { profile in
            var resolved = profile
            let count = nameCounts[profile.name, default: 0]
            nameCounts[profile.name] = count + 1
            if count > 0 {
                resolved.name = "\(profile.name) (\(count + 1))"
            }
            return resolved
        }
    }
}
```

- [ ] **Step 5: Implement SidebarItem model**

```swift
// OpenclawDaddy/Models/SidebarItem.swift
import Foundation

enum ProcessStatus: Equatable {
    case stopped
    case running
    case crashed
    case crashLooping
}

enum SidebarItem: Identifiable, Equatable {
    case profile(Profile, ProcessStatus)
    case terminal(UUID)

    var id: String {
        switch self {
        case .profile(let profile, _):
            return "profile-\(profile.id)"
        case .terminal(let id):
            return "terminal-\(id)"
        }
    }

    var displayName: String {
        switch self {
        case .profile(let profile, _):
            return profile.name
        case .terminal(let id):
            return "Shell \(id.uuidString.prefix(4))"
        }
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddyTests -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
git add OpenclawDaddy/Models/ OpenclawDaddyTests/AppConfigTests.swift
git commit -m "feat: add Profile, AppConfig, SidebarItem models with YAML serialization"
```

---

### Task 3: ConfigManager (Load / Save / Watch)

**Files:**
- Create: `OpenclawDaddy/Services/ConfigManager.swift`
- Create: `OpenclawDaddyTests/ConfigManagerTests.swift`

- [ ] **Step 1: Write failing tests for ConfigManager**

```swift
// OpenclawDaddyTests/ConfigManagerTests.swift
import XCTest
@testable import OpenclawDaddy

final class ConfigManagerTests: XCTestCase {
    var tempDir: URL!
    var configPath: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("openclaw-daddy-test-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        configPath = tempDir.appendingPathComponent("config.yaml")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }

    func testLoadCreatesDefaultWhenFileMissing() throws {
        let manager = ConfigManager(configDirectory: tempDir)
        let config = try manager.load()
        XCTAssertEqual(config.version, 1)
        XCTAssertEqual(config.global.restartDelay, 3)
        XCTAssertTrue(config.profiles.isEmpty)
        // File should now exist
        XCTAssertTrue(FileManager.default.fileExists(atPath: configPath.path))
    }

    func testLoadParsesExistingConfig() throws {
        let yaml = """
        version: 1
        global:
          restart_delay: 5
          extra_path:
            - /custom/bin
        profiles:
          - name: "Test"
            command: "echo hello"
            autostart: true
        """
        try yaml.write(to: configPath, atomically: true, encoding: .utf8)
        let manager = ConfigManager(configDirectory: tempDir)
        let config = try manager.load()
        XCTAssertEqual(config.global.restartDelay, 5)
        XCTAssertEqual(config.profiles.count, 1)
        XCTAssertEqual(config.profiles[0].name, "Test")
    }

    func testLoadRejectsUnsupportedVersion() throws {
        let yaml = """
        version: 99
        global:
          restart_delay: 3
        profiles: []
        """
        try yaml.write(to: configPath, atomically: true, encoding: .utf8)
        let manager = ConfigManager(configDirectory: tempDir)
        XCTAssertThrowsError(try manager.load()) { error in
            XCTAssertTrue("\(error)".contains("update"), "Error should mention updating the app")
        }
    }

    func testSaveWritesValidYAML() throws {
        let manager = ConfigManager(configDirectory: tempDir)
        var config = AppConfig.makeDefault()
        config.profiles = [Profile(name: "Saved", command: "echo saved", autostart: true)]
        try manager.save(config)

        let loaded = try manager.load()
        XCTAssertEqual(loaded.profiles.count, 1)
        XCTAssertEqual(loaded.profiles[0].name, "Saved")
    }

    func testLoadSkipsProfilesMissingRequiredFields() throws {
        // YAML with a profile missing 'command' field
        let yaml = """
        version: 1
        global:
          restart_delay: 3
        profiles:
          - name: "Valid"
            command: "echo valid"
          - name: "Invalid"
        """
        try yaml.write(to: configPath, atomically: true, encoding: .utf8)
        let manager = ConfigManager(configDirectory: tempDir)
        let config = try manager.load()
        // Invalid profile should be skipped
        XCTAssertEqual(config.profiles.count, 1)
        XCTAssertEqual(config.profiles[0].name, "Valid")
    }

    func testBuildPathForProfile() {
        let config = AppConfig(
            global: GlobalConfig(extraPath: ["/global/bin"]),
            profiles: [Profile(name: "T", command: "cmd", path: ["/profile/bin"])]
        )
        let manager = ConfigManager(configDirectory: tempDir)
        let path = manager.buildPath(for: config.profiles[0], global: config.global)
        // Should be: system PATH + /global/bin + /profile/bin
        XCTAssertTrue(path.contains("/global/bin"))
        XCTAssertTrue(path.contains("/profile/bin"))
        XCTAssertTrue(path.contains("/usr/bin")) // system PATH should be included
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddyTests -destination 'platform=macOS' test 2>&1 | grep -E '(error|FAIL)'`
Expected: FAIL — `ConfigManager` not defined

- [ ] **Step 3: Implement ConfigManager**

```swift
// OpenclawDaddy/Services/ConfigManager.swift
import Foundation
import Yams

enum ConfigError: LocalizedError {
    case unsupportedVersion(Int)
    case parseError(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let v):
            return "Config version \(v) is not supported. Please update OpenclawDaddy."
        case .parseError(let msg):
            return "Failed to parse config: \(msg)"
        case .saveFailed(let msg):
            return "Failed to save config: \(msg)"
        }
    }
}

@Observable
final class ConfigManager {
    private let configDirectory: URL
    private var configURL: URL { configDirectory.appendingPathComponent("config.yaml") }
    private var fileWatchSource: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?

    private(set) var config: AppConfig = .makeDefault()
    private(set) var validationWarnings: [String] = []

    var onConfigReloaded: ((AppConfig) -> Void)?

    init(configDirectory: URL? = nil) {
        if let dir = configDirectory {
            self.configDirectory = dir
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            self.configDirectory = home.appendingPathComponent(".openclaw-daddy")
        }
    }

    @discardableResult
    func load() throws -> AppConfig {
        let fm = FileManager.default

        // Create directory if needed
        if !fm.fileExists(atPath: configDirectory.path) {
            try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        }

        // Generate default if missing
        if !fm.fileExists(atPath: configURL.path) {
            let defaultConfig = AppConfig.makeDefault()
            try save(defaultConfig)
            self.config = defaultConfig
            return defaultConfig
        }

        let yamlString = try String(contentsOf: configURL, encoding: .utf8)

        // First pass: check version
        if let rawDict = try Yams.load(yaml: yamlString) as? [String: Any],
           let version = rawDict["version"] as? Int,
           version > AppConfig.supportedVersion {
            throw ConfigError.unsupportedVersion(version)
        }

        // Decode with lenient profile parsing
        var warnings: [String] = []
        let config = try decodeLenient(yamlString: yamlString, warnings: &warnings)
        self.validationWarnings = warnings
        self.config = config
        return config
    }

    func save(_ config: AppConfig) throws {
        let encoder = YAMLEncoder()
        let yamlString = try encoder.encode(config)
        do {
            try yamlString.write(to: configURL, atomically: true, encoding: .utf8)
            self.config = config
        } catch {
            throw ConfigError.saveFailed(error.localizedDescription)
        }
    }

    func buildPath(for profile: Profile, global: GlobalConfig) -> String {
        let systemPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let components = systemPath.split(separator: ":").map(String.init)
            + global.extraPath
            + profile.path
        return components.joined(separator: ":")
    }

    // MARK: - File Watching

    func startWatching() {
        let fd = open(configURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.handleFileChange()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.fileWatchSource = source
    }

    func stopWatching() {
        fileWatchSource?.cancel()
        fileWatchSource = nil
    }

    private func handleFileChange() {
        debounceWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let newConfig = try self.load()
                self.onConfigReloaded?(newConfig)
            } catch {
                self.validationWarnings.append("Reload failed: \(error.localizedDescription)")
            }
        }
        debounceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    // MARK: - Lenient Decoding

    private func decodeLenient(yamlString: String, warnings: inout [String]) throws -> AppConfig {
        guard let rawDict = try Yams.load(yaml: yamlString) as? [String: Any] else {
            throw ConfigError.parseError("Root is not a dictionary")
        }

        let version = rawDict["version"] as? Int ?? 1

        // Decode global
        var global = GlobalConfig()
        if let globalDict = rawDict["global"] as? [String: Any] {
            global.restartDelay = globalDict["restart_delay"] as? Int ?? 3
            global.extraPath = globalDict["extra_path"] as? [String] ?? []
        }

        // Decode profiles leniently — skip invalid ones
        var profiles: [Profile] = []
        if let profilesArray = rawDict["profiles"] as? [[String: Any]] {
            for (index, dict) in profilesArray.enumerated() {
                guard let name = dict["name"] as? String else {
                    warnings.append("Profile at index \(index): missing 'name', skipped")
                    continue
                }
                guard let command = dict["command"] as? String else {
                    warnings.append("Profile '\(name)': missing 'command', skipped")
                    continue
                }
                let profile = Profile(
                    name: name,
                    command: command,
                    autostart: dict["autostart"] as? Bool ?? false,
                    path: dict["path"] as? [String] ?? [],
                    env: dict["env"] as? [String: String] ?? [:],
                    logFile: dict["log_file"] as? String
                )
                profiles.append(profile)
            }
        }

        return AppConfig(version: version, global: global, profiles: profiles)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddyTests -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add OpenclawDaddy/Services/ConfigManager.swift OpenclawDaddyTests/ConfigManagerTests.swift
git commit -m "feat: add ConfigManager with YAML load/save, validation, FSEvents watch"
```

---

### Task 4: PTYManager (forkpty Wrapper)

**Files:**
- Create: `OpenclawDaddy/Services/PTYManager.swift`
- Create: `OpenclawDaddyTests/PTYManagerTests.swift`

- [ ] **Step 1: Write failing tests for PTYManager**

```swift
// OpenclawDaddyTests/PTYManagerTests.swift
import XCTest
@testable import OpenclawDaddy

final class PTYManagerTests: XCTestCase {

    func testSpawnProcessAndReadOutput() throws {
        let expectation = expectation(description: "Read output from spawned process")
        let pty = try PTYManager.spawn(
            command: "/bin/echo",
            arguments: ["hello-pty-test"],
            environment: ["PATH": "/usr/bin:/bin"],
            workingDirectory: "/tmp"
        )

        XCTAssertTrue(pty.pid > 0, "PID should be positive")
        XCTAssertTrue(pty.masterFd >= 0, "Master fd should be valid")

        // Read output from PTY
        DispatchQueue.global().async {
            var buffer = [UInt8](repeating: 0, count: 1024)
            let bytesRead = read(pty.masterFd, &buffer, buffer.count)
            if bytesRead > 0 {
                let output = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
                if output.contains("hello-pty-test") {
                    expectation.fulfill()
                }
            }
        }

        waitForExpectations(timeout: 5)
        pty.cleanup()
    }

    func testSpawnProcessWriteInput() throws {
        // Spawn cat which echoes stdin to stdout
        let pty = try PTYManager.spawn(
            command: "/bin/cat",
            arguments: [],
            environment: ["PATH": "/usr/bin:/bin"],
            workingDirectory: "/tmp"
        )

        let testString = "input-test\n"
        testString.withCString { ptr in
            write(pty.masterFd, ptr, strlen(ptr))
        }

        let expectation = expectation(description: "Read echoed input")
        DispatchQueue.global().async {
            var buffer = [UInt8](repeating: 0, count: 1024)
            var accumulated = ""
            for _ in 0..<10 {
                let bytesRead = read(pty.masterFd, &buffer, buffer.count)
                if bytesRead > 0 {
                    accumulated += String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""
                    if accumulated.contains("input-test") {
                        expectation.fulfill()
                        return
                    }
                }
            }
        }

        waitForExpectations(timeout: 5)
        kill(pty.pid, SIGTERM)
        pty.cleanup()
    }

    func testResizeTerminal() throws {
        let pty = try PTYManager.spawn(
            command: "/bin/cat",
            arguments: [],
            environment: ["PATH": "/usr/bin:/bin"],
            workingDirectory: "/tmp"
        )

        // Should not crash
        PTYManager.resize(masterFd: pty.masterFd, cols: 120, rows: 40)

        // Verify via ioctl
        var size = winsize()
        ioctl(pty.masterFd, TIOCGWINSZ, &size)
        XCTAssertEqual(size.ws_col, 120)
        XCTAssertEqual(size.ws_row, 40)

        kill(pty.pid, SIGTERM)
        pty.cleanup()
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddyTests -destination 'platform=macOS' test 2>&1 | grep -E '(error|FAIL)'`
Expected: FAIL — `PTYManager` not defined

- [ ] **Step 3: Implement PTYManager**

```swift
// OpenclawDaddy/Services/PTYManager.swift
import Foundation

struct PTYProcess {
    let pid: pid_t
    let masterFd: Int32

    func cleanup() {
        close(masterFd)
    }
}

enum PTYError: LocalizedError {
    case forkptyFailed
    case execFailed(String)

    var errorDescription: String? {
        switch self {
        case .forkptyFailed:
            return "forkpty() failed: \(String(cString: strerror(errno)))"
        case .execFailed(let cmd):
            return "Failed to exec: \(cmd)"
        }
    }
}

enum PTYManager {

    /// Spawn a new process in a pseudo-terminal.
    /// Returns the PTY master fd and child PID.
    static func spawn(
        command: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: String = "/",
        initialCols: UInt16 = 80,
        initialRows: UInt16 = 24
    ) throws -> PTYProcess {
        var masterFd: Int32 = -1
        var winSize = winsize(
            ws_row: initialRows,
            ws_col: initialCols,
            ws_xpixel: 0,
            ws_ypixel: 0
        )

        let pid = forkpty(&masterFd, nil, nil, &winSize)

        if pid < 0 {
            throw PTYError.forkptyFailed
        }

        if pid == 0 {
            // Child process
            chdir(workingDirectory)

            // Set environment
            for (key, value) in environment {
                setenv(key, value, 1)
            }
            setenv("TERM", "xterm-256color", 1)

            // Build argv
            let argv = [command] + arguments
            let cArgs = argv.map { strdup($0) } + [nil]
            defer { cArgs.forEach { free($0) } }

            execvp(command, cArgs)
            // If we get here, exec failed
            _exit(127)
        }

        // Parent process
        return PTYProcess(pid: pid, masterFd: masterFd)
    }

    /// Convenience: spawn via /bin/bash -l -c "command"
    static func spawnShell(
        shellCommand: String,
        environment: [String: String],
        workingDirectory: String = "/"
    ) throws -> PTYProcess {
        try spawn(
            command: "/bin/bash",
            arguments: ["-l", "-c", shellCommand],
            environment: environment,
            workingDirectory: workingDirectory
        )
    }

    /// Spawn an interactive login shell (for free terminal tabs)
    static func spawnInteractiveShell(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> PTYProcess {
        let shell = environment["SHELL"] ?? "/bin/zsh"
        return try spawn(
            command: shell,
            arguments: ["-l"],
            environment: environment,
            workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
        )
    }

    /// Resize the terminal window size for the PTY
    static func resize(masterFd: Int32, cols: UInt16, rows: UInt16) {
        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        ioctl(masterFd, TIOCSWINSZ, &size)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddyTests -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add OpenclawDaddy/Services/PTYManager.swift OpenclawDaddyTests/PTYManagerTests.swift
git commit -m "feat: add PTYManager with forkpty spawn, resize, interactive shell"
```

---

### Task 5: ProcessManager (Lifecycle + Keepalive)

**Files:**
- Create: `OpenclawDaddy/Services/ProcessManager.swift`
- Create: `OpenclawDaddyTests/ProcessManagerTests.swift`

- [ ] **Step 1: Write failing tests for ProcessManager**

```swift
// OpenclawDaddyTests/ProcessManagerTests.swift
import XCTest
@testable import OpenclawDaddy

final class ProcessManagerTests: XCTestCase {

    func testStartProfileProcess() throws {
        let profile = Profile(name: "Test", command: "echo started", autostart: false)
        let manager = ProcessManager(restartDelay: 1)

        let started = expectation(description: "Process started")
        manager.startProfile(profile, path: "/usr/bin:/bin") {
            started.fulfill()
        }
        waitForExpectations(timeout: 5)

        let status = manager.status(for: profile.id)
        // echo exits immediately with 0, so it should be stopped (not crashed)
        // Give it a moment to exit
        Thread.sleep(forTimeInterval: 0.5)
        let finalStatus = manager.status(for: profile.id)
        XCTAssertEqual(finalStatus, .stopped)
    }

    func testStopProfileProcess() throws {
        // Use 'sleep 60' so it stays running
        let profile = Profile(name: "Sleeper", command: "sleep 60", autostart: false)
        let manager = ProcessManager(restartDelay: 1)

        let started = expectation(description: "Process started")
        manager.startProfile(profile, path: "/usr/bin:/bin") {
            started.fulfill()
        }
        waitForExpectations(timeout: 5)

        XCTAssertEqual(manager.status(for: profile.id), .running)

        let stopped = expectation(description: "Process stopped")
        manager.stopProfile(profile.id) {
            stopped.fulfill()
        }
        waitForExpectations(timeout: 10)

        XCTAssertEqual(manager.status(for: profile.id), .stopped)
    }

    func testKeepaliveRestartsOnCrash() throws {
        // Use 'exit 1' to simulate crash
        let profile = Profile(name: "Crasher", command: "exit 1", autostart: false)
        let manager = ProcessManager(restartDelay: 1)

        var restartCount = 0
        let restarted = expectation(description: "Process restarted at least once")

        manager.onProcessRestarted = { id in
            if id == profile.id {
                restartCount += 1
                if restartCount >= 1 {
                    restarted.fulfill()
                }
            }
        }

        manager.startProfile(profile, path: "/usr/bin:/bin")
        waitForExpectations(timeout: 10)

        // Stop to prevent infinite restarts
        manager.stopProfile(profile.id)
        XCTAssertGreaterThanOrEqual(restartCount, 1)
    }

    func testNormalExitDoesNotRestart() throws {
        // exit 0 should NOT trigger keepalive
        let profile = Profile(name: "CleanExit", command: "exit 0", autostart: false)
        let manager = ProcessManager(restartDelay: 1)

        var restarted = false
        manager.onProcessRestarted = { _ in restarted = true }

        manager.startProfile(profile, path: "/usr/bin:/bin")

        // Wait enough time for a potential restart
        Thread.sleep(forTimeInterval: 3)

        XCTAssertFalse(restarted, "Normal exit (0) should not trigger restart")
        XCTAssertEqual(manager.status(for: profile.id), .stopped)
    }

    func testGetMasterFd() throws {
        let profile = Profile(name: "FdTest", command: "sleep 60", autostart: false)
        let manager = ProcessManager(restartDelay: 1)

        let started = expectation(description: "started")
        manager.startProfile(profile, path: "/usr/bin:/bin") { started.fulfill() }
        waitForExpectations(timeout: 5)

        let fd = manager.masterFd(for: profile.id)
        XCTAssertNotNil(fd)
        XCTAssertTrue(fd! >= 0)

        manager.stopProfile(profile.id)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddyTests -destination 'platform=macOS' test 2>&1 | grep -E '(error|FAIL)'`
Expected: FAIL — `ProcessManager` not defined

- [ ] **Step 3: Implement ProcessManager**

```swift
// OpenclawDaddy/Services/ProcessManager.swift
import Foundation

@Observable
final class ProcessManager {
    struct ManagedProcess {
        let profileId: UUID
        var pty: PTYProcess
        var status: ProcessStatus
        var processSource: DispatchSourceProcess?
        var consecutiveQuickCrashes: Int = 0
        var lastStartTime: Date = Date()
        var isStoppedByUser: Bool = false
    }

    private var processes: [UUID: ManagedProcess] = [:]
    private let restartDelay: Int
    private let queue = DispatchQueue(label: "com.wordgate.openclaw-daddy.process-manager")

    // Incremented on every state change to force SwiftUI re-render.
    // @Observable may miss nested dict mutations — this guarantees observation.
    private(set) var stateVersion: Int = 0

    var onProcessRestarted: ((UUID) -> Void)?
    var onCrashLoop: ((UUID, String) -> Void)?

    init(restartDelay: Int = 3) {
        self.restartDelay = restartDelay
    }

    private func notifyStateChange() {
        stateVersion += 1
    }

    func status(for profileId: UUID) -> ProcessStatus {
        // Touch stateVersion to register observation
        _ = stateVersion
        return processes[profileId]?.status ?? .stopped
    }

    func masterFd(for profileId: UUID) -> Int32? {
        _ = stateVersion
        return processes[profileId]?.pty.masterFd
    }

    var allProfileIds: [UUID] {
        Array(processes.keys)
    }

    func startProfile(
        _ profile: Profile,
        path: String,
        env: [String: String] = [:],
        onStarted: (() -> Void)? = nil
    ) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = path
                for (key, value) in profile.env.merging(env) { _, new in new } {
                    environment[key] = value
                }

                let pty = try PTYManager.spawnShell(
                    shellCommand: profile.command,
                    environment: environment,
                    workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
                )

                var managed = ManagedProcess(
                    profileId: profile.id,
                    pty: pty,
                    status: .running,
                    lastStartTime: Date()
                )

                // Monitor process exit
                let source = DispatchSource.makeProcessSource(
                    identifier: pty.pid,
                    eventMask: .exit,
                    queue: self.queue
                )
                source.setEventHandler { [weak self] in
                    self?.handleProcessExit(profileId: profile.id, profile: profile, path: path)
                }
                source.resume()
                managed.processSource = source

                DispatchQueue.main.async {
                    self.processes[profile.id] = managed
                    self.notifyStateChange()
                    onStarted?()
                }
            } catch {
                DispatchQueue.main.async {
                    self.processes[profile.id] = ManagedProcess(
                        profileId: profile.id,
                        pty: PTYProcess(pid: -1, masterFd: -1),
                        status: .crashed
                    )
                    self.notifyStateChange()
                }
            }
        }
    }

    func stopProfile(_ profileId: UUID, onStopped: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self, var managed = self.processes[profileId] else {
                DispatchQueue.main.async { onStopped?() }
                return
            }

            managed.isStoppedByUser = true
            managed.processSource?.cancel()
            managed.processSource = nil

            let pid = managed.pty.pid
            if pid > 0 {
                kill(pid, SIGTERM)

                // Wait up to 5 seconds for graceful exit
                self.queue.asyncAfter(deadline: .now() + 5) { [weak self] in
                    var status: Int32 = 0
                    let result = waitpid(pid, &status, WNOHANG)
                    if result == 0 {
                        // Still running, force kill — SIGKILL cannot be ignored,
                        // so fire-and-forget + WNOHANG reap is sufficient
                        kill(pid, SIGKILL)
                        waitpid(pid, &status, WNOHANG)
                    }
                    managed.pty.cleanup()
                    DispatchQueue.main.async {
                        self?.processes[profileId]?.status = .stopped
                        self?.processes[profileId]?.isStoppedByUser = true
                        self?.notifyStateChange()
                        onStopped?()
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.processes[profileId]?.status = .stopped
                    onStopped?()
                }
            }
        }
    }

    func restartProfile(_ profile: Profile, path: String) {
        stopProfile(profile.id) { [weak self] in
            self?.startProfile(profile, path: path)
        }
    }

    func stopAll(onComplete: (() -> Void)? = nil) {
        let group = DispatchGroup()
        for id in Array(processes.keys) {
            group.enter()
            stopProfile(id) { group.leave() }
        }
        group.notify(queue: .main) { onComplete?() }
    }

    // MARK: - Terminal Tabs (no keepalive)

    func spawnTerminal() -> (UUID, Int32)? {
        let id = UUID()
        do {
            let pty = try PTYManager.spawnInteractiveShell()
            let managed = ManagedProcess(
                profileId: id,
                pty: pty,
                status: .running
            )
            processes[id] = managed
            return (id, pty.masterFd)
        } catch {
            return nil
        }
    }

    func closeTerminal(_ id: UUID) {
        guard let managed = processes[id] else { return }
        if managed.pty.pid > 0 {
            kill(managed.pty.pid, SIGTERM)
        }
        managed.pty.cleanup()
        managed.processSource?.cancel()
        processes.removeValue(forKey: id)
    }

    func isTerminalRunning(_ id: UUID) -> Bool {
        guard let managed = processes[id], managed.pty.pid > 0 else { return false }
        var status: Int32 = 0
        let result = waitpid(managed.pty.pid, &status, WNOHANG)
        return result == 0
    }

    // MARK: - Private

    private func handleProcessExit(profileId: UUID, profile: Profile, path: String) {
        guard var managed = processes[profileId] else { return }

        // Reap child
        var status: Int32 = 0
        waitpid(managed.pty.pid, &status, 0)

        let exitCode = WIFEXITED(status) ? Int(WEXITSTATUS(status)) : -1
        let wasSignaled = WIFSIGNALED(status)

        // User-initiated stop — do not restart
        if managed.isStoppedByUser {
            return
        }

        // Normal exit (code 0) — stop, no restart
        if exitCode == 0 && !wasSignaled {
            DispatchQueue.main.async { [weak self] in
                self?.processes[profileId]?.status = .stopped
                self?.notifyStateChange()
            }
            return
        }

        // Abnormal exit — keepalive
        let elapsed = Date().timeIntervalSince(managed.lastStartTime)
        if elapsed < 1.0 {
            managed.consecutiveQuickCrashes += 1
        } else {
            managed.consecutiveQuickCrashes = 0
        }

        let isCrashLooping = managed.consecutiveQuickCrashes >= 10

        DispatchQueue.main.async { [weak self] in
            self?.processes[profileId]?.status = isCrashLooping ? .crashLooping : .crashed
            self?.processes[profileId]?.consecutiveQuickCrashes = managed.consecutiveQuickCrashes

            if isCrashLooping {
                self?.onCrashLoop?(profileId, profile.name)
            }
        }

        // Restart after delay
        let delay = self.restartDelay
        queue.asyncAfter(deadline: .now() + .seconds(delay)) { [weak self] in
            guard let self else { return }
            guard let current = self.processes[profileId],
                  !current.isStoppedByUser else { return }

            current.pty.cleanup()
            current.processSource?.cancel()

            // Re-spawn
            do {
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = path
                for (key, value) in profile.env {
                    environment[key] = value
                }

                let newPty = try PTYManager.spawnShell(
                    shellCommand: profile.command,
                    environment: environment
                )

                let source = DispatchSource.makeProcessSource(
                    identifier: newPty.pid,
                    eventMask: .exit,
                    queue: self.queue
                )
                source.setEventHandler { [weak self] in
                    self?.handleProcessExit(profileId: profileId, profile: profile, path: path)
                }
                source.resume()

                DispatchQueue.main.async { [weak self] in
                    self?.processes[profileId]?.pty = newPty
                    self?.processes[profileId]?.status = .running
                    self?.processes[profileId]?.processSource = source
                    self?.processes[profileId]?.lastStartTime = Date()
                    self?.notifyStateChange()
                    self?.onProcessRestarted?(profileId)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.processes[profileId]?.status = .crashed
                    self?.notifyStateChange()
                }
            }
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddyTests -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add OpenclawDaddy/Services/ProcessManager.swift OpenclawDaddyTests/ProcessManagerTests.swift
git commit -m "feat: add ProcessManager with keepalive, crash-loop detection, terminal tabs"
```

---

### Task 6: TerminalView (SwiftTerm Bridge)

**Files:**
- Create: `OpenclawDaddy/Views/TerminalView.swift`

No unit tests for this — it's an NSViewRepresentable bridge. Verified by visual inspection when integrated.

- [ ] **Step 1: Implement TerminalView**

```swift
// OpenclawDaddy/Views/TerminalView.swift
import SwiftUI
import SwiftTerm

struct TerminalView: NSViewRepresentable {
    let masterFd: Int32

    class Coordinator: NSObject, TerminalViewDelegate {
        var masterFd: Int32
        var readSource: DispatchSourceRead?

        init(masterFd: Int32) {
            self.masterFd = masterFd
            super.init()
        }

        func startReading(terminalView: SwiftTerm.TerminalView) {
            let source = DispatchSource.makeReadSource(
                fileDescriptor: masterFd,
                queue: .global(qos: .userInteractive)
            )
            source.setEventHandler { [weak self, weak terminalView] in
                guard let self, let terminalView else { return }
                var buffer = [UInt8](repeating: 0, count: 8192)
                let bytesRead = read(self.masterFd, &buffer, buffer.count)
                if bytesRead > 0 {
                    let data = Array(buffer[0..<bytesRead])
                    DispatchQueue.main.async {
                        terminalView.feed(byteArray: data)
                    }
                }
            }
            source.resume()
            self.readSource = source
        }

        func cleanup() {
            readSource?.cancel()
            readSource = nil
        }

        // MARK: - TerminalViewDelegate

        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            PTYManager.resize(
                masterFd: masterFd,
                cols: UInt16(newCols),
                rows: UInt16(newRows)
            )
        }

        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {
            // Could be used to update sidebar name in future
        }

        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Array(data)
            bytes.withUnsafeBufferPointer { ptr in
                if let baseAddress = ptr.baseAddress {
                    write(masterFd, baseAddress, bytes.count)
                }
            }
        }

        func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String : String]) {}
        func bell(source: SwiftTerm.TerminalView) {
            NSSound.beep()
        }
        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {
            if let str = String(data: content, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(str, forType: .string)
            }
        }
        func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(masterFd: masterFd)
    }

    func makeNSView(context: Context) -> SwiftTerm.TerminalView {
        let terminalView = SwiftTerm.TerminalView(frame: .zero)
        terminalView.terminalDelegate = context.coordinator
        terminalView.configureNativeColors()

        // Start reading from PTY
        context.coordinator.startReading(terminalView: terminalView)

        return terminalView
    }

    func updateNSView(_ nsView: SwiftTerm.TerminalView, context: Context) {
        // Update fd if it changed (e.g., after keepalive restart)
        if context.coordinator.masterFd != masterFd {
            context.coordinator.cleanup()
            context.coordinator.masterFd = masterFd
            context.coordinator.startReading(terminalView: nsView)
        }
    }

    static func dismantleNSView(_ nsView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.cleanup()
    }
}
```

- [ ] **Step 2: Verify project still builds**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddy -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

Note: `TerminalViewDelegate` has 10 required methods (all implemented above). The `feed(byteArray:)` method is used to push PTY output data into the terminal view. If this exact method name doesn't compile, try `feed(buffer:)` or access the underlying `Terminal` instance via `terminalView.getTerminal().feed(byteArray:)`. SwiftTerm also provides `PseudoTerminalHelpers` for PTY operations — consider using it as an alternative to raw `forkpty` if integration issues arise.

- [ ] **Step 3: Commit**

```bash
git add OpenclawDaddy/Views/TerminalView.swift
git commit -m "feat: add TerminalView NSViewRepresentable bridge for SwiftTerm"
```

---

### Task 7: Main Window + Sidebar UI

**Files:**
- Create: `OpenclawDaddy/Views/MainWindow.swift`
- Create: `OpenclawDaddy/Views/SidebarView.swift`
- Create: `OpenclawDaddy/Views/TerminalToolbar.swift`
- Create: `OpenclawDaddy/Views/EmptyStateView.swift`
- Modify: `OpenclawDaddy/App/OpenclawDaddyApp.swift`

- [ ] **Step 1: Create EmptyStateView**

```swift
// OpenclawDaddy/Views/EmptyStateView.swift
import SwiftUI

struct EmptyStateView: View {
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No profiles configured")
                .font(.title2)
            Text("Add one in Settings or edit ~/.openclaw-daddy/config.yaml")
                .foregroundStyle(.secondary)
            Button("Open Settings") {
                onOpenSettings()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 2: Create SidebarView**

```swift
// OpenclawDaddy/Views/SidebarView.swift
import SwiftUI

struct SidebarView: View {
    let profiles: [Profile]
    let terminalIds: [UUID]
    let statusProvider: (UUID) -> ProcessStatus
    @Binding var selection: String?
    let onNewTerminal: () -> Void

    var body: some View {
        List(selection: $selection) {
            Section("Profiles") {
                ForEach(profiles) { profile in
                    HStack {
                        statusCircle(for: statusProvider(profile.id))
                        Text(profile.name)
                        Spacer()
                    }
                    .tag("profile-\(profile.id)")
                }
            }

            Section("Terminals") {
                ForEach(terminalIds, id: \.self) { id in
                    HStack {
                        Circle()
                            .fill(.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                        Text("Shell \(id.uuidString.prefix(4))")
                        Spacer()
                    }
                    .tag("terminal-\(id)")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button {
                    onNewTerminal()
                } label: {
                    Label("New Terminal", systemImage: "plus.rectangle")
                }
                .buttonStyle(.plain)
                .padding(8)
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func statusCircle(for status: ProcessStatus) -> some View {
        Circle()
            .fill(statusColor(status))
            .frame(width: 8, height: 8)
    }

    private func statusColor(_ status: ProcessStatus) -> Color {
        switch status {
        case .running: return .green
        case .crashed: return .red
        case .crashLooping: return .yellow
        case .stopped: return .gray
        }
    }
}
```

- [ ] **Step 3: Create TerminalToolbar**

```swift
// OpenclawDaddy/Views/TerminalToolbar.swift
import SwiftUI

struct TerminalToolbar: View {
    let isProfile: Bool
    let status: ProcessStatus
    let onStart: () -> Void
    let onStop: () -> Void
    let onRestart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isProfile {
                Button(action: onStart) {
                    Label("Start", systemImage: "play.fill")
                }
                .disabled(status == .running)

                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(status == .stopped)

                Button(action: onRestart) {
                    Label("Restart", systemImage: "arrow.clockwise")
                }
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 4: Create MainWindow**

```swift
// OpenclawDaddy/Views/MainWindow.swift
import SwiftUI

struct MainWindow: View {
    @State var configManager: ConfigManager
    @State var processManager: ProcessManager
    @State private var selection: String?
    @State private var terminalIds: [UUID] = []
    @State private var terminalFds: [UUID: Int32] = [:]
    @SceneStorage("selectedItem") private var savedSelection: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                profiles: configManager.config.resolvedProfiles(),
                terminalIds: terminalIds,
                statusProvider: { processManager.status(for: $0) },
                selection: $selection,
                onNewTerminal: newTerminal
            )
            .frame(minWidth: 180)
        } detail: {
            if let selection {
                detailView(for: selection)
            } else {
                EmptyStateView {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .onAppear {
            selection = savedSelection
            startAutoProfiles()
        }
        .onChange(of: selection) { _, newValue in
            savedSelection = newValue
        }
    }

    @ViewBuilder
    private func detailView(for id: String) -> some View {
        if id.hasPrefix("profile-"),
           let profile = findProfile(from: id) {
            VStack(spacing: 0) {
                if let fd = processManager.masterFd(for: profile.id), fd >= 0 {
                    TerminalView(masterFd: fd)
                } else {
                    Text("Process not running")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .foregroundStyle(.secondary)
                }
                Divider()
                TerminalToolbar(
                    isProfile: true,
                    status: processManager.status(for: profile.id),
                    onStart: { startProfile(profile) },
                    onStop: { processManager.stopProfile(profile.id) },
                    onRestart: {
                        let path = configManager.buildPath(for: profile, global: configManager.config.global)
                        processManager.restartProfile(profile, path: path)
                    }
                )
            }
        } else if id.hasPrefix("terminal-"),
                  let termId = extractTerminalId(from: id),
                  let fd = terminalFds[termId] {
            VStack(spacing: 0) {
                TerminalView(masterFd: fd)
                Divider()
                TerminalToolbar(
                    isProfile: false,
                    status: .running,
                    onStart: {},
                    onStop: {},
                    onRestart: {}
                )
            }
        }
    }

    private func newTerminal() {
        if let (id, fd) = processManager.spawnTerminal() {
            terminalIds.append(id)
            terminalFds[id] = fd
            selection = "terminal-\(id)"
        }
    }

    private func startProfile(_ profile: Profile) {
        let path = configManager.buildPath(for: profile, global: configManager.config.global)
        processManager.startProfile(profile, path: path)
    }

    private func startAutoProfiles() {
        for profile in configManager.config.resolvedProfiles() where profile.autostart {
            startProfile(profile)
        }
    }

    private func findProfile(from selectionId: String) -> Profile? {
        guard let uuidString = selectionId.components(separatedBy: "profile-").last,
              let uuid = UUID(uuidString: uuidString) else { return nil }
        return configManager.config.resolvedProfiles().first { $0.id == uuid }
    }

    private func extractTerminalId(from selectionId: String) -> UUID? {
        guard let uuidString = selectionId.components(separatedBy: "terminal-").last else { return nil }
        return UUID(uuidString: uuidString)
    }
}
```

- [ ] **Step 5: Update OpenclawDaddyApp to use MainWindow + load config**

```swift
// OpenclawDaddy/App/OpenclawDaddyApp.swift
import SwiftUI

@main
struct OpenclawDaddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var configManager = ConfigManager()
    @State private var processManager = ProcessManager()

    var body: some Scene {
        WindowGroup {
            MainWindow(
                configManager: configManager,
                processManager: processManager
            )
            .onAppear {
                do {
                    let config = try configManager.load()
                    processManager = ProcessManager(restartDelay: config.global.restartDelay)
                    configManager.startWatching()
                } catch {
                    // First launch or error — Settings will handle it
                    print("Config load error: \(error)")
                }
            }
        }
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentSize)

        Settings {
            Text("Settings placeholder")
        }
    }
}
```

- [ ] **Step 6: Verify build**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddy -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

Note: SwiftTerm API may need adjustments at this stage. Fix any compilation errors from delegate conformance or API changes.

- [ ] **Step 7: Commit**

```bash
git add OpenclawDaddy/Views/ OpenclawDaddy/App/OpenclawDaddyApp.swift
git commit -m "feat: add main window with NavigationSplitView, sidebar, terminal detail"
```

---

### Task 8: MenuBarExtra (Tray Icon)

**Files:**
- Modify: `OpenclawDaddy/App/OpenclawDaddyApp.swift`
- Create: `OpenclawDaddy/Views/MenuBarView.swift`

- [ ] **Step 1: Create MenuBarView**

```swift
// OpenclawDaddy/Views/MenuBarView.swift
import SwiftUI

struct MenuBarView: View {
    let profiles: [Profile]
    let statusProvider: (UUID) -> ProcessStatus
    let onStartAll: () -> Void
    let onStopAll: () -> Void
    let onOpenWindow: () -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(profiles) { profile in
                HStack {
                    Circle()
                        .fill(statusColor(statusProvider(profile.id)))
                        .frame(width: 8, height: 8)
                    Text(profile.name)
                    Spacer()
                    Text(statusLabel(statusProvider(profile.id)))
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            Divider().padding(.vertical, 4)

            Button("Start All") { onStartAll() }
                .padding(.horizontal, 12)
            Button("Stop All") { onStopAll() }
                .padding(.horizontal, 12)

            Divider().padding(.vertical, 4)

            Button("Open Window") { onOpenWindow() }
                .padding(.horizontal, 12)
            Button("Settings...") { onOpenSettings() }
                .padding(.horizontal, 12)

            Divider().padding(.vertical, 4)

            Button("Quit") { onQuit() }
                .padding(.horizontal, 12)
        }
        .padding(.vertical, 8)
    }

    private func statusColor(_ status: ProcessStatus) -> Color {
        switch status {
        case .running: return .green
        case .crashed: return .red
        case .crashLooping: return .yellow
        case .stopped: return .gray
        }
    }

    private func statusLabel(_ status: ProcessStatus) -> String {
        switch status {
        case .running: return "Running"
        case .crashed: return "Crashed"
        case .crashLooping: return "Crash Loop"
        case .stopped: return "Stopped"
        }
    }
}
```

- [ ] **Step 2: Add MenuBarExtra to OpenclawDaddyApp**

Add this scene inside the `var body: some Scene` of `OpenclawDaddyApp`:

```swift
// Add after the Settings scene in OpenclawDaddyApp.swift
MenuBarExtra {
    MenuBarView(
        profiles: configManager.config.resolvedProfiles(),
        statusProvider: { processManager.status(for: $0) },
        onStartAll: {
            for profile in configManager.config.resolvedProfiles() {
                let path = configManager.buildPath(for: profile, global: configManager.config.global)
                processManager.startProfile(profile, path: path)
            }
        },
        onStopAll: { processManager.stopAll() },
        onOpenWindow: { NSApp.activate(ignoringOtherApps: true) },
        onOpenSettings: {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        },
        onQuit: {
            processManager.stopAll {
                NSApp.terminate(nil)
            }
        }
    )
} label: {
    let hasIssue = configManager.config.resolvedProfiles().contains {
        let s = processManager.status(for: $0.id)
        return s == .crashed || s == .crashLooping
    }
    Image(systemName: hasIssue ? "terminal.fill" : "terminal")
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddy -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add OpenclawDaddy/Views/MenuBarView.swift OpenclawDaddy/App/OpenclawDaddyApp.swift
git commit -m "feat: add MenuBarExtra with profile status, start/stop all, quit"
```

---

### Task 9: Settings UI (Profiles Editor + Permissions Panel)

**Files:**
- Create: `OpenclawDaddy/Views/SettingsView.swift`
- Create: `OpenclawDaddy/Views/ProfileEditorView.swift`
- Create: `OpenclawDaddy/Views/PermissionsView.swift`
- Create: `OpenclawDaddy/Services/PermissionManager.swift`

- [ ] **Step 1: Implement PermissionManager**

```swift
// OpenclawDaddy/Services/PermissionManager.swift
import Foundation
import AVFoundation
import CoreLocation
import UserNotifications
import AppKit

enum PermissionStatus: String {
    case granted = "Granted"
    case denied = "Denied"
    case notAsked = "Not Asked"
    case unknown = "Unknown"
}

struct PermissionInfo: Identifiable {
    let id: String
    let name: String
    var status: PermissionStatus
    let canRequest: Bool   // Can we trigger a system prompt?
    let canDetect: Bool    // Can we query the current status?
    let settingsURL: String?
}

@Observable
final class PermissionManager {

    var permissions: [PermissionInfo] = []
    private let locationManager = CLLocationManager()

    init() {
        refresh()
    }

    func refresh() {
        permissions = [
            screenRecordingPermission(),
            accessibilityPermission(),
            cameraPermission(),
            microphonePermission(),
            locationPermission(),
            notificationPermission(),
            fullDiskAccessPermission(),
            inputMonitoringPermission(),
        ]
    }

    func request(_ id: String) {
        switch id {
        case "camera":
            AVCaptureDevice.requestAccess(for: .video) { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        case "microphone":
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        case "notifications":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] _, _ in
                DispatchQueue.main.async { self?.refresh() }
            }
        case "screen_recording":
            CGRequestScreenCaptureAccess()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.refresh()
            }
        case "location":
            locationManager.requestWhenInUseAuthorization()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.refresh()
            }
        default:
            break
        }
    }

    func openSettings(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Individual Permission Checks

    private func screenRecordingPermission() -> PermissionInfo {
        let granted = CGPreflightScreenCaptureAccess()
        return PermissionInfo(
            id: "screen_recording",
            name: "Screen Recording",
            status: granted ? .granted : .denied,
            canRequest: true,
            canDetect: true,
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    private func accessibilityPermission() -> PermissionInfo {
        let trusted = AXIsProcessTrusted()
        return PermissionInfo(
            id: "accessibility",
            name: "Accessibility",
            status: trusted ? .granted : .denied,
            canRequest: false,
            canDetect: true,
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    private func cameraPermission() -> PermissionInfo {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return PermissionInfo(
            id: "camera",
            name: "Camera",
            status: avStatusToPermission(status),
            canRequest: status == .notDetermined,
            canDetect: true,
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
        )
    }

    private func microphonePermission() -> PermissionInfo {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return PermissionInfo(
            id: "microphone",
            name: "Microphone",
            status: avStatusToPermission(status),
            canRequest: status == .notDetermined,
            canDetect: true,
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
    }

    private func locationPermission() -> PermissionInfo {
        // CLLocationManager status check requires an instance
        return PermissionInfo(
            id: "location",
            name: "Location",
            status: .unknown,
            canRequest: true,
            canDetect: false,
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        )
    }

    private func notificationPermission() -> PermissionInfo {
        // Async check — we'll default to unknown and update
        return PermissionInfo(
            id: "notifications",
            name: "Notifications",
            status: .unknown,
            canRequest: true,
            canDetect: true,
            settingsURL: nil
        )
    }

    private func fullDiskAccessPermission() -> PermissionInfo {
        PermissionInfo(
            id: "full_disk",
            name: "Full Disk Access",
            status: .unknown,
            canRequest: false,
            canDetect: false,
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )
    }

    private func inputMonitoringPermission() -> PermissionInfo {
        PermissionInfo(
            id: "input_monitoring",
            name: "Input Monitoring",
            status: .unknown,
            canRequest: false,
            canDetect: false,
            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
    }

    private func avStatusToPermission(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined: return .notAsked
        @unknown default: return .unknown
        }
    }
}
```

- [ ] **Step 2: Create ProfileEditorView**

```swift
// OpenclawDaddy/Views/ProfileEditorView.swift
import SwiftUI

struct ProfileEditorView: View {
    @Binding var profile: Profile
    let onDelete: () -> Void

    @State private var newPathEntry = ""
    @State private var newEnvKey = ""
    @State private var newEnvValue = ""

    var body: some View {
        Form {
            Section("Basic") {
                TextField("Name", text: $profile.name)
                TextField("Command", text: $profile.command)
                    .font(.system(.body, design: .monospaced))
                Toggle("Autostart", isOn: $profile.autostart)
            }

            Section("PATH Entries") {
                ForEach(Array(profile.path.enumerated()), id: \.offset) { index, path in
                    HStack {
                        Text(path).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            profile.path.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("Add path...", text: $newPathEntry)
                        .font(.system(.body, design: .monospaced))
                    Button {
                        if !newPathEntry.isEmpty {
                            profile.path.append(newPathEntry)
                            newPathEntry = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }

            Section("Environment Variables") {
                ForEach(Array(profile.env.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(key).font(.system(.body, design: .monospaced))
                        Text("=").foregroundStyle(.secondary)
                        Text(profile.env[key] ?? "")
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            profile.env.removeValue(forKey: key)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("KEY", text: $newEnvKey)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 120)
                    Text("=")
                    TextField("VALUE", text: $newEnvValue)
                        .font(.system(.body, design: .monospaced))
                    Button {
                        if !newEnvKey.isEmpty {
                            profile.env[newEnvKey] = newEnvValue
                            newEnvKey = ""
                            newEnvValue = ""
                        }
                    } label: {
                        Image(systemName: "plus.circle")
                    }
                }
            }

            Section("Log") {
                TextField("Log file path (optional)", text: Binding(
                    get: { profile.logFile ?? "" },
                    set: { profile.logFile = $0.isEmpty ? nil : $0 }
                ))
                .font(.system(.body, design: .monospaced))
            }

            Section {
                Button("Delete Profile", role: .destructive) {
                    onDelete()
                }
            }
        }
        .formStyle(.grouped)
    }
}
```

- [ ] **Step 3: Create PermissionsView**

```swift
// OpenclawDaddy/Views/PermissionsView.swift
import SwiftUI

struct PermissionsView: View {
    @State var permissionManager = PermissionManager()

    var body: some View {
        Form {
            Section("Permissions") {
                ForEach(permissionManager.permissions) { perm in
                    HStack {
                        statusIcon(perm.status)
                        Text(perm.name)
                        Spacer()
                        Text(perm.status.rawValue)
                            .foregroundStyle(.secondary)
                            .font(.caption)

                        if perm.canRequest && (perm.status == .notAsked || perm.status == .denied) {
                            Button("Request") {
                                permissionManager.request(perm.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        if let url = perm.settingsURL {
                            Button("Open Settings") {
                                permissionManager.openSettings(url)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            Section {
                Button("Open System Settings") {
                    permissionManager.openSettings(
                        "x-apple.systempreferences:com.apple.preference.security"
                    )
                }

                Button("Refresh") {
                    permissionManager.refresh()
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permissionManager.refresh()
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: PermissionStatus) -> some View {
        switch status {
        case .granted:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .denied:
            Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
        case .notAsked:
            Image(systemName: "circle").foregroundStyle(.gray)
        case .unknown:
            Image(systemName: "questionmark.circle.fill").foregroundStyle(.orange)
        }
    }
}
```

- [ ] **Step 4: Create SettingsView (tabs)**

```swift
// OpenclawDaddy/Views/SettingsView.swift
import SwiftUI

struct SettingsView: View {
    @State var configManager: ConfigManager
    @State private var editableConfig: AppConfig = .makeDefault()
    @State private var saveError: String?

    var body: some View {
        TabView {
            profilesTab
                .tabItem { Label("Profiles", systemImage: "list.bullet") }

            PermissionsView()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            globalTab
                .tabItem { Label("Global", systemImage: "gearshape") }
        }
        .frame(width: 600, height: 450)
        .onAppear {
            editableConfig = configManager.config
        }
    }

    private var profilesTab: some View {
        VStack {
            if editableConfig.profiles.isEmpty {
                Text("No profiles. Click + to add one.")
                    .foregroundStyle(.secondary)
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(editableConfig.profiles.enumerated()), id: \.element.id) { index, _ in
                        ProfileEditorView(
                            profile: $editableConfig.profiles[index],
                            onDelete: {
                                editableConfig.profiles.remove(at: index)
                                saveConfig()
                            }
                        )
                    }
                }
            }

            HStack {
                Button {
                    editableConfig.profiles.append(
                        Profile(name: "New Profile", command: "openclaw --profile new run")
                    )
                    saveConfig()
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }

                Spacer()

                if let error = saveError {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Button("Save") { saveConfig() }
                    .keyboardShortcut("s")
            }
            .padding()
        }
    }

    private var globalTab: some View {
        Form {
            Section("Restart") {
                Stepper(
                    "Restart delay: \(editableConfig.global.restartDelay)s",
                    value: $editableConfig.global.restartDelay,
                    in: 1...60
                )
            }

            Section("Extra PATH (global)") {
                ForEach(Array(editableConfig.global.extraPath.enumerated()), id: \.offset) { index, path in
                    HStack {
                        Text(path).font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(role: .destructive) {
                            editableConfig.global.extraPath.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section {
                Button("Save") { saveConfig() }
                    .keyboardShortcut("s")
            }
        }
        .formStyle(.grouped)
    }

    private func saveConfig() {
        do {
            try configManager.save(editableConfig)
            saveError = nil
        } catch {
            saveError = error.localizedDescription
        }
    }
}
```

- [ ] **Step 5: Update OpenclawDaddyApp Settings scene**

Replace the `Settings` scene in `OpenclawDaddyApp.swift`:

```swift
Settings {
    SettingsView(configManager: configManager)
}
```

- [ ] **Step 6: Verify build**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddy -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 7: Commit**

```bash
git add OpenclawDaddy/Services/PermissionManager.swift OpenclawDaddy/Views/SettingsView.swift OpenclawDaddy/Views/ProfileEditorView.swift OpenclawDaddy/Views/PermissionsView.swift OpenclawDaddy/App/OpenclawDaddyApp.swift
git commit -m "feat: add Settings with profile CRUD editor and permissions panel"
```

---

### Task 10: Keyboard Shortcuts

**Files:**
- Modify: `OpenclawDaddy/App/OpenclawDaddyApp.swift`
- Modify: `OpenclawDaddy/Views/MainWindow.swift`

- [ ] **Step 1: Add keyboard shortcuts to MainWindow**

Add these modifiers to the top-level `NavigationSplitView` in `MainWindow.swift`:

```swift
// Add to the NavigationSplitView chain in MainWindow.swift
.keyboardShortcut("t", modifiers: .command)  // Won't work here — need Commands

// Instead, add a .commands modifier at the App level
```

Actually, keyboard shortcuts in SwiftUI macOS apps go in `Commands`. Update `OpenclawDaddyApp.swift`:

```swift
// In OpenclawDaddyApp body, add .commands to the WindowGroup:
WindowGroup {
    MainWindow(configManager: configManager, processManager: processManager)
        // ... existing modifiers
}
.commands {
    CommandGroup(after: .newItem) {
        Button("New Terminal") {
            NotificationCenter.default.post(name: .newTerminalRequested, object: nil)
        }
        .keyboardShortcut("t", modifiers: .command)

        Button("New Profile") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            NotificationCenter.default.post(name: .addProfileRequested, object: nil)
        }
        .keyboardShortcut("n", modifiers: .command)
    }

    CommandGroup(after: .newItem) {
        Button("Close Tab") {
            NotificationCenter.default.post(name: .closeTabRequested, object: nil)
        }
        .keyboardShortcut("w", modifiers: .command)
    }

    CommandGroup(replacing: .appSettings) {
        Button("Settings...") {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
        .keyboardShortcut(",", modifiers: .command)
    }

    CommandMenu("Process") {
        Button("Restart Selected") {
            NotificationCenter.default.post(name: .restartSelectedRequested, object: nil)
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])

        Button("Stop Selected") {
            NotificationCenter.default.post(name: .stopSelectedRequested, object: nil)
        }
        .keyboardShortcut("s", modifiers: [.command, .shift])

        Divider()

        Button("Start All") {
            for profile in configManager.config.resolvedProfiles() {
                let path = configManager.buildPath(for: profile, global: configManager.config.global)
                processManager.startProfile(profile, path: path)
            }
        }
        .keyboardShortcut("a", modifiers: [.command, .shift])
    }

    // ⌘1-9 to switch sidebar items
    CommandMenu("Tabs") {
        ForEach(0..<9, id: \.self) { index in
            Button("Switch to Tab \(index + 1)") {
                NotificationCenter.default.post(
                    name: .switchToTab,
                    object: nil,
                    userInfo: ["index": index]
                )
            }
            .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
        }
    }
}
```

Add notification name extensions:

```swift
// Add to OpenclawDaddy/App/OpenclawDaddyApp.swift (top of file)
extension Notification.Name {
    static let newTerminalRequested = Notification.Name("newTerminalRequested")
    static let restartSelectedRequested = Notification.Name("restartSelectedRequested")
    static let stopSelectedRequested = Notification.Name("stopSelectedRequested")
    static let closeTabRequested = Notification.Name("closeTabRequested")
    static let addProfileRequested = Notification.Name("addProfileRequested")
    static let switchToTab = Notification.Name("switchToTab")
}
```

- [ ] **Step 2: Handle notifications in MainWindow**

Add to `MainWindow`'s `NavigationSplitView`:

```swift
.onReceive(NotificationCenter.default.publisher(for: .newTerminalRequested)) { _ in
    newTerminal()
}
.onReceive(NotificationCenter.default.publisher(for: .restartSelectedRequested)) { _ in
    if let selection, selection.hasPrefix("profile-"),
       let profile = findProfile(from: selection) {
        let path = configManager.buildPath(for: profile, global: configManager.config.global)
        processManager.restartProfile(profile, path: path)
    }
}
.onReceive(NotificationCenter.default.publisher(for: .stopSelectedRequested)) { _ in
    if let selection, selection.hasPrefix("profile-"),
       let profile = findProfile(from: selection) {
        processManager.stopProfile(profile.id)
    }
}
.onReceive(NotificationCenter.default.publisher(for: .closeTabRequested)) { _ in
    guard let selection else { return }
    if selection.hasPrefix("terminal-"),
       let termId = extractTerminalId(from: selection) {
        if processManager.isTerminalRunning(termId) {
            // Show confirmation alert
            let alert = NSAlert()
            alert.messageText = "Shell is still running. Close anyway?"
            alert.addButton(withTitle: "Close")
            alert.addButton(withTitle: "Cancel")
            alert.alertStyle = .warning
            if alert.runModal() == .alertFirstButtonReturn {
                processManager.closeTerminal(termId)
                terminalIds.removeAll { $0 == termId }
                terminalFds.removeValue(forKey: termId)
                self.selection = nil
            }
        } else {
            processManager.closeTerminal(termId)
            terminalIds.removeAll { $0 == termId }
            terminalFds.removeValue(forKey: termId)
            self.selection = nil
        }
    }
    // Profile tabs: do nothing on ⌘W (cannot close while running per spec)
}
.onReceive(NotificationCenter.default.publisher(for: .switchToTab)) { notification in
    guard let index = notification.userInfo?["index"] as? Int else { return }
    let allItems = configManager.config.resolvedProfiles().map { "profile-\($0.id)" }
        + terminalIds.map { "terminal-\($0)" }
    if index < allItems.count {
        selection = allItems[index]
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddy -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add OpenclawDaddy/App/OpenclawDaddyApp.swift OpenclawDaddy/Views/MainWindow.swift
git commit -m "feat: add keyboard shortcuts (Cmd+T/W/N/1-9, Cmd+Shift+R/S/A, Cmd+,)"
```

---

### Task 11: LogManager (Optional Per-Profile Logging)

**Files:**
- Create: `OpenclawDaddy/Services/LogManager.swift`

- [ ] **Step 1: Implement LogManager**

```swift
// OpenclawDaddy/Services/LogManager.swift
import Foundation

final class LogManager {
    private var fileHandles: [UUID: FileHandle] = [:]
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    func startLogging(profileId: UUID, logFilePath: String) {
        let expanded = NSString(string: logFilePath).expandingTildeInPath
        let dir = (expanded as NSString).deletingLastPathComponent
        let baseName = ((expanded as NSString).lastPathComponent as NSString).deletingPathExtension
        let ext = (expanded as NSString).pathExtension

        // Create log directory
        try? FileManager.default.createDirectory(
            atPath: dir,
            withIntermediateDirectories: true
        )

        // Date-rotated filename
        let dateString = dateFormatter.string(from: Date())
        let rotatedPath = "\(dir)/\(baseName)-\(dateString).\(ext.isEmpty ? "log" : ext)"

        FileManager.default.createFile(atPath: rotatedPath, contents: nil)
        if let handle = FileHandle(forWritingAtPath: rotatedPath) {
            handle.seekToEndOfFile()
            fileHandles[profileId] = handle
        }
    }

    func write(profileId: UUID, data: Data) {
        fileHandles[profileId]?.write(data)
    }

    func write(profileId: UUID, bytes: [UInt8]) {
        write(profileId: profileId, data: Data(bytes))
    }

    func stopLogging(profileId: UUID) {
        fileHandles[profileId]?.closeFile()
        fileHandles.removeValue(forKey: profileId)
    }

    func stopAll() {
        for (id, _) in fileHandles {
            stopLogging(profileId: id)
        }
    }
}
```

- [ ] **Step 2: Integrate LogManager into ProcessManager or TerminalView read loop**

The log writing should happen in the TerminalView's `Coordinator.startReading` where PTY data is read. Add logging hook:

Add to `TerminalView.Coordinator`:

```swift
var logWriter: ((Data) -> Void)?
```

In `startReading`, after `read()`:

```swift
if bytesRead > 0 {
    let data = Array(buffer[0..<bytesRead])
    // Log to file if configured
    logWriter?(Data(data))
    DispatchQueue.main.async {
        terminalView.feed(byteArray: data)
    }
}
```

- [ ] **Step 3: Verify build**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddy -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git add OpenclawDaddy/Services/LogManager.swift OpenclawDaddy/Views/TerminalView.swift
git commit -m "feat: add LogManager with date-rotated per-profile file logging"
```

---

### Task 12: Edge Cases + Polish

**Files:**
- Modify: `OpenclawDaddy/App/AppDelegate.swift`
- Modify: `OpenclawDaddy/Services/ProcessManager.swift`
- Modify: `OpenclawDaddy/App/OpenclawDaddyApp.swift`

- [ ] **Step 1: Add crash-loop notification to ProcessManager**

In `ProcessManager`, set up `onCrashLoop` to send a macOS notification:

```swift
// In OpenclawDaddyApp.swift onAppear, after creating processManager:
processManager.onCrashLoop = { _, name in
    let content = UNMutableNotificationContent()
    content.title = "OpenclawDaddy"
    content.body = "\(name) is crash-looping"
    content.sound = .default
    let request = UNNotificationRequest(
        identifier: "crash-loop-\(name)",
        content: content,
        trigger: nil
    )
    UNUserNotificationCenter.current().add(request)
}
```

- [ ] **Step 2: Wire AppDelegate.processManager for graceful shutdown**

In `OpenclawDaddyApp.swift` `onAppear`, after creating processManager, wire it to AppDelegate:

```swift
// Wire processManager to AppDelegate for graceful shutdown on ⌘Q
appDelegate.processManager = processManager
```

This uses the `applicationShouldTerminate` → `.terminateLater` pattern already implemented in Task 1's AppDelegate, which blocks app exit until all processes are SIGTERMed and reaped.

- [ ] **Step 3: Add window frame autosave to MainWindow**

In `MainWindow.swift`, add to the `NavigationSplitView`:

```swift
.background(WindowAccessor())

// Helper to set autosave name
struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.setFrameAutosaveName("MainWindow")
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
```

- [ ] **Step 4: Verify build + run all tests**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddy -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddyTests -destination 'platform=macOS' test 2>&1 | tail -5`
Expected: `TEST SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git add OpenclawDaddy/
git commit -m "feat: add crash-loop notifications, graceful shutdown, window state restore"
```

---

### Task 13: First Launch Flow

**Files:**
- Modify: `OpenclawDaddy/Views/MainWindow.swift`
- Modify: `OpenclawDaddy/App/OpenclawDaddyApp.swift`

- [ ] **Step 1: Add first-launch detection and Settings auto-open**

In `OpenclawDaddyApp.swift` `onAppear`:

```swift
.onAppear {
    do {
        let config = try configManager.load()
        processManager = ProcessManager(restartDelay: config.global.restartDelay)
        configManager.startWatching()

        // First launch: if no profiles, open Settings
        if config.profiles.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    } catch {
        print("Config load error: \(error)")
    }
}
```

- [ ] **Step 2: Verify build**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddy -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git add OpenclawDaddy/App/OpenclawDaddyApp.swift
git commit -m "feat: auto-open Settings on first launch when no profiles configured"
```

---

### Task 14: Final Integration Test + Manual Verification

- [ ] **Step 1: Run full test suite**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddyTests -destination 'platform=macOS' test 2>&1 | tail -10`
Expected: `TEST SUCCEEDED` with all tests passing

- [ ] **Step 2: Build the app**

Run: `xcodebuild -project OpenclawDaddy.xcodeproj -scheme OpenclawDaddy -configuration Release -destination 'platform=macOS' build 2>&1 | tail -5`
Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Manual verification checklist**

Open the built .app and verify:
1. App launches with empty sidebar (first launch)
2. Settings window opens automatically
3. Can add a profile via Settings UI
4. Profile appears in sidebar after save
5. Can start profile — terminal shows output
6. Can stop profile — process terminates
7. Menu bar icon appears with profile statuses
8. ⌘T creates new terminal tab
9. Free terminal tab has interactive shell
10. Closing window keeps app in menu bar
11. Quit from menu bar terminates all processes

- [ ] **Step 4: Create sample config for testing**

Write `~/.openclaw-daddy/config.yaml` manually:

```yaml
version: 1
global:
  restart_delay: 3
  extra_path:
    - /usr/local/bin
    - /opt/homebrew/bin
profiles:
  - name: "Echo Test"
    command: "while true; do echo $(date); sleep 2; done"
    autostart: true
  - name: "Gateway"
    command: "openclaw --profile gateway run"
    autostart: false
```

Verify Echo Test autostarts and shows repeating date output in terminal.

- [ ] **Step 5: Final commit**

```bash
git add -A
git commit -m "chore: final integration — all tasks complete"
```

- [ ] **Step 6: Push to remote**

```bash
git push -u origin master
```
