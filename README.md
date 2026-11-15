# LordOS on Apple Silicon

**[Bahasa Indonesia →](README.id.md)**

Run LordOS on a MacBook Air/Pro M1 or M2, next to macOS. Two commands, about
30–45 minutes, and macOS is never touched.

> **Status: experimental.** Built and tested for one machine: MacBook Air M1.
> Nothing here partitions a disk — the Asahi installer does that, and it only
> uses free space.

---

## What this repository does

LordOS is a Linux desktop environment with its own Wayland compositor, written
in C. This repository puts it on a Mac that already runs Debian:

```
macOS                    untouched
 └── Debian              installed by the Asahi/Bananas installer  (step 1)
      └── LordOS         installed by this repository             (step 2)
```

The Asahi project does the hard part — the kernel, the firmware, the drivers.
This repository adds what is missing for LordOS on top of it: it accepts the
Debian release Apple Silicon actually runs, repacks the LordOS package where
Debian's FFmpeg version differs, and installs the fonts and audio packages the
desktop needs.

---

## Before you start

| | |
|---|---|
| **Mac** | MacBook Air/Pro M1 or M2. M3/M4 are not supported by the Asahi installer |
| **macOS** | 13.5 or newer |
| **Free space** | 25 GB or more (→ About This Mac → Storage) |
| **Time** | 30–45 minutes |
| **Network** | Wi-Fi or Ethernet works under Debian |

Not sure whether your Mac is supported? The Asahi installer says so before it
writes anything.

---

## Step 1 — Install Debian, with the Asahi/Bananas installer

**This step runs on macOS.** Open **Terminal**:

```sh
curl -L https://bananas-archive.debian.net/install | sh
```

The installer asks three things:

| Question | Answer |
|---|---|
| How much space for Linux? | **25 GB** or more |
| Which OS? | **`Debian GNU/Linux Testing minimal (console)`** |
| Boot entry name? | anything, for example `LordOS` |

> **Choose "minimal (console)"**, not GNOME or KDE. LordOS brings its own
> desktop, and a second one in the same Debian gets in the way.

> **The installer does not erase macOS.** It only uses free space. It shrinks
> nothing and moves nothing; if it cannot fit, it stops.

When it finishes, shut the Mac down. Start it again **holding the power button**
until you see the boot menu, choose the Debian entry, and finish Debian's own
setup (language, user, password).

**If the installer offers no "Testing" entry**, its menu changes from week to
week and the image to pick may be named differently. Any *minimal (console)*
Bananas image on **forky** or **sid** works; see
[`docs/TRIXIE.md`](docs/TRIXIE.md) for the Trixie image and why it is not the
recommended one.

---

## Step 2 — Connect and install, in one command

Log in on the Debian text console. There is no desktop yet — that is expected.

Connect to Wi-Fi first:

```sh
nmtui          # Activate a connection → your network → password
ping -c 2 deb.debian.org
```

Then run the installer:

```sh
curl -fsSL -o install.sh https://raw.githubusercontent.com/vidokun/lordos-m1/main/install.sh
less install.sh          # read it first; it is 3 screens
sudo sh install.sh
```

It runs four steps and stops at the first one that fails:

| Step | What it does |
|---|---|
| **1. Preflight** | machine, kernel, display, `speakersafetyd` — reads only |
| **2. Install** | `asahi-platform`, then the LordOS package (repacked on forky) |
| **3. Media** | optional; video, camera, microphone (see below) |
| **4. Verify** | services, display, icons, audio |

Useful options: `--dry-run` shows every command without running any;
`--with-media` enables video/camera/microphone; `--help` for the rest.

When it is done:

```sh
sudo reboot
```

You should reach the **LordOS login screen**.

---

## Step 3 — After logging in

### Icons look empty or like boxes

Some LordOS icons are not images: they are **text glyphs** from the system
fonts. Bluetooth is `ᛒ`, Printers `⎙`, Clipboard `⎘` — all three live only in
`fonts-noto-core`. Without that font they draw as empty boxes.

```sh
sh scripts/check-icons.sh                 # which glyph has no font; reads only
sudo sh scripts/check-icons.sh --install   # install what is missing
```

Log out and back in afterwards: the session reads fonts at startup.

### Video, camera and microphone do not work

Expected on Debian forky. LordOS is built against **FFmpeg 7**; forky ships
**FFmpeg 8**, so the media helper cannot load. Everything else — desktop,
browser, files, ordinary audio — works without it.

```sh
sh scripts/enable-media.sh            # check only, changes nothing
sudo sh scripts/enable-media.sh --apply
```

**This mixes Debian releases**: it installs FFmpeg 7 from trixie, pinned to
five packages, and reuses the `lord-media` binary from the package already
installed. The measured risk is in [`docs/MEDIA.md`](docs/MEDIA.md) — three
toolchain packages step down a version, `libc6` does not.

### The desktop moves slowly

Measure before changing anything:

```sh
sh scripts/check-performance.sh
```

It reports which composition path is in use. Two things are worth knowing
first, both measured on the reference M1:

- **Display scale costs pixels.** At 100% the desktop missed 3.8% of frames; at
  200% it missed 25.4%. On a 2560×1600 panel, 150% is a reasonable middle.
- **Another program can be the cause.** Firefox at 77% CPU held input events for
  20–40 ms in one measured case. Look at `top` before blaming the compositor.

See [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md) for what the numbers mean.

---

## Everyday scripts

Run these from a clone, or fetch them with `curl -fsSL … | sh` (each prints what
it will do first; the checking ones change nothing).

| Script | Purpose |
|---|---|
| `install.sh` | The whole install, in four steps |
| `scripts/check.sh` | Is this machine ready? Reads only |
| `scripts/doctor.sh` | What is running, what is not, what to fix. Reads only |
| `scripts/enable-media.sh` | Video, camera, microphone (`--apply`, `--revert`) |
| `scripts/check-icons.sh` | Which icon glyphs have no font (`--install`) |
| `scripts/fix-icons.sh` | Install the GTK/Qt icon themes (Adwaita, hicolor) |
| `scripts/check-performance.sh` | Why animation is slow, with numbers |
| `scripts/add-sway-desktop.sh` | A second Wayland desktop (sway) with a dock and a top bar, next to LordOS |

`lib/` holds what `install.sh` calls; you do not need to run it by hand.
`tests/` holds the test suites: `sh tests/test.sh` runs them all.

---

## Want a Wayland desktop with a dock, without LordOS?

LordOS's Dock and menu bar are drawn by its own compositor's theme, so they cannot
be moved into another desktop, and `lord-server` takes the display directly (no
nested mode). The alternative is a second session that looks similar:

```sh
sh scripts/add-sway-desktop.sh              # check only
sudo sh scripts/add-sway-desktop.sh --apply
```

That installs **sway** (wlroots) with **waybar** on top, **nwg-dock** at the
bottom, **fuzzel** as the launcher on Super, and **dunst** for notifications. It
adds a *"Sway (LordOS-like)"* entry to the login screen and leaves LordOS
completely alone — you pick one at login.

It is not LordOS's Dock: that one is part of a different compositor. This is a
separate dock that looks similar and behaves the way a dock should.

Undo with `sh scripts/add-sway-desktop.sh --revert` (no root needed: they are
your own files).

---

## Troubleshooting

### `No /sys/class/drm/card*`, or the kernel has no `CONFIG_DRM_APPLE`

Debian was installed without the Asahi kernel. Reinstall using the Bananas
installer from step 1 — a stock Debian ISO will not work on Apple Silicon.

### `speakersafetyd` is not active

**Do not play audio before this is fixed** — the internal speakers can be
damaged.

```sh
sudo apt install asahi-platform
sudo systemctl enable --now speakersafetyd
sudo reboot
```

### The LordOS installer rejects this Debian

If you ran `https://lordos.org/install.sh` directly, it accepts Debian 13 only.
`install.sh` from this repository accepts forky and sid, which is what Apple
Silicon runs today.

### Black screen after logging in

Switch to a text console with `Ctrl+Alt+F2`, log in, then:

```sh
sudo lordos --uninstall
```

Debian is back to normal. Nothing is broken.

### Remove LordOS

```sh
curl -fsSL https://lordos.org/install.sh | sudo sh -s -- --uninstall
```

### Remove Linux and go back to macOS only

Follow Asahi's own removal guide (delete the three Linux partitions), or:

```sh
# from macOS
diskutil list                 # find the Linux partitions
diskutil eraseVolume free free disk0sN
```

---

## What you should know — plainly

1. **Debian Testing moves.** It updates constantly and occasionally breaks.
   Do not run `apt full-upgrade` without a reason.

2. **Debian deprecated Stable for Apple Silicon.** This is outside LordOS's
   control and outside this repository's. Until the Asahi kernel is in Debian
   proper, "Stable on a Mac" will keep having problems.

3. **Touch ID and external displays over USB-C do not work.** No Linux driver
   exists for M1.

4. **This repository was built for one machine.** Package metadata was checked
   (43 dependencies, glibc, sonames) and the scripts were tested, but the
   install has not been run on a wide range of M1/M2 hardware.

5. **The Trixie kernel image has been frozen since October 2026** and gets no
   security patches. If that matters to you, use Testing.

6. **GPU acceleration works**, but some optimisations are limited by design.
   The layer path used for window drag declines fractional scales; at 150% some
   drawing stays on the CPU. Turning animations down (Accessibility → Reduce
   motion) is a legitimate fix, not a workaround.

---

## Repository layout

```
install.sh          the entry point: preflight → install → verify
scripts/            what you run after installing (all read-only unless said)
lib/                internals install.sh calls; not for typing by hand
docs/               MEDIA.md, TRIXIE.md, PERFORMANCE.md
tests/              the test suites; `sh tests/test.sh` runs them all
```

---

## License

The scripts here: MIT. LordOS: MIT (© iPERFEX). Debian: its own licenses.
Asahi Linux is a separate project with its own contributors; this repository is
**not** endorsed by or affiliated with it.
