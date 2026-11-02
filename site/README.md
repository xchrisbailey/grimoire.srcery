# Product page

The [website](https://xchrisbailey.github.io/grimoire.srcery/) is dependency-free HTML, CSS and JavaScript. Open `index.html` directly, or serve this folder with `python3 -m http.server 8000 --directory site` from the repository root.

Keep product claims and installation requirements aligned with the root README. Download links intentionally target `/releases`, not `/releases/latest`: beta releases are prereleases. Screenshots are copied from `docs/images`; brand SVGs come from `Brand`, and Geist and its OFL license come from `Resources/Fonts`. Refresh the copies here when those sources change. No remote fonts, analytics or runtime services are required.

The preview picker progressively enhances a plain list of screenshots and captions. Keep all content readable without JavaScript, keyboard controls operable, focus visible and motion optional. Check desktop, tablet and phone widths, no-JavaScript and reduced-motion modes before publishing.

`.github/workflows/pages.yml` uploads this folder and deploys to the existing `github-pages` environment on site/workflow changes to `main`, or a manual run on `main`. GitHub Pages must remain configured to use Actions. No native app build is involved. Paths are relative so the page works under `/grimoire.srcery/`.
