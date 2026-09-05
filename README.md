# Simple Mac Keyboard Control

<img src="docs/assets/icon.png" alt="Simple Mac Keyboard Control icon" width="96" />

**Volume and brightness. Back on your keyboard.**

[Choose stable or beta](https://apotenza92.github.io/simple-mac-keyboard-control/) · [Releases](https://github.com/apotenza92/simple-mac-keyboard-control/releases)

**Pre-release:** public downloads are not available yet. The download page and release channels are being prepared.

A free, open source Mac utility from the maker of [Macsimize](https://apotenza92.github.io/macsimize/) and [Dockmint](https://apotenza92.github.io/dockmint/).

Simple Mac Keyboard Control is a tiny native macOS menu-bar app for keyboard volume, mute, and brightness on hardware macOS cannot normally control.

It has two jobs:

- Add software volume and mute to fixed-volume audio outputs such as Focusrite Scarlett interfaces and USB DACs.
- Send brightness changes to external monitors over DDC/CI, with software dimming when DDC is unavailable.

There is no Dock icon, equalizer, per-app mixer, device router, or shortcut editor.

Every handled key displays a compact SwiftUI HUD based on the current macOS
volume and brightness overlays. macOS 26 and newer use Liquid Glass; older
supported releases use the same layout with an ultra-thin material.

## Requirements

- macOS 14.4 or later
- Apple silicon for external-monitor DDC brightness in the first release
- A monitor with DDC/CI enabled for hardware brightness control (otherwise software dimming is available)

## Stable and beta

Stable is for everyday use. Beta receives preview builds and newer stable releases. It has a separate purple icon, app name, preferences, and permission identity. Both can be installed; quit one before running the other. Downloads are architecture-specific. Release builds use Sparkle for automatic update checks and offer **Check for Updates…** in the menu. Downloaded updates must pass the app’s dedicated Ed25519 signature verification. Development builds do not update.

See [the release guide](docs/RELEASING.md) for packaging and launch requirements.

## Build and run

```sh
scripts/run-dev.sh
```

Builds are named `Simple Mac Keyboard Control Dev.app` or `Simple Mac Keyboard Control.app` for release. The development installer deliberately retains `~/Applications/KeyControl Dev.app` and the bundle identifier `com.apotenza.KeyControl.dev` so existing permissions survive the rename. The displayed development name ends in **Dev**. Move a release app to `/Applications` before enabling **Launch at login**.

Local builds automatically use an installed Apple Development certificate. Together with `scripts/run-dev.sh`, this gives the app a stable code identity and path so macOS permissions survive rebuilds. Set `KEYCONTROL_RELEASE_BUILD=1` for the release identity and `KEYCONTROL_SIGNING_IDENTITY` only when a release build needs a specific certificate.

Fresh installs open a short onboarding guide before requesting access. Afterwards, expand **Permissions** in the menu to inspect access and open the relevant System Settings page:

- **System Audio Recording** so the app can apply software gain. Audio stays on the Mac and is never recorded or stored.
- **Accessibility** so the app can consume volume up, volume down, and mute while software gain is active.
- **Input Monitoring** only when raw brightness keys are needed in a closed-lid/external-display setup.

System Audio Recording shows audio-pipeline status, not a claimed permission grant: macOS does not expose a reliable permission check here. Use **Try Audio** to start the audio path and trigger its system-managed request when needed.

## How volume works

Modern macOS exposes Core Audio process taps. The app creates a private, in-process tap as a software volume stage: it captures system output, mutes the direct copy, applies gain, and renders to the currently selected physical output. No audio driver, kernel extension, privileged helper, or administrator password is required.

The tap is private and fail-open. If the app exits or its audio path cannot start, Core Audio removes the tap and apps return to their normal direct output. Outputs that already expose native volume keep macOS volume-key handling and its HUD. The menu slider reads and adjusts their real Core Audio volume, and follows changes made with the keyboard or Control Center through Core Audio property notifications. A two-second poll remains as a recovery fallback. Native volume changes do not overwrite the saved software gain for fixed-volume outputs.

## Brightness compatibility

Brightness uses the monitor's DDC/CI luminance control. Support depends on the display, cable, adapter, and Mac port. DisplayPort and USB-C paths are generally more reliable than HDMI. Apple displays and built-in panels keep their native macOS behavior.

Each connected display has its own menu slider. Native displays use macOS brightness, monitors with a safely identified DDC service use hardware brightness, and other external displays use a click-through black shade. This changes the image, not the physical backlight; 100% removes the shade and 0% retains a visible floor. The shade disappears on exit or crash and starts undimmed when linking is off. Turning off Brightness keys removes it. Reconnecting the display or toggling Brightness keys checks DDC again and removes software dimming if hardware control becomes available.

The **Link brightness** checkbox makes the macOS main display the keyboard brightness master. A brightness key snaps all controllable displays to its updated percentage, and a linked slider sets the same percentage everywhere; unchecking it makes sliders independent and targets brightness keys at the display under the pointer. Linking is on by default. At launch, after detection completes, followers snap to the main display’s current percentage without changing the master. A saved opt-out is respected. Checking Link brightness immediately snaps followers to the main display’s percentage. Matching percentages does not claim to match nits. When the master uses native brightness, macOS applies the key and KeyControl briefly samples its resulting level at frame cadence, publishing the master and followers together to avoid staggered slider updates or a double step. If the main display cannot be controlled, the first controllable display becomes the master. Ambiguous DDC identities use software dimming rather than risk adjusting the wrong monitor. Software shades can appear in screenshots and do not promise accurate color or nits matching.

## Verify changes

```sh
scripts/test.sh
```

With the app running and permissions granted, exercise real media-key events against the selected audio interface and DDC display:

```sh
scripts/e2e-smoke.sh
```

The smoke test verifies volume down/up, mute/unmute, F14/F15 brightness, the HUD
kind/name/value for every action, and restoration of the original levels. It
also saves visual captures under `build/e2e-huds`.

Hardware behavior is covered by [the manual test plan](Tests/ManualTestPlan.md).

## Status

This is an early private prototype. See [the branding guide](docs/BRAND.md) for the name, colours, icon, and compatibility identifiers.

Enjoying the app? [Buy me a coffee](https://buymeacoffee.com/apotenza).
