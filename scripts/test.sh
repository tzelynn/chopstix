#!/bin/bash
# Runs the unit tests. With only the Command Line Tools installed (no Xcode), swift-testing
# lives outside the default search paths, so point the compiler and linker at it.
set -euo pipefail
cd "$(dirname "$0")/.."

CLT=/Library/Developer/CommandLineTools/Library/Developer
if ! xcodebuild -version >/dev/null 2>&1 && [ -d "$CLT/Frameworks/Testing.framework" ]; then
    exec swift test \
        -Xswiftc -F"$CLT/Frameworks" \
        -Xlinker -F"$CLT/Frameworks" \
        -Xlinker -rpath -Xlinker "$CLT/Frameworks" \
        -Xlinker -rpath -Xlinker "$CLT/usr/lib" \
        "$@"
fi
exec swift test "$@"
