<img src="docs/images/logo.svg" width="96" alt="Halfsies app icon">

# Halfsies

See the battery of both halves of your ZMK split keyboard in the Mac menu bar.

macOS shows only one battery level for a Bluetooth keyboard: the half your Mac connects to.
Halfsies shows both, left then right, for example `86% 39%`.

- Each side of the ring fills with that half's battery and turns red at 20% or less.
- A half that is asleep or out of range shows `-`.
- Click the ring to see both halves in more detail.

## Requirements

- A Mac with Apple silicon, running macOS 26 or later.
- A ZMK split keyboard connected over Bluetooth.
- Two lines in your keyboard's firmware (see [Firmware setting](#firmware-setting)).

## Install

1. Download the latest `Halfsies-x.y.z.zip` from [Releases](https://github.com/markandersontrocme/halfsies/releases).
2. Open the zip and drag Halfsies to your Applications folder.
3. Open Halfsies.
   macOS says it cannot verify the app, because Halfsies is not notarized by Apple.
   Click Done.
4. Open System Settings > Privacy & Security, scroll down to "Halfsies was blocked", and click Open Anyway.
5. Allow Bluetooth access when asked.

Settings opens on the first launch and tells you if anything is missing.

## Firmware setting

By default ZMK sends only the central half's battery to your Mac.
Add these lines to your keyboard's `.conf` file, rebuild, and flash the central half (usually the left one):

```ini
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_FETCHING=y
CONFIG_ZMK_SPLIT_BLE_CENTRAL_BATTERY_LEVEL_PROXY=y
```

If the second half still does not show up, remove the keyboard in System Settings > Bluetooth and pair it again.
macOS remembers the keyboard's old Bluetooth layout until you do.

Known ZMK bug: with these settings, the central half writes past the end of an array each time it disconnects from your Mac ([zmk#3522](https://github.com/zmkfirmware/zmk/issues/3522)).
On at least one board this stalled Bluetooth.
A fix is under review in [zmk#3556](https://github.com/zmkfirmware/zmk/pull/3556).

## Settings

Click the ring, then Settings, to:

- Swap left and right, if the half your Mac connects to is on the right.
- Show only the ring (Compact menu bar).
- Launch Halfsies at login.
- Pick a keyboard, if you have more than one.

## Troubleshooting

If nothing shows in the menu bar, open Halfsies again from Applications or Spotlight.
The top of its Settings window says what is wrong:

- **Waiting for Bluetooth permission**: allow Halfsies when macOS asks.
- **Not allowed to use Bluetooth**: click Open Bluetooth Settings and turn on Halfsies.
- **Bluetooth is off**: turn Bluetooth on.
- **No keyboard connected**: connect the keyboard in System Settings > Bluetooth.
- **Reports only one battery**: add the [firmware setting](#firmware-setting), then pair the keyboard again.

## Update

Download the new release, quit Halfsies, and replace the app in Applications.
Your settings are kept.
Because each release is a new download that Apple has not notarized, macOS asks you to click Open Anyway and allow Bluetooth again.

## Uninstall

Turn off Launch at login in Settings, quit Halfsies, and move it from Applications to the Trash.

## Privacy

Halfsies only reads battery levels from your keyboard over Bluetooth.
It makes no network connections, and its settings stay on your Mac.

## Feedback

Found a bug or have an idea? [Open an issue](https://github.com/markandersontrocme/halfsies/issues/new/choose).
To build Halfsies yourself or contribute, see [DEVELOPMENT.md](DEVELOPMENT.md).

## License

[MIT](LICENSE)
