# Rencana Produk: Logic Analyzer Consumer

Status: **draf awal**. Angka target dan pesaing di bawah adalah asumsi awal yang perlu
divalidasi (harga komponen, spesifikasi pesaing, ukuran pasar).

## 1. Untuk siapa

| Pengguna | Kebutuhan utama |
|---|---|
| Hobi / maker (Arduino, ESP32, Raspberry Pi) | Murah, colok-langsung, decode UART/I2C/SPI |
| Pelajar / mahasiswa / lab kampus | Murah, awet (tahan salah colok), software gratis |
| Engineer embedded (STM32, FPGA kecil) | Timing akurat, trigger bagus, capture panjang, decoder lengkap |

Kasus pakai utama: debug **UART, I2C, SPI, 1-Wire, CAN (lewat transceiver), PWM, GPIO**,
ukur timing dan glitch.

## 2. Yang wajib dimiliki produk consumer

| # | Kebutuhan | Status di prototipe S9 |
|---|---|---|
| 1 | **Colok USB → langsung jalan** (tanpa JTAG, tanpa 12 V, tanpa adapter UART) | ❌ |
| 2 | **Input tahan salah colok**: logika 1,8 / 3,3 / 5 V, proteksi ESD/overvoltage | ❌ (3,3 V langsung ke FPGA) |
| 3 | **Ambang tegangan input bisa diatur** | ❌ |
| 4 | **PulseView mengenali perangkat langsung** (Run/Stop/trigger dari PulseView) | ❌ (masih via sump3.py) |
| 5 | Windows / Linux / macOS | ⚠️ (sump3.py + PulseView jalan; belum plug-and-play) |
| 6 | Capture panjang untuk sinyal biasa | ⚠️ (RLE 4096 event) |
| 7 | Casing, kabel probe + grabber, panduan | ❌ |
| 8 | Harga bersaing | — |
| 9 | Sertifikasi EMC (CE/FCC) bila dijual luas | ❌ |

Yang **sudah terbukti** di prototipe: inti capture SUMP3 RLE 100 MHz, trigger, konversi
ke PulseView, dan decoder protokol.

## 3. Lanskap pesaing (perkiraan, perlu dicek ulang)

| Kelas | Contoh | Ciri |
|---|---|---|
| Clone murah 8 ch 24 MHz | berbasis Cypress FX2 (driver `fx2lafw`) | Sangat murah, streaming USB, didukung PulseView |
| 16 ch 100–400 MHz | Kingst LA1010/LA2016, DSLogic (DreamSourceLab) | Harga menengah, software sendiri (DSView adalah fork PulseView) |
| Premium | Saleae Logic | Mahal, software sangat matang |

Kesimpulan: bersaing **hanya** di "16 ch 100 MHz" sulit karena pasarnya sudah ramai dan
murah. Produk perlu **pembeda yang jelas**.

## 4. Kandidat pembeda

1. **Capture sangat panjang di resolusi penuh lewat RLE**: hardware hanya mengirim
   *perubahan*. Dengan streaming RLE lewat USB, sinyal biasa (UART, I2C, SPI tidak
   kontinu) bisa direkam menit hingga jam di 100 MHz, tanpa harus menurunkan samplerate.
   Ini cocok untuk menunggu bug yang jarang muncul.
2. **Native PulseView / sigrok (open source)**: driver libsigrok resmi (upstream), jadi
   tidak perlu software proprietary dan bisa memakai seluruh decoder sigrok.
3. **Open hardware** (konsekuensi CERN OHL dari SUMP3) dijadikan nilai jual: desain
   terbuka, bisa diperbaiki dan dimodifikasi komunitas.
4. **Input front-end yang benar-benar tahan banting** (proteksi, ambang yang bisa
   diatur), karena di kelas murah ini sering jadi titik lemah.

## 5. Arsitektur yang diusulkan (v1)

```
Probe ─► Front-end (proteksi + comparator, ambang via DAC) ─► FPGA
                                                               ├─ SUMP3 RLE pod(s) + trigger
                                                               ├─ Streaming RLE FIFO
                                                               └─ (opsional) SDRAM/DDR buffer
FPGA ─► USB bridge (mis. FT2232H/FT232H sync FIFO, atau FX2/FX3) ─► PC
PC   ─► libsigrok driver "sump3" ─► PulseView / sigrok-cli
```

| Blok | Pilihan yang perlu dievaluasi | Catatan |
|---|---|---|
| FPGA | Gowin, Lattice (iCE40 / ECP5), Artix-7 kecil | SUMP3 berupa Verilog netral vendor. Kriteria: harga, jumlah BRAM, toolchain gratis/open source |
| USB | FT2232H/FT232H (sync FIFO ±35–40 MB/s), Cypress FX2 (USB 2.0), FX3 (USB 3) | Throughput menentukan anggaran streaming RLE |
| Memori | Tanpa memori eksternal (BRAM saja) atau SDRAM/DDR | SDRAM untuk burst capture dalam |
| Front-end | Comparator + DAC untuk ambang, resistor seri + clamp/TVS | Target: logika 1,2–5 V, tahan ±? V (tentukan) |
| Clock | Oscillator di board | Tidak bergantung PS seperti pada S9 |
| Boot | Flash SPI/QSPI | Plug-and-play |
| Daya | USB 5 V | |

Perkiraan anggaran streaming RLE lewat USB 2.0 sync FIFO (±35 MB/s), dengan asumsi
±8 byte per event: **±4 juta perubahan sinyal per detik** untuk semua channel. Itu cukup
untuk kebanyakan sinyal consumer. Sinyal yang lebih ramai jatuh ke mode buffer
(trigger → buffer → tampil).

## 6. Software

| Komponen | Isi |
|---|---|
| Driver libsigrok `sump3` (C, GPL) | Scan USB, konfigurasi, trigger, streaming RLE → paket logic sigrok. Diusulkan upstream ke sigrok |
| PulseView | Dipakai apa adanya (resmi) setelah driver upstream; sebelum itu build khusus |
| Firmware FPGA | SUMP3 + streaming + kontrol USB |
| Installer / driver Windows | Hindari langkah manual (mis. Zadig). Pilih jalur driver USB yang jalan out-of-the-box |
| USB VID/PID | VID/PID sendiri, atau PID dari program open hardware (mis. pid.codes) |

Pekerjaan di `docs/ROADMAP_PULSEVIEW.md` (Fase 1–3) langsung terpakai di sini, terutama
Fase 3 (driver libsigrok native).

## 7. Tahapan

| Tahap | Isi | Hasil |
|---|---|---|
| **P0** (selesai) | Prototipe S9: SUMP3 RLE, trigger, PulseView via VCD | Inti teknis terbukti |
| **P1** | Software di hardware yang ada: client tanpa GUI + **driver libsigrok** (Fase 1+3 roadmap) | PulseView mengontrol SUMP3 langsung |
| **P2** | Dev board FPGA kandidat + modul USB (FT2232H/FT232H) + front-end di breadboard. Implementasi **streaming RLE lewat USB** | Bukti throughput, pilihan FPGA final |
| **P3** | PCB rev A: front-end, USB, flash, casing awal | Prototipe produk |
| **P4** | PCB rev B, uji ketahanan input, uji EMC pra-sertifikasi, panduan | Kandidat produksi |
| **P5** | Beta tester, sertifikasi, produksi PCBA, kemasan, harga | Rilis |

## 8. Lisensi dan legal (cek sebelum P3)

| Komponen | Lisensi | Konsekuensi |
|---|---|---|
| SUMP3 / MesaBus HDL | CERN OHL v1.2 | Komersial boleh; desain turunan dibagikan dengan lisensi sama ke penerima |
| sump3.py / bd_server.py | GPL | Bila disertakan, source wajib tersedia |
| libsigrok / PulseView | GPL v3 | Driver yang dibuat ikut GPL (cocok dengan rencana upstream) |
| Kode repo ini | Belum ada LICENSE | Perlu ditentukan |
| Nama produk / merek | — | Hindari memakai nama "SUMP3" sebagai merek tanpa izin |

Ini bukan nasihat hukum. Baca teks lisensi lengkap atau konsultasikan; pertimbangkan
menghubungi BlackMesaLabs.

## 9. Keputusan yang masih terbuka

- [ ] Target harga jual dan target BOM
- [ ] Jumlah channel (8 / 16) dan samplerate target (100 MHz cukup? 200+ MHz?)
- [ ] Rentang tegangan input dan tingkat proteksi
- [ ] Streaming RLE saja, atau + memori eksternal untuk burst
- [ ] Pilihan FPGA dan USB bridge (setelah P2)
- [ ] Model distribusi: open hardware penuh, atau hardware terbuka + produk jadi berbayar
- [ ] Pasar awal: lokal (Indonesia) atau global
