#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
domain="com.apotenza.KeyControl.dev"
app="${HOME}/Applications/KeyControl Dev.app"
sender="${repo_dir}/scripts/send-media-key.swift"
capture_dir="${repo_dir}/build/e2e-huds"

restore_step() {
    local key="$1" before="$2" up="$3" down="$4" current
    current="$(read_default "$key")"
    [[ "$before" =~ ^[0-9]+$ && "$current" =~ ^[0-9]+$ ]] || return 0
    if (( current == before - 6 )); then
        "$sender" "$up" >/dev/null 2>&1 || true
        sleep 1
    elif (( current == before + 6 )); then
        "$sender" "$down" >/dev/null 2>&1 || true
        sleep 1
    elif (( current != before )); then
        echo "Restoration needs attention: $key changed unexpectedly ($before -> $current)." >&2
    fi
}

cleanup() {
    # Read actual state, including when a key worked but a later HUD assertion failed.
    restore_step brightnessPercent "${before_brightness:-}" f15 f14
    restore_step volumePercent "${before_volume:-}" volume-up volume-down
    local current_muted
    current_muted="$(read_default volumeMuted)"
    if [[ "${before_muted:-}" =~ ^[01]$ && "$current_muted" =~ ^[01]$ && "$current_muted" != "$before_muted" ]]; then
        "$sender" mute >/dev/null 2>&1 || true
        sleep 1
    fi
}
trap cleanup EXIT

read_default() {
    defaults read "${domain}" "$1" 2>/dev/null || true
}

send_and_assert_hud() {
    local key="$1"
    local expected_kind="$2"
    local expected_percent="$3"
    local expected_name="$4"
    local capture_name="$5"
    local before_count
    before_count="$(read_default runtimeHUDCount)"
    if [[ -z "${before_count}" ]]; then before_count=0; fi

    "${sender}" "${key}"
    for _ in {1..20}; do
        if [[ "$(read_default runtimeHUDCount)" -gt "${before_count}" ]] \
            && [[ "$(read_default runtimeHUDKind)" == "${expected_kind}" ]] \
            && [[ "$(read_default runtimeHUDPercent)" == "${expected_percent}" ]] \
            && [[ "$(read_default runtimeHUDVisible)" == "1" ]]; then
            break
        fi
        sleep 0.05
    done

    local actual_name
    actual_name="$(read_default runtimeHUDName)"
    if [[ "$(read_default runtimeHUDCount)" -le "${before_count}" ]] \
        || [[ "$(read_default runtimeHUDKind)" != "${expected_kind}" ]] \
        || [[ "$(read_default runtimeHUDPercent)" != "${expected_percent}" ]] \
        || [[ "$(read_default runtimeHUDVisible)" != "1" ]] \
        || { [[ "${expected_name}" != "*" ]] && [[ "${actual_name}" != "${expected_name}" ]]; }; then
        echo "FAIL: ${key} HUD mismatch (kind=$(read_default runtimeHUDKind), percent=$(read_default runtimeHUDPercent), name=${actual_name:-missing}, visible=$(read_default runtimeHUDVisible))" >&2
        exit 1
    fi

    mkdir -p "${capture_dir}"
    screencapture -x -D 1 "${capture_dir}/${capture_name}.png"
    echo "PASS: ${key} HUD (${expected_kind}, ${expected_percent}%, ${actual_name})"
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

if (( before_volume < 6 )) || [[ "$before_muted" != "0" ]]; then
    echo "Start this smoke test unmuted with volume at least 6%; no test keys were sent." >&2
    exit 1
fi
expected_volume=$((before_volume - 6))
send_and_assert_hud volume-down volume "${expected_volume}" "${audio_device}" volume-down
sleep 1
after_volume="$(read_default volumePercent)"
after_down_muted="$(read_default volumeMuted)"
if [[ "${after_volume}" != "${expected_volume}" || "${after_down_muted}" != "0" ]]; then
    echo "FAIL: volume-down was not received (before=${before_volume}, after=${after_volume:-missing})" >&2
    echo "Grant KeyControl Accessibility, quit it, relaunch it, and rerun this script." >&2
    exit 1
fi
echo "PASS: volume-down ${before_volume}% -> ${after_volume}%"

send_and_assert_hud volume-up volume "${before_volume}" "${audio_device}" volume-up
sleep 1
after_volume_up="$(read_default volumePercent)"
if [[ "${after_volume_up}" != "${before_volume}" ]]; then
    echo "FAIL: volume-up did not restore level (expected=${before_volume}, after=${after_volume_up:-missing})" >&2
    exit 1
fi
echo "PASS: volume-up ${after_volume}% -> ${after_volume_up}%"

send_and_assert_hud mute muted "${before_volume}" "${audio_device}" mute
sleep 1
after_muted="$(read_default volumeMuted)"
if [[ "${after_muted}" != "1" ]]; then
    echo "FAIL: mute was not received (before=${before_muted}, after=${after_muted:-missing})" >&2
    exit 1
fi
echo "PASS: mute toggled 0 -> ${after_muted}"

send_and_assert_hud mute volume "${before_volume}" "${audio_device}" unmute
sleep 1
after_unmuted="$(read_default volumeMuted)"
if [[ "${after_unmuted}" != "0" ]]; then
    echo "FAIL: second mute key did not unmute" >&2
    exit 1
fi
echo "PASS: mute toggled 1 -> ${after_unmuted}"

if [[ "${before_muted}" == "1" ]]; then
    "${sender}" mute
    sleep 1
fi

if [[ "$(read_default runtimeBrightnessAvailable)" == "1" ]]; then
    before_brightness="$(read_default brightnessPercent)"
    if [[ -z "${before_brightness}" ]]; then before_brightness=50; fi
    if (( before_brightness < 6 )); then
        echo "Brightness smoke requires a starting level of at least 6%; no brightness keys were sent." >&2
        exit 1
    fi
    expected_brightness=$((before_brightness - 6))
    send_and_assert_hud f14 brightness "${expected_brightness}" "*" brightness-down
    sleep 2
    after_brightness="$(read_default brightnessPercent)"
    if [[ "${after_brightness}" != "${expected_brightness}" ]]; then
        echo "FAIL: brightness-down was not applied (before=${before_brightness}, after=${after_brightness:-missing})" >&2
        exit 1
    fi
    echo "PASS: brightness-down ${before_brightness}% -> ${after_brightness}%"
    send_and_assert_hud f15 brightness "${before_brightness}" "*" brightness-up
    sleep 2
    if [[ "$(read_default brightnessPercent)" != "${before_brightness}" ]]; then
        echo "FAIL: brightness-up did not restore level" >&2
        exit 1
    fi
    echo "PASS: brightness-up ${after_brightness}% -> ${before_brightness}%"
else
    echo "SKIP: no compatible DDC display was detected"
fi

echo "E2E smoke test passed; all key paths, HUD states, and restoration verified."
echo "HUD captures: ${capture_dir}"
