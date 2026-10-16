#!/bin/bash
# Runs the test suite. With only the Xcode Command Line Tools (no Xcode), Swift Testing lives
# outside the default search paths, so point the compiler and linker at it.
set -euo pipefail
cd "$(dirname "$0")/.."

args=()
if [[ "$(xcode-select -p 2>/dev/null)" == *CommandLineTools* ]]; then
  fw=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
  lib=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
  args=(-Xswiftc -F"$fw" -Xlinker -F"$fw" -Xlinker -rpath -Xlinker "$fw" -Xlinker -rpath -Xlinker "$lib")
fi
swift test "${args[@]+"${args[@]}"}" "$@"
