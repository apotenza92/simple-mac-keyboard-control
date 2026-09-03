# KeyControl repository guide

## Product boundary

Keep KeyControl a native menu-bar utility for exactly two jobs:

- Route the volume up, volume down, and mute keys through software gain when the current macOS output has no writable volume control.
- Route brightness up and down to external DDC/CI displays.

Treat equalizers, per-app audio, device routing, custom shortcuts, display contrast, and software dimming as out of scope. Prefer a focused fix over a new setting.

## Safety invariants

- The audio path is fail-open: a stopped or failed app must restore the ordinary direct Core Audio path.
- The real-time audio callback allocates no memory, performs no file or network IO, and takes no locks.
- Native-volume outputs keep macOS behavior; KeyControl intercepts volume keys only while software gain is active.
- DDC work stays serialized and off the main thread. A missing private API or unsupported monitor disables brightness without affecting volume.

## Verification

Run `scripts/test.sh` after every code change. For audio-path changes, also complete `Tests/ManualTestPlan.md` on one fixed-volume interface and one native-volume output. For DDC changes, complete it with an external DDC display attached.

Run `scripts/e2e-smoke.sh` only with the built app open and its macOS permissions granted. It emits actual media-key events, asserts the runtime state through the app's defaults domain, and restores the original values.

Keep the development bundle identifier, signing identity, and `~/Applications/KeyControl Dev.app` path stable: macOS keys TCC permissions to that identity. `scripts/run-dev.sh` owns the rebuild-install-launch loop.

Source behavior targets macOS 14.4 or later. Private `IOAVService` symbols are isolated to `DDCController.swift` because they can change in a macOS update.
