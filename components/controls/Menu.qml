pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.effects
import qs.services
import qs.modules.drawers

MouseArea {
    id: root

    enum Side {
        Top,
        Bottom,
        Left,
        Right
    }

    required property Item attachTo
    property int attachSideX: Menu.Right
    property int attachSideY: Menu.Bottom
    property int thisSideX: Menu.Right
    property int thisSideY: Menu.Top
    property real marginX
    property real marginY

    property list<MenuItem> items
    property MenuItem active: items[0] ?? null
    property bool expanded

    // A menu can hold thousands of entries (every font family installed), so it
    // may never be taller than the surface it floats on.
    readonly property real maxContentHeight: root.parent && root.parent.height > 0 ? Math.max(180, root.parent.height * 0.6) : 400

    signal itemSelected(item: MenuItem)

    parent: {
        const win = QsWindow.window;
        const contentWin = win as ContentWindow; // If inside the drawer content window, put it inside the interaction wrapper so hover works
        return contentWin ? contentWin.interactionWrapper : (win as QsWindow).contentItem;
    }
    anchors.fill: parent

    enabled: expanded
    hoverEnabled: expanded
    cursorShape: expanded ? Qt.ArrowCursor : undefined
    onClicked: expanded = false

    opacity: expanded ? 1 : 0
    layer.enabled: opacity < 1

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    TransformWatcher {
        id: watcher

        a: root.parent
        b: root.attachTo
    }

    Elevation {
        id: menu

        x: {
            watcher.transform; // mapToItem is not reactive so this forces updates
            const item = root.attachTo;
            let off = root.attachSideX === Menu.Left ? 0 : item.width;
            if (root.thisSideX === Menu.Right)
                off -= width;
            return item.mapToItem(root.parent, off, 0).x + root.marginX;
        }
        y: {
            watcher.transform; // mapToItem is not reactive so this forces updates
            const item = root.attachTo;
            let off = root.attachSideY === Menu.Top ? 0 : item.height;
            if (root.thisSideY === Menu.Bottom)
                off -= height;
            return item.mapToItem(root.parent, 0, off).y + root.marginY;
        }

        radius: Tokens.rounding.large
        level: 2

        // Collapsed menus have no content at all, so they cost nothing.
        implicitWidth: contentLoader.active ? contentLoader.implicitWidth : 200
        implicitHeight: contentLoader.active ? contentLoader.implicitHeight : 0

        transform: Scale {
            yScale: root.expanded ? 1 : 0.1
            origin.y: root.thisSideY === Menu.Bottom ? menu.height : 0

            Behavior on yScale {
                Anim {}
            }
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onWheel: e => e.accepted = true
        }

        Loader {
            id: contentLoader

            anchors.centerIn: parent
            active: root.expanded
            width: contentLoader.implicitWidth
            height: contentLoader.implicitHeight
            sourceComponent: menuContent
        }
    }

    // Built on first expansion and virtualised: the rows a menu holds are not
    // the rows it shows, and realising all of them at page load is what made
    // the Appearance settings take a noticeable moment to open.
    Component {
        id: menuContent

        Item {
            id: content

            // One TextMetrics pass over the longest label (character count is a
            // good proxy for width within a single font) sizes the menu to its
            // content without measuring every entry.
            readonly property string widestLabel: {
                let best = "";
                const n = root.items.length;
                for (let i = 0; i < n; i++) {
                    const t = root.items[i]?.text ?? "";
                    if (t.length > best.length)
                        best = t;
                }
                return best;
            }

            // Icon columns are measured with the icon font itself rather than
            // assumed, so rows never clip their leading or trailing glyph.
            readonly property real iconAllowance: iconMetrics.advanceWidth + Tokens.spacing.small
            readonly property real availableWidth: root.parent && root.parent.width > 0 ? root.parent.width - Tokens.spacing.large : 420

            implicitWidth: Math.min(content.availableWidth, Math.max(200, Math.ceil(labelMetrics.advanceWidth) + Tokens.padding.medium * 2 + content.iconAllowance * 2))
            implicitHeight: Math.min(list.contentHeight + Tokens.padding.extraSmall * 2, root.maxContentHeight)

            TextMetrics {
                id: labelMetrics

                font: Tokens.font.body.small
                text: content.widestLabel
            }

            TextMetrics {
                id: iconMetrics

                font: Tokens.font.icon.small
                text: "settings"
            }

            StyledRect {
                anchors.fill: parent
                radius: menu.radius
                color: Colours.palette.m3surfaceContainerLow

                ListView {
                    id: list

                    anchors.fill: parent
                    anchors.margins: Tokens.padding.extraSmall
                    model: root.items
                    spacing: 0
                    clip: true
                    cacheBuffer: 400
                    boundsBehavior: Flickable.StopAtBounds
                    interactive: contentHeight > height

                    delegate: StyledRect {
                        id: item

                        required property int index
                        required property MenuItem modelData
                        readonly property bool active: modelData === root?.active

                        implicitWidth: list.width
                        implicitHeight: menuOptionRow.implicitHeight + Tokens.padding.medium * 2
                        height: implicitHeight

                        radius: active ? Tokens.rounding.medium : Tokens.rounding.extraSmall
                        topLeftRadius: index === 0 ? Tokens.rounding.medium : radius
                        topRightRadius: index === 0 ? Tokens.rounding.medium : radius
                        bottomLeftRadius: index === list.count - 1 ? Tokens.rounding.medium : radius
                        bottomRightRadius: index === list.count - 1 ? Tokens.rounding.medium : radius

                        color: Qt.alpha(Colours.palette.m3tertiaryContainer, active ? 1 : 0)

                        Behavior on radius {
                            Anim {}
                        }

                        StateLayer {
                            topLeftRadius: parent.topLeftRadius
                            topRightRadius: parent.topRightRadius
                            bottomLeftRadius: parent.bottomLeftRadius
                            bottomRightRadius: parent.bottomRightRadius

                            color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                            disabled: !root.expanded
                            onClicked: {
                                root.itemSelected(item.modelData);
                                root.active = item.modelData;
                                item.modelData.clicked();
                                root.expanded = false;
                            }
                        }

                        RowLayout {
                            id: menuOptionRow

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                Layout.alignment: Qt.AlignVCenter
                                text: item.modelData?.icon ?? ""
                                color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                text: item.modelData?.text ?? ""
                                color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                            }

                            Loader {
                                asynchronous: true
                                Layout.alignment: Qt.AlignVCenter
                                active: item.modelData?.trailingIcon.length > 0
                                visible: active

                                sourceComponent: MaterialIcon {
                                    text: item.modelData.trailingIcon
                                    color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
