# Media di Debian Forky (video, kamera, mikrofon)

> **Ringkas:** LordOS butuh FFmpeg **7**. Debian Forky membawa FFmpeg **8**.
> Skrip `fix-forky.sh` membuang `lord-media` supaya LordOS bisa terpasang —
> itu mematikan fitur media. Dokumen ini menjelaskan cara mengembalikannya.

---

## Apa yang mati tanpa `lord-media`

`lord-media` adalah **1 dari 28** binary LordOS yang menautkan FFmpeg. Tanpa
binary itu:

| Fitur | Status |
|---|---|
| Desktop, aplikasi, browser, file manager | ✅ jalan |
| Pemutaran video | ❌ |
| Kamera (webcam) | ❌ |
| Mikrofon | ❌ |
| Audio biasa (musik, sistem) | ✅ jalan (PipeWire, tidak lewat lord-media) |

LordOS menanganinya dengan sopan — ada pesan `"The media helper (lord-media)
is not available"` di locale, jadi tidak crash.

---

## Cara mengembalikan media

Ada dua jalan. **Baca keduanya sebelum memilih.**

### Jalan A — FFmpeg 7 dari Trixie (cara yang dipakai `--with-media`)

Ini menambahkan Trixie sebagai sumber apt terbatas, hanya untuk lima library
FFmpeg 7.

```sh
# 1. tambahkan sumber Trixie
echo "deb http://deb.debian.org/debian trixie main" | sudo tee /etc/apt/sources.list.d/trixie-media.list

# 2. pin HANYA paket FFmpeg 7 ke Trixie; sisanya tetap Forky
sudo tee /etc/apt/preferences.d/trixie-media.pref >/dev/null <<'EOF'
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

sudo apt update
sudo apt install libavcodec61 libavformat61 libavutil59 libswscale8 libswresample5

# 3. pasang ulang lord-media (ambil dari paket asli, tanpa repack)
sudo curl -fL -o /tmp/lordos.deb \
  "https://github.com/lordbasex/LordOS/releases/download/v0.8.8.8-beta/lordos_0.8.8.8_arm64.deb"
cd /tmp && ar x lordos.deb && tar xf data.tar.xz ./usr/lib/lordos/bin/lord-media
sudo install -m 755 usr/lib/lordos/bin/lord-media /usr/lib/lordos/bin/lord-media
```

**Risiko yang sudah saya ukur di container `debian:forky` arm64:**

| Yang diperiksa | Hasil |
|---|---|
| `libc6` ikut turun versi? | **Tidak** — aman |
| Error dependensi? | **Tidak ada** |
| Paket turun versi | 3: `gcc-16-base`, `libstdc++6`, `libgcc-s1` |

Tiga paket itu turun dari `16.2.0-4` ke `16.2.0-3`. Itu **toolchain compiler**,
bukan library runtime yang dipakai LordOS. Risikonya rendah, tapi bukan nol.

> **Peringatan:** mencampur dua rilis Debian bukan cara yang bersih. Setiap
> `apt upgrade` berpotensi menarik Trixie lagi. Kalau sistem jadi aneh,
> hapus `/etc/apt/sources.list.d/trixie-media.list` dan
> `/etc/apt/preferences.d/trixie-media.pref`, lalu `apt install --reinstall`
> paket FFmpeg.

### Jalan B — Tunggu LordOS rilis untuk FFmpeg 8 (bersih, tanpa campur)

Itu di luar kendali kita. Butuh maintainer LordOS mengompilasi ulang terhadap
FFmpeg 8 (`libavcodec63`). Kalau itu terjadi, `lord-media` bisa dipasang normal
dan tidak ada pencampuran rilis.

---

## Cara memeriksa apakah media sudah jalan

```sh
sh scripts/doctor.sh
```

Lihat bagian **4. Media**. Yang benar:

```
  ✓ lord-media ADA
  ✓ library media lengkap
```

Kalau tertulis "lord-media TIDAK ADA", media belum aktif.

---

## Catatan teknis: kenapa soname berbeda

| | Paket | Versi FFmpeg |
|---|---|---|
| LordOS butuh | `libavcodec61` | 7 |
| Debian Trixie | `libavcodec61` | 7 |
| Debian Forky | `libavcodec63` | 8 |

Soname ikut versi mayor FFmpeg. Karena LordOS dikompilasi terhadap 7, ia tidak
mau memuat 8 — dan sebaliknya. Tidak ada cara "memaksa" selain menyediakan
FFmpeg 7 berdampingan.
