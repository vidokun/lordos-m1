#!/bin/sh
# test-check-performance.sh — the composition-line reading of check-performance.sh.
#
# The reading is the whole value of that script: "GPU composition (llvmpipe …)"
# is still the GPU path, while "CPU composition" never is, and each CPU reason
# needs a different fix. These cases feed it log fixtures and assert it says the
# right thing, without Debian, root or a GPU.
set -u
S="${1:-$(dirname -- "$0")/check-performance.sh}"
[ -f "$S" ] || { echo "test-check-performance: no script at $S" >&2; exit 1; }

fails=0
checks=0

# A fixture home whose ~/.cache/lordos/compositor.log holds one line.
with_line() {
    h=$(mktemp -d) || exit 1
    mkdir -p "$h/.cache/lordos"
    printf 'started\n%s\n' "$1" > "$h/.cache/lordos/compositor.log"
    printf '%s' "$h"
}

section1() {
    HOME="$1" sh "$S" 2>&1 | sed -n '/1\. Jalur komposisi/,/^2\. Perangkat GPU/p'
}

check() {   # check <label> <output> <required> [forbidden]
    checks=$((checks + 1))
    case "$2" in
        *"$3"*) ;;
        *) fails=$((fails + 1)); printf 'FAILED: %s (wanted %s)\n  got: %s\n' "$1" "$3" "$2"; return ;;
    esac
    if [ "${4:-}" ]; then
        case "$2" in
            *"$4"*) fails=$((fails + 1)); printf 'FAILED: %s (must not contain %s)\n  got: %s\n' "$1" "$4" "$2" ;;
        esac
    fi
}

# --- hardware GPU: the fast path ---------------------------------------------
h=$(with_line 'gpu: GPU composition (Apple M1 (G13G B0), EGL 1.5, dmabuf yes, render yes, display yes)')
o=$(section1 "$h"); rm -rf "$h"
check "hardware GPU is reported as the fast path" "$o" "renderer hardware"
check "hardware GPU is not called CPU"            "$o" "renderer hardware" "inilah lag-nya"

# --- GPU path but software renderer: the subtle case -------------------------
# This is NOT the CPU path; the wording must not send the user to fix the wrong thing.
h=$(with_line 'gpu: GPU composition (llvmpipe (LLVM 19, 256 bits), EGL 1.5, dmabuf imported, render yes, display yes)')
o=$(section1 "$h"); rm -rf "$h"
check "llvmpipe on the GPU path is still the GPU path" "$o" "GPU composition"
check "…but the software renderer is called out"      "$o" "renderer-nya software"
check "…and it is not reported as LordOS's CPU path"  "$o" "renderer-nya software" "inilah lag-nya"

# --- CPU paths, each with its own cause --------------------------------------
h=$(with_line 'gpu: off (LORD_GPU=0), CPU composition'); o=$(section1 "$h"); rm -rf "$h"
check "LORD_GPU=0 names the variable" "$o" "LORD_GPU=0"

h=$(with_line 'gpu: no GBM on the card, CPU composition'); o=$(section1 "$h"); rm -rf "$h"
check "missing GBM names GBM" "$o" "GBM"

h=$(with_line 'gpu: the renderer is software (llvmpipe (LLVM 19)): CPU composition (LORD_GPU=1 forces it)')
o=$(section1 "$h"); rm -rf "$h"
check "software renderer on the CPU path is explained" "$o" "renderer software untuk card ini"
check "…and is reported as the CPU path"               "$o" "inilah lag-nya"

h=$(with_line 'gpu: EGL did not start, CPU composition'); o=$(section1 "$h"); rm -rf "$h"
check "EGL failure is named" "$o" "EGL"

h=$(with_line 'gpu: the card (appledrm) has no 3D acceleration: CPU composition'); o=$(section1 "$h"); rm -rf "$h"
check "no-3D is named" "$o" "3D"

# --- nothing to read ---------------------------------------------------------
h=$(mktemp -d); o=$(section1 "$h"); rm -rf "$h"
check "no log says so instead of guessing" "$o" "belum bisa dibaca"
check "no log does not claim CPU"         "$o" "belum bisa dibaca" "inilah lag-nya"
check "no log does not claim GPU either"  "$o" "belum bisa dibaca" "renderer hardware"

printf '\n%d checks, %d failed\n' "$checks" "$fails"
[ "$fails" -eq 0 ]
