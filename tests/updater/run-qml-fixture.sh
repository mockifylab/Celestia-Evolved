#!/usr/bin/env bash
#
# End-to-end fixture test for the in-app updater *service* (services/Updater.qml)
# plus its interaction with the helper script. Unlike run-fixture.sh (which only
# exercises assets/update/apply_update.sh subcommands), this drives the real QML
# state machine under quickshell, offscreen:
#
#   1. unreachable feed        -> state error, friendly message
#   2. local HTTP fixture feed -> available (version compare + digest parse)
#   3. download -> verify -> extract -> apply (via the real helper) -> applied
#   4. install dir actually updated; user data preserved; rollback available
#
# No public network access: the feed is served from 127.0.0.1, assets via file://.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_DIR="$(cd "$ROOT/../.." && pwd)"
FIXTURE="$(mktemp -d /tmp/updater_qml_fixture.XXXXXX)"
HELPERS="$(mktemp -d /tmp/updater_qml_helpers.XXXXXX)"
PASS=0
FAIL=0

cleanup() {
    [[ -n "${FEED_PID:-}" ]] && kill "$FEED_PID" 2>/dev/null
    rm -rf "$FIXTURE" "$HELPERS"
}
trap cleanup EXIT

check() { # <name> <expected> <actual>
    local name="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (want '$want', got '$got')"
        FAIL=$((FAIL + 1))
    fi
}

check_file() { # <name> <regex> <file>
    local name="$1" re="$2" file="$3"
    if grep -qP "$re" "$file" 2>/dev/null; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (no /$re/ in $file)"
        FAIL=$((FAIL + 1))
    fi
}

echo "== updater QML fixture: $FIXTURE =="

# --- Build a release payload (v1.0.1) + tarball + digest ---
mkdir -p "$FIXTURE/payload"
echo 'v1.0.1' >"$FIXTURE/payload/VERSION"
echo "// new shell" >"$FIXTURE/payload/shell.qml"
tar -czf "$FIXTURE/shell-1.0.1.tar.gz" -C "$FIXTURE/payload" .
DIGEST="$(sha256sum "$FIXTURE/shell-1.0.1.tar.gz" | awk '{print $1}')"

# --- Fake install dir (must contain the payload's top-level entries so the
#     helper's apply can swap contents while preserving user data) ---
mkdir -p "$HELPERS/install"
echo 'v1.0.0' >"$HELPERS/install/VERSION"
echo "// old shell" >"$HELPERS/install/shell.qml"
echo "user = 42" >"$HELPERS/install/user.conf"

# --- Feed served over HTTP from 127.0.0.1 ---
# Pick a free port dynamically: a fixed port can be squatted by a leftover
# process, which would silently make this fixture serve a stale feed (the
# bind failure is otherwise invisible behind the redirect).
PORT="$(python3 -c "import socket; s=socket.socket(); s.bind(('127.0.0.1',0)); print(s.getsockname()[1]); s.close()")"
cat >"$FIXTURE/releases.json" <<EOF
{
  "tag_name": "v1.0.1",
  "name": "v1.0.1",
  "body": "Fixes: appearance panel performance, updater.",
  "assets": [
    {
      "name": "shell-1.0.1.tar.gz",
      "browser_download_url": "file://$FIXTURE/shell-1.0.1.tar.gz",
      "digest": "sha256:$DIGEST"
    }
  ]
}
EOF
python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$FIXTURE" >/dev/null 2>&1 &
FEED_PID=$!
sleep 1
if ! kill -0 "$FEED_PID" 2>/dev/null; then
    echo "FAIL: fixture feed server on port $PORT did not start"
    echo "== result: 0 passed, 1 failed =="
    exit 1
fi

# --- Assemble a throwaway quickshell config tree that wires the REAL service
#     singleton (services/Updater.qml) as qs.services and the REAL utils
#     (utils/Paths.qml) as qs.utils. Nothing is copied into the repo tree. ---
PROJ="$FIXTURE/proj"
mkdir -p "$PROJ/services" "$PROJ/utils"
cp "$ROOT/shell.qml" "$PROJ/shell.qml"
ln -sf "$SHELL_DIR/services/Updater.qml" "$PROJ/services/Updater.qml"
ln -sf "$SHELL_DIR/utils/Paths.qml" "$PROJ/utils/Paths.qml"

# --- Run the real Updater singleton under quickshell (offscreen) ---
OUT="$FIXTURE/harness.out"
env \
    QT_QPA_PLATFORM=offscreen \
    QML2_IMPORT_PATH="$SHELL_DIR/build/qml:${QML2_IMPORT_PATH:-/usr/lib/qt6/qml}" \
    CAELESTIA_UPDATE_FEED="http://127.0.0.1:$PORT/releases.json" \
    UPDATER_TEST_DEAD_FEED="http://127.0.0.1:1/releases.json" \
    CAELESTIA_UPDATE_HELPER="$SHELL_DIR/assets/update/apply_update.sh" \
    CAELESTIA_UPDATE_TARGET="$HELPERS/install" \
    XDG_CACHE_HOME="$FIXTURE/cache" \
    timeout 60 qs -p "$PROJ/shell.qml" >"$OUT" 2>&1
RC=$?
echo "harness exit: $RC"
sed 's/^/  | /' "$OUT"

# --- Assertions on the observed state machine ---
check "harness exited 0" 0 "$RC"
check_file "dead feed surfaced error" 'RESULT\|deadfeed.*state=error' "$OUT"
check_file "dead feed error message" 'Could not reach the update feed' "$OUT"
check_file "feed parsed + version compared" 'RESULT\|parsed.*state=available.*latest=1\.0\.1.*cur=1\.0\.0' "$OUT"
check_file "update flag raised" 'state=verifying.*avail=true' "$OUT"
check_file "asset digest extracted" "RESULT\|parsed.*digest=${DIGEST:0:8}" "$OUT"
check_file "release notes surfaced" 'RESULT\|parsed.*notes=true' "$OUT"
check_file "chain reached applied" 'RESULT\|final.*state=applied' "$OUT"
check_file "apply registers new version" 'RESULT\|final.*state=applied.*latest=1\.0\.1.*cur=1\.0\.1.*avail=false' "$OUT"
check_file "same release not re-offered after install" 'RESULT\|recheck.*state=upToDate.*cur=1\.0\.1' "$OUT"

# --- Effects on disk ---
check "install VERSION registered" "1.0.1" "$(cat "$HELPERS/install/VERSION" 2>/dev/null)"
check "user data preserved" "user = 42" "$(cat "$HELPERS/install/user.conf" 2>/dev/null)"
check "shell.qml updated" "// new shell" "$(cat "$HELPERS/install/shell.qml" 2>/dev/null)"
[[ -f "$FIXTURE/cache/caelestia/updates/rollback.env" ]]
check "rollback env written" 0 $?

echo
echo "== result: $PASS passed, $FAIL failed =="
[[ "$FAIL" -eq 0 ]]
