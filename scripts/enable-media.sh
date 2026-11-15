#!/bin/sh
# enable-media.sh — mengaktifkan video, kamera dan mikrofon LordOS di Debian Forky.
#
# Gejala: doctor.sh melaporkan "lord-media TIDAK ADA", jadi pemutaran video,
# kamera dan mikrofon mati (desktop, browser, file manager dan audio biasa tetap
# jalan — audio tidak lewat lord-media).
#
# Sebabnya satu ketidakcocokan soname:
#
#   paket LordOS dibangun terhadap   libavcodec.so.61   (FFmpeg 7, Debian trixie)
#   Debian Forky hanya punya         libavcodec.so.63   (FFmpeg 8)
#
# Diperiksa langsung dari biner resmi: lord-media memuat 7 pustaka
# (libavcodec.so.61, libavformat.so.61, libavutil.so.59, libswscale.so.8,
# libswresample.so.5, libva.so.2, libva-drm.so.2). Karena itu fix-forky.sh
# membuang biner ini dan dependensinya saat memasang LordOS.
#
# Skrip ini mengembalikannya: memasang FFmpeg 7 dari trixie (dipin, hanya enam
# paket) lalu mengambil lord-media dari paket resmi yang SUDAH TERPASANG di
# mesin ini — bukan mengunduh ulang paket 31 MB.
#
#   sh scripts/enable-media.sh             # periksa saja, tidak mengubah apa pun
#   sudo sh scripts/enable-media.sh --apply
#
# PERINGATAN: ini mencampur dua rilis Debian. Baca MEDIA.md sebelum --apply.
# Untuk membatalkan: sudo sh scripts/enable-media.sh --revert

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

# Soname FFmpeg 7 yang dibutuhkan lord-media (dibaca dari DT_NEEDED binernya).
# Paket Debian yang menyediakannya, di urutan pemasangan yang benar.
FF7_PKGS="libavutil59 libavcodec61 libavformat61 libswscale8 libswresample5"

MODE=check
for a in "$@"; do
    case "$a" in
        --apply)  MODE=apply ;;
        --revert) MODE=revert ;;
        -h|--help)
            # Di-pipe (curl | sh), $0 adalah "sh" — bukan berkas yang bisa dibaca.
            [ -f "$0" ] && sed -n '2,26p' "$0"
            printf '\nPilihan:\n  (tanpa argumen)  periksa saja, tidak mengubah apa pun\n  --apply          terapkan\n  --revert         batalkan\n\n'
            exit 0 ;;
        *) die "argumen tidak dikenal: $a (pakai --apply atau --revert)" ;;
    esac
done

as_root() {
    [ "$(id -u)" -eq 0 ] && return 0
    say "Perlu root. Menjalankan ulang dengan sudo..."
    exec sudo -E sh "$0" "$@"
}

# ---------------------------------------------------------------- --revert

if [ "$MODE" = revert ]; then
    as_root --revert
    hdr "Membatalkan"
    rm -f /etc/apt/sources.list.d/trixie-media.list
    rm -f /etc/apt/preferences.d/trixie-media.pref
    rm -f /usr/lib/lordos/bin/lord-media
    ok "sumber trixie, pin, dan lord-media dihapus"
    say ""
    note "Paket FFmpeg 7 sendiri dibiarkan: paket lain mungkin sudah bergantung"
    note "padanya. apt akan mengeluh kalau aman untuk dihapus:"
    say "    sudo apt autoremove"
    say ""
    note "LordOS kembali seperti semula: media mati, sisanya jalan."
    exit 0
fi

# ---------------------------------------------------------------- 1. keadaan

hdr "Keadaan sekarang"

[ "$(id -u)" -eq 0 ] || ok "mode periksa (tidak mengubah apa pun)"
if [ -r /proc/device-tree/model ]; then
    ok "mesin: $(tr -d '\000' < /proc/device-tree/model)"
else
    bad "tidak ada /proc/device-tree/model — ini bukan mesin Apple Silicon"
fi

# Dibaca dengan sed, bukan `. /etc/os-release`: berkas itu dieksekusi kalau
# di-source, dan OS_RELEASE membuat pemeriksaan ini bisa diuji tanpa Debian.
codename=$(sed -n 's/^VERSION_CODENAME=//p' "${OS_RELEASE:-/etc/os-release}" 2>/dev/null \
           | head -n 1 | sed 's/^"//; s/"$//')
case "$codename" in
    forky|sid) ok "Debian $codename" ;;
    trixie)
        say ""
        ok "Debian trixie: FFmpeg 7 memang sudah ada di sini"
        note "Di trixie tidak ada yang perlu diperbaiki — media jalan tanpa skrip ini."
        exit 0 ;;
    "")        warn "Versi Debian tidak terdeteksi (tidak ada /etc/os-release)" ;;
    *)         warn "Debian $codename; skrip ini ditulis untuk forky/sid" ;;
esac

helper=/usr/lib/lordos/bin/lord-media
if [ -x "$helper" ]; then
    ok "lord-media sudah ada di $helper"
else
    bad "lord-media TIDAK ada di $helper (ini yang mematikan media)"
fi

# Paket lordos wajib ada: tanpa itu tidak ada lord-server untuk dijalankan
# bersama lord-media, dan tidak ada paket asal untuk mengambil binernya.
if command -v dpkg-query >/dev/null 2>&1 && dpkg -s lordos >/dev/null 2>&1; then
    ok "paket lordos terpasang ($(dpkg-query -W -f='${Version}' lordos))"
else
    die "paket lordos tidak terpasang — pasang LordOS dulu (README, Langkah 4)"
fi

# Apakah FFmpeg 7 sudah bisa dimuat? Ini pertanyaan yang sebenarnya, bukan
# keberadaan paket: yang menentukan hanya apakah loader bisa menemukan soname-nya.
ff7_present=0
missing_sonames=''
for soname in libavcodec.so.61 libavformat.so.61 libavutil.so.59 libswscale.so.8 libswresample.so.5; do
    if ldconfig -p 2>/dev/null | grep -q "$soname"; then
        :
    else
        missing_sonames="$missing_sonames $soname"
    fi
done
[ -z "$missing_sonames" ] && ff7_present=1

if [ "$ff7_present" -eq 1 ]; then
    ok "FFmpeg 7 (soname .61/.59/.8/.5) dapat dimuat"
else
    bad "FFmpeg 7 tidak ada — kurang:$missing_sonames"
fi

# ---------------------------------------------------------------- 2. rencana

hdr "Rencana"

if [ -x "$helper" ] && [ "$ff7_present" -eq 1 ]; then
    ok "Media sudah aktif. Tidak ada yang perlu dilakukan."
    say ""
    note "Kalau aplikasi masih menolak memutar video, restart sesi:"
    say "    systemctl restart lordos.service"
    exit 0
fi

say "  1. Menambahkan Debian trixie sebagai sumber apt, DIPIN hanya untuk:"
say "     $FF7_PKGS"
say "     Paket lain tetap dari ${VERSION_CODENAME:-forky}."
say ""
say "  2. Memasang lima paket FFmpeg 7 itu."
say ""
if [ -x "$helper" ]; then
    say "  3. lord-media: sudah ada, tidak perlu diambil."
else
    SAY_SRC="paket lordos $(dpkg-query -W -f='${Version}' lordos) yang sudah terpasang"
    say "  3. Mengambil lord-media dari $SAY_SRC"
    say "     (tanpa mengunduh ulang paket 31 MB)."
fi
say ""

warn "Risiko yang sudah diukur (lihat MEDIA.md):"
note "tiga paket toolchain turun versi: gcc-16-base, libstdc++6, libgcc-s1"
note "libc6 TIDAK ikut turun. Tidak ada konflik dependensi."
say ""

if [ "$MODE" != apply ]; then
    printf '  Jalankan untuk menerapkan:\n\n    sudo sh %s --apply\n\n' "$(basename -- "$0")"
    note "Baca MEDIA.md dulu. Untuk membatalkan: --revert"
    exit 0
fi

# ---------------------------------------------------------------- 3. terapkan

as_root --apply

if ! command -v dpkg-deb >/dev/null 2>&1; then
    die "dpkg-deb tidak ada — ini bukan sistem Debian?"
fi

hdr "Sumber dan pin"

# Pin: hanya enam paket FFmpeg yang boleh diambil dari trixie; seluruh Forky
# tetap berprioritas lebih tinggi, jadi tidak ada paket lain yang ikut turun.
printf 'deb http://deb.debian.org/debian trixie main\n' > /etc/apt/sources.list.d/trixie-media.list
cat > /etc/apt/preferences.d/trixie-media.pref <<'EOF'
# Ditulis oleh enable-media.sh. Hapus untuk membatalkan (--revert).
Package: *
Pin: release n=forky
Pin-Priority: 900

Package: *
Pin: release n=trixie
Pin-Priority: 100

Package: libavcodec61 libavformat61 libavutil59 libswscale8 libswresample5 libavcodec-extra61
Pin: release n=trixie
Pin-Priority: 1001
EOF
ok "sumber trixie ditambahkan, dipin hanya untuk FFmpeg 7"

apt-get update -q </dev/null || die "apt-get update gagal — periksa jaringan"

hdr "Memasang FFmpeg 7"

# shellcheck disable=SC2086 # $FF7_PKGS adalah daftar nama paket
if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -q $FF7_PKGS </dev/null; then
    die "pemasangan FFmpeg 7 gagal. Tidak ada perubahan lain pada sesi LordOS."
fi
ok "FFmpeg 7 terpasang"

# Pastikan yang terpasang benar-benar soname .61, bukan .63 dari forky
if ! ldconfig -p 2>/dev/null | grep -q 'libavcodec.so.61'; then
    die "libavcodec.so.61 masih tidak ada setelah pemasangan — pin tidak bekerja"
fi
ok "loader sekarang menemukan libavcodec.so.61"

# ---------------------------------------------------------------- 4. lord-media

hdr "Mengambil lord-media"

if [ -x "$helper" ]; then
    ok "lord-media sudah ada di $helper"
else
    work=$(mktemp -d) || die "tidak bisa membuat folder kerja"
    trap 'rm -rf "$work"' EXIT

    got=""

    # Jalan 1 (disukai): dari paket .deb yang sudah diunduh apt saat LordOS
    # dipasang. Versinya pasti sama dengan lord-server yang berjalan, dan paket
    # itu sudah lewat verifikasi apt.
    set -- /var/cache/apt/archives/lordos_*_arm64.deb
    if [ -f "$1" ]; then
        say "  dari cache apt: $(basename "$1")"
        dpkg-deb --fsys-tarfile "$1" > "$work/fs.tar" 2>/dev/null && got=1
    fi

    # Jalan 2: unduh paket resmi, dan WAJIB memverifikasi tanda tangan rilis
    # lebih dulu — tanpa ini skrip akan memasang biner tanpa bukti asalnya.
    if [ -z "$got" ]; then
        ver=$(dpkg-query -W -f='${Version}' lordos 2>/dev/null || true)
        [ -n "$ver" ] || die "tidak tahu versi lordos yang terpasang"
        base="https://github.com/lordbasex/LordOS/releases/download/v${ver}-beta"
        say "  cache apt kosong; mengunduh paket resmi v${ver}-beta"
        note "  $base"

        for f in SHA256SUMS SHA256SUMS.sig; do
            curl -fsSL --max-time 60 -o "$work/$f" "$base/$f" \
                || die "gagal mengunduh $f dari rilis — periksa jaringan"
        done

        printf '%s\n' \
            "-----BEGIN PUBLIC KEY-----" \
            "MCowBQYDK2VwAyEA8cqwDzH+ZVMdBqNjC3141dmo3gcH8PWt88I+RE9dOaA=" \
            "-----END PUBLIC KEY-----" > "$work/release.pub"

        if ! command -v openssl >/dev/null 2>&1; then
            say "  Memasang openssl untuk memeriksa tanda tangan..."
            DEBIAN_FRONTEND=noninteractive apt-get install -y -q openssl </dev/null >/dev/null \
                || die "openssl dibutuhkan untuk memeriksa tanda tangan rilis"
        fi

        base64 -d < "$work/SHA256SUMS.sig" > "$work/sums.sig.bin" 2>/dev/null \
            || die "SHA256SUMS.sig bukan base64 yang valid"
        if ! openssl pkeyutl -verify -pubin -inkey "$work/release.pub" -rawin \
                -in "$work/SHA256SUMS" -sigfile "$work/sums.sig.bin" >/dev/null 2>&1; then
            die "tanda tangan SHA256SUMS TIDAK valid — berkas rilis mungkin diubah. Tidak ada yang dipasang."
        fi
        ok "tanda tangan rilis valid (Ed25519)"

        name="lordos_${ver}_arm64.deb"
        want=$(awk -v n="$name" '$2 == n || $2 == "*" n { print $1 }' "$work/SHA256SUMS")
        [ -n "$want" ] || die "$name tidak ada di SHA256SUMS rilis ini"
        curl -fsSL --max-time 300 -o "$work/$name" "$base/$name" \
            || die "gagal mengunduh $name"
        have=$(sha256sum "$work/$name" | cut -d' ' -f1)
        [ "$have" = "$want" ] \
            || die "SHA-256 $name tidak cocok dengan SHA256SUMS — unduhan rusak atau diubah"
        ok "SHA-256 cocok"

        dpkg-deb --fsys-tarfile "$work/$name" > "$work/fs.tar" 2>/dev/null && got=1
    fi

    [ -n "$got" ] || die "tidak bisa membaca isi paket lordos"

    # Ambil hanya biner lord-media dari isi paket.
    ( cd "$work" && tar xf fs.tar ./usr/lib/lordos/bin/lord-media ) 2>/dev/null \
        || die "paket lordos tidak berisi usr/lib/lordos/bin/lord-media"
    [ -f "$work/usr/lib/lordos/bin/lord-media" ] || die "lord-media tidak ada di dalam paket"

    # lord-server hanya mau menjalankan helper yang milik root/user dan tidak
    # bisa ditulis pihak lain (media/media.c:125-127) — jadi pemilik dan mode
    # keduanya harus benar, bukan hanya isinya.
    install -o root -g root -m 0755 "$work/usr/lib/lordos/bin/lord-media" "$helper" \
        || die "gagal memasang $helper"
    ok "lord-media terpasang (root:root 0755)"
fi

# ---------------------------------------------------------------- 5. verifikasi

hdr "Verifikasi"

fail=0

if [ -x "$helper" ]; then
    ok "lord-media ada dan dapat dieksekusi"
else
    bad "lord-media masih tidak ada"; fail=1
fi

# Yang menentukan bukan keberadaan paket, tetapi apakah loader bisa memuat
# semua soname yang tertanam di biner itu (DT_NEEDED).
missing=''
for soname in libavcodec.so.61 libavformat.so.61 libavutil.so.59 libswscale.so.8 \
              libswresample.so.5 libva.so.2 libva-drm.so.2; do
    ldconfig -p 2>/dev/null | grep -q "$soname" || missing="$missing $soname"
done
if [ -z "$missing" ]; then
    ok "semua 7 pustaka yang dibutuhkan lord-media dapat dimuat"
else
    bad "pustaka masih hilang:$missing"; fail=1
    note "libva.so.2 / libva-drm.so.2 datang dari paket libva2 dan libva-drm2:"
    say "    sudo apt install libva2 libva-drm2"
fi

# ldd menjawab pertanyaan yang sebenarnya: apakah loader menyelesaikan setiap
# soname, atau menulis "not found".
if [ -x "$helper" ] && command -v ldd >/dev/null 2>&1; then
    if ldd "$helper" 2>/dev/null | grep -q 'not found'; then
        bad "ldd masih melaporkan pustaka 'not found':"
        ldd "$helper" 2>/dev/null | grep 'not found' | sed 's/^/      /'
        fail=1
    else
        ok "ldd: semua dependensi lord-media terselesaikan"
    fi
fi

if [ "$fail" -ne 0 ]; then
    printf '\n%s✗ Media belum aktif.%s Lihat tanda ✗ di atas.\n' "$RED" "$BLD"
    say ""
    note "Bila pustaka hilang setelah --apply, kirimkan keluaran ini:"
    say "    ldd $helper | grep 'not found'"
    say "    sh scripts/doctor.sh"
    printf '%s\n' ""
    exit 1
fi

# ---------------------------------------------------------------- 6. selesai

hdr "Selesai"

ok "Media aktif: video, kamera dan mikrofon"

# lord-server menanyakan keberadaan lord-media sekali lalu menyimpannya
# (media/media.c:135: static int checked). Sesi yang berjalan belum tahu.
say ""
note "LordOS mencari lord-media sekali saat mulai. Sesi yang sedang berjalan"
note "belum tahu, jadi restart:"
say ""
say "    systemctl restart lordos.service"
say ""
note "Lalu periksa:"
say "    sh scripts/doctor.sh  # bagian 4 harus menulis 'lord-media ADA'"
say "    ldd $helper | grep 'not found'    # harus kosong"
say ""
note "Membatalkan semuanya: sudo sh scripts/enable-media.sh --revert"
say ""
exit 0
