# Display enablement: implementation and evidence

Updated 2026-09-15. Implemented in the development app; not published.

## Behaviour

- A checkbox at the right of each physical display title controls whether it is enabled.
- Exact hover tooltip: **Enable or Disable this display.**
- No saved disable preference: the app never automatically disables a display at startup or reconnect.
- A disabled screen remains listed with its brightness slider disabled and its enable control available.
- Checkboxes are hidden with only one attached physical display. The last usable active physical screen cannot be disabled.
- Controls are independent of the Brightness keys setting. Unsupported display switching leaves existing audio and brightness behaviour intact.
- Apple silicon only for now. Mirrored, unverified and ambiguous identities are rejected; a virtual screen cannot act as the sole safety survivor.

## Architecture

`DisplayConnection.swift` isolates the dynamically loaded SkyLight symbols
`CGSGetDisplayList` / `SLSGetDisplayList` and
`CGSConfigureDisplayEnabled` / `SLSConfigureDisplayEnabled`. Each change validates
fresh state, uses a begin/configure/complete transaction, cancels configuration
errors, and verifies the observed result. Commits use `.forAppOnly`, never
`.permanently`; private enable state is **not** assumed to roll back on process death.

Hardware testing reproduced missing third-party menu-bar icons on LG after
software-disable, cable loss, recovery and reconnect. Ordinary cable reconnect
with both screens enabled returned icons normally. A `.forSession` experiment
also reproduced the missing icons and was reverted. Restarting MenuBarAgent
restored icons, without preference changes; that diagnostic workaround is not
automated in the app. The root cause and a product fix remain unresolved.

### Isolation check, 2026-09-16

With the main development app fully stopped, the command-line prototype and
independent recovery helper completed a four-second built-in off/on cycle.
Before/after screenshots retained LG third-party icons. A read-only trace
(`scripts/trace-display-layout.swift`) recorded the LG becoming main at (0,0)
while alone. A final snapshot exactly matched the initial configuration:
built-in main at (0,0), 1512x982 logical / 3024x1964 pixels; LG at (-192,-1080),
1920x1080. Both had zero rotation. This single successful cycle does not rule out
an intermittent failure or the cable-loss sequence. Evidence is under
`build/display-isolation/`; the timed trace ended before restoration, so the
final geometry was captured separately in `layout-after.jsonl`.
Tested binary SHA-256: `65a75d0cf7e2e16110bf6ad59f6318bd0ff126af012abf31c2be8398f8f19df5`.
The coordinated cable attempt then timed out without a detected disconnect.
Its complete trace (`cable-layout.jsonl`) also restored the exact initial layout;
it does not count as a cable-recovery isolation result. The main app was relaunched
with both displays enabled while awaiting the user's observation.

The repeat isolated cable test detected physical loss and restored the built-in
screen before timeout. The user confirmed all LG icons returned on reconnect.
`build/display-isolation/cable-retry-layout.jsonl` restored the exact initial
geometry and briefly observed an intermediate display ID 11 with no display mode
during disconnection. This passing run narrows the next comparison to the main
app's presence, but does not prove causation or exclude intermittent macOS behavior.
Evidence: `build/display-isolation/cable-retry.log`. No service restart was used.

The matching repeat with the main app running reproduced missing icons, confirmed
by the user (`app-running-cable.log`). Final geometry still matched the baseline
(`app-running-layout.jsonl`). Next isolation target is brightness discovery and
its process-owned panels; a passing/failing pair is evidence of an app interaction,
not yet proof of the particular handler responsible.

With the main app running but `brightnessEnabled` temporarily false, the same
cable test restored all icons (user confirmed; `brightness-off-cable.log`). The
setting was restored to true. Inspection found software-brightness discovery
allocated and recreated full-display panels even at 100% brightness. The current
candidate fix allocates only below 100%, reuses panels, removes obsolete shades,
and rejects screens without a valid mode. Build and 27 tests passed, as did
`build/display-isolation/shade-lifecycle.json`. The revised build then passed the
coordinated cable test with brightness enabled: physical loss triggered independent
recovery and the user confirmed all LG icons returned (`shade-fix-cable.log`).
This supports panel allocation as the trigger in this setup; dimming below 100%
and broader sleep/wake coverage still need physical verification.

Software dimming now persists user-adjusted levels by vendor/model/serial in
`softwareBrightnessByDisplay`. Missing serials and currently duplicated hardware
identities are not used for automatic restoration. Native/DDC levels continue
to be read from the hardware. New software displays default to 100% until adjusted.
Shade creation is delayed until one second after the last discovery update;
obsolete shades are removed immediately. Persistence/isolation tests bring the
suite to 29 passing tests. Build and quit/relaunch checks passed; see
`build/display-isolation/brightness-memory-lifecycle.json`. The coordinated dimmed
cable check passed: LG was at 64% before unplug, recovery restored the built-in,
and the user confirmed remembered dimming and all icons returned on LG reconnect.
Evidence: `build/display-isolation/dimmed-memory-cable.log`; binary SHA-256
`81136e00d54b3f6c25591ada254e43880576673080d60dc8238feee180ec27dd`.

`DisplayHardware.swift` reads EDID-bearing `IOPortTransportState` entries. This
independently identifies physical external connections and detects lost transport
entries even when WindowServer's display list is stale. No IOAV/DDC transport
code was changed. Unsupported transport discovery prevents unsafe disabling.

The built-in lookup key uses its built-in/vendor/model identity. External keys
use vendor/model/serial. Duplicate keys are not switchable. A live experiment
established that the disabled built-in panel remained in the private display
list but its UUID lookup returned nil. The first prototype lost its target;
explicit recovery through its unique hardware entry restored it. Hardware keys
fixed that failure, and the corrected tests were rerun. Runtime display IDs and
UUID availability are not used as durable recovery identities.

`DisplayRecovery.swift` launches the same signed executable in an isolated helper
mode, before audio, AppKit application startup, preferences or Sparkle services.
A pipe handshake arms recovery before a disable request. The helper owns the
transaction and explicitly restores on parent EOF (including SIGKILL), on a
restore request, or on loss of a physical display transport. It checks transports
every 500 ms only while it owns a disabled screen. It exits when its job is done;
no scheduler, launch agent, administrator access or installed background service
is added. Ordinary display sleep is not inferred from a zero active-screen count.

`DisplayConnectionController.swift` serializes parent operations away from main,
retains disabled rows and names, retries restoration when removed hardware
returns, and also handles a helper crash while the main app survives. Requests
to restore all are wired to normal quit and system sleep/wake. Errors are shown
in the menu with details in the error row's tooltip. Private-API failure still
cannot guarantee physical recovery on every OS/driver; no such guarantee is made.

`MenuBarController.swift` adds native NSButton checkboxes, accessible display
labels, the exact tooltip, and disabled brightness state. The development-only
menu smoke invokes the native controls and validates target/actions without
synthesizing global input. The development installer now quits normally and
waits for recovery helpers; it refuses replacement if they remain alive instead
of killing them with a blanket process-name match.

## Reproduction and evidence

- `scripts/test.sh`: Swift tests, app build, strict signature and plist validation.
- `swift scripts/probe-display-apis.swift`: read-only symbol and display inventory.
- `python3 scripts/test-display-prototype.py`: bounded real off/on and controlling-process SIGKILL recovery, built-in and external. Requires the installed dev binary; reports under `build/display-prototype/`.
- `python3 scripts/test-display-menu.py`: with other KeyControl instances closed, native checkbox actions, last-display guard, brightness independence, and normal quit / SIGKILL of the actual app while a screen is disabled. Reports under `build/display-menu/` with the tested binary hash.
- `scripts/release/lifecycle_smoke.py`: ordinary app lifecycle, against the already permitted development identity.
- `--display-prototype unplug`: development-only 30-second built-in disable window. The user unplugs the external cable; independent recovery should return the built-in screen before the deadline. A timeout restores it but is explicitly not a physical-unplug pass.

Local hardware: Built-in Retina Display and LG FULL HD on macOS 27.0,
build 26A5425a. The four bounded switching/recovery modes passed. The native menu
was visually captured with both checked controls aligned beside the titles.
Machine-readable reports record tested binary hashes and process/state assertions;
the manual test plan distinguishes those from physical observations.

**Remaining hardware observations:** actual cable unplug/reconnect, real system
sleep/wake and lid transitions, open-lid keyboard/trackpad use, and physical hover
tooltip appearance. Intel switching is disabled. Other monitors/connections,
virtual/mirrored configurations and identical monitors have guard coverage only,
not physical compatibility passes. No release was performed.

## Primary research references

- [BetterDisplay feature documentation](https://github.com/waydabber/BetterDisplay): display disconnection exists; [the author confirms the current source is private](https://github.com/waydabber/BetterDisplay/discussions/4837).
- [displayplacer](https://github.com/jakehilborn/displayplacer/blob/master/src/DisplayPlacer.c): private enable API and CoreGraphics transactions; its permanent commit policy is not used here.
- [MacDisplay](https://github.com/jjongkwann/MacDisplay/blob/main/core.swift): dynamic symbol loading and private offline enumeration. Its retry loop checks the same ID's membership, rather than mapping changed IDs.
- [DisplaySwitch recovery findings](https://github.com/haxsmert/display-swich/blob/main/README.md) and [IOKit implementation](https://github.com/haxsmert/display-swich/blob/main/Sources/DisplaySwitchCore/CGDisplayService.swift): project-reported unplug and crash pitfalls informed the independent transport/recovery design; they do not substitute for local hardware tests.
- [Apple application-scoped configuration](https://developer.apple.com/documentation/coregraphics/cgconfigureoption/forapponly) and the installed SDK header describe public transaction lifetime, not a reliable private-flag crash rollback. The local SIGKILL test observed the screen still disabled until the helper restored it.
