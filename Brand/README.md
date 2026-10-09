# Brand

The source of truth is the [Grimoire brand book](https://claude.ai/artifact/CXpJJMMohhQYzsjoMMzq4D) (brand draft 1, decided 2026-09-30).

| File | What it is |
|---|---|
| `mark-dark.svg`, `mark-light.svg` | The ink tome mark (64×64) in Catppuccin Mocha and Latte. |
| `wordmark-dark.svg`, `wordmark-light.svg` | `grimoire` in Geist 800, outlined, with the pink ring and lavender dot over the i's and the peach Geist Mono `_` cursor. |
| `Grimoire.icon` | The Icon Composer app icon used by both app targets. A Latte squircle with a mauve glow by default and a Mocha one in dark mode; the tinted and clear looks come from the system. |
| `dmg-background.tiff` | The artwork behind the release DMG's Finder window: the mark and wordmark on the Mocha base, with an arrow between the app and Applications. A 1x and a 2x image in one TIFF, so it is sharp on Retina and non-Retina displays. Checked in, so packaging needs no renderer. |
| `dmg-layout.json` | The DMG window's position and size, icon size, and where each icon sits. `scripts/dmg-layout.py` writes it into the image and `scripts/dmg-background.swift` draws the arrow from it, so change it in one place. |
| `scripts/marks.py` | Regenerates the mark SVGs and the icon's layer art. |
| `scripts/wordmark.swift` | Regenerates the wordmark from the bundled Geist fonts. |
| `scripts/dmg-background.swift` | Regenerates `dmg-background.tiff` from `mark-dark.svg`, `wordmark-dark.svg` and `dmg-layout.json`, using AppKit, the bundled Geist font and `tiffutil`. |

Regenerate from the repo root:

```sh
python3 Brand/scripts/marks.py
swift Brand/scripts/wordmark.swift
swift Brand/scripts/dmg-background.swift
```

Open `Grimoire.icon` in Icon Composer (inside Xcode) to adjust glass, shadow or the per-appearance fills.

After changing `dmg-layout.json` or the artwork, run `scripts/package-mac.sh <label>` and open the DMG. The window is sized to the artwork, so a new window size means a new background.
