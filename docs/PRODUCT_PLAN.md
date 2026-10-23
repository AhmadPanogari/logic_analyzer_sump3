# Rencana Produk: Logic Analyzer Consumer

Status: **draf**. Keputusan yang sudah diambil: **16 channel, 100 MHz, pasar awal
Indonesia**. Angka komponen dan pesaing masih perlu divalidasi (harga, ketersediaan).

## 0. Posisi produk (pasar Indonesia)

```
Clone FX2 (murah, mudah didapat)        PRODUK INI                    Kingst / DSLogic / Saleae
8 ch, 24 MHz (16 ch lebih rendah)  ◄──  16 ch, 100 MHz, RLE  ──►     16 ch 100+ MHz, tapi jarang
sinyal maks. ±6 MHz praktis             harga terjangkau              dan mahal di Indonesia
                                        dukungan lokal (Bahasa)
```

| Hal | Clone FX2 | **Produk ini (target)** | Kingst / sejenis |
|---|---|---|---|
| Channel | 8 (16 dengan samplerate lebih rendah) | **16** | 16 |
| Samplerate | 24 MHz | **100 MHz** (resolusi 10 ns) | 100 MHz ke atas |
| Sinyal praktis (≥ 4 sampel/periode) | ±6 MHz | **±25 MHz** | ±25 MHz ke atas |
| Capture panjang | Streaming mentah USB, dibatasi 24 MHz | **Streaming RLE** di 100 MHz + **streaming mentah** ±16–20 MS/s (16 ch) | Buffer / streaming |
| Software | PulseView | **PulseView native** (open source) | Software sendiri |
| Ketersediaan di Indonesia | Mudah | **Produksi / stok lokal** | Jarang, impor |
| Dukungan | Tidak ada | **Panduan & dukungan Bahasa Indonesia** | Bahasa Inggris / Mandarin |

Pesan utama: *"16 channel 100 MHz yang terjangkau, mudah didapat, langsung jalan di
PulseView, dengan panduan Bahasa Indonesia."*

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
| Clone murah 8 ch 24 MHz | berbasis Cypress FX2 (driver `fx2lafw`) | Sangat murah, mudah didapat di Indonesia, streaming USB, didukung PulseView. Terbatas 24 MHz |
| 16 ch 100–400 MHz | Kingst LA1010/LA2016, DSLogic (DreamSourceLab) | Software sendiri (DSView adalah fork PulseView). **Di Indonesia jarang dan mahal** |
| Premium | Saleae Logic | Mahal, software sangat matang |

Kesimpulan: secara global kelas "16 ch 100 MHz" sudah ramai, tetapi **di Indonesia ada
celah**: pilihan yang mudah didapat hanya clone FX2 24 MHz, sedangkan kelas 100 MHz jarang
dan mahal. Pembeda tambahan di bawah memperkuat posisi itu.

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

## 4b. Pertimbangan pasar Indonesia

| Hal | Rencana / yang perlu dicek |
|---|---|
| Penjualan | Marketplace (Tokopedia, Shopee) dan komunitas (grup maker, kampus, SMK) |
| Harga | Sangat sensitif harga: BOM dan pilihan FPGA harus ditekan sejak desain |
| Dukungan | Panduan, video, dan contoh proyek dalam Bahasa Indonesia; garansi lokal |
| Ketahanan | Pengguna pemula sering salah colok 5 V / 12 V → proteksi input wajib |
| Komponen | Sebagian besar impor (FPGA, USB bridge): perhitungkan bea masuk, kurs, lead time |
| Produksi | PCB/PCBA: bandingkan pabrikan luar (mis. JLCPCB/PCBWay) vs perakitan lokal |
| Regulasi | Cek kebutuhan sertifikasi alat elektronik/USB di Indonesia (Kominfo/SDPPI umumnya untuk perangkat telekomunikasi/radio; alat ukur USB tanpa radio perlu dikonfirmasi) |
| Edukasi | Paket untuk kampus/SMK (harga lab, modul praktikum PulseView) |

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

## 5b. Rekomendasi untuk tahap P2 (bukti konsep murah)

Tujuan P2: membuktikan **ketiga mode capture** (lihat 5d), terutama streaming RLE
16 ch @ 100 MHz dan streaming mentah lewat USB 2.0, di FPGA kandidat yang murah,
sebelum mendesain PCB sendiri.

| Opsi | Komponen | Kelebihan | Kekurangan |
|---|---|---|---|
| **A (disarankan)** | Dev board **Gowin** (mis. Tang Nano 20K, GW2AR-18) + modul **FT232H/FT2232H** mode *245 sync FIFO* | FPGA murah, dicatu USB, mudah didapat di marketplace Indonesia, mendekati BOM produk. Toolchain Gowin EDA atau open source (Yosys + nextpnr) | Perlu porting SUMP3 ke Gowin (inferensi BSRAM, cek konstruksi Verilog) |
| B (eksperimen cepat) | Board **S9** yang sudah ada + modul FT232H/FT2232H kedua di konektor J1–J4 (8 data + 5 kontrol + CLKOUT 60 MHz) | Tidak perlu FPGA baru; SUMP3 sudah jalan | Bukan platform produk; kabel jumper di 60 MHz rawan; CJMCU yang sekarang dipakai untuk JTAG (channel A) tidak bisa sekaligus jadi sync FIFO |

Yang diukur di P2:
- Throughput nyata sync FIFO (target ±35–40 MB/s).
- Event RLE per detik yang bisa dialirkan tanpa overflow (mode 2).
- Samplerate maksimum streaming mentah tanpa overflow untuk 8 dan 16 channel (mode 3).
- Pemakaian resource SUMP3 di FPGA Gowin + timing 100 MHz.
- Kedalaman buffer mode trigger (BSRAM, atau SDRAM internal GW2AR bila dipakai).

Spesifikasi teknis kandidat (ketersediaan, harga, kapasitas BSRAM/SDRAM) harus dicek dari
datasheet dan penjual sebelum membeli.

## 5c. Memory depth

Kedalaman dinyatakan dalam **event RLE** (perubahan sinyal), bukan sampel. Dua mode:

1. **Buffer (trigger)**: event disimpan di memori board. Kapasitas = memori ÷ ukuran event
   (48–64 bit: kode + timestamp + 16 channel).
2. **Streaming RLE**: event dialirkan ke PC lewat USB. Durasi praktis tak terbatas selama
   sinyal ≤ anggaran USB (±4 juta event/detik, perkiraan USB 2.0 sync FIFO ±35 MB/s,
   ±8 byte/event).

| Tingkat | Memori | Kapasitas event | Setara sampel mentah @100 MHz | Biaya tambahan |
|---|---|---|---|---|
| Prototipe S9 | BRAM | 4.096 | 41 µs | — |
| BRAM FPGA kecil (mis. GW2AR-18, ±800 Kbit) | BRAM | ±16 ribu | 160 µs | Nol |
| **SDRAM 64 Mbit dalam paket FPGA** (GW2AR-18) | SDRAM | **±1 juta** | 10 ms | **Nol** |
| SDRAM eksternal 256 Mbit | SDRAM | ±4 juta | 40 ms | 1 chip |
| DDR3 2 Gbit | DDR3 | ±32 juta | 0,34 s | DDR + PCB rumit |
| **Streaming ke PC** | RAM PC | ratusan juta (1 GB ≈ 130 juta) | — | Nol |

Durasi untuk sinyal yang **terus aktif** (lebih lama jika ada jeda diam):

| Kapasitas | UART 115200 (±50 rb ev/s) | I2C 100 kHz (±250 rb ev/s) | SPI 1 MHz (±2 jt ev/s) |
|---|---|---|---|
| 16 rb | 0,3 s | 65 ms | 8 ms |
| 1 jt | 20 s | 4 s | 0,5 s |
| 4 jt | 80 s | 16 s | 2 s |
| 32 jt | ±11 menit | ±2 menit | 16 s |
| Streaming | tak terbatas | tak terbatas | tak terbatas |

**Rekomendasi v1**: streaming RLE sebagai fitur utama + buffer ±1 juta event dari SDRAM
internal FPGA (tanpa biaya BOM tambahan) untuk sinyal yang terlalu ramai bagi USB, +
**streaming mentah** untuk sinyal ramai tapi lambat (lihat 5d).
Kasus terburuk (berubah tiap 10 ns) memakai mode *raw* 16 bit/sampel tanpa timestamp
(±4 juta sampel ≈ 40 ms di SDRAM 64 Mbit), karena bandwidth tulis SDRAM bisa tidak cukup
untuk event 64 bit pada 100 juta event/detik.

Spesifikasi pemasaran yang jujur, misalnya: *"Buffer 1M transisi + streaming tanpa batas
(hingga ±4 juta transisi/detik)"*, bukan "1M sampel".

Semua kapasitas FPGA dan throughput USB di atas adalah perkiraan; ukur di P2.

## 5d. Tiga mode capture (v1)

Agar produk unggul dari clone FX2 di semua skenario, v1 memakai satu jalur USB
(FT232H/FT2232H sync FIFO, ±35–40 MB/s) dan satu set probe untuk tiga mode:

| Mode | Cara kerja | Samplerate | Durasi | Untuk |
|---|---|---|---|---|
| **1. Buffer 100 MHz** (trigger) | SUMP3 RLE (atau raw) ke SDRAM internal, lalu dikirim | 100 MHz | ±1 juta event | Sinyal cepat: SPI 10–25 MHz, glitch 10 ns, timing teliti |
| **2. Streaming RLE** | Event RLE dialirkan langsung ke PC | 100 MHz | Tak terbatas selama ≤ ±4 juta event/s | Sinyal dengan jeda: UART, I2C, GPIO; rekam menit sampai jam |
| **3. Streaming mentah** (seperti FX2) | Sampel mentah dialirkan langsung ke PC | Bisa dipilih; perkiraan maks. **16 ch ±16–20 MS/s**, **8 ch ±32–40 MS/s** | Tak terbatas (dibatasi RAM PC) | Sinyal ramai tapi lambat: LCD SPI ≤ ±5 MHz banyak frame, bus paralel lambat |

Perbandingan per skenario (target):

| Skenario | Clone FX2 | **Produk v1** | Mode |
|---|---|---|---|
| Init LCD SPI di SCLK 10–20 MHz | Tidak bisa | **Bisa** | 1 |
| Timing CS/DC/RESET, glitch | ±42 ns | **10 ns** | 1 / 2 |
| UART/I2C berjam-jam | Bisa (24 MHz) | **Bisa (100 MHz)** | 2 |
| LCD SPI ≤ 4–6 MHz, banyak frame | Bisa | **Bisa** (8 ch hingga ±32–40 MS/s) | 3 |
| 16 channel streaming | ±12 MS/s | **±16–20 MS/s** | 3 |

Catatan desain mode 3:
* Pengemasan sampel: 16 ch = 2 byte/sampel, 8 ch = 1 byte/sampel; pemilihan channel
  aktif mengurangi bandwidth.
* FIFO di FPGA + deteksi **overflow** (jika PC/USB tertinggal) yang dilaporkan ke
  PulseView, bukan data rusak diam-diam.
* Samplerate dibuat dari clock 100 MHz dengan divider (100/N MHz), sehingga resolusi
  tetap sinkron dengan mode 1 dan 2.
* Trigger dapat dihitung di hardware (seperti mode 1) atau di PC (seperti fx2lafw).
* Driver libsigrok menangani ketiga mode sebagai satu perangkat; pengguna memilih
  samplerate dan mode di PulseView.

Semua angka throughput adalah perkiraan dari kemampuan FT232H/FT2232H dan perlu diukur
di P2.

## 5e. Keputusan arsitektur: SUMP3 dan streaming

SUMP3 asli adalah *triggered buffer*: encoder RLE di tiap pod (`sump3_rle_pod.v`) hanya
menulis ke BRAM pod, dan isinya baru bisa dibaca setelah `acq_done` lewat jalur serial
2-kabel pod → hub → core → LocalBus. `sump3.py` juga hanya mengenal arm → tunggu →
download. **SUMP3 apa adanya tidak bisa streaming.**

| Mode produk (5d) | Dengan SUMP3 |
|---|---|
| 1. Buffer 100 MHz | Langsung bisa dengan BRAM (±16 ribu event di FPGA kecil). Buffer ±1 juta event di SDRAM perlu modifikasi pod (RAM pod adalah BRAM terinferensi, bukan pengendali SDRAM) |
| 2. Streaming RLE | Perlu modifikasi: sadap keluaran encoder RLE pod (`rle_wr_en`, `rle_wr_data`: satu word event kode + timestamp + data per perubahan, termasuk penanda rollover timestamp) → FIFO → USB |
| 3. Streaming mentah | Bukan bagian SUMP3: blok terpisah sampel → FIFO → USB |

Dua jalan:

| | **A. Modifikasi SUMP3** | **B. Engine capture sendiri** |
|---|---|---|
| Isi | Tambah port streaming + dukungan SDRAM ke pod SUMP3 | RLE encoder + trigger + FIFO + SDRAM + USB ditulis sendiri (format RLE serupa) |
| Kecepatan mulai | Cepat: encoder dan trigger sudah teruji di hardware | Lebih lama di awal |
| Kendali desain | Terikat struktur SUMP3 (hub/pod/core, bus serial) | Penuh, dirancang untuk USB/streaming |
| Lisensi | Turunan SUMP3 → **CERN OHL v1.2**; modifikasi wajib dibagikan | Bebas memilih lisensi, asal kode benar-benar ditulis sendiri (bukan turunan) |
| Software | Driver libsigrok baru (sump3.py tidak mendukung streaming) | Driver libsigrok baru |

Bagian tersulit sama di kedua jalan: **USB sync FIFO, pengendali SDRAM, front-end input,
driver libsigrok**. Logika RLE sendiri relatif sederhana.

**Keputusan:**
- **Sampai P2: jalan A.** SUMP3 sebagai referensi dan prototipe cepat; sadap encoder RLE
  untuk membuktikan streaming RLE lewat USB; blok streaming mentah dibuat di sampingnya.
- **Sebelum P3: putuskan A atau B**, terutama berdasarkan model lisensi/bisnis (open
  hardware penuh → A cocok; ingin bebas memilih lisensi → B).

## 6. Software

| Komponen | Isi |
|---|---|
| Driver libsigrok `sump3` (C, GPL) | Scan USB, konfigurasi, trigger, tiga mode capture (buffer 100 MHz, streaming RLE, streaming mentah) → paket logic sigrok. Diusulkan upstream ke sigrok |
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
| **P2** | Dev board FPGA kandidat + modul USB (FT2232H/FT232H) + front-end di breadboard. SUMP3 dimodifikasi (sadap encoder RLE) untuk **streaming RLE lewat USB**, + blok streaming mentah | Bukti throughput, pilihan FPGA final |
| **P3** | Keputusan A/B (5e). PCB rev A: front-end, USB, flash, casing awal | Prototipe produk |
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

- [x] Jumlah channel: **16**
- [x] Samplerate: **100 MHz** (resolusi 10 ns, sinyal praktis ±25 MHz)
- [x] Pasar awal: **Indonesia**
- [ ] Target harga jual dan target BOM (menentukan pilihan FPGA dan front-end)
- [ ] Rentang tegangan input dan tingkat proteksi
- [ ] Memory depth: usulan streaming RLE + buffer ±1 juta event (SDRAM internal FPGA), lihat 5c
- [x] Mode capture v1: **buffer 100 MHz + streaming RLE + streaming mentah** (lihat 5d)
- [x] Arsitektur sampai P2: **modifikasi SUMP3** (sadap encoder RLE) + blok streaming mentah (lihat 5e)
- [ ] Sebelum P3: tetap turunan SUMP3 (CERN OHL) atau engine capture sendiri (lihat 5e)
- [ ] Analisis LCD SPI cepat (≥ 40 MHz) / frame penuh di SCLK tinggi: perlu samplerate
      lebih tinggi atau buffer lebih besar; tentukan apakah masuk target v1
- [ ] Pilihan FPGA dan USB bridge (setelah P2)
- [ ] Model distribusi: open hardware penuh, atau hardware terbuka + produk jadi berbayar
