# Halfsies research summary

Research done on 2026-11-09 to scope a net-new macOS menu bar app for ZMK split keyboards.
The first feature is showing the battery level of both halves.
This page combines three detailed reports; each claim is cited in the report it comes from.

| Report | Covers |
| --- | --- |
| [01-zmk-and-macos-ble.md](01-zmk-and-macos-ble.md) | How ZMK exposes split battery, what macOS and CoreBluetooth allow, ZMK Studio RPC |
| [02-prior-art.md](02-prior-art.md) | About 20 existing tools on macOS, Windows, Linux, and Python, analysed at the source level |
| [03-language-build-publish.md](03-language-build-publish.md) | Language, project layout, build toolchain, signing, notarization, distribution, CI |
| [04-layer-display.md](04-layer-display.md) | Ways a host app can learn the active ZMK layer, for the future layer display |

## Key findings

### The data is already there, if the firmware is configured

- Stock ZMK can expose the other half's battery to the host, but only when the central half is built with `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y` and `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y`.
- Both options default to off on ZMK `main` as of 2026-10-09, so users need a firmware config change and reflash.
- With the proxy on, the central adds a second Battery Service (0x180F) with its own Battery Level (0x2A19) characteristic, which supports notifications.
- The halves can be told apart from descriptors rather than order: the peripheral's level has a User Description (0x2901) of `Peripheral N` and a Presentation Format (0x2904) description of `0x0108` ("auxiliary"), while the central's own level is `0x0106` ("main").
- macOS already reads both halves.
  On this Mac, `pmset -g accps` lists the "Forager" keyboard twice (39% and 86%), even though the system UI shows only one value.

### Two ways to read it on macOS

1. **CoreBluetooth (public, recommended).**
   Attach to the connection macOS already holds with `retrieveConnectedPeripherals(withServices:)`, discover both Battery Service instances, read the descriptors, and subscribe to notifications.
   Every working macOS tool in the survey does this, so it is proven in practice.
   It needs `NSBluetoothAlwaysUsageDescription`, plus the Bluetooth entitlement if sandboxed.
2. **IOKit power sources (private, optional fallback).**
   `IOPSCopyPowerSourcesByType` returns what `pmset` shows, with no GATT client and no Bluetooth prompt.
   It is undocumented, could break in any macOS release, and rules out the Mac App Store.

### What existing tools teach us

- The strongest native example is [itouuuuuuuuu/zmk-battery-bar](https://github.com/itouuuuuuuuuu/zmk-battery-bar) (Swift, notarized, Homebrew), and the most popular cross-platform one is [kot149/zmk-battery-center](https://github.com/kot149/zmk-battery-center) (Tauri and Rust).
  We studied them only to learn what works and will not fork or copy them.
- Tools that identify halves by discovery or callback order can silently swap left and right.
  Halfsies should identify halves by descriptors and let the user confirm which side is left, because ZMK assigns peripheral slots by bonding order.
- A sleeping or disconnected half reads as 0%, which causes false low-battery alerts in other tools.
- macOS caches the GATT layout, so after enabling the proxy users may have to remove and re-pair the keyboard.
- A misconfigured firmware looks like an app bug unless the app detects it and explains the fix.

### Gaps no existing tool fills

- A native macOS app designed to grow beyond battery, for example with a ZMK Studio client for layers and keymaps.
- Telling a disconnected half apart from a real 0%.
- Monitoring several keyboards at once in a native app.
- Battery over a USB-connected dongle, which has no path on ZMK `main` yet (open ZMK PR [#3458](https://github.com/zmkfirmware/zmk/pull/3458)).

### Risks to track

- Open ZMK bug [#3522](https://github.com/zmkfirmware/zmk/issues/3522) can corrupt memory on the central when the host disconnects with battery fetching on.
  Watch the fix in [#3556](https://github.com/zmkfirmware/zmk/pull/3556) before recommending the config to users.
- ZMK PR #3458 would change the GATT layout (left and right Presentation Format values that macOS 26 shows natively), so identification logic must accept both layouts.
- ZMK Studio RPC has no battery messages, so it is a path for future features, not for this one.

## Recommended stack

- **Language and UI:** Swift 6 with strict concurrency, SwiftUI `MenuBarExtra` (window style) and `@Observable`, AppKit `NSStatusItem` only if we ever need to open the popover from code.
- **Minimum macOS:** 14 (open decision; see below).
- **Layout:** a thin Xcode app target plus a local Swift package where nearly all code lives.
  - `HalfsiesCore`: transport-agnostic domain model (keyboard, part, battery reading) and pure parsing, Foundation only.
  - `HalfsiesBLE`: the only module that imports CoreBluetooth, implementing a `KeyboardTransport` protocol.
  - Feature modules (`HalfsiesBattery` first; later notifications, ZMK Studio RPC, and so on) depend on Core and receive a transport by injection.
  - Tests use Swift Testing against fake transports instead of mocking CoreBluetooth.
- **Build:** XcodeGen `project.yml` with the generated `.xcodeproj` kept out of git, `swift test` for the package, `xcodebuild` for the app.
- **Distribution:** Developer ID signed, hardened runtime, notarized DMG on GitHub Releases, Sparkle 2 for updates, and our own Homebrew tap.
- **CI:** GitHub Actions macOS runners with Xcode 27, release-please for versions and changelogs, signing and notarization in a temporary keychain.

The local toolchain is ready (Xcode 27.2, Swift 6.4.2, XcodeGen 2.46.0, Homebrew), but there is no code-signing identity yet.

## Next step: hardware spike

Before writing the app, a small throwaway spike against the connected Forager should answer:

1. Does `retrieveConnectedPeripherals(withServices:)` return the keyboard, and does service discovery return both Battery Service instances?
2. Can the app read the 0x2901 and 0x2904 descriptors, and do the values match what `pmset` reports?
3. Do notifications arrive on characteristics that macOS has already subscribed to?
4. Does the private IOKit path work from a hardened-runtime app, and does it notify on level changes?

Report 01 lists the full set of nine open questions.

## Decisions

Recorded 2026-11-09.

- **No Apple Developer Program.**
  No Developer ID signing, notarization, or Mac App Store.
  Local builds are signed with a free Apple ID "Personal Team" development certificate so the Bluetooth permission survives rebuilds.
  Release downloads, if any, are unsigned or ad-hoc signed and need "Open Anyway" in System Settings.
  Sparkle and the Homebrew tap are deferred until distribution matters.
- **Deployment target:** the current macOS only (26 and later), no back-compat work.
- **Sandbox:** off. Plain unsandboxed app, which is the easiest path.
- **Private IOKit reader:** not shipped. Public CoreBluetooth only; `pmset` is used only as a cross-check during the spike.
- **Repository:** private for now, may become public. CI is build and test only, so macOS runner minutes stay small.
- **Language:** Swift, because the app is macOS-only and CoreBluetooth, the menu bar, and the bundle tooling are all native Apple APIs.
  Rust with Tauri is the alternative if Windows and Linux support ever become a goal.
