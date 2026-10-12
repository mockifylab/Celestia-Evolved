.pragma library

// Write throttle (v1.0.3).
//
// A drag or a scroll emits one event per pointer sample (60-120 per second).
// Every emitted value can become a settings write or a hardware round trip
// (Pipewire volume, compositor rule, MPRIS seek), and each of those is far more
// expensive than the frame that produced it. The visual state must follow the
// pointer exactly, while the outward write should be coalesced.
//
// These functions keep that policy as plain data: `now` is always passed in by
// the caller and never read from a clock here, which makes the behaviour unit
// testable outside a running shell — see tests/sliders/run-mapping-test.sh.

function create(interval) {
    return { interval: interval, last: -1, pending: null };
}

// Returns the value to emit now, or null when this sample is suppressed and has
// been remembered as the pending value.
function push(state, now, value) {
    if (state.interval <= 0 || state.last < 0 || now - state.last >= state.interval) {
        state.last = now;
        state.pending = null;
        return value;
    }
    state.pending = value;
    return null;
}

function hasPending(state) {
    return state.pending !== null;
}

// Hands back the suppressed value, if any, so the end of a drag is always
// applied even when it landed inside a suppressed window.
function take(state, now) {
    if (state.pending === null)
        return null;
    const value = state.pending;
    state.pending = null;
    state.last = now;
    return value;
}

function reset(state) {
    state.last = -1;
    state.pending = null;
}
