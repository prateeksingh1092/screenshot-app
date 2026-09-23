#!/bin/bash
# The reference clone is input only. Execution is a coordinator action requiring network approval.
set -euo pipefail
cd "$(dirname "$0")/../.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
reference=/Users/16intelmac/Documents/Claude/Projects/screenshot-app/.scratch/evaluation/Snapzy
scratch="$PWD/.build/snapzy-baseline"
revision=837fc73d9b55dfde203e9d14aeb8c8fae4f0add7
if [[ "${1:---plan}" != --coordinator-build ]]; then
  [[ "${1:---plan}" == --plan ]] || { echo 'Use --plan or --coordinator-build' >&2; exit 2; }
  cat <<'PLAN'
PENDING COORDINATOR: package resolution requires network; no build performed.
Exact command from this worktree:
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer bash Tools/Performance/build-snapzy.sh --coordinator-build
This archives the pinned reference into .build/snapzy-baseline/source, resolves its
locked packages, and builds unsigned Release for the host architecture. It never
signs, installs, launches, or changes the reference clone. Do not execute before
network approval. An approved signing route may still be needed to launch; unsigned
results are not the signed-release baseline described by decision 22.
PLAN
  exit 0
fi
[[ ! -e "$scratch" ]] || { echo 'Scratch already exists; use a fresh worktree or inspect it manually.' >&2; exit 1; }
[[ "$(git -C "$reference" rev-parse HEAD)" == "$revision" ]] || { echo 'Reference revision changed.' >&2; exit 1; }
mkdir -p "$scratch/source" "$scratch/packages" "$scratch/package-cache"
git -C "$reference" archive "$revision" > "$scratch/source.tar"
tar -xf "$scratch/source.tar" -C "$scratch/source"
printf '%s\n' "$revision" > "$scratch/revision.txt"
# Disable credential-helper invocation; public pinned dependencies need no credentials.
export GIT_TERMINAL_PROMPT=0
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=credential.helper
export GIT_CONFIG_VALUE_0=''
common=(-project "$scratch/source/Snapzy.xcodeproj" -scheme Snapzy
  -clonedSourcePackagesDirPath "$scratch/packages" -packageCachePath "$scratch/package-cache"
  -derivedDataPath "$scratch/DerivedData" -scmProvider system
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 'CODE_SIGN_IDENTITY='
  CLANG_MODULE_CACHE_PATH="$CLANG_MODULE_CACHE_PATH"
  SWIFT_MODULE_CACHE_PATH="$SWIFTPM_MODULECACHE_OVERRIDE")
xcrun xcodebuild "${common[@]}" -resolvePackageDependencies -onlyUsePackageVersionsFromResolvedFile
xcrun xcodebuild "${common[@]}" -configuration Release -destination 'platform=macOS' \
  "ARCHS=$(uname -m)" ONLY_ACTIVE_ARCH=YES -disableAutomaticPackageResolution \
  -onlyUsePackageVersionsFromResolvedFile -skipPackageUpdates build
printf 'Unsigned build: %s\n' "$scratch/DerivedData/Build/Products/Release/Snapzy.app"
