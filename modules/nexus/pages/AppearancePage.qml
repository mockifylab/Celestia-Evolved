pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property var families: Qt.fontFamilies()

    readonly property string interfaceFamily: Config.appearance.font.body.family

    readonly property string monoFamily: Config.appearance.font.mono.family

    // Prepend the effective current family when it isn't a system font (e.g. the
    // bundled GoogleSansFlex resource) so it is always shown and selectable.
    readonly property var interfaceFontList: root.interfaceFamily && !root.families.includes(root.interfaceFamily) ? [root.interfaceFamily].concat(root.families) : root.families
    readonly property var monoFontList: root.monoFamily && !root.families.includes(root.monoFamily) ? [root.monoFamily].concat(root.families) : root.families

    // Custom colour theming
    readonly property list<string> seedPresets: ["#a8627b", "#5b6ee1", "#00897b", "#c77dff", "#ff6d00", "#e91e63", "#2e7d32", "#0288d1", "#8d6e63", "#607d8b"]

    readonly property list<MenuItem> modeItems: [
        MenuItem {
            text: Tr.tr("Auto")
            value: "auto"
        },
        MenuItem {
            text: Tr.tr("Light")
            value: "light"
        },
        MenuItem {
            text: Tr.tr("Dark")
            value: "dark"
        }
    ]

    readonly property list<MenuItem> sourceItems: [
        MenuItem {
            text: Tr.tr("Built-in Celestia palette")
            value: "builtin"
            icon: "palette"
        },
        MenuItem {
            text: Tr.tr("Colours derived from wallpaper")
            value: "wallpaper"
            icon: "image"
        },
        MenuItem {
            text: Tr.tr("Custom seed colour")
            value: "custom"
            icon: "adjust"
        },
        MenuItem {
            text: Tr.tr("Scheme file (external)")
            value: "scheme"
            icon: "file_download"
        }
    ]

    readonly property string currentSeed: GlobalConfig.appearance.colors.seed

    function clamp(v: real, lo: real, hi: real): real {
        return Math.max(lo, Math.min(hi, v));
    }

    // Honest description of what the wallpaper source is doing right now.
    function wallpaperStatusText(): string {
        switch (Colours.extractionState) {
        case "extracting":
            return Tr.tr("Extracting colours…");
        case "ok":
            return Tr.tr("Using %1 from %2").arg(Colours.wallpaperSeed).arg(Paths.shortenHome(Wallpapers.current));
        case "failed":
            return Colours.statusMessage || Tr.tr("Extraction failed");
        default:
            return Tr.tr("Not extracted yet");
        }
    }

    function setInterfaceFamily(family: string): void {
        GlobalConfig.appearance.font.headline.family = family;
        GlobalConfig.appearance.font.title.family = family;
        GlobalConfig.appearance.font.body.family = family;
        GlobalConfig.appearance.font.label.family = family;
    }

    function setMonoFamily(family: string): void {
        GlobalConfig.appearance.font.mono.family = family;
    }

    function isValidHex(v: string): bool {
        return /^#?[0-9a-fA-F]{6}$/.test(v.trim());
    }

    function setSeed(v: string): void {
        let t = v.trim();
        if (!t.startsWith("#"))
            t = `#${t}`;
        if (isValidHex(t))
            GlobalConfig.appearance.colors.seed = t.toLowerCase();
    }

    title: Tr.tr("Appearance")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Colors
        SectionHeader {
            first: true
            text: Tr.tr("Colors")
        }

        SelectRow {
            first: true
            label: Tr.tr("Palette source")
            subtext: Tr.tr("Which generator owns the shell palette")
            menuItems: root.sourceItems
            active: root.sourceItems.find(i => i.value === Colours.paletteSource) ?? null
            fallbackText: Colours.paletteSource
            onSelected: item => Colours.setPaletteSource(item.value)
        }

        SelectRow {
            visible: Colours.paletteSource === "builtin"
            label: Tr.tr("Built-in palette")
            subtext: Tr.tr("Coordinated dark and light Celestia palettes")
            menuItems: builtinPaletteItems.instances
            // qmllint disable missing-property
            active: builtinPaletteItems.instances.find(i => i.value === Colours.builtinPalette) ?? null
            fallbackText: BuiltinPalettes.label(Colours.builtinPalette)
            onSelected: item => Colours.setBuiltinPalette(item.value ?? "")
            // qmllint enable missing-property

            Variants {
                id: builtinPaletteItems

                model: BuiltinPalettes.defs

                MenuItem {
                    required property var modelData

                    text: modelData.label
                    icon: modelData.icon
                    value: modelData.id
                }
            }
        }

        ConnectedRect {
            visible: Colours.paletteSource === "custom"
            Layout.fillWidth: true
            implicitHeight: seedColumn.implicitHeight + Tokens.padding.medium * 2

            ColumnLayout {
                id: seedColumn

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    text: Tr.tr("Seed color")
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurface
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    Repeater {
                        model: root.seedPresets

                        delegate: Rectangle {
                            id: seedSwatch

                            required property string modelData

                            readonly property bool selected: root.currentSeed.toLowerCase() === modelData

                            width: 40
                            height: 40
                            radius: Tokens.rounding.medium
                            color: modelData
                            border.width: selected ? 3 : 1
                            border.color: selected ? Colours.palette.m3onSurface : Colours.palette.m3outlineVariant

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setSeed(seedSwatch.modelData)
                            }
                        }
                    }
                }
            }
        }

        TextFieldRow {
            visible: Colours.paletteSource === "custom"
            label: Tr.tr("Seed hex")
            subtext: Tr.tr("Any #rrggbb value")
            value: root.currentSeed
            errorText: Tr.tr("Invalid hex")
            validate: /^#?[0-9a-fA-F]{6}$/
            smallField: true
            onEditingFinished: v => root.setSeed(v)
        }

        InfoRow {
            visible: Colours.paletteSource === "wallpaper"
            label: Colours.extractionState === "failed" ? Tr.tr("Extraction failed") : Tr.tr("Wallpaper colours")
            value: root.wallpaperStatusText()
        }

        SelectRow {
            last: true
            label: Tr.tr("Mode")
            subtext: Tr.tr("Auto follows the wallpaper's brightness")
            menuItems: root.modeItems
            active: root.modeItems.find(i => i.value === GlobalConfig.appearance.colors.mode) ?? null
            fallbackText: GlobalConfig.appearance.colors.mode
            onSelected: item => Colours.setMode(item.value)
        }

        // Density
        SectionHeader {
            text: Tr.tr("Density")
        }

        SliderRow {
            first: true
            icon: "tune"
            label: Tr.tr("Interface scale")
            valueLabel: Math.round(Config.appearance.font.scale * 100) + "%"
            from: 0.5
            to: 2
            stepSize: 0.05
            value: Config.appearance.font.scale
            onMoved: v => GlobalConfig.appearance.font.scale = root.clamp(v, 0.5, 2)
        }

        SliderRow {
            icon: "memory"
            label: Tr.tr("Corner rounding")
            valueLabel: Math.round(Config.appearance.rounding.scale * 100) + "%"
            from: 0
            to: 2
            stepSize: 0.05
            value: Config.appearance.rounding.scale
            onMoved: v => GlobalConfig.appearance.rounding.scale = root.clamp(v, 0, 2)
        }

        SliderRow {
            icon: "expand_content"
            label: Tr.tr("Spacing")
            valueLabel: Math.round(Config.appearance.spacing.scale * 100) + "%"
            from: 0.5
            to: 2
            stepSize: 0.05
            value: Config.appearance.spacing.scale
            onMoved: v => GlobalConfig.appearance.spacing.scale = root.clamp(v, 0.5, 2)
        }

        SliderRow {
            last: true
            icon: "dashboard"
            label: Tr.tr("Padding")
            valueLabel: Math.round(Config.appearance.padding.scale * 100) + "%"
            from: 0.5
            to: 2
            stepSize: 0.05
            value: Config.appearance.padding.scale
            onMoved: v => GlobalConfig.appearance.padding.scale = root.clamp(v, 0.5, 2)
        }

        // Typography
        SectionHeader {
            text: Tr.tr("Typography")
        }

        SelectRow {
            first: true
            label: Tr.tr("Interface font")
            subtext: Tr.tr("Typeface used across the shell")
            fallbackText: root.interfaceFamily || Tr.tr("System default")
            menuItems: interfaceFontItems.instances
            active: interfaceFontItems.instances.find(i => i.modelData === root.interfaceFamily) ?? null
            // qmllint disable missing-property
            onSelected: item => root.setInterfaceFamily(item.modelData ?? "")
            // qmllint enable missing-property

            Variants {
                id: interfaceFontItems

                model: root.interfaceFontList

                MenuItem {
                    required property string modelData

                    text: modelData
                }
            }
        }

        SelectRow {
            last: true
            label: Tr.tr("Monospace font")
            subtext: Tr.tr("Typeface for terminal and code surfaces")
            fallbackText: root.monoFamily || Tr.tr("System default")
            menuItems: monoFontItems.instances
            active: monoFontItems.instances.find(i => i.modelData === root.monoFamily) ?? null
            // qmllint disable missing-property
            onSelected: item => root.setMonoFamily(item.modelData ?? "")
            // qmllint enable missing-property

            Variants {
                id: monoFontItems

                model: root.monoFontList

                MenuItem {
                    required property string modelData

                    text: modelData
                }
            }
        }

        // Transparency
        SectionHeader {
            text: Tr.tr("Transparency")
        }

        ToggleRow {
            first: true
            text: Tr.tr("Enable transparency")
            subtext: Tr.tr("Make panel and dialog surfaces translucent")
            checked: GlobalConfig.appearance.transparency.enabled
            onToggled: GlobalConfig.appearance.transparency.enabled = checked
        }

        SliderRow {
            icon: "web_asset"
            label: Tr.tr("Surface opacity")
            valueLabel: Math.round(GlobalConfig.appearance.transparency.base * 100) + "%"
            from: 0
            to: 1
            stepSize: 0.01
            enabled: GlobalConfig.appearance.transparency.enabled
            value: GlobalConfig.appearance.transparency.base
            onMoved: v => GlobalConfig.appearance.transparency.base = root.clamp(v, 0, 1)
        }

        SliderRow {
            last: true
            icon: "widgets"
            label: Tr.tr("Layer opacity")
            valueLabel: Math.round(GlobalConfig.appearance.transparency.layers * 100) + "%"
            from: 0
            to: 1
            stepSize: 0.01
            enabled: GlobalConfig.appearance.transparency.enabled
            value: GlobalConfig.appearance.transparency.layers
            onMoved: v => GlobalConfig.appearance.transparency.layers = root.clamp(v, 0, 1)
        }
    }
}
