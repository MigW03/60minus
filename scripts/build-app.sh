#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
cd "$project_dir"

# The newest installed SDK is the safest match for the active Command Line
# Tools compiler. SDKROOT can still be supplied explicitly when needed.
if [[ -z "${SDKROOT:-}" ]]; then
  sdk_root=$(find /Library/Developer/CommandLineTools/SDKs -maxdepth 1 -type d -name 'MacOSX[0-9]*.sdk' | sort | tail -1)
  export SDKROOT="$sdk_root"
fi

export SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/60minus-swift-cache"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/60minus-clang-cache"

swift build -c release \
  --disable-sandbox \
  --build-system native \
  -debug-info-format none \
  --cache-path "${TMPDIR:-/tmp}/60minus-spm-cache" \
  --config-path "${TMPDIR:-/tmp}/60minus-spm-config" \
  --security-path "${TMPDIR:-/tmp}/60minus-spm-security"

app_dir="$project_dir/build/60Minus.app"
contents_dir="$app_dir/Contents"
executable_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

rm -rf "$app_dir"
mkdir -p "$executable_dir" "$resources_dir"
cp "$project_dir/.build/release/SixtyMinus" "$executable_dir/SixtyMinus"
cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
codesign --force --sign - "$app_dir"

echo "$app_dir"
