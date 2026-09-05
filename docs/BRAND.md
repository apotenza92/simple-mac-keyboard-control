# Simple Mac Keyboard Control

**Volume and brightness. Back on your keyboard.**

A small native menu-bar app for keyboard volume, mute, and external-monitor
brightness on connected Mac hardware. No mixer, equalizer, or shortcut editor.

## Visual identity

- The app artwork contains only the colored sun/speaker glyph on a transparent canvas; macOS supplies the tile.
- The large glyph merges a warm yellow half-sun with a speaker; retain the natural overlap, without clipping at the midpoint.
- Stable uses a blue speaker; beta uses violet. Stable retains a gold sun; beta uses a peach-to-coral sunset sun.
- Light and dark appearances use contrast-adjusted gold and speaker colors on the system-provided background.
- Menu bar: the same custom sun/speaker geometry, monochrome at 18 points. macOS supplies template tinting.
- The combined mark is custom vector artwork inspired by the system symbols, not an unmodified SF Symbol.
- Typography: system SF; sentence case and plain, functional language.

`scripts/generate-icon-assets.py` generates the app SVGs, menu SVG, and native
`Resources/AppIcon.icon` and `Resources/AppIconBeta.icon` documents. The current
artwork is entirely vector. The previous individual SF Symbol renders remain in
`Resources/Symbols` as source material, but are not used by the current app icon.
Xcode packages light/dark appearances in `Assets.car`, plus an ICNS fallback for
older macOS. macOS supplies the outside mask and system background; no keycap, bevel, reflection, or background is drawn into the artwork. Icon appearance follows the system icon style
selection, which can be independent of window appearance. The website follows
browser light/dark preference. Builds require Xcode 26 or later; runtime support
remains macOS 14.4 or later. The HUD retains native macOS materials.

## Naming and compatibility

Public app name: **Simple Mac Keyboard Control**.
Development display name: **Simple Mac Keyboard Control Dev**.
Repository and workspace folder: `simple-mac-keyboard-control`.

Internal Swift modules, bundle IDs (`com.apotenza.KeyControl` and `.dev`), signing
identity, and the installed `~/Applications/KeyControl Dev.app` path remain stable
to avoid unnecessary permission migrations. These are implementation identifiers,
not public branding.

## Positioning and launch copy

Your audio interface. Your external monitor. The keys you already reach for.

Short description: A free, open source macOS menu-bar utility that brings volume,
mute, and brightness keys to external audio and displays.

Lead with the everyday problem: volume keys do nothing on an audio interface,
or brightness keys leave an external monitor behind. Explain software volume
and DDC only when people need compatibility or permission details. Avoid universal
compatibility claims, unverified performance claims, and promises about automatic updates.

The current public name remains in place pending the naming decision. KeyControl
is concise but has existing software-product collisions; do not rename the repo
or public URLs until the final name is chosen.

The website uses the GitHub Pages distribution model from Macsimize and Dockmint:
light/dark appearance, stable/beta selection, Apple silicon/Intel selection,
GitHub releases, and the same author/support links. Blue distinguishes this app
from the green identities of the other two.

The glyph uses closed filled outlines from `Resources/GlyphPaths.json`. Regenerate
them with `scripts/export-glyph-paths.swift` when changing geometry, then run the
asset generator. Stroke expansion and a unioned speaker outline avoid native
Icon Composer cap seams and overlapping-fill artifacts.
