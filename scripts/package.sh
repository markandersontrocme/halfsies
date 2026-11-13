#!/bin/bash
# Builds the Release app from the committed source, signs it ad-hoc, checks it, and zips it.
# CI runs this on every pull request, and on a version tag to produce the GitHub release.
#
# Usage: scripts/package.sh <version> <build-number>
#
# Writes to build/package/:
#   Halfsies-<version>.zip  the app, zipped with ditto
#   release-notes.md        the notes for the GitHub release
set -euo pipefail

usage() {
  echo "usage: $0 <version> <build-number>, for example: $0 0.2.0 14" >&2
  exit 64
}

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ $# -eq 2 ]] || usage
version=$1
build=$2
# CFBundleShortVersionString must be three period-separated integers, and CFBundleVersion an integer.
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like 1.2.3, got '$version'"
[[ $build =~ ^[0-9]+$ ]] || fail "build number must be an integer, got '$build'"

root=$(git rev-parse --show-toplevel)
out="$root/build/package"
source="$out/source"
app="$out/DerivedData/Build/Products/Release/Halfsies.app"
zip="$out/Halfsies-$version.zip"

rm -rf "$out"
mkdir -p "$source"

# Build from the committed files only.
# Gitignored files, in particular a developer's Config/Local.xcconfig signing override, never reach the build.
commit=$(git -C "$root" rev-parse HEAD)
if [[ -n $(git -C "$root" status --porcelain) ]]; then
  echo "warning: uncommitted changes are not included; building $commit" >&2
fi
git -C "$root" archive "$commit" | tar -x -C "$source"
[[ ! -e "$source/Config/Local.xcconfig" ]] || fail "Config/Local.xcconfig is committed; it must stay local"

echo "==> Building Halfsies $version ($build) from $commit"
(cd "$source" && xcodegen generate --quiet)
# Without a destination, xcodebuild builds only the host Mac's architecture.
# Build for Apple silicon on any host: nobody can test an Intel build yet.
xcodebuild -quiet \
  -project "$source/Halfsies.xcodeproj" \
  -scheme Halfsies \
  -configuration Release \
  -destination generic/platform=macOS \
  -derivedDataPath "$out/DerivedData" \
  ARCHS=arm64 \
  MARKETING_VERSION="$version" \
  CURRENT_PROJECT_VERSION="$build" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  build

# Checks the app at $1: a strict signature check, an ad-hoc signature with the hardened runtime, and the version.
check_app() {
  local app=$1 info signature
  codesign --verify --strict --verbose=2 "$app"
  signature=$(codesign --display --verbose=2 "$app" 2>&1)
  grep -q '^Signature=adhoc$' <<<"$signature" || fail "$app is not ad-hoc signed"
  grep -q '^TeamIdentifier=not set$' <<<"$signature" || fail "$app is signed with a team"
  grep -Eq '^CodeDirectory .*flags=.*runtime' <<<"$signature" || fail "$app does not use the hardened runtime"
  info="$app/Contents/Info.plist"
  [[ $(plutil -extract CFBundleShortVersionString raw "$info") == "$version" ]] || fail "$app has the wrong version"
  [[ $(plutil -extract CFBundleVersion raw "$info") == "$build" ]] || fail "$app has the wrong build number"
}

echo "==> Checking the app"
check_app "$app"
archs=$(lipo -archs "$app/Contents/MacOS/Halfsies")
min_macos=$(plutil -extract LSMinimumSystemVersion raw "$app/Contents/Info.plist")
min_macos=${min_macos%.0}
echo "architectures: $archs"
# The release notes say the build is Apple silicon only.
[[ $archs == arm64 ]] || fail "expected an arm64-only app, got: $archs; update the release notes"
echo "minimum macOS: $min_macos"

echo "==> Zipping"
ditto -c -k --keepParent "$app" "$zip"
# Unpack the zip again and check that the app survived the round trip.
ditto -x -k "$zip" "$out/unzipped"
check_app "$out/unzipped/Halfsies.app"

cat >"$out/release-notes.md" <<EOF
Beta build of Halfsies $version.

- **Not notarized.**
  The app is ad-hoc signed, so macOS blocks it the first time you open it and again after each update.
  Follow the [install steps](https://github.com/markandersontrocme/halfsies/blob/main/README.md#install) to open it anyway.
- Requires macOS $min_macos or later.
- Apple silicon only; there is no Intel build.
EOF

echo "==> Wrote $zip"
shasum -a 256 "$zip"
