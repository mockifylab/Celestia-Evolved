pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.services

// Headless harness for the palette design system. Prints RESULT lines that
// run-palette-fixture.sh asserts on. Runs under the offscreen platform: the
// generators are pure functions, no windows needed.
ShellRoot {
    id: root

    property int failures: 0

    function check(name: string, ok: bool): void {
        console.log(`RESULT|${name}|${ok ? "ok" : "fail"}`);
        if (!ok)
            root.failures++;
    }

    function isHex(v: string): bool {
        return /^#[0-9a-f]{6}$/.test(v);
    }

    function run(): void {
        // --- seed validation -------------------------------------------------
        root.check("valid 6-digit seed accepted", ColorGen.isValidSeed("#a8627b"));
        root.check("valid 3-digit seed accepted", ColorGen.isValidSeed("#fff"));
        root.check("missing hash rejected", !ColorGen.isValidSeed("a8627b"));
        root.check("garbage rejected", !ColorGen.isValidSeed("nonsense"));
        root.check("empty rejected", !ColorGen.isValidSeed(""));

        // --- built-in palettes are complete in both modes --------------------
        const keyRoles = ["m3primary", "m3onPrimary", "m3primaryContainer", "m3surface", "m3onSurface", "m3surfaceContainerHigh", "m3outline", "m3outlineVariant", "m3error", "m3success", "m3background", "m3onBackground"];
        let ids = BuiltinPalettes.ids;
        root.check("built-in palettes registered", ids.length >= 2);
        let complete = true;
        let contrast = true;
        let terms = true;
        for (const id of ids) {
            for (const light of [false, true]) {
                const r = BuiltinPalettes.roles(id, light);
                const names = Object.keys(r);
                if (names.length < 60)
                    complete = false;
                for (const k of keyRoles) {
                    if (!isHex(r[k] ?? ""))
                        complete = false;
                }
                for (let i = 0; i < 16; i++) {
                    if (!isHex(r[`term${i}`] ?? ""))
                        terms = false;
                }
                // Text must stay readable on its own background.
                const bg = Qt.color(r.m3background).hslLightness;
                const fg = Qt.color(r.m3onBackground).hslLightness;
                if (Math.abs(bg - fg) < 0.5)
                    contrast = false;
                if (light && !(bg > fg))
                    contrast = false;
                if (!light && !(bg < fg))
                    contrast = false;
            }
        }
        root.check("every built-in palette is complete", complete);
        root.check("every built-in palette has a terminal ramp", terms);
        root.check("built-in text/background contrast holds", contrast);

        // --- dark and light variants must actually differ --------------------
        const dark = BuiltinPalettes.roles("celestia", false);
        const light = BuiltinPalettes.roles("celestia", true);
        root.check("dark and light differ", dark.m3surface !== light.m3surface && dark.m3primary !== light.m3primary);

        // --- unknown palettes are refused, not invented ---------------------
        root.check("unknown palette returns empty", Object.keys(BuiltinPalettes.roles("does-not-exist", false)).length === 0);
        root.check("known palette id recognised", BuiltinPalettes.isKnown("celestia") && !BuiltinPalettes.isKnown("does-not-exist"));

        // --- generator is deterministic and tolerant -----------------------
        const a = ColorGen.roles("#3f9d7a", false, {});
        const b = ColorGen.roles("#3f9d7a", false, {});
        root.check("generation is deterministic", a.m3primary === b.m3primary && a.term4 === b.term4);
        const bogus = ColorGen.roles("not-a-colour", false, {});
        root.check("bogus seed still yields a usable palette", isHex(bogus.m3primary) && isHex(bogus.m3surfaceContainer));
        const tuned = ColorGen.roles("#3f9d7a", false, {
            sat: 0.9
        });
        root.check("design knobs are honoured", Qt.color(tuned.m3primary).hslSaturation > Qt.color(a.m3primary).hslSaturation);
        // Low-chroma wallpapers must not produce a grey shell.
        const dull = ColorGen.roles("#808080", false, {});
        root.check("grey seed is given an accent", Qt.color(dull.m3primary).hslSaturation >= 0.2);

        console.log(`RESULT|done|failures=${root.failures}`);
        Qt.exit(root.failures === 0 ? 0 : 1);
    }

    // Deferred until quickshell has connected the engine's exit handler.
    Timer {
        running: true
        interval: 0
        repeat: false
        onTriggered: root.run()
    }
}
