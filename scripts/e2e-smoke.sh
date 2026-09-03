#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
domain="com.apotenza.KeyControl.dev"
app="${HOME}/Applications/KeyControl Dev.app"
sender="${repo_dir}/scripts/send-media-key.swift"
brightness_changed=0

cleanup() {
    if [[ "${brightness_changed}" == "1" ]]; then
        "${sender}" brightness-up >/dev/null 2>&1 || true
        sleep 2
    fi
}
trap cleanup EXIT

read_default() {
    defaults read "${domain}" "$1" 2>/dev/null || true
}

if ! pgrep -f "^${app}/Contents/MacOS/KeyControl$" >/dev/null; then
    open "${app}"
    sleep 3
fi

audio_state="$(read_default runtimeAudioState)"
audio_device="$(read_default runtimeAudioDevice)"
echo "audio: ${audio_state:-unknown} (${audio_device:-unknown device})"
if [[ "${audio_state}" != "active" ]]; then
    echo "FAIL: software audio pipeline is not active" >&2
    exit 1
fi

if [[ "$(read_default runtimeAccessibilityTrusted)" != "1" ]]; then
    echo "FAIL: macOS does not report KeyControl as Accessibility-trusted" >&2
    exit 1
fi
if [[ "$(read_default runtimeEventTapRunning)" != "1" ]]; then
    echo "FAIL: KeyControl could not create its media-key event tap" >&2
    exit 1
fi
echo "event tap: active and Accessibility-trusted"
if [[ "$(read_default runtimeInputMonitoringGranted)" == "1" ]]; then
    echo "input monitoring: granted (raw brightness listener=$(read_default runtimeBrightnessHIDRunning))"
fi

before_volume="$(read_default volumePercent)"
before_muted="$(read_default volumeMuted)"
if [[ -z "${before_volume}" ]]; then before_volume=50; fi
if [[ -z "${before_muted}" ]]; then before_muted=0; fi

"${sender}" volume-down
sleep 1
after_volume="$(read_default volumePercent)"
after_down_muted="$(read_default volumeMuted)"
expected_volume=$((before_volume > 5 ? before_volume - 6 : 0))
if [[ "${after_volume}" != "${expected_volume}" || "${after_down_muted}" != "0" ]]; then
    echo "FAIL: volume-down was not received (before=${before_volume}, after=${after_volume:-missing})" >&2
    echo "Grant KeyControl Accessibility, quit it, relaunch it, and rerun this script." >&2
    exit 1
fi
echo "PASS: volume-down ${before_volume}% -> ${after_volume}%"

"${sender}" mute
sleep 1
after_muted="$(read_default volumeMuted)"
if [[ "${after_muted}" != "1" ]]; then
    echo "FAIL: mute was not received (before=${before_muted}, after=${after_muted:-missing})" >&2
    exit 1
fi
echo "PASS: mute toggled 0 -> ${after_muted}"

# Restore audio state through the same key path.
"${sender}" mute
sleep 1
"${sender}" volume-up
sleep 1
if [[ "${before_muted}" == "1" ]]; then "${sender}" mute; fi

if [[ "$(read_default runtimeBrightnessAvailable)" == "1" ]]; then
    before_brightness="$(read_default brightnessPercent)"
    if [[ -z "${before_brightness}" ]]; then before_brightness=50; fi
    "${sender}" brightness-down
    brightness_changed=1
    sleep 2
    after_brightness="$(read_default brightnessPercent)"
    expected_brightness=$((before_brightness > 5 ? before_brightness - 6 : 0))
    if [[ "${after_brightness}" != "${expected_brightness}" ]]; then
        echo "FAIL: brightness-down was not applied (before=${before_brightness}, after=${after_brightness:-missing})" >&2
        exit 1
    fi
    echo "PASS: brightness-down ${before_brightness}% -> ${after_brightness}%"
    "${sender}" brightness-up
    sleep 2
    brightness_changed=0
else
    echo "SKIP: no compatible DDC display was detected"
fi

echo "E2E smoke test passed; original levels restored."
