#!/bin/sh
# Verifies setup.sh's Forky branch actually calls fix-forky.sh then
# finish-setup.sh (and passes --with-media), and that trixie does not.
#
# It slices the real branch out of setup.sh rather than running the whole script,
# because the earlier sections check for Apple hardware and root — neither of
# which a test machine has.
set -u
SETUP="${1:-/Users/dokun/Documents/VIBECODING/lordos/lordos-m1/setup.sh}"
[ -f "$SETUP" ] || { echo "dryrun: no setup.sh at $SETUP" >&2; exit 1; }

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

# Stubs that record how each helper was invoked.
for s in fix-forky.sh finish-setup.sh install.sh; do
    printf '#!/bin/sh\necho "%s called: $*"\nexit 0\n' "$s" > "$work/$s"
done

fails=0
checks=0

# The branch, located by content rather than by a fixed line number so that the
# test survives edits above it: from the Forky comment to the "fi" that closes it.
branch() {
    start=$(grep -n '^# Debian Forky (dan sid) TIDAK bisa' "$SETUP" | cut -d: -f1)
    [ -n "$start" ] || { echo "DRYRUN: forky branch not found" >&2; exit 1; }
    end=$(awk -v s="$start" 'NR>s && /^fi$/ { print NR; exit }' "$SETUP")
    [ -n "$end" ] || { echo "DRYRUN: forky branch end not found" >&2; exit 1; }
    sed -n "${start},${end}p" "$SETUP"
}

# Everything the branch depends on from the top of the script. GRN/BLD/OFF are
# the colour variables the success message uses; without them the branch would
# print the literal "%s" and still exit 0, hiding a real breakage.
prelude() {
    printf 'GRN=""; BLD=""; OFF=""; RED=""; YLW=""\n'
    printf 'say() { :; }; ok() { :; }; warn() { :; }; hdr() { :; }\n'
    printf 'die() { echo "DIE $*"; exit 1; }\n'
    printf 'DIR="%s"; RAW="file://%s"; PASS_ARGS=""; to_clean=""\n' \
        "$work" "$work"
}

run_case() {
    checks=$((checks + 1))
    codename=$1; expect=$2; forbid=$3
    os=$(mktemp) || exit 1
    printf 'VERSION_CODENAME=%s\n' "$codename" > "$os"
    out=$({ prelude; branch; } | OS_RELEASE="$os" sh -s 2>&1)
    rm -f "$os"
    case "$out" in
        *"$expect"*) ;;
        *) fails=$((fails + 1)); printf 'FAILED [%s]: want %s\n  got: %s\n' "$codename" "$expect" "$out" ;;
    esac
    if [ -n "$forbid" ]; then
        case "$out" in
            *"$forbid"*) fails=$((fails + 1)); printf 'FAILED [%s]: must NOT contain %s\n  got: %s\n' "$codename" "$forbid" "$out" ;;
        esac
    fi
}

run_case forky "fix-forky.sh called:" "install.sh called"
run_case forky "finish-setup.sh called:" ""
run_case sid "fix-forky.sh called:" "install.sh called"

# Media is a separate script now (enable-media.sh, run after the install) and it
# reuses the installed package instead of downloading 31 MB again. setup.sh must
# therefore never hand --with-media to fix-forky.sh any more.
run_case forky "" "--with-media"
run_case sid "" "--with-media"

# trixie and older releases must NOT take the forky branch. The branch stops at
# its closing `fi`, so "no forky output" is the assertion — not "install.sh ran",
# which happens after the branch.
run_case trixie "" "fix-forky"
run_case bookworm "" "fix-forky"

# A forky run that stops at fix-forky must not claim success.
run_partial() {
    checks=$((checks + 1))
    os=$(mktemp) || exit 1
    printf 'VERSION_CODENAME=forky\n' > "$os"
    # fail at fix-forky.sh: the branch must stop, not run finish-setup.sh
    printf '#!/bin/sh\nexit 3\n' > "$work/fix-forky.sh"
    out=$({ prelude 0; branch; } | OS_RELEASE="$os" sh -s 2>&1)
    printf '#!/bin/sh\necho "fix-forky.sh called: $*"\nexit 0\n' > "$work/fix-forky.sh"
    rm -f "$os"
    case "$out" in
        *"finish-setup.sh called"*) fails=$((fails + 1)); printf 'FAILED: a failed fix-forky must stop the run\n  got: %s\n' "$out" ;;
        *"Reboot untuk masuk"*) fails=$((fails + 1)); printf 'FAILED: a failed fix-forky must not print success\n  got: %s\n' "$out" ;;
        *"berhenti dengan kode 3"*) ;;
        *) fails=$((fails + 1)); printf 'FAILED: expected the failure to be reported, got: %s\n' "$out" ;;
    esac
}
run_partial

printf '\n%d checks, %d failed\n' "$checks" "$fails"
[ "$fails" -eq 0 ]
