pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Components
import Caelestia.Config
import Caelestia.I18n
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property string stateText: {
        switch (Updater.state) {
        case "checking":
            return Tr.tr("Checking for updates…");
        case "upToDate":
            return Tr.tr("You are up to date");
        case "available":
            return Tr.tr("Update available");
        case "downloading":
            return Tr.tr("Downloading update…");
        case "verifying":
            return Tr.tr("Verifying checksum…");
        case "staging":
            return Tr.tr("Staging update…");
        case "applying":
            return Tr.tr("Applying update…");
        case "applied":
            return Tr.tr("Update applied");
        case "rollingBack":
            return Tr.tr("Rolling back…");
        case "error":
            return Tr.tr("Update failed");
        default:
            return Tr.tr("Not checked yet");
        }
    }

    readonly property color statusColour: {
        switch (Updater.state) {
        case "error":
            return Colours.palette.m3error;
        case "upToDate":
        case "applied":
            return Colours.palette.m3success;
        case "available":
            return Colours.palette.m3primary;
        default:
            return Colours.palette.m3onSurfaceVariant;
        }
    }

    title: Tr.tr("Updates")

    Component.onCompleted: Updater.refreshRollbackStatus()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Current status
        SectionHeader {
            first: true
            text: Tr.tr("Status")
        }

        ConnectedRect {
            Layout.fillWidth: true
            implicitHeight: statusLayout.implicitHeight + Tokens.padding.extraLarge * 2

            ColumnLayout {
                id: statusLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                RowLayout {
                    spacing: Tokens.spacing.small

                    MaterialIcon {
                        text: Updater.busy ? "sync" : "system_update"
                        color: root.statusColour
                        fontStyle: Tokens.font.icon.large
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.stateText
                        color: root.statusColour
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    visible: Updater.message !== ""
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Updater.message
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                }
            }
        }

        // Versions
        SectionHeader {
            text: Tr.tr("Versions")
        }

        InfoRow {
            first: true
            label: Tr.tr("Installed")
            value: `v${Updater.currentVersion}` || "…"
        }

        InfoRow {
            label: Tr.tr("Latest")
            value: Updater.latestVersion !== "" ? `v${Updater.latestVersion}` : "—"
        }

        InfoRow {
            label: Tr.tr("Last checked")
            last: true
            value: Updater.lastChecked !== "" ? Updater.lastChecked : Tr.tr("Never")
        }

        // Release notes
        SectionHeader {
            visible: Updater.releaseNotes !== ""
            text: Tr.tr("Release notes")
        }

        ConnectedRect {
            visible: Updater.releaseNotes !== ""
            Layout.fillWidth: true
            implicitHeight: notesScroll.implicitHeight + Tokens.padding.large * 2

            StyledText {
                id: notesScroll

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                wrapMode: Text.WordWrap
                text: Updater.releaseNotes
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }
        }

        // Actions
        ButtonRow {
            Layout.topMargin: Tokens.spacing.medium
            Layout.alignment: Qt.AlignHCenter
            spacing: Tokens.spacing.small

            IconTextButton {
                icon: "refresh"
                text: Tr.tr("Check")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                enabled: !Updater.busy
                onClicked: Updater.check()
            }

            IconTextButton {
                icon: "download"
                text: Tr.tr("Update")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Tonal
                enabled: Updater.state === "available" || Updater.state === "error"
                visible: Updater.updateAvailable || Updater.state === "downloading" || Updater.state === "verifying" || Updater.state === "staging" || Updater.state === "applying"
                onClicked: {
                    if (Updater.state === "available")
                        Updater.download();
                }
            }

            IconTextButton {
                icon: "undo"
                text: Tr.tr("Roll back")
                font: Tokens.font.body.large
                isRound: true
                shapeMorph: true
                type: IconTextButton.Text
                enabled: Updater.rollbackAvailable && !Updater.busy
                visible: Updater.rollbackAvailable
                onClicked: Updater.rollback()
            }
        }

        StyledText {
            Layout.topMargin: Tokens.spacing.medium
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            text: Tr.tr("Updates are downloaded from the project's GitHub Releases and verified with a SHA-256 checksum before being applied. A backup of the current version is kept so any update can be rolled back.")
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
        }
    }
}
