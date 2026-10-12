pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // Palette generation is entirely in-shell (ImageAnalyser + ColorGen), so the
    // only thing worth reporting here is what the current source actually did.
    readonly property string sourceLabel: {
        switch (Colours.paletteSource) {
        case "wallpaper":
            return Tr.tr("Wallpaper colours");
        case "custom":
            return Tr.tr("Custom seed colour");
        case "scheme":
            return Tr.tr("External scheme file");
        default:
            return Tr.tr("Built-in %1").arg(BuiltinPalettes.label(Colours.builtinPalette));
        }
    }

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

    readonly property var paletteRoles: [
        {
            name: Tr.tr("Primary"),
            colour: Colours.palette.m3primary
        },
        {
            name: Tr.tr("On primary"),
            colour: Colours.palette.m3onPrimary
        },
        {
            name: Tr.tr("Container"),
            colour: Colours.palette.m3primaryContainer
        },
        {
            name: Tr.tr("Secondary"),
            colour: Colours.palette.m3secondary
        },
        {
            name: Tr.tr("Tertiary"),
            colour: Colours.palette.m3tertiary
        },
        {
            name: Tr.tr("Error"),
            colour: Colours.palette.m3error
        },
        {
            name: Tr.tr("Success"),
            colour: Colours.palette.m3success
        },
        {
            name: Tr.tr("Surface"),
            colour: Colours.palette.m3surface
        },
        {
            name: Tr.tr("Elevated"),
            colour: Colours.palette.m3surfaceContainerHigh
        },
        {
            name: Tr.tr("Outline"),
            colour: Colours.palette.m3outline
        }
    ]

    function refreshFromWallpaper(): void {
        // Re-run the extraction instead of reusing the cached seed.
        Colours.setPaletteSource("wallpaper");
        Colours.refreshWallpaper();
    }

    title: Tr.tr("Colours")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Status of the active palette source
        SectionHeader {
            first: true
            text: Tr.tr("Status")
        }

        ConnectedRect {
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: statusLayout.implicitHeight + Tokens.padding.largeIncreased * 2

            ColumnLayout {
                id: statusLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.small

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: Colours.extractionState === "failed" || Colours.themeError !== "" ? "error" : "palette"
                        color: Colours.extractionState === "failed" || Colours.themeError !== "" ? Colours.palette.m3error : Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            Layout.fillWidth: true
                            text: root.sourceLabel
                            font: Tokens.font.title.medium
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: Colours.statusMessage !== "" ? Colours.statusMessage : Tr.tr("Palette is up to date")
                            color: Colours.statusMessage !== "" ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.body.small
                        }
                    }
                }

                InfoRow {
                    visible: Colours.paletteSource === "wallpaper" && Colours.wallpaperSeed !== ""
                    label: Tr.tr("Extracted seed")
                    value: Colours.wallpaperSeed
                }
            }
        }

        // Palette source
        SectionHeader {
            text: Tr.tr("Palette source")
        }

        SelectRow {
            first: true
            label: Tr.tr("Source")
            subtext: Tr.tr("Which generator owns the shell palette")
            menuItems: root.sourceItems
            active: root.sourceItems.find(i => i.value === Colours.paletteSource) ?? null
            fallbackText: Colours.paletteSource
            onSelected: item => Colours.setPaletteSource(item.value)
        }

        SelectRow {
            visible: Colours.paletteSource === "builtin"
            last: Colours.paletteSource !== "builtin"
            label: Tr.tr("Built-in palette")
            subtext: Tr.tr("Dark and light variants of the same design")
            menuItems: paletteItems.instances
            // qmllint disable missing-property
            active: paletteItems.instances.find(i => i.value === Colours.builtinPalette) ?? null
            fallbackText: BuiltinPalettes.label(Colours.builtinPalette)
            onSelected: item => Colours.setBuiltinPalette(item.value ?? "")
            // qmllint enable missing-property

            Variants {
                id: paletteItems

                model: BuiltinPalettes.defs

                MenuItem {
                    required property var modelData

                    text: modelData.label
                    icon: modelData.icon
                    value: modelData.id
                }
            }
        }

        SelectRow {
            last: Colours.paletteSource !== "scheme"
            label: Tr.tr("Mode")
            subtext: Tr.tr("Auto follows the wallpaper's brightness")
            menuItems: root.modeItems
            active: root.modeItems.find(i => i.value === GlobalConfig.appearance.colors.mode) ?? null
            fallbackText: GlobalConfig.appearance.colors.mode
            onSelected: item => Colours.setMode(item.value)
        }

        ConnectedRect {
            visible: Colours.paletteSource === "scheme"
            last: true
            Layout.fillWidth: true
            implicitHeight: schemeRow.implicitHeight + Tokens.padding.large * 2

            RowLayout {
                id: schemeRow

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        text: Tr.tr("Scheme")
                        font: Tokens.font.body.small
                    }

                    StyledText {
                        text: Colours.scheme || Tr.tr("Default")
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.extraSmall

                    StyledText {
                        text: Tr.tr("Variant")
                        font: Tokens.font.body.small
                    }

                    StyledText {
                        text: Colours.flavour || Tr.tr("None")
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.small
                    }
                }
            }
        }

        ButtonRow {
            visible: Colours.paletteSource === "wallpaper"
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.small
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "refresh"
                text: Tr.tr("Refresh from wallpaper")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: root.refreshFromWallpaper()
            }
        }

        // Live palette preview
        SectionHeader {
            text: Tr.tr("Current palette")
        }

        ConnectedRect {
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: paletteGrid.implicitHeight + Tokens.padding.largeIncreased * 2

            GridLayout {
                id: paletteGrid

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                columns: 5
                rowSpacing: Tokens.spacing.medium
                columnSpacing: Tokens.spacing.medium

                Repeater {
                    model: root.paletteRoles

                    ColumnLayout {
                        id: roleCell

                        required property var modelData

                        Layout.fillWidth: true
                        spacing: Tokens.spacing.extraSmall

                        StyledClippingRect {
                            Layout.fillWidth: true
                            implicitHeight: Tokens.padding.extraExtraLarge

                            color: roleCell.modelData.colour
                            radius: Tokens.rounding.medium
                            border.width: 1
                            border.color: Colours.palette.m3outlineVariant
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: roleCell.modelData.name
                            elide: Text.ElideRight
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                        }
                    }
                }
            }
        }
    }
}
