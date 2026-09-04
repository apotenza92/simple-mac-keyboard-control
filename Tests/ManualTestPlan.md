# Manual test plan

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
2. Confirm the menu reports native support.
3. Confirm macOS receives volume and mute keys normally.

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

1. Compare volume, mute, and brightness against `docs/design-references`.
2. Confirm the HUD appears at the top-right of the controlled display without activating KeyControl.
3. Confirm the device/display name, symbols, fill, 16 markers, material, and fade animation remain legible on light and dark backgrounds.
