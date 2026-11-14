#!/bin/sh
# Argv router for setup.sh, tested without root: extracts the flag-scanning
# block from setup.sh and runs it against fixed argument lists.
set -u
SETUP="$1"
[ -f "$SETUP" ] || { echo "no setup.sh at $SETUP" >&2; exit 1; }

fails=0
checks=0

# The flag loop, sliced out of setup.sh: from WITH_MEDIA=0 through the loop's done.
router() {
    sed -n '/^WITH_MEDIA=0$/,/^done$/p' "$SETUP"
    printf 'printf "%%s|%%s\\n" "$WITH_MEDIA" "$PASS_ARGS"\n'
}

run() {
    checks=$((checks + 1))
    want=$1; shift
    out=$(router | sh -s -- "$@" 2>&1)
    case "$out" in
        *"$want"*) ;;
        *) fails=$((fails + 1)); printf 'FAILED: argv [%s]\n  want: %s\n  got:  %s\n' "$ARGV" "$want" "$out" ;;
    esac
}

ARGV="--with-media --yes";  run "1| --yes" --with-media --yes
ARGV="--with-media";        run "1|" --with-media
ARGV="--yes";               run "0| --yes" --yes
ARGV="";                    run "0|"

# The Forky routing decision, sliced out of setup.sh: forky and sid must take
# fix-forky.sh's path (install.sh cannot satisfy FFmpeg 7 there); trixie must not.
route() {
    sed -n '/^codename=$(sed/,/^esac$/p' "$SETUP"
    sed -n '/^NEED_FORKY_PATH=0$/,/^esac$/p' "$SETUP"
    printf 'printf "%%s\\n" "$NEED_FORKY_PATH"\n'
}

route_case() {
    checks=$((checks + 1))
    codename=$1; want=$2
    f=$(mktemp) || exit 1
    printf 'VERSION_CODENAME=%s\n' "$codename" > "$f"
    out=$(route | OS_RELEASE="$f" sh -s 2>&1)
    rm -f "$f"
    if [ "$out" != "$want" ]; then
        fails=$((fails + 1))
        printf 'FAILED: VERSION_CODENAME=%s -> want NEED_FORKY_PATH=%s, got %s\n' "$codename" "$want" "$out"
    fi
}

route_case forky 1
route_case sid   1
route_case trixie 0
route_case bookworm 0
route_case "" 0

printf '\n%d checks, %d failed\n' "$checks" "$fails"
[ "$fails" -eq 0 ]
