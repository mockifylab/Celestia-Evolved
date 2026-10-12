pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import qs.utils

// Safe in-app updater for Celestia Shell Reimagined.
//
// The dangerous steps (download, checksum verify, extract, activate, rollback)
// are delegated to `assets/update/apply_update.sh`, which keeps a known-good
// backup of the install directory so any activation can be undone. This service
// only orchestrates those subcommands and maintains a small state machine that
// the Nexus Updates page binds to.
//
// Everything is driven from a single release feed that speaks the GitHub
// Releases JSON shape. The feed, repo, current version and target install dir
// are all overridable via the environment so the whole flow can be exercised
// against a controlled local fixture (file:// URLs, no network).
Singleton {
    id: root

    // --- Configuration (env-overridable for testing / self-hosting) ---

    readonly property string repo: Quickshell.env("CAELESTIA_UPDATE_REPO") || "mockifylab/Celestia-Shell_Reimagend"
    // feedOverride exists for tests and self-hosting; it defaults to the env
    // override so CAELESTIA_UPDATE_FEED keeps working.
    property string feedOverride: Quickshell.env("CAELESTIA_UPDATE_FEED") || ""
    readonly property string feedUrl: feedOverride !== "" ? feedOverride : `https://api.github.com/repos/${repo}/releases/latest`
    // Installed version, in precedence order:
    //  1. explicit test override,
    //  2. the version applied in this session (before a restart),
    //  3. the VERSION file written into the install dir by a past update,
    //  4. the version compiled into the C++ plugin (fresh git builds and old
    //     installs that predate the VERSION file).
    property string overrideVersion: ""
    property string detectedVersion: ""
    // CUtils.version may carry the tag 'v' prefix (default build version comes
    // from `git describe`); normalise so `v${currentVersion}` never doubles it.
    readonly property string compiledVersion: CUtils.version.replace(/^v/, "")
    readonly property string currentVersion: Quickshell.env("CAELESTIA_UPDATE_CURRENT") || (overrideVersion !== "" ? overrideVersion : (detectedVersion !== "" ? detectedVersion : compiledVersion))
    readonly property string helper: Quickshell.env("CAELESTIA_UPDATE_HELPER") || Quickshell.shellPath("assets/update/apply_update.sh")

    // Install directory that gets updated / rolled back.
    readonly property string installDir: Quickshell.env("CAELESTIA_UPDATE_TARGET") || Quickshell.shellPath("")

    readonly property string metaDir: `${Paths.cache}/updates`
    readonly property string downloadFile: `${metaDir}/download.bin`
    readonly property string stagedDir: `${metaDir}/staged`

    // --- Observable state (bound by UpdatePage) ---

    // One of: idle, checking, upToDate, available, downloading, verifying,
    // staging, applying, applied, rollingBack, error.
    property string state: "idle"
    property string latestVersion: ""
    property string downloadUrl: ""
    property int downloadSize: 0
    property string expectedDigest: ""
    property string releaseNotes: ""
    property string message: ""
    property string lastChecked: ""
    property bool rollbackAvailable: false
    property bool updateAvailable: false

    // Internal: the helper subcommand awaiting completion ("" when idle).
    property string pendingOp: ""

    readonly property bool busy: ["checking", "downloading", "verifying", "staging", "applying", "rollingBack"].includes(state)

    // --- Public API ---

    function check(): void {
        if (busy)
            return;
        state = "checking";
        message = "";
        updateAvailable = false;

        Requests.get(feedUrl, body => onFeedFetched(body), err => {
            state = "error";
            message = `Could not reach the update feed: ${err}`;
        });
    }

    function download(): void {
        if (downloadUrl === "") {
            fail("No update to download.");
            return;
        }
        state = "downloading";
        runHelper(["fetch", downloadUrl, downloadFile], "download");
    }

    // verify -> extract -> apply, chained. A verify failure aborts before
    // anything touches the install directory.
    function install(): void {
        if (expectedDigest === "") {
            fail("The release did not advertise a SHA-256 digest; refusing to apply an unverified update.");
            return;
        }
        state = "verifying";
        runHelper(["verify", downloadFile, expectedDigest], "verify");
    }

    function rollback(): void {
        state = "rollingBack";
        runHelper(["rollback", installDir, metaDir], "rollback");
    }

    function refreshRollbackStatus(): void {
        runHelper(["status", metaDir], "status");
    }

    // --- Feed parsing ---

    function onFeedFetched(body: string): void {
        let json;
        try {
            json = JSON.parse(body);
        } catch (e) {
            state = "error";
            message = "Update feed was not valid JSON.";
            return;
        }

        const tag = json.tag_name ?? json.name ?? "";
        latestVersion = tag.replace(/^v/, "");
        releaseNotes = json.body ?? "";
        lastChecked = Qt.formatDateTime(new Date(), "yyyy-MM-dd HH:mm");

        // Pick a tarball-ish asset; prefer one that advertises a digest.
        const assets = json.assets ?? [];
        const pick = assets.find(a => /\.(tar\.gz|tgz|tar\.xz|zip)$/.test(a.name ?? "")) ?? assets[0];
        downloadUrl = pick ? (pick.browser_download_url ?? pick.download_url ?? "") : "";
        downloadSize = pick ? (pick.size ?? 0) : 0;
        expectedDigest = pick ? (pick.digest ?? "").replace(/^sha256:/, "").toLowerCase() : "";

        // GitHub's release API has no per-asset digest, so fall back to a
        // `sha256:<hex>` marker published in the release body by the release
        // workflow. Still verified before anything is applied.
        if (expectedDigest === "" && typeof json.body === "string") {
            const m = json.body.match(/sha256:?\s*([0-9a-fA-F]{64})/i);
            if (m)
                expectedDigest = m[1].toLowerCase();
        }

        const cmp = compareVersions(latestVersion, currentVersion);
        if (cmp > 0 && downloadUrl !== "") {
            updateAvailable = true;
            state = "available";
        } else {
            updateAvailable = false;
            state = "upToDate";
        }
    }

    // --- Semver compare (major.minor.patch + optional -prerelease) ---

    function compareVersions(a: string, b: string): int {
        const av = String(a).trim().replace(/^v/, "");
        const bv = String(b).trim().replace(/^v/, "");
        const ac = av.split("-")[0].split(".");
        const bc = bv.split("-")[0].split(".");
        const apre = av.includes("-") ? av.split("-").slice(1).join("-") : "";
        const bpre = bv.includes("-") ? bv.split("-").slice(1).join("-") : "";

        for (let i = 0; i < 3; i++) {
            const x = Number(ac[i] ?? 0) || 0;
            const y = Number(bc[i] ?? 0) || 0;
            if (x < y)
                return -1;
            if (x > y)
                return 1;
        }

        // Same numeric core: a release outranks any pre-release of it.
        if (apre === "" && bpre !== "")
            return 1;
        if (apre !== "" && bpre === "")
            return -1;
        if (apre < bpre)
            return -1;
        if (apre > bpre)
            return 1;
        return 0;
    }

    // --- Helper process plumbing ---

    function runHelper(args, op: string): void {
        if (helperProc.running)
            return;
        pendingOp = op;
        helperProc.command = ["bash", helper, ...args];
        helperProc.running = true;
    }

    function onHelperFinished(op: string, code: int): void {
        if (op === "status") {
            rollbackAvailable = helperOut.text.includes("rollback_available=1");
            return;
        }

        if (code !== 0) {
            if (op === "verify" && code === 3)
                fail("Downloaded file failed SHA-256 verification. Nothing was installed.");
            else if (op === "rollback" && code === 4)
                fail("No previous version backup is available to roll back to.");
            else
                fail(`${op} failed (exit ${code}). ${helperErr.text.trim()}`.trim());
            return;
        }

        switch (op) {
        case "download":
            state = "verifying";
            runHelper(["verify", downloadFile, expectedDigest], "verify");
            break;
        case "verify":
            state = "staging";
            runHelper(["extract", downloadFile, stagedDir], "extract");
            break;
        case "extract":
            state = "applying";
            runHelper(["apply", stagedDir, installDir, metaDir, latestVersion], "apply");
            break;
        case "apply":
            // Register the new version BEFORE flipping state: observers that
            // snapshot currentVersion on the state change must already see the
            // applied release (and the same release must not be re-offered in
            // this session; after restart the VERSION file takes over).
            overrideVersion = latestVersion;
            detectedVersion = latestVersion;
            updateAvailable = false;
            rollbackAvailable = true;
            state = "applied";
            message = "Update applied. Restart the shell to load the new version.";
            break;
        case "rollback":
            state = "idle";
            // The backup restored the previous VERSION file (or none), so drop
            // the session override and re-read what is on disk now.
            overrideVersion = "";
            versionFile.reload();
            message = "Rolled back to the previous version. Restart the shell.";
            refreshRollbackStatus();
            break;
        default:
            break;
        }
    }

    function fail(msg: string): void {
        state = "error";
        message = msg;
    }

    // Opt-in headless auto-check so the whole flow can be driven from tests.
    Component.onCompleted: {
        versionFile.reload();
        if (Quickshell.env("CAELESTIA_UPDATE_AUTOCHECK") === "1") {
            refreshRollbackStatus();
            Qt.callLater(() => check());
        }
    }

    // Authoritative installed-version metadata for tarball-installed shells.
    FileView {
        id: versionFile

        path: `${root.installDir}/VERSION`
        watchChanges: false
        printErrors: false

        onLoaded: {
            // Accept both "1.0.2" and legacy "v1.0.2" payloads.
            const v = text().trim().replace(/^v/, "");
            if (v !== "" && v !== "undefined")
                root.detectedVersion = v;
        }
        onLoadFailed: _err => {
            // No VERSION file (fresh build or pre-v1.0.2 install): fall back to
            // the compiled version. This is not an error state.
            root.detectedVersion = "";
        }
    }

    Process {
        id: helperProc

        // qmllint disable incompatible-type
        environment: ({
                // qmllint enable incompatible-type
                LC_ALL: "C"
            })

        stdout: StdioCollector {
            id: helperOut
        }

        stderr: StdioCollector {
            id: helperErr
        }

        // Fires with the real exit status once streams are closed.
        onExited: code => { // qmllint disable signal-handler-parameters
            if (root.pendingOp === "")
                return;
            const op = root.pendingOp;
            root.pendingOp = "";
            root.onHelperFinished(op, code);
        }
    }
}
