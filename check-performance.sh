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

# Sesi user dijalankan lord-sessiond sebagai `lord-server --headless` (sessiond.c:10),
# jadi lordlog_session_start() dipanggil dan log sesi seharusnya ada. Path-nya
# ditentukan lordlog_dir(): /var/log/lordos/users/<user> bila LORDOS_SESSIOND=1
# dan home-nya cocok, selain itu ~/.cache/lordos (lordlog.c:117-130).
#
# Kalau tidak ada yang terbaca, itu sendiri informasi: script ini melaporkan
# apa yang dilihatnya, bukan menebak path lain.
LOGS="/var/log/lordos/users/*/compositor.log"
[ -n "${HOME:-}" ] && LOGS="$LOGS $HOME/.cache/lordos/compositor.log"

line=''
seen=''
for f in $LOGS; do
    [ -e "$f" ] || continue
    seen="$seen $f"
    [ -r "$f" ] || { seen="$seen(UNREADABLE)"; continue; }
    l=$(grep -h "gpu: " "$f" 2>/dev/null | tail -1)
    [ -n "$l" ] && line="$l" && log_f="$f"
done
# journalctl bisa menggantung (atau tidak ada sama sekali di luar Debian).
# `timeout` tidak ada di macOS, jadi dibungkus sendiri: perintah dijalankan di
# latar, diberi batas waktu, lalu dimatikan. Tanpa ini skrip menggantung
# selamanya di mesin tanpa systemd — dan test-nya ikut menggantung.
within() {                      # within <detik> <perintah...>
    _secs=$1; shift
    ( "$@" ) </dev/null 2>/dev/null &
    _p=$!
    ( sleep "$_secs"; kill -TERM "$_p" 2>/dev/null ) >/dev/null 2>&1 &
    _k=$!
    wait "$_p" 2>/dev/null
    _rc=$?
    kill -TERM "$_k" 2>/dev/null
    return "$_rc"
}

# fallback: journal, seperti yang dipakai doctor.sh. NO_JOURNAL=1 melewatinya
# (dipakai test, dan berguna kalau journal di mesin ini lambat).
if [ -z "$line" ] && [ "${NO_JOURNAL:-0}" != 1 ] && command -v journalctl >/dev/null 2>&1; then
    l=$(within 5 journalctl -b -u lordos.service --no-pager | grep "gpu: " | tail -1)
    [ -n "$l" ] && line="$l" && log_f="journalctl -u lordos.service"
fi

# --log FILE: pakai log yang diberikan, untuk sesi yang tidak bisa dibaca script ini.
[ -n "${LOG_FILE:-}" ] && [ -r "$LOG_FILE" ] && line=$(grep -h "gpu: " "$LOG_FILE" | tail -1) && log_f="$LOG_FILE"

# Baris-baris dari gpu.c. Yang sukses menyebut renderer-nya, yang gagal
# menyebut alasannya — jadi alasannya dibaca, bukan disimpulkan:
#   gpu: GPU composition (llvmpipe …, EGL 1.5, dmabuf …, render …, display …)
#   gpu: the renderer is software (llvmpipe …): CPU composition
#   gpu: no GBM on the card, CPU composition
#   gpu: off (LORD_GPU=0), CPU composition
# "GPU composition (llvmpipe …)" MASIH jalur GPU — hanya renderer software.
case "$line" in
    "")
        warn "tidak ada baris gpu: yang bisa dibaca"
        if [ -n "$seen" ]; then
            note "log ditemukan:$seen — tapi tidak bisa dibaca atau kosong"
            note "Kalau '(UNREADABLE)': jalankan sebagai root: sudo sh $0"
        else
            note "tidak ada compositor.log di:"
            note "  /var/log/lordos/users/*/compositor.log"
            note "  $HOME/.cache/lordos/compositor.log"
            note "Sesi user memang --headless (sessiond.c:10), jadi lordlog_session_start()"
            note "dipanggil dan log seharusnya dibuat. Kalau tidak ada, sesi ditutup bersih"
            note "atau logrotate baru memutarnya."
        fi
        fix "jalankan ulang setelah login ke sesi LordOS: sudo sh $0"
        fix "atau beri log-nya langsung: LOG_FILE=/path/compositor.log sh $0" ;;
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
        c=$(echo "$line" | awk '{printf "%d", $1}')
        if [ "$c" -ge 80 ]; then
            bad "lord-server ${c}% CPU — animasi di CPU"
        else
            ok "lord-server ${c}% CPU (jauh dari jenuh: bukan CPU yang menjadi leher)"
        fi
    fi
fi

# ---------------------------------------------------------------- 4. knob

hdr "4. Yang bisa dicoba (terukur, bukan dugaan)"

# docs/GPU.md:281, Raspberry Pi 5 dengan V3D: GPU drag ON memberi 25.8–27.5 fps
# di bawah beban, OFF memberi 59.8–60.0 fps — dua kali lipat, karena upload
# tekstur drag dijalankan di CPU oleh V3D. Apple AGX belum diukur di dokumen
# itu, jadi ini percobaan yang pantas dicoba, bukan jaminan.
note "LORD_GPU_DRAG=0 mematikan drag window lewat GPU; jendela digambar CPU."
note "Di Pi 5 (V3D) itu menaikkan 25.8–27.5 -> 59.8–60.0 fps di bawah beban."
note "Untuk AGX Apple ini BELUM diukur: coba, lalu bandingkan sendiri."
say ""
say "    sudo systemctl edit lordos.service     # tambahkan Environment="
say "    # lalu, di bagian [Service]:"
say "    #   Environment=LORD_GPU_DRAG=0"
say "    sudo systemctl daemon-reload && systemctl restart lordos.service"
say ""
note "Kembalikan dengan menghapus baris itu dan restart lagi."

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
