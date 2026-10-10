# Installing Celestia Shell Reimagined

This guide covers building, installing, running, updating and removing the shell
from source. The shell targets **Arch Linux** and any distribution that can
provide the dependencies below; the Nix flake is also available.

> [!IMPORTANT]
> Commands here assume `$XDG_CONFIG_HOME` is set (normally `~/.config`). If it is
> unset, substitute `~/.config` wherever `$XDG_CONFIG_HOME` appears.

## Dependencies

Runtime:

- [`quickshell-git`](https://git.outfoxxed.me/quickshell/quickshell) — **must be
  the git version**, not the latest tagged release
- [`caelestia-cli`](https://github.com/caelestia-dots/cli) — optional, for the
  `caelestia shell ...` IPC wrapper and wallpaper/scheme helpers
- `glibc`, `gcc-libs`
- [`ddcutil`](https://github.com/rockowitz/ddcutil),
  [`brightnessctl`](https://github.com/Hummer12007/brightnessctl)
- [`libcava`](https://github.com/LukashonakV/cava),
  [`aubio`](https://github.com/aubio/aubio),
  [`libpipewire`](https://github.com/PipeWire/pipewire)
- [`networkmanager`](https://gitlab.freedesktop.org/NetworkManager/NetworkManager)
- [`lm_sensors`](https://github.com/lm-sensors/lm-sensors)
- [`libqalculate`](https://github.com/Qalculate/libqalculate)
- [`power-profiles-daemon`](https://gitlab.freedesktop.org/upower/power-profiles-daemon)
- Fonts: `ttf-material-symbols-variable`, `ttf-rubik-vf`,
  `ttf-cascadia-code-nerd`
- Qt 6: `qt6-base`, `qt6-declarative`, `qt6-imageformats`,
  [`qt6-m3shapes-git`](https://github.com/soramane/m3shapes)
- Helpers: [`swappy`](https://github.com/jtheoof/swappy),
  [`fish`](https://github.com/fish-shell/fish-shell),
  [`bash`](https://www.gnu.org/software/bash)
- For the built-in updater: `curl` (or `wget`), `tar`, `sha256sum`
  (coreutils), `rsync`

Build:

- `cmake` (≥ 3.19), `ninja`
- `qt6-shadertools`
- A C++20 compiler (`gcc`/`clang`)

## Manual install

Clone the repository into Quickshell's config directory so it can be found by
name, then build and install with CMake:

```sh
cd "$XDG_CONFIG_HOME/quickshell"
git clone https://github.com/mockifylab/Celestia-Shell_Reimagend.git caelestia

cd caelestia
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/
cmake --build build
sudo cmake --install build
```

The version string is taken from the latest git tag (`git describe --tags`), so a
tagged checkout reports the correct version in **Nexus → About** and to the
updater.

### Install locations

| CMake variable | Default | Contents |
| --- | --- | --- |
| `INSTALL_QSCONFDIR` | `/etc/xdg/quickshell/caelestia` | Shell QML, assets (incl. the updater helper), LICENSE |
| `INSTALL_QMLDIR` | `<libdir>/qt6/qml` | The `Caelestia` QML plugin |
| `INSTALL_LIBDIR` | `<libdir>/caelestia` | Native helper library |

You can customise these with `-DINSTALL_QSCONFDIR=...`, etc. If you change
`INSTALL_LIBDIR`, also export `CAELESTIA_LIB_DIR` to the same path in your
environment.

For easy local tinkering, install into your user config instead of the system
prefix:

```sh
mkdir -p ~/.config/quickshell/caelestia
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/ \
  -DINSTALL_QSCONFDIR="$HOME/.config/quickshell/caelestia"
cmake --build build
cmake --install build
```

## Running

Start the shell with:

```sh
qs -c caelestia
```

or, if you use the companion CLI (recommended, and detaches from the terminal):

```sh
caelestia shell -d
```

Under Hyprland you can autostart it from your `hyprland.conf`. IPC commands are
available through `caelestia shell ...` (or `qs ipc`), e.g.:

```sh
caelestia shell -s          # list available IPC commands
```

## Updating

### In-app (recommended)

Open **Nexus → Updates** and press **Check**. If a newer release is found you can
**Update** it in place: the archive is downloaded, its SHA-256 digest verified,
staged, and only then applied — with a backup kept so you can **Roll back**. See
[UPDATER.md](UPDATER.md) for how this works and how to self-host the feed.

### From source

```sh
cd "$XDG_CONFIG_HOME/quickshell/caelestia"
git pull
cmake --build build
sudo cmake --install build
```

Restart the shell afterwards to load the new version.

## Uninstalling

CMake records every installed file in `build/install_manifest.txt`. To remove a
system install:

```sh
sudo xargs rm -vf < build/install_manifest.txt
```

Then remove the user configuration and caches if you want a clean slate:

```sh
rm -rf ~/.config/caelestia          # settings (shell.json, monitors, ...)
rm -rf ~/.local/state/caelestia     # runtime state (scheme.json, ...)
rm -rf ~/.cache/caelestia           # caches (incl. updater downloads/backup)
```

If you installed to a user prefix (`~/.config/quickshell/caelestia`), delete that
directory as well.
