pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Models
import qs.services
import qs.utils

Searcher {
    id: root

    readonly property string currentNamePath: `${Paths.state}/wallpaper/path.txt`
    readonly property list<string> smartArg: GlobalConfig.services.smartScheme ? [] : ["--no-smart"]
    readonly property string fallback: Quickshell.shellPath("assets/wallpaper.webp")

    property bool showPreview: false
    readonly property string current: showPreview ? previewPath : actualCurrent
    property string previewPath
    property string actualCurrent
    property bool previewColourLock
    property bool pendingPreviewClear

    // Colour analysis is the expensive part of a preview: it decodes an image
    // and regenerates a full palette. Holding an arrow key steps through a dozen
    // wallpapers a second, so analysis follows the selection the user settles on
    // instead of every intermediate step. The preview image itself stays instant.
    property string analysedPreviewPath
    property int previewAnalysisDelayMs: 150
    readonly property string analysedWallpaper: showPreview && analysedPreviewPath !== "" ? analysedPreviewPath : actualCurrent

    function getCategoryFor(w: FileSystemEntry): string {
        let category = w.parentDir.slice(Paths.wallsdir.length + 1);
        if (category.includes("/"))
            category = category.slice(0, category.indexOf("/"));
        return category;
    }

    function setRandom(): void {
        const entries = wallpapers.entries;
        if (entries.length === 0)
            return;
        const idx = Math.floor(Math.random() * entries.length);
        root.setWallpaper(entries[idx].path);
    }

    function setWallpaper(path: string): void {
        actualCurrent = path;
        // Persist the path for restoration on shell restart / reboot
        pathWriter.setText(path);
        // Colours listens for the actualCurrent change and regenerates the
        // palette when the wallpaper owns it (see Colours.handleWallpaperChange).
    }

    function preview(path: string): void {
        previewPath = path;
        showPreview = true;
        previewAnalysisTimer.restart();
    }

    // Runs for the settled selection only: the last wallpaper the cursor rested
    // on, not the ones scrolled past on the way there.
    function runPreviewAnalysis(): void {
        if (!showPreview || previewPath === "")
            return;
        analysedPreviewPath = previewPath;
        Colours.previewWallpaper(previewPath);
    }

    function stopPreview(): void {
        previewAnalysisTimer.stop();
        showPreview = false;
        if (previewColourLock)
            pendingPreviewClear = true;
        else
            Colours.showPreview = false;
    }

    onPreviewColourLockChanged: {
        if (!previewColourLock && pendingPreviewClear)
            Colours.showPreview = false;
    }

    list: wallpapers.entries
    key: "relativePath"
    useFuzzy: GlobalConfig.launcher.useFuzzy.wallpapers
    extraOpts: useFuzzy ? ({}) : ({
            forward: false
        })

    Timer {
        id: previewAnalysisTimer

        interval: root.previewAnalysisDelayMs
        onTriggered: root.runPreviewAnalysis()
    }

    IpcHandler {
        function get(): string {
            return root.actualCurrent;
        }

        function set(path: string): void {
            root.setWallpaper(path);
        }

        function list(): string {
            return root.list.map(w => w.path).join("\n");
        }

        target: "wallpaper"
    }

    FileView {
        id: pathWriter

        path: root.currentNamePath
        printErrors: false
    }

    FileView {
        path: root.currentNamePath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            let wall = text().trim();
            if (!wall)
                wall = root.fallback;
            root.actualCurrent = wall;
            root.previewColourLock = false;
        }
        onLoadFailed: {
            root.actualCurrent = root.fallback;
            root.previewColourLock = false;
        }
    }

    FileSystemModel {
        id: wallpapers

        recursive: true
        path: Paths.wallsdir
        filter: FileSystemModel.Images
    }
}
