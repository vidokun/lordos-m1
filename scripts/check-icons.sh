#!/bin/sh
# check-icons.sh — mengapa sebagian ikon di LordOS tampil kotak/kosong (Debian Forky).
#
# Jawaban singkat: ikon-ikon itu BUKAN file gambar. LordOS menggambarnya sebagai
# GLYPH TEKS dari font sistem. Kalau font yang punya glyph itu tidak terpasang,
# yang muncul adalah kotak "tofu" — bukan ikon yang gagal dimuat.
#
#   apps/settings/index.jsx:878  Bluetooth = 'ᛒ'  (U+16D2)
#   apps/settings/index.jsx:878  Printers  = '⎙'  (U+2399)
#   apps/settings/index.jsx:878  Clipboard = '⎘'  (U+2398)
#
# Font fallback LordOS (server/src/ui/textlayout.c:106) mencoba berurutan:
#   Noto Sans → DejaVu Sans → Noto Sans Symbols → Noto Sans Symbols 2 → ...
#
# DejaVu Sans punya hampir semua glyph itu — tetapi TIDAK punya U+16D2 (Runic),
# U+2399 dan U+2398. Ketiganya hanya ada di fonts-noto-core.
# Di mesin ini fonts-noto-core tidak terpasang, jadi tepat tiga ikon itu kosong.
#
# Skrip ini HANYA MEMBACA. Dengan --install, ia memasang paket font yang kurang.
#
#   sh check-icons.sh              # periksa
#   sh check-icons.sh --install    # periksa, lalu pasang yang kurang
#
# Keluar 0 kalau semua glyph punya font, 1 kalau ada yang kosong.

set -u

OKC=''; WARNC=''; ERRC=''; BLD=''; OFF=''
if [ -t 1 ]; then
    OKC=$(printf '\033[32m'); WARNC=$(printf '\033[33m')
    ERRC=$(printf '\033[31m'); BLD=$(printf '\033[1m'); OFF=$(printf '\033[0m')
fi

DO_INSTALL=0
for a in "$@"; do
    case "$a" in
        --install) DO_INSTALL=1 ;;
        -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
        *) printf 'check-icons.sh: argumen tidak dikenal: %s\n' "$a" >&2; exit 2 ;;
    esac
done

say()  { printf '%s\n' "$*"; }
hdr()  { printf '\n%s%s%s\n' "$BLD" "$1" "$OFF"; }
ok()   { printf '  %s✓%s %s\n' "$OKC" "$OFF" "$1"; }
warn() { printf '  %s!%s %s\n' "$WARNC" "$OFF" "$1"; }
bad()  { printf '  %s✗%s %s\n' "$ERRC" "$OFF" "$1"; }
note() { printf '      %s\n' "$1"; }

# cp|nama|package-yang-menyediakan|keterangan
# Daftar ini diambil dari sumber LordOS, bukan dari dokumentasi.
GLYPHS='16d2|Bluetooth ᛒ|fonts-noto-core|apps/settings/index.jsx:878
2399|Printers ⎙|fonts-noto-core|apps/settings/index.jsx:878
2398|Clipboard ⎘|fonts-noto-core|apps/settings/index.jsx:878
1f512|kunci gembok 🔒|fonts-noto-color-emoji|sdk/fileglyphs.jsx:68
26a1|Power ⚡|fonts-dejavu-core|apps/settings/Power.jsx
266a|Sound ♪|fonts-dejavu-core|apps/settings/index.jsx:878
21c5|Network ⇅|fonts-dejavu-core|apps/settings/index.jsx:878
2601|Cloud ☁|fonts-dejavu-core|apps/settings/index.jsx:878
2726|AI ✦|fonts-dejavu-core|apps/settings/index.jsx:879
2328|Keyboard ⌨|fonts-dejavu-core|apps/settings/index.jsx:879
25ad|Displays ▭|fonts-dejavu-core|apps/settings/index.jsx:877
25d0|Appearance ◐|fonts-dejavu-core|apps/settings/index.jsx:877
25c9|Notifications ◉|fonts-dejavu-core|apps/settings/index.jsx:878
25eb|Default apps ◫|fonts-dejavu-core|apps/settings/index.jsx:879
25ce|Web apps ◎|fonts-dejavu-core|apps/settings/index.jsx:879
263a|Users ☺|fonts-dejavu-core|apps/settings/index.jsx:880'

# Font placeholder yang selalu ada di fontconfig dan TIDAK bisa menggambar apa pun
# dengan benar: .LastResort hanya punya kotak, Unifont terlalu kasar untuk UI.
PLACEHOLDER='^(\.|LastResort|Unifont|Droid Sans Fallback|DejaVu Sans Mono)'

have_fc_list=0
command -v fc-list >/dev/null 2>&1 && have_fc_list=1

# Keluarkan nama family pertama yang punya glyph itu, atau kosong.
font_for() {
    fc-list ":charset=$1" family 2>/dev/null \
        | tr ',' '\n' | sed 's/^ *//; s/ *$//' \
        | grep -viE "$PLACEHOLDER" | grep -v '^$' | head -n 1
}

hdr "Memeriksa glyph ikon LordOS"

if [ "$have_fc_list" -eq 1 ]; then
    note "metode: fc-list (fontconfig) — glyph dicari langsung di cmap font"
else
    warn "fc-list tidak ada; memeriksa keberadaan paket font saja (kurang tepat)"
    note "fc-list ada di paket fontconfig: sudo apt install fontconfig"
fi

missing_pkgs=''
missing_names=''
blank=0

# POSIX sh: `while` di dalam pipe berjalan di subshell dan kehilangan variabel,
# jadi hasil pemeriksaan ditulis ke file sementara lalu dibaca di shell ini.
tmp=$(mktemp) || { printf 'check-icons.sh: mktemp gagal\n' >&2; exit 1; }
trap 'rm -f "$tmp"' EXIT

printf '%s\n' "$GLYPHS" | while IFS='|' read -r cp name pkg _; do
    [ -n "$cp" ] || continue
    if [ "$have_fc_list" -eq 1 ]; then
        fam=$(font_for "$cp")
        if [ -n "$fam" ]; then
            printf 'OK|%s|%s|%s\n' "$name" "$fam" "$cp"
        else
            printf 'MISS|%s|%s|%s\n' "$name" "$pkg" "$cp"
        fi
    else
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            printf 'OK|%s|%s|%s\n' "$name" "$pkg" "$cp"
        else
            printf 'MISS|%s|%s|%s\n' "$name" "$pkg" "$cp"
        fi
    fi
done > "$tmp"

while IFS='|' read -r state name detail cp; do
    [ -n "$state" ] || continue
    cphex=$(printf '%s' "$cp" | tr 'a-f' 'A-F')
    case "$state" in
        OK)   ok "$(printf '%-18s U+%s  %s' "$name" "$cphex" "$detail")" ;;
        MISS) bad "$(printf '%-18s U+%s  tidak ada font — butuh %s' "$name" "$cphex" "$detail")"
              missing_pkgs="$missing_pkgs $detail"
              missing_names="$missing_names $name"
              blank=$((blank + 1)) ;;
    esac
done < "$tmp"

# --- ringkasan ---------------------------------------------------------------

hdr "Ringkasan"

if [ "$blank" -eq 0 ]; then
    printf '  %s%sSemua glyph punya font.%s Kalau ikon masih kosong, penyebabnya bukan font.\n\n' \
        "$OKC" "$BLD" "$OFF"
    say "  Berikutnya: cek apakah sesi sudah memuat font baru — logout lalu login."
    say "  Kalau tetap kosong, jalankan: sh scripts/doctor.sh"
    exit 0
fi

printf '  %s%s%d glyph TIDAK punya font.%s Inilah ikon yang tampil sebagai kotak.\n\n' \
    "$ERRC" "$BLD" "$blank" "$OFF"

# Paket unik, urut stabil
pkgs=$(printf '%s\n' $missing_pkgs | awk '!seen[$0]++' | tr '\n' ' ')
note "tanpa font ini, LordOS tidak bisa menggambar:"
say "    $missing_names"
say ""
note "paket yang diperlukan:"
say "    $pkgs"
say ""

printf '  Pasang dengan:\n\n    sudo apt install %s\n\n' "$pkgs"

if [ "$DO_INSTALL" -eq 1 ]; then
    [ "$(id -u)" -eq 0 ] || { say "Perlu root untuk --install. Jalankan: sudo sh check-icons.sh --install"; exit 1; }
    hdr "Memasang font"
    say "  apt-get install $pkgs"
    # shellcheck disable=SC2086 # $pkgs adalah daftar nama paket
    if DEBIAN_FRONTEND=noninteractive apt-get install -y -q $pkgs; then
        ok "terpasang"
        say ""
        note "Cache font dibangun ulang oleh apt. Sesi yang sedang berjalan belum tahu:"
        say "    lordos-logout      # lalu login lagi"
        exit 0
    fi
    bad "pemasangan gagal — coba: sudo apt update && sudo apt install $pkgs"
    exit 1
fi

say "  Setelah memasang, logout lalu login supaya sesi memuat font baru."
say "  Untuk memasang sekarang: sudo sh check-icons.sh --install"
say ""
exit 1
