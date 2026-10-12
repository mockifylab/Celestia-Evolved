# Theming and settings

Everything below is configured live from **Nexus**. Shell settings persist to
`~/.config/caelestia/shell.json`; the palette choice and wallpaper colour cache
persist to `~/.local/state/caelestia/theme.json`. Each page also has a matching
IPC target where noted.

## Colours (palette sources)

Celestia Reimagined generates complete Material 3 palettes **inside the shell**.
No external `caelestia` CLI is required, and none is used.

Open **Nexus → Appearance → Palette source** (also on **Wallpaper & style →
Colors**) and choose one:

- **Built-in Celestia palette** — a curated palette from the shell's own design
  system (`services/BuiltinPalettes.qml`): *Celestia*, *Dawn*, *Verdant*,
  *Nocturne*. Each one generates a coordinated **dark and light** set, and
  switching between dark and light mode swaps to the matching variant.
- **Colors from wallpaper** — extracts the dominant colour from the current
  wallpaper with the shell's own image analyser, generates the palette from it,
  and caches the result per wallpaper. Changing the wallpaper re-extracts (cached
  wallpapers apply instantly); **Refresh** forces a re-extraction. In `Auto`
  mode the light/dark decision comes from the wallpaper's measured luminance.
- **Custom color** — the classic single seed colour: pick a swatch or type any
  `#rrggbb`.
- **External scheme** — reads an externally generated `scheme.json`, if you have
  one. When no `theme.json` exists yet, the shell migrates your previous choice
  automatically: an existing `scheme.json` maps to *External scheme*, an enabled
  custom seed maps to *Custom color*, otherwise *Colors from wallpaper*.

**Mode** — `Auto` (follows the wallpaper/scheme luminance), `Light`, or `Dark`.

All sources go through one generator (`services/ColorGen.qml`): HSL tonal ramps
for every M3 role — primary, secondary, tertiary, error, success, background,
surface and elevated surfaces, their `on*` counterparts, outlines/muted text,
hover and selected states, plus a coherent `term0..term15` terminal ramp — with
`on*` roles derived from each base tone's lightness so text stays legible. It is
an approximation of Google's Material Color Utilities (which use HCT/CAM16) but
is fully self-contained, and every theme-aware surface (bar, dock, launcher,
settings, panels, control centre, notifications) reads the same role set.

Extraction and application are reported honestly: the Colors page shows the
current state (`extracting`, `ok`, `failed`) and the reason for a failure (no
wallpaper set, unsupported image format, unreadable path, or an image that could
not be decoded in time) instead of inventing colours.

Scriptable: `qs ipc call colours get|set|list|palette|seed|status`.

## Appearance

Also under **Nexus → Appearance**:

- **Density** — interface scale, corner rounding, spacing and padding, each as a
  percentage slider.
- **Typography** — choose the interface font and the monospace font from your
  installed families. The currently-effective family is always shown, even if it
  is a bundled resource rather than a system font.
- **Transparency** — enable translucent panel/dialog surfaces and tune surface
  vs. layer opacity independently.

## Motion

**Nexus → Motion** bundles the shell's animation behaviour:

- **Profile** — one of `Balanced`, `Smooth`, `Expressive`, `Minimal`, or
  `Reduced Motion`. A profile is a tuned combination of speed, morph and spring;
  anything not matching a profile shows as `Custom`.
- **Fine tuning**
  - *Animation speed* — global duration scale.
  - *Morph fluidity* — how strongly surfaces deform during transitions.
  - *Spring overshoot* — how bouncy the expressive spatial curves are.
- **Accessibility** — a **Reduced motion** switch that minimises non-essential
  animation across the shell.

## Hyprland

**Nexus → Hyprland** talks to the running compositor directly through the
`Hypr` service (Hyprland IPC), so changes apply immediately.

> [!WARNING]
> These settings change the **live compositor**, not your config file. They
> revert when Hyprland restarts unless you save them. The page includes a
> **Backup** button (copies `hyprland.conf` with a timestamp) and a **Reload**
> button (`hyprctl reload`) to help you persist changes safely.

Sections:

- **Window decorations** — inner/outer gaps, border size, corner rounding,
  active-window opacity, shadows, background blur.
- **Animations and effects** — the compositor's own window animations (distinct
  from the shell's Motion settings).
- **Workspaces** — workspace gaps, wraparound navigation, touchpad swipe
  direction, and create-on-swipe-past-last.
- **Pointer and input** — mouse sensitivity, natural scroll, tap-to-click, and
  pointer acceleration profile.

Each control reads its live value from `hyprctl` and writes back through
`Hyprland` IPC, so the sliders and toggles always reflect the current
compositor state.
