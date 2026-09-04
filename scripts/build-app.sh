#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_dir}/scripts/xcode-env.sh"

if [[ "${KEYCONTROL_RELEASE_BUILD:-0}" == "1" ]]; then
    display_name="Simple Mac Keyboard Control"
    bundle_identifier="com.apotenza.KeyControl"
else
    display_name="Simple Mac Keyboard Control Dev"
    bundle_identifier="com.apotenza.KeyControl.dev"
fi
app_dir="${repo_dir}/build/${display_name}.app"

swift build --package-path "${repo_dir}" -c release --product KeyControl
build_dir="$(swift build --package-path "${repo_dir}" -c release --show-bin-path)"

rm -rf "${app_dir:?}"
mkdir -p "${app_dir}/Contents/MacOS"
mkdir -p "${app_dir}/Contents/Resources"
swift "${repo_dir}/scripts/render-icon.swift" "${repo_dir}/build/AppIcon.iconset"
iconutil -c icns "${repo_dir}/build/AppIcon.iconset" -o "${app_dir}/Contents/Resources/AppIcon.icns"
cp "${build_dir}/KeyControl" "${app_dir}/Contents/MacOS/KeyControl"
cp "${repo_dir}/Resources/Info.plist" "${app_dir}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${display_name}" "${app_dir}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${display_name}" "${app_dir}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${bundle_identifier}" "${app_dir}/Contents/Info.plist"
printf 'APPL????' > "${app_dir}/Contents/PkgInfo"

identity="-"
available_identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
if [[ -n "${KEYCONTROL_SIGNING_IDENTITY:-}" ]]; then
    identity="${KEYCONTROL_SIGNING_IDENTITY}"
elif [[ "${KEYCONTROL_RELEASE_BUILD:-0}" != "1" ]] && grep -q "Apple Development" <<<"${available_identities}"; then
    identity="$(sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' <<<"${available_identities}" | head -1)"
elif [[ "${KEYCONTROL_RELEASE_BUILD:-0}" != "1" ]] && grep -q "KeyControl Dev" <<<"${available_identities}"; then
    identity="KeyControl Dev"
elif grep -q "Developer ID Application" <<<"${available_identities}"; then
    identity="$(sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' <<<"${available_identities}" | head -1)"
fi

if [[ "${KEYCONTROL_RELEASE_BUILD:-0}" == "1" && "${identity}" == "-" ]]; then
    echo "A release build requires a Developer ID or KEYCONTROL_SIGNING_IDENTITY." >&2
    exit 1
fi

sign_args=(--force --sign "${identity}")
if [[ "${identity}" != "-" ]]; then
    sign_args+=(--options runtime --timestamp --entitlements "${repo_dir}/Resources/KeyControl.entitlements")
else
    sign_args+=(--timestamp=none)
fi
codesign "${sign_args[@]}" "${app_dir}"

echo "Built ${app_dir}"
echo "Bundle identifier ${bundle_identifier}"
echo "Signed with ${identity}"
