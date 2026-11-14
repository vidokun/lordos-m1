#!/bin/sh
# fix-forky.sh — memasang LordOS di Debian Forky, yang membawa FFmpeg 8.
#
# Masalah: paket LordOS dikompilasi terhadap FFmpeg 7 (libavcodec61, libavformat61,
# libavutil59, libswscale8, libswresample5). Debian Forky mengirim FFmpeg 8
# (libavcodec63, ...). apt membatalkan SELURUH transaksi karena satu dependensi
# mustahil dipenuhi — itulah sebabnya error-nya menyebut puluhan paket lain yang
# sebenarnya tersedia.
#
# Solusi skrip ini:
#   1. unduh paket lordos resmi (arm64)
#   2. buang 5 dependensi FFmpeg dari metadata, dan buang binary lord-media
#      (satu-satunya dari 28 binary yang memuat FFmpeg; LordOS sudah punya
#      penanganan "media helper tidak tersedia")
#   3. pasang paket hasil repack
#
# Yang HILANG setelah ini: pemutaran video, kamera, mikrofon lewat lord-media.
# Desktop, aplikasi, terminal, browser, dan file manager TETAP JALAN.
#
# Kalau Anda ingin fitur media juga, jalankan `sh fix-forky.sh --with-media`
# yang memasang FFmpeg 7 dari Trixie (mencampur rilis — lihat peringatannya).

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
die()  { printf '\n%s✗ %s%s\n\n' "$RED" "$1" "$OFF" >&2; exit 1; }

WITH_MEDIA=0
for a in "$@"; do
    case "$a" in
        --with-media) WITH_MEDIA=1 ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    say "Perlu root. Menjalankan ulang dengan sudo..."
    exec sudo -E sh "$0" "$@"
fi

VER="${LORDOS_VER:-0.8.8.8}"
RAW="${LORDOS_RAW:-https://github.com/lordbasex/LordOS/releases/download}"
URL="$RAW/v${VER}-beta/lordos_${VER}_arm64.deb"

WORK=$(mktemp -d) || die "tidak bisa membuat folder kerja"
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- 1. mesin

hdr "Memeriksa mesin"

model=""
[ -r /proc/device-tree/model ] && model=$(tr -d '\000' < /proc/device-tree/model)
case "$model" in
    *"Apple"*) ok "Apple Silicon: $model" ;;
    *) die "Bukan Apple Silicon (model: ${model:-tidak terdeteksi})" ;;
esac

kver=$(uname -r)
cfg="/boot/config-$kver"
if [ -r "$cfg" ] && grep -qE '^CONFIG_DRM_APPLE=[my]$' "$cfg"; then
    ok "Kernel punya driver display Apple"
else
    die "Kernel $kver tidak punya CONFIG_DRM_APPLE — layar akan hitam"
fi

if [ -d /sys/class/drm ] && ls /sys/class/drm/card[0-9] >/dev/null 2>&1; then
    ok "DRM card ditemukan"
else
    die "Tidak ada /sys/class/drm/card*"
fi

# ---------------------------------------------------------------- 2. unduh

hdr "Mengunduh LordOS $VER"

deb="$WORK/lordos.deb"
say "  $URL"
if ! curl -fL --progress-bar -o "$deb" "$URL"; then
    die "gagal mengunduh paket LordOS — periksa versi ($VER) atau jaringan"
fi
ok "terunduh ($(du -h "$deb" | cut -f1))"

# Paket pendamping: lordos bergantung pada keduanya, dan tanpa mereka apt
# membatalkan seluruh transaksi (pesan errornya menyebut puluhan paket lain).
hdr "Mengunduh paket pendamping"

hwdeb=$(curl -fsSL --max-time 60 \
    "https://api.github.com/repos/lordbasex/LordOS/releases/tags/v${VER}-beta" \
    | grep -oE '"name": *"lordos-hwdata_[^"]*_all\.deb"' \
    | head -1 | sed 's/.*"\(lordos-hwdata_[^"]*\)"/\1/')

if [ -z "$hwdeb" ]; then
    die "tidak menemukan lordos-hwdata di rilis v${VER}-beta"
fi

for pkg in "$hwdeb" "lordos-rclone_1.75.2-1_arm64.deb"; do
    say "  $pkg"
    if curl -fL --progress-bar -o "$WORK/$pkg" "$RAW/v${VER}-beta/$pkg"; then
        ok "$pkg terunduh"
    else
        die "gagal mengunduh $pkg"
    fi
done

# ---------------------------------------------------------------- 3. repack

hdr "Menyesuaikan paket untuk Forky"

cd "$WORK" || die "tidak bisa masuk folder kerja"
ar x "$deb" || die "gagal membuka paket (ar)"
mkdir -p ctl data
tar xf control.tar.* -C ctl || die "gagal membuka control.tar"
tar xf data.tar.*  -C data  || die "gagal membuka data.tar"

# buang binary yang memuat FFmpeg 7
if [ -f data/usr/lib/lordos/bin/lord-media ]; then
    rm -f data/usr/lib/lordos/bin/lord-media
    ok "lord-media dilewati (satu-satunya binary yang butuh FFmpeg 7)"
fi

# buang dependensi FFmpeg 7 dari metadata
before=$(grep -c 'libavcodec61' ctl/control || true)
sed -i -E '
    s/, *libavcodec61[^,]*//g;
    s/, *libavformat61[^,]*//g;
    s/, *libavutil59[^,]*//g;
    s/, *libswscale8[^,]*//g;
    s/, *libswresample5[^,]*//g;
    s/^Depends: *, */Depends: /
' ctl/control
if grep -q -E 'libavcodec|libavformat|libavutil|libswscale|libswresample' ctl/control; then
    die "masih ada dependensi FFmpeg setelah disaring — kirim output ini ke maintainer"
fi
ok "dependensi FFmpeg 7 dihapus dari metadata (sebelumnya $before baris)"

# pastikan Depends masih waras
grep -q '^Depends: .' ctl/control || die "Depends jadi kosong setelah disaring"

if [ "$WITH_MEDIA" -eq 1 ]; then
    warn "--with-media: memakai FFmpeg 7 dari Trixie (mencampur rilis Debian)"
fi

# bangun ulang.
# Catatan: JANGAN pakai `ar` mentah. ar versi BSD (mis. di macOS) menyisipkan
# entri `__.SYMDEF SORTED` yang merusak format .deb. dpkg-deb menangani ini
# dengan benar dan tersedia di Debian.
if command -v dpkg-deb >/dev/null 2>&1; then
    root="$WORK/root"
    mkdir -p "$root/DEBIAN"
    cp -a ctl/. "$root/DEBIAN/"
    # data/ sudah berisi pohon filesystem lengkap
    ( cd data && tar cf - . ) | ( cd "$root" && tar xf - ) || die "gagal menyusun root"
    dpkg-deb --build --root-owner-group "$root" "$WORK/lordos-forky.deb" >/dev/null \
        || die "dpkg-deb --build gagal"
else
    die "dpkg-deb tidak ditemukan — ini bukan sistem Debian?"
fi
ok "paket repack selesai"

# ---------------------------------------------------------------- 4. pasang

hdr "Memasang dependensi"

apt-get update -q || die "apt-get update gagal"
apt-get install -y -q --no-install-recommends asahi-platform \
    || warn "asahi-platform gagal — speaker belum terlindungi"

if [ "$WITH_MEDIA" -eq 1 ]; then
    say "  Menambahkan FFmpeg 7 dari Trixie..."
    echo "deb http://deb.debian.org/debian trixie main" > /etc/apt/sources.list.d/trixie-ffmpeg.list
    cat > /etc/apt/preferences.d/trixie-ffmpeg.pref <<'EOF'
Package: libavcodec61 libavformat61 libavutil59 libswscale8 libswresample5 libavcodec-extra61
Pin: release n=trixie
Pin-Priority: 1001
EOF
    apt-get update -q || true
    if apt-get install -y -q libavcodec61 libavformat61 libavutil59 libswscale8 libswresample5; then
        ok "FFmpeg 7 terpasang dari Trixie"
    else
        warn "FFmpeg 7 gagal dipasang — melanjutkan tanpa fitur media"
    fi
fi

hdr "Memasang LordOS"

# Ketiga paket sekaligus, supaya apt menyelesaikan dependensi dalam satu transaksi.
if ! apt-get install -y -q --no-install-recommends \
        "$WORK/$hwdeb" "$WORK/lordos-rclone_1.75.2-1_arm64.deb" "$WORK/lordos-forky.deb"; then
    printf '\n'
    die "pemasangan gagal. Kirimkan output ini untuk analisis:

    apt-get install -s $WORK/lordos-forky.deb 2>&1 | tail -30"
fi

ok "LordOS terpasang"

# ---------------------------------------------------------------- 5. hasil

hdr "Selesai"

if ! systemctl is-enabled speakersafetyd >/dev/null 2>&1; then
    warn "speakersafetyd tidak enabled — jalankan: sudo systemctl enable --now speakersafetyd"
else
    ok "speakersafetyd aktif"
fi

if [ ! -f /usr/lib/lordos/bin/lord-media ]; then
    say ""
    say "  Catatan: fitur media (video, kamera, mikrofon) tidak aktif di mesin ini"
    say "  karena FFmpeg 7 tidak tersedia di Debian Forky. Desktop tetap berjalan."
    say "  Untuk mengaktifkannya: sh fix-forky.sh --with-media"
fi

printf '\nReboot untuk masuk ke LordOS:\n\n    sudo reboot\n\n'
