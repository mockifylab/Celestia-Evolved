pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import "sliderMapping.js" as SliderMap
import "../../../utils/writeThrottle.js" as WriteThrottle

ConnectedRect {
    id: root

    property alias icon: icon.text
    property alias label: label.text
    property alias valueLabel: valueLabel.text
    property real value
    property real from: 0
    property real to: 1
    property real stepSize: 0

    // Pointer samples arrive at display refresh rate, but each outward value is
    // a settings write and a write can restyle the whole shell. Writes are
    // limited to one per interval during a drag; the newest suppressed value is
    // always applied once the drag pauses, so nothing is lost. The handle and
    // the filled track follow the pointer directly and are never delayed.
    property int writeIntervalMs: 40

    // The throttle keeps its own small state object. It is mutated in place by
    // the shared helper, so it must not be re-assigned here.
    property var throttleState: WriteThrottle.create(root.writeIntervalMs)

    signal moved(value: real)

    // Wheel steps are discrete and computed from the stored value, so they are
    // applied immediately rather than coalesced.
    function stepBy(delta: real): void {
        const step = root.stepSize > 0 ? root.stepSize : GlobalConfig.services.audioIncrement;
        const next = delta > 0 ? root.value + step : root.value - step;
        root.moved(SliderMap.clamp(SliderMap.snap(next, root.from, step), root.from, root.to));
    }

    function pushWrite(v: real): void {
        const st = root.throttleState;
        st.interval = Math.max(0, root.writeIntervalMs);
        const immediate = WriteThrottle.push(st, Date.now(), v);
        if (immediate !== null)
            root.moved(immediate);
        else if (!flushTimer.running)
            flushTimer.restart();
    }

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins + rowLayout.anchors.topMargin

    Timer {
        id: flushTimer

        interval: Math.max(8, root.writeIntervalMs)
        onTriggered: {
            const st = root.throttleState;
            const trailing = WriteThrottle.take(st, Date.now());
            if (trailing === null)
                return;
            root.moved(trailing);
            if (WriteThrottle.hasPending(st))
                flushTimer.restart();
        }
    }

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
                    if (event.angleDelta.y !== 0)
                        root.stepBy(event.angleDelta.y);
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
                    onInteraction: v => root.pushWrite(SliderMap.positionToValue(v, root.from, root.to, root.stepSize))
                }
            }
        }
    }
}
