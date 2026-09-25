#!/bin/sh
# Compiles the live-harness tools into .build/live-harness/. Compiling never runs them.
# scripts/ci.sh calls this so the harness can't silently rot.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
out="$root/.build/live-harness"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
mkdir -p "$out" "$root/.build/module-cache"
target="$(uname -m)-apple-macos26.0"
# The tools are small single-file programs with global state, so they use Swift 5 mode.
compile() {
  name=$1; shift
  xcrun swiftc -swift-version 5 -O -target "$target" -module-cache-path "$root/.build/module-cache" \
    "$@" -o "$out/$name"
}
compile pattern -parse-as-library "$root/Tools/FrisketTestPattern.swift"
compile drive -parse-as-library "$root/Tools/LiveHarness/drive.swift"
compile meter "$root/Tools/LiveHarness/meter.swift"
compile sckwins -parse-as-library "$root/Tools/LiveHarness/sckwins.swift"
compile sheet "$root/Tools/LiveHarness/sheet.swift"
echo "live harness: built pattern drive meter sckwins sheet in $out"
