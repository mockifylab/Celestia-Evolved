.pragma library

// Release notes come from GitHub as markdown, which reads as noise when shown as
// plain text in the Updates page ("**bold**", "`code`", "[link](url)", HTML
// comment markers, "##" headings). This module turns that markup into something
// a person can actually read: prose, list items and link labels are preserved,
// while markup decoration and non-prose blocks (code fences, rules, badges) are
// dropped because they cannot be read as sentences on this surface.
//
// Deliberately free of Qt/Quickshell types so it can be unit tested with node.

function stripNoise(body) {
    let t = `${body === undefined || body === null ? "" : body}`;
    // HTML comments carry machine metadata (the updater digest marker).
    t = t.replace(/<!--[\s\S]*?-->/g, "");
    // Images and badges are decorative and unreadable as text.
    t = t.replace(/!\[[^\]]*\]\([^)]*\)/g, "");
    return t;
}

function stripInline(text) {
    let t = `${text}`;
    // Links: keep the label, drop the URL wrapper.
    t = t.replace(/\[([^\]]*)\]\([^)]*\)/g, "$1");
    // Emphasis and code, widest marker first so "**`x`**" collapses fully.
    t = t.replace(/\*\*\*([^*]+)\*\*\*/g, "$1");
    t = t.replace(/\*\*([^*]+)\*\*/g, "$1");
    t = t.replace(/__([^_]+)__/g, "$1");
    t = t.replace(/~~([^~]+)~~/g, "$1");
    t = t.replace(/`([^`]+)`/g, "$1");
    t = t.replace(/\*([^*\n]+)\*/g, "$1");
    t = t.replace(/(^|[^\w])_([^_\n]+)_(?=[^\w]|$)/g, "$1$2");
    return t;
}

// Returns null for lines that carry no readable content (rules, empty bullets).
// Blank lines are kept as "" because they separate paragraphs.
function formatLine(line) {
    const raw = `${line}`.replace(/\s+$/, "");
    if (raw.replace(/^\s*/, "") === "")
        return "";
    if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(raw))
        return null;
    let t = raw.replace(/^\s*#{1,6}\s+/, ""); // heading -> plain line
    t = t.replace(/^\s*>\s?/, ""); // blockquote
    t = t.replace(/^\s*[-*+]\s+/, "• "); // bullet
    t = t.replace(/^\s*(\d+)\.\s+/, "$1. "); // ordered list stays numbered
    t = stripInline(t).replace(/\s+$/, "");
    return t === "•" ? null : t;
}

function isFence(line) {
    return /^\s*(```|~~~)/.test(`${line}`);
}

// plain(body) -> the same notes as readable text.
function plain(body) {
    const lines = [];
    let inFence = false;
    for (const line of stripNoise(body).split("\n")) {
        // Fenced code is not prose; drop the block, not just its delimiters.
        if (isFence(line)) {
            inFence = !inFence;
            continue;
        }
        if (inFence)
            continue;
        const formatted = formatLine(line);
        if (formatted !== null)
            lines.push(formatted);
    }
    let out = lines.join("\n");
    out = out.replace(/\n{3,}/g, "\n\n");
    return out.trim();
}

// upToDate(installed, latest) -> the confirmation line for a system that has
// nothing left to install.
function upToDate(installed, latest) {
    const v = `${latest === undefined || latest === null ? "" : latest}`.replace(/^v/, "");
    const i = `${installed === undefined || installed === null ? "" : installed}`.replace(/^v/, "");
    if (v === "")
        return "No release information yet.";
    if (i !== "" && i === v)
        return `Version ${v} is installed. This is the newest release.`;
    return `Newest release: ${v}.`;
}
