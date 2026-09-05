# Release and distribution

## Channels

| | Stable | Beta |
|---|---|---|
| Tags | `vX.Y.Z` | `vX.Y.Z-beta.N`, plus newer stable releases |
| App | Simple Mac Keyboard Control.app | Simple Mac Keyboard Control Beta.app |
| Bundle ID | `com.apotenza.KeyControl` | `com.apotenza.KeyControl.beta` |
| Icon | Gold/blue | Sunset/violet |
| Cask | `simple-mac-keyboard-control` | `simple-mac-keyboard-control@beta` |

Both require macOS 14.4. Native arm64 and x64 packages are separate. Hardware
DDC is Apple-silicon-only; Intel uses software dimming. Keep one channel running.
Development retains `com.apotenza.KeyControl.dev` and `~/Applications/KeyControl Dev.app`.

## Updates

Release builds embed Sparkle 2.9.6, automatic checks, and a Check for Updates menu
button. Users approve installation. Development builds never start Sparkle.
Each identity and architecture has its own HTTPS feed under `appcasts/` on main.
A dedicated Ed25519 public key is embedded in the app; private material lives in
macOS Keychain (account `com.apotenza.KeyControl`) and the `sparkle-signing`
environment. Archives are signature-checked before extraction. App termination
restores the direct audio path and removes software dimming before an update.

The first release establishes the updater baseline. There is no previous public
version for an N-1 installation test yet. Before subsequent releases, exercise
an actual previous-version Sparkle install and relaunch; archive signature tests
alone do not establish that result.

## Tag-driven publication

1. Run `scripts/test.sh`, Python release tests with `cryptography==45.0.7`, Node
   download tests, and actionlint. Complete `Tests/ManualTestPlan.md` on both
   fixed-volume/native-volume outputs and a working external DDC display.
2. Add `release-notes/vX.Y.Z.md`, commit, and push main. Record the exact hardware-
   verified commit as `HARDWARE_VERIFIED_COMMIT` in the final stable-release or
   beta-release environment. This is verification evidence, never an inferred pass.
3. Push the tag. The workflow requires the tagged commit to be reachable from main.
   Native ARM and Intel jobs build, sign, notarize, staple, and package each identity.
4. The workflow stages a draft, signs exact Sparkle archives, and seals the common
   Homebrew publication bundle. Independent native jobs verify identity, version,
   architecture, code-signing certificate, hardened runtime, Gatekeeper, notarization,
   Sparkle signatures, and tamper rejection.
5. After the hardware gate, the secret-free publication job attests the Homebrew
   bundle, publishes the immutable release, and advances feeds without downgrades.
6. The tap's hourly reconciliation discovers the attested release and publishes
   the approved casks through its protected publisher. For immediate publication,
   dispatch `publish-homebrew.yml` in `apotenza92/homebrew-tap` with product, tag,
   commit, source run ID/attempt, and correlation ID. Source jobs have no tap write token.
7. Dispatch `pages.yml` to publish the minimal download page. Verify public package
   URLs, each feed, and both casks before announcing availability.

Release signing credentials are isolated in tag-only `release-signing` and
`sparkle-signing` environments. Apple metadata is public configuration; the P12,
certificate password, P8, and Sparkle private key must never enter source control.
Repository release immutability must be enabled. Public distribution also requires
public release/download access; repository visibility is not changed by the scripts.

## Current launch status

The release wiring is implemented. First publication remains gated on recorded
hardware verification and successful native CI. Do not describe the app as
released or Homebrew-installable until public artifacts and casks are verified.
