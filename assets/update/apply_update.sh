#!/usr/bin/env bash
#
# Celestia Shell Reimagined — safe in-app updater helper.
#
# This script is the single source of truth for the safety-critical parts of
# the in-app update flow. The QML `Updater` service only orchestrates these
# subcommands; every destructive step keeps a known-good backup so it can be
# rolled back.
#
# Subcommands:
#   fetch    <url> <out>              Download a release asset (supports file://).
#   verify   <file> <expected_sha256> Check SHA-256; exit 0 ok / 3 mismatch.
#   compare  <a> <b>                  Print -1|0|1 for semver a<=>b.
#   extract  <tarball> <dir>          Extract a release tarball into <dir>.
#   apply    <staged> <install> <meta>Back up <install>, then activate <staged>.
#   rollback <install> <meta>         Restore the last backup made by `apply`.
#   status   <meta>                   Print current rollback availability as KV.
#
# Exit codes: 0 ok, 1 general error, 2 usage, 3 checksum mismatch,
#             4 missing backup, 5 validation failure.
#
set -euo pipefail

die() { echo "$*" >&2; exit "${EXITCODE:-1}"; }

usage() {
    echo "usage: apply_update.sh <fetch|verify|compare|extract|apply|rollback|status> ..." >&2
    exit 2
}

# Normalise a version string: strip leading v/whitespace.
norm() {
    local v="${1// }"
    v="${v#"${v%%[![:space:]]*}"}" # ltrim
    v="${v// }"                     # no internal spaces
    echo "${v#v}"
}

# Compare two semver strings (major.minor.patch, optional -prerelease).
# Prints -1 when a<b, 0 when equal, 1 when a>b.
semver_compare() {
    local a b
    a="$(norm "$1")"
    b="$(norm "$2")"

    # Split off any pre-release suffix for a simple lexical tie-break.
    local ap="${a%%-*}" bp="${b%%-*}"
    local a_pre="" b_pre=""
    [[ "$a" == *-* ]] && a_pre="${a#*-}"
    [[ "$b" == *-* ]] && b_pre="${b#*-}"

    local IFS=.
    # shellcheck disable=SC2206
    local aa=($ap) bb=($bp)
    local i x y
    for ((i = 0; i < 3; i++)); do
        x="${aa[i]:-0}"; y="${bb[i]:-0}"
        # coerce non-numeric to 0
        [[ "$x" =~ ^[0-9]+$ ]] || x=0
        [[ "$y" =~ ^[0-9]+$ ]] || y=0
        if ((x < y)); then echo -1; return; fi
        if ((x > y)); then echo 1; return; fi
    done

    # Same numeric core: a release outranks a pre-release.
    if [[ -z "$a_pre" && -n "$b_pre" ]]; then echo 1; return; fi
    if [[ -n "$a_pre" && -z "$b_pre" ]]; then echo -1; return; fi
    if [[ "$a_pre" < "$b_pre" ]]; then echo -1; return; fi
    if [[ "$a_pre" > "$b_pre" ]]; then echo 1; return; fi
    echo 0
}

require_sha256_tool() {
    if command -v sha256sum >/dev/null 2>&1; then
        SHA_TOOL="sha256sum"
    elif command -v shasum >/dev/null 2>&1; then
        SHA_TOOL="shasum -a 256"
    else
        die "no sha256sum or shasum available"
    fi
}

sha256_of() {
    # shellcheck disable=SC2086
    $SHA_TOOL "$1" | awk '{print $1}'
}

cmd_fetch() {
    local url="${1:-}" out="${2:-}"
    [[ -n "$url" && -n "$out" ]] || usage
    mkdir -p "$(dirname "$out")"
    # Normalise a bare filesystem path into a file:// URI so curl is happy.
    local target="$url"
    if [[ "$url" != *"://"* && -e "$url" ]]; then
        target="file://$(readlink -f "$url")"
    fi
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 2 -o "$out" "$target" || die "fetch failed: $url"
    elif command -v wget >/dev/null 2>&1; then
        wget -q -O "$out" "$target" || die "fetch failed: $url"
    else
        [[ "$target" == file://* ]] || die "need curl/wget for remote url"
        cp "${target#file://}" "$out" || die "copy failed: $url"
    fi
    [[ -s "$out" ]] || die "downloaded file is empty"
    echo "fetched $out"
}

cmd_verify() {
    local file="${1:-}" expected="${2:-}"
    [[ -n "$file" && -n "$expected" ]] || usage
    [[ -f "$file" ]] || die "no such file: $file"
    require_sha256_tool
    expected="$(echo "$expected" | tr 'A-F' 'a-f' | sed 's/^sha256://')"
    local actual
    actual="$(sha256_of "$file" | tr 'A-F' 'a-f')"
    if [[ "$actual" == "$expected" ]]; then
        echo "verified $actual"
    else
        echo "checksum mismatch: expected $expected got $actual" >&2
        exit 3
    fi
}

cmd_compare() {
    local a="${1:-}" b="${2:-}"
    [[ -n "$a" && -n "$b" ]] || usage
    semver_compare "$a" "$b"
}

cmd_extract() {
    local tarball="${1:-}" dir="${2:-}"
    [[ -n "$tarball" && -n "$dir" ]] || usage
    [[ -f "$tarball" ]] || die "no such tarball: $tarball"
    rm -rf "$dir"
    mkdir -p "$dir"
    case "$tarball" in
        *.zip)
            command -v unzip >/dev/null 2>&1 || die "unzip required for zip assets"
            unzip -q "$tarball" -d "$dir" || die "extraction failed"
            ;;
        *)
            tar -xf "$tarball" -C "$dir" || die "extraction failed"
            ;;
    esac

    # GitHub release archives wrap everything in a single top-level directory
    # (e.g. caelestia-shell-v1.0.1/). Flatten exactly one such wrapper so the
    # payload sits directly under <dir>, which is what `apply` mirrors in.
    local -a top=("$dir"/* "$dir"/.[!.]*)
    local -a real=()
    local e
    for e in "${top[@]}"; do
        [[ -e "$e" ]] && real+=("$e")
    done
    if [[ ${#real[@]} -eq 1 && -d "${real[0]}" ]]; then
        local wrapper="${real[0]}"
        # shellcheck disable=SC2015
        ( shopt -s dotglob nullglob; mv "$wrapper"/* "$dir"/ ) && rmdir "$wrapper" 2>/dev/null || true
    fi
    echo "extracted to $dir"
}

cmd_apply() {
    local staged="${1:-}" install="${2:-}" meta="${3:-}"
    [[ -n "$staged" && -n "$install" && -n "$meta" ]] || usage
    [[ -d "$staged" ]] || { EXITCODE=5 die "staged dir missing: $staged"; }
    [[ -d "$install" ]] || { EXITCODE=5 die "install dir missing: $install"; }

    mkdir -p "$meta"
    local backup="$meta/backup"
    rm -rf "$backup"
    cp -a "$install" "$backup" || die "backup failed"

    # Record rollback coordinates before touching the install dir.
    {
        echo "rollback_path=$backup"
        echo "install=$install"
        echo "applied_from=$staged"
        echo "applied_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    } >"$meta/rollback.env"

    # Activate: mirror staged into install, preserving user config files.
    # -c forces a content (checksum) comparison so files that happen to share
    # size+mtime with the old install are still refreshed correctly.
    rsync -ac --delete \
        --exclude 'user.conf' \
        --exclude 'user.conf.d' \
        --exclude '.cache' \
        "$staged/" "$install/" || {
        # On failure, restore the snapshot we just took.
        rsync -ac --delete "$backup/" "$install/" || die "apply failed AND restore failed"
        die "apply failed; restored previous version"
    }
    echo "applied"
}

cmd_rollback() {
    local install="${1:-}" meta="${2:-}"
    [[ -n "$install" && -n "$meta" ]] || usage
    local backup="$meta/backup"
    [[ -d "$backup" ]] || { EXITCODE=4 die "no backup to roll back to"; }
    rsync -ac --delete --exclude 'user.conf' --exclude 'user.conf.d' \
        "$backup/" "$install/" || die "rollback failed"
    echo "rolled-back"
}

cmd_status() {
    local meta="${1:-}"
    [[ -n "$meta" ]] || usage
    if [[ -f "$meta/rollback.env" ]]; then
        echo "rollback_available=1"
        # shellcheck disable=SC1091
        sed 's/^/env_/' "$meta/rollback.env"
    else
        echo "rollback_available=0"
    fi
}

main() {
    local mode="${1:-}"
    shift || true
    case "$mode" in
        fetch) cmd_fetch "$@" ;;
        verify) cmd_verify "$@" ;;
        compare) cmd_compare "$@" ;;
        extract) cmd_extract "$@" ;;
        apply) cmd_apply "$@" ;;
        rollback) cmd_rollback "$@" ;;
        status) cmd_status "$@" ;;
        *) usage ;;
    esac
}

main "$@"
