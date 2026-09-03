#!/usr/bin/env bash

if ! xcrun xcodebuild -version >/dev/null 2>&1; then
    xcode_app="$(find /Applications -maxdepth 1 -type d -name 'Xcode*.app' -print -quit)"
    if [[ -z "${xcode_app}" ]]; then
        echo "KeyControl requires Xcode, but no Xcode app was found in /Applications." >&2
        exit 1
    fi
    export DEVELOPER_DIR="${xcode_app}/Contents/Developer"
fi
