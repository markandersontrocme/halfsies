# ZMK and macOS BLE feasibility for halfsies

Research date: 2026-11-09.
ZMK sources are pinned to `main` at commit [`4dd95d78`](https://github.com/zmkfirmware/zmk/commit/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85) (2026-10-09).
The latest tagged ZMK release is [`v0.3.0`](https://github.com/zmkfirmware/zmk/releases/tag/v0.3.0) (2025-08-01).
ZMK `main` builds against Zephyr `v4.1.0+zmk-fixes` ([`app/west.yml` L8-L11](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/west.yml#L8-L11)).
Local checks ran on macOS 27.0.1 (build 26A434) with the macOS 27.0 Command Line Tools SDK.

## TL;DR

- ZMK can expose the peripheral half's battery to the host, but only when the user sets two Kconfig options on the central, and both default to `n`.
  The options are `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y` and `CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y` ([docs `config/split.md` L28-L29](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/config/split.md#L28-L29)).
  With stock firmware, no host API can read the peripheral half, so the app needs an onboarding step that tells the user to change their firmware config.
- With the proxy on, the central's GATT table has a second Battery Service (0x180F) instance.
  Each peripheral gets one Battery Level (0x2A19) characteristic with read and notify, a Characteristic Presentation Format (0x2904) descriptor with description `0x0108` ("auxiliary"), and a User Description (0x2901) descriptor with the text `"Peripheral <n>"` ([`central_bas_proxy.c` L45-L69](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/central_bas_proxy.c#L45-L69)).
  The central's own battery stays in Zephyr's stock Battery Service, whose 0x2904 description is `0x0106` ("main") ([Zephyr `bas.c` L67-L80](https://github.com/zmkfirmware/zephyr/blob/v4.1.0%2Bzmk-fixes/subsys/bluetooth/services/bas/bas.c#L67-L80)).
  A host tells the halves apart by the 0x2904 description (main vs auxiliary) and the 0x2901 string, not by order.
- On this Mac, macOS 27 already publishes both halves of a connected ZMK split ("Forager", VID 0x1D50 / PID 0x615E) as two separate accessory power sources, at 39% and 86%.
  `pmset -g accps` lists both, and the IOKit SPI `IOPSCopyPowerSourcesByType` returns them, with the second tagged `"Part Identifier" = "Other"`.
  Apple's Accessory Design Guidelines say multi-instance Battery Service support started in macOS 26 ([ADG R32 Update 1, section 33, p. 242](https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf)).
  That path needs no CoreBluetooth and no Bluetooth TCC prompt, but it depends on private API and keys.
- The public path is CoreBluetooth.
  Apple documents that `retrieveConnectedPeripherals(withServices:)` returns peripherals that other apps (including the system) connected, and that the app must call `connect` locally before use ([Apple docs](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals(withservices:))).
  Apple's guidelines list the services that iOS filters out of third-party discovery as GATT, GAP, HID and ANCS, so Battery Service is not filtered ([ADG section 57.14, p. 348-349](https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf)).
  ZMK Studio's own macOS app uses this exact pattern to reach a custom GATT service on a ZMK keyboard that macOS already holds connected ([`zmk-studio` `gatt.rs` L105-L158](https://github.com/zmkfirmware/zmk-studio/blob/main/src-tauri/src/transport/gatt.rs#L105-L158)).
- ZMK Studio's RPC protocol has no battery messages.
  It runs protobuf over a custom GATT service (`00000000-0196-6107-c967-c5cfb1c2482a`) or over USB CDC-ACM serial, and most keymap calls require the user to press a physical `&studio_unlock` key first.
  It is a candidate transport for later keymap features, not for battery.
- Dongle setups (dongle as central over USB, both halves as BLE peripherals) have no battery path to the host on ZMK `main`.
  ZMK has no USB HID battery report on `main`, and Studio has no battery call.
  Open PR [#3458](https://github.com/zmkfirmware/zmk/pull/3458) would add per-part HID battery reports and per-part Battery Service instances, but it is not merged.
- Biggest risks: users must reflash with non-default config, the proxy has an open memory-corruption bug ([#3522](https://github.com/zmkfirmware/zmk/issues/3522)), and the 3+-part case violates the Battery Service spec, so OS behaviour there is undefined.

## 1. ZMK firmware side

### 1.1 Kconfig options and defaults

ZMK defines the fetch and proxy options in [`app/src/split/bluetooth/Kconfig`](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/Kconfig).

| Option | Defined at | Default | Effect |
| --- | --- | --- | --- |
| `ZMK_SPLIT_BLE_CENTRAL_PERIPHERALS` | [L30-L31](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/Kconfig#L30-L31) | `1` ([`Kconfig.defaults` L13-L14](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/Kconfig.defaults#L13-L14)) | Number of peripheral slots on the central. |
| `ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING` | [L33-L37](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/Kconfig#L33-L37) | `n` (no `default` line) | Central subscribes to each peripheral's Battery Level and raises internal events. |
| `ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY` | [L45-L49](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/Kconfig#L45-L49) | `n` (no `default` line) | Central re-exposes the peripheral levels to hosts in an extra Battery Service. |

The proxy option sits inside `if ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING` ([L39-L51](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/Kconfig#L39-L51)), so it cannot be enabled alone.
The docs table lists both defaults as `n` ([`docs/config/split.md` L28-L29](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/config/split.md#L28-L29)).
The docs tell users to set both to `y` to report both sides ([`docs/config/battery.md` L31-L34](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/config/battery.md#L31-L34)).
The docs also warn that "Host support for multiple battery levels is undefined" and that users "probably need a special application or script" ([L36-L38](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/config/battery.md#L36-L38)).
The feature page repeats that only the central's level reaches the host by default ([`docs/features/battery.md` L8](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/features/battery.md#L8)).

The central's own Battery Service is on by default.
`ZMK_BLE` implies `ZMK_BATTERY_REPORTING` ([`app/Kconfig` L173](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/Kconfig#L173)), which implies Zephyr's `BT_BAS` ([`app/Kconfig` L382-L386](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/Kconfig#L382-L386)).
Users can turn it off with `CONFIG_BT_BAS=n`, which the docs suggest because BAS notifications can wake macOS from sleep ([`docs/config/battery.md` L27](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/config/battery.md#L27)).
The app should handle a keyboard that has no Battery Service at all.

The proxy has existed since PR [#2045](https://github.com/zmkfirmware/zmk/pull/2045) (merged 2024-01-03), so it is in v0.3.0 and `main`.
The build only compiles `central_bas_proxy.c` when the proxy option is set ([`app/src/split/bluetooth/CMakeLists.txt` L12-L14](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/CMakeLists.txt#L12-L14)).

### 1.2 GATT layout with the proxy on

The proxy defines one extra primary Battery Service named `bas_aux` ([`central_bas_proxy.c` L67-L69](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/central_bas_proxy.c#L67-L69)).
`LISTIFY` adds one group of attributes per peripheral slot, so N peripherals produce N Battery Level characteristics inside that single service.
Each group has these attributes ([L61-L65](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/central_bas_proxy.c#L61-L65)):

- Battery Level 0x2A19 with `READ | NOTIFY` and plain read permission (no encryption required).
- Client Characteristic Configuration 0x2902.
- Characteristic Presentation Format 0x2904 with format uint8 (`0x04`), unit percentage (`0x27AD`), namespace Bluetooth SIG (`0x01`), and description `0x0108` ([L45-L51](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/central_bas_proxy.c#L45-L51)).
- Characteristic User Description 0x2901 with the string `"Peripheral 0"`, `"Peripheral 1"`, and so on ([L53-L54](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/central_bas_proxy.c#L53-L54)).

The Bluetooth SIG namespace table maps `0x0106` to "main", `0x0108` to "auxiliary", `0x010D` to "left" and `0x010E` to "right" ([SIG `namespace.yaml`](https://bitbucket.org/bluetooth-SIG/public/src/main/assigned_numbers/core/namespace.yaml)).

The central's own level stays in Zephyr's stock `bas` service.
That service has a 0x2904 descriptor with description `0x0106` ("main") and no 0x2901 descriptor ([Zephyr `bas.c` L67-L80](https://github.com/zmkfirmware/zephyr/blob/v4.1.0%2Bzmk-fixes/subsys/bluetooth/services/bas/bas.c#L67-L80)).
ZMK writes the central's level into it with `bt_bas_set_battery_level` ([`battery.c` L106-L117](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/battery.c#L106-L117)).
Zephyr initialises that level to 100 before the first sample ([`bas.c` L32](https://github.com/zmkfirmware/zephyr/blob/v4.1.0%2Bzmk-fixes/subsys/bluetooth/services/bas/bas.c#L32)).

Handle order is likely "main" first, then "auxiliary", but the app should not depend on it.
Zephyr places static services in a linker section sorted by name ([`BT_GATT_SERVICE_DEFINE`, `gatt.h` L842-L845](https://github.com/zmkfirmware/zephyr/blob/v4.1.0%2Bzmk-fixes/include/zephyr/bluetooth/gatt.h#L842-L845); [`Z_LINK_ITERABLE`, `linker/iterable_sections.h` L15-L18](https://github.com/zmkfirmware/zephyr/blob/v4.1.0%2Bzmk-fixes/include/zephyr/linker/iterable_sections.h#L15-L18)).
The section names are `bas_` and `bas_aux_`, so `bas` sorts first.
This is my reading of the macros, not a documented guarantee, and PR #3458 renames these services.

How a host should tell the instances apart:

1. Read each Battery Level's 0x2904 descriptor and decode the 2-byte description at offset 5.
   `0x0106` is the central, and `0x0108` is a proxied peripheral.
2. Read the 0x2901 descriptor of each auxiliary characteristic to get the peripheral slot index.
3. Treat a Battery Level with no 0x2904 as "the device" when it is the only one.

ZMK assigns slot numbers in the order peripherals are first bonded, not by left or right.
`reserve_peripheral_slot` calls `zmk_ble_put_peripheral_addr`, which returns the first stored address that matches or the first empty slot, and saves it to settings ([`central.c` L226-L237](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/central.c#L226-L237); [`ble.c` L380-L405](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/ble.c#L380-L405)).
For a two-half board, "Peripheral 0" is simply "the other half".
For a dongle with two halves, the app cannot know which slot is left without asking the user once.

### 1.3 Spec compliance

The Battery Service v1.1 spec allows multiple service instances, one per battery ([BAS v1.1 section 1](https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/BAS_v1.1/out/en/index-en.html)).
It says "Only one instance of each characteristic is permitted within this service" (section 3).
It requires a 0x2904 descriptor on each Battery Level when there is more than one Battery Service, with a description that "is unique among all instances of the Battery Service" (section 3.1.2.1).

ZMK's layout complies for a two-part split, which has one main and one auxiliary instance.
It breaks the spec for three or more parts, such as a dongle with two halves or a three-part keyboard.
In that case one service holds several Battery Level characteristics, and they all share the description "auxiliary".
Host behaviour for that layout is undefined, and the app has to rely on the 0x2901 strings there.

A dongle with two peripherals did not compile at all in v0.3.0 ([#3095](https://github.com/zmkfirmware/zmk/issues/3095)).
The fix landed on `main` on 2025-12-07 ([#3105, commit `ece2ce11`](https://github.com/zmkfirmware/zmk/commit/ece2ce11b8)) and is not in any tagged release yet.

### 1.4 Notifications and value semantics

The proxied characteristic supports notify.
When the central gets a peripheral battery event, the proxy calls `bt_gatt_notify(NULL, ...)` on that slot's value attribute, which notifies every subscribed host ([`central_bas_proxy.c` L71-L97](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/central_bas_proxy.c#L71-L97)).
Reads return the cached value from `zmk_split_central_get_peripheral_battery_level` ([L31-L43](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/central_bas_proxy.c#L31-L43); [`split/central.c` L153-L164](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/central.c#L153-L164)).

Upstream of the proxy, the central subscribes to the peripheral's Battery Level and also does one read after discovery ([`central.c` L623-L639](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/central.c#L623-L639)).
Each part samples its battery every `CONFIG_ZMK_BATTERY_REPORT_INTERVAL` seconds, 60 by default ([docs `config/battery.md` L17](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/config/battery.md#L17); [`battery.c` L138-L141](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/battery.c#L138-L141)).
Sampling stops when the part goes idle or to sleep ([`battery.c` L173](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/battery.c#L173)), so levels go stale while the keyboard is idle.
The app should subscribe to notifications rather than poll, because polling cannot get fresher data than the firmware's 60-second sampling.

Two value quirks matter for the UI:

- When a peripheral disconnects, the central sets that slot to 0 ([`central.c` L951-L969](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/bluetooth/central.c#L951-L969)).
  The slot also reads 0 before a peripheral first connects ([`split/central.c` L26-L30](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/split/central.c#L26-L30)).
  The app cannot tell "half disconnected" from "battery empty", so it should show 0 as "unknown or disconnected".
- The disconnect handler runs for every connection, including the host's.
  For a host connection, the slot index is `-EINVAL`, which wraps to 234 in a `uint8_t`, and the central writes 0 past the end of its battery array.
  The bug is open as [#3522](https://github.com/zmkfirmware/zmk/issues/3522), with a fix in open PR [#3556](https://github.com/zmkfirmware/zmk/pull/3556).
  The report shows this can crash the Bluetooth controller on some builds, which is a support risk when we tell users to enable fetching.

### 1.5 Multiple peripherals and dongles

ZMK docs say that with a dongle "the dongle takes on the role of central" ([`docs/features/split-keyboards.md` L11](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/features/split-keyboards.md#L11)), and that dongles typically connect to the host over USB ([`docs/hardware-integration/dongle.mdx` L15](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/hardware-integration/dongle.mdx#L15)).
Over USB, the host never sees a Battery Service, so the BLE proxy does not help.

ZMK `main` has no USB HID battery report.
A code search for "battery" under `app/src` finds no hit in `hid.c` or `usb_hid.c` ([search](https://github.com/search?q=repo%3Azmkfirmware%2Fzmk+battery+path%3Aapp%2Fsrc&type=code)).
Open PR [#2938](https://github.com/zmkfirmware/zmk/pull/2938) and its successor [#3458](https://github.com/zmkfirmware/zmk/pull/3458) add HID battery reports per part, one Battery Service instance per part, configurable 0x2904 descriptions (which would allow "left" and "right"), and an optional "Lowest Charge" main service.
PR #3458 was tested against Linux 7.1, and its author notes that neither PR was tested on Apple hosts.

If a dongle connects to the Mac over BLE instead, the proxy layout from section 1.2 applies with N=2.
The dongle has no battery sensor in most builds, so its "main" service reports Zephyr's default 100.

### 1.6 ZMK Studio

Transports:

- BLE GATT uses service `00000000-0196-6107-c967-c5cfb1c2482a` and one RPC characteristic `00000001-0196-6107-c967-c5cfb1c2482a` with write, read and indicate ([`studio/uuid.h` L11-L13](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/uuid.h#L11-L13); [`gatt_rpc_transport.c` L89-L95](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/gatt_rpc_transport.c#L89-L95)).
  Both attributes require an encrypted link.
- USB uses a CDC-ACM serial port added by the `studio-rpc-usb-uart` snippet ([`snippet .conf`](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/snippets/studio-rpc-usb-uart/studio-rpc-usb-uart.conf); [`.overlay`](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/snippets/studio-rpc-usb-uart/studio-rpc-usb-uart.overlay)).
- Both transports frame bytes with SOF `0xAB`, escape `0xAC` and EOF `0xAD` ([`msg_framing.h` L19-L21](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/msg_framing.h#L19-L21)).

Studio is off by default.
`ZMK_STUDIO` has no default ([`studio/Kconfig` L4-L9](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/Kconfig#L4-L9)), and the docs tell users to enable it plus the snippet on the central only ([`docs/features/studio.md` L78-L92](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/features/studio.md#L78-L92)).
Once Studio is on, the BLE transport defaults to on ([L76-L81](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/Kconfig#L76-L81)).
The RPC layer only listens on the transport that matches the keyboard's selected output endpoint ([`rpc.c` L245-L262](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/rpc.c#L245-L262)).
Over BLE it sends responses only to the active profile's connection ([`gatt_rpc_transport.c` L140-L147](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/gatt_rpc_transport.c#L140-L147)).
Docs confirm the user must select the same output endpoint they connect Studio over ([`studio.md` L69-L70](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/features/studio.md#L69-L70)).
When a client subscribes, ZMK requests a lower peripheral latency of 10 by default, which costs keyboard battery ([L34-L53](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/gatt_rpc_transport.c#L34-L53); [`Kconfig` L89-L94](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/Kconfig#L89-L94)).

Protocol:
The messages are proto3 files in [zmkfirmware/zmk-studio-messages](https://github.com/zmkfirmware/zmk-studio-messages/tree/6cb4c283e76209d59c45fbcb218800cd19e9339d/proto/zmk) (MIT), pinned by ZMK at commit `6cb4c283` ([`west.yml` L41-L44](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/west.yml#L41-L44)).
The top-level `Request` has three subsystems: `core`, `behaviors` and `keymap` ([`studio.proto` L11-L19](https://github.com/zmkfirmware/zmk-studio-messages/blob/6cb4c283e76209d59c45fbcb218800cd19e9339d/proto/zmk/studio.proto#L11-L19)).
`core` offers device info, lock state, lock and settings reset ([`core.proto` L10-L17](https://github.com/zmkfirmware/zmk-studio-messages/blob/6cb4c283e76209d59c45fbcb218800cd19e9339d/proto/zmk/core.proto#L10-L17)).
`keymap` offers get keymap, set binding, save, discard, physical layouts, and add, move, remove, restore and rename layers ([`keymap.proto` L5-L20](https://github.com/zmkfirmware/zmk-studio-messages/blob/6cb4c283e76209d59c45fbcb218800cd19e9339d/proto/zmk/keymap.proto#L5-L20)).
Notifications cover only lock-state changes and unsaved-changes status ([`studio.proto` L38-L43](https://github.com/zmkfirmware/zmk-studio-messages/blob/6cb4c283e76209d59c45fbcb218800cd19e9339d/proto/zmk/studio.proto#L38-L43)).
The protocol has no battery, active-layer or connection-status messages.
The messages repo has had no commits since 2024-10-03.

Lock and unlock:
With locking on (implied on real hardware, [`Kconfig` L39](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/Kconfig#L39)), the device starts locked ([`core.c` L11-L13](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/core.c#L11-L13)).
Secured handlers return `UNLOCK_REQUIRED` while locked ([`rpc.c` L46-L50](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/rpc.c#L46-L50)).
Only `get_device_info`, `get_lock_state` and `list_all_behaviors` work while locked ([`core_subsystem.c` L79-L81](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/core_subsystem.c#L79-L81); [`behavior_subsystem.c` L212-L213](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/behavior_subsystem.c#L212-L213)).
Every keymap call, including the read-only `get_keymap`, is secured ([`keymap_subsystem.c` L527-L538](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/keymap_subsystem.c#L527-L538)).
The only way to unlock is a `&studio_unlock` key press on the keyboard ([`behavior_studio_unlock.c` L22](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/behaviors/behavior_studio_unlock.c#L22); [`studio.md` L45](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/features/studio.md#L45)).
The device relocks after 600 seconds idle and on disconnect by default ([`Kconfig` L22-L28](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/src/studio/Kconfig#L22-L28)).

Third-party clients:
Nothing in the protocol ties it to the official app, and both the messages and the [TypeScript client](https://github.com/zmkfirmware/zmk-studio-ts-client) are MIT.
The TS client hardcodes the same service and characteristic UUIDs ([`gatt.ts` L4-L5](https://github.com/zmkfirmware/zmk-studio-ts-client/blob/main/src/transport/gatt.ts#L4-L5)).
A Swift app can generate types with `swift-protobuf` and implement the framing.

## 2. macOS side

### 2.1 CoreBluetooth access to a system-connected HID keyboard

Apple's docs for `retrieveConnectedPeripherals(withServices:)` say the list "can include those that other apps have connected", and "You need to connect these peripherals locally using the `connect(_:options:)` method before using them" ([Apple docs](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/retrieveconnectedperipherals(withservices:))).
The macOS 27.0 SDK header says the same ([`CBCentralManager.h` L156-L165](file:///Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/CoreBluetooth.framework/Headers/CBCentralManager.h), checked locally).
Apple's guidelines list the services iOS hides from third-party discovery as Generic Attribute Profile, Generic Access Profile, HID and Apple Notification Center Service ([ADG R32 Update 1, section 57.14, p. 348-349](https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf)).
Battery Service and Device Information are not on that list.
That section names iOS, and I found no Apple document that states the macOS list.
An Apple engineer wrote in 2016 that HID profiles "are directly consumed by the system" and apps "cannot interact with HID devices/services directly" ([forum thread 69814](https://developer.apple.com/forums/thread/69814)).
A DTS engineer wrote in 2026 that "As bluetoothd discovers HID services, it creates IOHIDDevice which are then 'injected' back into the kernel's HID system" ([forum thread 848602](https://developer.apple.com/forums/thread/848602)).
The local IORegistry matches that description, because the ZMK keyboard appears as an `IOHIDUserDevice` with `Transport = "Bluetooth Low Energy"`.

The strongest evidence that the pattern works on macOS for a ZMK keyboard comes from ZMK Studio.
Studio's docs list BLE support for its native apps, including macOS ([`studio.md` L23-L25](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/features/studio.md#L23-L25)).
Its Tauri backend uses the `bluest` crate, whose `discover_devices` first returns `retrieve_connected_peripherals_with_services` results ([`bluest` `adapter.rs` L142-L154, L219-L231](https://github.com/alexmoon/bluest/blob/v0.6.6/src/corebluetooth/adapter.rs#L142-L231)).
On macOS, Studio then calls `connect_device` on that system-connected keyboard and discovers its custom service ([`gatt.rs` L105-L112, L121-L158](https://github.com/zmkfirmware/zmk-studio/blob/main/src-tauri/src/transport/gatt.rs#L105-L158)).
That proves an app can open a GATT session on a ZMK keyboard that macOS holds connected.
It does not by itself prove that macOS leaves 0x180F visible, which still needs the hardware spike.

Multiple instances in CoreBluetooth:
`CBPeripheral.services` and `CBService.characteristics` are arrays of distinct objects, so duplicate UUIDs are representable.
The SDK documents that a 0x2901 descriptor value arrives as `NSString` and a 0x2904 value as `NSData` ([`CBUUID.h` L28-L50](file:///Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/CoreBluetooth.framework/Headers/CBUUID.h), checked locally).

Connection sharing:
Cancelling the app's connection does not drop the keyboard, because "other apps may still have a connection to the peripheral" ([`cancelPeripheralConnection(_:)`](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/cancelperipheralconnection(_:))).
`connect(_:options:)` never times out, so the app must manage its own retries ([docs](https://developer.apple.com/documentation/corebluetooth/cbcentralmanager/connect(_:options:))).
`setNotifyValue(true, for:)` delivers each change through `peripheral(_:didUpdateValueFor:error:)` ([docs](https://developer.apple.com/documentation/corebluetooth/cbperipheral/setnotifyvalue(_:for:))).

Identifying ZMK devices:
ZMK's Device Information PnP ID defaults to VID 0x1D50 and PID 0x615E, and the manufacturer string defaults to "ZMK Project" ([`app/Kconfig` L30-L52](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/app/Kconfig#L30-L52)).
Board authors can override these, so the app should also let the user pick a device by name.

### 2.2 How macOS itself handles multiple Battery Service instances

Apple's Accessory Design Guidelines R32 Update 1 (dated 2026-10-30) have a section titled "Bluetooth Low Energy Battery Service", marked "supported starting in iOS 26.0, iPadOS 26.0, macOS 26.0" ([ADG section 33, p. 242](https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf)).
It says a 0x2904 descriptor "is only required if there are multiple instances of Battery Service".
It lists the supported descriptors as "Main", "Left" and "Right".
It adds that "Main" means "Case" when Left and Right are both present, for headsets only.
"Auxiliary", which ZMK uses, is not in Apple's list.

Local observation on macOS 27.0.1 with a connected ZMK split named "Forager" (VID 0x1D50, PID 0x615E, `HID BLE` in `system_profiler`):

```text
$ pmset -g accps
 -Forager (id=52961414)    39%;
 -Forager (id=52961415)    86%;
```

The same two entries come back from `IOPSCopyPowerSourcesByType(4)` (read-only probe via Python `ctypes`):

```text
{'Name': 'Forager', 'Current Capacity': 39, 'Type': 'Accessory Source', 'Transport Type': 'Bluetooth LE',
 'Accessory Identifier': 'D5BA88F1-D237-E9FB-A6EB-8036F7C8D78B', 'Vendor ID': 7504, 'Product ID': 24926, ...}
{'Name': 'Forager', 'Current Capacity': 86, 'Part Identifier': 'Other', 'Type': 'Accessory Source',
 'Transport Type': 'Bluetooth LE', 'Accessory Identifier': 'D5BA88F1-D237-E9FB-A6EB-8036F7C8D78B', ...}
```

The `Accessory Identifier` equals the `PhysicalDeviceUniqueID` of the keyboard's `IOHIDUserDevice` in `ioreg`, so the battery entries can be joined to the HID device.
I infer that the untagged entry is the "main" service (central half) and the "Other" entry is the "auxiliary" service (peripheral), but I did not read the GATT table to confirm it.
`system_profiler SPBluetoothDataType` shows no battery field for this keyboard, although it shows `device_batteryLevelMain` for an Apple trackpad and Left, Right and Case for AirPods.
`ioreg` shows no `BatteryPercent` on the ZMK keyboard's HID services.
`BatteryPercent` appears only under `AppleDeviceManagementHIDEventService`, which matched only Apple's own trackpad here.

What this means for the app:

- On macOS 26 and later, the OS reads both instances for a two-part ZMK split with the proxy on, and keeps them as separate power sources.
- The public IOPowerSources API does not return them.
  `IOPSCopyPowerSourcesInfo` returned only the internal battery in the probe.
  `IOPSCopyPowerSourcesByType` is exported from IOKit ([SDK `IOKit.tbd` L515](file:///Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit.tbd)) but absent from the public headers in `IOKit.framework/Headers/ps`.
  The keys `Accessory Source`, `Accessory Identifier` and `Part Identifier` are not in the public `IOPSKeys.h` either.
- The public notify(3) key `kIOPSNotifyAnyPowerSource` exists ([`IOPowerSources.h` L175](file:///Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/IOKit.framework/Headers/ps/IOPowerSources.h)), but I did not test whether it fires for accessory changes.
- If a future ZMK build tags the halves "left" and "right" (possible with PR #3458's configurable descriptors), macOS might label them natively, but Apple scopes the Left and Right semantics to headsets.

IOBluetooth's public headers have no BLE battery API.
The only battery symbols are the HFP indicator and an SDP attribute ([`IOBluetoothHandsFreeDevice.h` L260-L265](file:///Library/Developer/CommandLineTools/SDKs/MacOSX27.0.sdk/System/Library/Frameworks/IOBluetooth.framework/Headers/objc/IOBluetoothHandsFreeDevice.h)).

### 2.3 Permissions

- `NSBluetoothAlwaysUsageDescription` "is required if your app uses the device's Bluetooth interface" (macOS 11.0+) ([Apple docs](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbluetoothalwaysusagedescription)).
  Core Bluetooth docs say the app "will crash" without the usage key ([Core Bluetooth overview](https://developer.apple.com/documentation/corebluetooth)).
  ZMK Studio's macOS build ships this key ([`Info.plist`](https://github.com/zmkfirmware/zmk-studio/blob/main/src-tauri/Info.plist)).
- `CBManager.authorization` (macOS 10.15+) reports the TCC state and starts as `notDetermined` ([Apple docs](https://developer.apple.com/documentation/corebluetooth/cbmanager/authorization-swift.type.property)).
  The first `CBCentralManager` creation triggers the system prompt.
- A sandboxed app needs `com.apple.security.device.bluetooth`, enabled under App Sandbox, Hardware, Bluetooth ([Apple docs](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.device.bluetooth)).

None of these block either a sandboxed or an unsandboxed app.
They do add one user prompt at first launch.
The private IOPowerSources path needs no Bluetooth prompt, but whether it works inside the sandbox is untested.

The keyboard's `IOHIDUserDevice` carries `RequiresTCCAuthorization = Yes` in `ioreg`.
Opening it through IOHIDManager would need Input Monitoring permission, which is a larger ask than Bluetooth.

### 2.4 USB alternatives

ZMK `main` has no USB path for battery data.
USB HID has no battery report (section 1.5), and Studio over CDC-ACM has no battery call (section 1.6).
Studio over USB serial is a future path for keymap features once the user enables the snippet.
PR #3458 would add HID battery reports per part, but nobody has tested whether macOS reads HID battery usages from a USB keyboard.

### 2.5 Gotchas

- GATT cache after reflashing.
  Zephyr indicates Service Changed for the whole database to all bonded peers when the database hash differs from the stored one at boot ([`gatt.c` L942-L972](https://github.com/zmkfirmware/zephyr/blob/v4.1.0%2Bzmk-fixes/subsys/bluetooth/host/gatt.c#L942-L972)).
  That code needs `CONFIG_BT_GATT_CACHING` (default `y`, but it depends on `PSA_CRYPTO_CLIENT`) and `CONFIG_BT_SETTINGS` ([`Kconfig.gatt` L102-L122](https://github.com/zmkfirmware/zephyr/blob/v4.1.0%2Bzmk-fixes/subsys/bluetooth/host/Kconfig.gatt#L102-L122)).
  Apple's guidelines say the host "may use the Service Changed characteristic to determine if it can rely on previously read (cached) information" ([ADG section 57.12.2, p. 347](https://developer.apple.com/accessories/Accessory-Design-Guidelines.pdf)).
  CoreBluetooth reports such changes through `peripheral(_:didModifyServices:)` ([docs](https://developer.apple.com/documentation/corebluetooth/cbperipheraldelegate/peripheral(_:didmodifyservices:))).
  If the hash path is compiled out, macOS may keep the old table and the user would need to remove and re-pair the keyboard, as ZMK's macOS troubleshooting steps already describe ([`connection-issues.mdx` L120-L126](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/troubleshooting/connection-issues.mdx#L120-L126)).
- Wake from sleep.
  ZMK docs say BAS notifications can wake macOS ([`battery.md` L27](https://github.com/zmkfirmware/zmk/blob/4dd95d7840eb3d5a3f59bb29fbf1ab054715ef85/docs/docs/config/battery.md#L27)).
  The proxy adds a second notifying characteristic, which can only add wake events.
- Power.
  Reading or subscribing to BAS uses the existing link, and ZMK only notifies when a value changes, so subscribing costs the keyboard almost nothing.
  Opening Studio does cost power, because ZMK lowers peripheral latency while a Studio client is subscribed.
- Firmware churn.
  PR #3458 reworks the layout into one service per part with configurable descriptors and an optional "Lowest Charge" main service.
  The app should discover by descriptors and never hardcode handles or ordering.

## 3. Bottom line

### Definitely possible

- Reading the central half's battery over CoreBluetooth Battery Service, given Apple's iOS filter list, Studio's working macOS GATT access, and the absence of encryption requirements on Zephyr's BAS read.
- Reading the peripheral half the same way when the user has enabled `..._FETCHING` and `..._PROXY` on the central, with notify support and descriptors (0x2904 `0x0108` and 0x2901 `"Peripheral n"`) that identify it.
- Talking ZMK Studio RPC from a third-party macOS app over BLE or USB serial, for future keymap features, after a physical unlock.

### Impossible today

- Getting the peripheral half's level from stock ZMK firmware, because the proxy defaults to off.
- Getting any battery level from a USB-connected dongle on ZMK `main`.
- Getting battery, active layer or connection status through ZMK Studio, because the protocol has no such messages.
- Reading BLE accessory battery through public IOKit or IOBluetooth APIs, since only the private `IOPSCopyPowerSourcesByType` returned it.

### Uncertain, needs a hardware spike

The "Forager" ZMK split connected to this Mac makes a good spike target.

1. Does `retrieveConnectedPeripherals(withServices: [0x180F])` return the keyboard on macOS 26 and 27, and does `discoverServices` return both Battery Service instances?
2. Can the app read the 0x2904 and 0x2901 descriptors, and does the "main" instance match the 39% entry from `IOPSCopyPowerSourcesByType`?
3. Does `setNotifyValue` work on a characteristic that `bluetoothd` already subscribed to, and do notifications arrive while the app is in the background?
4. Does the private `IOPSCopyPowerSourcesByType` work from a sandboxed, hardened-runtime app, and does `kIOPSNotifyAnyPowerSource` fire when an accessory level changes?
5. How does macOS 26 and later handle the 3+-part layout, with several Battery Level characteristics in one service sharing the "auxiliary" description?
6. How does macOS before 26 handle the auxiliary instance, both in its own UI and through CoreBluetooth?
7. After enabling the proxy and reflashing, does macOS pick up the new service through Service Changed, or does the user have to re-pair?
8. Does a dongle connected over BLE (rare) behave like the N=2 case in section 1.3?
9. If PR #3458 merges, does macOS read per-part HID battery reports from a USB dongle?

## Open questions / needs hardware spike

- Confirm Battery Service visibility, both instances, and descriptor reads via CoreBluetooth on the connected "Forager" (spike items 1 to 3).
- Decide whether to ship the private IOPowerSources path as the default reader, as a fallback, or not at all, after testing items 4 and 6.
  It avoids the Bluetooth prompt and an extra GATT client, but it is undocumented, could break in any macOS release, and rules out the Mac App Store.
- Pick a UX for the firmware prerequisite, such as detecting a keyboard that exposes only one Battery Service and linking the user to ZMK's battery config docs.
- Track ZMK [#3522](https://github.com/zmkfirmware/zmk/issues/3522) / [#3556](https://github.com/zmkfirmware/zmk/pull/3556) before telling users to enable fetching, because the bug can crash the central's radio on host disconnect.
- Track ZMK [#3458](https://github.com/zmkfirmware/zmk/pull/3458), which would change the GATT layout and add a USB path.
- Ask the user to name the halves once (slot 0 may be left or right), because ZMK assigns slots by bonding order.
- Find a primary Apple statement for macOS (not iOS) on which GATT services CoreBluetooth filters from apps; none was found in Apple docs or DTS forum answers.
