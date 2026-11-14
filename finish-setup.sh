#!/bin/sh
# finish-setup.sh — menyelesaikan hal-hal yang dilakukan install.sh tetapi TIDAK
# dilakukan oleh fix-forky.sh.
#
# fix-forky.sh hanya memasang PAKET LordOS. Ia tidak menjalankan bagian "setup
# sistem" milik install.sh. Akibatnya, setelah paket terpasang:
#
#   - lordos.service tidak di-enable  -> Anda mendarat di CLI
#   - user greeter tidak dibuat       -> login screen bilang "no users"
#   - grup user tidak dilengkapi      -> audio/video/input bisa gagal
#
# Skrip ini menambal ketiganya, dengan aman dan idempoten (boleh dijalankan
# berkali-kali).
#
#   sudo sh finish-setup.sh

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
die()  { printf '\n%s✗ %s%s\n\n' "$RED" "$1" "$OFF" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || { say "Perlu root. Menjalankan ulang dengan sudo..."; exec sudo -E sh "$0" "$@"; }

GREETER_USER=lordos-greeter
FAIL=0

# ---------------------------------------------------------------- 0. paket

hdr "Memeriksa paket LordOS"

if ! dpkg -s lordos >/dev/null 2>&1; then
    die "paket lordos belum terpasang. Jalankan fix-forky.sh dulu."
fi
ok "paket lordos terpasang ($(dpkg-query -W -f='${Version}' lordos))"

# ---------------------------------------------------------------- 1. user greeter

hdr "User greeter (login screen)"

if getent passwd "$GREETER_USER" >/dev/null 2>&1; then
    ok "user $GREETER_USER sudah ada"
else
    say "  Membuat user sistem $GREETER_USER..."
    if useradd --system --home-dir /var/lib/lordos-greeter --create-home \
            --shell /usr/sbin/nologin --comment LordOS "$GREETER_USER"; then
        ok "user $GREETER_USER dibuat"
    else
        bad "gagal membuat $GREETER_USER"; FAIL=$((FAIL+1))
    fi
fi

# grup tambahan untuk greeter: ia mengomposisi lewat GPU
for g in render video; do
    if getent group "$g" >/dev/null 2>&1; then
        if id -nG "$GREETER_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then
            ok "$GREETER_USER sudah di grup $g"
        else
            usermod -aG "$g" "$GREETER_USER" 2>/dev/null && ok "$GREETER_USER ditambahkan ke $g"
        fi
    fi
done

# ---------------------------------------------------------------- 2. user Anda

hdr "User Anda (harus terlihat di login screen)"

# User yang menjalankan sudo. Kalau skrip dijalankan dari sudo, SUDO_USER berisi
# user aslinya; kalau root langsung, pakai fallback.
ME="${SUDO_USER:-}"
if [ -z "$ME" ] || [ "$ME" = root ]; then
    ME=$(awk -F: '$3 >= 1000 && $3 < 60000 { print $1; exit }' /etc/passwd)
fi

if [ -z "$ME" ]; then
    bad "tidak menemukan user biasa (uid 1000..59999) di sistem ini"
    say ""
    say "  Login screen hanya menampilkan user dengan uid >= 1000 dan shell yang bukan nologin."
    say "  Buat satu dulu:"
    say ""
    say "      sudo adduser namakamu"
    say ""
    FAIL=$((FAIL+1))
else
    uid=$(id -u "$ME" 2>/dev/null || echo "?")
    shell=$(getent passwd "$ME" | cut -d: -f7)
    ok "user: $ME (uid=$uid, shell=$shell)"

    case "$shell" in
        *nologin*|*/false)
            bad "shell user ini $shell — login screen akan MENYEMBUNYIKANNYA"
            say "      Ubah dengan: sudo usermod -s /bin/bash $ME"
            FAIL=$((FAIL+1)) ;;
    esac

    # grup yang dibutuhkan sesi LordOS
    need=""
    for g in sudo audio video input render lpadmin pipewire plugdev; do
        getent group "$g" >/dev/null 2>&1 || continue
        id -nG "$ME" 2>/dev/null | tr ' ' '\n' | grep -qx "$g" || need="$need $g"
    done
    if [ -n "$need" ]; then
        say "  Menambahkan grup yang kurang:$need"
        # shellcheck disable=SC2086
        usermod -aG $(echo $need | tr ' ' ',') "$ME" && ok "grup ditambahkan"
    else
        ok "user sudah di semua grup yang dibutuhkan"
    fi
fi

# ---------------------------------------------------------------- 3. service

hdr "Layanan LordOS"

# Unit bisa ter-mask karena `systemd.mask=lordos.service` di kernel command line
# (cara masuk ke teks saat login screen tidak bisa ditinggalkan). Selama ter-mask,
# `systemctl enable` PASTI gagal — unmask dulu.
state=$(systemctl is-enabled lordos.service 2>/dev/null || true)
case "$state" in
    masked)
        warn "lordos.service sedang MASKED (kemungkinan dari systemd.mask= di GRUB)"
        if systemctl unmask lordos.service >/dev/null 2>&1; then
            ok "mask dilepas"
        else
            bad "gagal unmask lordos.service"; FAIL=$((FAIL+1))
        fi ;;
esac

if systemctl is-enabled lordos.service >/dev/null 2>&1; then
    ok "lordos.service sudah enabled"
else
    # tampilkan alasan sebenarnya, jangan telan pesannya
    if err=$(systemctl enable lordos.service 2>&1); then
        ok "lordos.service di-enable (mulai saat boot)"
    else
        bad "gagal enable lordos.service"
        [ -n "$err" ] && printf '      %s\n' "$err"
        FAIL=$((FAIL+1))
    fi
fi

# tty1 dipakai LordOS; login teks tetap ada di tty2-tty6
if [ "$(systemctl is-enabled getty@tty1.service 2>/dev/null || true)" != masked ]; then
    systemctl mask getty@tty1.service >/dev/null 2>&1 && ok "getty@tty1 di-mask (Ctrl+Alt+F2 untuk teks login)"
else
    ok "getty@tty1 sudah di-mask"
fi

for u in lord-netperm.service lord-fand.service; do
    if systemctl is-enabled "$u" >/dev/null 2>&1; then
        ok "$u enabled"
    else
        systemctl enable "$u" >/dev/null 2>&1 && ok "$u enabled" || warn "$u tidak bisa di-enable"
    fi
done

# ---------------------------------------------------------------- 4. user PipeWire

hdr "PipeWire untuk user"

systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service >/dev/null 2>&1 \
    && ok "unit PipeWire global di-enable" || warn "gagal enable unit PipeWire global"

if [ -n "${ME:-}" ] && [ "$ME" != root ]; then
    loginctl enable-linger "$ME" >/dev/null 2>&1 && ok "linger aktif untuk $ME" || warn "linger gagal"
fi

# ---------------------------------------------------------------- 5. speaker

hdr "Pelindung speaker"

if dpkg -s speakersafetyd >/dev/null 2>&1; then
    systemctl enable --now speakersafetyd >/dev/null 2>&1 || true
    if [ "$(systemctl is-active speakersafetyd 2>/dev/null || echo no)" = active ]; then
        ok "speakersafetyd berjalan"
    else
        warn "speakersafetyd belum aktif — mungkin butuh reboot"
    fi
else
    bad "speakersafetyd TIDAK terpasang — speaker berisiko rusak"
    say "      Jalankan: sudo apt install asahi-platform"
    FAIL=$((FAIL+1))
fi

# ---------------------------------------------------------------- 6. DRM

hdr "Display"

cards=0
for c in /sys/class/drm/card[0-9]; do [ -e "$c" ] && cards=$((cards+1)); done
if [ "$cards" -gt 0 ]; then
    ok "$cards DRM card terdeteksi"
else
    bad "tidak ada /sys/class/drm/card* — layar tidak akan menyala"
    FAIL=$((FAIL+1))
fi

# ---------------------------------------------------------------- hasil

hdr "Hasil"

if [ "$FAIL" -gt 0 ]; then
    bad "$FAIL masalah belum selesai — lihat tanda ✗ di atas"

    # Jangan biarkan user terkunci: kalau lordos.service tidak bisa jalan dan
    # getty@tty1 juga ter-mask, tidak ada jalan masuk sama sekali.
    if ! systemctl is-enabled lordos.service >/dev/null 2>&1; then
        if [ "$(systemctl is-enabled getty@tty1.service 2>/dev/null || true)" = masked ]; then
            say ""
            warn "Mengembalikan login teks di tty1 supaya Anda tidak terkunci"
            systemctl unmask getty@tty1.service >/dev/null 2>&1 && \
                ok "getty@tty1 di-unmask (login teks tersedia setelah reboot)"
        fi
    fi

    printf '\nPerbaiki, lalu jalankan lagi: sudo sh finish-setup.sh\n\n'
    exit 1
fi

printf '%s%sSemua siap.%s Reboot sekarang:\n\n' "$GRN" "$BLD" "$OFF"
printf '    sudo reboot\n\n'
printf 'Setelah reboot Anda akan melihat login screen LordOS.\n'
printf 'Kalau masih "no users", jalankan: journalctl -b -u lordos.service\n\n'
