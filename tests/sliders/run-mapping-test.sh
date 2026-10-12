#!/usr/bin/env bash
# Automated regression tests for the shared slider value-mapping maths used by
# every settings slider (modules/nexus/common/sliderMapping.js) and the shared
# write throttle (utils/writeThrottle.js).
# Covers: range boundaries, midpoints, step snapping (incl. negative ranges),
# float-artefact elimination, out-of-range validation, the exact ranges
# configured by the Appearance / Motion / Hyprland / Audio sliders, and the
# write throttle that stops a drag from writing one setting per pointer sample.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
SRC="$REPO/modules/nexus/common/sliderMapping.js"
THROTTLE_SRC="$REPO/utils/writeThrottle.js"
[ -f "$SRC" ] || { echo "FAIL: missing $SRC"; exit 1; }
[ -f "$THROTTLE_SRC" ] || { echo "FAIL: missing $THROTTLE_SRC"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# QML `.pragma library` is not Node JS; strip it, then export the functions.
strip_pragma() { grep -v '^\.pragma library$' "$1"; }

strip_pragma "$SRC" > "$WORK/mapping.js"
cat >> "$WORK/mapping.js" <<'EOF'
module.exports = { clamp, snap, positionToValue, decimalsOf };
EOF

strip_pragma "$THROTTLE_SRC" > "$WORK/throttle.js"
cat >> "$WORK/throttle.js" <<'EOF'
module.exports = { create, push, take, hasPending, reset };
EOF

cat > "$WORK/test.js" <<'EOF'
const m = require("./mapping.js");
const t = require("./throttle.js");
let fails = 0;
function check(name, ok) {
    if (ok) console.log(`ok   ${name}`);
    else { fails++; console.log(`FAIL ${name}`); }
}
function eq(actual, expected, name) {
    const ok = Object.is(actual, expected) || Math.abs(actual - expected) < 1e-12;
    if (!ok) { fails++; console.log(`FAIL ${name}: got ${actual}, want ${expected}`); }
    else console.log(`ok   ${name}`);
}

// --- clamp ---
eq(m.clamp(5, 0, 1), 1, "clamp above max");
eq(m.clamp(-5, 0, 1), 0, "clamp below min");
eq(m.clamp(0.4, 0, 1), 0.4, "clamp passthrough");

// --- decimalsOf: exact decimal depth of step grids ---
eq(m.decimalsOf(1), 0, "decimalsOf int");
eq(m.decimalsOf(0.05), 2, "decimalsOf 0.05");
eq(m.decimalsOf(0.01), 2, "decimalsOf 0.01");
eq(m.decimalsOf(0.30000000000000004), 1, "decimalsOf noisy 0.3");

// --- snap: grid anchored at `from`, float artefacts removed ---
eq(m.snap(1.24999, 0.5, 0.05), 1.25, "snap to 0.05 grid");
eq(m.snap(0.7000000000000001, 0, 0.01), 0.7, "snap kills float artefact");
eq(m.snap(-0.549999, -1, 0.05), -0.55, "snap negative grid");
eq(m.snap(13.4, 0, 1), 13, "snap integer grid");
eq(m.snap(0.456, 0, 0), 0.456, "snap disabled when step=0");

// --- positionToValue: the slider row contract (spec §2) ---
// Appearance: font scale 0.5..2 step 0.05
eq(m.positionToValue(0, 0.5, 2, 0.05), 0.5, "font min");
eq(m.positionToValue(1, 0.5, 2, 0.05), 2, "font max");
eq(m.positionToValue(0.5, 0.5, 2, 0.05), 1.25, "font mid");
eq(m.positionToValue(0.25, 0.5, 2, 0.05), 0.9, "font quarter snapped (.875 ties up)");
// Hyprland: gaps 0..40 step 1 (integer settings stay integers)
eq(m.positionToValue(0.333, 0, 40, 1), 13, "gaps third");
eq(m.positionToValue(1, 0, 40, 1), 40, "gaps max int");
// Hyprland: sensitivity -1..1 step 0.05 (negative range)
eq(m.positionToValue(0, -1, 1, 0.05), -1, "sens min negative");
eq(m.positionToValue(0.5, -1, 1, 0.05), 0, "sens zero");
eq(m.positionToValue(1, -1, 1, 0.05), 1, "sens max");
// Opacity 0.2..1 step 0.01
eq(m.positionToValue(0, 0.2, 1, 0.01), 0.2, "opacity min");
eq(m.positionToValue(0.5, 0.2, 1, 0.01), 0.6, "opacity mid");
// Audio: unit range, continuous (step 0)
eq(m.positionToValue(0.42, 0, 1, 0), 0.42, "audio continuous");
// Overshoot 0..1.6 step 0.05 (Motion page)
eq(m.positionToValue(1, 0, 1.6, 0.05), 1.6, "overshoot max");
eq(m.positionToValue(0.7, 0, 1.6, 0.05), 1.1, "overshoot 70%");
// Out-of-range positions are validated, not silently extrapolated
eq(m.positionToValue(2, 0, 1, 0.01), 1, "pos above 1 clamped");
eq(m.positionToValue(-1, 0, 1, 0.01), 0, "pos below 0 clamped");
// Result is always exactly representable on its own grid (no float dirt
// reaches persistence: stored value == displayed number == handle position)
for (let i = 0; i <= 100; i++) {
    const v = m.positionToValue(i / 100, 0.5, 2, 0.05);
    if (Math.abs(v - Math.round(v * 100) / 100) > 1e-12) {
        fails++; console.log(`FAIL sweep dirt at ${i / 100}: ${v}`); break;
    }
}
console.log("sweep 0..1 over font grid: clean");

// --- write throttle: the drag must not write per pointer sample (v1.0.3) ---
const th = t.create(40);
eq(t.push(th, 0, 0.5), 0.5, "throttle leading sample is applied");
eq(t.push(th, 8, 0.55), null, "throttle suppresses inside the window");
eq(t.hasPending(th), true, "throttle remembers the suppressed sample");
eq(t.push(th, 16, 0.6), null, "throttle keeps only the newest suppressed value");
eq(t.take(th, 40), 0.6, "throttle trailing value is the newest one");
eq(t.take(th, 41), null, "throttle trailing value is not replayed");
eq(t.push(th, 80, 0.7), 0.7, "throttle emits again once the window passes");
check("throttle never loses the last value of a drag", (() => {
    const s = t.create(40);
    let now = 0;
    let last = null;
    for (let i = 0; i < 200; i++) {
        now += 7;
        const v = 0.5 + i * 0.0075;
        const out = t.push(s, now, v);
        if (out !== null) last = out;
    }
    const trailing = t.take(s, now);
    if (trailing !== null) last = trailing;
    return Math.abs(last - (0.5 + 199 * 0.0075)) < 1e-12;
})());
check("throttle bounds the write rate", (() => {
    const s = t.create(40);
    let writes = 0;
    for (let ms = 0; ms <= 1000; ms += 8) if (t.push(s, ms, ms) !== null) writes++;
    return writes > 0 && writes <= 1000 / 40 + 2;
})());
eq(t.push(t.create(0), 5, 1), 1, "throttle interval 0 applies the first sample");
eq(t.push(t.create(0), 5, 2), 2, "throttle interval 0 applies every sample");
const rs = t.create(40);
t.push(rs, 0, 1);
t.reset(rs);
eq(t.push(rs, 1, 2), 2, "throttle reset re-arms the leading edge");

if (fails) { console.log(`${fails} FAILURES`); process.exit(1); }
console.log("ALL SLIDER MAPPING TESTS PASSED");
EOF

node "$WORK/test.js"
exit $?
