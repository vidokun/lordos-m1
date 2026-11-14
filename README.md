# LordOS di Mac Apple Silicon

Pasang **LordOS** di MacBook Air/Pro M1 atau M2 Anda, berdampingan dengan macOS.

> **Status: eksperimental.** Dibuat untuk satu mesin (MacBook Air M1). Tidak ada
> jaminan. Tapi semua langkah di sini sudah diperiksa dan tidak ada yang bisa
> merusak macOS Anda.

---

## Apa yang Anda dapat

LordOS adalah desktop environment Linux (compositor Wayland sendiri, ditulis dalam C).
Repo ini memasangnya di atas Debian yang sudah berjalan di Mac Anda.

```
macOS  (tidak disentuh)
  └── Debian (dipasang oleh installer Asahi/Bananas)
        └── LordOS (dipasang oleh repo ini)
```

---

## Sebelum mulai

Anda perlu:

| | |
|---|---|
| **Mac** | MacBook Air/Pro M1 atau M2 (M3/M4 belum didukung) |
| **macOS** | 13.5 atau lebih baru |
| **Ruang** | ~25 GB kosong |
| **Waktu** | 30–45 menit |

Cek ruang: ** → About This Mac → Storage**.

---

## Langkah 1 — Pasang Debian (lewat installer Asahi/Bananas)

Ini dilakukan **di macOS**, bukan di Linux.

Buka **Terminal**, lalu:

```sh
curl -L https://bananas-archive.debian.net/install | sh
```

Saat installer bertanya:

| Pertanyaan | Jawab |
|---|---|
| Berapa ruang untuk Linux? | **25 GB** atau lebih |
| OS apa? | **`Debian GNU/Linux Testing minimal (console)`** |
| Nama entri boot? | terserah, misal `LordOS` |

> ⚠️ **Pilih "minimal (console)"**, jangan GNOME atau KDE. LordOS membawa desktop
> sendiri, dan GNOME/KDE akan bentrok.

> ℹ️ Installer ini **tidak menghapus macOS**. Ia hanya memakai ruang kosong.

Setelah selesai, matikan mesin. Nyalakan dengan **tekan-tahan tombol power**,
pilih entri Debian, lalu ikuti setup Debian (bahasa, user, password).

---

## Langkah 2 — Sambungkan internet

Setelah Debian menyala, Anda akan melihat **layar teks hitam dengan prompt login**.
Ini normal — belum ada desktop.

Login, lalu sambungkan Wi-Fi:

```sh
nmtui
```

Pilih **Activate a connection** → pilih Wi-Fi → masukkan password.

Tes:

```sh
ping -c 2 deb.debian.org
```

---

## Langkah 3 — Jalankan pemeriksa

```sh
curl -fsSL https://raw.githubusercontent.com/vidokun/lordos-m1/main/check.sh | sh
```

Skrip ini **hanya membaca** — tidak memasang atau mengubah apa pun.

Ia akan menampilkan daftar centang. Baca bagian **Hasil** di bawah:

| Hasil | Artinya |
|---|---|
| `AMAN` | Lanjut ke Langkah 4 |
| `BOLEH LANJUT, dengan N peringatan` | Lanjut, tapi baca peringatannya |
| `JANGAN LANJUT` | Ada yang harus diperbaiki — lihat tanda ✗ |

---

## Langkah 4 — Pasang LordOS

```sh
curl -fsSL https://raw.githubusercontent.com/vidokun/lordos-m1/main/setup.sh | sudo sh
```

Atau, kalau ingin melihat isinya dulu (disarankan):

```sh
curl -fsSL -o setup.sh https://raw.githubusercontent.com/vidokun/lordos-m1/main/setup.sh
less setup.sh          # baca dulu
sudo sh setup.sh
```

Skrip ini akan:
1. Memeriksa mesin Anda Apple Silicon dan kernelnya benar
2. Memasang `asahi-platform` (pelindung speaker — **wajib**)
3. Memasang LordOS

---

## Langkah 5 — Reboot

```sh
sudo reboot
```

Anda akan melihat **layar login LordOS**.

---

## Kalau ada masalah

### "Tidak ada /sys/class/drm/card*"

Kernel Anda bukan kernel Asahi. Debian dipasang tanpa kernel yang benar.

**Perbaikan:** pastikan Anda memakai installer Bananas (Langkah 1), bukan ISO
Debian biasa.

### "Kernel tidak punya CONFIG_DRM_APPLE"

Sama seperti di atas. Tanpa driver ini layar akan tetap hitam.

### `speakersafetyd` tidak aktif

**Jangan nyalakan suara** sebelum ini beres — speaker bisa rusak.

```sh
sudo apt install asahi-platform
sudo systemctl enable --now speakersafetyd
sudo reboot
```

### Installer LordOS menolak Debian Anda

Kalau Anda memakai `curl https://lordos.org/install.sh` langsung (bukan
`setup.sh` dari repo ini), ia hanya menerima Debian 13. `setup.sh` di repo ini
membawa installer yang sudah dipatch agar menerima Debian Testing (forky).

### Layar hitam setelah login

Boot ke TTY dengan `Ctrl+Alt+F2`, login, lalu:

```sh
sudo lordos --uninstall
```

Debian Anda kembali normal. Tidak ada yang rusak.

### Ingin menghapus LordOS

```sh
curl -fsSL https://lordos.org/install.sh | sudo sh -s -- --uninstall
```

### Ingin menghapus Linux dan kembali ke macOS saja

Ikuti panduan resmi Asahi (hapus 3 partisi Linux), atau:

```sh
# dari macOS
diskutil list              # cari partisi Linux
diskutil eraseVolume free free disk0sN
```

---

## Yang perlu Anda tahu — jujur

1. **Debian Testing bergerak.** Ia terus diperbarui. Sesekali ada yang rusak.
   Jangan `apt full-upgrade` tanpa alasan.

2. **Tim Debian mendeprecate Debian Stable untuk Apple Silicon.** Ini di luar
   kendali LordOS maupun repo ini. Selama kernel Asahi belum masuk kernel Debian
   resmi, "Stable di Mac" akan terus bermasalah.

3. **Touch ID dan monitor eksternal via USB-C tidak berfungsi.** Belum didukung
   driver Linux untuk M1.

4. **Belum diuji di mesin ini oleh siapa pun.** Metadata paket sudah diperiksa
   (43 dependensi, glibc, soname), tapi belum ada yang menjalankan LordOS di Mac
   M1 dan melaporkannya.

5. **Kernel dari image Trixie beku sejak Oktober 2026** dan tidak dapat patch
   keamanan. Kalau ini penting bagi Anda, gunakan Testing.

---

## Isi repo

| File | Fungsi |
|---|---|
| `check.sh` | Pemeriksa kesiapan. Hanya membaca. |
| `setup.sh` | Pemasang satu-perintah (paket Asahi + LordOS). |
| `install.sh` | Installer LordOS yang sudah dipatch (forky/sid). |
| `test.sh` | Test untuk `check.sh`. |
| `installer_data_trixie.json` | Untuk yang ingin Debian 13 (Trixie). Lihat di bawah. |

---

## Ingin Debian 13 (Trixie)?

Image Trixie masih ada di server Bananas tapi tidak muncul di menu installer.
Lihat [`TRIXIE.md`](TRIXIE.md) untuk caranya — dan baca dulu peringatan
keamanannya.

---

## Lisensi

Skrip di repo ini: MIT.
LordOS: MIT (© iPERFEX). Debian: lisensi masing-masing.
