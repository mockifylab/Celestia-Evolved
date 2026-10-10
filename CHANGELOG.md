# Changelog

All notable changes to **Celestia Shell — Reimagined** are documented here.
This project adheres to [Semantic Versioning](https://semver.org/).

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
