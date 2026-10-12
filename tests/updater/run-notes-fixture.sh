#!/usr/bin/env bash
# Regression tests for the release-note renderer used by the Updates page
# (modules/nexus/pages/releaseNotes.js).
#
# Release notes come from GitHub as markdown. Shown raw they read as asterisks,
# backticks, comment markers and hashes, which is exactly what users complained
# about. These tests pin the contract: the same content, as clean text, with the
# machine-readable digest marker removed from the *display* but left untouched in
# the raw body the updater verifies against.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SRC="$REPO/modules/nexus/pages/releaseNotes.js"
[ -f "$SRC" ] || { echo "FAIL: missing $SRC"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# QML `.pragma library` is not Node JS; strip it, then export the functions.
tail -n +2 "$SRC" > "$WORK/notes.js"
cat >> "$WORK/notes.js" <<'EOF'
module.exports = { plain, upToDate, stripNoise };
EOF

cat > "$WORK/test.js" <<'EOF'
const n = require("./notes.js");
let fails = 0;

function check(name, ok) {
    if (ok) console.log(`ok   ${name}`);
    else { fails++; console.log(`FAIL ${name}`); }
}
function eq(actual, expected, name) {
    check(name, actual === expected);
    if (actual !== expected) console.log(`     got:  ${JSON.stringify(actual)}\n     want: ${JSON.stringify(expected)}`);
}

// A body shaped like a real GitHub release, including the digest marker the
// updater workflow publishes and the auto-generated noise users objected to.
const DIGEST = "sha256:f39d06bfc506fb6d4c86a958d05184f38a757b0d5a2d0777ceb150399b8cc163";
const raw = [
    `<!-- updater-digest ${DIGEST} -->`,
    "",
    "## What's Changed",
    "",
    "* fix: v1.0.2 maintenance pass by @mockifylab in https://github.com/x/y/pull/2",
    "* **updater**: keep *plugins* safe from `rsync --delete`",
    "",
    "**Full Changelog**: https://github.com/x/y/compare/v1.0.1...v1.0.2",
    "",
    "![badge](https://img.shields.io/v.svg)",
    "",
    "### Details",
    "1. first ordered item",
    "2. second ordered item",
    "",
    "```",
    "fenced code that is not prose",
    "```",
    "",
    "---"
].join("\n");

const text = n.plain(raw);

check("digest marker is not shown to the user", !text.includes("updater-digest"));
check("no visible hash in the rendered notes", !text.includes(DIGEST));
check("no markdown comment syntax leaks", !text.includes("<!--"));
check("no bold markers leak", !text.includes("**"));
check("no heading markers leak", !text.includes("##"));
check("no inline code markers leak", !text.includes("`"));
check("no link syntax leaks", !text.includes("]("));
check("no image syntax leaks", !text.includes("!["));
check("no horizontal rule syntax leaks", !text.includes("---"));
check("fence content is dropped, not shown as prose", !text.includes("fenced code that is not prose"));
check("content survives: PR line", text.includes("fix: v1.0.2 maintenance pass"));
check("content survives: link label kept, URL dropped", text.includes("@mockifylab in https://github.com/x/y/pull/2"));
check("content survives: changelog label", text.includes("Full Changelog"));
check("bullets become readable bullets", text.includes("• updater: keep plugins safe from rsync --delete"));
check("ordered lists keep their numbers", text.includes("1. first ordered item") && text.includes("2. second ordered item"));
check("no blank-line runs longer than one", !text.includes("\n\n\n"));
check("paragraph structure survives", /What's Changed\n\n/.test(text));
check("no trailing whitespace on any line", !/[ \t]\n/.test(text) && !/[ \t]$/.test(text));

// The raw body must stay exactly what the updater verifies against: rendering
// must never be what feeds checksum parsing.
check("raw body still carries the digest for verification", raw.includes(DIGEST));
check("stripNoise does not touch surrounding prose", n.stripNoise("keep me") === "keep me");

eq(n.plain(""), "", "empty body renders empty");
eq(n.plain(undefined), "", "missing body renders empty");
eq(n.plain(null), "", "null body renders empty");

// Up-to-date confirmation wording (spec: tell the user the system is current).
eq(n.upToDate("1.0.3", "1.0.3"), "Version 1.0.3 is installed. This is the newest release.", "same version is confirmed");
eq(n.upToDate("v1.0.3", "v1.0.3"), "Version 1.0.3 is installed. This is the newest release.", "v prefixes normalise");
eq(n.upToDate("1.0.2", "1.0.3"), "Newest release: 1.0.3.", "older install names the newest");
eq(n.upToDate("1.0.3", ""), "No release information yet.", "no feed data is admitted");
eq(n.upToDate("", "1.0.3"), "Newest release: 1.0.3.", "unknown installed version is not claimed current");

if (fails) { console.log(`${fails} FAILURES`); process.exit(1); }
console.log("ALL RELEASE NOTE RENDER TESTS PASSED");
EOF

if node "$WORK/test.js"; then
    echo "PASS: release note renderer"
    exit 0
fi
echo "FAIL: release note renderer"
exit 1
