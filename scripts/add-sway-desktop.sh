#!/bin/sh
# add-sway-desktop.sh — a Wayland desktop with a dock and a status bar, next to LordOS.
#
# Why this exists: LordOS's Dock and menu bar are parts of its own compositor's
# theme (themes/default/components/Dock.jsx draws them through the SDK's `Layer`,
# `screen` and `useDockCovered`) — they cannot be moved into another compositor.
# lord-server also takes DRM/KMS directly and has no nested mode, so LordOS cannot
# run inside another Wayland session either.
#
# What this does instead: sway (a wlroots compositor) with
#   - waybar          the status bar (top), configured to look like LordOS's
#   - nwg-dock        the dock (bottom), GTK, layer-shell
#   - fuzzel          the launcher, on Super
#   - dunst           notifications
#   - swww            wallpaper (optional; skipped when absent)
#
# It changes nothing about LordOS: the two sessions coexist and you choose at
# the login screen. Debian's default greeter (or LordOS's) starts sway from a
# session file, so both appear.
#
#   sh add-sway-desktop.sh              # check only, changes nothing
#   sudo sh add-sway-desktop.sh --apply # install and write the config
#   sudo sh add-sway-desktop.sh --revert
#
# Verified as available in Debian forky: sway, waybar, nwg-dock, fuzzel, dunst,
# wl-clipboard, grim, slurp, brightnessctl, playerctl.

set -u

RED=''; GRN=''; YLW=''; BLD=''; OFF=''
if [ -t 1 ]; then
    RED=$(printf '\033[31m'); GRN=$(printf '\033[32m')
    YLW=$(printf '\033[33m'); BLD=$(printf '\033[1m'); OFF=$(printf '\033[0m')
fi

say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n%s== %s ==%s\n\n' "$BLD" "$1" "$OFF"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$OFF" "$1"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$OFF" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$RED" "$OFF" "$1"; }
note() { printf '      %s\n' "$1"; }
die()  { printf '\n%s✗ %s%s\n\n' "$RED" "$1" "$OFF" >&2; exit 1; }

PACKAGES="sway waybar nwg-dock fuzzel dunst wl-clipboard grim slurp brightnessctl playerctl"

MODE=check
for a in "$@"; do
    case "$a" in
        --apply) MODE=apply ;;
        --revert) MODE=revert ;;
        -h|--help)
            if [ -f "$0" ]; then sed -n '2,26p' "$0"; else
                say "add-sway-desktop.sh — a Wayland desktop with a dock and a status bar"
                say "  (no args)  check only   --apply  install   --revert  undo"
            fi
            exit 0 ;;
        *) die "unknown option: $a (try --help)" ;;
    esac
done

as_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    say "This needs root. Running again with sudo..."
    exec sudo -E sh "$0" "$@"
}

# PASSWD_FILE lets the tests point this at a fixture; the script never writes it.
PASSWD_FILE="${PASSWD_FILE:-/etc/passwd}"
TARGET_USER="${SUDO_USER:-}"
[ -n "$TARGET_USER" ] || TARGET_USER=$(awk -F: -v f="$PASSWD_FILE" '$3>=1000 && $3<60000 {print $1; exit}' "$PASSWD_FILE" 2>/dev/null)
[ -n "$TARGET_USER" ] || die "no regular user found in $PASSWD_FILE"

home_of() {
    h=$(getent passwd "$1" 2>/dev/null | cut -d: -f6)
    [ -n "$h" ] || h=$(awk -F: -v u="$1" '$1==u {print $6; exit}' "$PASSWD_FILE" 2>/dev/null)
    printf '%s' "$h"
}

# ---------------------------------------------------------------- --revert

if [ "$MODE" = revert ]; then
    # No root needed: these are the user's own files. The session entry under
    # /usr/share is removed only when this already runs as root.
    hdr "Reverting"
    h=$(home_of "$TARGET_USER")
    [ -n "$h" ] || die "cannot find the home of $TARGET_USER"
    rm -f "$h/.config/sway/config.lordos-dock"
    rm -f "$h/.config/waybar/config.jsonc.lordos-dock"
    if [ "$(id -u)" -eq 0 ]; then
        rm -f /usr/share/wayland-sessions/sway-lordos-dock.desktop
        ok "config files and the session entry are removed"
    else
        ok "config files are removed"
        note "the session entry stays; remove it as root:"
        say "    sudo rm -f /usr/share/wayland-sessions/sway-lordos-dock.desktop"
    fi
    say ""
    note "The packages stay installed: other sessions may use them."
    note "Remove them yourself if you want:"
    say "    sudo apt remove sway waybar nwg-dock fuzzel dunst"
    say ""
    note "sway then falls back to its own default config, which still starts."
    exit 0
fi

# ---------------------------------------------------------------- 1. state

hdr "State"
[ "$(id -u)" -eq 0 ] || ok "check mode (nothing is changed)"
say "  user: $TARGET_USER"

# Read with sed, not `. /etc/os-release`: sourcing a system file executes it, and
# OS_RELEASE lets this be tested without Debian.
OS_F="${OS_RELEASE:-/etc/os-release}"
codename=$(sed -n 's/^VERSION_CODENAME=//p' "$OS_F" 2>/dev/null | head -n 1 | sed 's/^"//; s/"$//')
case "$codename" in
    forky|sid|trixie) ok "Debian $codename" ;;
    "") warn "Debian version not detected (no $OS_F)" ;;
    *)  warn "Debian $codename; written for forky/sid" ;;
esac

if command -v sway >/dev/null 2>&1; then
    ok "sway is installed"
else
    warn "sway is not installed yet"
fi

# Which of the wanted packages apt can actually provide here.
available=''
for p in $PACKAGES; do
    if apt-cache show "$p" >/dev/null 2>&1 && apt-cache policy "$p" 2>/dev/null | grep -q "Candidate: [0-9]"; then
        available="$available $p"
    else
        note "not in this Debian: $p (skipped)"
    fi
done
[ -n "$available" ] || die "none of the packages are available — is this Debian?"
say ""
note "will install:$available"
say ""

# ---------------------------------------------------------------- 2. plan

hdr "Plan"
say "  1. install:$available"
say "  2. write ~/.config/sway/config.lordos-dock (included by your sway config)"
say "  3. write ~/.config/waybar/config.jsonc.lordos-dock (top bar)"
say ""
note "LordOS is not touched: it keeps its own session and its own Dock."
note "sway and LordOS both appear in the login screen; you pick one."
say ""

if [ "$MODE" != apply ]; then
    printf '  To apply:\n\n    sudo sh %s --apply\n\n' "$(basename -- "$0")"
    note "Undo with --revert"
    exit 0
fi

# ---------------------------------------------------------------- 3. apply

as_root --apply

hdr "Installing"

# shellcheck disable=SC2086 # $available is a list of package names
if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -q --no-install-recommends $available; then
    die "the package install failed. Nothing else was changed."
fi
ok "installed"

hdr "Writing the configuration"

h=$(home_of "$TARGET_USER")
[ -d "$h" ] || die "no home directory for $TARGET_USER"
cfg="$h/.config"
mkdir -p "$cfg/sway" "$cfg/waybar"

# Sway: the LordOS-like fragment, pulled in with `include`.
cat > "$cfg/sway/config.lordos-dock" <<'SWAY'
# Written by add-sway-desktop.sh. LordOS-like layout: status bar on top,
# dock at the bottom, Super as the launcher key.
# Kept in its own file so `include` can be removed without touching your config.

# Super alone opens the launcher (fuzzel); the rest stay as sway ships them.
set $mod Mod4
bindsym $mod Return exec foot
bindsym $mod d exec fuzzel
bindsym $mod Shift+q kill
bindsym $mod Shift+e exec swaynag -t warning -m 'Exit sway?' -B 'Yes' 'swaymsg exit'

# Gaps and borders close to a floating desktop, not a tiling one.
gaps inner 8
gaps outer 4
default_border pixel 2
default_floating_border normal

# Status bar (top) and dock (bottom).
exec waybar -c ~/.config/waybar/config.jsonc.lordos-dock -s ~/.config/waybar/style.css
exec nwg-dock -d -i 40 -a start -p bottom -l top

# Notifications, wallpaper and clipboard if their packages are present.
exec sh -c 'command -v dunst >/dev/null 2>&1 && dunst'
exec sh -c 'command -v swww-daemon >/dev/null 2>&1 && swww-daemon'
exec sh -c 'command -v wl-paste >/dev/null 2>&1 && wl-paste --type text --watch cliphist store || true'

# Alt-drag moves windows, as on a desktop rather than a tiler.
floating_modifier $mod
SWAY
chown "$TARGET_USER": "$cfg/sway/config.lordos-dock"
ok "sway fragment: $cfg/sway/config.lordos-dock"

# Waybar: the status bar, mirroring LordOS's top strip.
cat > "$cfg/waybar/config.jsonc.lordos-dock" <<'WAYBAR'
// Written by add-sway-desktop.sh. A top bar: workspaces left, the clock in
// the middle, the tray and the volume/battery on the right.
{
  "layer": "top",
  "position": "top",
  "height": 32,
  "spacing": 8,
  "modules-left": ["sway/workspaces", "sway/mode"],
  "modules-center": ["sway/window", "clock"],
  "modules-right": ["tray", "pulseaudio", "backlight", "battery", "network"],

  "sway/workspaces": { "disable-scroll": true, "all-outputs": true },
  "sway/window": { "max-length": 60 },
  "clock": { "format": "{:%a %d %b  %H:%M}", "tooltip-format": "{calendar}" },
  "tray": { "icon-size": 18, "spacing": 8 },
  "pulseaudio": { "format": "{icon} {volume}%", "format-muted": "muted" },
  "backlight": { "format": "{percent}%", "device": "intel_backlight" },
  "battery": { "format": "{capacity}%", "states": { "warning": 20, "critical": 10 } },
  "network": { "format-wifi": "{essid}", "format-ethernet": "wired", "format-disconnected": "off" }
}
WAYBAR
chown "$TARGET_USER": "$cfg/waybar/config.jsonc.lordos-dock"
ok "waybar config: $cfg/waybar/config.jsonc.lordos-dock"

# ---------------------------------------------------------------- 4. wire it

hdr "Wiring it in"

# sway reads ~/.config/sway/config; create one if there is none, and add the
# include once if there is.
swcfg="$cfg/sway/config"
if [ ! -f "$swcfg" ]; then
    cat > "$swcfg" <<'MAIN'
# Written by add-sway-desktop.sh. sway's own default config is replaced by this
# file the first time; the LordOS-like layout lives in the include below.
include ~/.config/sway/config.lordos-dock
MAIN
    chown "$TARGET_USER": "$swcfg"
    ok "created $swcfg"
elif grep -q "config.lordos-dock" "$swcfg"; then
    ok "$swcfg already includes the fragment"
else
    printf '\ninclude ~/.config/sway/config.lordos-dock\n' >> "$swcfg"
    chown "$TARGET_USER": "$swcfg"
    ok "appended the include to $swcfg"
fi

# A session entry, so a display manager offers sway next to LordOS.
if [ -d /usr/share/wayland-sessions ]; then
    cat > /usr/share/wayland-sessions/sway-lordos-dock.desktop <<'DESK'
[Desktop Entry]
Name=Sway (LordOS-like)
Comment=A wlroots Wayland desktop with a top bar and a bottom dock
Exec=sway
Type=Application
DESK
    ok "session entry: sway appears in the login screen"
else
    warn "/usr/share/wayland-sessions is missing; start sway from a TTY with: sway"
fi

# ---------------------------------------------------------------- 5. verify

hdr "Verify"
n=0
for p in sway waybar nwg-dock fuzzel; do
    if command -v "${p%%-*}" >/dev/null 2>&1 || dpkg -s "$p" >/dev/null 2>&1; then
        ok "$p present"
    else
        bad "$p missing"; n=$((n+1))
    fi
done
[ -f "$cfg/sway/config.lordos-dock" ] && ok "fragment written" || { bad "fragment missing"; n=$((n+1)); }
[ -f "$cfg/waybar/config.jsonc.lordos-dock" ] && ok "waybar config written" || { bad "waybar config missing"; n=$((n+1)); }

if [ "$n" -ne 0 ]; then
    printf '\n%s✗ %d problem(s).%s\n' "$RED" "$n" "$OFF"
    exit 1
fi

hdr "Done"
say "  Log out and pick \"Sway (LordOS-like)\" in the login screen."
say ""
say "  Or start it from a text console (Ctrl+Alt+F3):"
say ""
say "      sway"
say ""
note "Super opens the launcher. Super+Enter opens a terminal."
note "The dock is nwg-dock: right-click a running app for its menu."
say ""
note "This is not LordOS's Dock. LordOS's is drawn by its own compositor;"
note "this one is a separate program that looks similar and behaves like a dock."
say ""
