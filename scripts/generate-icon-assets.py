#!/usr/bin/env python3
"""Generate editable SVGs and native appearance-aware Icon Composer documents."""
from pathlib import Path
import json
ROOT = Path(__file__).resolve().parents[1]

def hybrid_glyph(sun, speaker):
    paths = json.loads((ROOT/'Resources/GlyphPaths.json').read_text())
    return (f'<path d="{paths["sun"]}" fill="{sun}"/>'
            + f'<path d="{paths["wave"]}" fill="{speaker}"/>'
            + f'<path d="{paths["speaker"]}" fill="{speaker}"/>')


def artwork(channel, dark):
    beta = channel == 'beta'
    sun_top, sun_bottom = ('#ffe79a', '#f0ad25') if dark else ('#e5ac29', '#a76500')
    if beta:
        sun_top, sun_bottom = ('#ffba80', '#ff6557') if dark else ('#f58a39', '#ca433f')
    audio_top, audio_bottom = (('#d1b6ff', '#9b6bef') if dark else ('#a271ef', '#6535b7')) if beta else (('#a0dcff', '#409fee') if dark else ('#329ff2', '#095fbd'))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
<title>Keyboard Control — {channel}, {'dark' if dark else 'light'}</title>
<desc>A clean gold half-sun merging naturally into a colored speaker glyph, on a transparent canvas. The shared custom vector mark matches the monochrome menu icon.</desc>
<defs>
  <linearGradient id="sunColor" gradientUnits="userSpaceOnUse" x1="0" y1="1" x2="3" y2="17"><stop stop-color="{sun_top}"/><stop offset="1" stop-color="{sun_bottom}"/></linearGradient>
  <linearGradient id="audioColor" gradientUnits="userSpaceOnUse" x1="9" y1="4" x2="12" y2="14"><stop stop-color="{audio_top}"/><stop offset="1" stop-color="{audio_bottom}"/></linearGradient>
</defs>
<!-- A single full-bleed transparent canvas; macOS supplies the background and mask. -->
<g transform="translate(62 62) scale(50)">{hybrid_glyph('url(#sunColor)', 'url(#audioColor)')}</g>
</svg>
'''

for channel in ['stable','beta']:
    name='AppIconBeta' if channel=='beta' else 'AppIcon'
    package=ROOT/'Resources'/f'{name}.icon'
    assets=package/'Assets';assets.mkdir(parents=True,exist_ok=True)
    for dark in [False,True]:
        svg=artwork(channel,dark)
        (assets/('artwork-dark.svg' if dark else 'artwork.svg')).write_text(svg)
        # Web preview keeps standard Mac icon padding; native compiler supplies its own mask.
        web=svg.replace('<defs>','<defs><clipPath id="tile-mask"><rect x="100" y="100" width="824" height="824" rx="184"/></clipPath>',1)
        marker='<!-- A single full-bleed'
        web=web.replace(marker, '<g clip-path="url(#tile-mask)"><g transform="translate(100 100) scale(.8046875)">\n'
                        + marker, 1).replace('</svg>', '</g></g></svg>')
        (ROOT/'docs/assets'/f'icon-{channel}-{"dark" if dark else "light"}.svg').write_text(web)
    manifest={
        'fill-specializations':[{'value':'system-light'},{'appearance':'dark','value':'system-dark'}],
        'groups':[{'layers':[{
            'fill-specializations':[{'value':'none'},{'appearance':'dark','value':'none'}],
            'image-name-specializations':[{'value':'artwork.svg'},{'appearance':'dark','value':'artwork-dark.svg'}],
            'name':'Sun and sound glyph'}],
            'shadow':{'kind':'neutral','opacity':0},'translucency':{'enabled':False,'value':0}}],
        'supported-platforms':{'squares':'shared'}}
    (package/'icon.json').write_text(json.dumps(manifest,indent=2)+'\n')
(ROOT/'docs/assets/keyboard-control-concept.svg').write_text((ROOT/'docs/assets/icon-stable-light.svg').read_text())

# The menu preview and full app icon use precisely the same uncut vector geometry.
(ROOT/'docs/assets/menu-control-concept.svg').write_text(
    '<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 18 18" role="img" aria-label="Brightness and volume">\n'
    '<style>:root { color: #1d1d1f; } @media (prefers-color-scheme: dark) { :root { color: #f5f5f7; } }</style>\n'
    + hybrid_glyph('currentColor', 'currentColor') + '</svg>\n')
