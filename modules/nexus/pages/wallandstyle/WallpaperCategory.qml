pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    // Incremental reveal: only instantiate/decode wallpapers near the viewport
    // instead of the whole category up front (see WallpaperSelect for rationale).
    readonly property int perRow: Config.nexus.wallpapersPerRow
    property int revealed: perRow * 3

    readonly property var fullList: Wallpapers.list.filter(w => Wallpapers.getCategoryFor(w) === root.nState.selectedWallpaperCategory).sort((a, b) => a.name.localeCompare(b.name))

    function growChunk(): void {
        if (root.revealed < root.fullList.length)
            root.revealed += root.perRow * 3;
    }

    function ensureFilled(): void {
        const f = root.flickable;
        if (f && f.contentHeight > 0 && f.contentHeight <= f.height)
            root.growChunk();
    }

    title: {
        const c = nState.selectedWallpaperCategory;
        return c.slice(0, 1).toUpperCase() + c.slice(1);
    }
    isSubPage: true

    onFullListChanged: revealed = perRow * 3

    GridLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth

        columns: Config.nexus.wallpapersPerRow
        rowSpacing: Tokens.spacing.medium
        columnSpacing: Tokens.spacing.large

        Connections {
            function onContentYChanged(): void {
                const f = root.flickable;
                if (f && f.contentY + f.height >= f.contentHeight - f.height)
                    root.growChunk();
            }

            function onContentHeightChanged(): void {
                root.ensureFilled();
            }

            target: root.flickable
        }

        Repeater {
            model: {
                const view = root.fullList.slice(0, root.revealed);
                while (view.length < root.perRow)
                    view.push(null);
                return view;
            }

            WallItem {
                required property FileSystemEntry modelData

                // Empty placeholders for sizing
                opacity: modelData ? 1 : 0
                enabled: modelData

                source: String(modelData?.path ?? "")
                text: modelData?.name ?? ""
                onClicked: {
                    Wallpapers.setWallpaper(modelData.path);
                    root.nState.closeSubPage();
                    root.nState.closeSubPage();
                }
            }
        }
    }
}
