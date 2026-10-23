# Build PulseView Windows dengan patch driver OLS

Tujuan: installer PulseView Windows yang memakai
`host/sigrok/libsigrok-ols-rx-robust.patch`, agar **Run berulang** di board S9
(mode OLS) langsung bekerja tanpa Connect ulang.

Build Windows PulseView resmi dibuat dengan cross-compile dari Linux (MXE +
`sigrok-util/cross-compile/mingw`), dan libsigrok di-link statis. Jadi DLL tidak bisa
diganti, dan PulseView harus di-build ulang. Di laptop Windows, pakai **WSL Ubuntu**.

Perkiraan: disk kosong ±20 GB, waktu 1–3 jam (paling lama di langkah MXE, cukup sekali).

## 0. Siapkan WSL

PowerShell (admin):

```powershell
wsl --install -d Ubuntu-22.04
```

Buka terminal Ubuntu. **Kerjakan semuanya di home Linux (`~`), jangan di `/mnt/c/...`**
(akses file Windows dari WSL sangat lambat untuk build).

### Alternatif: Ubuntu 22.04 di VMware

Bisa dipakai sebagai pengganti WSL (langkah 0 dilewati). Atur VM dulu:

* **CPU** 4 core atau lebih, **RAM** 8 GB atau lebih (Qt5 dan Boost butuh memori).
* **Disk kosong** ±25 GB di dalam VM. Cek dengan `df -h ~`. Kalau kurang, perbesar
  virtual disk lewat *VM Settings → Hard Disk → Expand*, lalu perbesar partisinya dengan
  `gparted`.
* Build di home VM (`~`), **jangan** di shared folder `/mnt/hgfs/...` (lambat, dan
  symlink/permission bisa gagal).

Menyalin file antara Windows dan VM, pilih salah satu:

* **Shared folder**: *VM Settings → Options → Shared Folders*, lalu aktifkan folder repo.
  Di VM file muncul di `/mnt/hgfs/<nama_share>/`. Kalau kosong, jalankan
  `sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other`.
* **Drag & drop** (butuh `open-vm-tools-desktop`).
* **git clone** repo ini langsung di VM, branch `claude/determined-cerf-xd6tlq`.

Di langkah 3 dan 5, ganti `/mnt/c/Users/<user>/Downloads/...` dengan path shared folder
tersebut.

## 1. Paket build

```bash
sudo apt update
sudo apt install -y build-essential git wget cmake pkg-config p7zip-full unzip \
  autoconf automake autopoint intltool libtool libtool-bin bison flex gperf lzip \
  libssl-dev ruby python3 python3-mako python-is-python3 nsis sdcc \
  libgdk-pixbuf2.0-dev
```

## 2. MXE (toolchain + Qt5, Boost, glib, …), sekali saja

```bash
cd ~
git clone https://github.com/sigrokproject/sigrok-util.git
git clone https://github.com/mxe/mxe.git mxe-git
cd mxe-git
patch -p1 < ../sigrok-util/cross-compile/mingw/mxe_fixes.patch
patch -p1 < ../sigrok-util/cross-compile/mingw/libusb1_upgrade.patch
make -j"$(nproc)" JOBS="$(nproc)" MXE_TARGETS=i686-w64-mingw32.static.posix \
  MXE_PLUGIN_DIRS=plugins/examples/qt5-freeze \
  gcc glib libzip libusb1 libftdi1 hidapi glibmm qtbase qtimageformats \
  qtsvg qttranslations boost check gendef libieee1284 \
  qtbase_CONFIGURE_OPTS='-no-sql-mysql'
```

Kalau gagal di tengah jalan, jalankan ulang perintah `make` yang sama. Paket yang sudah
selesai tidak di-build lagi.

## 3. Pasang patch OLS ke skrip build sigrok

Skrip `sigrok-cross-mingw` meng-clone ulang libsigrok setiap kali dijalankan, jadi patch
disisipkan **di dalam skrip**, tepat setelah `cd libsigrok`:

```bash
cp /mnt/c/Users/<user>/Downloads/logic_analyzer_sump3_git/host/sigrok/libsigrok-ols-rx-robust.patch ~/
cd ~/sigrok-util/cross-compile/mingw
sed -i '/cd libsigrok$/a patch -p1 < $HOME/libsigrok-ols-rx-robust.patch || exit 1' sigrok-cross-mingw
grep -n -A1 'cd libsigrok$' sigrok-cross-mingw
```

`grep` harus menampilkan baris `patch -p1 < $HOME/libsigrok-ols-rx-robust.patch`
tepat di bawah `cd libsigrok`. Sesuaikan path `/mnt/c/...` dengan lokasi repo Anda
(lakukan `git pull` dulu agar file patch ada).

Opsional: di bagian atas skrip, ubah `PARALLEL="-j 2"` menjadi `PARALLEL="-j 8"`
(sesuai jumlah core).

## 4. Build sigrok + PulseView

```bash
cd ~/sigrok-util/cross-compile/mingw
./sigrok-cross-mingw 2>&1 | tee ~/sigrok-build.log
```

Pastikan patch benar-benar terpasang:

```bash
grep -n "patching file\|FAILED\|Hunk" ~/sigrok-build.log | head
```

Harus ada `patching file src/hardware/openbench-logic-sniffer/protocol.c`, tanpa
`FAILED`. Kalau ada `FAILED`, berarti libsigrok upstream sudah berubah di bagian itu.
Kirim log-nya, dan patch akan saya perbarui.

## 5. Installer

```bash
find ~/sigrok-util -name "pulseview-*installer.exe"
cp "$(find ~/sigrok-util -name 'pulseview-*installer.exe' | head -1)" /mnt/c/Users/<user>/Downloads/
```

Uninstall PulseView lama, lalu jalankan installer baru di Windows.

## 6. Uji di board S9

1. Bitstream `antminer_s9_ols`, jumper baud sesuai pilihan (mulai dari 115200, lalu coba
   921600: driver ber-patch membaca per blok sehingga seharusnya kuat di baud tinggi).
2. Connect sekali (Openbench Logic Sniffer, COM channel B, baud = jumper) → Scan → OK.
3. 64K sampel / 1 MHz / Pattern Internal → **Run, Run, Run** tanpa Connect ulang.
   Ganti jumlah sampel (5K, 20K, 64K), lalu Run lagi.
4. Kalau ada yang gagal: *Settings → Logging*, level 4 (Debug), simpan log, kirim. Cari
   `Serial read failed` (pesan baru dari patch) dan `Received N bytes`.

## Masalah umum

| Gejala | Solusi |
|---|---|
| `python: command not found` di MXE | `sudo apt install python-is-python3` |
| Download paket MXE gagal | Ulangi `make` (mirror kadang timeout) |
| Build sangat lambat | Pastikan bekerja di `~`, bukan `/mnt/c` |
| Disk WSL penuh | Hapus `~/mxe-git/pkg` dan `~/mxe-git/.ccache` setelah langkah 2 selesai |
| Patch `FAILED` | libsigrok upstream berubah. Kirim `~/sigrok-build.log` |
