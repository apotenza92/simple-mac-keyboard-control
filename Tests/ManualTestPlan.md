# Manual test plan

## Selecting checks

Use this plan as a set of targeted checks. It is not a checklist to repeat in full
for every tag. Record the source build, devices, results, and any unverified
observations. Earlier evidence remains useful when the relevant implementation
and hardware/OS assumptions are unchanged.

| Change | Verification needed |
|---|---|
| Icons, naming, website, release metadata | Asset/build/download checks; no audio or DDC hardware retest |
| Menu or HUD presentation | Inspect the affected controls/appearance; smoke-test changed key interactions |
| Gain, mute, audio buffers, tap/aggregate routing | Fixed-volume playback, held keys, mute/unmute, quit restoration, and native-output passthrough |
| Output observation, device switching, teardown | Switch fixed/native outputs and verify restoration; disconnect/reconnect when that handling changes |
| Sleep/wake handling | Real sleep/wake recovery on the affected audio/display path |
| DDC transport, discovery, display matching | Working-DDC read/write and correct physical monitor response; reconnect when discovery changes |
| Software dimming, linking, display lifecycle | Affected external/built-in isolation, linking, minimum visibility, Spaces, and shade cleanup checks |
| Updater/install/relaunch changes | Signed update installation and relaunch; verify affected runtime cleanup |
| First stable release or substantial platform rewrite | Establish a representative baseline using the applicable sections below |

Unit tests cover level math, native-channel balance, key decoding, DDC packet
validation, and linking decisions. `scripts/e2e-smoke.sh` exercises actual media
keys, HUD/runtime state, and restoration on an already permitted running app.
Neither establishes audible quality, physical brightness, cable recovery, or
sleep/wake behavior. A simulated notification is not proof of real sleep/wake.

Run physical tests for changed behavior and relevant bug reports. Do not repeat
unrelated tests merely because a version or icon changed. Keep missing evidence
explicit, and never turn an unperformed test into a recorded pass.

## Fixed-volume audio interface

1. Select the Scarlett or another fixed-volume interface as the macOS output.
2. Start KeyControl and approve System Audio Recording and Accessibility.
3. Play continuous audio at a safe hardware-knob level.
4. Press volume down, volume up, and mute; confirm the level changes and the KeyControl HUD follows each value.
5. Confirm mute empties the HUD bar, and unmute restores both the prior audible level and filled bar.
6. Hold each volume key and confirm audio remains clean without pops or stalls.
7. Quit KeyControl during playback; confirm ordinary unattenuated audio resumes immediately.
8. Relaunch it; confirm the saved volume and mute state return.

## Native-volume output

1. Switch to Mac speakers or another output with native volume.
2. Confirm the menu slider shows the current system volume and changes the native output when dragged.
3. Confirm macOS receives volume and mute keys normally; keyboard and Control Center changes promptly update the menu slider through Core Audio notifications.
4. Confirm returning to the fixed-volume output restores its saved software volume, not the native output’s level.

## Output changes and recovery

1. Switch between the fixed-volume interface and native speakers during playback.
2. Disconnect and reconnect the interface.
3. Sleep and wake the Mac.
4. Confirm KeyControl recovers within two seconds and no route remains silent after quitting.

## External display brightness

1. Enable DDC/CI in the monitor's on-screen settings.
2. Confirm KeyControl shows a brightness slider.
3. Move the slider and press brightness down/up; confirm the monitor and HUD move together.
4. With a MacBook panel active, confirm the built-in panel and external display both change.
5. If available, close the lid and confirm brightness keys still control the external display after Input Monitoring is granted.
6. Disconnect and reconnect the monitor; confirm brightness availability updates.

## HUD appearance

The dropdown uses System Menu by default; the HUD independently uses Regular glass on macOS 26+ and Classic HUD on older systems. Confirm no Glass · Dev picker appears. Compare in light and dark mode over the same wallpaper. Do not automate screenshots when the user has requested manual captures.

1. Compare volume, mute, and brightness against `docs/design-references`.
2. Confirm the HUD appears at the top-right of the controlled display without activating KeyControl.
3. Confirm the device/display name, symbols, fill, 16 markers, material, and fade animation remain legible on light and dark backgrounds.
4. Open the menu in light and dark appearance. Confirm device names and standard blue sliders with native thumbs are readable. Drag and keyboard-adjust each slider. Muting shows zero without changing speaker symbols; moving the volume slider unmutes. HUD controls remain white and notched, independent of the menu picker.

## Permissions and setup

1. On a fresh test account, confirm the setup explanation appears before permission requests. Do not reset the normal development account's permissions.
2. Relaunch an existing installation; confirm onboarding is not shown again and current access is retained.
3. Expand Permissions in the menu. Confirm Accessibility and Input Monitoring status updates after returning from System Settings.
4. Confirm each Open Settings button opens the appropriate privacy pane; grant access manually.
5. Confirm System Audio Recording reports pipeline status rather than claiming permission is granted, and native-volume outputs hide the System Audio Recording section.

## Verification record — 2026-09-04

- `scripts/test.sh`: 11 tests passed; release build, code signature, and Info.plist validation passed.
- Installed and launched with `scripts/run-dev.sh`, preserving the development identity and path.
- Attached hardware: Alex’s AirPods Pro, built-in MacBook panel, BenQ BL2785TC.
- Runtime confirms AirPods use native volume; audio pipeline code was not changed.
- BenQ DDC reads and writes of the Get VCP request return `0xe0114000` on the present connection. The app now reports brightness unavailable rather than claiming hardware control.
- Physical brightness changes, lid-close operation, and disconnect/reconnect recovery remain unverified pending a working DDC connection. Audible native-key behavior and fixed-volume playback were not manually exercised in this run.

## Software brightness fallback

1. Connect a non-Apple external display over a path without working DDC. Confirm the brightness slider starts at 100%, with no explanatory text or retry button.
2. Press brightness down/up and move the slider. Confirm external application content darkens, mouse clicks pass through, and the HUD remains readable.
3. Check another Space and a full-screen application. Confirm the shade follows the external screen and does not cover the built-in panel.
4. Hold brightness down. Confirm the minimum remains visible.
5. Disable Brightness keys, quit normally, and terminate the app. Confirm the shade disappears each time. Relaunch and confirm no residual dimming.
6. Try a direct DDC connection and toggle Brightness keys off and on. Confirm the shade disappears when DDC is detected.
7. In mixed native/DDC/software setups, confirm each menu row adjusts its named display. Ambiguous DDC identities must fall back to software without writing to another monitor.

### Software fallback and HUD verification — 2026-09-04

- Rebuilt with `scripts/test.sh`: all 11 tests, release build, signing, and plist checks passed.
- The running Dev app reports software brightness on the BenQ and native audio on AirPods.
- Real F14/F15 events changed software brightness 100 → 94 → 100. Window-server inspection found the shade on the BenQ at alpha 0.054, and the custom HUD at the BenQ's top-right. Returning to 100 removed the visible shade.
- Forced termination while dimmed removed both app windows; relaunched through `scripts/run-dev.sh`.
- Full-screen Spaces, physical key use with the lid closed, direct-DDC recovery, and multiple external screens remain manual checks.

## HUD ownership

- Native-volume outputs: only the native macOS volume HUD.
- Software-volume outputs: one KeyControl volume HUD on the main display.
- Built-in brightness: preserve native macOS adjustment and HUD.
- Controlled external brightness: a separate KeyControl HUD on each known controlled display.
- External-only setup: consume handled brightness media events to avoid macOS's unavailable-brightness indicator.
- Custom brightness HUDs use the actual adjusted display IDs and each display’s own level.

### Native volume slider verification — 2026-09-04

- `scripts/test.sh`: all 13 tests and build/signing validation passed.
- Live Core Audio/controller check on AirPods: read 38%, set 37%, verified hardware readback and controller state, then restored exact original hardware scalar values.
- Confirmed native adjustment preserves a separate saved software level and works with software volume-key handling disabled.
- Fixed-volume audio playback/recovery and an end-to-end UI drag remain manual checks; no fixed-volume output was selected for this run.

## Display rows and linking

1. Confirm every online display has a named brightness row, including the built-in panel. Unavailable displays should have disabled sliders.
2. Uncheck Link brightness. Adjust each slider; only its named display should change.
3. Check Link brightness. Adjust a slider; all controllable displays should snap to the selected percentage. Start with unequal levels and confirm checking the box itself immediately snaps followers to the main display’s percentage.
4. With linking off, point at each display and use brightness keys. Confirm only that display changes, with native HUD behavior on the built-in panel.
5. With linking on, start with unequal levels and press a brightness key. Confirm the macOS main display determines the new shared percentage, native brightness is not double-adjusted, and follower HUDs show the snapped level. Repeat with an external display set as the main display.
6. Reconnect a display and relaunch. Confirm rows refresh and the link preference persists.

### Display linking verification — 2026-09-04

- All 16 tests passed, including relative linking, independent adjustment, clamping, and missing-display handling. Release build and signing checks passed.
- Live controller check found Built-in Retina Display at 79% (native) and BenQ BL2785TC at 100% (software).
- An unlinked BenQ change to 99% left native brightness unchanged. A linked change to 98% moved native brightness down one percentage point as expected. Exact original native brightness was restored and test shades removed.
- Link preference persistence verified. Physical working-DDC, multiple-DDC identity matching, full-screen Spaces, and hotplug remain manual hardware checks.

### Main-display brightness linking — 2026-09-04

- Link brightness uses the standard checkbox size.
- All 17 tests passed, including main-display selection independent of display ordering and equal linked levels.
- Live native/software controller check verified that a follower at 100% snaps to the native master's updated value and the master receives no extra step. Linked sliders also set a shared percentage. Original native brightness restored after verification.
- Physical native key timing, external-main hardware behavior, and working DDC followers remain manual checks.

## Grouped menu controls

1. Confirm Volume keys sits above the audio slider, and Brightness keys and Link brightness sit above the display sliders.
2. Disable Volume keys. Confirm the audio name and slider are replaced by one full-size ghosted native slider, including on a native-volume output.
3. Disable Brightness keys. Confirm all display rows are replaced by one full-size ghosted native slider and Link brightness is disabled.
4. Re-enable each section and confirm its named controls return. Check both light and dark appearance.
5. Confirm Launch at login and Quit share a row and Permissions is the last section.
6. With brightness enabled and linking off, confirm “Brightness keys control the pointed-at display” appears below the checkboxes; linking on or brightness off hides the hint. Confirm the ghosted slider has the same track, thumb, symbols, width, and height as an active slider.
7. Confirm System Audio Recording is hidden for native audio and when Volume keys is off, and returns when software audio needs it.

### Launch-time brightness linking — 2026-09-04

- All 18 tests passed, including default-on linking and a saved opt-out.
- Live controller launch check: with linking enabled, the software follower matched the native main display after discovery without a key press; with linking disabled, the software follower remained at 100%.
- The initial snap runs only after detection completes, leaving the master unchanged and emitting no key HUD. Working-DDC launch behavior remains a hardware check.

## Responsiveness verification — 2026-09-04

- Replaced 250 ms native-volume polling as the primary update path with owned Core Audio main-queue property listeners for volume, mute, and default output. Stop removes the listeners and guards against late callbacks restarting control. Recovery polling is every two seconds.
- Replaced the fixed 180 ms native-master delay with a short 8 ms initial sample and 16 ms follow-up sampling during a key burst. Idle brightness polling pauses during the burst. Linked changes publish one complete display array, never an intermediate master-only array.
- Removed redundant notifications and forced defaults synchronization from controller, key, and HUD hot paths. DDC remains on its serial queue; the real-time audio callback is unchanged.
- Same live controller probe before/after on AirPods and built-in/BenQ software brightness: native volume 255.3 → 19.4 ms; linked brightness 192.1 → 14.1 ms. Divergent linked display snapshots dropped from one to zero. These are single-run hardware-change-to-model timings, not pixel-render timings or percentile guarantees. Test hardware settings were restored.
- All 18 tests and release build/signing checks passed. Native UI inspection timed out, so visible menu animation, fixed-volume playback/recovery, and working-DDC physical timing remain manual checks.
- With the menu open, compare native volume response to Control Center and press/hold brightness keys with linking enabled. Verify both slider thumbs update together, one native master step per key, and final hardware/model levels agree after release. Also verify unlink/disable/quit during a key burst and switching audio outputs.

## Fast-repeat verification — 2026-09-04

- Reproduced update starvation with 80 rapid controller key events (4 ms requested spacing) and eight native brightness changes: before the fix, zero display snapshots updated during the hold; the final level arrived only after release.
- Replaced restart-on-repeat tasks with one 60 Hz common-run-loop timer whose deadline extends with each repeat. The same probe delivered all eight changes during the hold, zero divergent linked snapshots, and matching final levels. Original native brightness was restored.
- HUD panels now retain one observable hosting view per display and share a deadline timer. A 100-update probe verified hosting-view identity stayed constant and dismissal still occurred after the burst.
- Software shades avoid repeated order-front calls. Runtime diagnostic writes coalesce over 50 ms; slider state still publishes immediately on sampled changes.
- `scripts/test.sh`: all 18 tests, release build, signing, and plist verification passed. Menu pixel smoothness and physical DDC repeat behavior remain manual checks.

## Display-paced performance review — 2026-09-04

- Reviewed the menu, HUD, key capture, controller updates, device discovery, native/DDC/software brightness, audio hardware/listeners/render callback, appearance, permissions, and launch lifecycle.
- Active linked native brightness sampling now uses the main display's CADisplayLink in common run-loop modes, rather than an independent fixed 60 Hz timer. It expires after the key burst; the idle timer also expires it if the display stops delivering frames.
- Volume and brightness have separate observed menu sections. Level updates no longer invalidate the whole menu. Permission polling and appearance observation avoid publishing unchanged values.
- Removed live defaults subscriptions from material styling (saved development styling is read at launch), reused cached display names for brightness HUDs, and coalesced HUD diagnostic writes over 50 ms.
- Live rapid-repeat probe: eight of eight native level changes published during 80 controller nudges, zero divergent linked snapshots, matching final levels. Live single-change probe: linked brightness 11.3 ms and native audio 19.1 ms from hardware change to model publication. These are individual controller measurements, not rendered-frame benchmarks or statistically significant comparisons.
- HUD probe: 100 updates retained one hosting view and dismissed after the burst. All 18 tests, release build, signing, and plist checks passed. Probes restored original native hardware values.
- Remaining limits: integer percentage steps, native brightness readback timing, independent display refresh rates, and physical DDC latency. The serial DDC transport and real-time audio callback were left unchanged. Working-DDC verification and visible menu smoothness still require physical testing; the attached dock uses software dimming. The existing e2e smoke script requires a fixed-volume audio output, so it was not run on native AirPods.

## Release-candidate runtime verification — 2026-09-05

Candidate source: `96e90ad` (0.1.0). Installed with `scripts/run-dev.sh` using the
unchanged development identity and path.

- Connected hardware: Scarlett 2i2 USB default output; AW3425DWM external display.
  Runtime reported active software gain, trusted Accessibility, active media-key
  tap, granted Input Monitoring, and hardware DDC mode.
- `scripts/e2e-smoke.sh` passed all real media-key and HUD assertions: volume
  52 → 46 → 52, mute/unmute, hardware brightness 100 → 94 → 100. Original settings
  were restored. Captures remain in ignored `build/e2e-huds/`.
- Switched to MacBook speakers, sent a native volume key, and verified native
  hardware volume and menu readback agreed. Saved software volume remained 52%.
  Restored the speakers' original volume/mute, selected the Scarlett again, and
  verified the active software pipeline recovered at 52%.
- Normal app quit wrote the stopped pipeline state and retained Scarlett as the
  default output. Relaunch restored active software gain at 52%.
- These automated checks establish routing/controller/HUD state and recovery.
  They do not establish audible quality, pops/stalls, physical brightness
  appearance, cable disconnect/reconnect, or sleep/wake behavior. Those manual
  checks remain unconfirmed; the automated evidence alone does not establish
  those observations.
