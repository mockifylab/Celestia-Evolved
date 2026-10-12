pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Images
import qs.services
import qs.utils

Singleton {
    id: root

    property bool showPreview
    property string scheme
    property string flavour
    readonly property bool light: showPreview ? previewLight : currentLight
    property bool currentLight
    property bool previewLight
    readonly property M3Palette palette: showPreview ? preview : current
    readonly property M3TPalette tPalette: M3TPalette {}
    readonly property M3Palette current: M3Palette {}
    readonly property M3Palette preview: M3Palette {}
    readonly property Transparency transparency: Transparency {}
    readonly property alias wallLuminance: analyser.luminance

    property bool cooldownPending
    property real lastBaseTransparency

    // --- Palette sources (v1.0.2) ---
    // Which generator owns the live palette. The choice is stored in shell
    // state (`theme.json`) so it survives restarts and does not depend on a
    // rebuilt config plugin:
    //   builtin   curated in-shell Celestia palette (see BuiltinPalettes)
    //   wallpaper colours extracted from the active wallpaper
    //   custom    legacy: seed colour picked in the Appearance settings
    //   scheme    legacy: scheme.json written by an external tool
    readonly property list<string> paletteSourceIds: ["builtin", "wallpaper", "custom", "scheme"]
    property string paletteSource: "builtin"
    property string builtinPalette: BuiltinPalettes.defaultId
    // Extraction bookkeeping for the wallpaper source. `extractionState` is
    // idle | extracting | ok | failed: failures are surfaced to the user and
    // never replaced by a fabricated palette.
    property string extractionState: "idle"
    property string extractionError: ""
    property string themeError: ""
    property string wallpaperSeed: ""
    property string wallpaperSeedPath: ""
    property string pendingWallpaper: ""
    property var wallpaperCache: ({})
    readonly property string themeStatePath: `${Paths.state}/theme.json`
    property bool themeStateLoaded
    property bool themeStateMissing
    property bool schemeAvailable
    // Whether the palette currently on screen came from a real source.
    readonly property string statusMessage: root.themeError !== "" ? root.themeError : root.extractionError

    function getLuminance(c: color): real {
        if (c.r == 0 && c.g == 0 && c.b == 0)
            return 0;
        return Math.sqrt(0.299 * (c.r ** 2) + 0.587 * (c.g ** 2) + 0.114 * (c.b ** 2));
    }

    function alterColour(c: color, a: real, layer: int): color {
        const luminance = getLuminance(c);

        const offset = (!light || layer == 1 ? 1 : -layer / 2) * (light ? 0.2 : 0.3) * (1 - transparency.base) * (1 + wallLuminance * (light ? (layer == 1 ? 3 : 1) : 2.5));
        const scale = (luminance + offset) / luminance;
        const r = Math.max(0, Math.min(1, c.r * scale));
        const g = Math.max(0, Math.min(1, c.g * scale));
        const b = Math.max(0, Math.min(1, c.b * scale));

        return Qt.rgba(r, g, b, a);
    }

    function layer(c: color, layer: var): color {
        if (!transparency.enabled)
            return c;

        return layer === 0 ? Qt.alpha(c, transparency.base) : alterColour(c, transparency.layers, layer ?? 1);
    }

    function on(c: color): color {
        if (c.hslLightness < 0.5)
            return Qt.hsla(c.hslHue, c.hslSaturation, 0.9, 1);
        return Qt.hsla(c.hslHue, c.hslSaturation, 0.1, 1);
    }

    function load(data: string, isPreview: bool): void {
        // scheme.json is only authoritative when the user selects that source;
        // otherwise an external generator must not fight the in-shell palette.
        if (!isPreview && root.paletteSource !== "scheme")
            return;

        const colours = isPreview ? preview : current;
        const scheme = JSON.parse(data);

        if (!isPreview) {
            root.scheme = scheme.name;
            flavour = scheme.flavour;
            currentLight = scheme.mode === "light";
        } else {
            previewLight = scheme.mode === "light";
        }

        for (const [name, colour] of Object.entries(scheme.colours)) {
            const propName = name.startsWith("term") ? name : `m3${name}`;
            if (colours.hasOwnProperty(propName))
                colours[propName] = `#${colour}`;
        }
    }

    function setMode(mode: string): void {
        GlobalConfig.appearance.colors.mode = mode;
        root.applyTheme();
    }

    // --- Source / palette selection -------------------------------------

    function setPaletteSource(source: string): void {
        if (!root.paletteSourceIds.includes(source) || root.paletteSource === source)
            return;
        root.paletteSource = source;
        root.saveThemeState();
        root.applyTheme();
    }

    function setBuiltinPalette(paletteId: string): void {
        if (!BuiltinPalettes.isKnown(paletteId)) {
            root.themeError = `Unknown built-in palette '${paletteId}'`;
            return;
        }
        root.themeError = "";
        if (root.builtinPalette === paletteId)
            return;
        root.builtinPalette = paletteId;
        root.saveThemeState();
        root.applyTheme();
    }

    // --- Wallpaper-derived colours --------------------------------------

    function isSupportedImage(path: string): bool {
        return /\.(png|jpe?g|webp|bmp|gif)$/i.test(path);
    }

    // Explicit light/dark choice wins; 'auto' follows the analysed wallpaper.
    function resolveLight(): bool {
        const mode = GlobalConfig.appearance.colors.mode;
        if (mode === "light")
            return true;
        if (mode === "dark")
            return false;
        return analyser.luminance > 0.5;
    }

    // Write a generated role map into a palette. Returns false when the map is
    // not a complete palette, so callers can refuse to claim success.
    // Preview writes never touch the live status message.
    function applyRoles(roles: var, colours: QtObject, isPreview: bool): bool {
        const names = Object.keys(roles ?? {});
        if (names.length < 40) {
            if (!isPreview)
                root.themeError = "Palette generation produced no colours";
            return false;
        }
        let applied = 0;
        for (const name of names) {
            if (colours.hasOwnProperty(name)) {
                colours[name] = roles[name];
                applied++;
            }
        }
        if (applied < names.length) {
            if (!isPreview)
                root.themeError = `Palette generation produced ${applied}/${names.length} recognised roles`;
            return false;
        }
        root.themeError = "";
        return true;
    }

    // The single writer of the live palette.
    function applyTheme(): void {
        // Any extraction still in flight is now stale.
        root.pendingWallpaper = "";
        const light = root.resolveLight();
        switch (root.paletteSource) {
        case "wallpaper":
            root.requestWallpaper(Wallpapers.actualCurrent);
            break;
        case "custom":
            root.applyCustom();
            break;
        case "scheme":
            schemeFile.reload();
            break;
        default:
            if (root.applyRoles(BuiltinPalettes.roles(root.builtinPalette, light), root.current, false)) {
                root.currentLight = light;
                root.scheme = `celestia:${root.builtinPalette}`;
            }
            break;
        }
    }

    // Extract a seed from the wallpaper and build the palette from it. Results
    // are cached per wallpaper path, so restarting the shell (or switching back
    // and forth between sources) does not re-decode the image, and a new
    // wallpaper is re-analysed automatically.
    function requestWallpaper(path: string): void {
        if (!path) {
            root.extractionState = "failed";
            root.extractionError = "No wallpaper is selected, so there is nothing to extract colours from.";
            return;
        }
        if (!root.isSupportedImage(path)) {
            root.extractionState = "failed";
            root.extractionError = `Unsupported wallpaper format: ${Paths.shortenHome(path)}`;
            return;
        }

        const light = root.resolveLight();
        const cached = root.wallpaperCache[path];
        if (typeof cached === "string" && ColorGen.isValidSeed(cached)) {
            root.wallpaperSeed = cached;
            root.wallpaperSeedPath = path;
            if (root.applyRoles(ColorGen.roles(cached, light, {}), root.current, false)) {
                root.currentLight = light;
                root.scheme = "dynamic";
                root.extractionState = "ok";
                root.extractionError = "";
            }
            return;
        }

        root.extractionState = "extracting";
        root.extractionError = "";
        root.pendingWallpaper = path;
        // Re-assigning the same path would be ignored by the analyser, so force
        // a re-read for manual refreshes.
        wallpaperAnalyser.source = "";
        wallpaperAnalyser.source = path;
        extractTimer.restart();
    }

    // Force a fresh extraction ("Refresh from wallpaper"), discarding the cache
    // entry for the current wallpaper.
    function refreshWallpaper(): void {
        const path = Wallpapers.actualCurrent;
        delete root.wallpaperCache[path];
        root.wallpaperCache = Object.assign({}, root.wallpaperCache);
        root.requestWallpaper(path);
    }

    // Called when the wallpaper changes: regenerate if the wallpaper owns the
    // palette, otherwise just keep the luminance-based auto mode in step.
    function handleWallpaperChange(path: string): void {
        if (root.paletteSource === "wallpaper")
            root.requestWallpaper(path);
        else if (GlobalConfig.appearance.colors.mode === "auto")
            root.applyTheme();
    }

    // Kept for external callers (scripts, IPC): route into the single wallpaper
    // extraction path.
    function applyWallpaper(path: string): void {
        root.requestWallpaper(path);
    }

    function previewWallpaper(path: string): void {
        if (!path)
            return;
        previewAnalyser.source = path;
    }

    // Generate the full M3 palette from the configured seed and write it into the
    // live palette so every surface adopts it.
    function applyCustom(): void {
        const c = GlobalConfig.appearance.colors;
        if (!ColorGen.isValidSeed(c.seed)) {
            root.themeError = `'${c.seed}' is not a valid seed colour`;
            return;
        }

        const light = root.resolveLight();
        root.currentLight = light;

        if (root.applyRoles(ColorGen.roles(c.seed, light, {}), root.current, false))
            root.scheme = "custom";
    }

    // --- Persistence ----------------------------------------------------

    function saveThemeState(): void {
        if (!root.themeStateLoaded)
            return;
        const data = {
            source: root.paletteSource,
            builtin: root.builtinPalette,
            wallpaperSeed: root.wallpaperSeed,
            wallpaperSeedPath: root.wallpaperSeedPath,
            wallpaperCache: root.wallpaperCache
        };
        themeWriter.setText(JSON.stringify(data, null, 2));
    }

    function loadThemeState(raw: string): void {
        let data = null;
        try {
            data = JSON.parse(raw);
        } catch (_e) {
            data = null;
        }

        if (!data || typeof data !== "object") {
            root.migrateThemeState();
            root.themeStateLoaded = true;
            root.themeStateMissing = true;
            root.saveThemeState();
            root.applyTheme();
            return;
        }

        root.themeStateMissing = false;

        if (root.paletteSourceIds.includes(data.source))
            root.paletteSource = data.source;
        if (BuiltinPalettes.isKnown(data.builtin))
            root.builtinPalette = data.builtin;
        if (data.wallpaperCache && typeof data.wallpaperCache === "object") {
            const cache = {};
            for (const [path, seed] of Object.entries(data.wallpaperCache)) {
                if (typeof seed === "string" && ColorGen.isValidSeed(seed))
                    cache[path] = seed;
            }
            root.wallpaperCache = cache;
        }
        if (typeof data.wallpaperSeed === "string" && ColorGen.isValidSeed(data.wallpaperSeed)) {
            root.wallpaperSeed = data.wallpaperSeed;
            root.wallpaperSeedPath = typeof data.wallpaperSeedPath === "string" ? data.wallpaperSeedPath : "";
        }

        root.themeStateLoaded = true;
        root.applyTheme();
    }

    // No saved preference yet (fresh install or an install predating v1.0.2):
    // keep the look the user already had instead of surprising them. An
    // external scheme generator that is actually producing schemes wins, exactly
    // as before this version.
    function migrateThemeState(): void {
        if (root.schemeAvailable)
            root.paletteSource = "scheme";
        else if (!GlobalConfig.appearance.colors.customEnabled)
            root.paletteSource = "wallpaper";
        else
            root.paletteSource = "builtin";
    }

    function reloadHyprRules(): void {
        let rule, trEnabled;
        if (Hypr.usingLua) {
            rule = `eval hl.layer_rule({ match = { namespace = "caelestia-drawers" }, %1 = %2 })`;
            trEnabled = transparency.enabled;
        } else {
            rule = "keyword layerrule %1 %2, match:namespace caelestia-drawers";
            trEnabled = transparency.enabled ? 1 : 0;
        }
        Hypr.extras.batchMessage([rule.arg("blur").arg(trEnabled), rule.arg("ignore_alpha").arg(Math.max(0, transparency.base - 0.03))]);
    }

    function requestReloadHyprRules(): void {
        if (cooldownTimer.running) {
            root.cooldownPending = true;
        } else {
            root.reloadHyprRules();
            cooldownTimer.restart();
        }
    }

    Component.onCompleted: {
        themeFile.reload();
        root.requestReloadHyprRules();
    }

    Connections {
        // The legacy `customEnabled` switch is now a shorthand for a palette
        // source, so hand-editing the config file keeps working.
        function onCustomEnabledChanged(): void {
            if (!root.themeStateLoaded)
                return;
            root.setPaletteSource(GlobalConfig.appearance.colors.customEnabled ? "custom" : "wallpaper");
        }

        function onSeedChanged(): void {
            if (root.paletteSource === "custom")
                root.applyTheme();
        }

        function onModeChanged(): void {
            if (root.themeStateLoaded)
                root.applyTheme();
        }

        target: GlobalConfig.appearance.colors
    }

    // Re-evaluate auto mode when wallpaper luminance changes
    Connections {
        function onLuminanceChanged(): void {
            if (root.themeStateLoaded && GlobalConfig.appearance.colors.mode === "auto")
                root.applyTheme();
        }

        target: analyser
    }

    // Wallpaper changes: regenerate when the wallpaper owns the palette.
    Connections {
        function onActualCurrentChanged(): void {
            if (root.themeStateLoaded)
                root.handleWallpaperChange(Wallpapers.actualCurrent);
        }

        target: Wallpapers
    }

    Connections {
        function onConfigReloaded(): void {
            root.reloadHyprRules();
        }

        target: Hypr
    }

    // Scriptable control of the theme, mirroring the wallpaper IPC handler.
    IpcHandler {
        function get(): string {
            return root.paletteSource;
        }

        function set(source: string): void {
            root.setPaletteSource(source);
        }

        function list(): string {
            return root.paletteSourceIds.join("\n");
        }

        // Live role values, so automation can verify the palette actually
        // changed instead of trusting a setting write.
        function palette(): string {
            const p = root.current;
            return `${p.m3primary} ${p.m3surface} ${p.m3onSurface} ${p.m3outline}`;
        }

        function seed(): string {
            return root.wallpaperSeed;
        }

        function status(): string {
            return `${root.extractionState}|${root.statusMessage}`;
        }

        target: "colours"
    }

    FileView {
        id: themeFile

        path: root.themeStatePath
        watchChanges: false
        printErrors: false
        onLoaded: root.loadThemeState(themeFile.text())
        onLoadFailed: {
            // No saved preference yet: inherit the previous behaviour rather
            // than silently restyling an existing install.
            root.migrateThemeState();
            root.themeStateLoaded = true;
            root.themeStateMissing = true;
            root.saveThemeState();
            root.applyTheme();
        }
    }

    FileView {
        id: themeWriter

        path: root.themeStatePath
        printErrors: false
    }

    FileView {
        id: schemeFile

        path: `${Paths.state}/scheme.json`
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            root.schemeAvailable = true;
            // An install that predates v1.0.2 and is driven by an external
            // scheme generator keeps that generator.
            if (root.themeStateMissing) {
                root.themeStateMissing = false;
                root.paletteSource = "scheme";
                root.saveThemeState();
            }
            root.load(schemeFile.text(), false);
        }
        onLoadFailed: {
            root.schemeAvailable = false;
            // Only an error the user can act on when they picked this source.
            if (root.paletteSource === "scheme") {
                root.extractionState = "failed";
                root.extractionError = `No scheme file at ${Paths.shortenHome(`${Paths.state}/scheme.json`)}. Choose another palette source in Appearance settings.`;
            }
        }
    }

    ImageAnalyser {
        id: analyser

        source: Wallpapers.current
    }

    // Separate analysers for applying and previewing wallpaper-derived colours
    ImageAnalyser {
        id: wallpaperAnalyser

        onDominantColourChanged: {
            // Results arrive asynchronously; drop anything no longer requested
            // (e.g. the user switched source or wallpaper mid-extraction).
            const path = root.pendingWallpaper;
            if (path === "")
                return;
            root.pendingWallpaper = "";
            extractTimer.stop();

            const seed = ColorGen.toHex(wallpaperAnalyser.dominantColour);
            const light = root.resolveLight();
            root.wallpaperSeed = seed;
            root.wallpaperSeedPath = path;
            if (root.applyRoles(ColorGen.roles(seed, light, {}), root.current, false)) {
                root.currentLight = light;
                root.scheme = "dynamic";
                root.extractionState = "ok";
                root.extractionError = "";
                // Cache per wallpaper so restarts and source switches are instant.
                root.wallpaperCache[path] = seed;
                root.saveThemeState();
            } else {
                root.extractionState = "failed";
                root.extractionError = `Colour extraction from ${Paths.shortenHome(path)} produced no usable palette.`;
            }
        }
    }

    ImageAnalyser {
        id: previewAnalyser

        onDominantColourChanged: {
            const seed = ColorGen.toHex(previewAnalyser.dominantColour);
            const light = root.resolveLight();
            root.previewLight = light;
            if (root.applyRoles(ColorGen.roles(seed, light, {}), root.preview, true)) {
                root.showPreview = true;
                Wallpapers.previewColourLock = false;
            }
        }
    }

    // Image decoding happens in the plugin and reports no failure of its own,
    // so a stalled extraction is surfaced instead of leaving the user waiting.
    Timer {
        id: extractTimer

        interval: 5000
        onTriggered: {
            if (root.extractionState !== "extracting")
                return;
            const path = root.pendingWallpaper;
            root.pendingWallpaper = "";
            root.extractionState = "failed";
            root.extractionError = `Could not read colours from ${Paths.shortenHome(path)}. The image may be corrupt or its format is not supported.`;
        }
    }

    Timer {
        id: cooldownTimer

        interval: 30
        onTriggered: {
            if (root.cooldownPending) {
                root.cooldownPending = false;
                root.reloadHyprRules();
                restart();
            }
        }
    }

    Timer {
        id: cAnimCompleteTimer

        interval: Tokens.anim.durations.expressiveSlowEffects
        onTriggered: root.requestReloadHyprRules()
    }

    component Transparency: QtObject {
        readonly property bool enabled: Tokens.transparency.enabled
        readonly property real base: Math.max(0, Math.min(1, Tokens.transparency.base - (root.light ? 0.1 : 0)))
        readonly property real layers: Math.max(0, Math.min(1, Tokens.transparency.layers))

        onEnabledChanged: {
            if (enabled)
                root.requestReloadHyprRules();
            else
                cAnimCompleteTimer.start();
        }
        onBaseChanged: {
            if (root.lastBaseTransparency > base)
                root.requestReloadHyprRules();
            else
                cAnimCompleteTimer.start();
            root.lastBaseTransparency = base;
        }
    }

    component M3TPalette: QtObject {
        readonly property color m3primary_paletteKeyColor: root.layer(root.palette.m3primary_paletteKeyColor)
        readonly property color m3secondary_paletteKeyColor: root.layer(root.palette.m3secondary_paletteKeyColor)
        readonly property color m3tertiary_paletteKeyColor: root.layer(root.palette.m3tertiary_paletteKeyColor)
        readonly property color m3neutral_paletteKeyColor: root.layer(root.palette.m3neutral_paletteKeyColor)
        readonly property color m3neutral_variant_paletteKeyColor: root.layer(root.palette.m3neutral_variant_paletteKeyColor)
        readonly property color m3background: root.layer(root.palette.m3background, 0)
        readonly property color m3onBackground: root.layer(root.palette.m3onBackground)
        readonly property color m3surface: root.layer(root.palette.m3surface, 0)
        readonly property color m3surfaceDim: root.layer(root.palette.m3surfaceDim, 0)
        readonly property color m3surfaceBright: root.layer(root.palette.m3surfaceBright, 0)
        readonly property color m3surfaceContainerLowest: root.layer(root.palette.m3surfaceContainerLowest)
        readonly property color m3surfaceContainerLow: root.layer(root.palette.m3surfaceContainerLow)
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
        readonly property color m3surfaceContainerHigh: root.layer(root.palette.m3surfaceContainerHigh)
        readonly property color m3surfaceContainerHighest: root.layer(root.palette.m3surfaceContainerHighest)
        readonly property color m3onSurface: root.layer(root.palette.m3onSurface)
        readonly property color m3surfaceVariant: root.layer(root.palette.m3surfaceVariant, 0)
        readonly property color m3onSurfaceVariant: root.layer(root.palette.m3onSurfaceVariant)
        readonly property color m3inverseSurface: root.layer(root.palette.m3inverseSurface, 0)
        readonly property color m3inverseOnSurface: root.layer(root.palette.m3inverseOnSurface)
        readonly property color m3outline: root.layer(root.palette.m3outline)
        readonly property color m3outlineVariant: root.layer(root.palette.m3outlineVariant)
        readonly property color m3shadow: root.layer(root.palette.m3shadow)
        readonly property color m3scrim: root.layer(root.palette.m3scrim)
        readonly property color m3surfaceTint: root.layer(root.palette.m3surfaceTint)
        readonly property color m3primary: root.layer(root.palette.m3primary)
        readonly property color m3onPrimary: root.layer(root.palette.m3onPrimary)
        readonly property color m3primaryContainer: root.layer(root.palette.m3primaryContainer)
        readonly property color m3onPrimaryContainer: root.layer(root.palette.m3onPrimaryContainer)
        readonly property color m3inversePrimary: root.layer(root.palette.m3inversePrimary)
        readonly property color m3secondary: root.layer(root.palette.m3secondary)
        readonly property color m3onSecondary: root.layer(root.palette.m3onSecondary)
        readonly property color m3secondaryContainer: root.layer(root.palette.m3secondaryContainer)
        readonly property color m3onSecondaryContainer: root.layer(root.palette.m3onSecondaryContainer)
        readonly property color m3tertiary: root.layer(root.palette.m3tertiary)
        readonly property color m3onTertiary: root.layer(root.palette.m3onTertiary)
        readonly property color m3tertiaryContainer: root.layer(root.palette.m3tertiaryContainer)
        readonly property color m3onTertiaryContainer: root.layer(root.palette.m3onTertiaryContainer)
        readonly property color m3error: root.layer(root.palette.m3error)
        readonly property color m3onError: root.layer(root.palette.m3onError)
        readonly property color m3errorContainer: root.layer(root.palette.m3errorContainer)
        readonly property color m3onErrorContainer: root.layer(root.palette.m3onErrorContainer)
        readonly property color m3success: root.layer(root.palette.m3success)
        readonly property color m3onSuccess: root.layer(root.palette.m3onSuccess)
        readonly property color m3successContainer: root.layer(root.palette.m3successContainer)
        readonly property color m3onSuccessContainer: root.layer(root.palette.m3onSuccessContainer)
        readonly property color m3primaryFixed: root.layer(root.palette.m3primaryFixed)
        readonly property color m3primaryFixedDim: root.layer(root.palette.m3primaryFixedDim)
        readonly property color m3onPrimaryFixed: root.layer(root.palette.m3onPrimaryFixed)
        readonly property color m3onPrimaryFixedVariant: root.layer(root.palette.m3onPrimaryFixedVariant)
        readonly property color m3secondaryFixed: root.layer(root.palette.m3secondaryFixed)
        readonly property color m3secondaryFixedDim: root.layer(root.palette.m3secondaryFixedDim)
        readonly property color m3onSecondaryFixed: root.layer(root.palette.m3onSecondaryFixed)
        readonly property color m3onSecondaryFixedVariant: root.layer(root.palette.m3onSecondaryFixedVariant)
        readonly property color m3tertiaryFixed: root.layer(root.palette.m3tertiaryFixed)
        readonly property color m3tertiaryFixedDim: root.layer(root.palette.m3tertiaryFixedDim)
        readonly property color m3onTertiaryFixed: root.layer(root.palette.m3onTertiaryFixed)
        readonly property color m3onTertiaryFixedVariant: root.layer(root.palette.m3onTertiaryFixedVariant)
    }

    component M3Palette: QtObject {
        property color m3primary_paletteKeyColor: "#a8627b"
        property color m3secondary_paletteKeyColor: "#8e6f78"
        property color m3tertiary_paletteKeyColor: "#986e4c"
        property color m3neutral_paletteKeyColor: "#807477"
        property color m3neutral_variant_paletteKeyColor: "#837377"
        property color m3background: "#191114"
        property color m3onBackground: "#efdfe2"
        property color m3surface: "#191114"
        property color m3surfaceDim: "#191114"
        property color m3surfaceBright: "#403739"
        property color m3surfaceContainerLowest: "#130c0e"
        property color m3surfaceContainerLow: "#22191c"
        property color m3surfaceContainer: "#261d20"
        property color m3surfaceContainerHigh: "#31282a"
        property color m3surfaceContainerHighest: "#3c3235"
        property color m3onSurface: "#efdfe2"
        property color m3surfaceVariant: "#514347"
        property color m3onSurfaceVariant: "#d5c2c6"
        property color m3inverseSurface: "#efdfe2"
        property color m3inverseOnSurface: "#372e30"
        property color m3outline: "#9e8c91"
        property color m3outlineVariant: "#514347"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3surfaceTint: "#ffb0ca"
        property color m3primary: "#ffb0ca"
        property color m3onPrimary: "#541d34"
        property color m3primaryContainer: "#6f334a"
        property color m3onPrimaryContainer: "#ffd9e3"
        property color m3inversePrimary: "#8b4a62"
        property color m3secondary: "#e2bdc7"
        property color m3onSecondary: "#422932"
        property color m3secondaryContainer: "#5a3f48"
        property color m3onSecondaryContainer: "#ffd9e3"
        property color m3tertiary: "#f0bc95"
        property color m3onTertiary: "#48290c"
        property color m3tertiaryContainer: "#b58763"
        property color m3onTertiaryContainer: "#000000"
        property color m3error: "#ffb4ab"
        property color m3onError: "#690005"
        property color m3errorContainer: "#93000a"
        property color m3onErrorContainer: "#ffdad6"
        property color m3success: "#B5CCBA"
        property color m3onSuccess: "#213528"
        property color m3successContainer: "#374B3E"
        property color m3onSuccessContainer: "#D1E9D6"
        property color m3primaryFixed: "#ffd9e3"
        property color m3primaryFixedDim: "#ffb0ca"
        property color m3onPrimaryFixed: "#39071f"
        property color m3onPrimaryFixedVariant: "#6f334a"
        property color m3secondaryFixed: "#ffd9e3"
        property color m3secondaryFixedDim: "#e2bdc7"
        property color m3onSecondaryFixed: "#2b151d"
        property color m3onSecondaryFixedVariant: "#5a3f48"
        property color m3tertiaryFixed: "#ffdcc3"
        property color m3tertiaryFixedDim: "#f0bc95"
        property color m3onTertiaryFixed: "#2f1500"
        property color m3onTertiaryFixedVariant: "#623f21"
        property color term0: "#353434"
        property color term1: "#ff4c8a"
        property color term2: "#ffbbb7"
        property color term3: "#ffdedf"
        property color term4: "#b3a2d5"
        property color term5: "#e98fb0"
        property color term6: "#ffba93"
        property color term7: "#eed1d2"
        property color term8: "#b39e9e"
        property color term9: "#ff80a3"
        property color term10: "#ffd3d0"
        property color term11: "#fff1f0"
        property color term12: "#dcbc93"
        property color term13: "#f9a8c2"
        property color term14: "#ffd1c0"
        property color term15: "#ffffff"
    }
}
