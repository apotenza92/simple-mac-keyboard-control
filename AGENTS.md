# KeyControl repository guide

## Product boundary

Keep KeyControl a native menu-bar utility for exactly two jobs:

- Route the volume up, volume down, and mute keys through software gain when the current macOS output has no writable volume control.
- Route brightness up and down to external DDC/CI displays, with software dimming as a fallback when DDC is unavailable.

Treat equalizers, per-app audio, device routing, custom shortcuts, and display contrast as out of scope. Prefer a focused fix over a new setting.

## Safety invariants

- The audio path is fail-open: a stopped or failed app must restore the ordinary direct Core Audio path.
- The real-time audio callback allocates no memory, performs no file or network IO, and takes no locks.
- Native-volume outputs keep macOS behavior; KeyControl intercepts volume keys only while software gain is active.
- Software dimming must leave built-in displays alone, keep a visible minimum, and disappear when the app stops or fails.
- DDC work stays serialized and off the main thread. A missing private API or unsupported monitor disables brightness without affecting volume.

## Verification

Run `scripts/test.sh` after application or build-code changes. Run the relevant release, download, or workflow checks for distribution changes. Documentation-only edits do not require rebuilding the app.

Choose hardware verification from the behavior changed, using the coverage matrix in `Tests/ManualTestPlan.md`. Audio processing/routing changes need fixed-volume playback and native-output passthrough checks; DDC transport/discovery changes need a working DDC display. Test disconnect/reconnect or sleep/wake when their handling changes or a regression involves them. UI changes need the affected UI checks, not the entire hardware plan. Branding, website, and release-metadata changes do not require unrelated hardware retests.

Establish a hardware baseline for the first stable release, and broaden it after substantial audio/display rewrites or relevant macOS/driver compatibility changes. Reuse recorded evidence for unchanged behavior; record the tested build, hardware, result, and remaining gaps. Do not describe controller-state assertions as audible or physical verification. A known regression in an affected safety invariant blocks release until resolved. Missing human observations must be reported accurately; do not fabricate passes or add a blanket per-commit hardware approval gate.

Run `scripts/e2e-smoke.sh` only with the built app open and its macOS permissions granted. It emits actual media-key events, asserts the runtime state through the app's defaults domain, and restores the original values.

Keep the development bundle identifier, signing identity, and `~/Applications/KeyControl Dev.app` path stable: macOS keys TCC permissions to that identity. `scripts/run-dev.sh` owns the rebuild-install-launch loop.

Source behavior targets macOS 14.4 or later. Private `IOAVService` symbols are isolated to `DDCController.swift` because they can change in a macOS update.
