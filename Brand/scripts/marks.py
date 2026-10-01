#!/usr/bin/env python3
"""Writes the SVG masters of the ink tome mark and the Icon Composer layer.

The drawing is the brand book's `m-tome` symbol (64x64), with its CSS classes
resolved to Catppuccin Mocha (dark) or Latte (light).
"""
from pathlib import Path

BRAND = Path(__file__).resolve().parent.parent

PALETTES = {
    "dark": dict(base="#1e1e2e", text="#cdd6f4", mauve="#cba6f7", peach="#fab387",
                 yellow="#f9e2af", pink="#f5c2e7", lavender="#b4befe"),
    "light": dict(base="#eff1f5", text="#4c4f69", mauve="#8839ef", peach="#fe640b",
                  yellow="#df8e1d", pink="#ea76cb", lavender="#7287fd"),
}


def tome(c, clip_id="clip-tome"):
    return f"""  <defs>
    <clipPath id="{clip_id}"><rect x="15.5" y="13.5" width="29" height="39" rx="1.5"/></clipPath>
  </defs>
  <rect x="18" y="16" width="32" height="42" rx="3" fill="{c['base']}" stroke="{c['text']}" stroke-width="3"/>
  <path d="M21 56.5H46" fill="none" stroke="{c['text']}" stroke-width="1.5" stroke-linecap="round" opacity=".45"/>
  <rect x="14" y="12" width="32" height="42" rx="3" fill="{c['base']}" stroke="{c['text']}" stroke-width="3"/>
  <path clip-path="url(#{clip_id})" d="M10 36Q16 31.5 22 36T34 36T46 36T58 36V60H10Z" fill="{c['mauve']}"/>
  <circle cx="31" cy="44" r="2.6" fill="{c['base']}" fill-opacity=".55"/>
  <circle cx="38" cy="48.5" r="1.8" fill="{c['base']}" fill-opacity=".55"/>
  <path d="M20.5 13.5V52.5" fill="none" stroke="{c['text']}" stroke-width="3"/>
  <rect x="40" y="26" width="11" height="9" rx="2.5" fill="{c['peach']}" stroke="{c['text']}" stroke-width="3"/>
  <path d="M8 2Q8 7.5 13.5 7.5Q8 7.5 8 13Q8 7.5 2.5 7.5Q8 7.5 8 2Z" fill="{c['yellow']}"/>
  <circle cx="55" cy="9" r="3" fill="none" stroke="{c['pink']}" stroke-width="2"/>
  <circle cx="59" cy="18" r="2.2" fill="{c['lavender']}"/>
"""


def svg(body, view_box, size):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{view_box}" '
            f'width="{size}" height="{size}">\n{body}</svg>\n')


for name, colors in PALETTES.items():
    (BRAND / f"mark-{name}.svg").write_text(svg(tome(colors), "0 0 64 64", 64))

# Icon Composer layers: the mark fills 68% of the 1024pt canvas, as in the brand book.
side = 64 / 0.68
inset = (side - 64) / 2
icon_assets = BRAND / "Grimoire.icon" / "Assets"
icon_assets.mkdir(parents=True, exist_ok=True)
for name, colors in PALETTES.items():
    (icon_assets / f"tome-{name}.svg").write_text(
        svg(tome(colors), f"{-inset:.3f} {-inset:.3f} {side:.3f} {side:.3f}", 1024))
