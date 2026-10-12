pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import "sliderMapping.js" as SliderMap

ConnectedRect {
    id: root

    property alias icon: icon.text
    property alias label: label.text
    property alias valueLabel: valueLabel.text
    property real value
    property real from: 0
    property real to: 1
    property real stepSize: 0

    signal moved(value: real)

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins + rowLayout.anchors.topMargin

    RowLayout {
        id: rowLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.largeIncreased
        anchors.topMargin: Tokens.padding.large
        spacing: Tokens.spacing.medium

        MaterialIcon {
            id: icon

            color: Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.medium
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                StyledText {
                    id: label

                    Layout.fillWidth: true
                    font: Tokens.font.body.small
                    elide: Text.ElideRight
                }

                StyledText {
                    id: valueLabel

                    color: Colours.palette.m3outline
                    font: Tokens.font.body.small
                }
            }

            CustomMouseArea {
                function onWheel(event: WheelEvent): void {
                    const step = root.stepSize > 0 ? root.stepSize : GlobalConfig.services.audioIncrement;
                    if (event.angleDelta.y > 0)
                        root.moved(SliderMap.clamp(SliderMap.snap(root.value + step, root.from, step), root.from, root.to));
                    else if (event.angleDelta.y < 0)
                        root.moved(SliderMap.clamp(SliderMap.snap(root.value - step, root.from, step), root.from, root.to));
                }

                Layout.fillWidth: true
                implicitHeight: Tokens.padding.medium * 2

                StyledSlider {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    implicitHeight: parent.implicitHeight

                    radius: Tokens.rounding.small
                    from: root.from
                    to: root.to
                    stepSize: root.stepSize > 0 ? root.stepSize : 0
                    // Validate out-of-range programmatic/restore values so the
                    // handle can never sit at a position that disagrees with the
                    // stored setting.
                    value: SliderMap.clamp(root.value, root.from, root.to)
                    enabled: root.enabled
                    onInteraction: v => root.moved(SliderMap.positionToValue(v, root.from, root.to, root.stepSize))
                }
            }
        }
    }
}
