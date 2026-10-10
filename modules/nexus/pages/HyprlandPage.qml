import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // Live values come from `hyprctl descriptions` via the Hypr service; writes go
    // back through Hyprland IPC so they apply immediately and stay in sync.
    readonly property var opts: Hypr.options

    readonly property string configPath: `${Quickshell.env("HYPRLAND_CONFIG_REQUEST") || `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/hypr/hyprland.conf`}`

    readonly property list<MenuItem> accelItems: [
        MenuItem {
            text: Tr.tr("Adaptive")
            value: 0
        },
        MenuItem {
            text: Tr.tr("Linear")
            value: 1
        },
        MenuItem {
            text: Tr.tr("Legacy")
            value: 2
        }
    ]

    function opt(key: string, def: real): real {
        const v = root.opts[key];
        return (v === undefined || v === null) ? def : Number(v);
    }

    function optBool(key: string, def: bool): bool {
        const v = root.opts[key];
        return (v === undefined || v === null) ? def : Number(v) !== 0;
    }

    function setOpt(key: string, value: var): void {
        const o = {};
        o[key] = value;
        Hypr.extras.applyOptions(o);
    }

    title: Tr.tr("Hyprland")

    Component.onCompleted: Hypr.extras.refreshOptions()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            id: backupProc

            command: ["sh", "-c", `cp '${root.configPath}' '${root.configPath}.bak.$(date +%Y%m%d-%H%M%S)'`]
            onRunningChanged: if (!running)
                Hypr.extras.refreshOptions()
        }

        Process {
            id: reloadProc

            command: ["hyprctl", "reload"]
            onRunningChanged: if (!running)
                Hypr.extras.refreshOptions()
        }

        // Live-compositor notice
        ConnectedRect {
            first: true
            last: true
            Layout.fillWidth: true
            implicitHeight: noticeLayout.implicitHeight + Tokens.padding.largeIncreased * 2

            RowLayout {
                id: noticeLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    Layout.alignment: Qt.AlignTop
                    Layout.topMargin: Tokens.padding.extraSmall
                    text: "priority_high"
                    color: Colours.palette.m3tertiary
                    fontStyle: Tokens.font.icon.medium
                }

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Tr.tr("These change the running Hyprland compositor immediately. They are not written to your config file, so a Hyprland restart reverts them unless you save them to your configuration.")
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }

        // Window decorations
        SectionHeader {
            text: Tr.tr("Window decorations")
        }

        SliderRow {
            first: true
            icon: "expand_content"
            label: Tr.tr("Inner gaps")
            valueLabel: Math.round(root.opt("general:gaps_in", 8)) + "px"
            from: 0
            to: 40
            stepSize: 1
            value: root.opt("general:gaps_in", 8)
            onMoved: v => root.setOpt("general:gaps_in", Math.round(v))
        }

        SliderRow {
            icon: "web_asset"
            label: Tr.tr("Outer gaps")
            valueLabel: Math.round(root.opt("general:gaps_out", 8)) + "px"
            from: 0
            to: 40
            stepSize: 1
            value: root.opt("general:gaps_out", 8)
            onMoved: v => root.setOpt("general:gaps_out", Math.round(v))
        }

        SliderRow {
            icon: "memory"
            label: Tr.tr("Border size")
            valueLabel: Math.round(root.opt("general:border_size", 1)) + "px"
            from: 0
            to: 8
            stepSize: 1
            value: root.opt("general:border_size", 1)
            onMoved: v => root.setOpt("general:border_size", Math.round(v))
        }

        SliderRow {
            icon: "widgets"
            label: Tr.tr("Corner rounding")
            valueLabel: Math.round(root.opt("decoration:rounding", 0)) + "px"
            from: 0
            to: 30
            stepSize: 1
            value: root.opt("decoration:rounding", 0)
            onMoved: v => root.setOpt("decoration:rounding", Math.round(v))
        }

        SliderRow {
            icon: "tune"
            label: Tr.tr("Active window opacity")
            valueLabel: Math.round(root.opt("decoration:active_opacity", 1) * 100) + "%"
            from: 0.2
            to: 1
            stepSize: 0.01
            value: root.opt("decoration:active_opacity", 1)
            onMoved: v => root.setOpt("decoration:active_opacity", v)
        }

        ToggleRow {
            text: Tr.tr("Window shadows")
            subtext: Tr.tr("Drop shadows behind windows")
            checked: root.optBool("decoration:shadow:enabled", true)
            onToggled: root.setOpt("decoration:shadow:enabled", checked ? 1 : 0)
        }

        ToggleRow {
            last: true
            text: Tr.tr("Background blur")
            subtext: Tr.tr("Blur the wallpaper behind translucent surfaces")
            checked: root.optBool("decoration:blur:enabled", true)
            onToggled: root.setOpt("decoration:blur:enabled", checked ? 1 : 0)
        }

        // Animations and effects
        SectionHeader {
            text: Tr.tr("Animations and effects")
        }

        ToggleRow {
            first: true
            last: true
            text: Tr.tr("Compositor animations")
            subtext: Tr.tr("Hyprland window movement animations (independent of shell motion)")
            checked: root.optBool("animations:enabled", true)
            onToggled: root.setOpt("animations:enabled", checked ? 1 : 0)
        }

        // Workspaces
        SectionHeader {
            text: Tr.tr("Workspaces")
        }

        SliderRow {
            first: true
            icon: "view_kanban"
            label: Tr.tr("Workspace gaps")
            valueLabel: Math.round(root.opt("general:gaps_workspaces", 0)) + "px"
            from: 0
            to: 40
            stepSize: 1
            value: root.opt("general:gaps_workspaces", 0)
            onMoved: v => root.setOpt("general:gaps_workspaces", Math.round(v))
        }

        ToggleRow {
            text: Tr.tr("Wraparound navigation")
            subtext: Tr.tr("Slide from the first to the last workspace and back")
            checked: root.optBool("animations:workspace_wraparound", false)
            onToggled: root.setOpt("animations:workspace_wraparound", checked ? 1 : 0)
        }

        ToggleRow {
            text: Tr.tr("Invert swipe direction")
            subtext: Tr.tr("Reverse the touchpad workspace-swipe direction")
            checked: root.optBool("gestures:workspace_swipe_invert", false)
            onToggled: root.setOpt("gestures:workspace_swipe_invert", checked ? 1 : 0)
        }

        ToggleRow {
            last: true
            text: Tr.tr("Create workspace on swipe")
            subtext: Tr.tr("Swiping past the last workspace opens a new one")
            checked: root.optBool("gestures:workspace_swipe_create_new", true)
            onToggled: root.setOpt("gestures:workspace_swipe_create_new", checked ? 1 : 0)
        }

        // Pointer and input
        SectionHeader {
            text: Tr.tr("Pointer and input")
        }

        SliderRow {
            first: true
            icon: "tune"
            label: Tr.tr("Mouse sensitivity")
            valueLabel: root.opt("input:sensitivity", 1).toFixed(2)
            from: 0.1
            to: 2
            stepSize: 0.05
            value: root.opt("input:sensitivity", 1)
            onMoved: v => root.setOpt("input:sensitivity", v)
        }

        ToggleRow {
            text: Tr.tr("Natural scroll")
            subtext: Tr.tr("Invert touchpad scroll direction")
            checked: root.optBool("input:touchpad:natural_scroll", false)
            onToggled: root.setOpt("input:touchpad:natural_scroll", checked ? 1 : 0)
        }

        ToggleRow {
            text: Tr.tr("Tap to click")
            subtext: Tr.tr("Click by tapping the touchpad")
            checked: root.optBool("input:touchpad:tap-to-click", false)
            onToggled: root.setOpt("input:touchpad:tap-to-click", checked ? 1 : 0)
        }

        SelectRow {
            last: true
            label: Tr.tr("Pointer acceleration")
            subtext: Tr.tr("How cursor speed responds to movement")
            menuItems: root.accelItems
            active: root.accelItems.find(i => i.value === Math.round(root.opt("input:accel_profile", 0))) ?? null
            onSelected: item => root.setOpt("input:accel_profile", item.value)
        }

        // Configuration management
        SectionHeader {
            text: Tr.tr("Configuration")
        }

        ConnectedRect {
            first: true
            Layout.fillWidth: true
            implicitHeight: cfgCol.implicitHeight + Tokens.padding.large * 2

            ColumnLayout {
                id: cfgCol

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.extraSmall

                StyledText {
                    text: Tr.tr("Config file")
                    font: Tokens.font.body.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.configPath
                    elide: Text.ElideMiddle
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                }
            }
        }

        ButtonRow {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "folder"
                text: Tr.tr("Backup")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: backupProc.running = true
            }

            IconTextButton {
                icon: "refresh"
                text: Tr.tr("Reload")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                horizontalPadding: Tokens.padding.extraLarge
                verticalPadding: Tokens.padding.medium
                onClicked: reloadProc.running = true
            }
        }
    }
}
