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

| | A. GitHub Actions (disarankan) | B. Lokal di VM Ubuntu 22.04 |
|---|---|---|
| Yang di-build di laptop | Tidak ada | MXE + sigrok + PulseView |
| Waktu | ±30–60 menit (server GitHub) | 2–4 jam |
| Disk | — | ±25 GB |
| Butuh | Akun GitHub | VM 4+ core, 8 GB RAM |

## Jalur A: GitHub Actions

Skrip CI-nya sama persis dengan nightly sigrok. Bedanya hanya libsigrok diambil dari
fork Anda yang sudah di-patch.

### A1. Fork libsigrok dan pasang patch

1. Buka <https://github.com/sigrokproject/libsigrok>, lalu klik **Fork**.
2. Di VM Ubuntu (atau Git Bash di Windows):

   ```bash
   git clone https://github.com/<akun>/libsigrok.git
   cd libsigrok
   git checkout -b ols-rx-robust
   git apply --check ~/libsigrok-ols-rx-robust.patch && git apply ~/libsigrok-ols-rx-robust.patch
   git commit -am "ols: read in blocks, ignore empty reads (Windows repeated runs)"
   git push -u origin ols-rx-robust
   ```

   Untuk `git push`, password GitHub diisi dengan **Personal Access Token**
   (*Settings → Developer settings → Personal access tokens*, scope `repo`).

### A2. Fork sigrok-build dan arahkan ke fork libsigrok

1. Buka <https://github.com/sigrokproject/sigrok-build>, klik **Fork**, dan **biarkan nama
   repo tetap `sigrok-build`**. Job di workflow hanya berjalan jika nama repo berakhiran
   `sigrok-build`.
2. Di fork, buka tab **Actions** dan klik **I understand my workflows, go ahead and enable
   them**.
3. Edit `.github/workflows/build.yml` di web GitHub (ikon pensil). Di blok `env:` paling
   atas, ubah dua baris:

   ```yaml
   LIBSIGROK_REPO: "https://github.com/<akun>/libsigrok.git"
   LIBSIGROK_BRANCH: "ols-rx-robust"
   ```

   Lalu **Commit changes**. Commit ini langsung menjalankan workflow (`on: push`).
   Bisa juga dijalankan manual: *Actions → Build sigrok artifacts → Run workflow*.

### A3. Ambil installer

1. Tunggu job **PulseView MXE build (x86_64) (Release)** selesai (hijau). Job lain
   (macOS, AppImage, sigrok-cli) boleh diabaikan atau di-cancel.
2. Di halaman run, bagian **Artifacts**, unduh `artifact-pulseview-x86_64-release-mxe`
   (zip berisi `pulseview-NIGHTLY-x86_64-release-installer.exe`).
3. Uninstall PulseView lama, lalu jalankan installer baru.

Untuk memastikan patch terpasang, buka log job → langkah **Build dependencies** dan cari
`Cloning into 'libsigrok'`. Sebelumnya harus ada clone dari `github.com/<akun>/libsigrok`.

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
