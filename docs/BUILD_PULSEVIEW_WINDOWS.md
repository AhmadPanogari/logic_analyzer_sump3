# Build PulseView Windows dengan patch driver OLS

Tujuan: installer PulseView Windows yang memakai
`host/sigrok/libsigrok-ols-rx-robust.patch`, agar **Run berulang** di board S9
(mode OLS) langsung bekerja tanpa Connect ulang.

PulseView Windows me-link libsigrok secara statis, jadi DLL tidak bisa diganti dan
PulseView harus di-build ulang. Sigrok sendiri membuat build nightly Windows lewat
GitHub Actions di repo [`sigrok-build`](https://github.com/sigrokproject/sigrok-build),
dengan MXE yang dikunci di commit `b48b3cc` (2021).

> `sigrok-util/cross-compile/mingw` (README lama) **sudah usang**: `mxe_fixes.patch`-nya
> gagal di MXE terbaru (`Hunk FAILED`). Catatan di patch itu sendiri menyebut hal yang sama.
> Jangan dipakai.

Ada dua jalur:

| | A. GitHub Actions di repo ini (disarankan) | B. Lokal di VM Ubuntu 22.04 |
|---|---|---|
| Yang di-build di laptop | Tidak ada | MXE + sigrok + PulseView |
| Waktu | Run pertama ±1 jam 20 menit, berikutnya ±10 menit (MXE di-cache) | 2–4 jam |
| Disk | — | ±25 GB |

## Jalur A: GitHub Actions di repo ini

Workflow: `.github/workflows/pulseview-windows.yml`. Isinya sama dengan nightly sigrok
(`sigrok-build/ci/mxe`), dengan dua perbedaan:

* MXE (commit `b48b3cc` + patch `sigrok-build/docker/*.patch`) di-build di runner lalu
  di-cache. Image `ghcr.io/sigrokproject/sigrok-mxe` milik sigrok privat, sehingga di fork
  `docker pull` selalu gagal dengan `denied`.
* `host/sigrok/libsigrok-ols-rx-robust.patch` dipasang dengan `git apply` tepat setelah
  libsigrok di-clone. Fork libsigrok tidak diperlukan.

Workflow berjalan otomatis setiap kali file workflow atau `host/sigrok/**` berubah. Bisa
juga dijalankan manual: *Actions → PulseView Windows (OLS patch) → Run workflow* (untuk
jalan manual, workflow harus ada di branch default).

Hasil: *Actions → run → Artifacts → `pulseview-ols-x86_64-installer`* (zip berisi
`pulseview-ols-<tanggal>-x86_64-installer.exe`, tersimpan 90 hari). Patch terpasang jika di
log langkah *sigrok libraries* ada `== libsigrok changes ==` diikuti
`src/hardware/openbench-logic-sniffer/protocol.c | 29`.

Run pertama (23-10-2026): MXE 58 menit, sigrok 2 menit, PulseView + installer 4 menit.
Hasilnya `pulseview-0.5.0-git-af02198` + patch OLS.

## Jalur B: lokal di VM Ubuntu 22.04

Sama dengan isi `docker/sigrok-mxe.Dockerfile` + `ci/mxe/*.sh` di `sigrok-build`, tetapi
dijalankan langsung di VM.

### B0. VM

* CPU 4 core atau lebih, RAM 8 GB atau lebih, disk kosong ±25 GB (`df -h ~`).
* Build di home VM (`~`), jangan di shared folder `/mnt/hgfs/...`.
* Menyalin file Windows ↔ VM: *VM Settings → Options → Shared Folders*. Isinya muncul di
  `/mnt/hgfs/<nama_share>/`. Kalau kosong, jalankan
  `sudo mkdir -p /mnt/hgfs && sudo vmhgfs-fuse .host:/ /mnt/hgfs -o allow_other`.

### B1. Paket

```bash
sudo apt update
sudo apt install -y autoconf automake autopoint bash bison bzip2 flex g++ g++-multilib \
  sdcc gettext git gperf gtk-doc-tools intltool libc6-dev-i386 libgdk-pixbuf2.0-dev \
  libltdl-dev libssl-dev libtool-bin libxml-parser-perl lzip make openssl p7zip-full \
  patch perl pkg-config python3 python-is-python3 ruby sed unzip wget xz-utils \
  doxygen nsis cmake
```

### B2. MXE (versi yang dikunci sigrok)

```bash
cd ~
rm -rf mxe-git                      # hapus clone lama yang sudah ter-patch sebagian
git clone https://github.com/sigrokproject/sigrok-build.git
git clone https://github.com/mxe/mxe.git mxe-git
cd mxe-git
git reset --hard b48b3cc7085548e896fe967dc6371ff9951390a4
patch -p1 < ../sigrok-build/docker/mxe_fixes.patch
patch -p1 < ../sigrok-build/docker/hidapi_fixes.patch

M="make -j$(nproc) MXE_USE_CCACHE= DONT_CHECK_REQUIREMENTS=1 MXE_TARGETS=x86_64-w64-mingw32.static.posix MXE_PLUGIN_DIRS=plugins/examples/qt5-freeze"
$M gcc
$M glib
$M libzip libusb1 libftdi1 hidapi glibmm
$M qtbase qtimageformats qtsvg qttools qttranslations
$M boost
$M check gendef libieee1284 nettle qwt qtbase_CONFIGURE_OPTS='-no-sql-mysql'
```

Jalankan di dalam `tmux`. Kalau satu baris gagal karena download timeout, ulangi baris itu.

### B3. sigrok (libsigrok ber-patch) + PulseView

```bash
cp /mnt/hgfs/<nama_share>/host/sigrok/libsigrok-ols-rx-robust.patch ~/
cd ~/sigrok-build/ci/mxe
# patch libsigrok tepat setelah di-clone oleh skrip dependencies
sed -i '/^cd libsigrok$/a git apply $HOME/libsigrok-ols-rx-robust.patch' sigrok-mxe-build-dependencies.sh
grep -n -A1 '^cd libsigrok$' sigrok-mxe-build-dependencies.sh

export MXE_DIR=$HOME/mxe-git TARGET=x86_64 INSTALL_DIR=$HOME/sr
export GIT_CLONE="git clone --depth=1" WGET="wget -c --quiet"
export LIBSERIALPORT_REPO=git://sigrok.org/libserialport
export LIBSIGROK_REPO=git://sigrok.org/libsigrok LIBSIGROK_BRANCH=master
export LIBSIGROKDECODE_REPO=git://sigrok.org/libsigrokdecode
export SIGROK_FIRMWARE_REPO=git://sigrok.org/sigrok-firmware
export SIGROK_FIRMWARE_FX2LAFW_REPO=git://sigrok.org/sigrok-firmware-fx2lafw
export SIGROK_DUMPS_REPO=git://sigrok.org/sigrok-dumps
. ./sigrok-mxe-init-toolchain.sh
./sigrok-mxe-build-dependencies.sh 2>&1 | tee ~/deps.log

cd ~ && git clone --depth=1 https://github.com/sigrokproject/pulseview.git
mkdir -p pulseview/build && cd pulseview/build
$CMAKE -DCMAKE_INSTALL_PREFIX:PATH=$INSTALL_DIR -DCMAKE_BUILD_TYPE=Release \
  -DDISABLE_WERROR=TRUE -DENABLE_TESTS=FALSE ..
make $PARALLEL && make install/strip
wget -c https://github.com/pbatard/libwdi/releases/download/b721/zadig-2.4.exe -O $INSTALL_DIR/zadig.exe
wget -c https://github.com/pbatard/libwdi/releases/download/v1.2.5/zadig_xp-2.2.exe -O $INSTALL_DIR/zadig_xp.exe
cp ~/sigrok-build/ci/mxe/contrib-mxe/FileAssociation.nsh contrib/
makensis -DPE64=1 contrib/pulseview_cross.nsi
cp contrib/pulseview-*installer.exe /mnt/hgfs/<nama_share>/
```

Kalau `git apply` di log `deps.log` gagal, berarti libsigrok upstream sudah berubah. Kirim
log-nya, dan patch akan diperbarui.

## Uji di board S9

1. Bitstream `antminer_s9_ols`, jumper baud sesuai pilihan. Mulai dari 115200, lalu coba
   921600: driver ber-patch membaca per blok sehingga seharusnya kuat di baud tinggi.
2. Connect sekali (Openbench Logic Sniffer, COM channel B, baud = jumper) → Scan → OK.
3. 64K sampel / 1 MHz / Pattern Internal → **Run, Run, Run** tanpa Connect ulang.
   Ganti jumlah sampel (5K, 20K, 64K), lalu Run lagi.
4. Kalau ada yang gagal: *Settings → Logging*, level 4 (Debug), simpan log, kirim. Cari
   `Serial read failed` (pesan baru dari patch) dan `Received N bytes`.
