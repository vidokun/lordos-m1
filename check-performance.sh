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

LOGS="/var/log/lordos/users/*/compositor.log"
comp=''
for f in $LOGS; do
    [ -r "$f" ] || continue
    c=$(grep -oE "GPU composition|CPU composition|the renderer is software" "$f" 2>/dev/null | tail -1)
    [ -n "$c" ] && comp="$c" && log_f="$f"
done
# fallback: journal, seperti yang dipakai doctor.sh
if [ -z "$comp" ]; then
    comp=$(journalctl -b -u lordos.service --no-pager 2>/dev/null \
           | grep -oiE "GPU composition|CPU composition|the renderer is software" | tail -1)
    [ -n "$comp" ] && log_f="journalctl -u lordos.service"
fi

case "$comp" in
    "GPU composition"*)
        ok "GPU composition — animasi memakai GPU" ;;
    "CPU composition"*)
        bad "CPU composition — animasi digambar di CPU, ini penyebab lag"
        note "Penyebabnya renderer software (llvmpipe/softpipe): Mesa tidak membuka Apple GPU."
        fix "lihat bagian 2 dan 3 di bawah" ;;
    "the renderer is software"*)
        bad "renderer software (llvmpipe/softpipe) — kompositor jatuh ke CPU"
        fix "lihat bagian 2 dan 3 di bawah" ;;
    "")
        warn "belum bisa dibaca dari log"
        note "Log kompositor hanya ada setelah sesi LordOS pernah masuk."
        fix "grep -i 'composition\\|renderer' /var/log/lordos/users/*/compositor.log"
        fix "journalctl -b -u lordos.service | grep -i 'composition\\|renderer'" ;;
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
