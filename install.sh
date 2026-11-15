#!/bin/sh
# install.sh — LordOS on Apple Silicon: one entry point for the whole install.
#
#   curl -fsSL https://raw.githubusercontent.com/vidokun/lordos-m1/main/install.sh | sudo sh
#
# It runs the steps in order and stops at the first one that fails:
#
#   1. preflight   the machine, the kernel, the display, speakersafetyd
#   2. install     LordOS itself (repacked on Debian forky, where FFmpeg 8 replaces 7)
#   3. verify      services, display, icons, audio
#   4. next steps  what is left, as commands to copy
#
# Every step is one of the scripts in this repository, so each can still be run
# alone. Nothing here touches macOS, and nothing partitions a disk: that is the
# Asahi installer's job, before this runs (see README).
#
# Options:
#   --dry-run            show what each step would run, change nothing
#   --skip-preflight     go straight to the install
#   --with-media         also enable video, camera and microphone (mixes Debian
#                        releases; read docs/MEDIA.md first)
#   --yes                do not ask anything
#   -h, --help           this text

set -u

RED=''; GRN=''; YLW=''; BLD=''; OFF=''
if [ -t 1 ]; then
    RED=$(printf '\033[31m'); GRN=$(printf '\033[32m')
    YLW=$(printf '\033[33m'); BLD=$(printf '\033[1m'); OFF=$(printf '\033[0m')
fi

step()  { printf '\n%s== %s ==%s\n\n' "$BLD" "$1" "$OFF"; }
say()   { printf '%s\n' "$*"; }
ok()    { printf '  %s✓%s %s\n' "$GRN" "$OFF" "$1"; }
warn()  { printf '  %s!%s %s\n' "$YLW" "$OFF" "$1"; }
bad()   { printf '  %s✗%s %s\n' "$RED" "$OFF" "$1"; }
die()   { printf '\n%s✗ %s%s\n\n' "$RED" "$1" "$OFF" >&2; exit 1; }

RAW="${LORDOS_RAW:-https://raw.githubusercontent.com/vidokun/lordos-m1/main}"

# Piped (curl | sh), $0 is "sh" and there is no repository next to us: every
# script is fetched instead. Run from a clone, the local files are used, which
# is what the tests do.
DIR=$(dirname -- "$0" 2>/dev/null)
[ -f "$0" ] && DIR=$(cd -- "$DIR" 2>/dev/null && pwd) || DIR=""
[ -d "$DIR" ] || DIR=""
if [ -n "$DIR" ] && [ ! -f "$DIR/install.sh" ]; then DIR=""; fi

DRY=0; SKIP_PRE=0; WITH_MEDIA=0; PASS_YES=0
for a in "$@"; do
    case "$a" in
        --dry-run) DRY=1 ;;
        --skip-preflight) SKIP_PRE=1 ;;
        --with-media) WITH_MEDIA=1 ;;
        --yes|-y) PASS_YES=1 ;;
        -h|--help)
            # Piped (curl | sh), $0 is "sh": not a file to read. Print the usage
            # that matters instead of a sed error. The full header is above.
            if [ -f "$0" ]; then
                sed -n '2,30p' "$0"
            else
                cat <<'USAGE'
LordOS on Apple Silicon — one entry point for the whole install.

  curl -fsSL https://raw.githubusercontent.com/vidokun/lordos-m1/main/install.sh | sudo sh

Options:
  --dry-run          show what each step would run, change nothing
  --skip-preflight   go straight to the install
  --with-media       also enable video, camera and microphone
                     (mixes Debian releases; read docs/MEDIA.md first)
  --yes              do not ask anything
  -h, --help         this text
USAGE
            fi
            exit 0 ;;
        *) die "unknown option: $a (see --help)" ;;
    esac
done

[ "$(id -u)" -eq 0 ] || [ "$DRY" -eq 1 ] || {
    say "The installer needs root. Run it again with sudo, or type:"
    say ""
    say "    curl -fsSL $RAW/install.sh | sudo sh"
    exit 1
}

# fetch_or_local <path inside the repo> → prints a path to a runnable script
TMPDIR_SCRIPTS=""
cleanup() { [ -n "$TMPDIR_SCRIPTS" ] && rm -rf "$TMPDIR_SCRIPTS"; }
trap cleanup EXIT

fetch_or_local() {
    if [ -n "$DIR" ] && [ -f "$DIR/$1" ]; then
        printf '%s' "$DIR/$1"
        return 0
    fi
    [ -n "$TMPDIR_SCRIPTS" ] || TMPDIR_SCRIPTS=$(mktemp -d) || return 1
    out="$TMPDIR_SCRIPTS/$(basename "$1")"
    curl -fsSL -o "$out" "$RAW/$1" 2>/dev/null || { rm -f "$out"; return 1; }
    printf '%s' "$out"
}

run_step() {   # run_step <label> <repo path> [args...]
    label=$1; path=$2; shift 2
    script=$(fetch_or_local "$path") || die "could not fetch $path — check the network"
    if [ "$DRY" -eq 1 ]; then
        ok "$label: would run $path $*"
        return 0
    fi
    say "  running $path $*"
    if [ "$PASS_YES" -eq 1 ]; then
        sh "$script" "$@" --yes || return 1
    else
        sh "$script" "$@" || return 1
    fi
}

stepline() { printf '  → %s\n' "$*"; }

# ---------------------------------------------------------------- 1. preflight

step "1/4  Preflight"
say "  Reading the machine. Nothing is installed in this step."
say ""

if [ "$SKIP_PRE" -eq 1 ]; then
    warn "skipped (--skip-preflight)"
else
    if ! run_step "preflight" "scripts/check.sh"; then
        die "the preflight check says this machine is not ready. Fix what it lists (✗), then run this installer again."
    fi
fi

# ---------------------------------------------------------------- 2. install

step "2/4  Installing LordOS"

if [ "$DRY" -eq 1 ]; then
    stepline "lib/setup.sh  (checks the kernel, installs asahi-platform, then:)"
    stepline "  - Debian forky/sid → lib/fix-forky.sh, then lib/finish-setup.sh"
    stepline "  - Debian trixie   → lib/lordos-install.sh"
else
    if ! run_step "install" "lib/setup.sh"; then
        die "the install stopped. Your Debian is unchanged. Copy the message above."
    fi
fi

# ---------------------------------------------------------------- 3. media

if [ "$WITH_MEDIA" -eq 1 ]; then
    step "3/4  Enabling media (video, camera, microphone)"
    warn "this mixes Debian releases: FFmpeg 7 from trixie. Read docs/MEDIA.md."
    if ! run_step "media" "scripts/enable-media.sh" --apply; then
        warn "media was not enabled. Everything else still works; try later with:"
        say "      sudo sh scripts/enable-media.sh --apply"
    fi
else
    step "3/4  Media (video, camera, microphone)"
    say "  Skipped. On Debian forky these stay off: the package needs FFmpeg 7,"
    say "  forky has 8. Turn them on later (it mixes Debian releases, read the doc):"
    say ""
    say "      sudo sh scripts/enable-media.sh --apply"
fi

# ---------------------------------------------------------------- 4. verify

step "4/4  Verifying"

if [ "$DRY" -eq 1 ]; then
    ok "verify: would run scripts/doctor.sh"
else
    if run_step "verify" "scripts/doctor.sh"; then
        ok "the post-install check passed"
    else
        warn "the post-install check found something. It is listed above; run it again with:"
        say "      sh scripts/doctor.sh"
    fi
fi

# ---------------------------------------------------------------- next steps

step "Done"

say "  Reboot to reach the LordOS login screen:"
say ""
say "      sudo reboot"
say ""
say "  If icons are missing after logging in (they are text glyphs, not images):"
say ""
say "      sudo sh scripts/check-icons.sh --install"
say ""
say "  If the desktop moves slowly, measure before changing anything:"
say ""
say "      sh scripts/check-performance.sh"
say ""
say "  Read this before reporting a problem:"
say ""
say "      sh scripts/doctor.sh"
say ""
