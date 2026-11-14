#!/bin/sh
# check-performance.sh — mengapa animasi LordOS terasa lambat, dengan angka.
#
# Hanya MEMBACA: tidak memasang, tidak mengubah, tidak menghapus apa pun.
#
#   sh check-performance.sh
#
# Yang menentukan bukan "ada GPU" tetapi jalur mana yang dipakai kompositor:
# LordOS memakai GPU kalau renderer GL-nya bukan software, dan jatuh ke jalur
# CPU-nya sendiri kalau renderer-nya llvmpipe/softpipe (docs/GPU.md:31-38).
# Di mesin tanpa driver Apple, animasi jadi lambat justru karena itu.

set -u

RED=''; GRN=''; YLW=''; BLD=''; OFF=''
if [ -t 1 ]; then
    RED=$(printf '\033[31m'); GRN=$(printf '\033[32m')
    YLW=$(printf '\033[33m'); BLD=$(printf '\033[1m'); OFF=$(printf '\033[0m')
fi

PASS=0; WARN=0; FAIL=0
hdr() { printf '\n%s%s%s\n' "$BLD" "$1" "$OFF"; }
ok()   { printf '  %s✓%s %s\n' "$GRN" "$OFF" "$1"; PASS=$((PASS+1)); }
warn() { printf '  %s!%s %s\n' "$YLW" "$OFF" "$1"; WARN=$((WARN+1)); }
bad()  { printf '  %s✗%s %s\n' "$RED" "$OFF" "$1"; FAIL=$((FAIL+1)); }
note() { printf '      %s\n' "$1"; }
fix()  { printf '      %s→ %s%s\n' "$YLW" "$1" "$OFF"; }

# ---------------------------------------------------------------- 1. jalur

hdr "1. Jalur komposisi (ini yang menentukan)"

LOGS="/var/log/lordos/log/users/*/compositor.log /var/log/lordos/users/*/compositor.log"
# Tanpa lord-sessiond, log sesi ada di ~/.cache/lordos (lordlog.c:106). Untuk
# sesi yang sedang berjalan, $HOME skrip ini adalah home user itu.
[ -n "${HOME:-}" ] && LOGS="$LOGS $HOME/.cache/lordos/compositor.log"
line=''
for f in $LOGS; do
    [ -r "$f" ] || continue
    l=$(grep -h "gpu: " "$f" 2>/dev/null | tail -1)
    [ -n "$l" ] && line="$l" && log_f="$f"
done
# fallback: journal, seperti yang dipakai doctor.sh
if [ -z "$line" ]; then
    l=$(journalctl -b -u lordos.service --no-pager 2>/dev/null | grep "gpu: " | tail -1)
    [ -n "$l" ] && line="$l" && log_f="journalctl -u lordos.service"
fi

# Baris-baris dari gpu.c. Yang sukses menyebut renderer-nya, yang gagal
# menyebut alasannya — jadi alasannya dibaca, bukan disimpulkan:
#   gpu: GPU composition (llvmpipe …, EGL 1.5, dmabuf …, render …, display …)
#   gpu: the renderer is software (llvmpipe …): CPU composition
#   gpu: no GBM on the card, CPU composition
#   gpu: off (LORD_GPU=0), CPU composition
# "GPU composition (llvmpipe …)" MASIH jalur GPU — hanya renderer software.
case "$line" in
    "")
        warn "belum bisa dibaca dari log"
        note "Dibaca dari /var/log/lordos/users/*/compositor.log dan ~/.cache/lordos."
        fix "grep 'gpu: ' /var/log/lordos/users/*/compositor.log | tail -1"
        fix "grep 'gpu: ' ~/.cache/lordos/compositor.log | tail -1" ;;
    *"GPU composition"*)
        ok "GPU composition"
        note "$line"
        case "$line" in
            *llvmpipe*|*softpipe*|*swrast*)
                warn "renderer-nya software (llvmpipe): digambar di atas GPU, bukan CPU LordOS"
                note "Jalurnya GPU, tapi driver asli Apple tidak dipakai — itu yang membuatnya lebih lambat." ;;
            *) ok "renderer hardware — jalur tercepat" ;;
        esac ;;
    *"CPU composition"*)
        bad "CPU composition — animasi digambar di CPU, inilah lag-nya"
        note "$line"
        # Alasannya tertulis di baris itu; tiap alasan butuh tindakan berbeda.
        case "$line" in
            *"LORD_GPU=0"*)         fix "LORD_GPU=0 di environment mematikan GPU: hapus dari /etc/environment atau profil sesi" ;;
            *"no GBM"*)             fix "GBM tidak tersedia untuk card ini (libgbm1 / driver DRM)" ;;
            *"no 3D acceleration"*) fix "driver card ini melaporkan tanpa 3D; LORD_GPU=1 memaksa mencoba" ;;
            *"no EGL"*|*"EGL did not start"*) fix "EGL gagal start: periksa libegl-mesa0 dan /dev/dri" ;;
            *"no XRGB8888"*)        fix "card tidak menawarkan config EGL XRGB8888" ;;
            *"context"*)            fix "konteks/surface GLES2 gagal dibuat" ;;
            *"shaders"*)            fix "shader gagal dikompilasi — bug driver, bukan pengaturan" ;;
            *"renderer is software"*) fix "Mesa memilih renderer software untuk card ini: tidak ada driver hardware yang cocok" ;;
            *)                      fix "alasannya ada di baris di atas" ;;
        esac ;;
    *) note "baris gpu: tidak dikenali: $line" ;;
esac

[ -n "${log_f:-}" ] && note "sumber: $log_f"

# ---------------------------------------------------------------- 2. GPU

hdr "2. Perangkat GPU"

# Versi paket: fitur UI berbeda antar rilis, jadi jawaban "tidak ada
# pengaturannya" tidak bisa dinilai tanpa ini.
if command -v dpkg-query >/dev/null 2>&1; then
    v=$(dpkg-query -W -f='${Version}' lordos 2>/dev/null || true)
    [ -n "$v" ] && ok "LordOS $v terpasang"
fi

cards=0
for c in /sys/class/drm/card[0-9]; do [ -e "$c" ] && cards=$((cards+1)); done
[ "$cards" -gt 0 ] && ok "$cards DRM card" || bad "tidak ada DRM card"

[ -e /dev/dri/renderD128 ] && ok "render node ada" || warn "tidak ada /dev/dri/renderD128"

# Driver Apple terpasang?
if [ -e /sys/module/appledrm ] || grep -q "appledrm" /proc/modules 2>/dev/null; then
    ok "modul appledrm termuat"
else
    warn "appledrm tidak termuat — layar mungkin tetap jalan, tapi GPU tidak"
fi

if [ -e /usr/lib/aarch64-linux-gnu/dri/apple_dri.so ] \
   || [ -e /usr/lib/dri/apple_dri.so ] \
   || find /usr/lib -name apple_dri.so 2>/dev/null | head -1 | grep -q .; then
    ok "Mesa punya driver Apple (apple_dri.so)"
else
    bad "apple_dri.so tidak ada — Mesa tidak bisa memakai GPU Apple"
    fix "sudo apt install --reinstall libgl1-mesa-dri"
fi

# ---------------------------------------------------------------- 3. angka

hdr "3. Angka sesi"

frames=''
for f in $LOGS; do
    [ -r "$f" ] || continue
    l=$(grep -oE "[0-9.]+ *ms" "$f" 2>/dev/null | tail -1)
    [ -n "$l" ] && frames="$frames $l"
done
if [ -n "$frames" ]; then
    note "frame terakhir:$frames"
else
    note "log sesi belum memuat waktu frame"
fi

# Beban CPU sesi: animasi di CPU berarti core-nya penuh.
if command -v ps >/dev/null 2>&1; then
    line=$(ps -o %cpu=,comm= -C lord-server 2>/dev/null | head -1)
    if [ -n "$line" ]; then
        note "lord-server sekarang: %CPU = $(echo "$line" | awk '{print $1}')"
        c=$(echo "$line" | awk '{printf "%d", $1}')
        [ "$c" -ge 80 ] && bad "lord-server memakai ${c}% CPU — animasi di CPU" || ok "lord-server ${c}% CPU"
    fi
fi

# ---------------------------------------------------------------- ringkasan

hdr "Ringkasan"
printf '  %s%d lulus%s   %s%d peringatan%s   %s%d masalah%s\n\n' \
    "$GRN" "$PASS" "$OFF" "$YLW" "$WARN" "$OFF" "$RED" "$FAIL" "$OFF"

if [ "$FAIL" -eq 0 ]; then
    printf '%s%sTidak ada masalah wajib.%s\n\n' "$GRN" "$BLD" "$OFF"
else
    printf '%s%s%d masalah.%s Kalau bagian 1 bilang CPU composition, itu\n' "$RED" "$BLD" "$FAIL" "$OFF"
    printf 'penyebab lag-nya, dan tidak ada pengaturan yang bisa memperbaikinya.\n\n'
fi
