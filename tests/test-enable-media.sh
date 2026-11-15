#!/bin/sh
# test-enable-media.sh — tests enable-media.sh without Debian, root, or network.
#
# The script's whole job is a decision: is FFmpeg 7 loadable, is lord-media
# present, and which of the three modes (check / apply / revert) is being asked
# for. Each case below swaps one of those facts for a stub and asserts the
# decision changes with it.
set -u
S="${1:-$(dirname -- "$0")/../scripts/enable-media.sh}"
[ -f "$S" ] || { echo "test-enable-media: no script at $S" >&2; exit 1; }

work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin" "$work/helper"

fails=0
checks=0

# --- stubs -------------------------------------------------------------------

# os-release fixtures
printf 'VERSION_CODENAME=forky\n'  > "$work/os-forky"
printf 'VERSION_CODENAME=sid\n'    > "$work/os-sid"
printf 'VERSION_CODENAME=trixie\n' > "$work/os-trixie"

# dpkg: lordos is installed, version 0.8.8.8
cat > "$work/bin/dpkg" <<'EOF'
#!/bin/sh
case "$1" in -s) exit 0 ;; *) exit 0 ;; esac
EOF
cat > "$work/bin/dpkg-query" <<'EOF'
#!/bin/sh
echo "0.8.8.8"
EOF

# ldconfig: switch between "FFmpeg 7 present" and "FFmpeg 7 missing".
ff7_present() {
    cat > "$work/bin/ldconfig" <<'EOF'
#!/bin/sh
for s in libavcodec.so.61 libavformat.so.61 libavutil.so.59 libswscale.so.8 libswresample.so.5 libva.so.2 libva-drm.so.2; do
    echo "	$s (libc6,AArch64) => /usr/lib/aarch64-linux-gnu/$s"
done
EOF
    chmod +x "$work/bin/ldconfig"
}
ff7_missing() {
    cat > "$work/bin/ldconfig" <<'EOF'
#!/bin/sh
echo "	libavcodec.so.63 (libc6,AArch64) => /usr/lib/aarch64-linux-gnu/libavcodec.so.63"
EOF
    chmod +x "$work/bin/ldconfig"
}
chmod +x "$work/bin/dpkg" "$work/bin/dpkg-query"

# The helper path is absolute in the script; point it at the fixture so the test
# can create and remove it without touching the real filesystem.
sed "s|^helper=/usr/lib/lordos/bin/lord-media|helper=$work/helper/lord-media|" "$S" > "$work/sut.sh"

helper_exists()   { printf '#!/bin/sh\nexit 0\n' > "$work/helper/lord-media"; chmod +x "$work/helper/lord-media"; }
helper_absent()   { rm -f "$work/helper/lord-media"; }

run() {  # run <os-fixture> [args...]
    os=$1; shift
    PATH="$work/bin:$PATH" OS_RELEASE="$os" sh "$work/sut.sh" "$@" 2>&1
}

expect() {   # expect <label> <output> <substring>
    checks=$((checks + 1))
    case "$2" in
        *"$3"*) ;;
        *) fails=$((fails + 1)); printf 'FAILED: %s (wanted %s)\n  got: %s\n' "$1" "$3" "$2" ;;
    esac
}

refuse() {   # refuse <label> <output> <substring that must NOT appear>
    checks=$((checks + 1))
    case "$2" in
        *"$3"*) fails=$((fails + 1)); printf 'FAILED: %s (must not contain %s)\n  got: %s\n' "$1" "$3" "$2" ;;
    esac
}

# --- 1. trixie is not the problem this script solves ---------------------------
ff7_present; helper_absent
o=$(run "$work/os-trixie")
expect "trixie says media already works" "$o" "FFmpeg 7 memang sudah ada"
refuse "trixie installs nothing"         "$o" "apt-get install"

# --- 2. forky with FFmpeg 7 missing: name the gap, offer --apply --------------
ff7_missing; helper_absent
o=$(run "$work/os-forky")
# Not "libavcodec.so.61" alone: that literal also appears in the plan text, so it
# would pass even if detection were broken. This is the detection's own wording.
expect "forky reports the missing sonames" "$o" "FFmpeg 7 tidak ada — kurang:"
expect "the report names the codec soname"  "$o" "kurang: libavcodec.so.61"
expect "forky refuses to touch anything by default" "$o" "--apply"

# With FFmpeg 7 present the report must NOT claim it is missing — the inverse.
ff7_present; helper_absent
o2=$(run "$work/os-forky")
expect "present FFmpeg 7 is reported as loadable" "$o2" "FFmpeg 7 (soname"
refuse "present FFmpeg 7 is not called missing"    "$o2" "FFmpeg 7 tidak ada"

# --- 3. check mode never mutates ---------------------------------------------
refuse "check mode does not write apt sources" "$o" "/etc/apt/sources.list.d"

# --- 4. everything already in place: nothing to do, exit 0 -------------------
ff7_present; helper_exists
o=$(run "$work/os-forky")
expect "no-op when already active" "$o" "Media sudah aktif"
run "$work/os-forky" >/dev/null 2>&1
[ $? -eq 0 ] && checks=$((checks + 1)) || { checks=$((checks + 1)); fails=$((fails + 1)); echo "FAILED: already-active must exit 0"; }

# --- 5. sid is treated like forky -------------------------------------------
ff7_missing; helper_absent
o=$(run "$work/os-sid")
expect "sid takes the forky path" "$o" "Debian sid"

# --- 6. an unknown release is still handled, not crashed ---------------------
printf 'VERSION_CODENAME=bookworm\n' > "$work/os-bookworm"
o=$(run "$work/os-bookworm")
expect "unknown release warns instead of dying" "$o" "ditulis untuk forky"
case "$o" in *"unbound variable"*|*"syntax error"*) fails=$((fails+1)); checks=$((checks+1)); echo "FAILED: crashed on unknown release";; *) checks=$((checks+1));; esac

# --- 7. no os-release at all --------------------------------------------------
o=$(PATH="$work/bin:$PATH" OS_RELEASE="$work/nonexistent" sh "$work/sut.sh" 2>&1)
expect "missing os-release is warned about" "$o" "tidak terdeteksi"
case "$o" in *"unbound variable"*) fails=$((fails+1)); checks=$((checks+1)); echo "FAILED: crashed with no os-release";; *) checks=$((checks+1));; esac

# --- 8. --revert must never delete without root ------------------------------
# (we are not root here; the script re-execs through sudo, which fails in a
#  non-interactive test, so nothing is deleted either way)
o=$(run "$work/os-forky" --revert)
refuse "revert does not delete as a non-root user" "$o" "sumber trixie, pin, dan lord-media dihapus"

# --- 9. unknown flag is rejected --------------------------------------------
o=$(run "$work/os-forky" --nonsense)
expect "unknown flag is refused" "$o" "argumen tidak dikenal"

# --- 9b. --help works when piped, where $0 is "sh" and not a readable file ---
# Every script here is meant to be read as `curl ... | sh`, so this matters.
o=$(cat "$S" | sh -s -- --help 2>&1)
expect "piped --help prints the options" "$o" "--apply"
refuse "piped --help does not leak a sed error" "$o" "No such file"

# --- 10. the post-install verification catches a half-finished install -------
# The state check (before) and the verification (after) are different loops; a
# sabotage in one is invisible to the other. Here FFmpeg 7 looks installed, so
# the plan proceeds, but --apply is not run: this only proves the check ran.
ff7_present; helper_exists
o=$(run "$work/os-forky")
refuse "no false 'libs missing' once they are present" "$o" "pustaka masih hilang"

# libva is a separate package from the av* set; make sure the verification list
# still contains it, because lord-media links it and forgetting it breaks the
# helper at runtime, not at install time. Anchored on the loop header, because
# the names also appear in the note text above it.
for soname in libva.so.2 libva-drm.so.2; do
    checks=$((checks + 1))
    sed -n '/^for soname in/,/; do/p' "$S" | grep -q "$soname" \
        || { fails=$((fails + 1)); echo "FAILED: verification loop does not check $soname"; }
done

printf '\n%d checks, %d failed\n' "$checks" "$fails"
[ "$fails" -eq 0 ]
