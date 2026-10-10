pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // Baseline (default) expressive spatial curves. Overshoot is scaled relative to
    // these so the shell keeps its characteristic springy morph.
    readonly property var baseSpatial: ({
            fast: [0.42, 1.67, 0.21, 0.90, 1, 1],
            def: [0.38, 1.21, 0.22, 1.00, 1, 1],
            slow: [0.39, 1.29, 0.35, 0.98, 1, 1]
        })

    readonly property var profiles: ({
            balanced: {
                scale: 1.00,
                deform: 1.00,
                over: 1.00
            },
            smooth: {
                scale: 1.25,
                deform: 1.00,
                over: 0.85
            },
            expressive: {
                scale: 1.05,
                deform: 1.50,
                over: 1.40
            },
            minimal: {
                scale: 0.65,
                deform: 0.40,
                over: 0.35
            },
            reduced: {
                scale: 0.00,
                deform: 0.00,
                over: 0.00
            }
        })

    readonly property list<MenuItem> profileItems: [
        MenuItem {
            text: Tr.tr("Balanced")
            value: "balanced"
        },
        MenuItem {
            text: Tr.tr("Smooth")
            value: "smooth"
        },
        MenuItem {
            text: Tr.tr("Expressive")
            value: "expressive"
        },
        MenuItem {
            text: Tr.tr("Minimal")
            value: "minimal"
        },
        MenuItem {
            text: Tr.tr("Reduced Motion")
            value: "reduced"
        }
    ]

    readonly property real currentOvershoot: {
        const c = TokenConfig.appearance.curves.expressiveDefaultSpatial;
        if (!c || c.length < 2)
            return 1;
        return (c[1] - 1) / (root.baseSpatial.def[1] - 1);
    }

    function clamp(v: real, lo: real, hi: real): real {
        return Math.max(lo, Math.min(hi, v));
    }

    function applyOvershoot(factor: real): void {
        const f = root.clamp(factor, 0, 1.6);
        const mk = b => [b[0], 1 + (b[1] - 1) * f, b[2], 1 + (b[3] - 1) * f, b[4], b[5]];
        TokenConfig.appearance.curves.expressiveFastSpatial = mk(root.baseSpatial.fast);
        TokenConfig.appearance.curves.expressiveDefaultSpatial = mk(root.baseSpatial.def);
        TokenConfig.appearance.curves.expressiveSlowSpatial = mk(root.baseSpatial.slow);
    }

    function applyProfile(id: string): void {
        const p = root.profiles[id];
        if (!p)
            return;

        GlobalConfig.appearance.anim.durations.scale = p.scale;
        GlobalConfig.appearance.deformScale = p.deform;
        root.applyOvershoot(p.over);
    }

    function currentProfileId(): string {
        const s = GlobalConfig.appearance.anim.durations.scale;
        const d = Config.appearance.deformScale;
        for (const key of Object.keys(root.profiles)) {
            const p = root.profiles[key];
            if (Math.abs(s - p.scale) < 0.02 && Math.abs(d - p.deform) < 0.02)
                return key;
        }
        return "";
    }

    title: Tr.tr("Motion")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Presets
        SectionHeader {
            first: true
            text: Tr.tr("Motion profile")
        }

        SelectRow {
            first: true
            last: true
            label: Tr.tr("Profile")
            subtext: Tr.tr("A tuned bundle of speed, morph and spring settings")
            fallbackText: Tr.tr("Custom")
            menuItems: root.profileItems
            active: root.profileItems.find(i => i.value === root.currentProfileId()) ?? customItem
            onSelected: item => root.applyProfile(item.value)

            MenuItem {
                id: customItem

                text: Tr.tr("Custom")
            }
        }

        // Fine tuning
        SectionHeader {
            text: Tr.tr("Fine tuning")
        }

        SliderRow {
            first: true
            icon: "speed"
            label: Tr.tr("Animation speed")
            valueLabel: Math.round(GlobalConfig.appearance.anim.durations.scale * 100) + "%"
            from: 0
            to: 2
            stepSize: 0.05
            value: GlobalConfig.appearance.anim.durations.scale
            onMoved: v => GlobalConfig.appearance.anim.durations.scale = root.clamp(v, 0, 2)
        }

        SliderRow {
            icon: "animation"
            label: Tr.tr("Morph fluidity")
            valueLabel: Math.round(Config.appearance.deformScale * 100) + "%"
            from: 0
            to: 2
            stepSize: 0.05
            value: Config.appearance.deformScale
            onMoved: v => GlobalConfig.appearance.deformScale = root.clamp(v, 0, 2)
        }

        SliderRow {
            last: true
            icon: "expand_content"
            label: Tr.tr("Spring overshoot")
            valueLabel: Math.round(root.currentOvershoot * 100) + "%"
            from: 0
            to: 1.6
            stepSize: 0.05
            value: root.currentOvershoot
            onMoved: v => root.applyOvershoot(v)
        }

        // Accessibility
        SectionHeader {
            text: Tr.tr("Accessibility")
        }

        ToggleRow {
            first: true
            last: true
            text: Tr.tr("Reduced motion")
            subtext: Tr.tr("Minimise non-essential animation across the shell")
            checked: GlobalConfig.appearance.anim.durations.scale <= 0.05
            onToggled: checked ? root.applyProfile("reduced") : root.applyProfile("balanced")
        }
    }
}
