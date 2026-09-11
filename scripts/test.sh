#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
cd "$project_dir"

if [[ -z "${SDKROOT:-}" ]]; then
  sdk_root=$(find /Library/Developer/CommandLineTools/SDKs -maxdepth 1 -type d -name 'MacOSX[0-9]*.sdk' | sort | tail -1)
  export SDKROOT="$sdk_root"
fi

export SWIFT_MODULECACHE_PATH="${TMPDIR:-/tmp}/60minus-swift-cache"
export CLANG_MODULE_CACHE_PATH="${TMPDIR:-/tmp}/60minus-clang-cache"

arguments=(
  --disable-sandbox
  --cache-path "${TMPDIR:-/tmp}/60minus-spm-cache"
  --config-path "${TMPDIR:-/tmp}/60minus-spm-config"
)

# Some Command Line Tools distributions keep Testing's macro plugin in a
# nested directory that SwiftPM does not discover automatically.
testing_plugin=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
if [[ -f "$testing_plugin" ]]; then
  arguments+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_plugin")
fi

swift test "${arguments[@]}"
