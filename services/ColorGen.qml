pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

// In-shell Material-You-style palette generator.
//
// Given a single seed colour and a light/dark choice, it derives a full set of
// M3 roles using HSL tonal ramps. This is an approximation of Google's Material
// Color Utilities (which use HCT/CAM16), but it is self-contained (no external
// `caelestia` CLI needed) and keeps text legible by deriving `on*` roles from
// the base tone's lightness.
//
// It is the single design system of the shell: both the built-in Celestia
// palettes (see BuiltinPalettes.qml) and wallpaper-derived colours go through
// `roles()` below, so every surface, including the terminal ramp, is generated
// from the same tonal rules.
Singleton {
    id: root

    // Whether a string is usable as a colour seed. Used to reject bogus input
    // instead of silently generating a palette from garbage.
    function isValidSeed(seed: string): bool {
        if (seed === undefined || seed === null)
            return false;
        const s = String(seed).trim();
        if (!/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(s))
            return false;
        const c = Qt.color(s);
        return c !== undefined && c.valid !== false;
    }

    function clamp(v: real, lo: real, hi: real): real {
        return Math.max(lo, Math.min(hi, v));
    }

    function mod1(v: real): real {
        return ((v % 1) + 1) % 1;
    }

    function toHex(c: color): string {
        const h = n => ("0" + Math.round(clamp(n, 0, 1) * 255).toString(16)).slice(-2);
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }

    // Build a colour from hue (0..1, wraps), saturation (0..1) and a Material
    // "tone" (0..100 lightness).
    function tone(h: real, s: real, t: real): string {
        return toHex(Qt.hsla(mod1(h), clamp(s, 0, 1), clamp(t / 100, 0, 1), 1));
    }

    // Move `base` a fraction `pull` (0..1) of the shortest way around the hue
    // wheel towards `towards`, so canonical accents can be tinted to match a
    // palette without collapsing into a single colour.
    function mixHue(base: real, towards: real, pull: real): real {
        let d = towards - base;
        if (d > 0.5)
            d -= 1;
        else if (d < -0.5)
            d += 1;
        return mod1(base + d * clamp(pull, 0, 1));
    }

    // Terminal colour ramp (term0..term15). Kept in the same tonal system as
    // the M3 roles so a palette change never leaves stale ANSI colours behind.
    function terminalRamp(h: real, s: real, nS: real, light: bool): var {
        const pull = 0.25; // hint the canonical hues towards the seed hue
        const lo = light ? 30 : 76;
        const hi = light ? 45 : 90;
        const hues = [0.99, 0.36, 0.12, 0.62, 0.87, 0.5];
        const sats = [0.75, 0.55, 0.75, 0.65, 0.6, 0.6];
        const t = {};
        t.term0 = tone(h, nS, light ? 20 : 12);
        t.term7 = tone(h, nS, light ? 40 : 88);
        t.term8 = tone(h, nS, light ? 60 : 45);
        t.term15 = tone(h, nS, light ? 95 : 97);
        for (let i = 0; i < 6; i++) {
            const hue = mixHue(hues[i], h, pull);
            t[`term${1 + i}`] = tone(hue, sats[i], lo);
            t[`term${9 + i}`] = tone(hue, sats[i], hi);
        }
        return t;
    }

    // Returns a map of M3 role name -> hex string for the given seed and mode.
    // `opts` tunes the design system per palette:
    //   sat         - override the accent saturation (0..1)
    //   neutralSat  - tint of the neutral ramp (default 0.05)
    //   variantSat  - saturation of secondary/tertiary relative multipliers
    function roles(seed: string, light: bool, opts: var): var {
        const o = opts ?? {};
        const sc = Qt.color(isValidSeed(seed) ? seed : "#808080");
        const h = sc.hslHue;
        // Guarantee enough chroma to read as a themed accent.
        const s = o.sat !== undefined ? clamp(o.sat, 0, 1) : clamp(Math.max(sc.hslSaturation, 0.28), 0, 0.7);
        const spread = o.variantSat ?? 1;
        const sh = s * 0.32 * spread; // secondary (desaturated)
        const th = s * 0.55 * spread; // tertiary
        const tHue = mod1(h + 0.14); // ~+50 degrees
        const nS = o.neutralSat ?? 0.05; // neutral
        const nvS = nS > 0.05 ? nS + 0.07 : 0.12; // neutral variant

        // Primary/secondary/tertiary key tones differ between light and dark.
        const pKey = light ? 40 : 80;
        const pCont = light ? 90 : 32;
        const pOn = light ? 10 : 90;
        const pOnKey = light ? 100 : 20;
        const inv = light ? 80 : 40;

        // Surface / neutral ramp.
        const surf = light ? 98 : 6;
        const onSurf = light ? 10 : 90;
        const cLowest = light ? 100 : 4;
        const cLow = light ? 96 : 10;
        const cBase = light ? 94 : 12;
        const cHigh = light ? 92 : 17;
        const cHighest = light ? 90 : 22;
        const sDim = light ? 87 : 6;
        const sBright = light ? 98 : 24;
        const onSurfVar = light ? 30 : 80;
        const surVar = light ? 90 : 20;
        const outl = light ? 50 : 62;
        const outlVar = light ? 80 : 28;
        const invSurf = light ? 20 : 90;
        const invOnSurf = light ? 95 : 20;

        const r = {};
        // Palette key colours
        r.m3primary_paletteKeyColor = tone(h, s, pKey);
        r.m3secondary_paletteKeyColor = tone(h, sh, pKey);
        r.m3tertiary_paletteKeyColor = tone(tHue, th, pKey);
        r.m3neutral_paletteKeyColor = tone(h, nS, 50);
        r.m3neutral_variant_paletteKeyColor = tone(h, nvS, 50);

        // Primary
        r.m3primary = tone(h, s, pKey);
        r.m3onPrimary = tone(h, s, pOnKey);
        r.m3primaryContainer = tone(h, s, pCont);
        r.m3onPrimaryContainer = tone(h, s, pOn);
        r.m3inversePrimary = tone(h, s, inv);
        r.m3surfaceTint = r.m3primary;

        // Secondary
        r.m3secondary = tone(h, sh, pKey);
        r.m3onSecondary = tone(h, sh, pOnKey);
        r.m3secondaryContainer = tone(h, sh, pCont);
        r.m3onSecondaryContainer = tone(h, sh, pOn);

        // Tertiary
        r.m3tertiary = tone(tHue, th, pKey);
        r.m3onTertiary = tone(tHue, th, pOnKey);
        r.m3tertiaryContainer = tone(tHue, th, pCont);
        r.m3onTertiaryContainer = tone(tHue, th, pOn);

        // Fixed variants
        r.m3primaryFixed = tone(h, s, 90);
        r.m3primaryFixedDim = tone(h, s, 80);
        r.m3onPrimaryFixed = tone(h, s, 10);
        r.m3onPrimaryFixedVariant = tone(h, s, 30);
        r.m3secondaryFixed = tone(h, sh, 90);
        r.m3secondaryFixedDim = tone(h, sh, 80);
        r.m3onSecondaryFixed = tone(h, sh, 10);
        r.m3onSecondaryFixedVariant = tone(h, sh, 30);
        r.m3tertiaryFixed = tone(tHue, th, 90);
        r.m3tertiaryFixedDim = tone(tHue, th, 80);
        r.m3onTertiaryFixed = tone(tHue, th, 10);
        r.m3onTertiaryFixedVariant = tone(tHue, th, 30);

        // Error (fixed hue)
        r.m3error = tone(0.99, 0.85, light ? 45 : 80);
        r.m3onError = tone(0.99, 0.85, light ? 100 : 20);
        r.m3errorContainer = tone(0.99, 0.8, light ? 90 : 35);
        r.m3onErrorContainer = tone(0.99, 0.85, light ? 10 : 90);

        // Success (fixed hue)
        r.m3success = tone(0.36, 0.45, light ? 40 : 80);
        r.m3onSuccess = tone(0.36, 0.45, light ? 100 : 20);
        r.m3successContainer = tone(0.36, 0.4, light ? 90 : 32);
        r.m3onSuccessContainer = tone(0.36, 0.5, light ? 10 : 90);

        // Surfaces / neutrals
        r.m3background = tone(h, nS, surf);
        r.m3onBackground = tone(h, nS, onSurf);
        r.m3surface = tone(h, nS, surf);
        r.m3surfaceDim = tone(h, nS, sDim);
        r.m3surfaceBright = tone(h, nS, sBright);
        r.m3surfaceContainerLowest = tone(h, nS, cLowest);
        r.m3surfaceContainerLow = tone(h, nS, cLow);
        r.m3surfaceContainer = tone(h, nS, cBase);
        r.m3surfaceContainerHigh = tone(h, nS, cHigh);
        r.m3surfaceContainerHighest = tone(h, nS, cHighest);
        r.m3onSurface = tone(h, nS, onSurf);
        r.m3surfaceVariant = tone(h, nvS, surVar);
        r.m3onSurfaceVariant = tone(h, nvS, onSurfVar);
        r.m3inverseSurface = tone(h, nS, invSurf);
        r.m3inverseOnSurface = tone(h, nS, invOnSurf);
        r.m3outline = tone(h, nvS, outl);
        r.m3outlineVariant = tone(h, nvS, outlVar);
        r.m3shadow = "#000000";
        r.m3scrim = "#000000";

        // Terminal ramp, derived from the same hues so schemes stay coherent.
        const termRoles = terminalRamp(h, s, nS, light);
        for (const [name, colour] of Object.entries(termRoles))
            r[name] = colour;

        return r;
    }
}
