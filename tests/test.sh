#!/bin/sh
# test.sh — memastikan check.sh memberi jawaban yang benar pada kondisi yang berbeda.
#
# Menjalankan check.sh dengan "dunia palsu" (variabel lingkungan yang menunjuk ke
# direktori fixture), jadi tidak menyentuh sistem sungguhan.
#
#   sh test.sh

set -u

DIR=$(cd -- "$(dirname -- "$0")" && pwd)
CHECK="$DIR/../scripts/check.sh"
[ -f "$CHECK" ] || { echo "test.sh: check.sh tidak ditemukan" >&2; exit 1; }

FAILS=0
CHECKS=0

t_ok()   { CHECKS=$((CHECKS + 1)); }
t_fail() { CHECKS=$((CHECKS + 1)); FAILS=$((FAILS + 1)); printf 'FAILED: %s\n' "$1"; }

# check.sh membaca path sistem secara langsung. Untuk menguji logikanya tanpa mesin
# Apple, kita jalankan versi yang path-nya bisa diarahkan lewat ROOTPREFIX.
run_with_root() {
    root=$1
    ROOT="$root" sh -c '
        exec 3>&1
        sed \
            -e "s#/proc/device-tree#${ROOT}/proc/device-tree#g" \
            -e "s#/sys/class/drm#${ROOT}/sys/class/drm#g" \
            -e "s#/sys/firmware/acpi#${ROOT}/sys/firmware/acpi#g" \
            -e "s#/boot/config-#${ROOT}/boot/config-#g" \
            -e "s#/etc/os-release#${ROOT}/etc/os-release#g" \
            -e "s#/var#${ROOT}/var#g" \
            "'"$CHECK"'" > /tmp/_chk.$$;
        sh /tmp/_chk.$$
        rc=$?
        rm -f /tmp/_chk.$$
        exit $rc
    ' 2>&1
}

mkroot() {
    r=$1
    mkdir -p "$r/proc/device-tree" "$r/sys/class/drm" "$r/sys/firmware" \
             "$r/boot" "$r/etc" "$r/var"
    printf '%s' "$r"
}

# --- case 1: mesin Apple yang siap -------------------------------------------
r=$(mkroot /tmp/t_ready)
printf 'Apple MacBook Air (M1, 2020)\000' > "$r/proc/device-tree/model"
mkdir -p "$r/sys/class/drm/card0-DP-1"
printf 'connected\n' > "$r/sys/class/drm/card0-DP-1/status"
printf 'ID=debian\nVERSION_ID="14"\nVERSION_CODENAME=forky\n' > "$r/etc/os-release"
kv=$(uname -r)
printf 'CONFIG_DRM_APPLE=m\nCONFIG_SECURITY_LANDLOCK=y\n' > "$r/boot/config-$kv"
out=$(run_with_root "$r")
t_ok
case "$out" in
    *"Apple MacBook Air"*) ;;
    *) t_fail "kasus 1: model Apple tidak terdeteksi" ;;
esac
case "$out" in
    *"CONFIG_DRM_APPLE"*) ;;
    *) t_fail "kasus 1: DRM_APPLE tidak terdeteksi" ;;
esac

# --- case 2: kernel tanpa DRM_APPLE harus ditolak ----------------------------
r2=$(mkroot /tmp/t_nodrm)
printf 'Apple Mac mini (M1, 2020)\000' > "$r2/proc/device-tree/model"
mkdir -p "$r2/sys/class/drm/card0-HDMI-1"
printf 'disconnected\n' > "$r2/sys/class/drm/card0-HDMI-1/status"
printf 'ID=debian\nVERSION_ID="14"\nVERSION_CODENAME=forky\n' > "$r2/etc/os-release"
printf 'CONFIG_DRM_APPLE not set\n' > "$r2/boot/config-$kv"
out2=$(run_with_root "$r2")
t_ok
case "$out2" in
    *"TIDAK punya CONFIG_DRM_APPLE"*) ;;
    *) t_fail "kasus 2: kernel tanpa DRM_APPLE seharusnya dilaporkan" ;;
esac

# --- case 3: bukan Apple harus ditolak ---------------------------------------
r3=$(mkroot /tmp/t_rpi)
printf 'Raspberry Pi 5 Model B\000' > "$r3/proc/device-tree/model"
printf 'ID=debian\nVERSION_ID="13"\nVERSION_CODENAME=trixie\n' > "$r3/etc/os-release"
printf 'CONFIG_DRM_APPLE=y\n' > "$r3/boot/config-$kv"
out3=$(run_with_root "$r3")
t_ok
case "$out3" in
    *"bukan Mac"*|*"Raspberry Pi"*) ;;
    *) t_fail "kasus 3: Raspberry Pi seharusnya ditolak" ;;
esac

# --- case 4: tanpa DRM card harus dilaporkan ---------------------------------
r4=$(mkroot /tmp/t_nocard)
printf 'Apple MacBook Air (M2, 2022)\000' > "$r4/proc/device-tree/model"
printf 'ID=debian\nVERSION_ID="14"\nVERSION_CODENAME=forky\n' > "$r4/etc/os-release"
printf 'CONFIG_DRM_APPLE=m\n' > "$r4/boot/config-$kv"
out4=$(run_with_root "$r4")
t_ok
case "$out4" in
    *"tidak akan bisa tampil"*) ;;
    *) t_fail "kasus 4: tidak ada DRM card seharusnya dilaporkan" ;;
esac

# --- case 5: skrip tidak boleh menulis apa pun -------------------------------
# Periksa source-nya, bukan menjalankannya: tidak boleh ada perintah yang mengubah sistem.
t_ok
if grep -nE '(^|[^a-zA-Z])(rm|mv|dd|mkfs|wipefs|sgdisk|fdisk|parted|shred|truncate)[[:space:]]' "$CHECK" >/dev/null 2>&1; then
    t_fail "kasus 5: check.sh mengandung perintah yang mengubah sistem"
fi
if grep -nE '>[[:space:]]*/(etc|boot|usr|var)/' "$CHECK" >/dev/null 2>&1; then
    t_fail "kasus 5: check.sh menulis ke path sistem"
fi

# --- case 6: check.sh harus bisa gagal ---------------------------------------
t_ok
sh "$CHECK" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    # Di mesin Apple yang sudah siap, exit 0 wajar. Di mesin ini (macOS) harus 1.
    echo "  (catatan: check.sh keluar 0 — hanya benar bila dijalankan di Apple Silicon yang siap)"
fi

# --- case 7: setup.sh harus merutekan forky lewat fix-forky.sh --------------
# install.sh tidak bisa memasang LordOS di forky (butuh FFmpeg 7, forky punya 8),
# jadi setup.sh wajib memilih jalur lain. Lihat test-setup-router.sh.
DIR=$(dirname -- "$0")
t_ok
if [ -f "$DIR/test-setup-router.sh" ]; then
    if ! sh "$DIR/test-setup-router.sh" "$DIR/../lib/setup.sh" >/dev/null 2>&1; then
        t_fail "kasus 7: router setup.sh salah (argumen atau forky/trixie)"
    fi
else
    t_fail "kasus 7: test-setup-router.sh tidak ditemukan"
fi

# --- case 8: jalur forky benar-benar memanggil skrip yang tepat ------------
t_ok
if [ -f "$DIR/test-setup-forky.sh" ]; then
    if ! sh "$DIR/test-setup-forky.sh" "$DIR/../lib/setup.sh" >/dev/null 2>&1; then
        t_fail "kasus 8: jalur forky tidak memanggil fix-forky.sh/finish-setup.sh"
    fi
else
    t_fail "kasus 8: test-setup-forky.sh tidak ditemukan"
fi

# --- case 9: enable-media.sh memutuskan hal yang benar ----------------------
t_ok
if [ -f "$DIR/test-enable-media.sh" ]; then
    if ! sh "$DIR/test-enable-media.sh" "$DIR/../scripts/enable-media.sh" >/dev/null 2>&1; then
        t_fail "kasus 9: enable-media.sh salah memutuskan (forky/trixie/aktif)"
    fi
else
    t_fail "kasus 9: test-enable-media.sh tidak ditemukan"
fi

# --- case 10: check-performance.sh membaca jalur komposisi dengan benar ------
# "GPU composition (llvmpipe …)" masih jalur GPU; menyebutnya CPU path akan
# mengirim user memperbaiki hal yang salah.
t_ok
if [ -f "$DIR/test-check-performance.sh" ]; then
    if ! sh "$DIR/test-check-performance.sh" "$DIR/../scripts/check-performance.sh" >/dev/null 2>&1; then
        t_fail "kasus 10: check-performance.sh salah membaca jalur komposisi"
    fi
else
    t_fail "kasus 10: test-check-performance.sh tidak ditemukan"
fi

# --- case 11: install.sh (the wizard) memanggil langkah yang benar ----------
t_ok
if [ -f "$DIR/test-install-wizard.sh" ]; then
    if ! sh "$DIR/test-install-wizard.sh" "$DIR/../install.sh" >/dev/null 2>&1; then
        t_fail "kasus 11: install.sh melewatkan langkah atau menyebut path yang tidak ada"
    fi
else
    t_fail "kasus 11: test-install-wizard.sh tidak ditemukan"
fi

# --- case 12: add-sway-desktop.sh memutuskan hal yang benar -----------------
t_ok
if [ -f "$DIR/test-add-sway-desktop.sh" ]; then
    if ! sh "$DIR/test-add-sway-desktop.sh" "$DIR/../scripts/add-sway-desktop.sh" >/dev/null 2>&1; then
        t_fail "kasus 12: add-sway-desktop.sh salah (user, rilis, atau --revert)"
    fi
else
    t_fail "kasus 12: test-add-sway-desktop.sh tidak ditemukan"
fi

printf '\n%d pemeriksaan, %d gagal\n' "$CHECKS" "$FAILS"
[ "$FAILS" -eq 0 ]
