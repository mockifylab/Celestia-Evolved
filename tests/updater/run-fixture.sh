#!/usr/bin/env bash
#
# Local fixture test for assets/update/apply_update.sh.
#
# Builds a controlled release fixture (fake install dir, new-version tarball,
# GitHub-style releases.json with a sha256 digest) and drives the helper
# through: fetch -> verify (pass) -> verify (tamper) -> compare -> extract ->
# apply (backup) -> rollback -> status. No network access; file:// only.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_DIR="$(cd "$ROOT/../.." && pwd)"
SCRIPT="$SHELL_DIR/assets/update/apply_update.sh"
FIXTURE="$(mktemp -d /tmp/update_fixture.XXXXXX)"
PASS=0
FAIL=0

check() { # <name> <expected-status> <actual-status>
    local name="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (want status $want, got $got)"
        FAIL=$((FAIL + 1))
    fi
}

run() { # <name> <want-status> <args...>
    local name="$1" want="$2"
    shift 2
    "$@" >/dev/null 2>&1
    check "$name" "$want" "$?"
}

echo "== updater helper fixture: $FIXTURE =="
[[ -x "$SCRIPT" ]] || { echo "script not executable: $SCRIPT"; exit 1; }

# --- Build a fake "installed" shell ---
mkdir -p "$FIXTURE/install"
echo 'v1.0.0' >"$FIXTURE/install/VERSION"
echo "// old shell" >"$FIXTURE/install/shell.qml"
echo "user = 42" >"$FIXTURE/install/user.conf" # must survive apply

# --- Build a staged release payload (v1.0.1) + tarball ---
mkdir -p "$FIXTURE/payload"
echo 'v1.0.1' >"$FIXTURE/payload/VERSION"
echo "// new shell" >"$FIXTURE/payload/shell.qml"
tar -czf "$FIXTURE/shell-1.0.1.tar.gz" -C "$FIXTURE/payload" .
DIGEST="$(sha256sum "$FIXTURE/shell-1.0.1.tar.gz" | awk '{print $1}')"

# --- GitHub-style release feed ---
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

# --- fetch ---
run "fetch feed" 0 "$SCRIPT" fetch "file://$FIXTURE/releases.json" "$FIXTURE/dl.json"
grep -q '"tag_name": "v1.0.1"' "$FIXTURE/dl.json"
check "fetch feed content" 0 $?
run "fetch asset" 0 "$SCRIPT" fetch "file://$FIXTURE/shell-1.0.1.tar.gz" "$FIXTURE/dl.tar.gz"

# --- verify (pass + tamper) ---
run "verify good digest" 0 "$SCRIPT" verify "$FIXTURE/dl.tar.gz" "sha256:$DIGEST"
echo "malicious" >>"$FIXTURE/dl.tar.gz"
run "verify tampered digest fails" 3 "$SCRIPT" verify "$FIXTURE/dl.tar.gz" "$DIGEST"

# --- compare ---
check "compare older" 0 "$([ "$("$SCRIPT" compare 1.0.0 1.0.1)" == "-1" ] && echo 0 || echo 1)"
check "compare equal" 0 "$([ "$("$SCRIPT" compare v1.0.1 1.0.1)" == "0" ] && echo 0 || echo 1)"
check "compare newer" 0 "$([ "$("$SCRIPT" compare 1.2.0 1.1.9)" == "1" ] && echo 0 || echo 1)"
check "compare prerelease" 0 "$([ "$("$SCRIPT" compare 1.0.1-rc1 1.0.1)" == "-1" ] && echo 0 || echo 1)"

# --- extract (fresh asset, tarball above was tampered) ---
run "extract" 0 "$SCRIPT" extract "$FIXTURE/shell-1.0.1.tar.gz" "$FIXTURE/staged"

# --- apply: activates staged, keeps a backup, preserves user.conf ---
run "apply" 0 "$SCRIPT" apply "$FIXTURE/staged" "$FIXTURE/install" "$FIXTURE/meta"
check "apply updated VERSION" 0 "$([[ "$(cat "$FIXTURE/install/VERSION")" == "v1.0.1" ]] && echo 0 || echo 1)"
check "apply preserved user.conf" 0 "$([[ "$(cat "$FIXTURE/install/user.conf")" == "user = 42" ]] && echo 0 || echo 1)"
check "apply wrote rollback env" 0 "$([[ -f "$FIXTURE/meta/rollback.env" ]] && echo 0 || echo 1)"

# --- status ---
status_out="$("$SCRIPT" status "$FIXTURE/meta")"
[[ "$status_out" == *"rollback_available=1"* ]]
check "status reports rollback available" 0 $?

# --- rollback: restores v1.0.0 ---
run "rollback" 0 "$SCRIPT" rollback "$FIXTURE/install" "$FIXTURE/meta"
check "rollback restored VERSION" 0 "$([[ "$(cat "$FIXTURE/install/VERSION")" == "v1.0.0" ]] && echo 0 || echo 1)"
check "rollback restored shell.qml" 0 "$(grep -q "old shell" "$FIXTURE/install/shell.qml" && echo 0 || echo 1)"

# --- rollback without backup ---
run "rollback without backup fails" 4 "$SCRIPT" rollback "$FIXTURE/install" "$FIXTURE/nometa"

# --- apply with explicit version registers installed metadata (v1.0.2) ---
# Simulates a payload WITHOUT a VERSION file (older release assets): the fourth
# argument must write <install>/VERSION so the shell can self-report it.
mkdir -p "$FIXTURE/staged_v2" "$FIXTURE/install_v2"
echo "// v2 shell" >"$FIXTURE/staged_v2/shell.qml"
run "apply with version" 0 "$SCRIPT" apply "$FIXTURE/staged_v2" "$FIXTURE/install_v2" "$FIXTURE/meta_v2" "1.0.2"
check "apply wrote VERSION from arg" 0 "$([[ "$(cat "$FIXTURE/install_v2/VERSION")" == "1.0.2" ]] && echo 0 || echo 1)"
check "rollback env records version" 0 "$(grep -q 'applied_version=1.0.2' "$FIXTURE/meta_v2/rollback.env" && echo 0 || echo 1)"
run "rollback v2 restores (drops VERSION)" 0 "$SCRIPT" rollback "$FIXTURE/install_v2" "$FIXTURE/meta_v2"
check "rollback v2 removed registered VERSION" 0 "$([[ ! -f "$FIXTURE/install_v2/VERSION" || "$(cat "$FIXTURE/install_v2/VERSION")" != "1.0.2" ]] && echo 0 || echo 1)"

# --- nested tarball (GitHub-style single top-level dir) must flatten ---
mkdir -p "$FIXTURE/nest/caelestia-shell-v1.0.2"
echo 'v1.0.2' >"$FIXTURE/nest/caelestia-shell-v1.0.2/VERSION"
echo "// nested shell" >"$FIXTURE/nest/caelestia-shell-v1.0.2/shell.qml"
tar -czf "$FIXTURE/nested.tar.gz" -C "$FIXTURE/nest" caelestia-shell-v1.0.2
run "extract nested" 0 "$SCRIPT" extract "$FIXTURE/nested.tar.gz" "$FIXTURE/staged_nested"
check "nested extract flattened" 0 "$([[ -f "$FIXTURE/staged_nested/VERSION" ]] && echo 0 || echo 1)"
check "nested flatten dropped wrapper" 0 "$([[ ! -d "$FIXTURE/staged_nested/caelestia-shell-v1.0.2" ]] && echo 0 || echo 1)"

# --- upgrade path: legacy install (no VERSION at all) -> v1.0.2 release shape ---
# Reproduces the real user situation: an install made before VERSION metadata
# existed, updated from a tarball built by release.yml (which now embeds VERSION).
# After the update the install must self-report 1.0.2 and the same release must
# no longer compare as newer.
mkdir -p "$FIXTURE/legacy_install"
echo "// legacy shell" >"$FIXTURE/legacy_install/shell.qml"
mkdir -p "$FIXTURE/legacy_install/plugins"
echo "plugin" >"$FIXTURE/legacy_install/plugins/demo.toml" # must survive apply
mkdir -p "$FIXTURE/legacy_payload/caelestia-shell-v1.0.2"
echo '1.0.2' >"$FIXTURE/legacy_payload/caelestia-shell-v1.0.2/VERSION"
echo "// 1.0.2 shell" >"$FIXTURE/legacy_payload/caelestia-shell-v1.0.2/shell.qml"
tar -czf "$FIXTURE/legacy-1.0.2.tar.gz" -C "$FIXTURE/legacy_payload" caelestia-shell-v1.0.2
check "legacy install has no VERSION" 0 "$([[ ! -f "$FIXTURE/legacy_install/VERSION" ]] && echo 0 || echo 1)"
run "legacy extract" 0 "$SCRIPT" extract "$FIXTURE/legacy-1.0.2.tar.gz" "$FIXTURE/legacy_staged"
run "legacy apply" 0 "$SCRIPT" apply "$FIXTURE/legacy_staged" "$FIXTURE/legacy_install" "$FIXTURE/legacy_meta"
check "legacy apply registers installed version" 0 "$([[ "$(cat "$FIXTURE/legacy_install/VERSION")" == "1.0.2" ]] && echo 0 || echo 1)"
check "legacy apply preserved plugins" 0 "$([[ -f "$FIXTURE/legacy_install/plugins/demo.toml" ]] && echo 0 || echo 1)"
check "registered release is not newer than itself" 0 \
    "$([ "$($SCRIPT compare "$(cat "$FIXTURE/legacy_install/VERSION")" 1.0.2)" == "0" ] && echo 0 || echo 1)"
run "legacy rollback restores pre-VERSION state" 0 "$SCRIPT" rollback "$FIXTURE/legacy_install" "$FIXTURE/legacy_meta"
check "legacy rollback removed VERSION" 0 "$([[ ! -f "$FIXTURE/legacy_install/VERSION" ]] && echo 0 || echo 1)"

# --- body digest is what the updater falls back to (QML side); ensure marker form ---
check "digest marker regex" 0 "$(printf 'x <!-- updater-digest sha256:%s --> y' "$DIGEST" | grep -qP 'sha256:?\s*[0-9a-fA-F]{64}' && echo 0 || echo 1)"

echo
echo "== result: $PASS passed, $FAIL failed =="
rm -rf "$FIXTURE"
[[ "$FAIL" -eq 0 ]]
