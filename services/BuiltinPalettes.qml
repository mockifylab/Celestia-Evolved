pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// Built-in Celestia palettes.
//
// Each entry is a curated set of parameters for the shell's own tonal design
// system (ColorGen), not a bag of hardcoded colours: every M3 role, including
// the terminal ramp, is generated from the palette's seed. That keeps built-in
// palettes and wallpaper-derived palettes visually consistent, and makes the
// dark/light variants of a palette differ only by mode, exactly as the
// wallpaper-derived path does.
Singleton {
    id: root

    readonly property string defaultId: "celestia"

    // id: stable key persisted in the theme state file
    // label: display name (not translated: they are proper names)
    // seed: accent seed colour
    // opts: design-system knobs (see ColorGen.roles)
    readonly property var defs: [
        {
            "id": "celestia",
            "label": "Celestia",
            "icon": "brightness_4",
            "seed": "#a8627b",
            "opts": {
                "sat": 0.55,
                "neutralSat": 0.06
            }
        },
        {
            "id": "dawn",
            "label": "Dawn",
            "icon": "light_mode",
            "seed": "#e08b52",
            "opts": {
                "sat": 0.52,
                "neutralSat": 0.05
            }
        },
        {
            "id": "verdant",
            "label": "Verdant",
            "icon": "forest",
            "seed": "#3f9d7a",
            "opts": {
                "sat": 0.48,
                "neutralSat": 0.045,
                "variantSat": 0.85
            }
        },
        {
            "id": "nocturne",
            "label": "Nocturne",
            "icon": "nightlight",
            "seed": "#6f7dd8",
            "opts": {
                "sat": 0.5,
                "neutralSat": 0.04,
                "variantSat": 0.9
            }
        }
    ]

    readonly property list<string> ids: root.defs.map(d => d.id)

    function def(paletteId: string): var {
        for (const d of root.defs) {
            if (d.id === paletteId)
                return d;
        }
        return null;
    }

    function isKnown(paletteId: string): bool {
        return root.def(paletteId) !== null;
    }

    function label(paletteId: string): string {
        const d = root.def(paletteId);
        return d === null ? paletteId : d.label;
    }

    function icon(paletteId: string): string {
        const d = root.def(paletteId);
        return d === null ? "palette" : d.icon;
    }

    // Full role map for a built-in palette in the given mode. Returns an empty
    // map for an unknown id so callers can detect the failure instead of
    // applying a half-built palette.
    function roles(paletteId: string, light: bool): var {
        const d = root.def(paletteId);
        if (d === null)
            return {};
        return ColorGen.roles(d.seed, light, d.opts);
    }
}
