# Performance on Apple Silicon

Read this before changing anything. Every number below was measured on a
MacBook Air M1 (16 GB, 2560×1600 panel, kernel `7.1.13+deb14.2-asahi`), not
copied from a document.

Start with the measurement, not with a guess:

```sh
sh scripts/check-performance.sh
```

---

## What the compositor reports, and what it means

LordOS draws to the screen through one of two paths. The session log says which
one, in a line that starts with `gpu: `:

| Line | Meaning |
|---|---|
| `gpu: GPU composition (Apple M1 …, EGL 1.5, dmabuf …)` | the fast path |
| `gpu: GPU composition (llvmpipe …)` | still the GPU path, but a software renderer |
| `gpu: CPU composition` | LordOS's own CPU path; the reason follows on the same line |

The reason on a CPU line is specific, and each needs a different fix:
`LORD_GPU=0` in the environment, `no GBM on the card`, `EGL did not start`,
`no 3D acceleration`, `shaders`.

Where the log lives:

```sh
/var/log/lordos/users/$USER/compositor.log        # needs root
~/.cache/lordos/compositor.log                    # without lord-sessiond
/var/log/lordos/users/$USER/compositor.log.prev   # the previous session
```

---

## The one measurement that matters: display scale

Two Desktop-impact runs on the same machine, same session, only the scale
differing:

| | scale 100% | scale 200% |
|---|---|---|
| `desk.fps` | **54.7** | 45.5 |
| `desk.missed` | **3.8%** | 25.4% |
| `paintMs` p50 (alone) | 1.44 ms | 6.36 ms |
| `renderMs` p50 (alone) | 1.89 ms | 7.45 ms |
| `uploadMpx` per frame | 0.95 | 3.31 |
| `gpuMs` p50 | 1.54 ms | 1.85 ms |

`gpuMs` barely moved. Everything that grew is CPU-side pixel work: 3.5× the
pixels per frame, 4.4× the paint time, and a quarter of frames late.

On a 2560×1600 panel, **150%** is a reasonable middle: 2.25× the pixels of 100%,
and text large enough to read comfortably. 200% is where frames start missing.

---

## The other cause, which is not the compositor

One measured session had pointer events held for **20–40 ms** (488 batches),
with 31 batches over 100 ms. The compositor was not the problem:

```
77.0 %CPU  firefox-esr        00:09:46 CPU time
24.9 %CPU  Isolated Web Co
 3.0 %CPU  lord-server
```

`PSI cpu: some avg10=5.52` — processes waiting for CPU — while `PSI io` was 0.
The input thread was waiting because a browser had the cores.

Before blaming the compositor, look at `top`. A browser with many tabs, or one
software-decoding video, will make any compositor feel slow.

---

## Knobs that exist, and when they help

| Variable | Effect | When |
|---|---|---|
| `LORD_GPU_DRAG=0` | the dragged window is composed by the CPU | Off by default nowhere; on the Pi 5 it doubled fps under load. **Not useful here**: the GPU drag path already takes 0 of 566 frames on this machine |
| `LORD_PIPELINE=1` | builds the next frame while a flip is pending | Frames heavier than 60% of the period. Costs latency: 17 ms alone, 29 ms under load (measured on the Pi 5). Wrong direction if input feels laggy |
| `LORD_GPU_SCISSOR=1` | buffer-age scissor, when `EGL_EXT_buffer_age` exists | Small redraws |
| `LORD_GPU_VERIFY=1` | compares GPU drag frames against the CPU's | Checking correctness, not speed |

Set them for the session with:

```sh
sudo systemctl edit lordos.service
# under [Service]:
#   Environment=LORD_PIPELINE=1
sudo systemctl daemon-reload && systemctl restart lordos.service
```

Remove the line and restart to undo.

---

## Reduce motion is a real fix, not a workaround

If animation is what bothers you, turn it off: **Settings → Accessibility →
Reduce motion**. The desktop stops animating entirely, which removes the whole
cost described above. For a machine used for reading and writing, that is a
legitimate choice, and it costs nothing in correctness.

---

## Recording a measurement worth comparing

`lordos-sysreport bench --quick` measures the compositor and the interface
workloads (~40 s). The **Desktop impact** test — the one that produces the
numbers in the table above — runs from **System Information → Performance**, or
its own button there. Results are saved to
`~/.local/state/lordos/lordbench-desktop.json`; the previous run is kept beside
it as `lordbench-desktop-prev.json`, so a before/after comparison needs no notes.
