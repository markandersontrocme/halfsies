# Developing Halfsies

## Building

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
The Xcode project is generated and not committed.

```sh
xcodegen generate
open Halfsies.xcodeproj
```

Or from the command line:

```sh
xcodegen generate
xcodebuild -project Halfsies.xcodeproj -scheme Halfsies -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Debug/Halfsies.app
```

### Signing

Builds are ad-hoc signed by default, so they need no Apple account.
macOS ties the Bluetooth permission to the signature, and an ad-hoc signature changes with every build, so each rebuild asks for Bluetooth access again.
To keep the permission across rebuilds, sign with a free Apple ID; see [Config/Signing.xcconfig](Config/Signing.xcconfig).

Running a development build with Launch at login turned on points the login item at that build.
Turn it off and on again in the copy you actually use.

## Testing

Nearly all logic lives in the Swift package and is tested without Xcode:

```sh
swift test --package-path HalfsiesKit
```

Tests use Swift Testing against fake transports; CoreBluetooth is never mocked.
Check the Bluetooth and UI layers by hand against a real keyboard.

## Layout

- `App/` is the thin app target: app entry point, Settings window, launch at login.
- `HalfsiesKit/` is a Swift package with nearly all the code:
  - `HalfsiesCore`: the keyboard model and pure logic, such as identifying each half from its Bluetooth descriptors.
  - `HalfsiesBLE`: reads battery levels with CoreBluetooth; the only module that imports it.
  - `HalfsiesBattery`: observable battery state, setup status, and settings.
  - `HalfsiesUI`: SwiftUI views.
- `scripts/package.sh` builds the zipped, ad-hoc signed app that CI publishes.
- `docs/design.md` records the design decisions, and `docs/research/` the research behind them.
- `docs/images/` holds the logo and the GitHub social preview; `render-social-preview.sh` regenerates the preview PNG.

## Releasing

Every pull request builds the release zip and keeps it as a workflow artifact, so you can try the exact build before releasing.

To publish a release, run the CI workflow on `main` with a new tag, from the Actions tab or with:

```sh
gh workflow run ci.yml --ref main --field tag=v0.1.0
```

Pushing a `v0.1.0` tag yourself does the same.
The tag must be three numbers, sets the app version, and is published as a GitHub prerelease.
See [docs/design.md](docs/design.md#distribution) for why releases are ad-hoc signed and not notarized.

To build the same zip locally:

```sh
scripts/package.sh 0.1.0 1
```
