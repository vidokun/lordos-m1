#!/bin/sh
# setup.sh — satu perintah untuk memasang LordOS di Mac Apple Silicon lewat Debian (Bananas).
#
#   sh setup.sh
#
# Ia memeriksa mesin, memasang paket Asahi yang wajib, lalu memasang LordOS.
# Aman dijalankan berulang: langkah yang sudah beres akan dilewati.
#
# Yang TIDAK dilakukan: menyentuh partisi, bootloader, atau macOS. Semua urusan
# disk sudah selesai sebelum skrip ini dijalankan (oleh installer Asahi/Bananas).

set -u

RED=''; GRN=''; YLW=''; BLD=''; OFF=''
if [ -t 1 ]; then
    RED=$(printf '\033[31m'); GRN=$(printf '\033[32m')
    YLW=$(printf '\033[33m'); BLD=$(printf '\033[1m'); OFF=$(printf '\033[0m')
fi

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n%s== %s ==%s\n\n' "$BLD" "$1" "$OFF"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$OFF" "$1"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$OFF" "$1"; }
die()  { printf '\n%s✗ %s%s\n\n' "$RED" "$1" "$OFF" >&2; exit 1; }

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        say "Skrip ini perlu root. Menjalankan ulang dengan sudo..."
        exec sudo -E sh "$0" "$@"
    fi
}

need_root "$@"

# ---------------------------------------------------------------- 1. pemeriksaan

hdr "Memeriksa mesin"

model=""
[ -r /proc/device-tree/model ] && model=$(tr -d '\000' < /proc/device-tree/model)

case "$model" in
    *"Apple"*) ok "Apple Silicon: $model" ;;
    "")        die "Tidak ada /proc/device-tree/model — ini bukan mesin Apple Silicon" ;;
    *)         die "Mesin ini bukan Apple Silicon: $model" ;;
esac

[ "$(uname -m)" = "aarch64" ] || die "Arsitektur $(uname -m), harus aarch64"

kver=$(uname -r)
cfg="/boot/config-$kver"
if [ -r "$cfg" ] && grep -qE '^CONFIG_DRM_APPLE=[my]$' "$cfg"; then
    ok "Kernel punya driver display Apple ($kver)"
else
    warn "Kernel $kver tidak punya CONFIG_DRM_APPLE"
    say ""
    say "  Ini berarti Debian di mesin ini belum memakai kernel Asahi."
    say "  LordOS bisa terpasang, tapi layar akan tetap hitam."
    say ""
    say "  Perbaiki dulu: pastikan Debian dipasang lewat installer Bananas,"
    say "  atau pasang kernel Asahi dari arsip Bananas. Lalu jalankan lagi."
    die "Kernel bukan kernel Asahi"
fi

cards=0
for c in /sys/class/drm/card[0-9]; do [ -e "$c" ] && cards=$((cards + 1)); done
[ "$cards" -gt 0 ] && ok "$cards DRM card ditemukan" || die "Tidak ada /sys/class/drm/card* — tidak ada display"

# ---------------------------------------------------------------- 2. paket Asahi

hdr "Paket Asahi (pelindung speaker dan audio)"

if dpkg -s asahi-platform >/dev/null 2>&1; then
    ok "asahi-platform sudah terpasang"
else
    say "  Memasang asahi-platform..."
    apt-get update -q || die "apt-get update gagal — periksa jaringan"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q asahi-platform \
        || die "Gagal memasang asahi-platform"
    ok "asahi-platform terpasang"
fi

if dpkg -s speakersafetyd >/dev/null 2>&1; then
    ok "speakersafetyd terpasang"
    systemctl enable --now speakersafetyd >/dev/null 2>&1 || true
    if [ "$(systemctl is-active speakersafetyd 2>/dev/null || echo no)" = "active" ]; then
        ok "speakersafetyd berjalan"
    else
        warn "speakersafetyd belum aktif — mungkin perlu reboot"
    fi
else
    die "speakersafetyd tidak ada setelah memasang asahi-platform"
fi

# ---------------------------------------------------------------- 3. LordOS

hdr "LordOS"

say "  Menjalankan installer LordOS dari folder ini..."
say "  (installer ini sudah dipatch agar menerima Debian forky/sid)"
say ""

sh "$DIR/install.sh" "$@"
rc=$?

printf '\n'
if [ "$rc" -eq 0 ]; then
    printf '%s%sSelesai.%s Reboot untuk masuk ke LordOS:\n\n' "$GRN" "$BLD" "$OFF"
    printf '    sudo reboot\n\n'
else
    printf '%s%sInstaller LordOS berhenti dengan kode %s.%s\n\n' "$RED" "$BLD" "$rc" "$OFF"
    printf 'Debian Anda tetap utuh. Tidak ada yang rusak.\n'
    printf 'Salin pesan error di atas untuk analisis.\n\n'
fi
exit "$rc"
