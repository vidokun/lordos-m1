#!/bin/sh
# fix-icons.sh — memasang tema ikon yang hilang di LordOS pada Debian Forky.
#
# Gejala: ikon aplikasi (file manager, browser, pengaturan) tampil kosong atau
# kotak-kotak, sementara ikon LordOS sendiri (crown, glyph) normal.
#
# Sebab: paket LordOS membawa ikonnya sendiri di /usr/lib/lordos/assets/icons,
# tetapi aplikasi GTK dan Qt memakai tema ikon SISTEM. Debian minimal (console)
# yang dipasang lewat Bananas tidak membawa adwaita-icon-theme, dan paket LordOS
# tidak merekomendasikannya. Akibatnya aplikasi tidak punya ikon untuk digambar.
#
#   sudo sh fix-icons.sh

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

[ "$(id -u)" -eq 0 ] || { say "Perlu root. Menjalankan ulang dengan sudo..."; exec sudo -E sh "$0" "$@"; }

hdr "Memeriksa ikon"

have_adwaita=0
[ -d /usr/share/icons/Adwaita ] && have_adwaita=1
have_hicolor=0
[ -d /usr/share/icons/hicolor ] && have_hicolor=1

if [ "$have_adwaita" -eq 1 ]; then
    ok "Adwaita ada"
else
    warn "Adwaita TIDAK ada — ini penyebab ikon kosong"
fi

if [ "$have_hicolor" -eq 1 ]; then
    ok "hicolor ada"
else
    warn "hicolor TIDAK ada"
fi

if [ "$have_adwaita" -eq 1 ] && [ "$have_hicolor" -eq 1 ]; then
    say ""
    say "Tema ikon sudah lengkap. Kalau ikon masih kosong, masalahnya di tempat lain:"
    say ""
    say "    sh doctor.sh      # periksa menyeluruh"
    say ""
    exit 0
fi

hdr "Memasang tema ikon"

# adwaita-icon-theme membawa ikon standar GNOME; hicolor adalah fallback wajib
pkgs=""
[ "$have_adwaita" -eq 0 ] && pkgs="$pkgs adwaita-icon-theme"
[ "$have_hicolor" -eq 0 ] && pkgs="$pkgs hicolor-icon-theme"

say "  Memasang:$pkgs"
say ""

# shellcheck disable=SC2086
if apt-get install -y -q --no-install-recommends $pkgs; then
    ok "terpasang"
else
    say ""
    warn "gagal memasang. Coba perbarui indeks dulu:"
    say "      sudo apt update && sudo apt install$pkgs"
    exit 1
fi

hdr "Memperbarui cache ikon"

if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    for d in /usr/share/icons/Adwaita /usr/share/icons/hicolor; do
        [ -f "$d/index.theme" ] || continue
        gtk-update-icon-cache -f -t "$d" >/dev/null 2>&1 && ok "cache $d diperbarui"
    done
else
    warn "gtk-update-icon-cache tidak ada (biasanya tidak masalah)"
fi

hdr "Selesai"

say "  Logout lalu login lagi supaya sesi membaca tema baru:"
say ""
say "      lordos-logout        # atau: systemctl restart lordos.service"
say ""
say "  Kalau ikon masih kosong setelah itu, jalankan:"
say ""
say "      sh doctor.sh"
say ""
