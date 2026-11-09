# 05 - CoreBluetooth spike results

A throwaway app (not committed) tested on 2026-11-09 whether a regular macOS app can read both halves' battery from a ZMK split that macOS has already connected.
It answers spike items 1 to 3 from [01-zmk-and-macos-ble.md](01-zmk-and-macos-ble.md).

## Setup

- Mac: macOS 27.0.1, Xcode 27.2, Swift 6.4.2.
- Keyboard: "Forager", a ZMK split with battery fetching and proxy enabled, already paired and connected to macOS.
- App: an unsandboxed, ad-hoc signed `.app` bundle with `NSBluetoothAlwaysUsageDescription` and `LSUIElement`.
  A bare command-line tool was not used, because macOS attributes Bluetooth permission to the responsible app and requires the usage description.

## Results

- The first launch triggered the Bluetooth permission prompt (`AUTHREQ_PROMPTING ... kTCCServiceBluetoothAlways` in the `tccd` log).
  Until the user answered, `centralManagerDidUpdateState` was never called, so an app must not treat "no state yet" as an error.
- `retrieveConnectedPeripherals(withServices: [0x180F])` returned Forager.
  Filtering by HID (0x1812) returned nothing, which matches CoreBluetooth hiding the HID service from apps.
  Filtering by Device Information (0x180A) also returned Forager.
- `connect` on the system-connected peripheral succeeded immediately, and `discoverServices(nil)` returned `180F`, `180F`, `180A`, and the ZMK Studio service `00000000-0196-6107-C967-C5CFB1C2482A`.
- Both Battery Level characteristics have properties `0x12` (read and notify).
- Descriptors read back as follows.

| Value | 0x2904 Presentation Format | 0x2901 User Description | Role |
| --- | --- | --- | --- |
| 86% | `04 00 ad 27 01 06 01` (uint8, percentage, SIG namespace, description `0x0106` "main") | none | central |
| 39% | `04 00 ad 27 01 08 01` (description `0x0108` "auxiliary") | `Peripheral 0` | peripheral 0 |

- `setNotifyValue(true)` succeeded on both characteristics, even though macOS itself already reads them.
  The Client Characteristic Configuration descriptor read back as 1 on both.
- No notification arrived during a 10-minute run, because neither level changed.
  ZMK only notifies on change, so notification delivery is still unconfirmed; the app re-reads every 60 seconds regardless.
- `pmset -g accps` listed the two Forager entries as 39% then 86%, the opposite of the GATT discovery order.
  This confirms that halves must be identified by descriptors, not by order.

## Confirmed in the real app

The first Halfsies build, using the same approach, published `central 86%` and `peripheral(0) 39%` for Forager within half a second of launch.

## Still open

- Notification delivery on an actual level change.
- Behavior across keyboard sleep and wake, and after the Mac sleeps.
- Spike items 4 to 9 in [01-zmk-and-macos-ble.md](01-zmk-and-macos-ble.md), several of which no longer matter because the private IOKit path is not used.
