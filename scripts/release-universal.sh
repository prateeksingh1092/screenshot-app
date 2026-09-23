#!/bin/sh
set -eu
# Universal Release. Signs with the existing Apple Development identity.
# Never installs to ~/Applications, never launches, never distributes.
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
derived=$root/.build/ReleaseDerivedData
app=$derived/Build/Products/Release/Frisket.app
label=$root/.build/release/ARM64-BUILT-AND-SIGNED-NEVER-EXECUTED.json
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH=$root/.build/clang-cache
export SWIFTPM_MODULECACHE_OVERRIDE=$root/.build/module-cache
# Compile unsigned first. Xcode's per-target codesign hung on a keychain prompt.
xcodebuild -project "$root/Frisket.xcodeproj" -scheme Frisket \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived" \
  -clonedSourcePackagesDirPath "$root/.build/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO build
/usr/bin/python3 -B "$root/Tools/Release/label.py" --sign --app "$app" --output "$label"
