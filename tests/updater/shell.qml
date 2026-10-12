// Drives the real services/Updater.qml singleton (registered via the qs module
// scan of this directory) against a local fixture feed. Prints one RESULT line
// per observable outcome so run-qml-fixture.sh can assert on the full state
// machine:
//   error path -> available (feed parse + digest + version compare) ->
//   download -> verify -> extract -> apply chain via the helper -> applied.
import QtQuick
import Quickshell
import qs.services

ShellRoot {
    id: root

    property int phase: 0
    property string liveFeedOverride: ""

    function emit(tag: string): void {
        const o = Updater;
        console.log("RESULT|" + tag + "|state=" + o.state + "|latest=" + o.latestVersion + "|cur=" + o.currentVersion + "|avail=" + o.updateAvailable + "|digest=" + o.expectedDigest.substring(0, 8) + "|notes=" + (o.releaseNotes !== "") + "|msg=" + o.message.replace(/\|/g, " "));
    }

    function onFeedError(): void {
        // Phase 1 was the unreachable feed; a clean error is the expected
        // outcome (the message arrives asynchronously, so emit captures it).
        if (root.phase !== 1 || Updater.state !== "error")
            return;
        root.phase = 2;
        root.emit("deadfeed");
        Updater.feedOverride = root.liveFeedOverride;
        Updater.check();
    }

    function onFeedAvailable(): void {
        // Phase 2 checked the fixture feed; 'available' proves parsing,
        // version comparison and digest extraction. Start the chain.
        if (root.phase !== 2 || Updater.state !== "available")
            return;
        root.emit("parsed");
        root.phase = 3;
        Updater.download();
    }

    function start(): void {
        Updater.refreshRollbackStatus();

        // Phase 1: unreachable feed must surface a clean error state. The live
        // fixture feed arrives via CAELESTIA_UPDATE_FEED (feedOverride's init).
        root.liveFeedOverride = Updater.feedOverride;
        root.phase = 1;
        Updater.feedOverride = Quickshell.env("UPDATER_TEST_DEAD_FEED") || "http://127.0.0.1:1/releases.json";
        Updater.check();
    }

    Connections {
        function onStateChanged(): void {
            root.emit("state");
            root.onFeedError();
            root.onFeedAvailable();

            // Phase 3: the whole download->verify->extract->apply chain ran.
            if (root.phase === 3 && Updater.state === "applied") {
                root.emit("final");
                Qt.exit(0);
            }

            // Any unexpected error mid-chain: fail loudly.
            if (Updater.state === "error" && root.phase >= 3) {
                console.log("RESULT|fatal|msg=" + Updater.message.replace(/\|/g, " "));
                Qt.exit(1);
            }
        }

        target: Updater
    }

    Timer {
        running: true
        interval: 0
        repeat: false
        onTriggered: root.start()
    }

    Timer {
        running: true
        interval: 30000
        onTriggered: {
            console.log("RESULT|timeout|phase=" + root.phase);
            Qt.exit(1);
        }
    }
}
