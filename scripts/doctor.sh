#!/bin/sh
# doctor.sh — pemeriksa menyeluruh LordOS di Debian Forky.
#
# Menjawab: apa yang berjalan, apa yang tidak, dan apa yang bisa diperbaiki.
# Hanya MEMBACA. Tidak memasang, tidak mengubah, tidak menghapus apa pun.
#
#   sh doctor.sh            # ringkasan
#   sh doctor.sh --fix-hints  # sertakan perintah perbaikan (default: ya)
#
# Keluar 0 kalau tidak ada masalah wajib.

set -u

OKC=''; ERRC=''; WARNC=''; BLD=''; OFF=''
if [ -t 1 ]; then
    OKC=$(printf '\033[32m'); ERRC=$(printf '\033[31m')
    WARNC=$(printf '\033[33m'); BLD=$(printf '\033[1m'); OFF=$(printf '\033[0m')
fi

FAIL=0; WARN=0; PASS=0

hdr() { printf '\n%s%s%s\n' "$BLD" "$1" "$OFF"; }
ok()   { printf '  %s✓%s %s\n' "$OKC" "$OFF" "$1"; PASS=$((PASS+1)); }
warn() { printf '  %s!%s %s\n' "$WARNC" "$OFF" "$1"; WARN=$((WARN+1)); }
bad()  { printf '  %s✗%s %s\n' "$ERRC" "$OFF" "$1"; FAIL=$((FAIL+1)); }
fix()  { printf '      %s→ %s%s\n' "$WARNC" "$1" "$OFF"; }
note() { printf '      %s\n' "$1"; }

# ---------------------------------------------------------------- 1. sistem

hdr "1. Sistem"

[ -r /etc/os-release ] && . /etc/os-release
case "${VERSION_CODENAME:-}" in
    forky|sid) ok "Debian ${VERSION_CODENAME} (didukung)" ;;
    trixie)    ok "Debian trixie (didukung)" ;;
    *)         warn "Debian ${VERSION_CODENAME:-tidak dikenal}" ;;
esac

model=""
[ -r /proc/device-tree/model ] && model=$(tr -d '\000' < /proc/device-tree/model)
case "$model" in
    *Apple*) ok "Apple Silicon: $model" ;;
    *)       warn "bukan Apple Silicon: ${model:-tidak terdeteksi}" ;;
esac

kver=$(uname -r)
printf '  Kernel: %s\n' "$kver"
if [ -r "/boot/config-$kver" ] && grep -qE '^CONFIG_DRM_APPLE=[my]$' "/boot/config-$kver"; then
    ok "driver display Apple ada"
else
    bad "CONFIG_DRM_APPLE tidak ada — layar bisa hitam"
fi

# ---------------------------------------------------------------- 2. layanan

hdr "2. Layanan"

svc() {                       # svc <unit> <wajib|opsional>
    u=$1; need=$2
    en=$(systemctl is-enabled "$u" 2>/dev/null || echo "no")
    ac=$(systemctl is-active  "$u" 2>/dev/null || echo "no")
    case "$ac:$en" in
        active:enabled)  ok "$u: aktif, enabled" ;;
        active:*)        ok "$u: aktif (enabled=$en)" ;;
        *:enabled)       warn "$u: enabled tapi tidak aktif"
                         fix "sudo systemctl start $u" ;;
        *)
            if [ "$need" = wajib ]; then
                bad "$u: TIDAK aktif dan TIDAK enabled"
                fix "sudo systemctl enable --now $u"
            else
                warn "$u: tidak aktif"
            fi ;;
    esac
}

svc lordos.service wajib
svc lord-netperm.service wajib
svc lord-fand.service opsional
svc speakersafetyd.service wajib
svc bluetooth.service opsional
svc pipewire.service opsional
svc wireplumber.service opsional

printf '\n  Unit yang gagal:\n'
failed=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}')
if [ -z "$failed" ]; then
    ok "tidak ada unit gagal"
else
    for u in $failed; do
        bad "$u gagal"
        fix "journalctl -u $u -b --no-pager | tail -20"
    done
fi

# ---------------------------------------------------------------- 3. display

hdr "3. Display dan GPU"

cards=0
for c in /sys/class/drm/card[0-9]; do [ -e "$c" ] && cards=$((cards+1)); done
if [ "$cards" -gt 0 ]; then
    ok "$cards DRM card"
else
    bad "tidak ada DRM card"
fi

conn=0
for c in /sys/class/drm/card*-*; do
    [ -e "$c/status" ] || continue
    s=$(cat "$c/status" 2>/dev/null)
    [ "$s" = connected ] && conn=$((conn+1))
done
[ "$conn" -gt 0 ] && ok "$conn connector terhubung" || warn "tidak ada connector 'connected'"

if [ -e /dev/dri/renderD128 ]; then ok "render node ada (GPU 3D)"; else warn "tidak ada render node"; fi

# komposisi GPU vs CPU — LordOS menulisnya di log sesi
if systemctl is-active lordos.service >/dev/null 2>&1; then
    comp=$(journalctl -b -u lordos.service --no-pager 2>/dev/null | grep -oiE "CPU composition|GPU composition" | tail -1)
    [ -n "$comp" ] && note "komposisi: $comp"
fi

# ---------------------------------------------------------------- 4. media

hdr "4. Media (video, kamera, mikrofon)"

if [ -x /usr/lib/lordos/bin/lord-media ]; then
    ok "lord-media ADA"
    # cek dependensi yang benar-benar dipakai
    miss=""
    for lib in libavcodec libavformat libavutil libswscale libswresample; do
        found=$(ldd /usr/lib/lordos/bin/lord-media 2>/dev/null | grep "$lib" | awk '{print $3}')
        if [ -n "$found" ] && [ ! -e "$found" ]; then
            miss="$miss $lib"
        fi
    done
    if [ -z "$miss" ]; then
        ok "library media lengkap"
    else
        bad "library media hilang:$miss"
        fix "lihat MEDIA.md di repo untuk memasang FFmpeg 7"
    fi
else
    warn "lord-media TIDAK ADA — video, kamera, mikrofon nonaktif"
    note "Ini normal di Debian Forky: LordOS butuh FFmpeg 7, Forky punya FFmpeg 8."
    fix "lihat MEDIA.md untuk mengaktifkannya"
fi

# kamera dan audio
if [ -e /dev/video0 ]; then ok "kamera terdeteksi (/dev/video0)"; else note "tidak ada /dev/video0 (kamera)"; fi
if command -v wpctl >/dev/null 2>&1; then
    sink=$(wpctl status 2>/dev/null | grep -c "Sinks:")
    [ "$sink" -gt 0 ] && ok "PipeWire punya sink audio" || warn "PipeWire tanpa sink audio"
fi

# ---------------------------------------------------------------- 5. ikon

hdr "5. Ikon dan font"

missing_icon=0
for t in Adwaita hicolor; do
    if [ -d "/usr/share/icons/$t" ]; then
        ok "tema ikon $t ada"
    else
        if [ "$t" = Adwaita ]; then
            bad "tema ikon Adwaita TIDAK ADA — ikon aplikasi Linux akan kosong"
            fix "sudo apt install adwaita-icon-theme"
            missing_icon=1
        else
            warn "tema ikon $t tidak ada"
        fi
    fi
done

if [ "$missing_icon" -eq 1 ]; then
    note "LordOS membawa ikonnya sendiri (assets/icons), tapi aplikasi GTK/Qt"
    note "memakai tema sistem. Tanpa Adwaita, ikon mereka tidak muncul."
fi

for f in fonts-noto-core fonts-dejavu-core; do
    if dpkg -s "$f" >/dev/null 2>&1; then ok "$f terpasang"; else warn "$f tidak terpasang"; fi
done

# ---------------------------------------------------------------- 6. paket Asahi

hdr "6. Paket Asahi"

for p in asahi-platform asahi-scripts speakersafetyd asahi-audio; do
    if dpkg -s "$p" >/dev/null 2>&1; then
        ok "$p terpasang"
    else
        case "$p" in
            asahi-platform|speakersafetyd) bad "$p TIDAK terpasang"; fix "sudo apt install asahi-platform" ;;
            *) warn "$p tidak terpasang"; fix "sudo apt install $p" ;;
        esac
    fi
done

# ---------------------------------------------------------------- 7. sesi user

hdr "7. Sesi user"

ME="${SUDO_USER:-$(awk -F: '$3>=1000 && $3<60000 {print $1; exit}' /etc/passwd)}"
if [ -n "$ME" ]; then
    ok "user: $ME (uid=$(id -u "$ME" 2>/dev/null))"
    sh_=$(getent passwd "$ME" | cut -d: -f7)
    case "$sh_" in
        *nologin*|*/false) bad "shell $sh_ — greeter akan menyembunyikan user ini" ;;
        *) ok "shell: $sh_" ;;
    esac
    miss=""
    for g in audio video input render pipewire; do
        getent group "$g" >/dev/null 2>&1 || continue
        id -nG "$ME" 2>/dev/null | tr ' ' '\n' | grep -qx "$g" || miss="$miss $g"
    done
    if [ -n "$miss" ]; then
        warn "grup kurang:$miss"
        fix "sudo usermod -aG $(echo $miss | tr ' ' ',') $ME"
    else
        ok "semua grup sesi lengkap"
    fi
else
    warn "tidak menemukan user biasa"
fi

if getent passwd lordos-greeter >/dev/null 2>&1; then
    ok "user lordos-greeter ada"
else
    bad "user lordos-greeter TIDAK ADA — login screen akan bilang 'no users'"
    fix "sudo sh lib/finish-setup.sh"
fi

# ---------------------------------------------------------------- hasil

hdr "Ringkasan"

printf '  %s%d lulus%s   %s%d peringatan%s   %s%d masalah%s\n\n' \
    "$OKC" "$PASS" "$OFF" "$WARNC" "$WARN" "$OFF" "$ERRC" "$FAIL" "$OFF"

if [ "$FAIL" -eq 0 ]; then
    printf '%s%sTidak ada masalah wajib.%s\n\n' "$OKC" "$BLD" "$OFF"
    [ "$WARN" -gt 0 ] && printf 'Ada %d peringatan — lihat tanda ! di atas.\n\n' "$WARN"
    exit 0
fi

printf '%s%s%d masalah perlu diperbaiki.%s Lihat tanda ✗ dan baris → di atas.\n\n' \
    "$ERRC" "$BLD" "$FAIL" "$OFF"
exit 1
