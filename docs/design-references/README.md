# macOS OSD references

These screenshots are visual references for KeyControl's fallback HUD. They were
captured from Apple's native macOS 27 volume and brightness overlays on September
4, 2026.

- `macos-27-volume-osd.png`: Scarlett 2i2 USB volume overlay
- `macos-27-brightness-osd.png`: Built-in Liquid Retina XDR Display brightness overlay
- `macos-27-muted-osd.png`: muted volume overlay with an empty level bar

KeyControl uses one SwiftUI implementation on every supported macOS release.
macOS 26 and newer use native Liquid Glass; older releases use the same geometry
with an ultra-thin material. It should match these references: placement,
dimensions, corner radius, material, typography, icon scale, slider geometry,
timing, and animation.
