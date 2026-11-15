# LordOS di Mac Apple Silicon

**[English →](README.md)**

Jalankan LordOS di MacBook Air/Pro M1 atau M2, berdampingan dengan macOS. Dua
perintah, sekitar 30–45 menit, dan macOS tidak pernah disentuh.

> **Status: eksperimental.** Dibuat dan diuji untuk satu mesin: MacBook Air M1.
> Tidak ada yang mempartisi disk di sini — itu tugas installer Asahi, dan ia
> hanya memakai ruang kosong.

---

## Apa yang repo ini kerjakan

LordOS adalah desktop Linux dengan compositor Wayland-nya sendiri, ditulis
dalam C. Repo ini memasangnya di Mac yang sudah menjalankan Debian:

```
macOS                    tidak disentuh
 └── Debian              dipasang installer Asahi/Bananas   (langkah 1)
      └── LordOS         dipasang repo ini                  (langkah 2)
```

Bagian tersulit — kernel, firmware, driver — dikerjakan proyek Asahi. Repo ini
menambahkan yang belum ada untuk LordOS di atasnya: menerima rilis Debian yang
benar-benar dipakai Apple Silicon, me-repack paket LordOS ketika versi FFmpeg
Debian berbeda, dan memasang font serta paket audio yang dibutuhkan desktop.

---

## Sebelum mulai

| | |
|---|---|
| **Mac** | MacBook Air/Pro M1 atau M2. M3/M4 belum didukung installer Asahi |
| **macOS** | 13.5 atau lebih baru |
| **Ruang kosong** | 25 GB atau lebih (→ About This Mac → Storage) |
| **Waktu** | 30–45 menit |
| **Jaringan** | Wi-Fi atau LAN jalan di Debian |

Belum yakin Mac Anda didukung? Installer Asahi memberi tahu sebelum menulis
apa pun.

---

## Langkah 1 — Pasang Debian lewat installer Asahi/Bananas

**Langkah ini dijalankan di macOS.** Buka **Terminal**:

```sh
curl -L https://bananas-archive.debian.net/install | sh
```

Installer menanyakan tiga hal:

| Pertanyaan | Jawab |
|---|---|
| Berapa ruang untuk Linux? | **25 GB** atau lebih |
| OS apa? | **`Debian GNU/Linux Testing minimal (console)`** |
| Nama entri boot? | terserah, misalnya `LordOS` |

> **Pilih "minimal (console)"**, bukan GNOME atau KDE. LordOS membawa desktop
> sendiri, dan desktop kedua di Debian yang sama akan mengganggu.

> **Installer ini tidak menghapus macOS.** Ia hanya memakai ruang kosong. Tidak
> mengecilkan partisi, tidak memindahkan apa pun; kalau tidak cukup, ia berhenti.

Setelah selesai, matikan Mac. Nyalakan lagi dengan **menekan-tahan tombol power**
sampai menu boot muncul, pilih entri Debian, lalu selesaikan setup Debian
(bahasa, user, password).

**Kalau tidak ada entri "Testing"**, menu installer berubah dari minggu ke
minggu dan nama imagenya bisa berbeda. Image *minimal (console)* Bananas mana
pun di **forky** atau **sid** bisa dipakai; lihat [`docs/TRIXIE.md`](docs/TRIXIE.md)
untuk image Trixie dan alasan ia bukan pilihan yang disarankan.

---

## Langkah 2 — Sambungkan lalu pasang, satu perintah

Login di konsol teks Debian. Belum ada desktop — itu normal.

Sambungkan Wi-Fi dulu:

```sh
nmtui          # Activate a connection → jaringan Anda → password
ping -c 2 deb.debian.org
```

Lalu jalankan installer:

```sh
curl -fsSL -o install.sh https://raw.githubusercontent.com/vidokun/lordos-m1/main/install.sh
less install.sh          # baca dulu; 3 layar
sudo sh install.sh
```

Ia menjalankan empat langkah dan berhenti di langkah pertama yang gagal:

| Langkah | Isinya |
|---|---|
| **1. Preflight** | mesin, kernel, display, `speakersafetyd` — hanya membaca |
| **2. Install** | `asahi-platform`, lalu paket LordOS (di-repack di forky) |
| **3. Media** | opsional; video, kamera, mikrofon (lihat di bawah) |
| **4. Verify** | layanan, display, ikon, audio |

Opsi berguna: `--dry-run` menampilkan semua perintah tanpa menjalankannya;
`--with-media` mengaktifkan video/kamera/mikrofon; `--help` untuk sisanya.

Setelah selesai:

```sh
sudo reboot
```

Anda akan sampai di **layar login LordOS**.

---

## Langkah 3 — Setelah login

### Ikon kosong atau tampil sebagai kotak

Sebagian ikon LordOS bukan gambar, melainkan **glyph teks** dari font sistem.
Bluetooth `ᛒ`, Printers `⎙`, Clipboard `⎘` — ketiganya hanya ada di
`fonts-noto-core`. Tanpa font itu, yang muncul kotak kosong.

```sh
sh scripts/check-icons.sh                 # glyph mana yang tak punya font; hanya membaca
sudo sh scripts/check-icons.sh --install   # pasang yang kurang
```

Logout lalu login lagi: sesi membaca font saat mulai.

### Video, kamera dan mikrofon tidak jalan

Normal di Debian forky. LordOS dibangun terhadap **FFmpeg 7**; forky membawa
**FFmpeg 8**, jadi helper medianya tidak bisa dimuat. Sisanya — desktop,
browser, file manager, audio biasa — tetap jalan.

```sh
sh scripts/enable-media.sh            # periksa saja, tidak mengubah apa pun
sudo sh scripts/enable-media.sh --apply
```

**Ini mencampur rilis Debian**: memasang FFmpeg 7 dari trixie, dipin ke lima
paket, lalu memakai biner `lord-media` dari paket yang sudah terpasang.
Risiko terukurnya ada di [`docs/MEDIA.md`](docs/MEDIA.md) — tiga paket
toolchain turun satu versi, `libc6` tidak.

### Desktop terasa lambat

Ukur dulu sebelum mengubah apa pun:

```sh
sh scripts/check-performance.sh
```

Ia melaporkan jalur komposisi mana yang dipakai. Dua hal yang perlu diketahui
lebih dulu, keduanya terukur di M1 referensi:

- **Skala tampilan memakan piksel.** Di 100% desktop melewatkan 3,8% frame; di
  200% melewatkan 25,4%. Pada panel 2560×1600, 150% adalah jalan tengah yang wajar.
- **Program lain bisa jadi penyebabnya.** Firefox pada 77% CPU menahan event
  input 20–40 ms dalam satu kasus terukur. Lihat `top` sebelum menyalahkan
  kompositor.

Arti angka-angka itu ada di [`docs/PERFORMANCE.md`](docs/PERFORMANCE.md).

---

## Script sehari-hari

Jalankan dari hasil clone, atau ambil lewat `curl -fsSL … | sh` (semua
menjelaskan dulu apa yang akan dilakukan; yang berjenis pemeriksa tidak
mengubah apa pun).

| Script | Fungsi |
|---|---|
| `install.sh` | Seluruh pemasangan, dalam empat langkah |
| `scripts/check.sh` | Apakah mesin ini siap? Hanya membaca |
| `scripts/doctor.sh` | Apa yang jalan, apa yang tidak, apa yang harus diperbaiki |
| `scripts/enable-media.sh` | Video, kamera, mikrofon (`--apply`, `--revert`) |
| `scripts/check-icons.sh` | Glyph ikon mana yang tidak punya font (`--install`) |
| `scripts/fix-icons.sh` | Pasang tema ikon GTK/Qt (Adwaita, hicolor) |
| `scripts/check-performance.sh` | Kenapa animasi lambat, dengan angka |
| `scripts/add-sway-desktop.sh` | Desktop Wayland kedua (sway) dengan dock dan bar atas, di samping LordOS |

`lib/` berisi yang dipanggil `install.sh`; tidak perlu dijalankan sendiri.
`tests/` berisi suite uji: `sh tests/test.sh` menjalankan semuanya.

---

## Ingin desktop Wayland dengan dock, tanpa LordOS?

Dock dan menu bar LordOS digambar oleh tema kompositor LordOS sendiri, jadi
tidak bisa dipindahkan ke desktop lain, dan `lord-server` mengambil display
langsung (tidak ada mode nested). Alternatifnya sesi kedua yang mirip:

```sh
sh scripts/add-sway-desktop.sh              # periksa saja
sudo sh scripts/add-sway-desktop.sh --apply
```

Itu memasang **sway** (wlroots) dengan **waybar** di atas, **nwg-dock** di
bawah, **fuzzel** sebagai launcher pada tombol Super, dan **dunst** untuk
notifikasi. Ia menambah entri *"Sway (LordOS-like)"* di layar login dan tidak
mengganggu LordOS — Anda pilih salah satu saat login.

Ini bukan Dock LordOS: yang itu bagian dari kompositor lain. Ini dock terpisah
yang tampil mirip dan berperilaku sebagaimana dock seharusnya.

Batalkan dengan `sh scripts/add-sway-desktop.sh --revert` (tidak perlu root:
itu file Anda sendiri).

---

## Kalau ada masalah

### Tidak ada `/sys/class/drm/card*`, atau kernel tanpa `CONFIG_DRM_APPLE`

Debian terpasang tanpa kernel Asahi. Pasang ulang memakai installer Bananas dari
langkah 1 — ISO Debian biasa tidak akan jalan di Apple Silicon.

### `speakersafetyd` tidak aktif

**Jangan nyalakan suara sebelum ini beres** — speaker internal bisa rusak.

```sh
sudo apt install asahi-platform
sudo systemctl enable --now speakersafetyd
sudo reboot
```

### Installer LordOS menolak Debian ini

Kalau Anda menjalankan `https://lordos.org/install.sh` langsung, ia hanya
menerima Debian 13. `install.sh` dari repo ini menerima forky dan sid, yaitu
yang dipakai Apple Silicon hari ini.

### Layar hitam setelah login

Pindah ke konsol teks dengan `Ctrl+Alt+F2`, login, lalu:

```sh
sudo lordos --uninstall
```

Debian kembali normal. Tidak ada yang rusak.

### Menghapus LordOS

```sh
curl -fsSL https://lordos.org/install.sh | sudo sh -s -- --uninstall
```

### Menghapus Linux dan kembali ke macOS saja

Ikuti panduan penghapusan resmi Asahi (hapus tiga partisi Linux), atau:

```sh
# dari macOS
diskutil list                 # cari partisi Linux
diskutil eraseVolume free free disk0sN
```

---

## Yang perlu Anda tahu — terus terang

1. **Debian Testing bergerak.** Ia terus diperbarui dan sesekali ada yang rusak.
   Jangan `apt full-upgrade` tanpa alasan.

2. **Debian mendeprecate Stable untuk Apple Silicon.** Ini di luar kendali
   LordOS maupun repo ini. Selama kernel Asahi belum masuk Debian resmi,
   "Stable di Mac" akan terus bermasalah.

3. **Touch ID dan monitor eksternal via USB-C tidak berfungsi.** Belum ada
   driver Linux untuk M1.

4. **Repo ini dibuat untuk satu mesin.** Metadata paket sudah diperiksa (43
   dependensi, glibc, soname) dan script-nya diuji, tapi pemasangannya belum
   dicoba di banyak perangkat M1/M2.

5. **Image kernel Trixie beku sejak Oktober 2026** dan tidak dapat patch
   keamanan. Kalau itu penting bagi Anda, gunakan Testing.

6. **Akselerasi GPU jalan**, tapi beberapa optimasi dibatasi secara desain.
   Jalur layer untuk menggeser jendela menolak skala pecahan; di 150% sebagian
   penggambaran tetap di CPU. Menurunkan animasi (Accessibility → Reduce
   motion) adalah solusi sah, bukan akal-akalan.

---

## Struktur repo

```
install.sh          titik masuk: preflight → install → verify
scripts/            yang Anda jalankan setelah memasang (hanya membaca, kecuali disebut)
lib/                internal yang dipanggil install.sh; bukan untuk diketik manual
docs/               MEDIA.md, TRIXIE.md, PERFORMANCE.md
tests/              suite uji; `sh tests/test.sh` menjalankan semuanya
```

---

## Lisensi

Script di sini: MIT. LordOS: MIT (© iPERFEX). Debian: lisensi masing-masing.
Asahi Linux adalah proyek terpisah dengan kontributornya sendiri; repo ini
**tidak** didukung atau berafiliasi dengannya.
