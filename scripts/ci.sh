#!/bin/sh
# Local CI (decision 57, DA-7): exits non-zero when the tree must not merge.
#
#   scripts/ci.sh            repository checks, package tests, unsigned app build, harness compile
#   scripts/ci.sh --defects  run the known-defect tests unwrapped and list the red ones
#
# The pre-push hook in .githooks runs the first form.
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$root"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$root/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$root/.build/module-cache"

# Known-defect test functions are named after their defect: d1…, d22… (decision 58).
defect_tests='[./]d[0-9]+[A-Z]'

if [ "${1:-}" = "--defects" ]; then
  log=$(mktemp -t frisket-defects)
  FRISKET_SHOW_DEFECTS=1 "$root/scripts/test-core.sh" --filter "$defect_tests" >"$log" 2>&1 || true
  if ! grep -q "Test run with" "$log"; then
    cat "$log" >&2
    echo "ci: the defect run did not complete; log: $log" >&2
    exit 1
  fi
  echo "Known defects still red:"
  grep -E '^✘ Test d[0-9]+[A-Za-z]+.*(failed|recorded an issue)' "$log" \
    | sed -E 's/^✘ Test (d[0-9]+[A-Za-z0-9_]*).*/\1/' | sort -u | sed 's/^/  /'
  echo "Known-defect tests now green (their wrapper must go):"
  grep -E '^✔ Test d[0-9]+[A-Za-z]' "$log" | sed -E 's/^✔ Test (d[0-9]+[A-Za-z0-9_]*).*/\1/' | sort -u | sed 's/^/  /'
  echo "Full log: $log"
  exit 0
fi

echo "== repository checks (Checks/check_repository.py: six invariants, core imports, app sources)"
/usr/bin/python3 -B Checks/check_repository.py --self-test || { echo "ci: a repository-check fixture failed" >&2; exit 1; }
/usr/bin/python3 -B Checks/check_repository.py --root "$root" || { echo "ci: a repository check failed" >&2; exit 1; }

echo "== drift (retired terms, Checks/retired-terms.tsv)"
/usr/bin/python3 -B Checks/check_drift.py --self-test >/dev/null
/usr/bin/python3 -B Checks/check_drift.py --root "$root" || { echo "ci: a retired term is back in a live file" >&2; exit 1; }

echo "== package tests"
"$root/scripts/test-core.sh"

echo "== unsigned app build"
xcodebuild -quiet -project Frisket.xcodeproj -scheme Frisket \
  -configuration Development -destination "platform=macOS,arch=$(uname -m)" \
  -derivedDataPath "$root/.build/DerivedData" \
  -clonedSourcePackagesDirPath "$root/.build/SourcePackages" \
  -onlyUsePackageVersionsFromResolvedFile -disableAutomaticPackageResolution \
  CODE_SIGNING_ALLOWED=NO build

echo "== live harness (compile only)"
"$root/Tools/LiveHarness/build.sh"

echo "ci: green"
