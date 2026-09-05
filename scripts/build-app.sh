#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${repo_dir}/scripts/xcode-env.sh"

if [[ "${KEYCONTROL_RELEASE_BUILD:-0}" == "1" ]]; then
    display_name="Simple Mac Keyboard Control"
    bundle_identifier="com.apotenza.KeyControl"
    if [[ "${KEYCONTROL_CHANNEL:-stable}" == "beta" ]]; then
        display_name+=" Beta"
        bundle_identifier+=".beta"
    elif [[ "${KEYCONTROL_CHANNEL:-stable}" != "stable" ]]; then
        echo "Release channel must be stable or beta." >&2
        exit 1
    fi
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
python3 "${repo_dir}/scripts/generate-icon-assets.py"
icon_name="AppIcon"
if [[ "${KEYCONTROL_RELEASE_BUILD:-0}" == "1" && "${KEYCONTROL_CHANNEL:-stable}" == "beta" ]]; then
    icon_name="AppIconBeta"
fi
python3 "${repo_dir}/scripts/verify-compiled-icons.py"
cp "${repo_dir}/Resources/CompiledIcons/${icon_name}/Assets.car" "${app_dir}/Contents/Resources/"
cp "${repo_dir}/Resources/CompiledIcons/${icon_name}/${icon_name}.icns" "${app_dir}/Contents/Resources/"
mkdir -p "${app_dir}/Contents/Frameworks"
ditto "${repo_dir}/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "${app_dir}/Contents/Frameworks/Sparkle.framework"
cp "${build_dir}/KeyControl" "${app_dir}/Contents/MacOS/KeyControl"
cp "${repo_dir}/Resources/Info.plist" "${app_dir}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $icon_name" "${app_dir}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string $icon_name" "${app_dir}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${display_name}" "${app_dir}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${display_name}" "${app_dir}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${bundle_identifier}" "${app_dir}/Contents/Info.plist"
if [[ -n "${KEYCONTROL_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${KEYCONTROL_VERSION}" "${app_dir}/Contents/Info.plist"
fi
if [[ -n "${KEYCONTROL_BUILD_NUMBER:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${KEYCONTROL_BUILD_NUMBER}" "${app_dir}/Contents/Info.plist"
fi
if [[ "${KEYCONTROL_RELEASE_BUILD:-0}" == "1" ]]; then
    arch="$(uname -m)"
    [[ "$arch" != "x86_64" ]] || arch=x64
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://raw.githubusercontent.com/apotenza92/simple-mac-keyboard-control/main/appcasts/${KEYCONTROL_CHANNEL:-stable}-${arch}.xml" "${app_dir}/Contents/Info.plist"
fi
printf 'APPL????'   > "${app_dir}/Contents/PkgInfo"

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
framework="${app_dir}/Contents/Frameworks/Sparkle.framework"
# Sign nested helpers inside out; preserve Sparkle helper entitlements.
while IFS= read -r component; do
    codesign --force --sign "$identity" --options runtime --timestamp --preserve-metadata=entitlements "$component"
done < <(find "$framework/Versions/B" -depth \( -name "*.xpc" -o -name "*.app" -o -name Autoupdate \))
codesign --force --sign "$identity" --options runtime --timestamp "$framework"
codesign "${sign_args[@]}" "${app_dir}"

echo "Built ${app_dir}"
echo "Bundle identifier ${bundle_identifier}"
echo "Signed with ${identity}"
