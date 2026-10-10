<h1 align="center">Celestia Shell — Reimagined</h1>

<div align="center">

A refined, feature-complete desktop shell for [Hyprland](https://hypr.land),
built on [Quickshell](https://quickshell.outfoxxed.me).

**Celestia Shell Reimagined** is an in-place evolution of the
[Caelestia desktop shell](https://github.com/caelestia-dots/shell) that adds a
safe in-app updater, fully in-shell Material You theming, richer motion and
appearance controls, and a live Hyprland configuration panel — while keeping the
original's look, behaviour and configuration format.

![Version](https://img.shields.io/badge/version-1.0.0-9ccbfb?style=for-the-badge&labelColor=101418)
![License](https://img.shields.io/badge/license-GPL--3.0-b9c8da?style=for-the-badge&labelColor=101418)
![Platform](https://img.shields.io/badge/platform-Linux%20%C2%B7%20Hyprland-d3bfe6?style=for-the-badge&labelColor=101418)

</div>

---

## What's new in Reimagined

These are the headline features added on top of the upstream shell. See the
[documentation set](#documentation) for details.

- **Safe in-app updater** — check for, download, verify (SHA-256), stage, apply
  and roll back releases from Nexus without leaving the desktop. Every update is
  checksum-gated and keeps a known-good backup, so a bad update can always be
  undone. [Learn more →](docs/UPDATER.md)
- **In-shell Material You theming** — generate a complete M3 palette from a
  single seed colour, entirely inside the shell (no external CLI required), with
  light/dark/auto modes. [Learn more →](docs/THEMING.md)
- **Appearance controls** — density (rounding, spacing, padding, interface
  scale), typography (interface + monospace family), and transparency
  (surface/layer opacity) — all live. [Learn more →](docs/THEMING.md)
- **Motion profiles** — Balanced / Smooth / Expressive / Minimal / Reduced,
  plus fine-grained animation speed, morph fluidity and spring overshoot, and a
  reduced-motion accessibility switch. [Learn more →](docs/THEMING.md)
- **Live Hyprland settings** — tune window decorations, animations, workspace
  behaviour and pointer/input against the running compositor, with an automatic
  config backup and reload. [Learn more →](docs/THEMING.md)

## Components

- Widgets: [`Quickshell`](https://quickshell.outfoxxed.me)
- Window manager: [`Hyprland`](https://hypr.land)
- Optional companion CLI/dots: [`caelestia`](https://github.com/caelestia-dots/cli)

## Quick start

Full instructions live in [docs/INSTALL.md](docs/INSTALL.md). The short version,
assuming the [dependencies](docs/INSTALL.md#dependencies) are installed:

```sh
git clone https://github.com/mockifylab/Celestia-Shell_Reimagend.git caelestia
cd caelestia
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/
cmake --build build
sudo cmake --install build
```

Then start it with `qs -c caelestia` (or `caelestia shell -d` if you also use
the companion CLI).

To update later you can simply use the built-in updater from **Nexus → Updates**,
or re-run the install steps from a fresh `git pull`. To remove it, see
[Uninstalling](docs/INSTALL.md#uninstalling).

## Configuration

All configuration lives in `~/.config/caelestia/shell.json`. The file is not
created by default; any option you omit uses its built-in default. Per-monitor
overrides go in `~/.config/caelestia/monitors/<monitor_name>/shell.json`.

The new theming, appearance, motion and updater settings are all reachable from
the in-shell **Nexus** settings hub, and are persisted to the same file. For the
updater's advanced (self-hosting / testing) options, see
[docs/UPDATER.md](docs/UPDATER.md#advanced-configuration).

## Documentation

| Document | Contents |
| --- | --- |
| [docs/INSTALL.md](docs/INSTALL.md) | Dependencies, build, install, run, update, uninstall |
| [docs/UPDATER.md](docs/UPDATER.md) | The safe in-app updater: design, safety model, self-hosting |
| [docs/THEMING.md](docs/THEMING.md) | Colours, appearance, motion and Hyprland settings |
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | Local dev loop, code-quality gates, testing |
| [CHANGELOG.md](CHANGELOG.md) | Release history |
| [CONTRIBUTING.md](.github/CONTRIBUTING.md) | How to contribute |

## Attribution & license

Celestia Shell Reimagined is a derivative of the
**[caelestia-dots/shell](https://github.com/caelestia-dots/shell)** project by
the Caelestia team, and is distributed under the same terms.

- Upstream project: <https://github.com/caelestia-dots/shell>
- License: [GNU General Public License v3.0 only](LICENSE)

This project remains GPL-3.0 licensed. You are free to use, study, share and
modify it under those terms; the complete license text is included in
[`LICENSE`](LICENSE), and the upstream copyright notices are preserved.
