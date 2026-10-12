.pragma library

// Shared slider value-mapping maths (v1.0.2).
//
// Single source of truth for converting a normalised slider position ([0..1])
// into an actual setting value and back. Keeping it as pure functions (no Qt
// types) makes it unit-testable outside a running shell — see
// tests/sliders/run-fixture.sh.

function clamp(value, from, to) {
    return Math.max(from, Math.min(to, value));
}

// Snap `value` onto the step grid anchored at `from`, then round away binary
// float artefacts (e.g. 0.7000000000000001) so the stored value, the displayed
// number and the handle position are all the exact same number.
function snap(value, from, step) {
    if (step <= 0) {
        return value;
    }
    const decimals = decimalsOf(step);
    const snapped = Math.round((value - from) / step) * step + from;
    return decimals > 0 ? parseFloat(snapped.toFixed(decimals)) : Math.round(snapped);
}

// Number of decimal places needed to represent `step` exactly (tolerating
// float representation noise like 0.30000000000000004).
function decimalsOf(step) {
    for (let d = 0; d <= 8; d++) {
        const scaled = step * Math.pow(10, d);
        if (Math.abs(scaled - Math.round(scaled)) < 1e-9) {
            return d;
        }
    }
    return 8;
}

// Map a normalised position (handle travel, 0..1) to an actual value in
// [from..to], snapped to the step grid and clamped to the range.
function positionToValue(pos, from, to, step) {
    const actual = from + clamp(pos, 0, 1) * (to - from);
    return clamp(snap(actual, from, step), from, to);
}