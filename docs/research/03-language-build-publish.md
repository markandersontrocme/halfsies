# 03 - Language, architecture, build, and publishing

Research date: 2026-11-09.
Scope: programming language and UI framework, app architecture for extensibility, build toolchain, CI, signing and notarization, distribution, and updates for "halfsies", a macOS menu bar app for ZMK split keyboards.
The ZMK protocol and prior-art apps are covered by the other research documents.

## TL;DR / recommended stack

- **Language and UI:** Swift 6 language mode on the current Swift 6.4 toolchain ([Swift 6.4 release](https://www.swift.org/blog/swift-6.4-released/), [Xcode support matrix](https://developer.apple.com/support/xcode/)), SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.window)` for the popover ([MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)), and CoreBluetooth used directly.
- **AppKit:** use it only where SwiftUI falls short, for example by dropping to `NSStatusItem` if the status item needs custom click handling ([NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)).
- **Minimum macOS:** 14 (Sonoma).
  That version unlocks the Observation framework ([Observation](https://developer.apple.com/documentation/observation)) and `SettingsLink` ([SettingsLink](https://developer.apple.com/documentation/swiftui/settingslink)), on top of `MenuBarExtra` and `SMAppService`, which need macOS 13 ([SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)).
- **Structure:** a thin Xcode app target plus a local Swift package (`HalfsiesKit`) with a transport-agnostic `Core` module, a `BLE` adapter module, and feature modules.
  Tests use Swift Testing against fake transports ([Swift Testing](https://developer.apple.com/documentation/testing)).
- **Project generation:** XcodeGen `project.yml` with the `.xcodeproj` gitignored ([XcodeGen](https://github.com/yonaskolb/XcodeGen)).
  XcodeGen 2.46.0 is already installed on this Mac.
  The fallback is a committed Xcode project that uses synchronized folders.
  SwiftPM alone cannot produce a proper `.app` ([PackageDescription Product](https://developer.apple.com/documentation/packagedescription/product)).
- **Distribution:** Developer ID signing, Hardened Runtime, notarization with `notarytool`, and stapling ([Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).
  Releases ship as a notarized DMG on GitHub Releases.
  The app stays non-sandboxed at first (see the sandbox decision below).
- **Updates:** Sparkle 2.10.x with an EdDSA-signed appcast hosted on GitHub Pages ([Sparkle docs](https://sparkle-project.org/documentation/), [Sparkle 2.10.1](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1)).
- **Homebrew:** an own tap (`homebrew-tap`) with a cask that sets `auto_updates true` and uses a Sparkle livecheck ([Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)).
  Move to `homebrew/cask` later, if it meets the notability bar ([Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)).
- **CI/CD:** GitHub Actions on the `xcode-27` image, which is GA ([GitHub changelog](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/)).
  release-please opens release PRs ([release-please-action](https://github.com/googleapis/release-please-action)).
  A tag-triggered job archives, signs in a temporary keychain, notarizes with an App Store Connect API key, staples, builds the appcast, and publishes.
- **Cost:** the paid Apple Developer Program at 99 USD per year is required for Developer ID and notarization ([Enroll](https://developer.apple.com/programs/enroll/), [Developer ID](https://developer.apple.com/developer-id/)).
  Standard GitHub-hosted runners are free for public repositories ([GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)).

## Local toolchain findings

These come from read-only commands run on 2026-11-09.

| Item | Result |
| --- | --- |
| `sw_vers` | macOS 27.0.1, build 26A434 |
| `xcodebuild -version` | Xcode 27.2, build 27B52 |
| `swift --version` | Apple Swift 6.4.2 (swiftlang-6.4.2.1.9), target `arm64-apple-macosx27.0.0` |
| `xcode-select -p` | `/Applications/Xcode.app/Contents/Developer` |
| SDKs (`xcodebuild -showsdks`) | macOS 27.2, plus iOS, tvOS, watchOS, visionOS, and DriverKit 27.2 |
| `xcodegen` | installed at `/opt/homebrew/bin/xcodegen`, version 2.46.0 (the latest release, [2.46.0](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0)) |
| `tuist` | not installed |
| `brew` | installed, Homebrew 7.0.9 (latest is [7.0.13](https://github.com/Homebrew/brew/releases/tag/7.0.13)) |
| `gh` | 2.102.0 |
| `swift-format` | bundled with the Xcode toolchain (`swift format --version` reports 6.4.4) |
| `notarytool` / `stapler` | present via `xcrun` (notarytool 1.1.4) |
| `xcbeautify`, `swiftlint`, `create-dmg`, `mise` | not installed |
| Code-signing identities (`security find-identity -v -p codesigning`) | 0 valid identities |
| Xcode accounts | none signed in |

Xcode 27.x requires macOS Tahoe 26.6 or later to run, ships Swift 6.4, and deploys to macOS 12 through 27 ([Xcode support matrix](https://developer.apple.com/support/xcode/)).
The machine is current.
Before anything can be signed or notarized, the owner needs a paid developer account, a Developer ID Application certificate, and an App Store Connect API key.

## 1. Language and UI options

### Current Swift and Apple toolchain

Swift 6.4 was released on 2026-09-15 ([Swift 6.4 release](https://www.swift.org/blog/swift-6.4-released/)).
In that release, SwiftPM uses Swift Build as its default build system, and Swift Testing gained XCTest interoperability ([Swift 6.4 release](https://www.swift.org/blog/swift-6.4-released/)).
Xcode 27, 27.1, and 27.2 all ship Swift 6.4 ([Xcode support matrix](https://developer.apple.com/support/xcode/)).

### Options compared

| Option | CoreBluetooth access | Menu bar UX | Binary size | Permission handling | Maintainability |
| --- | --- | --- | --- | --- | --- |
| **Swift + SwiftUI `MenuBarExtra`** | Direct, first-class | Native; `.window` style gives a popover-like panel ([window style](https://developer.apple.com/documentation/swiftui/menubarextrastyle/window)) | Small (system frameworks are not bundled) | Standard Info.plist key and TCC prompt ([NSBluetoothAlwaysUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription)) | Best: one language, Apple-supported APIs |
| **Swift + AppKit `NSStatusItem`** | Direct | Native and fully controllable ([NSStatusItem](https://developer.apple.com/documentation/appkit/nsstatusitem)) | Small | Same | Good, but more imperative UI code |
| **Hybrid (SwiftUI app, AppKit where needed)** | Direct | Best of both | Small | Same | Good; the recommended fallback path |
| **Rust + btleplug (with Tauri or objc2)** | Via btleplug's CoreBluetooth backend ([btleplug](https://github.com/deviceplug/btleplug)) | Tauri tray plus a webview popover is not native-feeling; objc2 means hand-writing AppKit bindings | Tauri can be under 600 KB, using the system webview ([Tauri](https://v2.tauri.app/start/)) | Still needs a bundle with `NSBluetoothAlwaysUsageDescription` ([btleplug macOS notes](https://github.com/deviceplug/btleplug#macos)) | Two languages and an extra abstraction over CoreBluetooth; Tauri 3 is in alpha ([tauri-v3.0.0-alpha.6](https://github.com/tauri-apps/tauri/releases/tag/tauri-v3.0.0-alpha.6)) |
| **Go (tinygo-org/bluetooth)** | Via cgo bindings ([tinygo bluetooth](https://github.com/tinygo-org/bluetooth)) | No first-party menu bar toolkit | Medium | Needs a manual bundle | Weak fit for a GUI app |
| **Electron + Web Bluetooth** | Web Bluetooth only; the app must handle `select-bluetooth-device` itself ([Electron devices](https://www.electronjs.org/docs/latest/tutorial/devices)) | Webview popover | Large (bundles Chromium) | Chooser-based model | Battery Service is allowed, but the HID service is blocklisted ([GATT blocklist](https://github.com/WebBluetoothCG/registries/blob/master/gatt_blocklist.txt)) |
| **Python (bleak + rumps/PyObjC)** | Via bleak's CoreBluetooth backend ([bleak](https://github.com/hbldh/bleak)) | Basic | Large (bundled interpreter) | Manual bundling | Packaging and signing an interpreter is fragile |

Assessment (my judgment, based on the sources above):

- A ZMK keyboard is normally already connected to macOS as a HID device.
  CoreBluetooth's `retrieveConnectedPeripherals(withServices:)` returns peripherals that are connected to the system, including ones other apps connected, and the app then connects to them locally ([retrieveConnectedPeripherals](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals(withservices:))).
- Native Swift reaches this API directly.
  Cross-platform layers can only reach it through whatever subset they expose.
- Web Bluetooth's chooser model is a poor fit for a background utility.
- Every non-native option still has to produce a signed `.app` bundle with Info.plist keys and entitlements, so it adds a toolchain without removing any Apple-specific work.
- Recommendation: **Swift + SwiftUI `MenuBarExtra(.window)`**, falling back to an `NSStatusItem` that hosts SwiftUI in an `NSPopover`/`NSPanel` if `MenuBarExtra` limits become a problem.

### `MenuBarExtra` notes

- Available from macOS 13 ([MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)).
- A menu-bar-only app is terminated automatically if the user removes the extra from the menu bar.
  Apple suggests setting `LSUIElement` so the app does not appear in the Dock or app switcher ([MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)).
- Styles are `automatic`, `menu`, and `window` ([MenuBarExtraStyle](https://developer.apple.com/documentation/swiftui/menubarextrastyle)).
- The documented initializers accept a label view, title, image, and `isInserted` binding, and nothing else ([MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra)).
  There is no documented API to open or close the window programmatically.
  If the app later needs that (for example, to open the popover from a notification), it is the main reason to switch to `NSStatusItem`.
- A custom `label:` view can render two battery numbers in the menu bar ([MenuBarExtra init(content:label:)](https://developer.apple.com/documentation/swiftui/menubarextra)).

### Minimum macOS version for the recommended APIs

| API | Minimum macOS | Source |
| --- | --- | --- |
| `MenuBarExtra`, `.window` style | 13.0 | [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra), [window](https://developer.apple.com/documentation/swiftui/menubarextrastyle/window) |
| `SMAppService.mainApp` | 13.0 | [mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) |
| `openWindow` | 13.0 | [OpenWindowAction](https://developer.apple.com/documentation/swiftui/openwindowaction) |
| Observation (`@Observable`) | 14.0 | [Observation](https://developer.apple.com/documentation/observation) |
| `SettingsLink` | 14.0 | [SettingsLink](https://developer.apple.com/documentation/swiftui/settingslink) |
| `NSBluetoothAlwaysUsageDescription` | 11.0 | [NSBluetoothAlwaysUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription) |
| Sparkle 2.10.x runtime | 12.0 | [Sparkle README](https://github.com/sparkle-project/Sparkle#requirements) |
| Xcode 27 deployment floor | 12 | [Xcode support matrix](https://developer.apple.com/support/xcode/) |

The recommended deployment target is **macOS 14**, because `@Observable` is the cleanest state model for SwiftUI.
Raising it to 15 or 26 would cut test surface further at little user cost.
That is an owner decision (see the end of this document).

### Swift 6 strict concurrency and CoreBluetooth

Facts:

- `CBCentralManager(delegate:queue:)` dispatches events on the queue you pass, or on the main queue if `queue` is `nil`.
  This comes from the header comments in `CBCentralManager.h` in the local macOS 27.2 SDK.
  Apple's docs page for the initializer is [init(delegate:queue:options:)](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/init(delegate:queue:options:)).
- The CoreBluetooth headers in the macOS 27.2 SDK carry no `Sendable`, `NS_SWIFT_SENDABLE`, or main-actor annotations (checked with `grep` on the local SDK).
  `CBCentralManager`, `CBPeripheral`, and friends are therefore non-`Sendable` to Swift, and `CBCentralManagerDelegate` is a plain nonisolated `NSObjectProtocol` ([CBCentralManagerDelegate](https://developer.apple.com/documentation/corebluetooth/cbcentralmanagerdelegate)).
- Swift 6.2 added isolated conformances (SE-0470), which let a `@MainActor` type conform to a nonisolated protocol as `@MainActor Proto`, and added runtime checks on casts ([SE-0470](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0470-isolated-conformances.md)).
- Swift 6.2 also added module-wide default `MainActor` isolation (SE-0466), enabled in SwiftPM with `.defaultIsolation(MainActor.self)`.
  The proposal targets apps and executables and calls it "the wrong default for many kinds of modules" such as libraries ([SE-0466](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0466-control-default-actor-isolation.md), [defaultIsolation](https://developer.apple.com/documentation/packagedescription/swiftsetting/defaultisolation(_:_:))).
- The Swift 6 migration guide lists `@preconcurrency` conformances, which insert runtime isolation checks, and `nonisolated` witnesses as the remedies for a protocol conformance isolation mismatch ([Common Compiler Errors](https://github.com/swiftlang/swift-migration-guide/blob/main/Guide.docc/CommonProblems.md)).

Recommended pattern (my judgment):

- Battery traffic is a few bytes per minute, so performance does not justify a background queue.
- Create the central with `queue: nil` so delegate callbacks arrive on the main thread.
- Make the BLE adapter a `@MainActor final class` that conforms with `@MainActor CBCentralManagerDelegate` and `@MainActor CBPeripheralDelegate` (SE-0470).
  This avoids `nonisolated` plus `MainActor.assumeIsolated` boilerplate.
  If a conformance form does not compile against the ObjC protocol, use `@preconcurrency` conformance, which the migration guide documents.
- Never let `CBPeripheral` or `CBCharacteristic` escape the BLE module.
  Translate them into `Sendable` value types (`PeripheralID`, `BatteryReading { half, percent, timestamp }`) at the boundary, and publish them through an `AsyncStream` or a `@MainActor @Observable` store.
- Keep `Core` and protocol-parsing modules on the default `nonisolated` isolation with `Sendable` value types.
  Turn on `.defaultIsolation(MainActor.self)` only for the app target and UI feature modules, following SE-0466's guidance.
- If ZMK Studio RPC later needs heavy streaming, move the central to a private serial queue inside the BLE module and keep the same `Sendable` boundary.
  Nothing outside that module would change.

## 2. Project structure for extensibility

A practical layout:

```text
halfsies/
  project.yml                 # XcodeGen spec (the .xcodeproj is generated and gitignored)
  App/                        # thin app target: @main App, MenuBarExtra, Settings scene, AppKit glue
    Info.plist, Halfsies.entitlements (generated by XcodeGen from project.yml)
  HalfsiesKit/                # local Swift package, where nearly all code lives
    Package.swift
    Sources/
      HalfsiesCore/           # transport-agnostic model: Keyboard, Half, BatteryLevel, KeyboardTransport protocol, parsing
      HalfsiesBLE/            # CoreBluetooth adapter implementing KeyboardTransport
      HalfsiesBattery/        # feature: battery monitor store, low-battery policy
      HalfsiesNotifications/  # feature (later): UNUserNotificationCenter wrapper
      HalfsiesStudio/         # feature (later): ZMK Studio RPC client over BLE or serial transport
      HalfsiesUI/             # SwiftUI views shared by the popover and settings
    Tests/
      HalfsiesCoreTests/, HalfsiesBatteryTests/, ...
```

Design rules:

- **`HalfsiesCore`** has no Apple-framework imports beyond Foundation.
  It defines a small `KeyboardTransport` protocol (discover, connect, read, subscribe) and the domain model.
  Byte parsing, such as reading a Battery Level characteristic and mapping it to left or right, lives here as pure functions.
  That makes the code most worth testing trivially testable.
- **`HalfsiesBLE`** is the only module that imports CoreBluetooth.
  `CBPeripheral` cannot be constructed in tests, so do not try to mock CoreBluetooth itself.
  Mock at the `KeyboardTransport` seam instead, and keep the CoreBluetooth adapter thin enough to verify by hand on real hardware.
- **Feature modules** depend on `Core` and receive a `KeyboardTransport` by injection.
  "Plugins" should be compile-time Swift modules registered in the app's composition root, not runtime-loaded bundles.
  Loading code at runtime would conflict with Hardened Runtime library validation and complicate notarization ([Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime)).
- **App target** holds only the `@main` `App`, scene wiring, Sparkle, `SMAppService`, and Info.plist and entitlements.
- SwiftPM products are only libraries, executables, and plugins ([PackageDescription Product](https://developer.apple.com/documentation/packagedescription/product)).
  This is why the app target stays in Xcode while the logic lives in the package.

Testing:

- Use **Swift Testing** (`import Testing`, `@Test`, `#expect`) for all package tests.
  It ships with Swift 6 and Xcode 16 or later, supports parameterized tests and tags, and runs in parallel in-process ([Swift Testing](https://developer.apple.com/documentation/testing)).
- XCTest and Swift Testing interoperate as of Swift 6.4 ([Swift 6.4 release](https://www.swift.org/blog/swift-6.4-released/), [Migrating from XCTest](https://developer.apple.com/documentation/testing/migratingfromxctest)).
  Keep XCTest only for UI automation via `XCUIApplication` if that is ever wanted ([XCUIApplication](https://developer.apple.com/documentation/xctest/xcuiapplication)).
- `swift test` in `HalfsiesKit/` runs the package tests without Xcode project generation.
  That keeps the inner loop fast for agents and CI.
- Testing code that needs an entitlement or Info.plist key from a bare SwiftPM test bundle is a known pain point ([Swift Forums](https://forums.swift.org/t/swift-package-manager-use-of-info-plist-use-for-apps/6532)).
  This is one more reason to keep CoreBluetooth calls out of unit tests.

## 3. Build toolchain

### Options

| Option | Proper `.app` with Info.plist, entitlements, `LSUIElement` | Merge conflicts | Extra dependency | Notes |
| --- | --- | --- | --- | --- |
| **Plain Xcode project** | Yes | `project.pbxproj` conflicts, reduced by Xcode 16 synchronized ("buildable") folders ([XcodeGen spec on syncedFolder](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)) | None | Hard for agents and humans to review or edit `pbxproj` diffs |
| **SwiftPM only** | No: products are library, executable, or plugin only ([Product](https://developer.apple.com/documentation/packagedescription/product)); no first-class Info.plist generation for apps ([Swift Forums](https://forums.swift.org/t/swift-package-manager-use-of-info-plist-use-for-apps/6532)) | None | Custom bundling and signing scripts | You would hand-assemble `Contents/MacOS`, `Info.plist`, sign, and embed Sparkle.framework; fragile |
| **XcodeGen** | Yes; `info:` and `entitlements:` generate the files from YAML ([ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)) | None; the `.xcodeproj` can leave git ("no more merge conflicts") ([XcodeGen](https://github.com/yonaskolb/XcodeGen)) | One Swift CLI, MIT, already installed | Supports local Swift packages and `syncedFolder`; easy to "eject" by committing a generated project |
| **Tuist** | Yes, via `Project.swift` Swift manifests ([Tuist projects](https://tuist.dev/en/docs/guides/features/projects)) | None | Tuist CLI, recommended to install via mise ([Install Tuist](https://tuist.dev/en/docs/guides/install-tuist)) | Powerful; the CLI also connects projects to Tuist's cache, insights, and runner services ([Install Tuist](https://tuist.dev/en/docs/guides/install-tuist)); very frequent releases (stable [4.215.1](https://github.com/tuist/tuist/releases) on 2026-11-08) |

Recommendation: **XcodeGen**.

- A roughly 50-line `project.yml` is reviewable, diffable, and easy for agents to edit.
- It generates Info.plist and entitlements, and removes `pbxproj` conflicts.
- Lock-in is minimal, because the generated project is a normal Xcode project that can be committed if XcodeGen ever stalls.
- Tuist solves problems this single-app repo does not have, such as large modular graphs and binary caching.

Command-line builds use `xcodebuild` (flags checked with `xcodebuild -help` on Xcode 27.2):

```sh
xcodegen generate
xcodebuild -project Halfsies.xcodeproj -scheme Halfsies -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData -clonedSourcePackagesDirPath build/SourcePackages \
  -onlyUsePackageVersionsFromResolvedFile test
xcodebuild -project Halfsies.xcodeproj -scheme Halfsies -configuration Release \
  -archivePath build/Halfsies.xcarchive archive
xcodebuild -exportArchive -archivePath build/Halfsies.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export   # method: developer-id
```

The `developer-id` export method is listed in `xcodebuild -help` under the `-exportOptionsPlist` keys.
Apple documents the archive, export, and `ditto` packaging flow for scripted builds ([Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).

## 4. Info.plist keys and entitlements

| Key or entitlement | Value | Why | Source |
| --- | --- | --- | --- |
| `LSUIElement` | `true` | Agent app: no Dock icon or app-switcher entry | [LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement), [MenuBarExtra](https://developer.apple.com/documentation/swiftui/menubarextra) |
| `NSBluetoothAlwaysUsageDescription` | Short purpose string | "Required if your app uses the device's Bluetooth interface"; macOS 11+ | [NSBluetoothAlwaysUsageDescription](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription) |
| `SUFeedURL`, `SUPublicEDKey` | Appcast URL, EdDSA public key | Sparkle | [Sparkle docs](https://sparkle-project.org/documentation/) |
| Hardened Runtime (`ENABLE_HARDENED_RUNTIME=YES`) | on | Required for notarization | [Hardened Runtime](https://developer.apple.com/documentation/security/hardened-runtime) |
| `com.apple.security.get-task-allow` | absent in Release | Notarization rejects it | [Notarizing](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) |
| `com.apple.security.app-sandbox` | optional (see below) | Required for the Mac App Store | [App Sandbox](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.app-sandbox), [Configuring the App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox) |
| `com.apple.security.device.bluetooth` | `true` if sandboxed | Bluetooth access inside the sandbox | [device.bluetooth](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.bluetooth) |
| `com.apple.security.network.client` | `true` if sandboxed | Sparkle appcast and downloads | [network.client](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.client), [Sparkle sandboxing](https://sparkle-project.org/documentation/sandboxing/) |
| `com.apple.security.device.serial` / `device.usb` | later, if sandboxed and using ZMK Studio over USB | Serial or USB device access | [Entitlement Key Reference (archive)](https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html), [device.usb](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.usb) |

Sandbox notes:

- Entitlements only declare intent.
  The user still grants the actual Bluetooth permission through the system prompt ([Configuring the App Sandbox](https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox)).
- Sparkle in a sandboxed app needs its Installer XPC service (`SUEnableInstallerLauncherService`) and a `mach-lookup` temporary-exception entitlement ([Sparkle sandboxing](https://sparkle-project.org/documentation/sandboxing/)).
- Recommendation: start **non-sandboxed** under Developer ID, which is simpler with Sparkle and leaves future USB serial work open.
  Keep the code sandbox-clean (no arbitrary file access) so the sandbox can be enabled later if the Mac App Store becomes a goal.
  This is an owner decision.

Launch at login:

- Use `SMAppService.mainApp.register()` and `unregister()`, available on macOS 13 and later ([SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice), [mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)).
- Read `status` to reflect the real state in Settings ([status](https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.property)).
- Offer `SMAppService.openSystemSettingsLoginItems()` when approval is required ([openSystemSettingsLoginItems](https://developer.apple.com/documentation/servicemanagement/smappservice/opensystemsettingsloginitems())).
- Do not enable it silently.
  Mac App Store guideline 2.4.5(iii) forbids auto-launch without consent, and the same courtesy is right for Developer ID builds ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)).

## 5. Signing, notarization, distribution

### Developer ID versus the Mac App Store

| | Developer ID (direct) | Mac App Store |
| --- | --- | --- |
| Membership | Paid program; only the Account Holder can create the Developer ID certificate ([Developer ID](https://developer.apple.com/developer-id/)) | Paid program ([Compare memberships](https://developer.apple.com/support/compare-memberships/)) |
| Sandbox | Optional | Mandatory, guideline 2.4.5(i) ([App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)) |
| Updates | Sparkle or your own updater | MAS only; "other update mechanisms are not allowed", 2.4.5(vii) |
| Review | Automated notarization only; "not App Review" ([Notarizing](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)) | Human review on every release |
| Homebrew | Natural fit | Not applicable |
| Fit for halfsies | Fast iteration, open-source friendly, GitHub Releases | Discoverability; sandbox constraints on future serial and USB work |

Recommendation: **Developer ID first**.
The Mac App Store could be added later as a second, sandboxed build flavour, but that doubles the release work, so treat it as an explicit future decision.

### Membership and cost

- The Apple Developer Program costs 99 USD per membership year.
  Individuals need an Apple Account with two-factor authentication.
  Organizations also need a D-U-N-S number, a legal entity, and a public website ([Enroll](https://developer.apple.com/programs/enroll/)).
- The paid program is what provides Developer ID certificates and the notary service ([Developer ID](https://developer.apple.com/developer-id/)).
- Software distributed with Developer ID must be notarized on macOS 10.15 and later ([Notarizing](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).

### Notarization flow

Notarization requirements: Developer ID signature, Hardened Runtime, secure timestamp, no `get-task-allow`, and a link against the macOS 10.9 SDK or later ([Notarizing](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).

1. Archive and export with method `developer-id`.
   Xcode signs with Hardened Runtime and a timestamp.
2. Zip the app with `ditto -c -k --keepParent Halfsies.app Halfsies.zip` ([Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).
3. Submit with `xcrun notarytool submit Halfsies.zip --key AuthKey.p8 --key-id <id> --issuer <uuid> --wait`.
   The App Store Connect API key options come from `notarytool submit --help` on Xcode 27.2.
   Apple also documents `--keychain-profile` for local use ([Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).
4. Always fetch the log with `notarytool log <id>`, because it can contain warnings even on success ([Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).
5. Staple the app with `xcrun stapler staple Halfsies.app`.
   A zip cannot be stapled, so staple the items inside and re-zip ([Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).
6. Build the DMG with `hdiutil`, containing the stapled app and an `/Applications` symlink.
   Sign the DMG, notarize it (the service accepts UDIF disk images), and staple it ([Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).
7. Most submissions finish within 5 minutes, and 98 percent within 15 minutes.
   Stay under 75 notarizations per day ([Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).
8. The `altool` path has been dead since 2023-11-01 ([Notarizing](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).

### How unsigned or ad-hoc builds behave now

- On Apple silicon, every executable must be signed, but an ad-hoc signature is enough to run, and the linker applies one automatically ([Big Sur universal apps release notes](https://developer.apple.com/documentation/macos-release-notes/macos-big-sur-11_0_1-universal-apps-release-notes)).
- A downloaded (quarantined) app that is not notarized gets a warning that macOS "can't verify that the app is free of malware" ([Apple Support 102445](https://support.apple.com/en-us/102445)).
- Since macOS Sequoia, users can no longer Control-click to override Gatekeeper.
  They must go to System Settings > Privacy & Security and click "Open Anyway" ([Apple Developer News, 2024-08-06](https://developer.apple.com/news/?id=saqachfa), [Apple Support 102445](https://support.apple.com/en-us/102445)).
- I found no primary source describing further Gatekeeper changes in macOS 27.
- In practice, unsigned or ad-hoc release builds are a poor experience for non-technical users, and Homebrew no longer accepts them in its main cask repository (below).
  Notarized Developer ID builds open with only the standard first-launch confirmation ([Notarizing](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)).

### DMG versus zip

- Sparkle accepts `.dmg`, `.zip`, `.tar.*`, and `.aar` ([Sparkle publishing](https://sparkle-project.org/documentation/publishing/)).
- The notary service accepts zip, UDIF DMG, and flat pkg ([Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).
- A zip needs one notarization round and is the smallest moving part.
  A DMG gives the familiar drag-to-Applications experience and can carry its own stapled ticket.
- Recommendation: ship **one notarized and stapled DMG** to people, Sparkle, and Homebrew alike.
  If release complexity needs trimming, a stapled-app zip is an acceptable alternative.

### Homebrew cask

- Homebrew 5.0.0 deprecated casks without code signing and planned to disable casks in `homebrew/cask` that fail Gatekeeper checks in September 2026.
  It also deprecated `--no-quarantine` ([Homebrew 5.0.0](https://brew.sh/2025/11/12/homebrew-5.0.0/)).
  Homebrew 6.0.0 restated that schedule ([Homebrew 6.0.0](https://brew.sh/2026/06/11/homebrew-6.0.0/)).
- The current acceptance policy says casks must not require Gatekeeper to be bypassed, and that Gatekeeper-assessable artifacts must pass Homebrew's Gatekeeper checks ([Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)).
  In practice, this means **notarization is required for `homebrew/cask`**.
- `homebrew/cask` also has notability requirements.
  New apps need "substantial, independently verifiable public interest" ([Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)).
  A brand-new app should therefore start in its own tap.
- **Own tap:** a repo named `homebrew-tap` with `Casks/halfsies.rb`.
  Cask names should be globally unique, so consider a prefix ([How to Create and Maintain a Tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)).
  Since Homebrew 6.0.0, users must explicitly trust third-party taps before their code runs ([Homebrew 6.0.0](https://brew.sh/2026/06/11/homebrew-6.0.0/), [Tap docs](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap)).
  Document the trust step in the README.
- **Cask stanzas:** `auto_updates true`, because Sparkle provides "Check for Updates…".
  `livecheck do strategy :sparkle end` points at the appcast.
  `depends_on macos: ">= :sonoma"` sets the minimum.
  A `zap` stanza covers preferences ([Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)).
- Homebrew 7 keeps an opt-out (`HOMEBREW_NO_UPGRADE_AUTO_UPDATES_CASKS`) for self-updating apps ([Homebrew 7.0.0](https://brew.sh/2026/09/13/homebrew-7.0.0/)).

### Auto-updates with Sparkle 2

- **Version:** current is 2.10.1 (2026-10-25).
  The 2.10 line requires macOS 12 or later because Xcode 27 dropped older deployment targets ([Sparkle 2.10.1](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.1), [Sparkle README](https://github.com/sparkle-project/Sparkle#requirements)).
- **Install:** add Sparkle as a Swift package.
  Set `SUFeedURL` and `SUPublicEDKey` in Info.plist ([Sparkle docs](https://sparkle-project.org/documentation/)).
- **SwiftUI wiring:** create `SPUStandardUpdaterController(startingUpdater: true, ...)` in the `App` initializer.
  Expose a "Check for Updates…" button bound to `canCheckForUpdates` ([Sparkle programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/)).
  In a menu-bar-only app, put the button in the popover and in Settings, not in a main menu.
- **Keys:** run `generate_keys` once.
  It stores the EdDSA private key in the login keychain and prints the public key.
  Keep the key safe, because losing it breaks updates ([Sparkle docs](https://sparkle-project.org/documentation/)).
  Export it to a GitHub Actions secret for CI.
- **Appcast generation:** `generate_appcast` signs archives, creates deltas, and writes the appcast ([Sparkle publishing](https://sparkle-project.org/documentation/publishing/)).
  In CI, pipe the key in with `echo "$SPARKLE_ED_PRIVATE_KEY" | generate_appcast --ed-key-file - --download-url-prefix https://github.com/<owner>/halfsies/releases/download/vX.Y.Z/ <dir>` ([generate_appcast source](https://github.com/sparkle-project/Sparkle/blob/2.x/generate_appcast/main.swift)).
- **Hosting:** host `appcast.xml` on GitHub Pages (a `gh-pages` branch or Pages artifact).
  The DMG enclosures stay on GitHub Releases.
  The feed URL then stays stable across releases.
  Sparkle only needs HTTPS URLs ([Sparkle publishing](https://sparkle-project.org/documentation/publishing/)).
- **Extras:** set `sparkle:minimumSystemVersion`.
  Channels (for example, beta), critical updates, and phased rollouts are available when needed ([Sparkle publishing](https://sparkle-project.org/documentation/publishing/)).
- **Signing:** Sparkle's docs recommend Developer ID plus notarization, and warn that ad-hoc signed Debug builds may fail to load Sparkle under library validation ([Sparkle docs](https://sparkle-project.org/documentation/)).

## 6. CI/CD on GitHub Actions

### Runner images available now

| Label | OS | Xcode | Status |
| --- | --- | --- | --- |
| `xcode-27`, `xcode-27-xlarge` | macOS 27, arm64 | Xcode 27 line | GA since 2026-10-15 ([changelog](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/)); the README badge still says preview ([runner-images](https://github.com/actions/runner-images)) |
| `macos-latest`, `macos-26`, `macos-26-xlarge` | macOS 26, arm64 | Xcode 26.0.1 to 26.6 (26.5 default) | GA ([runner-images](https://github.com/actions/runner-images), [issue 14404](https://github.com/actions/runner-images/issues/14404)) |
| `macos-15`, `macos-15-xlarge` | macOS 15, arm64 | Xcode 16 line | GA ([runner-images](https://github.com/actions/runner-images)) |
| `macos-26-intel`, `macos-15-intel` | x64 | as above | GA ([GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)) |
| `macos-14` | | | Retired from GitHub Actions on 2026-11-02 ([runner-images](https://github.com/actions/runner-images)) |

Notes:

- GitHub moved to "one major Xcode version" per image, with the new `xcode-NN` labels ([changelog](https://github.blog/changelog/2026-10-15-xcode-27-runner-image-generally-available/)).
  **Pin `runs-on: xcode-27`** so CI matches the local Xcode 27.2 and Swift 6.4.
  Select the exact Xcode inside the job with `sudo xcode-select -s` if several minor versions are present.
- Standard arm64 macOS runners have 3 M1 CPUs and 7 GB RAM.
  They are free and unlimited for public repos and billed per minute for private repos ([GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)).

### Signing in CI

GitHub's documented recipe ([Sign Xcode applications](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)):

- Store the Developer ID Application `.p12` as a base64 secret, plus `P12_PASSWORD` and a random `KEYCHAIN_PASSWORD`.
- Run `security create-keychain`, then `set-keychain-settings -lut 21600`, then `unlock-keychain`.
- Run `security import ... -A`, then `security set-key-partition-list -S apple-tool:,apple:`, then `security list-keychain -d user -s`.
- Hosted runners are destroyed after each job.
  Self-hosted runners need an `if: always()` cleanup step.
- A Developer ID app with no restricted capabilities does not need a provisioning profile.
  Use manual signing in `ExportOptions.plist` (`method: developer-id`, `signingStyle: manual`, `teamID`) so CI does not need an Apple account session.

### Notarizing in CI

- Use an App Store Connect API key (`.p8` as a secret, plus key ID and issuer ID) with `notarytool submit --key/--key-id/--issuer --wait`.
  This avoids storing an Apple ID password (options from `notarytool submit --help`).
- The runner needs outbound access to the notary S3 endpoint and the CloudKit ranges for `stapler` ([Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).
  Hosted runners have this.

### Release automation

- **release-please** (`googleapis/release-please-action`, latest v5.0.0) reads Conventional Commits and maintains a release PR with the version bump and changelog.
  Merging that PR creates the tag and GitHub Release.
  `release-type: simple` fits a non-language-specific repo ([release-please-action](https://github.com/googleapis/release-please-action), [v5.0.0](https://github.com/googleapis/release-please-action/releases/tag/v5.0.0)).
  Use a PAT or GitHub App token so the created tag can trigger the build workflow, because the default `GITHUB_TOKEN` does not trigger further workflows ([release-please-action](https://github.com/googleapis/release-please-action)).
  This also respects the owner's rule against hand-editing `CHANGELOG.md`.
- **Workflows:**
  - `ci.yml` runs on PRs: `swift test` in the package, `xcodegen generate`, `xcodebuild test`, and a `swift format lint` check.
  - `release-please.yml` runs on pushes to `main`.
  - `release.yml` runs on `v*` tags or on release-please output.
    It archives, exports, notarizes, staples, builds and notarizes the DMG, uploads it to the release, runs `generate_appcast`, publishes the appcast to Pages, and bumps the tap's cask (a PR or commit to `homebrew-tap`).
- **Version source:** set `MARKETING_VERSION` from the tag.
  Set `CURRENT_PROJECT_VERSION` (`CFBundleVersion`, which Sparkle compares) to a monotonically increasing number such as the CI run number or a commit count.

### Caching

- Cache `build/SourcePackages` (set with `-clonedSourcePackagesDirPath`), keyed on `Package.resolved`, using `actions/cache` ([actions/cache](https://github.com/actions/cache)).
- Optionally cache the package's `.build` keyed on `Package.resolved` plus the toolchain version.
- Caching DerivedData for a small app is rarely worth it.
- Use `-onlyUsePackageVersionsFromResolvedFile` so CI never re-resolves dependencies (flag listed in `xcodebuild -help`).

## 7. Recommended stack and "zero to published release"

**Stack:**

- Swift 6.4 in Swift 6 language mode.
- SwiftUI `MenuBarExtra(.window)` with `@Observable` stores, and AppKit only where needed.
- CoreBluetooth in a single `@MainActor` adapter behind a `KeyboardTransport` protocol.
- A local `HalfsiesKit` Swift package (Core, BLE, features, UI).
- Swift Testing.
- XcodeGen.
- Xcode 27.2 locally and the `xcode-27` runner in CI.
- Developer ID, Hardened Runtime, notarytool, and stapler.
- A notarized DMG on GitHub Releases.
- Sparkle 2.10 with the appcast on GitHub Pages.
- An own Homebrew tap.
- release-please.
- Minimum macOS 14.

**Steps:**

1. Enroll in the Apple Developer Program as an individual or organization ([Enroll](https://developer.apple.com/programs/enroll/)).
   Decide the seller name and bundle ID prefix, for example `dev.<owner>.halfsies`.
2. As Account Holder, create a **Developer ID Application** certificate ([Developer ID](https://developer.apple.com/developer-id/)).
   Export it as `.p12`.
3. Create an **App Store Connect API key** for notarization.
   Store the `.p8`, key ID, and issuer ID.
4. Generate Sparkle EdDSA keys with `generate_keys` and back up the private key ([Sparkle docs](https://sparkle-project.org/documentation/)).
5. Scaffold the repo: `project.yml` (app target with `info:` and `entitlements:`, Hardened Runtime, `LSUIElement`, `NSBluetoothAlwaysUsageDescription`, `SUFeedURL`, `SUPublicEDKey`), plus `HalfsiesKit/Package.swift`, `ExportOptions.plist`, and a `.gitignore` that excludes `*.xcodeproj`.
6. Implement v1:
   - `Core` model and battery parsing, test-first with Swift Testing.
   - The `BLE` adapter using `retrieveConnectedPeripherals(withServices:)` plus Battery Service reads and notifications.
   - The `MenuBarExtra` label showing L and R percentages.
   - A popover and a Settings scene with a launch-at-login toggle via `SMAppService.mainApp`.
   - Sparkle's "Check for Updates…".
7. Add `ci.yml` on `xcode-27`: package tests, XcodeGen, `xcodebuild test`, format lint.
8. Add GitHub secrets: `DEVELOPER_ID_P12_BASE64`, `P12_PASSWORD`, `KEYCHAIN_PASSWORD`, `ASC_KEY_P8_BASE64`, `ASC_KEY_ID`, `ASC_ISSUER_ID`, `SPARKLE_ED_PRIVATE_KEY`, and `RELEASE_TOKEN` (PAT or App token for release-please and the tap).
9. Add `release-please.yml` and `release.yml`:
   1. Import the certificate into a temporary keychain ([Sign Xcode applications](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)).
   2. `xcodebuild archive` and `-exportArchive` with method `developer-id`.
   3. Zip, notarize, and staple the app; then create, sign, notarize, and staple the DMG ([Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)).
   4. Verify with `spctl -a -vv` and `codesign --verify --deep --strict` as a sanity gate.
   5. Upload the DMG to the GitHub Release.
   6. Run `generate_appcast --ed-key-file -` and publish `appcast.xml` to Pages ([Sparkle publishing](https://sparkle-project.org/documentation/publishing/)).
   7. Update `Casks/halfsies.rb` in `homebrew-tap` with the new version and sha256 ([Cask Cookbook](https://docs.brew.sh/Cask-Cookbook)).
10. Create the `homebrew-tap` repo.
    Document `brew tap <owner>/tap`, the tap-trust step ([Homebrew 6.0.0](https://brew.sh/2026/06/11/homebrew-6.0.0/)), and `brew install --cask halfsies`.
11. Merge a `feat:` commit, merge the release-please PR, and watch the tag build publish v0.1.0.
12. On a clean Mac (or a fresh user account), download the DMG.
    Confirm Gatekeeper opens it without warnings, the Bluetooth prompt appears with the purpose string, both halves' batteries show, and the next release arrives through Sparkle.

## Open decisions for the owner

1. **Deployment target:** macOS 14 (recommended; Observation and `SettingsLink`), 15, or 26.
   A higher target means less testing, but excludes users who have not upgraded.
2. **Architectures:** universal (arm64 plus x86_64) or Apple-silicon-only.
   Reports say macOS 26 Tahoe is the last release for Intel Macs ([Six Colors](https://sixcolors.com/post/2025/06/macos-tahoe-is-the-last-release-to-support-intel/), secondary source).
   Homebrew moved Intel to Tier 3 in September 2026 ([Homebrew 5.0.0](https://brew.sh/2025/11/12/homebrew-5.0.0/)).
   Universal costs little now, but doubles the test matrix in principle.
3. **Sandbox and Mac App Store:** stay non-sandboxed Developer ID only (recommended for v1), or sandbox from day one to keep a Mac App Store option open.
   The cost is Sparkle XPC setup and constraints on future USB serial work for ZMK Studio ([Sparkle sandboxing](https://sparkle-project.org/documentation/sandboxing/), [App Review 2.4.5](https://developer.apple.com/app-store/review/guidelines/)).
4. **Developer account type:** individual (fast; your legal name shows as the seller) or organization (needs a D-U-N-S number and website) ([Enroll](https://developer.apple.com/programs/enroll/)).
5. **Project generator:** XcodeGen (recommended) or a committed Xcode project with synchronized folders (zero tools, but `pbxproj` diffs).
   Tuist is not recommended for this size.
6. **Artifact format:** a notarized DMG (recommended) or a zip of the stapled app (one notarization round fewer).
7. **Repository visibility:** a public repo gets free, unlimited macOS CI minutes.
   A private repo pays per minute ([GitHub-hosted runners](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)).
8. **License and Homebrew target:** own tap only, or also aim for `homebrew/cask` once the app has demonstrable public interest ([Acceptable Casks](https://docs.brew.sh/Acceptable-Casks)).
9. **Release cadence tooling:** release-please (recommended, PR-based, Conventional Commits) or plain tag-push releases with generated notes.
