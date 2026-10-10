# Theming and settings

Everything below is configured live from **Nexus**, and persisted to
`~/.config/caelestia/shell.json`. Each page also has a matching IPC target where
noted.

## Colours (Material You)

Celestia Reimagined generates a full Material 3 palette **inside the shell**,
from a single seed colour — no external `caelestia` CLI needed.

Open **Nexus → Appearance** and turn on **Use custom colors**:

- **Seed color** — pick a preset swatch or type any `#rrggbb` value.
- **Mode** — `Auto` (follows your current light/dark scheme), `Light`, or `Dark`.

The generator (`services/ColorGen.qml`) derives every M3 role — primary,
secondary, tertiary, error, success, surfaces, neutrals and their `on*`
counterparts — using HSL tonal ramps, keeping text legible by deriving `on*`
roles from each base tone's lightness. It is an approximation of Google's
Material Color Utilities (which use HCT/CAM16) but is fully self-contained.

When custom colours are **off**, the shell reverts to the standard
`scheme.json`-driven behaviour, so the two modes coexist cleanly.

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
