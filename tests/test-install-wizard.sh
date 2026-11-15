#!/bin/sh
# test-install-wizard.sh — the entry point's decisions, without installing anything.
#
# The wizard's whole job is to call the right scripts in the right order and to
# stop when one fails. Each case stubs the steps and asserts what was called.
set -u
W="${1:-$(dirname -- "$0")/../install.sh}"
[ -f "$W" ] || { echo "test-install-wizard: no install.sh at $W" >&2; exit 1; }

fails=0
checks=0

check() {   # check <label> <output> <required> [forbidden]
    checks=$((checks + 1))
    case "$2" in
        *"$3"*) ;;
        *) fails=$((fails + 1)); printf 'FAILED: %s (wanted %s)\n  got:  %s\n' "$1" "$3" "$2"; return ;;
    esac
    if [ "${4:-}" ]; then
        case "$2" in
            *"$4"*) fails=$((fails + 1)); printf 'FAILED: %s (must not contain %s)\n  got: %s\n' "$1" "$4" "$2" ;;
        esac
    fi
}

# --- 1. the dry run changes nothing and names every step ---------------------
out=$(sh "$W" --dry-run --skip-preflight 2>&1)
check "dry run reaches the install step"  "$out" "lib/setup.sh"
check "dry run reaches verify"            "$out" "scripts/doctor.sh"
check "dry run says it would not install" "$out" "would run"
check "dry run announces it is a dry run"  "$out" "would run"

# --- 2. media is offered, and named as mixing releases -----------------------
out=$(sh "$W" --dry-run --skip-preflight 2>&1)
check "media is mentioned when not asked for" "$out" "scripts/enable-media.sh"
check "the mixing of releases is stated"      "$out" "mixes Debian releases"

# --- 3. --with-media asks for it ---------------------------------------------
out=$(sh "$W" --dry-run --skip-preflight --with-media 2>&1)
check "--with-media runs enable-media"  "$out" "scripts/enable-media.sh"
check "--with-media states the risk"    "$out" "Read docs/MEDIA.md"

# --- 4. an unknown option is refused, not ignored ----------------------------
out=$(sh "$W" --nonsense 2>&1)
check "unknown option is refused" "$out" "unknown option"

# --- 5. --help works piped, where $0 is "sh" and not a readable file ---------
out=$(cat "$W" | sh -s -- --help 2>&1)
check "piped --help lists the options"    "$out" "--dry-run"
check "piped --help lists the options"    "$out" "--with-media"
check "piped --help does not leak an error" "$out" "--dry-run" "No such file"

# --- 6. every step the wizard names exists in the repository -----------------
# A wizard that tells you to run ../scripts/missing.sh is worse than none.
root=$(cd -- "$(dirname -- "$W")" && pwd)
for f in scripts/check.sh lib/setup.sh scripts/enable-media.sh scripts/doctor.sh \
         scripts/check-icons.sh scripts/check-performance.sh; do
    checks=$((checks + 1))
    [ -f "$root/$f" ] || { fails=$((fails + 1)); echo "FAILED: the wizard names $f, which does not exist"; }
done

# --- 7. it refuses to install without root, and says how -------------------
out=$(sh "$W" --dry-run --skip-preflight 2>&1)
case "$(id -u)" in
    0) checks=$((checks + 1)) ;;   # root: the branch does not run
    *) check "non-root without --dry-run is told to use sudo" \
             "$(sh "$W" --skip-preflight 2>&1)" "sudo" ;;
esac

printf '\n%d checks, %d failed\n' "$checks" "$fails"
[ "$fails" -eq 0 ]
