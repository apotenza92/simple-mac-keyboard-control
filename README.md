# KeyControl

KeyControl is a tiny native macOS menu-bar app that makes the keyboard volume, mute, and brightness keys work with hardware macOS cannot normally control.

It has two jobs:

- Add software volume and mute to fixed-volume audio outputs such as Focusrite Scarlett interfaces and USB DACs.
- Send brightness changes to external monitors over DDC/CI.

There is no Dock icon, equalizer, per-app mixer, device router, or shortcut editor.

## Requirements

- macOS 14.4 or later
- Apple silicon for external-monitor DDC brightness in the first release
- A monitor with DDC/CI enabled for brightness control

## Build and run

```sh
scripts/run-dev.sh
```

Local builds are named `KeyControl Dev.app`, use the development-only bundle identifier `com.apotenza.KeyControl.dev`, and run from the stable `~/Applications` path. Release builds remain `KeyControl.app`. Move a release app to `/Applications` before enabling **Launch at login**.

Local builds automatically use an installed Apple Development certificate. Together with `scripts/run-dev.sh`, this gives the app a stable code identity and path so macOS permissions survive rebuilds. Set `KEYCONTROL_RELEASE_BUILD=1` for the release identity and `KEYCONTROL_SIGNING_IDENTITY` only when a release build needs a specific certificate.

On first run, macOS asks for:

- **System Audio Recording** so KeyControl can apply software gain. Audio stays on the Mac and is never recorded or stored.
- **Accessibility** so KeyControl can consume volume up, volume down, and mute while software gain is active.
- **Input Monitoring** only when raw brightness keys are needed in a closed-lid/external-display setup.

## How volume works

Modern macOS exposes Core Audio process taps. KeyControl creates a private, in-process tap as a software volume stage: it captures system output, mutes the direct copy, applies gain, and renders to the currently selected physical output. No audio driver, kernel extension, privileged helper, or administrator password is required.

The tap is private and fail-open. If KeyControl exits or its audio path cannot start, Core Audio removes the tap and apps return to their normal direct output. Outputs that already expose native volume are left to macOS.

## Brightness compatibility

Brightness uses the monitor's DDC/CI luminance control. Support depends on the display, cable, adapter, and Mac port. DisplayPort and USB-C paths are generally more reliable than HDMI. Apple displays and built-in panels keep their native macOS behavior.

## Verify changes

```sh
scripts/test.sh
```

With KeyControl running and permissions granted, exercise real media-key events against the selected audio interface and DDC display:

```sh
scripts/e2e-smoke.sh
```

The smoke test verifies the live pipeline, volume-down, mute, and brightness-down paths, then restores the original levels.

Hardware behavior is covered by [the manual test plan](Tests/ManualTestPlan.md).

## Status

This is an early private prototype. `KeyControl` is a working name and can be changed before a public release.
