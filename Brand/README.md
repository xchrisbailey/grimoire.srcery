# Brand

The source of truth is the [Grimoire brand book](https://claude.ai/artifact/CXpJJMMohhQYzsjoMMzq4D) (brand draft 1, decided 2026-09-30).

| File | What it is |
|---|---|
| `mark-dark.svg`, `mark-light.svg` | The ink tome mark (64×64) in Catppuccin Mocha and Latte. |
| `wordmark-dark.svg`, `wordmark-light.svg` | `grimoire` in Geist 800, outlined, with the pink ring and lavender dot over the i's and the peach Geist Mono `_` cursor. |
| `Grimoire.icon` | The Icon Composer app icon used by both app targets. A Latte squircle with a mauve glow by default and a Mocha one in dark mode; the tinted and clear looks come from the system. |
| `scripts/marks.py` | Regenerates the mark SVGs and the icon's layer art. |
| `scripts/wordmark.swift` | Regenerates the wordmark from the bundled Geist fonts. |

Regenerate from the repo root:

```sh
python3 Brand/scripts/marks.py
swift Brand/scripts/wordmark.swift
```

Open `Grimoire.icon` in Icon Composer (inside Xcode) to adjust glass, shadow or the per-appearance fills.
