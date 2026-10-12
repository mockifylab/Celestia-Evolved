#!/usr/bin/env bash
#
# Fixture test for the palette design system (services/ColorGen.qml and
# services/BuiltinPalettes.qml). Runs the real singletons headless under
# quickshell (offscreen platform) and asserts on the emitted RESULT lines:
# seed validation, role completeness, dark/light coordination, terminal ramp,
# text contrast and determinism.
#
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_DIR="$(cd "$ROOT/../.." && pwd)"
FIXTURE="$(mktemp -d /tmp/palette_fixture.XXXXXX)"
PASS=0
FAIL=0

cleanup() { rm -rf "$FIXTURE"; }
trap cleanup EXIT

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

check() { # <name> <want> <got>
    local name="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then
        echo "PASS: $name"
        PASS=$((PASS + 1))
    else
        echo "FAIL: $name (want '$want', got '$got')"
        FAIL=$((FAIL + 1))
    fi
}

echo "== palette fixture: $FIXTURE =="

# Throwaway quickshell config tree wiring the real service singletons. Nothing
# is copied into the repo tree.
PROJ="$FIXTURE/proj"
mkdir -p "$PROJ/services"
cp "$ROOT/shell.qml" "$PROJ/shell.qml"
ln -sf "$SHELL_DIR/services/ColorGen.qml" "$PROJ/services/ColorGen.qml"
ln -sf "$SHELL_DIR/services/BuiltinPalettes.qml" "$PROJ/services/BuiltinPalettes.qml"

OUT="$FIXTURE/harness.out"
env \
    QT_QPA_PLATFORM=offscreen \
    QML2_IMPORT_PATH="$SHELL_DIR/build/qml:${QML2_IMPORT_PATH:-/usr/lib/qt6/qml}" \
    timeout 60 qs -p "$PROJ/shell.qml" >"$OUT" 2>&1
RC=$?
echo "harness exit: $RC"
sed 's/^/  | /' "$OUT"

check "harness exited 0" 0 "$RC"

for name in \
    "valid 6-digit seed accepted" \
    "valid 3-digit seed accepted" \
    "missing hash rejected" \
    "garbage rejected" \
    "empty rejected" \
    "built-in palettes registered" \
    "every built-in palette is complete" \
    "every built-in palette has a terminal ramp" \
    "built-in text/background contrast holds" \
    "dark and light differ" \
    "unknown palette returns empty" \
    "known palette id recognised" \
    "generation is deterministic" \
    "bogus seed still yields a usable palette" \
    "design knobs are honoured" \
    "grey seed is given an accent"; do
    check_file "qml: $name" "^.*RESULT\|$name\|ok" "$OUT"
done

check_file "no failing assertions" 'RESULT\|done\|failures=0' "$OUT"

echo
echo "== result: $PASS passed, $FAIL failed =="
[[ "$FAIL" -eq 0 ]] && exit 0 || exit 1
