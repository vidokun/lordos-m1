# Debian 13 (Trixie) di Mac Apple Silicon

> ## ⚠️ BACA DULU
>
> Tim Debian Bananas **mendeprecate `trixie-bananas` pada 2026-11-09**. Artinya:
>
> - **Tidak ada pembaruan keamanan lagi.** Kernel Anda akan beku di build 15 Oktober 2026.
> - Wiki Bananas menyebut **CVE-2026-98432** sebagai contoh kerentanan yang tidak
>   akan ditambal.
> - Image Trixie masih ada di server, tapi ini adalah arsip, bukan rilis hidup.
>
> Kalau Anda memilih Trixie, terimalah bahwa kernel Anda tidak akan diperbarui.
> Untuk pemakaian pribadi risikonya terkendali; untuk mesin berisi data penting,
> gunakan Testing.

Kalau Anda tetap ingin Trixie, ada dua cara.

---

## Cara A — Lewat menu installer (image tersembunyi)

Image Trixie tersedia di server tapi **tidak muncul** di menu installer, karena
`installer_data.json` di server hanya memuat entri Testing.

File `installer_data_trixie.json` di repo ini memuat kedua pilihan.

**Di macOS:**

```sh
cd ~/Downloads

# 1. unduh script installer resmi
curl -L -o install.sh https://bananas-archive.debian.net/install
chmod +x install.sh

# 2. unduh file data dari repo ini
curl -L -o installer_data_trixie.json \
  https://raw.githubusercontent.com/vidokun/lordos-m1/main/installer_data_trixie.json

# 3. jalankan dengan file data itu
sudo INSTALLER_DATA="$PWD/installer_data_trixie.json" ./install.sh
```

Menu akan menampilkan:

```
1) Debian GNU/Linux 13 (trixie) minimal (console) — frozen, see notes
2) Debian GNU/Linux Testing (forky) minimal (console) — maintained
```

Pilih **1**.

---

## Cara B — Pasang Testing dulu, lalu turunkan ke Trixie

> Ini **tidak disarankan**. Menurunkan rilis Debian di mesin hidup bisa
> meninggalkan paket dalam keadaan setengah jadi. Hanya lakukan kalau Anda paham
> `apt` dengan baik.

Kalau tetap mau:

```sh
# 1. ganti suite di sources
sudo sed -i 's/unstable-bananas/trixie-bananas/g' /etc/apt/sources.list.d/bananas.list
sudo sed -i 's/forky/trixie/g' /etc/apt/sources.list.d/debian.sources

# 2. turunkan
sudo apt update
sudo apt full-upgrade --allow-downgrades
```

Risiko: beberapa paket mungkin tidak punya versi Trixie dan akan tertinggal.

---

## Setelah Trixie terpasang

Langkah selanjutnya sama dengan README:

1. `sh scripts/check.sh` — periksa kesiapan
2. `sudo sh install.sh` — pasang LordOS

**Kabar baik:** installer LordOS di repo ini **sudah menerima Trixie tanpa patch
tambahan** (Trixie adalah target asli LordOS). Jadi di Trixie Anda bahkan tidak
perlu perbaikan versi.

---

## Catatan teknis

Image Trixie yang dipakai:

```
debian-asahi-trixie-console@261015101957-33576de.zip   440 MB
```

Struktur partisinya **identik** dengan image Testing:

| | Trixie | Testing |
|---|---|---|
| `boot.img` | 1.610.612.736 B | 1.610.612.736 B |
| `root.img` | 3.688.890.368 B | 3.688.890.368 B |

Karena itu template partisi dari entri Testing dipakai ulang di
`installer_data_trixie.json` — ukurannya byte-per-byte sama.

---

## Ringkasan risiko

| | Trixie | Testing |
|---|---|---|
| Interface LordOS cocok | ✅ target asli | ⚠️ belum diuji |
| Driver display Apple | ✅ ada | ✅ ada |
| Pembaruan keamanan | ❌ tidak ada | ✅ ada |
| Kernel | beku Okt 2026 | diperbarui |
| Suite Bananas | deprecated | aktif |
| Skrip installer perlu patch? | tidak | ya (sudah dibawa repo ini) |
