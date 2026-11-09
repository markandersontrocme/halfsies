# 02 - Prior art: tools that show ZMK split battery levels

Survey date: 2026-11-09.
Star counts and "last push" dates are as of that day.
Source links are pinned to the commit that was current on that day, so line numbers stay valid.
We read the source of every project listed below; no project was cloned into this repository, built, or run.

## TL;DR

- At least a dozen open source tools already show both halves of a ZMK split, and every one that works reads the same thing: two or more Battery Service (0x180F) instances on the central half, each with a Battery Level (0x2A19) characteristic, which stock ZMK exposes when `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY` and `..._FETCHING` are on ([ZMK docs](https://zmk.dev/docs/config/battery), [central_bas_proxy.c L45-L69](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb/app/src/split/bluetooth/central_bas_proxy.c#L45-L69)).
- On macOS, every working tool uses public CoreBluetooth, attaching to the connection macOS already holds for HID via `retrieveConnectedPeripherals(withServices:)` or `retrievePeripherals(withIdentifiers:)` ([zmk-battery-bar BLEManager.swift L85](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L85), [L145](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L145)).
None of them needs a private framework or IOKit for the battery data.
- The robust way to tell the halves apart is the descriptors: stock ZMK gives each proxied peripheral level a Characteristic User Description (0x2901) of `"Peripheral N"` and a Presentation Format (0x2904) description of 0x0108 "auxiliary", while the central's own level has no 0x2901 and a 0x2904 description of 0x0106 "main" ([central_bas_proxy.c L45-L65](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb/app/src/split/bluetooth/central_bas_proxy.c#L45-L65), [Zephyr bas.c L67-L80](https://github.com/zmkfirmware/zephyr/blob/v4.1.0%2Bzmk-fixes/subsys/bluetooth/services/bas/bas.c#L67-L80)).
The mature tools use "has a User Description" as the rule; the weaker ones use discovery order or callback order, and those break.
- The two most mature projects are [kot149/zmk-battery-center](https://github.com/kot149/zmk-battery-center) (Tauri + Rust `bluest`, cross-platform, unsigned on macOS) and [itouuuuuuuuu/zmk-battery-bar](https://github.com/itouuuuuuuuu/zmk-battery-bar) (native Swift, signed, notarized, Homebrew cask).
Both subscribe to notifications and keep a slow read as a safety net.
- macOS itself shows only one level for stock ZMK ([Katona on ZMK PR #1243](https://github.com/zmkfirmware/zmk/pull/1243#issuecomment-1100389963), [Mighty Mitts README](https://github.com/codyd51/Mighty-Mitts/blob/75da8660599d/README.md)).
An unmerged ZMK PR shows that tagging the two levels with Presentation Format "left" (0x010D) and "right" (0x010E) makes macOS 26 show `L 98% R 100%` natively in the Bluetooth menu ([ZMK PR #3458 comment](https://github.com/zmkfirmware/zmk/pull/3458#issuecomment-6209774162)).
- Gaps nobody fills well: a native, signed macOS app that is built to grow beyond battery (ZMK Studio RPC, layers), handles USB-dongle setups without a forked firmware, distinguishes "peripheral asleep or disconnected" from "0%", and identifies halves without heuristics for 3+ part splits.

## Comparison table

| Project | Platform | Stack | License | Stars | Last push | Data source | Central vs peripheral | Firmware needs | Distribution |
|---|---|---|---|---|---|---|---|---|---|
| [kot149/zmk-battery-center](https://github.com/kot149/zmk-battery-center) | macOS, Windows, Linux | Tauri v2, Rust `bluest` 0.6, React | MIT | 197 | 2026-11-03 | `bluest` (CoreBluetooth / WinRT / BlueZ), notify or poll | 0x2901 present = its text, absent = "Central" | Stock PROXY + FETCHING | Homebrew tap (unsigned, `brew trust`), GitHub Releases, curl install script |
| [itouuuuuuuuu/zmk-battery-bar](https://github.com/itouuuuuuuuu/zmk-battery-bar) | macOS 14+ | Swift 6, SwiftPM, AppKit + SwiftUI | MIT | 82 | 2026-10-24 | CoreBluetooth notify + 60 s read | 0x2901 substring, sibling inference, index fallback | Stock PROXY + FETCHING | Homebrew cask, Developer ID signed, notarized |
| [codyd51/Mighty-Mitts](https://github.com/codyd51/Mighty-Mitts) | macOS | Objective-C, Xcode | None in repo (README says MIT) | 79 | 2026-09-25 | CoreBluetooth read every 60 s | Alternating callback order | Stock PROXY + FETCHING | Prebuilt zip on GitHub Releases |
| [Maksim-Isakau/zmk-split-battery](https://github.com/Maksim-Isakau/zmk-split-battery) | Windows 10 19041+ | C# .NET 9 WinForms, WinRT GATT | MIT | 109 | 2025-08-05 | WinRT `GattCharacteristic` uncached read + `ValueChanged` | `GattCharacteristic.UserDescription`, else "Main" | Stock PROXY + FETCHING | Zip on GitHub Releases |
| [rleyvasal/zmk-next-battery](https://github.com/rleyvasal/zmk-next-battery) | macOS 13+ | Swift, shell build | None | 0 | 2026-11-06 | CoreBluetooth; USB via ZMK Studio serial port with a custom frame | 0x2901 text ("left/central/right/peripheral") + sibling inference | BT: stock. USB: "ZMK Next" fork + `zmk-studio-log` module | Ad-hoc signed zip, not notarized |
| [mh4x0f/zmkBATx](https://github.com/mh4x0f/zmkBATx) | Linux | C++, Qt6, SimpleBluez (D-Bus) | MIT | 57 | 2025-01-03 | BlueZ `GattCharacteristic1.ReadValue` | 0x2901 present = Peripheral, else Central (one slot each) | Stock PROXY + FETCHING | AUR, nixpkgs ([AUR](https://aur.archlinux.org/packages/zmkbatx), [MyNixOS](https://mynixos.com/nixpkgs/package/zmkBATx)) |
| [lihaoyun6/AirBattery](https://github.com/lihaoyun6/AirBattery) | macOS 11+ | Swift, SwiftUI, WidgetKit | AGPL-3.0 | 2997 | 2025-11-02 | CoreBluetooth scan of all BLE devices; `system_profiler`; IORegistry | None, keyed by device name (last value wins) | n/a | Homebrew tap, GitHub Releases |
| [Katona/zmk-ble](https://github.com/Katona/zmk-ble) | macOS | SwiftUI, Xcode | MIT | 13 | 2023-01-21 | CoreBluetooth | Exact 0x2901 strings "Central" / "Peripheral" | Unmerged PR #1243 era firmware (obsolete) | Source only |
| [JanValiska/ZmkBatteryClient](https://github.com/JanValiska/ZmkBatteryClient) | Linux (Waybar) | Rust `bluer` | MIT | 8 | 2025-12-16 | BlueZ D-Bus read | 0x2901 present = peripheral, else "Central" | Stock | Source (cargo) |
| [ngbucsit/sketchybar-zmk-battery](https://github.com/ngbucsit/sketchybar-zmk-battery) | macOS (SketchyBar plugin) | Swift CLI | None | 1 | 2026-11-02 | CoreBluetooth | "Peripheral N" parse + 0x2904 = 0x0108 | Stock | Source (swift build) |
| [meta-boy/cornix-hud](https://github.com/meta-boy/cornix-hud) | macOS 14+ | Swift | MIT | 0 | 2026-09-28 | CoreBluetooth battery + ZMK Studio RPC over BLE GATT | 0x2901 present = right half | Stock battery; custom add-on for layers | Ad-hoc signed zip, not notarized |
| [maurzo/zmk-battery-util](https://github.com/maurzo/zmk-battery-util) | macOS | Swift, XcodeGen | MIT | 1 | 2025-08-10 | CoreBluetooth | Timestamp heuristic, no per-characteristic identity | Stock | DMG on Releases |
| [PapaniaP/bat-mon](https://github.com/PapaniaP/bat-mon) | macOS | Swift | MIT | 0 | 2026-10-14 | CoreBluetooth | Discovery index (0 = left, 1 = right) | Stock | Source |
| [AuntAnt/SplitBattery](https://github.com/AuntAnt/SplitBattery) | macOS | SwiftUI | None | 0 | 2026-01-18 | CoreBluetooth | Service order (first = left, last = right), asserts on 3+ | Stock | Source |
| [winiar93/zmk-battery](https://github.com/winiar93/zmk-battery) | Linux | Bash, `busctl`, systemd timer | MIT | 2 | 2026-11-05 | BlueZ D-Bus `ReadValue` | D-Bus object path order (attribute handle order) | Stock | Install script |
| [bjornborg/zmk-battery-report](https://github.com/bjornborg/zmk-battery-report) | Linux | Python `dbus_next` | None | 1 | 2025-03-10 | BlueZ D-Bus | 0x2901 present = its text, else "Central" | Stock | Single script |
| [bogamie/zmk-split-battery-tray](https://github.com/bogamie/zmk-split-battery-tray) | Linux (GNOME) | GNOME Shell JS + ZMK C module | MIT | 1 | 2026-04-26 | Vendor-defined USB HID report from the dongle | Fixed byte positions (byte 0 left, byte 1 right) | Custom firmware module on the dongle | Install script |
| [Cirius1792/zmk-battery-monitor](https://github.com/Cirius1792/zmk-battery-monitor) | Windows / cross-platform | Python `hidapi`, `pystray` | None | 0 | 2025-03-23 | Guesses HID feature reports | First two bytes in 0-100 | Assumes a battery HID report stock ZMK does not send | Source |
| [zmkfirmware/zmk-studio](https://github.com/zmkfirmware/zmk-studio) + [zmk-studio-ts-client](https://github.com/zmkfirmware/zmk-studio-ts-client) | Web, desktop (Tauri) | TypeScript, Rust `bluest` | Apache-2.0 / MIT | 326 / 8 | 2026-07-02 / 2026-01-23 | Studio RPC (protobuf) over serial or custom BLE GATT service | n/a (no battery RPC) | `CONFIG_ZMK_STUDIO` | Web app, desktop builds |

## Per-project implementation analysis

### kot149/zmk-battery-center (Tauri, cross-platform)

The most featureful tool: tray app with multi-keyboard support, history graphs, and low-battery notifications ([README L10-L24](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/README.md#L10-L24)).
The BLE layer is Rust using the `bluest` crate 0.6, which wraps CoreBluetooth on macOS, WinRT on Windows and BlueZ on Linux ([Cargo.toml L29](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/src-tauri/Cargo.toml#L29)).

How it gets the data:
- Device lookup only lists already-connected devices that expose the Battery Service, using `connected_devices_with_services` on macOS and Linux and a service probe with an 8 s timeout on Windows ([ble.rs L235-L276](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/src-tauri/src/ble.rs#L235-L276)).
- It walks every Battery Service instance and every Battery Level characteristic in it, rather than stopping at the first ([ble.rs L278-L341](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/src-tauri/src/ble.rs#L278-L341)).
- It has two modes: a notification worker per characteristic that subscribes with `characteristic.notify()` ([ble.rs L489-L523](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/src-tauri/src/ble.rs#L489-L523)), and a polling mode that connects, reads and disconnects ([ble.rs L948-L964](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/src-tauri/src/ble.rs#L948-L964)).

How it tells the halves apart:
- It reads the 0x2901 User Description of each Battery Level and uses that text as the label; a characteristic without one is labelled "Central" ([ble.rs L301-L336](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/src-tauri/src/ble.rs#L301-L336), [L349](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/src-tauri/src/ble.rs#L349)).
- Device-supplied text is sanitized because labels end up in CSV history files ([ble.rs L170-L176](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/src-tauri/src/ble.rs#L170-L176)).
- Users can rename "Peripheral 0" to "Right" ([issue #85](https://github.com/kot149/zmk-battery-center/issues/85), [issue #86](https://github.com/kot149/zmk-battery-center/issues/86)).

Firmware: stock ZMK with `CONFIG_BT_BAS`, `CONFIG_ZMK_BATTERY_REPORTING`, and the two split proxy options ([README L118-L131](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/README.md#L118-L131)).

Distribution: a Homebrew tap, but the app is not code-signed, so users must run `brew trust` or remove the quarantine attribute ([README L40-L56](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/README.md#L40-L56), [README L107-L116](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/README.md#L107-L116)).
The macOS bundle only adds `NSBluetoothAlwaysUsageDescription` ([Info.plist](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/src-tauri/Info.plist)) and enables Tauri's `macos-private-api` feature ([Cargo.toml L22](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/src-tauri/Cargo.toml#L22)).
Battery text directly in the menu bar is macOS-only and was inspired by ZMK Battery Bar ([README L17](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/README.md#L17), [issue #71](https://github.com/kot149/zmk-battery-center/issues/71)).

Known issues worth learning from:
- On Linux, polling reads through `bluest` made BlueZ drop the keyboard's connection, and calling `disconnect_device()` disconnects the device at OS level, so the app stopped disconnecting on Linux ([issue #57](https://github.com/kot149/zmk-battery-center/issues/57), [ble.rs L197-L213](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/src-tauri/src/ble.rs#L197-L213)).
- A dongle with two peripherals showed only the first peripheral until the code was fixed to iterate all characteristics ([issue #25](https://github.com/kot149/zmk-battery-center/issues/25)).
- A sleeping peripheral reads as 0% and triggered a false low-battery notification; the fix was an option to ignore 0% ([issue #86](https://github.com/kot149/zmk-battery-center/issues/86)).
- A dongle display module set `CONFIG_BT_BAS=n`, which hid the central's level; and enabling USB/BLE on the peripheral also broke reporting ([issue #3](https://github.com/kot149/zmk-battery-center/issues/3)).
- USB dongles cannot report battery over USB in stock ZMK; the workaround is pairing the dongle over Bluetooth as well ([issue #12](https://github.com/kot149/zmk-battery-center/issues/12)).
- Tray quirks: the first macOS arm64 build was "damaged" ([issue #17](https://github.com/kot149/zmk-battery-center/issues/17)), and on macOS 27 a left click on the tray icon arrived as a right click ([issue #90](https://github.com/kot149/zmk-battery-center/issues/90)).

### itouuuuuuuuu/zmk-battery-bar (native Swift, macOS)

The most polished native macOS implementation, and the closest to what halfsies wants for its first feature.
It is a SwiftPM executable targeting macOS 14 with Swift 6 language mode ([Package.swift](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Package.swift)), an `LSUIElement` agent app ([Info.plist L5](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Resources/Info.plist#L5)), and holds only the `com.apple.security.device.bluetooth` entitlement ([entitlements](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Resources/ZMKBatteryBar.entitlements)).

How it gets the data:
- Already-connected keyboards do not show up in a scan, so it first asks `retrieveConnectedPeripherals(withServices: [180F])` and then scans ([BLEManager.swift L79-L99](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L79-L99)).
- On launch it reconnects to the saved keyboard by identifier with `retrievePeripherals(withIdentifiers:)` and keeps an exponential backoff alive if CoreBluetooth temporarily loses the peripheral ([BLEManager.swift L139-L160](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L139-L160)).
- For every discovered Battery Service it discovers 0x2A19, enables notifications and discovers descriptors, and it defers the first read until the role is known so the index fallback cannot assign the wrong half ([BLEManager.swift L447-L485](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L447-L485)).
- A 60 s read timer is only a safety net for missed notifications and for stale detection ([BLEManager.swift L216-L245](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L216-L245), [ble-domain-knowledge.md L8-L13](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/.claude/rules/ble-domain-knowledge.md#L8-L13)).
- When Bluetooth turns off it clears state itself, because CoreBluetooth sends no per-peripheral disconnect in that case ([BLEManager.swift L351-L365](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L351-L365)).

How it tells the halves apart:
- It reads 0x2901 and maps any text containing "central" or "peripheral" to a role ([DescriptorRoleParser.swift L4-L14](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/DescriptorRoleParser.swift#L4-L14), [BLEManager.swift L515-L544](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L515-L544)).
- Because stock ZMK's central level has no 0x2901, it infers the one unresolved characteristic from its resolved sibling, and only falls back to array index when every descriptor read has terminally failed ([RoleAssigner.swift L8-L89](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/RoleAssigner.swift#L8-L89)).
- Support for 3+ part splits (left, right, numpad) was added by a contributor ([issue #48](https://github.com/itouuuuuuuuu/zmk-battery-bar/issues/48)).

Beyond battery, it can follow whichever keyboard you are typing on by watching IOHIDManager input values, which requires the Input Monitoring permission ([ActiveKeyboardMonitor.swift L30-L71](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/Utilities/ActiveKeyboardMonitor.swift#L30-L71)).

Distribution: a tag push builds, signs with a Developer ID certificate under hardened runtime, notarizes and staples, and updates a Homebrew cask in a separate tap ([README L94-L120](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/README.md#L94-L120), [release.yml L57](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/.github/workflows/release.yml#L57)).

The repo keeps a domain-knowledge file with findings that apply directly to us ([ble-domain-knowledge.md](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/.claude/rules/ble-domain-knowledge.md)):
- A read returns a cached value and never wakes the peripheral half, so a peripheral value can be arbitrarily stale ([L14-L26](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/.claude/rules/ble-domain-knowledge.md#L14-L26)).
- macOS caches the GATT database, so after a firmware change that alters the layout the user must remove and re-pair the keyboard ([L40-L46](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/.claude/rules/ble-domain-knowledge.md#L40-L46)).
- The app shares the connection macOS already holds for HID; each poll forces a slave-latency wakeup, a small but non-zero power cost ([L27-L33](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/.claude/rules/ble-domain-knowledge.md#L27-L33), [issue #72](https://github.com/itouuuuuuuuu/zmk-battery-bar/issues/72)).
- A `nice_nano` build on a `nice_nano_v2` board reports 0% permanently ([L47-L48](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/.claude/rules/ble-domain-knowledge.md#L47-L48)).

Limitation: it connects to one selected keyboard at a time ([BLEManager.swift L110-L137](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L110-L137)).

### codyd51/Mighty-Mitts (Objective-C, macOS)

A small menu bar applet that other projects link to as prior art ([zmk-battery-center README L156-L163](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/README.md#L156-L163)).
It lists connected peripherals that expose 0x180F via `retrieveConnectedPeripheralsWithServices:` and makes the user pick one by name ([AppDelegate.m L97-L124](https://github.com/codyd51/Mighty-Mitts/blob/75da8660599d/Mighty%20Mitts/AppDelegate.m#L97-L124)).
A 60 s `NSTimer` re-reads; it never subscribes to notifications ([AppDelegate.m L14-L16](https://github.com/codyd51/Mighty-Mitts/blob/75da8660599d/Mighty%20Mitts/AppDelegate.m#L14-L16), [L155-L171](https://github.com/codyd51/Mighty-Mitts/blob/75da8660599d/Mighty%20Mitts/AppDelegate.m#L155-L171), [L199-L207](https://github.com/codyd51/Mighty-Mitts/blob/75da8660599d/Mighty%20Mitts/AppDelegate.m#L199-L207)).
Halves are assigned by a flip-flop: each `didUpdateValueForCharacteristic` callback alternates between "left" and "right" ([AppDelegate.m L209-L231](https://github.com/codyd51/Mighty-Mitts/blob/75da8660599d/Mighty%20Mitts/AppDelegate.m#L209-L231)).
That is fragile: one missed or extra callback swaps the halves, and a ZMK fork later swapped its proxy layout so Mighty Mitts would show the levels in the right places ([zmk-next-battery BatteryRoles.swift L3-L7](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/Sources/BatteryRoles.swift#L3-L7)).
The project ships a prebuilt zip and has no LICENSE file even though the README says MIT ([README](https://github.com/codyd51/Mighty-Mitts/blob/75da8660599d/README.md)); an open issue reports a missing Info.plist in the project ([issue #2](https://github.com/codyd51/Mighty-Mitts/issues/2)).

### Maksim-Isakau/zmk-split-battery (C#, Windows)

The first host tool for the split proxy, written against Katona's original PR ([ZMK PR #1243 comment](https://github.com/zmkfirmware/zmk/pull/1243#issuecomment-1312848161)).
It enumerates paired BLE devices with a `DeviceWatcher` and an AQS filter on the Bluetooth LE protocol ID ([BatteryMonitor.cs L94-L121](https://github.com/Maksim-Isakau/zmk-split-battery/blob/13eed4236fa2/BatteryMonitor.cs#L94-L121)).
It opens the device with `BluetoothLEDevice.FromIdAsync`, gets all Battery Services with `BluetoothCacheMode.Uncached`, and collects every Battery Level characteristic keyed by its attribute handle ([BatteryMonitor.cs L123-L171](https://github.com/Maksim-Isakau/zmk-split-battery/blob/13eed4236fa2/BatteryMonitor.cs#L123-L171)).
WinRT exposes the 0x2901 text directly as `GattCharacteristic.UserDescription`, and a characteristic without one is labelled "Main" ([BatteryMonitor.cs L201-L211](https://github.com/Maksim-Isakau/zmk-split-battery/blob/13eed4236fa2/BatteryMonitor.cs#L201-L211)).
A value of 255 is treated as unknown ([BatteryMonitor.cs L231](https://github.com/Maksim-Isakau/zmk-split-battery/blob/13eed4236fa2/BatteryMonitor.cs#L231)).
It attaches `ValueChanged` handlers but we found no explicit CCCD write and no periodic re-read; values are read once at connect ([BatteryMonitor.cs L150](https://github.com/Maksim-Isakau/zmk-split-battery/blob/13eed4236fa2/BatteryMonitor.cs#L150), [L159](https://github.com/Maksim-Isakau/zmk-split-battery/blob/13eed4236fa2/BatteryMonitor.cs#L159)).
The author confirms it does not track connect and disconnect, so values go stale after charging until the user reconnects ([issue #4](https://github.com/Maksim-Isakau/zmk-split-battery/issues/4)).
Reconnect is a fixed 300 s countdown ([MainForm.cs L42](https://github.com/Maksim-Isakau/zmk-split-battery/blob/13eed4236fa2/MainForm.cs#L42), [L387-L410](https://github.com/Maksim-Isakau/zmk-split-battery/blob/13eed4236fa2/MainForm.cs#L387-L410)).

### rleyvasal/zmk-next-battery (Swift, macOS, Bluetooth and USB)

Notable for being the only macOS tool that also reads battery over USB.
Over Bluetooth it uses CoreBluetooth notifications plus a 5 minute re-read, and filters candidates to devices that also expose HID 0x1812, falling back to all battery devices "if macOS hides HID from this query" ([BluetoothSource.swift L1-L23](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/Sources/BluetoothSource.swift#L1-L23), [L75-L109](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/Sources/BluetoothSource.swift#L75-L109)).
It cancels and retries a connect that is still pending after 20 s, because a connect started while the link could not encrypt can stay pending forever ([BluetoothSource.swift L87-L99](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/Sources/BluetoothSource.swift#L87-L99)).
Halves are named from 0x2901 text ("left"/"central" vs "right"/"peripheral"), and an undescribed level is the opposite of its described sibling, which handles both upstream ZMK and a fork that swaps the layout ([BatteryRoles.swift L1-L27](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/Sources/BatteryRoles.swift#L1-L27)).
It also parses Battery Level Status (0x2BED) for charging state ([BatteryRoles.swift L29-L43](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/Sources/BatteryRoles.swift#L29-L43)).
Over USB it opens the ZMK Studio CDC serial port (VID 0x1D50, PID 0x615E) for about a second every 10 s, sends a custom `G1` request and parses a custom `K` text frame, skipping the port if another app holds it ([USBSource.swift L1-L18](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/Sources/USBSource.swift#L1-L18), [Frames.swift L1-L26](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/Sources/Frames.swift#L1-L26)).
That USB path is not ZMK Studio RPC; it needs the author's "ZMK Next" fork and a `zmk-studio-log` module ([README L7-L13](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/README.md#L7-L13)).
It is ad-hoc signed and not notarized ([README L36-L37](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/README.md#L36-L37)).

### Smaller macOS tools

- [Katona/zmk-ble](https://github.com/Katona/zmk-ble) is the proof of concept from the author of the original ZMK PR ([PR #1243 comment](https://github.com/zmkfirmware/zmk/pull/1243#issuecomment-1165689937)).
It matches the exact 0x2901 strings "Central" and "Peripheral" that the unmerged PR used ([ZmkPeripheral.swift L68-L92](https://github.com/Katona/zmk-ble/blob/ae968ae02b16/zmk-ble/ZmkPeripheral.swift#L68-L92)), so it does not work with the merged implementation, which labels only the peripheral as "Peripheral N" ([central_bas_proxy.c L53-L65](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb/app/src/split/bluetooth/central_bas_proxy.c#L53-L65)).
This is the clearest example of a host tool coupled to firmware strings.
- [ngbucsit/sketchybar-zmk-battery](https://github.com/ngbucsit/sketchybar-zmk-battery) is the only tool we found that also reads the 0x2904 Presentation Format descriptor: "Peripheral N" text gives the index, 0x2904 description 0x0108 "auxiliary" marks a peripheral without text, and anything else is central ([BatteryPart.swift L22-L61](https://github.com/ngbucsit/sketchybar-zmk-battery/blob/7e85f980af7e/Sources/ZMKBatteryCore/BatteryPart.swift#L22-L61), [BatteryMonitor.swift L375-L389](https://github.com/ngbucsit/sketchybar-zmk-battery/blob/7e85f980af7e/Sources/sketchybar-zmk-battery/BatteryMonitor.swift#L375-L389)).
- [meta-boy/cornix-hud](https://github.com/meta-boy/cornix-hud) treats a level with a 0x2901 descriptor as the right half ([KeyboardBLE.swift L131](https://github.com/meta-boy/cornix-hud/blob/7fffaac37d3c/app/Sources/CornixHUD/KeyboardBLE.swift#L131)) and also talks ZMK Studio RPC over the Studio BLE GATT service from Swift, with its own framing implementation ([StudioRPC.swift L6-L20](https://github.com/meta-boy/cornix-hud/blob/7fffaac37d3c/app/Sources/CornixHUD/StudioRPC.swift#L6-L20)).
It is the only native macOS example we found of Studio RPC over CoreBluetooth.
- [maurzo/zmk-battery-util](https://github.com/maurzo/zmk-battery-util) reads and subscribes to every 0x2A19 ([ZMKBatteryUtil.swift L82-L91](https://github.com/maurzo/zmk-battery-util/blob/c7944fd9dfc8/Sources/ZMKBatteryUtil/ZMKBatteryUtil.swift#L82-L91)) but stores readings per peripheral, not per characteristic, and decides which slot to overwrite by a 150 ms timestamp window ([L108-L129](https://github.com/maurzo/zmk-battery-util/blob/c7944fd9dfc8/Sources/ZMKBatteryUtil/ZMKBatteryUtil.swift#L108-L129)), so it cannot say which half is which.
- [PapaniaP/bat-mon](https://github.com/PapaniaP/bat-mon) maps discovery index 0 to left and 1 to right ([BluetoothManager.swift L566-L567](https://github.com/PapaniaP/bat-mon/blob/f2d7b45ce5a7/BatMon/Managers/BluetoothManager.swift#L566-L567)).
- [AuntAnt/SplitBattery](https://github.com/AuntAnt/SplitBattery) maps the first service to left and the last to right, and hits `assertionFailure` for anything other than one or two services ([DevicesViewModel.swift L119-L129](https://github.com/AuntAnt/SplitBattery/blob/b4070db3a6f6/SplitBattery/DevicesViewModel.swift#L119-L129)).

### lihaoyun6/AirBattery (general BLE battery app, macOS)

The most popular general-purpose battery app on macOS, and a good example of what a generic tool does with a split keyboard.
It runs an unfiltered `scanForPeripherals(withServices: nil)` on a timer ([BLEBattery.swift L129-L136](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f/AirBattery/BatteryInfo/BLEBattery.swift#L129-L136)) and reads 0x2A19 from any 0x180F service ([L197-L201](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f/AirBattery/BatteryInfo/BLEBattery.swift#L197-L201)).
Each value is stored under the peripheral's name, so with two Battery Level characteristics the last callback wins ([BLEBattery.swift L216-L235](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f/AirBattery/BatteryInfo/BLEBattery.swift#L216-L235)).
It guesses "charging" when a level goes up ([L224](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f/AirBattery/BatteryInfo/BLEBattery.swift#L224)).
For Apple and system-known devices it parses `system_profiler SPBluetoothDataType -json` ([MagicBattery.swift L16](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f/AirBattery/BatteryInfo/MagicBattery.swift#L16)) and reads `BatteryPercent` from IORegistry classes such as `AppleDeviceManagementHIDEventService` ([MagicBattery.swift L130-L170](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f/AirBattery/BatteryInfo/MagicBattery.swift#L130-L170)).
The `system_profiler` keys it uses include `device_batteryLevelMain`, `device_batteryLevelLeft`, `device_batteryLevelRight` and `device_batteryLevelCase` ([MagicBattery.swift L246-L318](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f/AirBattery/BatteryInfo/MagicBattery.swift#L246-L318)), which shows macOS has left and right slots per device, as used for AirPods.
Conclusion: AirBattery does not handle multiple Battery Service instances on one device, and its AGPL-3.0 license would rule out reuse anyway.

### Linux tools

- **BlueZ itself handles only one Battery Service per device.**
Its battery profile logs "More than one BATT service exists for this device" and ignores the rest ([profiles/battery/battery.c L268-L279](https://github.com/bluez/bluez/blob/aa4f5ce97c87/profiles/battery/battery.c#L268-L279)), so `org.bluez.Battery1`, and UPower above it, see only the central.
Every BLE-based Linux tool below therefore reads `org.bluez.GattCharacteristic1` directly over D-Bus.
- [mh4x0f/zmkBATx](https://github.com/mh4x0f/zmkBATx) (Qt6, SimpleBluez) reads each Battery Level and labels it Peripheral if a 0x2901 descriptor exists, otherwise Central ([bleinterfacebluez.cpp L86-L106](https://github.com/mh4x0f/zmkBATx/blob/ee8446b7549a/src/bleinterfacebluez.cpp#L86-L106)).
With one slot per role, a dongle with two peripherals showed only one of them ([issue #4](https://github.com/mh4x0f/zmkBATx/issues/4)).
- [JanValiska/ZmkBatteryClient](https://github.com/JanValiska/ZmkBatteryClient) (Rust `bluer`) uses the same rule and emits Waybar JSON ([main.rs L65-L90](https://github.com/JanValiska/ZmkBatteryClient/blob/e74fd3cfdf34/src/main.rs#L65-L90)).
- [bjornborg/zmk-battery-report](https://github.com/bjornborg/zmk-battery-report) does the same in Python with `dbus_next` ([zmk-battery-status.py L36-L56](https://github.com/bjornborg/zmk-battery-report/blob/c1119d5edea0/zmk-battery-status.py#L36-L56)).
- [winiar93/zmk-battery](https://github.com/winiar93/zmk-battery) sorts characteristic object paths (which follow attribute handles) and labels them by position ([zmk-battery.sh L115-L125](https://github.com/winiar93/zmk-battery/blob/b8556bcd3b76/zmk-battery.sh#L115-L125), [L277](https://github.com/winiar93/zmk-battery/blob/b8556bcd3b76/zmk-battery.sh#L277)).
It works because ZMK registers the main BAS before the proxy, but that is an implementation detail.
- A ZMK user posted the same idea as a one-off `gdbus` script with hard-coded handle paths ([PR #1243 comment](https://github.com/zmkfirmware/zmk/pull/1243#issuecomment-2628938021)).
- [bogamie/zmk-split-battery-tray](https://github.com/bogamie/zmk-split-battery-tray) solves the dongle case with a firmware module that adds a vendor-defined (usage page 0xFF00) USB HID interface carrying left and right levels as two bytes ([battery_hid.c L10-L39](https://github.com/bogamie/zmk-split-battery-tray/blob/a75d51db16db/firmware/battery_hid.c#L10-L39)), read by a GNOME Shell extension ([README](https://github.com/bogamie/zmk-split-battery-tray/blob/a75d51db16db/README.md)).

### Python and HID guessing

We found no maintained bleak-based ZMK battery tool on GitHub; one user mentions using Bleak ad hoc to read both peripherals ([zmk-battery-center issue #25](https://github.com/kot149/zmk-battery-center/issues/25)).
[Cirius1792/zmk-battery-monitor](https://github.com/Cirius1792/zmk-battery-monitor) uses `hidapi` instead and scans HID feature report IDs 1-8, treating the first two bytes between 0 and 100 as left and right ([main.py L466-L522](https://github.com/Cirius1792/zmk-battery-monitor/blob/6fb2eebbb8cb/main.py#L466-L522)).
Stock ZMK sends no such report, so this is a guess that can return plausible-looking garbage; it is a pattern to avoid.

### ZMK Studio and RPC clients

- The official Studio protocol has no battery messages.
The subsystems are `core` (device info, lock state, reset), `behaviors` and `keymap` ([studio.proto L11-L43](https://github.com/zmkfirmware/zmk-studio-messages/blob/6cb4c283e762/proto/zmk/studio.proto#L11-L43), [core.proto L10-L36](https://github.com/zmkfirmware/zmk-studio-messages/blob/6cb4c283e762/proto/zmk/core.proto#L10-L36)).
- Transports are USB CDC serial and a custom BLE GATT service `00000000-0196-6107-c967-c5cfb1c2482a` with one RPC characteristic `00000001-...` ([gatt.ts L4-L10](https://github.com/zmkfirmware/zmk-studio-ts-client/blob/87ccd3a36280/src/transport/gatt.ts#L4-L10)).
Messages are protobuf wrapped in SOF 0xAB / ESC 0xAC / EOF 0xAD framing ([framing.ts L1-L3](https://github.com/zmkfirmware/zmk-studio-ts-client/blob/87ccd3a36280/src/framing.ts#L1-L3)).
- The Studio desktop app is Tauri and uses the same `bluest` crate as zmk-battery-center for its BLE transport ([Cargo.toml L21](https://github.com/zmkfirmware/zmk-studio/blob/1bb6bb84a370/src-tauri/Cargo.toml#L21), [gatt.rs L9-L14](https://github.com/zmkfirmware/zmk-studio/blob/1bb6bb84a370/src-tauri/src/transport/gatt.rs#L9-L14)).
- Third-party Studio clients exist in Swift: cornix-hud over BLE GATT (above), and [Intersebbtor/ZMK-keymap-viewer](https://github.com/Intersebbtor/ZMK-keymap-viewer), which tunnels Studio RPC over Raw HID reports using the third-party `zmk-raw-hid` module and listens on usage page 0xFF60 via IOHIDManager ([StudioClient.swift L13-L36](https://github.com/Intersebbtor/ZMK-keymap-viewer/blob/de5546aca104/StudioClient.swift#L13-L36), [LiveLayerMonitor.swift L11-L42](https://github.com/Intersebbtor/ZMK-keymap-viewer/blob/de5546aca104/LiveLayerMonitor.swift#L11-L42), [README L76-L78](https://github.com/Intersebbtor/ZMK-keymap-viewer/blob/de5546aca104/README.md#L76-L78)).
- Studio keeps the keymap locked until the user presses `&studio_unlock`, which every client has to design around ([ZMK-keymap-viewer README L159-L161](https://github.com/Intersebbtor/ZMK-keymap-viewer/blob/de5546aca104/README.md#L159-L161)).
- Custom Studio RPC subsystems are possible from a firmware module, as [cormoran/zmk-module-settings-rpc](https://github.com/cormoran/zmk-module-settings-rpc) shows, but that again needs firmware changes.

### ZMK community work and what macOS shows

- The proxy came from Katona's PR #1243 (closed) and was merged as PR #2045 on 2024-01-03 ([PR #1243](https://github.com/zmkfirmware/zmk/pull/1243), [PR #2045](https://github.com/zmkfirmware/zmk/pull/2045)).
Katona noted that macOS Monterey shows only the central battery and suggested host utilities for the rest ([PR #1243 description](https://github.com/zmkfirmware/zmk/pull/1243), [comment](https://github.com/zmkfirmware/zmk/pull/1243#issuecomment-1100389963)).
- ZMK's own docs say host support for multiple battery levels is undefined, that usually only the main battery is shown, and that "you probably need a special application or script" ([ZMK battery config](https://zmk.dev/docs/config/battery)).
- Issue #2892 asks for USB battery reporting, the lowest level as the main value, and configurable descriptions, and points out that every proxied service uses the same 0x0108 "auxiliary" description, so with 3+ parts only the 0x2901 text tells them apart ([issue #2892](https://github.com/zmkfirmware/zmk/issues/2892)).
- PR #2938 implements HID battery reporting over USB and configurable Presentation Format descriptions ([PR #2938](https://github.com/zmkfirmware/zmk/pull/2938)), and PR #3458 continues it with per-part HID batteries and charge status; both are open ([PR #3458](https://github.com/zmkfirmware/zmk/pull/3458)).
- Testing PR #3458 on macOS 26.6.2, a contributor found that Presentation Format descriptions 269 (left) and 270 (right) make macOS show `L 98% R 100%` in the Bluetooth menu, like AirPods ([comment](https://github.com/zmkfirmware/zmk/pull/3458#issuecomment-6209774162)).
The same tester found the USB HID battery report appears as a UPS in System Settings > Energy ([comment](https://github.com/zmkfirmware/zmk/pull/3458#issuecomment-6247742915)).
- On Linux, multi-battery HID devices are supported from kernel 7.1, and UPower needed a merge request to stop hiding all but one battery ([PR #3458 description](https://github.com/zmkfirmware/zmk/pull/3458)).
- An open bug reports an out-of-bounds write to the peripheral battery array on a non-peripheral disconnect, with a fix in review ([issue #3522](https://github.com/zmkfirmware/zmk/issues/3522), [PR #3556](https://github.com/zmkfirmware/zmk/pull/3556)).
- The same macOS question keeps coming back in community channels, for example a ZMK Discord thread titled "how to know the battery status of right half on MacOS?" ([Answer Overflow mirror](https://www.answeroverflow.com/m/1385618216977567842)).

## Lessons for halfsies

### Approaches that work

- **Public CoreBluetooth is enough for battery on macOS.**
Every working macOS tool retrieves the peripheral macOS already has connected (`retrieveConnectedPeripherals(withServices: [180F])`, or `retrievePeripherals(withIdentifiers:)` for a saved one), calls `connect` to get an app-level handle, and discovers all 0x180F services ([zmk-battery-bar BLEManager.swift L79-L160](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L79-L160), [Mighty Mitts AppDelegate.m L89-L93](https://github.com/codyd51/Mighty-Mitts/blob/75da8660599d/Mighty%20Mitts/AppDelegate.m#L89-L93)).
- **Iterate every Battery Service and every Battery Level characteristic.**
Stopping at the first service, or keeping one slot per role, silently drops the second peripheral on dongle setups ([zmk-battery-center issue #25](https://github.com/kot149/zmk-battery-center/issues/25), [zmkBATx issue #4](https://github.com/mh4x0f/zmkBATx/issues/4), [Katona ZmkPeripheral.swift L53](https://github.com/Katona/zmk-ble/blob/ae968ae02b16/zmk-ble/ZmkPeripheral.swift#L53)).
- **Identify halves from descriptors, not order.**
Read 0x2901 and 0x2904 for each level: "Peripheral N" or description 0x0108 means a proxied peripheral, and no 0x2901 with 0x0106 means the central ([central_bas_proxy.c L45-L65](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb/app/src/split/bluetooth/central_bas_proxy.c#L45-L65), [sketchybar-zmk-battery BatteryPart.swift L49-L61](https://github.com/ngbucsit/sketchybar-zmk-battery/blob/7e85f980af7e/Sources/ZMKBatteryCore/BatteryPart.swift#L49-L61)).
Defer showing values until roles are known, as zmk-battery-bar does ([BLEManager.swift L465-L469](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L465-L469)).
Also accept 0x2904 left (0x010D) and right (0x010E), since that is where upstream firmware is heading ([ZMK PR #3458 comment](https://github.com/zmkfirmware/zmk/pull/3458#issuecomment-6209774162)).
- **Map "central/peripheral" to "left/right" as a user setting.**
ZMK does not know which physical side is central, and both mature apps let users relabel ([zmk-battery-bar README L49-L57](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/README.md#L49-L57), [zmk-battery-center issue #85](https://github.com/kot149/zmk-battery-center/issues/85)).
- **Subscribe to notifications; keep a slow read only as a safety net.**
Reads return cached values and cost the keyboard a latency wakeup, so polling adds power cost without fresher data ([zmk-battery-bar ble-domain-knowledge.md L8-L33](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/.claude/rules/ble-domain-knowledge.md#L8-L33)).
- **Treat disconnects and Bluetooth power changes explicitly**, with backoff reconnects, and clear state on power-off because CoreBluetooth sends no per-peripheral callback then ([BLEManager.swift L300-L365](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L300-L365)).
- **Sign, notarize and ship a Homebrew cask.**
The one notarized app avoids the Gatekeeper workarounds that every unsigned tool has to document ([zmk-battery-bar README L94-L120](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/README.md#L94-L120), [zmk-battery-center README L107-L116](https://github.com/kot149/zmk-battery-center/blob/96912ef1e0da/README.md#L107-L116)).

### Pitfalls they hit

- Order-based identification (discovery index, callback alternation, service order, D-Bus path order) works until it does not, and swaps halves without any error ([Mighty Mitts AppDelegate.m L209-L231](https://github.com/codyd51/Mighty-Mitts/blob/75da8660599d/Mighty%20Mitts/AppDelegate.m#L209-L231), [bat-mon L566-L567](https://github.com/PapaniaP/bat-mon/blob/f2d7b45ce5a7/BatMon/Managers/BluetoothManager.swift#L566-L567)).
- Matching exact descriptor strings couples the app to one firmware revision ([Katona ZmkPeripheral.swift L85-L89](https://github.com/Katona/zmk-ble/blob/ae968ae02b16/zmk-ble/ZmkPeripheral.swift#L85-L89)).
- Keying values by device name or peripheral loses the second level ([AirBattery BLEBattery.swift L227-L228](https://github.com/lihaoyun6/AirBattery/blob/134e02f2861f/AirBattery/BatteryInfo/BLEBattery.swift#L227-L228), [maurzo L108-L129](https://github.com/maurzo/zmk-battery-util/blob/c7944fd9dfc8/Sources/ZMKBatteryUtil/ZMKBatteryUtil.swift#L108-L129)).
- A peripheral that is asleep or disconnected from the central reads as 0%, which triggers false low-battery alerts ([zmk-battery-center issue #86](https://github.com/kot149/zmk-battery-center/issues/86), [ZMK PR #2938 thread](https://github.com/zmkfirmware/zmk/pull/2938)).
- macOS caches the GATT database, so firmware changes to battery config need an unpair and re-pair before the app sees them ([ble-domain-knowledge.md L43-L46](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/.claude/rules/ble-domain-knowledge.md#L43-L46)).
- Firmware misconfiguration looks like an app bug: `CONFIG_BT_BAS=n` from a display module hides the central level, and wrong board targets read 0% ([zmk-battery-center issue #3](https://github.com/kot149/zmk-battery-center/issues/3), [ble-domain-knowledge.md L47-L48](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/.claude/rules/ble-domain-knowledge.md#L47-L48)).
In-app diagnostics that list what the device actually exposes would save support time.
- Values that never refresh after charging, because the app does not watch connection events ([zmk-split-battery issue #4](https://github.com/Maksim-Isakau/zmk-split-battery/issues/4)).
- Unsigned builds: "damaged app" reports and `xattr` instructions ([zmk-battery-center issue #17](https://github.com/kot149/zmk-battery-center/issues/17)).
- Cross-platform tray toolkits bring their own macOS quirks, such as left clicks arriving as right clicks on macOS 27 ([zmk-battery-center issue #90](https://github.com/kot149/zmk-battery-center/issues/90)).

### Gaps none of them fill

- **USB dongles on macOS with stock firmware.**
Over USB, stock ZMK exposes no battery data, so tools either need a forked firmware ([zmk-next-battery](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/README.md#L7-L13), [zmk-split-battery-tray](https://github.com/bogamie/zmk-split-battery-tray/blob/a75d51db16db/README.md)) or ask users to also pair the dongle over Bluetooth ([zmk-battery-center issue #12](https://github.com/kot149/zmk-battery-center/issues/12)).
If PR #3458 lands, macOS will need care because its USB HID battery currently shows as a UPS ([comment](https://github.com/zmkfirmware/zmk/pull/3458#issuecomment-6247742915)).
- **A foundation for more than battery.**
The battery apps are single-purpose, and the Studio-aware tools are single-keyboard or need custom modules ([cornix-hud README](https://github.com/meta-boy/cornix-hud/blob/7fffaac37d3c/README.md), [ZMK-keymap-viewer README L76-L78](https://github.com/Intersebbtor/ZMK-keymap-viewer/blob/de5546aca104/README.md#L76-L78)).
No native macOS app combines battery over standard BAS with a general ZMK Studio RPC client.
- **Honest freshness and status.**
Only zmk-next-battery shows reading age and source ([README L14-L17](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/README.md#L14-L17)); none distinguishes "peripheral not connected to central" from a real 0%.
- **Multiple keyboards at once on macOS natively.**
zmk-battery-bar follows one selected keyboard ([BLEManager.swift L110-L137](https://github.com/itouuuuuuuuu/zmk-battery-bar/blob/3ae5b1e934d5/Sources/ZMKBatteryBar/BLE/BLEManager.swift#L110-L137)); only the Tauri app watches several.
- **3+ part splits identified by position, not index.**
Stock firmware only says "Peripheral 0/1", so mapping those to "right half" or "numpad" needs a user setting until per-part descriptions are configurable ([issue #2892](https://github.com/zmkfirmware/zmk/issues/2892)).
- **Charging state.**
Only zmk-next-battery reads Battery Level Status (0x2BED), and it needs a fork ([BatteryRoles.swift L29-L43](https://github.com/rleyvasal/zmk-next-battery/blob/dc9518c7436a/Sources/BatteryRoles.swift#L29-L43)); upstream support is in the open PR #3458 ([PR #3458](https://github.com/zmkfirmware/zmk/pull/3458)).
