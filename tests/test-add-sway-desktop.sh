#!/bin/sh
# test-add-sway-desktop.sh — the check mode and the decisions of add-sway-desktop.sh.
#
# No Debian, no root, no packages: apt-cache and the passwd file are fixtures, so
# the script's own logic is what is being tested.
set -u
S="${1:-$(dirname -- "$0")/../scripts/add-sway-desktop.sh}"
[ -f "$S" ] || { echo "test-add-sway: no script at $S" >&2; exit 1; }

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/home"

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

# --- fixtures ---------------------------------------------------------------

# A regular user whose home is NOT /home/<user>: the script must use the passwd
# entry, not a guess.
printf 'root:x:0:0::/root:/bin/sh\ndokun:x:1000:1000::%s/home:/bin/bash\n' "$work" > "$work/passwd"
printf 'VERSION_CODENAME=forky\n' > "$work/os-forky"
printf 'VERSION_CODENAME=bookworm\n' > "$work/os-old"

# Every package looks available, with a real candidate.
cat > "$work/bin/apt-cache" <<'EOF'
#!/bin/sh
if [ "$1" = policy ]; then echo "  Candidate: 1.0"; fi
exit 0
EOF

# getent is not present everywhere; the script falls back to the passwd file.
cat > "$work/bin/getent" <<'EOF'
#!/bin/sh
exit 1
EOF
chmod +x "$work/bin/apt-cache" "$work/bin/getent"

# --- 1. check mode: finds the user, names the plan, changes nothing ---------
out=$(PATH="$work/bin:$PATH" PASSWD_FILE="$work/passwd" OS_RELEASE="$work/os-forky" sh "$S" 2>&1)
check "the user comes from the passwd file" "$out" "user: dokun"
check "forky is recognised"                 "$out" "Debian forky"
check "the plan is shown"                   "$out" "sway waybar nwg-dock"
check "check mode says nothing is changed"  "$out" "nothing is changed"

# --- 2. check mode writes nothing ------------------------------------------
checks=$((checks + 1))
[ ! -e "$work/home/.config/sway/config.lordos-dock" ] || {
    fails=$((fails + 1)); echo "FAILED: check mode wrote a config file"; }

# --- 3. an unknown Debian release warns but still works --------------------
out=$(PATH="$work/bin:$PATH" PASSWD_FILE="$work/passwd" OS_RELEASE="$work/os-old" sh "$S" 2>&1)
check "an old release warns" "$out" "written for forky/sid"

# --- 4. no os-release at all is handled ------------------------------------
out=$(PATH="$work/bin:$PATH" PASSWD_FILE="$work/passwd" OS_RELEASE="$work/nonexistent" sh "$S" 2>&1)
check "a missing os-release is reported" "$out" "not detected"
case "$out" in *"unbound variable"*) fails=$((fails+1)); checks=$((checks+1)); echo "FAILED: crashed with no os-release";; *) checks=$((checks+1));; esac

# --- 5. an empty passwd file is refused, not guessed -----------------------
printf '' > "$work/empty-passwd"
out=$(PATH="$work/bin:$PATH" PASSWD_FILE="$work/empty-passwd" OS_RELEASE="$work/os-forky" sh "$S" 2>&1)
check "an empty passwd is refused" "$out" "no regular user found"

# --- 6. it never installs without --apply ---------------------------------
case "$out" in
    *apt-get*) fails=$((fails+1)); checks=$((checks+1)); echo "FAILED: check mode ran apt-get" ;;
    *) checks=$((checks+1)) ;;
esac

# --- 7. the sway fragment and the waybar config are in the script ----------
# They are written by --apply; assert they are correct text, not that they ran.
for want in "nwg-dock -d" "waybar -c" "bindsym \$mod d exec fuzzel" "gaps inner"; do
    checks=$((checks + 1))
    grep -q "$want" "$S" || { fails=$((fails + 1)); echo "FAILED: the sway fragment lacks: $want"; }
done
checks=$((checks + 1))
grep -q '"modules-center"' "$S" || { fails=$((fails + 1)); echo "FAILED: the waybar config lacks modules-center"; }

# --- 8. --help works piped, where $0 is "sh" ------------------------------
out=$(cat "$S" | sh -s -- --help 2>&1)
check "piped --help prints something useful" "$out" "--apply"
check "piped --help does not leak an error"  "$out" "--apply" "No such file"

# --- 9. home_of reads the passwd entry, not /home/<user> -------------------
# --revert deletes files from the real home; guessing /home/<user> would leave
# them behind (or delete the wrong ones) when the home lives elsewhere.
mkdir -p "$work/home/.config/sway" "$work/home/.config/waybar"
: > "$work/home/.config/sway/config.lordos-dock"
: > "$work/home/.config/waybar/config.jsonc.lordos-dock"
out=$(PATH="$work/bin:$PATH" PASSWD_FILE="$work/passwd" OS_RELEASE="$work/os-forky" sh "$S" --revert 2>&1)
checks=$((checks + 1))
if [ -e "$work/home/.config/sway/config.lordos-dock" ]; then
    fails=$((fails + 1)); echo "FAILED: --revert did not remove the fragment from the real home"
fi
checks=$((checks + 1))
case "$out" in
    *"Permission denied"*|*"cannot find"*) fails=$((fails + 1)); echo "FAILED: --revert could not resolve the home: $out" ;;
esac

printf '\n%d checks, %d failed\n' "$checks" "$fails"
[ "$fails" -eq 0 ]
