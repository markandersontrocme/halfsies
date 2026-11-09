# Layer display: how a macOS app can learn the active ZMK layer

Research date: 2026-11-09.
ZMK sources are pinned to `main` at commit [`4dd95d78`](https://github.com/zmkfirmware/zmk/commit/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85) (2026-10-09), the same pin as [01-zmk-and-macos-ble.md](01-zmk-and-macos-ble.md).
Studio messages are pinned to [`zmk-studio-messages@6cb4c283`](https://github.com/zmkfirmware/zmk-studio-messages/tree/6cb4c283e76209d59c45fbcb218800cd19e9339d/proto/zmk), which is still the head of `main`.
Apple HID internals are from the open-source [`IOHIDFamily-2238.120.5`](https://github.com/apple-oss-distributions/IOHIDFamily/tree/e31e90a24c27ad6cbe981650d12a1a4124065b03) tag and the local macOS SDK in Xcode 27.2.
Community repos are pinned to their head commit on the research date.
Nothing here was tested on hardware; the last section lists what a spike must confirm.

## TL;DR

- Stock ZMK does not tell the host which layer is active, over any transport.
  A ZMK maintainer says so directly: "Layers aren't reported to the computer" ([zmk#2772 comment](https://github.com/zmkfirmware/zmk/issues/2772#issuecomment-2596369756)).
  Every working option needs a firmware change on the central (or dongle) and a reflash.
- ZMK Studio RPC has no active-layer request or notification, so the unlock question is moot today.
  The only notifications are lock-state changes and "unsaved changes" ([`studio.proto` L38-L43](https://github.com/zmkfirmware/zmk-studio-messages/blob/6cb4c283e76209d59c45fbcb218800cd19e9339d/proto/zmk/studio.proto#L38-L43); [`core.proto` L32-L36](https://github.com/zmkfirmware/zmk-studio-messages/blob/6cb4c283e76209d59c45fbcb218800cd19e9339d/proto/zmk/core.proto#L32-L36); [`keymap.proto` L39-L43](https://github.com/zmkfirmware/zmk-studio-messages/blob/6cb4c283e76209d59c45fbcb218800cd19e9339d/proto/zmk/keymap.proto#L39-L43)), and the firmware's keymap event mapper is an empty stub ([`keymap_subsystem.c` L540-L542](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/keymap_subsystem.c#L540-L542)).
- The firmware already raises a `zmk_layer_state_changed` event with layer id, on/off and a lock flag on every real change ([`layer_state_changed.h` L12-L17](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/include/zmk/events/layer_state_changed.h#L12-L17); [`keymap.c` L150-L164](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/keymap.c#L150-L164)).
  Every community solution is a small module that subscribes to that event and pushes the state out on some channel.
- Two channel designs are proven on macOS:
  1. **A vendor-page raw HID interface** (usage page 0xFF60) added by [zzeneg/zmk-raw-hid](https://github.com/zzeneg/zmk-raw-hid), read with `IOHIDManager`.
     One host code path covers BLE, USB and a USB dongle.
     Per Apple's IOHIDFamily source it needs no Input Monitoring permission, as long as macOS presents it as its own HID device and not as part of the keyboard.
  2. **A custom GATT service over BLE plus a CDC-ACM serial port over USB**, as in [rafaelromao/zmk-layer-hud](https://github.com/rafaelromao/zmk-layer-hud).
     It needs only the Bluetooth permission Halfsies already asks for, but it is two host code paths.
- Avoid any design that puts the layer report inside the keyboard's own HID device (for example the [pfilipp/zmk](https://github.com/pfilipp/zmk/blob/4994db488fb79707de693967def2f282651d5fb7/docs/docs/features/layer-state-report.md) fork or open ZMK PR [#3390](https://github.com/zmkfirmware/zmk/pull/3390)).
  macOS marks any HID device that contains a keyboard collection as needing Input Monitoring ([`IOHIDDevice.cpp` L527-L531](https://github.com/apple-oss-distributions/IOHIDFamily/blob/e31e90a24c27ad6cbe981650d12a1a4124065b03/IOHIDFamily/IOHIDDevice.cpp#L527-L531)).
- Keycode side channels (macros or listeners that tap F13-F20 on layer change) work without a custom module, but they leak keys into the focused app, need Accessibility or Input Monitoring, and go blind while Secure Event Input is on.
- **Recommendation:** raw HID via `zmk-raw-hid`, with a tiny Halfsies-owned publisher module (layer bitmap only), read with a non-seizing `IOHIDManager`.
  If the hardware spike shows that macOS folds the BLE raw HID service into the keyboard device (and so asks for Input Monitoring), switch to the custom GATT plus CDC-ACM design instead.

## Options

Latency figures are reasoned from connection parameters, not measured.
ZMK asks for a 7.5 to 15 ms BLE connection interval ([`app/Kconfig` L236-L246](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/Kconfig#L236-L246)), and a layer change follows a key press, so the link is already active.

| # | Mechanism | Firmware change needed | macOS permission | Latency | Maturity |
| --- | --- | --- | --- | --- | --- |
| A | Vendor raw HID interface (0xFF60) via `zmk-raw-hid` + layer publisher, read with `IOHIDManager` | Two modules on the central or dongle, `raw_hid_adapter` shield, re-pair BLE | None expected (vendor-only HID device); BLE case to verify | About one BLE connection event or USB poll | Module since 2024-12; used by KeyPeek (210 stars), cornix-hud, ZMK-keymap-viewer |
| B | Custom GATT service (BLE) + CDC-ACM serial (USB), read with CoreBluetooth and a serial port | One module plus a snippet for USB, re-pair BLE likely | Bluetooth (already needed); none for serial | Same as A | Young: zmk-layer-hud (2026-09, 5 stars), taichi-dm proof of concept |
| C | Vendor report inside the keyboard's main HID descriptor | ZMK fork (pfilipp) or unmerged PR #3390 | Input Monitoring | Same as A | Fork-only |
| D | ZMK Studio RPC | Studio enabled plus a custom RPC subsystem from a ZMK fork, or a new upstream message | Bluetooth for BLE; none for serial | Same as A, but Studio lowers peripheral latency while subscribed | Not possible upstream today |
| E | Keycode side channel (F13-F20 tapped by macros or `zmk-listeners`) | Keymap edits, optionally the `zmk-listeners` module | Accessibility (`NSEvent` global monitor) or Input Monitoring (event tap or `IOHIDManager`) | Key event path plus macro tap time | Folk technique, recommended in passing by a maintainer |
| F | HID LED indicators, typed layer names, inferring from key reports | Not viable | - | - | - |

## A. Vendor raw HID interface

### Firmware side

[zzeneg/zmk-raw-hid](https://github.com/zzeneg/zmk-raw-hid) (MIT, created 2024-12-23, last commit [`6a37765d`](https://github.com/zzeneg/zmk-raw-hid/commit/6a37765dfab6197292e7a9f47305dcf87386d56a) on 2026-08-24) adds bidirectional raw HID over USB and BLE ([README L7](https://github.com/zzeneg/zmk-raw-hid/blob/6a37765dfab6197292e7a9f47305dcf87386d56a/README.md#L7)).
It does nothing on its own; another module must raise `raw_hid_sent_event` ([README L13-L14](https://github.com/zzeneg/zmk-raw-hid/blob/6a37765dfab6197292e7a9f47305dcf87386d56a/README.md#L13-L14)).
It is enabled by adding the `raw_hid_adapter` shield to the build ([README L39-L46](https://github.com/zzeneg/zmk-raw-hid/blob/6a37765dfab6197292e7a9f47305dcf87386d56a/README.md#L39-L46)).
`CONFIG_RAW_HID` depends on `!ZMK_SPLIT || ZMK_SPLIT_ROLE_CENTRAL`, so it builds only on the central or dongle ([`Kconfig` L1-L4](https://github.com/zzeneg/zmk-raw-hid/blob/6a37765dfab6197292e7a9f47305dcf87386d56a/Kconfig#L1-L4)).
Defaults are usage page 0xFF60, usage 0x61 and 32-byte reports, the same values QMK and VIA use ([`Kconfig` L6-L16](https://github.com/zzeneg/zmk-raw-hid/blob/6a37765dfab6197292e7a9f47305dcf87386d56a/Kconfig#L6-L16)).
The report descriptor is a single vendor application collection with one input and one output report and no report ID ([`raw_hid.h` L12-L31](https://github.com/zzeneg/zmk-raw-hid/blob/6a37765dfab6197292e7a9f47305dcf87386d56a/include/raw_hid/raw_hid.h#L12-L31)).

Transport details:

- **USB:** it registers a second Zephyr USB HID device (`HID_1`), so the keyboard enumerates with a separate HID interface for raw HID ([`usb_hid.c` L84-L93](https://github.com/zzeneg/zmk-raw-hid/blob/6a37765dfab6197292e7a9f47305dcf87386d56a/src/usb_hid.c#L84-L93)).
- **BLE:** it defines a second HID Service (0x1812) instance with its own report map, an encrypted notify input report and a write output report ([`hog.c` L97-L123](https://github.com/zzeneg/zmk-raw-hid/blob/6a37765dfab6197292e7a9f47305dcf87386d56a/src/hog.c#L97-L123)).
  It sends to the active BLE profile's connection only ([`hog.c` L125-L151](https://github.com/zzeneg/zmk-raw-hid/blob/6a37765dfab6197292e7a9f47305dcf87386d56a/src/hog.c#L125-L151)).
  Because it is a HID service, macOS's own HID stack subscribes to it, so Halfsies never touches it through CoreBluetooth (which hides 0x1812 anyway, see report 01).
- Existing users must forget and re-pair the keyboard after adding the service, because macOS caches the service list ([cornix-hud README L66-L69](https://github.com/meta-boy/cornix-hud/blob/7fffaac37d3c1986893d02cef94c21f61417b61b/README.md#L66-L69); [KeyPeek README L112-L113](https://github.com/srwi/keypeek/blob/78a2274aff9faaaf0edb783860db39d7b297d94d/README.md#L112-L113)).

Layer publishers that sit on top of `zmk-raw-hid`:

| Module | Message | Notes |
| --- | --- | --- |
| [srwi/zmk-keypeek-layer-notifier](https://github.com/srwi/zmk-keypeek-layer-notifier) (2026-02, last commit 2026-10-21) | `0xFF`, length, default-layer mask (u32), active-layer mask (u32) ([`layer_notifier.c` L15-L38](https://github.com/srwi/zmk-keypeek-layer-notifier/blob/23a9e46287e083a66d1d6f1939f68efb1f0f5295/src/layer_notifier.c#L15-L38)) | Also sends a `0xF1` packet for every key press and release by position ([L40-L75](https://github.com/srwi/zmk-keypeek-layer-notifier/blob/23a9e46287e083a66d1d6f1939f68efb1f0f5295/src/layer_notifier.c#L40-L75)), and tunnels Studio RPC as `0xF2` by default ([`Kconfig` L12-L20](https://github.com/srwi/zmk-keypeek-layer-notifier/blob/23a9e46287e083a66d1d6f1939f68efb1f0f5295/Kconfig#L12-L20)) |
| cornix-hud add-on in [meta-boy/zmk-keyboard-cornix@stock-keymap](https://github.com/meta-boy/zmk-keyboard-cornix/tree/stock-keymap) | `0xCD`, version, `0x01`, layer mask (u32 LE), highest layer, BLE profile, connected; host sends `[0xCD, 0x01]` to request state ([README L40-L57](https://github.com/meta-boy/cornix-hud/blob/7fffaac37d3c1986893d02cef94c21f61417b61b/README.md#L40-L57)) | Board-specific, about 60 lines |
| [senyasdt/zmk-yasb](https://github.com/senyasdt/zmk-yasb) (Windows widget) | Layer and battery state via `raise_raw_hid_sent_event` ([`layer_status.c`](https://github.com/senyasdt/zmk-yasb/blob/main/modules/zmk-yasb-layer-status/src/layer_status.c)) | Windows host only |

[lennyitb/zmk-layer-report](https://github.com/lennyitb/zmk-layer-report) (MIT, 2026-05) takes the same approach without `zmk-raw-hid`.
It adds its own USB HID interface and its own BLE HID service on usage page 0xFF42 with report ID 0x20 ([README L60-L76](https://github.com/lennyitb/zmk-layer-report/blob/a31472192a0de6ad1086bb0c62419c510d031ee6/README.md#L60-L76); [`ble_hid.c` L61-L82](https://github.com/lennyitb/zmk-layer-report/blob/a31472192a0de6ad1086bb0c62419c510d031ee6/src/ble_hid.c#L61-L82)).
Its 4-byte report is a u16 layer bitmap plus modifier state and sticky flags, and the current state can be read back over GATT after a reconnect ([`state-report-spec.md` L7-L29, L87-L92](https://github.com/lennyitb/zmk-layer-report/blob/a31472192a0de6ad1086bb0c62419c510d031ee6/docs/state-report-spec.md#L7-L29)).

### macOS side

Two native Swift macOS apps already read layer state this way with `IOHIDManager`, matching the primary usage page 0xFF60 and usage 0x61:

- [meta-boy/cornix-hud](https://github.com/meta-boy/cornix-hud) is a BLE menu bar app (battery plus layer overlay) ([`HUDLink.swift` L1-L42](https://github.com/meta-boy/cornix-hud/blob/7fffaac37d3c1986893d02cef94c21f61417b61b/app/Sources/CornixHUD/HUDLink.swift#L1-L42)).
- [Intersebbtor/ZMK-keymap-viewer](https://github.com/Intersebbtor/ZMK-keymap-viewer) says it works "over USB or Bluetooth" and that the vendor page "does not need the Input Monitoring permission" ([`LiveLayerMonitor.swift` L4-L45](https://github.com/Intersebbtor/ZMK-keymap-viewer/blob/de5546aca1045b6452ab610daa1b13980331b432/LiveLayerMonitor.swift#L4-L45)).

[KeyPeek](https://github.com/srwi/keypeek) (Rust, 210 stars) reaches the same interface through `hidapi` on macOS, and its code notes that on macOS a BLE ZMK keyboard may only be visible through the 0xFF60 interface ([`discovery.rs` L107-L121](https://github.com/srwi/keypeek/blob/78a2274aff9faaaf0edb783860db39d7b297d94d/crates/keypeek-protocol/src/firmware/zmk/discovery.rs#L107-L121); [`hid.rs` L1-L5](https://github.com/srwi/keypeek/blob/78a2274aff9faaaf0edb783860db39d7b297d94d/crates/keypeek-protocol/src/platform/hid.rs#L1-L5)).
A Windows user of `zmk-raw-hid` reports that BLE raw HID fails on Windows but "On Linux and Mac all works fine" ([zmk-raw-hid#4 comment](https://github.com/zzeneg/zmk-raw-hid/issues/4#issuecomment-4434034386)).

**Why no Input Monitoring, from Apple's source:**

- The kernel sets `kIOHIDRequiresTCCAuthorizationKey` only on HID devices that conform to Generic Desktop Keyboard, Generic Desktop Mouse or Digitizer Touch Pad ([`IOHIDDevice.cpp` L527-L531](https://github.com/apple-oss-distributions/IOHIDFamily/blob/e31e90a24c27ad6cbe981650d12a1a4124065b03/IOHIDFamily/IOHIDDevice.cpp#L527-L531)).
- "Conforms" means any entry in the device's `DeviceUsagePairs`, not only the primary usage ([`IOHIDDevice.cpp` L2569-L2610](https://github.com/apple-oss-distributions/IOHIDFamily/blob/e31e90a24c27ad6cbe981650d12a1a4124065b03/IOHIDFamily/IOHIDDevice.cpp#L2569-L2610)).
- User space calls `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)` on open only when that key is set, and otherwise opens freely ([`IOHIDDeviceClass.m` L511-L535](https://github.com/apple-oss-distributions/IOHIDFamily/blob/e31e90a24c27ad6cbe981650d12a1a4124065b03/IOHIDLib/IOHIDDeviceClass.m#L511-L535)).
  The SDK documents `kIOHIDRequestTypeListenEvent` as the Input Monitoring gate for `IOHIDManagerOpen` and `IOHIDDeviceOpen` (`IOKit.framework/Headers/hidsystem/IOHIDLib.h` L155-L159 in the macOS 27.2 SDK).
- A non-privileged local user may open a non-keyboard device, and only seizing a keyboard needs admin ([`IOHIDLibUserClient.cpp` L701-L715](https://github.com/apple-oss-distributions/IOHIDFamily/blob/e31e90a24c27ad6cbe981650d12a1a4124065b03/IOHIDFamily/IOHIDLibUserClient.cpp#L701-L715)).

So a separate USB interface with only the 0xFF60 collection is permission-free by construction.
For BLE, the answer depends on whether macOS turns the second HID service into its own `IOHIDDevice`, which happens in closed-source Bluetooth code.
The two Swift apps above match on primary usage page 0xFF60, which only works if it is its own device, but this must be checked on hardware (`hidutil list` or `ioreg`).

**Pitfalls:**

- `hidapi` on macOS opens devices exclusively (`kIOHIDOptionsTypeSeizeDevice`) by default since 0.12 ([`hid.c` L119](https://github.com/libusb/hidapi/blob/418d62afe38f05241bb9095dc13c5d783568586d/mac/hid.c#L119), [L468](https://github.com/libusb/hidapi/blob/418d62afe38f05241bb9095dc13c5d783568586d/mac/hid.c#L468); [`hidapi_darwin.h` L50-L68](https://github.com/libusb/hidapi/blob/418d62afe38f05241bb9095dc13c5d783568586d/mac/hidapi_darwin.h#L50-L68)).
  A seized device returns `kIOReturnExclusiveAccess` to everyone else ([`IOHIDLibUserClient.cpp` L716-L721](https://github.com/apple-oss-distributions/IOHIDFamily/blob/e31e90a24c27ad6cbe981650d12a1a4124065b03/IOHIDFamily/IOHIDLibUserClient.cpp#L716-L721)).
  Users hit exactly this error running `qmk-hid-host` against a ZMK board on macOS ([qmk-hid-host#15](https://github.com/zzeneg/qmk-hid-host/issues/15)).
  Halfsies must open with `kIOHIDOptionsTypeNone`, and should tell the user when another tool (KeyPeek, qmk-hid-host, Vial) holds the device.
- 0xFF60 is shared by many modules and apps, so the payload needs a magic byte or version, and the reader must ignore packets it does not know.
- The KeyPeek notifier streams every key press by position, which is a keystroke log of sorts and extra radio traffic; Halfsies should not ask users to install it just for a layer indicator.
- The notifications go out whether or not any app listens, because macOS subscribes to every HID report characteristic.
- Messages are only sent on change, so a freshly started app needs a request or heartbeat for the initial state (cornix-hud requests it and polls while its overlay is visible: [README L57](https://github.com/meta-boy/cornix-hud/blob/7fffaac37d3c1986893d02cef94c21f61417b61b/README.md#L57), [`Overlay.swift` L88-L94](https://github.com/meta-boy/cornix-hud/blob/7fffaac37d3c1986893d02cef94c21f61417b61b/app/Sources/CornixHUD/Overlay.swift#L88-L94)).

## B. Custom GATT service plus CDC-ACM serial

[rafaelromao/zmk-layer-hud](https://github.com/rafaelromao/zmk-layer-hud) (MIT, created 2026-09-16, active) ships the most carefully designed module of this kind, together with a macOS HUD.

- Over BLE it defines its own primary service `d1f0a7c2-6b3e-4f8a-9c21-5e7b4a0d9f31` with one notify characteristic `d1f0a7c3-...`, and the CCC needs encryption, so only a bonded host can subscribe ([`signal_gatt.c` L39-L60](https://github.com/rafaelromao/zmk-layer-hud/blob/5ec92a4d91f365e04b057aabe8a9952d2a292de8/firmware/src/signal_gatt.c#L39-L60)).
- It notifies only the active profile's host, and only if that host subscribed; the author fixed a bug where a Mac on another profile saw key positions typed into a different computer ([`signal_gatt.c` L15-L20, L62-L83](https://github.com/rafaelromao/zmk-layer-hud/blob/5ec92a4d91f365e04b057aabe8a9952d2a292de8/firmware/src/signal_gatt.c#L15-L20)).
- Over USB it uses a CDC-ACM interface of its own, added by a `layer-hud-usb-uart` snippet ([`zmk-setup.md` L81-L112](https://github.com/rafaelromao/zmk-layer-hud/blob/5ec92a4d91f365e04b057aabe8a9952d2a292de8/docs/zmk-setup.md#L81-L112)).
- Frames are `A5 5A ver kind len payload crc8`, and the layers frame carries the full u32 layer bitmap ([`signal_frame.h` L14-L40](https://github.com/rafaelromao/zmk-layer-hud/blob/5ec92a4d91f365e04b057aabe8a9952d2a292de8/firmware/src/signal_frame.h#L14-L40)).
- A configurable heartbeat (2 s in the example) lets a late-starting host catch up, and key positions are opt-in ([README L43-L48](https://github.com/rafaelromao/zmk-layer-hud/blob/5ec92a4d91f365e04b057aabe8a9952d2a292de8/README.md#L43-L48)).
- The author explains why not to hide the signal in keyboard reports: Linux maps reserved keyboard usages to real key events ([`zmk-setup.md` L137-L156](https://github.com/rafaelromao/zmk-layer-hud/blob/5ec92a4d91f365e04b057aabe8a9952d2a292de8/docs/zmk-setup.md#L137-L156)).
- On macOS the host reads the channel with bleak (CoreBluetooth) or pyserial; only its optional typed-keys strip needs Input Monitoring, and "the signal channel needs nothing" ([README L429-L436](https://github.com/rafaelromao/zmk-layer-hud/blob/5ec92a4d91f365e04b057aabe8a9952d2a292de8/README.md#L429-L436); [L511-L512](https://github.com/rafaelromao/zmk-layer-hud/blob/5ec92a4d91f365e04b057aabe8a9952d2a292de8/README.md#L511-L512)).
- The serial port needs no permission on macOS, and the HUD takes it exclusively (`TIOCEXCL`), which blocks other tools such as ZMK Studio until it stops ([README L535-L539](https://github.com/rafaelromao/zmk-layer-hud/blob/5ec92a4d91f365e04b057aabe8a9952d2a292de8/README.md#L535-L539)).

[taichi-dm/zmk-layer-notifier](https://github.com/taichi-dm/zmk-layer-notifier) (0 stars, one day of commits in 2026-03) is a smaller proof of concept aimed at macOS.
It sends one byte, the highest active layer, on a custom service `E6B30001-...` and over a CDC-ACM UART, debounced by 16 ms ([`ble_transport.c` L1-L64](https://github.com/taichi-dm/zmk-layer-notifier/blob/f82b8afbce035f7f5902eda9e5ef31cce52d023e/src/ble_transport.c#L1-L64); [`layer_notifier.c` L31-L59](https://github.com/taichi-dm/zmk-layer-notifier/blob/f82b8afbce035f7f5902eda9e5ef31cce52d023e/src/layer_notifier.c#L31-L59)).
It needs no encryption and notifies every connection (`bt_gatt_notify(NULL, ...)`), which is the cross-profile leak that zmk-layer-hud fixed ([`ble_transport.c` L46-L60](https://github.com/taichi-dm/zmk-layer-notifier/blob/f82b8afbce035f7f5902eda9e5ef31cce52d023e/src/ble_transport.c#L46-L60)).

Fit with Halfsies:

- The BLE half reuses the CoreBluetooth plumbing Halfsies builds for battery: attach to the system-held connection with `retrieveConnectedPeripherals`, discover, subscribe (report 01, section on Studio and `gatt.rs`).
- USB and dongle setups need a second path through a serial port, with its own discovery, framing and exclusivity rules.
- Subscription is explicit, so the keyboard sends nothing when Halfsies is not running.

## C. Vendor report inside the keyboard's HID descriptor

[pfilipp/zmk-layer](https://github.com/pfilipp/zmk-layer) is a native Swift menu bar app that shows the active layer and lock state ([README L5-L9](https://github.com/pfilipp/zmk-layer/blob/e90c37562b2bc666ff921f7d439b6fb858c0c9a3/README.md#L5-L9)).
It requires firmware built from the [pfilipp/zmk](https://github.com/pfilipp/zmk/tree/layer-state-report) fork with `CONFIG_ZMK_HID_LAYER_STATE_REPORT=y` ([README L20, L28-L47](https://github.com/pfilipp/zmk-layer/blob/e90c37562b2bc666ff921f7d439b6fb858c0c9a3/README.md#L20)).
The fork adds report ID 0x04 on vendor page 0xFF00 with two bytes (highest layer, locked) to ZMK's main HID report map ([fork docs L5-L33](https://github.com/pfilipp/zmk/blob/4994db488fb79707de693967def2f282651d5fb7/docs/docs/features/layer-state-report.md#L5-L33)).
The app matches the Generic Desktop Keyboard device and filters for report ID 0x04 ([`HIDManager.swift` L47-L54, L140-L160](https://github.com/pfilipp/zmk-layer/blob/e90c37562b2bc666ff921f7d439b6fb858c0c9a3/zmk-layer/HIDManager.swift#L47-L54)).
Because the collection lives in the same HID device as the keyboard, that device conforms to Keyboard and opening it triggers the Input Monitoring prompt ([`IOHIDDevice.cpp` L527-L531](https://github.com/apple-oss-distributions/IOHIDFamily/blob/e31e90a24c27ad6cbe981650d12a1a4124065b03/IOHIDFamily/IOHIDDevice.cpp#L527-L531)).
Open ZMK PR [#3390](https://github.com/zmkfirmware/zmk/pull/3390) (2026-06, no review) would add a similar vendor "vkey" collection to the main descriptor upstream, with the same macOS consequence.
Rejected for Halfsies: it needs a fork today, and Input Monitoring is a heavier and more alarming permission than Bluetooth.

## D. ZMK Studio RPC

What the protocol offers:

- Requests: `core` (device info, lock state, lock, reset), `behaviors`, and `keymap` (get keymap, set binding, save, discard, physical layouts, layer add, move, remove, restore, rename) ([`studio.proto` L11-L19](https://github.com/zmkfirmware/zmk-studio-messages/blob/6cb4c283e76209d59c45fbcb218800cd19e9339d/proto/zmk/studio.proto#L11-L19); [`keymap.proto` L5-L20](https://github.com/zmkfirmware/zmk-studio-messages/blob/6cb4c283e76209d59c45fbcb218800cd19e9339d/proto/zmk/keymap.proto#L5-L20)).
- `Keymap` and `Layer` carry ids, names and bindings, but no active flag ([`keymap.proto` L176-L186](https://github.com/zmkfirmware/zmk-studio-messages/blob/6cb4c283e76209d59c45fbcb218800cd19e9339d/proto/zmk/keymap.proto#L176-L186)).
- Notifications: lock state and unsaved changes only, as in the TL;DR.
- Firmware: the only event mapper with content is the core lock-state mapper ([`core_subsystem.c` L96](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/core_subsystem.c#L96)), and the RPC listener subscribes only to endpoint changes and RPC notifications ([`rpc.c` L316-L347](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/rpc.c#L316-L347)).
- Upstream has no open PR to add layer state; the zmk-studio-messages repo has one closed "layer rgb sync" PR with no body ([zmk-studio-messages#1](https://github.com/zmkfirmware/zmk-studio-messages/pull/1)).

Unlock: today there is nothing to unlock for.
If a layer notification were added, the lock would not block it, because notifications are sent straight from the event listener without the lock check that guards secured request handlers ([`rpc.c` L316-L330](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/rpc.c#L316-L330)).
Layer names, though, come only from `get_keymap`, which is secured and needs `&studio_unlock` ([`keymap_subsystem.c` L527](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/keymap_subsystem.c#L527)).

The extension route exists only in a fork:
[cormoran/zmk](https://github.com/cormoran/zmk/tree/main%2Bcustom-studio-protocol) branch `main+custom-studio-protocol` adds custom RPC subsystems (commit `e0ad0fbaea`, "feat(studio): implement custom rpc protocol"), and modules such as [cormoran/zmk-feature-device-info](https://github.com/cormoran/zmk-feature-device-info) require that patched ZMK ([README L24-L39](https://github.com/cormoran/zmk-feature-device-info/blob/main/README.md#L24-L39)).
A layer-state subsystem could be written there, but users would have to move their whole firmware to a fork.

Running Studio permanently alongside the OS connection:

- Over BLE it is a GATT service on the same link as HID, so a third-party app can keep it open while macOS types over HID (report 01, section 1.6).
- But while any client is subscribed, ZMK requests peripheral latency 10 instead of 30 ([`gatt_rpc_transport.c` L34-L53](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/gatt_rpc_transport.c#L34-L53); [`app/Kconfig` L242-L243](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/Kconfig#L242-L243)), so an always-on menu bar app would cost keyboard battery around the clock.
- RPC answers only on the transport of the selected output endpoint ([`rpc.c` L245-L282](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/rpc.c#L245-L282)), and the device relocks on disconnect and after 600 s idle ([`studio/Kconfig` L22-L28](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/Kconfig#L22-L28)).
- Over USB, Studio is a CDC-ACM serial port from the `studio-rpc-usb-uart` snippet ([`studio.md` L78-L92](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/features/studio.md#L78-L92)); a serial port has one practical owner, so Halfsies and the ZMK Studio app would fight over it.
- `CONFIG_ZMK_STUDIO` selects RPC only on the central ([`studio/Kconfig` L4-L6](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/Kconfig#L4-L6)), and the BLE transport defaults on once Studio is on ([L76-L81](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/Kconfig#L76-L81)); Studio also costs significant RAM ([`studio.md` L181](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/features/studio.md#L181)).

Studio remains useful as an optional, on-demand source of layer names (see "Layer ids and names" below), not as the live layer channel.

## E. Keycode side channel

A maintainer's suggested workaround is to send special keycodes such as F13 from layer keys via macros, or to hook layer changes with [ssbb/zmk-listeners](https://github.com/ssbb/zmk-listeners) ([zmk#2772 comment](https://github.com/zmkfirmware/zmk/issues/2772#issuecomment-2596369756)).

- Macros can wrap `&mo` with other behaviors using `&macro_pause_for_release` ([`macros.md` L219-L256](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/keymaps/behaviors/macros.md#L219-L256)), but every layer key in the keymap must be rewritten, and `&tog`, `&to`, conditional layers and combos would each need care.
- `zmk-listeners` (21 stars, last push 2025-12) triggers one behavior on layer entry and another on exit, with a 5 ms default tap time ([README L27-L61](https://github.com/ssbb/zmk-listeners/blob/main/README.md#L27-L61)), so it catches every way a layer changes.
- macOS defines virtual key codes only up to F20 (`kVK_F13` to `kVK_F20` in `HIToolbox.framework/Headers/Events.h` L281-L301 of the macOS 27.2 SDK), so at most eight unmodified keys are available, and more layers need modifier combinations.

macOS permissions to observe those keys:

- `NSEvent.addGlobalMonitorForEvents` sees key events only if the app is trusted for Accessibility, and never sees events sent to itself ([Apple docs](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))).
- A listen-only `CGEventTap` needs Input Monitoring, checked with `CGPreflightListenEventAccess` and requested with `CGRequestListenEventAccess` (`CGEvent.h` L398-L402 in the macOS 27.2 SDK; [Apple docs](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:))).
- `IOHIDManager` on the keyboard device needs Input Monitoring, as in option C.

Costs: the keys also reach the focused app and any shortcut bound to them; while any process holds Secure Event Input (password fields, Terminal's Secure Keyboard Entry), keyboard events stop reaching every intercepting process, so layer changes are silently missed ([Apple TN2150](https://developer.apple.com/library/archive/technotes/tn2150/_index.html)).
This is the only option that needs no custom C module, but it is the least robust and asks for the most sensitive permission.

## F. Dead ends

- **HID LED indicators:** ZMK's five indicator states (Num, Caps, Scroll Lock, Compose, Kana) flow from host to keyboard only ([`led-indicators.md` L6-L14](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/features/led-indicators.md#L6-L14); [`hid_indicators.c` L54](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/hid_indicators.c#L54)).
  Projects such as [GarrettFaucher/zmk-focus-layer](https://github.com/GarrettFaucher/zmk-focus-layer) use Scroll Lock the other way round, to let the host switch the keyboard's layer.
- **Typing the layer name:** [DivisionSt/zmk-layer-id](https://github.com/DivisionSt/zmk-layer-id) types the current layer name as text on a key press ([README L1-L10](https://github.com/DivisionSt/zmk-layer-id/blob/main/README.md#L1-L10)); it is on demand, not live.
- **Inferring from normal key reports:** layer state is not in any standard report ([zmk#2772 comment](https://github.com/zmkfirmware/zmk/issues/2772#issuecomment-2596369756)).
- **Battery or other standard GATT services:** none carry layer state; the central's GATT additions on `main` are HID, Battery and the optional battery proxy (report 01).

## Split and dongle nuances

- Layer state lives only on the central: "The internal keyboard state (like active layers) is handled exclusively by the central" ([`split-keyboards.md` L13](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/features/split-keyboards.md#L13)).
  `keymap.c` and the layer event are compiled only for non-split or central builds ([`app/CMakeLists.txt` L48, L77-L78](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/CMakeLists.txt#L48-L78)).
- The split protocol sends no layer state to peripherals; central-to-peripheral commands are poll, invoke behavior, set physical layout and set HID indicators ([`split/transport/types.h` L64-L69](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/include/zmk/split/transport/types.h#L64-L69)).
  So only the central (or dongle) needs the new module and a reflash; the peripheral half is untouched.
  Every module above says the same ([zmk-layer-hud README L55](https://github.com/rafaelromao/zmk-layer-hud/blob/5ec92a4d91f365e04b057aabe8a9952d2a292de8/README.md#L55); [KeyPeek README L100](https://github.com/srwi/keypeek/blob/78a2274aff9faaaf0edb783860db39d7b297d94d/README.md#L100); [pfilipp docs L169-L171](https://github.com/pfilipp/zmk/blob/4994db488fb79707de693967def2f282651d5fb7/docs/docs/features/layer-state-report.md#L169-L171)).
- With a dongle, the dongle is the central ([`split-keyboards.md` L11](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/features/split-keyboards.md#L11)) and usually reaches the Mac over USB, so only USB-capable designs (A, or the serial half of B) work there.
  Battery has no dongle path on `main` (report 01), so a dongle user could get layers but not battery.
- Layer and battery data both come from the central over the same BLE link, so "central disconnected" means both go stale together, while a sleeping peripheral affects only its battery.
- Only the active BLE profile's host receives updates in well-behaved modules (`zmk-raw-hid` [`hog.c` L126](https://github.com/zzeneg/zmk-raw-hid/blob/6a37765dfab6197292e7a9f47305dcf87386d56a/src/hog.c#L126); zmk-layer-hud [`signal_gatt.c` L67-L81](https://github.com/rafaelromao/zmk-layer-hud/blob/5ec92a4d91f365e04b057aabe8a9952d2a292de8/firmware/src/signal_gatt.c#L67-L81)).
  If the Mac is bonded but another profile is selected, Halfsies should show "not the active device" rather than a stale layer.

### Layer ids and names

- The event and `zmk_keymap_layer_state()` work in layer ids, while `zmk_keymap_highest_layer_active()` returns an index ([`keymap.c` L177-L209](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/keymap.c#L177-L209)).
- Studio builds turn on layer reordering ([`studio/Kconfig` L46](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/Kconfig#L46)), after which ids and indexes differ ([`keymap.c` L112-L132](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/keymap.c#L112-L132)).
  A protocol should send the id bitmap, and the app should label ids.
- The firmware knows each layer's display name (`zmk_keymap_layer_name`, [`keymap.h` L55](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/include/zmk/keymap.h#L55)), so a Halfsies module could answer a "names" request; otherwise names come from Studio `get_keymap` after an unlock, or from user settings in the app.
- The event's `locked` flag ([`layer_state_changed.h` L15](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/include/zmk/events/layer_state_changed.h#L15)) lets the UI tell a toggled layer from a held one; ZMK keeps a separate lock mask ([`keymap.c` L179](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/keymap.c#L179)).
- Momentary layers under hold-tap can flicker; existing modules coalesce bursts (16 ms in taichi-dm, a settle timer in zmk-layer-hud [`layer_signal.c` L77-L80](https://github.com/rafaelromao/zmk-layer-hud/blob/5ec92a4d91f365e04b057aabe8a9952d2a292de8/firmware/src/layer_signal.c#L77-L80)).

## Recommendation

Build the layer display on option A.

1. **Firmware:** document `zzeneg/zmk-raw-hid` plus a small Halfsies publisher module for the central or dongle.
   The module should send a versioned packet with a magic byte, the u32 layer-id bitmap and the lock mask, on change and on request, and nothing about key presses.
   It should answer a "names" request with `zmk_keymap_layer_name` so the app needs no Studio unlock.
   Optionally, the app can also parse KeyPeek's `0xFF` layer packet so KeyPeek users need no extra module.
2. **App:** one `IOHIDManager` reader matching primary usage page 0xFF60 and usage 0x61, opened with `kIOHIDOptionsTypeNone`, correlated to the CoreBluetooth battery peripheral by name or VID/PID.
   This covers BLE, USB and dongle with one code path and keeps the app free of Input Monitoring.
3. **Gate on the spike:** if macOS 26 shows the BLE raw HID collection inside the keyboard's `IOHIDDevice` (or prompts for Input Monitoring), switch to option B and consider supporting the zmk-layer-hud wire format, which is already MIT and well specified.
4. **Do not use** Studio RPC as the live channel (no message, fork needed, battery cost) or keycode tricks (permissions, leaks, Secure Input gaps), and do not use designs that extend the keyboard's own descriptor.

Why A over B: the user cost is similar (one or two modules on the central plus a re-pair), but A gives one transport on the Mac for every connection type and builds on the most widely used ZMK raw HID module.
B's advantage is that it needs only the Bluetooth permission for certain, and it sends nothing when no app subscribes.

## Open questions needing hardware

1. With `zmk-raw-hid` over BLE on macOS 26, does `hidutil list` show a separate HID device with primary usage page 0xFF60, and does `IOHIDManagerOpen` on it complete without an Input Monitoring prompt?
2. Is a re-pair needed after adding a HID service or a custom GATT service, and does macOS honour a Service Changed indication instead?
3. Can Halfsies open the raw HID device while KeyPeek, qmk-hid-host or Vial hold it, and how should the app report a seize conflict?
4. What end-to-end latency does a layer change show over BLE and USB, and which connection interval does macOS actually grant?
5. With option B, do CoreBluetooth notifications arrive on the system-held connection (the same question as battery question 3 in report 01)?
6. With a USB dongle, does the dongle's composite device expose the raw HID interface separately from its keyboard interface?
7. When the Mac is bonded on an inactive BLE profile, is the stale-state case detectable (no reports versus a disconnect)?
8. If two Mac apps subscribe to the same ZMK Studio characteristic over one BLE link, do both receive every indication, and do their RPC responses interleave?
