import QtQuick
import Caelestia.Config
import qs.components

Item {
    id: root

    required property ScreenState screenState
    required property Item sidebarPanel
    property alias osdPanel: content.osdPanel
    property alias sessionPanel: content.sessionPanel
    property alias utilitiesPanel: content.utilitiesPanel

    readonly property bool placementBottom: GlobalConfig.notifs.placement === NotifPlacement.BottomLeft || GlobalConfig.notifs.placement === NotifPlacement.Bottom || GlobalConfig.notifs.placement === NotifPlacement.BottomRight

    visible: height > 0
    anchors.topMargin: placementBottom ? 0 : -5
    anchors.bottomMargin: placementBottom ? -5 : 0
    implicitWidth: Math.max(sidebarPanel.width, content.implicitWidth)
    implicitHeight: content.implicitHeight

    Content {
        id: content

        anchors.topMargin: -root.anchors.topMargin
        anchors.bottomMargin: -root.anchors.bottomMargin
        screenState: root.screenState
    }
}
