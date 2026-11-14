#!/bin/sh
# check.sh — periksa apakah mesin Apple Silicon ini siap dipasangi LordOS.
#
# Jalankan SETELAH Debian (Bananas) terpasang dan setelah `sudo apt install asahi-platform`.
# Skrip ini HANYA MEMBACA. Tidak memasang, tidak mengubah, tidak menghapus apa pun.
#
#   sh check.sh
#
# Keluar dengan 0 kalau semua syarat wajib terpenuhi, 1 kalau ada yang kurang.

set -u

RED=''; GRN=''; YLW=''; BLD=''; OFF=''
if [ -t 1 ]; then
    RED=$(printf '\033[31m'); GRN=$(printf '\033[32m')
    YLW=$(printf '\033[33m'); BLD=$(printf '\033[1m'); OFF=$(printf '\033[0m')
fi

FAIL=0
WARN=0

pass() { printf '  %s✓%s %s\n' "$GRN" "$OFF" "$1"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$OFF" "$1"; WARN=$((WARN + 1)); }
bad()  { printf '  %s✗%s %s\n' "$RED" "$OFF" "$1"; FAIL=$((FAIL + 1)); }

hdr() { printf '\n%s%s%s\n' "$BLD" "$1" "$OFF"; }

hdr "1. Mesin"

model=""
if [ -r /proc/device-tree/model ]; then
    model=$(tr -d '\000' < /proc/device-tree/model)
fi

if [ -n "$model" ]; then
    case "$model" in
        *"Apple"*)
            pass "Apple Silicon: $model" ;;
        *"Raspberry Pi"*)
            bad "Ini Raspberry Pi, bukan Mac: $model" ;;
        *)
            warn "Device tree ada tapi bukan Apple: $model" ;;
    esac
else
    if [ -d /sys/firmware/acpi ]; then
        bad "Tidak ada device tree, tapi ada ACPI — ini bukan Apple Silicon"
    else
        bad "Tidak bisa menentukan jenis mesin"
    fi
fi

arch=$(uname -m)
case "$arch" in
    aarch64) pass "Arsitektur: $arch" ;;
    arm64)   pass "Arsitektur: $arch (macOS; di Linux akan tampil aarch64)" ;;
    *)       bad "Arsitektur salah: $arch (harus aarch64)" ;;
esac

hdr "2. Kernel"

kver=$(uname -r)
printf '  Kernel: %s\n' "$kver"

cfg="/boot/config-$kver"
if [ -r "$cfg" ]; then
    if grep -qE '^CONFIG_DRM_APPLE=[my]$' "$cfg"; then
        pass "Kernel punya driver display Apple (CONFIG_DRM_APPLE)"
    else
        bad "Kernel TIDAK punya CONFIG_DRM_APPLE — layar akan hitam"
        printf '      %sIni bukan kernel Asahi. Pakai kernel dari paket Bananas.%s\n' "$YLW" "$OFF"
    fi
else
    warn "Tidak bisa baca $cfg — lewati pemeriksaan config kernel"
fi

hdr "3. Display (DRM)"

cards=""
for c in /sys/class/drm/card[0-9]; do
    [ -e "$c" ] && cards="$cards $c"
done

if [ -n "$cards" ]; then
    pass "DRM card ditemukan:$cards"
    found_conn=0
    for c in /sys/class/drm/card*-*; do
        [ -e "$c/status" ] && found_conn=1
    done
    [ "$found_conn" -eq 1 ] && pass "Connector ditemukan" || warn "Card ada tapi tanpa connector"
else
    bad "Tidak ada /sys/class/drm/card* — LordOS tidak akan bisa tampil (tidak ada display)"
fi

hdr "4. Paket Asahi"

if dpkg -s asahi-platform >/dev/null 2>&1; then
    pass "asahi-platform terpasang"
else
    bad "asahi-platform BELUM terpasang"
    printf '      %sJalankan: sudo apt update && sudo apt install asahi-platform%s\n' "$YLW" "$OFF"
fi

if dpkg -s speakersafetyd >/dev/null 2>&1; then
    pass "speakersafetyd terpasang"
    if [ "$(systemctl is-enabled speakersafetyd 2>/dev/null || echo no)" = "enabled" ]; then
        pass "speakersafetyd aktif saat boot"
    else
        warn "speakersafetyd ada tapi tidak enabled — speaker berisiko"
        printf '      %sJalankan: sudo systemctl enable --now speakersafetyd%s\n' "$YLW" "$OFF"
    fi
    if [ "$(systemctl is-active speakersafetyd 2>/dev/null || echo no)" = "active" ]; then
        pass "speakersafetyd sedang berjalan"
    else
        warn "speakersafetyd belum berjalan (mungkin perlu reboot)"
    fi
else
    bad "speakersafetyd BELUM terpasang — JANGAN nyalakan suara dulu"
fi

for p in asahi-scripts asahi-audio; do
    if dpkg -s "$p" >/dev/null 2>&1; then
        pass "$p terpasang"
    else
        warn "$p tidak terpasang"
    fi
done

hdr "5. Debian"

if [ -r /etc/os-release ]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    printf '  Distro: %s %s (%s)\n' "${ID:-?}" "${VERSION_ID:-?}" "${VERSION_CODENAME:-?}"
    case "${VERSION_CODENAME:-}" in
        trixie)  pass "Debian 13 (trixie) — didukung" ;;
        forky|sid) pass "Debian ${VERSION_CODENAME} — didukung oleh installer LordOS yang sudah dipatch" ;;
        *) warn "Distro ${VERSION_CODENAME:-tidak dikenal} — installer LordOS mungkin menolak" ;;
    esac
else
    bad "Tidak ada /etc/os-release"
fi

glibc=$(ldd --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+$')
if [ -n "$glibc" ]; then
    major=${glibc%%.*}
    minor=${glibc#*.}
    if [ "$major" -gt 2 ] || { [ "$major" -eq 2 ] && [ "$minor" -ge 38 ]; }; then
        pass "glibc $glibc (LordOS butuh >= 2.38)"
    else
        bad "glibc $glibc terlalu tua (butuh >= 2.38)"
    fi
fi

hdr "6. Dependensi"

missing=""
for p in libc6 libwayland-server0 libwayland-client0 libxkbcommon0 libcrypt1 \
         libssl3t64 libfreerdp3-3 libwinpr3-3 fuse3 polkitd pkexec libgbm1 \
         libegl1 libgles2 libwayland-egl1 libarchive13t64 libcairo2 \
         libfreetype6 libfontconfig1 libvulkan1 libgomp1 libstdc++6 \
         libavcodec61 libavutil59 libpipewire-0.3-0t64; do
    dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
done

if [ -z "$missing" ]; then
    pass "Semua dependensi inti terpasang"
else
    warn "Belum terpasang (mungkin akan diambil apt saat install LordOS):$missing"
fi

hdr "7. Jaringan dan ruang"

dns_ok=0
if command -v getent >/dev/null 2>&1; then
    getent hosts deb.debian.org >/dev/null 2>&1 && dns_ok=1
elif command -v host >/dev/null 2>&1; then
    host deb.debian.org >/dev/null 2>&1 && dns_ok=1
elif command -v nslookup >/dev/null 2>&1; then
    nslookup deb.debian.org >/dev/null 2>&1 && dns_ok=1
fi

if [ "$dns_ok" -eq 1 ]; then
    if ping -c1 -W2 deb.debian.org >/dev/null 2>&1; then
        pass "Jaringan ke deb.debian.org OK (DNS + ping)"
    else
        warn "DNS OK, ping diblokir (normal di sebagian jaringan) — coba: sudo apt update"
    fi
else
    bad "Tidak bisa resolve deb.debian.org — tidak ada jaringan (sambungkan: nmtui)"
fi

free_mb=$(df -Pk /var 2>/dev/null | awk 'NR==2 {print int($4/1024)}')
if [ -n "${free_mb:-}" ]; then
    if [ "$free_mb" -ge 4096 ]; then
        pass "Ruang di /var: ${free_mb} MB"
    elif [ "$free_mb" -ge 2048 ]; then
        warn "Ruang di /var hanya ${free_mb} MB (LordOS butuh >= 2 GB, sisa tipis)"
    else
        bad "Ruang di /var hanya ${free_mb} MB (butuh >= 2 GB)"
    fi
fi

hdr "Hasil"

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
    printf '%s%sAMAN.%s Semua syarat terpenuhi. Lanjutkan dengan:\n\n' "$GRN" "$BLD" "$OFF"
    printf '    sh install.sh\n\n'
    exit 0
fi

if [ "$FAIL" -eq 0 ]; then
    printf '%s%sBOLEH LANJUT, dengan %d peringatan.%s Lihat "!" di atas.\n\n' "$YLW" "$BLD" "$WARN" "$OFF"
    printf 'Kalau yang diperingatkan hanya dependensi (bagian 6), apt akan\n'
    printf 'mengambilnya saat install. Kalau speakersafetyd, pasang dulu:\n\n'
    printf '    sudo apt install asahi-platform && sudo reboot\n\n'
    exit 0
fi

printf '%s%sJANGAN LANJUT.%s Ada %d masalah yang harus diperbaiki dulu.\n\n' "$RED" "$BLD" "$OFF" "$FAIL"
printf 'Perbaiki yang bertanda ✗ di atas, lalu jalankan lagi: sh check.sh\n\n'
exit 1
