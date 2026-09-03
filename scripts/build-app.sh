#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="${repo_dir}/build/KeyControl.app"
source "${repo_dir}/scripts/xcode-env.sh"

swift build --package-path "${repo_dir}" -c release --product KeyControl
build_dir="$(swift build --package-path "${repo_dir}" -c release --show-bin-path)"

rm -rf "${app_dir:?}"
mkdir -p "${app_dir}/Contents/MacOS"
cp "${build_dir}/KeyControl" "${app_dir}/Contents/MacOS/KeyControl"
cp "${repo_dir}/Resources/Info.plist" "${app_dir}/Contents/Info.plist"
printf 'APPL????' > "${app_dir}/Contents/PkgInfo"

identity="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -q "Developer ID Application"; then
    identity="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
fi

sign_args=(--force --sign "${identity}")
if [[ "${identity}" != "-" ]]; then
    sign_args+=(--options runtime --timestamp --entitlements "${repo_dir}/Resources/KeyControl.entitlements")
else
    sign_args+=(--timestamp=none)
fi
codesign "${sign_args[@]}" "${app_dir}"

echo "Built ${app_dir}"
