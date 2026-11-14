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

# Saat dijalankan sebagai file, DIRECTORY = folder skrip. Saat di-pipe (curl | sh),
# $0 bukan path yang bisa dipercaya — jadi DIRECTORY kosong dan install.sh diunduh.
DIR=""
if [ -f "$0" ]; then
    DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || DIR=""
fi
RAW="${LORDOS_RAW:-https://raw.githubusercontent.com/vidokun/lordos-m1/main}"

say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n%s== %s ==%s\n\n' "$BLD" "$1" "$OFF"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$OFF" "$1"; }
warn() { printf '  %s!%s %s\n' "$YLW" "$OFF" "$1"; }
die()  { printf '\n%s✗ %s%s\n\n' "$RED" "$1" "$OFF" >&2; exit 1; }

need_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    say "Skrip ini perlu root. Menjalankan ulang dengan sudo..."
    if [ -f "$0" ]; then
        exec sudo -E sh "$0" "$@"
    fi
    # Di-pipe (curl | sh): tidak ada file untuk dijalankan ulang. Simpan dulu.
    self=$(mktemp) || die "tidak bisa membuat file sementara"
    if ! curl -fsSL -o "$self" "$RAW/setup.sh"; then
        rm -f "$self"
        die "tidak bisa menyimpan skrip untuk sudo — jalankan dengan sudo sejak awal"
    fi
    exec sudo -E sh "$self" "$@"
}

# --with-media sengaja TIDAK ditangani di sini. Dulu flag ini diteruskan ke
# fix-forky.sh, yang artinya mengunduh ulang paket LordOS 31 MB hanya untuk
# memasang FFmpeg 7. enable-media.sh melakukan bagian media saja, pada sistem
# yang sudah terpasang, tanpa unduhan itu — jadi hanya ada satu jalur, dan yang
# lebih ringan.
PASS_ARGS=""
to_clean=""
for a in "$@"; do
    case "$a" in
        --with-media)
            say "  --with-media sudah tidak dipakai setup.sh."
            say "  Untuk fitur media sesudah LordOS terpasang:"
            say ""
            say "      curl -fsSL -o enable-media.sh https://raw.githubusercontent.com/vidokun/lordos-m1/main/enable-media.sh"
            say "      sudo sh enable-media.sh --apply"
            say ""
            say "  Pemasangan LordOS di atas tetap dilanjutkan tanpa media."
            say ""
            ;;
        -h|--help)
            # Di-pipe (curl | sh), $0 adalah "sh" — bukan berkas yang bisa dibaca,
            # jadi sed akan mencetak error. Bantuan tetap ditampilkan tanpa header.
            [ -f "$0" ] && sed -n '2,20p' "$0"
            say ""
            say "Pilihan:"
            say "  --yes   jangan bertanya"
            say ""
            say "Fitur media punya skripnya sendiri: enable-media.sh"
            exit 0 ;;
        *) PASS_ARGS="$PASS_ARGS $a" ;;
    esac
done

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

# Debian Forky (dan sid) TIDAK bisa memakai install.sh: paket LordOS menuntut
# FFmpeg 7 (libavcodec61, ...), dan Forky hanya punya FFmpeg 8 (libavcodec63).
# apt lalu membatalkan SELURUH transaksi, jadi install.sh berhenti dengan
# "apt-get could not install LordOS". fix-forky.sh menangani persis itu: ia
# me-repack paket tanpa dependensi FFmpeg 7, memasangnya, lalu finish-setup.sh
# menyelesaikan bagian sistem. Di trixie, install.sh tetap jalur yang benar.
#
# Dibaca dengan sed, bukan `. /etc/os-release`: file itu dieksekusi kalau di-source,
# dan OS_RELEASE membuat keputusan ini bisa diuji tanpa Debian.
codename=$(sed -n 's/^VERSION_CODENAME=//p' "${OS_RELEASE:-/etc/os-release}" 2>/dev/null \
           | head -n 1 | sed 's/^"//; s/"$//')
NEED_FORKY_PATH=0
case "$codename" in
    forky|sid) NEED_FORKY_PATH=1 ;;
esac

if [ "$NEED_FORKY_PATH" -eq 1 ]; then
    say "  Debian ${codename}: memakai jalur Forky (paket di-repack, FFmpeg 7 dibuang)"
    say ""
    for s in fix-forky.sh finish-setup.sh; do
        if [ -n "$DIR" ] && [ -f "$DIR/$s" ]; then
            f="$DIR/$s"
        else
            f=$(mktemp) || die "tidak bisa membuat file sementara"
            if ! curl -fsSL -o "$f" "$RAW/$s"; then
                rm -f "$f"
                die "gagal mengunduh $s — periksa jaringan"
            fi
            to_clean="$to_clean $f"
        fi
        # selanjutnya: sh "$f"
        sh "$f"
        rc=$?
        [ "$rc" -eq 0 ] || break
    done
    for f in ${to_clean:-}; do rm -f "$f"; done
    printf '\n'
    if [ "$rc" -eq 0 ]; then
        printf '%s%sSelesai.%s Reboot untuk masuk ke LordOS:\n\n' "$GRN" "$BLD" "$OFF"
        printf '    sudo reboot\n\n'
    else
        printf '%s%sPemasangan berhenti dengan kode %s.%s\n\n' "$RED" "$BLD" "$rc" "$OFF"
        printf 'Debian Anda tetap utuh. Tidak ada yang rusak.\n'
        printf 'Salin pesan error di atas untuk analisis.\n\n'
    fi
    exit "$rc"
fi

INST=""
if [ -n "$DIR" ] && [ -f "$DIR/install.sh" ]; then
    INST="$DIR/install.sh"
fi

if [ -z "$INST" ]; then
    say "  Mengunduh installer LordOS..."
    tmp=$(mktemp) || die "tidak bisa membuat file sementara"
    if curl -fsSL -o "$tmp" "$RAW/install.sh"; then
        INST="$tmp"
        ok "installer diunduh"
    else
        rm -f "$tmp"
        die "gagal mengunduh install.sh — periksa jaringan"
    fi
fi

say "  Menjalankan installer LordOS"
say "  (installer ini sudah dipatch agar menerima Debian trixie)"
say ""

# shellcheck disable=SC2086 # $PASS_ARGS adalah daftar argumen; --with-media sudah disaring
sh "$INST" $PASS_ARGS
rc=$?

[ "${tmp:-}" != "" ] && rm -f "$tmp"

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
