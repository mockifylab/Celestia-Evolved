# Changelog

All notable changes to **Celestia Shell — Reimagined** are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

## [1.0.2]

Maintenance release. Full work log: `V1.0.2_CHANGELOG.md`, verification matrix:
`V1.0.2_TEST_PLAN.md`.

### Fixed

- **Every settings slider.** Value, handle position, track fill, the applied
  setting and the saved value now come from one shared mapping library
  (`utils/sliderMapping.js`): correct ranges/steps, exact endpoints, no float
  drift, correct percent↔fraction handling, and clicks near the ends reach the
  minimum/maximum. Affected surfaces include Motion, Appearance, Panels/Taskbar,
  Hyprland, Audio and Services.
- **Installed version was never registered.** A successful in-app update now
  writes `<install>/VERSION`, and the shell reads that first (falling back to the
  compiled-in version for older installs). The Updates page, About page and the
  update comparison share that one value, so an installed release is no longer
  re-offered forever. Release tarballs also carry `VERSION`.
- **Updates page was partly decorative.** It now shows the real installed and
  available versions, the actual release notes from the release feed, the
  download size, honest progress/completion/error states, and its buttons drive
  the real download → verify → stage → apply pipeline (with rollback intact).
- **Wallpaper-derived colours reported a missing CLI.** The `caelestia` CLI was
  an incorrect assumption, not a dependency; extraction now uses the colour
  analyser already shipped with the shell, with a per-wallpaper cache,
  regeneration when the wallpaper changes, dark/light auto-detection from image
  luminance, and truthful failure states (no wallpaper, unsupported format,
  unreadable path, timed-out decode) instead of fabricated colours.
- **Updates could delete user content.** Installed plugins are now preserved
  across apply and rollback, like `user.conf` and the cache already were.

### Added

- **Palette source selector in Appearance**: Built-in Celestia palette, colours
  derived from the wallpaper, plus the legacy custom-seed and external-scheme
  sources. Switching applies immediately, persists across restarts
  (`theme.json`), and dark/light mode picks the matching variant.
- **Four built-in palettes** (`celestia`, `dawn`, `verdant`, `nocturne`), each
  generated as coordinated dark *and* light sets covering every supported theme
  role (background, surface, elevated surface, text, muted text, borders, accent,
  hover/selected, error, terminal ramp) and applied through the existing theme
  architecture, so bar, dock, launcher, settings, panels, control centre and
  notifications all follow.
- `qs ipc` entry points for the theme (`colours get/set/list/palette/seed/status`)
  and regression fixtures for sliders, the updater and palettes.

## [1.0.1]

Maintenance release (published earlier; entry back-filled — the full log is
`V1.0.1_CHANGELOG.md`).

### Fixed

- Notification popups became a configurable panel rather than a hardcoded
  surface.
- `SliderRow` no longer mis-mapped the normalized value of `StyledSlider`.
- Wallpaper selection persisted correctly across restarts.

## [1.0.0]

The first Reimagined release, built on Caelestia Shell v2.5.0.

### Added

- **Safe in-app updater** (Nexus → Updates): check the release feed, download,
  verify a SHA-256 digest, stage, apply and roll back — all from the desktop.
  Checksum-gated (unverified updates are refused), backs up the current install
  before activating, preserves `user.conf`, and auto-restores if activation
  fails. Fully overridable via `CAELESTIA_UPDATE_*` for self-hosting and offline
  testing, and covered by a local fixture test.
- **In-shell Material You theming**: generate a complete M3 palette from a single
  seed colour, with Light / Dark / Auto modes — no external CLI required.
- **Appearance controls**: interface scale, corner rounding, spacing and padding
  density; interface and monospace font selection; and transparency (surface and
  layer opacity).
- **Motion profiles**: Balanced / Smooth / Expressive / Minimal / Reduced, plus
  fine-grained animation speed, morph fluidity and spring overshoot, and a
  reduced-motion accessibility switch.
- **Live Hyprland settings**: window decorations, compositor animations,
  workspace behaviour (gaps, wraparound, swipe) and pointer/input, applied
  against the running compositor with automatic config backup and reload.
- **Documentation set**: `README`, install/uninstall guide, updater guide,
  theming guide and a development/testing guide.

### Fixed

- **Appearance panel load performance**: the wallpaper picker now reveals items
  incrementally bound to the viewport instead of realising the entire list at
  once, removing the release-blocking stall when opening Appearance.

### Notes

- Remains GPL-3.0 licensed and is a derivative of
  [`caelestia-dots/shell`](https://github.com/caelestia-dots/shell).

[1.0.0]: https://github.com/mockifylab/Celestia-Shell_Reimagend/releases/tag/v1.0.0
