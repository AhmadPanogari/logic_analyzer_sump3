# Rencana Produk: Logic Analyzer Consumer

Status: **draf**. Keputusan yang sudah diambil: **16 channel, pasar awal Indonesia,
target spesifikasi: mengalahkan Kingst LA2016** (200 MS/s di 16 ch, buffer ≥ 1 Gbit, lihat
3c). Angka komponen dan pesaing masih perlu divalidasi (harga, ketersediaan).

## 0. Posisi produk (pasar Indonesia)

```
Clone FX2 (murah, mudah didapat)        PRODUK INI                    Kingst LA2016 / DSLogic
8 ch, 24 MHz (16 ch lebih rendah)  ◄──  16 ch, 200 MS/s, 1 Gbit,  ──► 16 ch 200 MS/s, 1 Gbit,
sinyal maks. ±6 MHz praktis             RLE + streaming, ambang       ambang tetap, software sendiri
                                        bisa diatur, PulseView        (kelas USB 3: Sipeed SLogic,
                                        native, dukungan lokal         lihat 3)
```

| Hal | Clone FX2 | **Produk ini (target)** | Kingst / sejenis |
|---|---|---|---|
| Channel | 8 (16 dengan samplerate lebih rendah) | **16** | 16 |
| Samplerate | 24 MHz | **200 MS/s di 16 ch** (resolusi 5 ns) | 100–200 MS/s |
| Sinyal praktis (≥ 4 sampel/periode) | ±6 MHz | **±50 MHz** (dibatasi front-end) | ±25–50 MHz |
| Capture panjang | Streaming mentah USB, dibatasi 24 MHz | **Buffer 1 Gbit + RLE**, **streaming mentah** ±17 MS/s (16 ch), streaming RLE pada samplerate yang dipilih (lihat 5d) | Buffer (LA2016) / streaming |
| Software | PulseView | **PulseView native** (open source) | Software sendiri |
| Ketersediaan di Indonesia | Mudah | **Produksi / stok lokal** | Jarang, impor |
| Dukungan | Tidak ada | **Panduan & dukungan Bahasa Indonesia** | Bahasa Inggris / Mandarin |

Pesan utama: *"16 channel 200 MS/s dengan memori 1 Gbit, ambang yang bisa diatur,
langsung jalan di PulseView, lebih murah dari LA2016, dengan panduan Bahasa Indonesia."*

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
| 16 ch USB 2, 100–500 MS/s | Kingst LA1010/**LA2016**/LA5016, DSLogic Plus (DreamSourceLab) | Software sendiri (DSView adalah fork PulseView). **Di Indonesia jarang dan mahal** |
| 16–32 ch **USB 3 streaming** | **Sipeed SLogic16U3** (±US$ 60–69: 16 ch @200 MS/s streaming, 0–10 V, ambang 0–6 V, sigrok/PulseView), **SLogic32U3** (±US$ 99–179: 32 ch @200 MS/s, 4 ch @1,4 GS/s, USB 3.2 ±800 MB/s, DDR3 2 Gbit sebagai buffer elastis, aplikasi SLogicView) | Spesifikasi teknis di atas target kita di harga yang mirip. **Pesaing terberat** |
| Premium | Saleae Logic | Mahal, software sangat matang |

Perbandingan samplerate saat **16 channel aktif bersamaan** (perkiraan, cek datasheet):

| Produk | Maks. (sedikit ch) | 16 ch serentak | Mode |
|---|---|---|---|
| Clone FX2 | 24 MS/s (8 ch) | ±12 MS/s | Streaming USB 2 |
| Kingst LA1010 | 100 MS/s (≤3 ch) | ±16 MS/s | Streaming USB 2 |
| DSLogic Plus | 400 MS/s (≤4 ch) | ±100 MS/s | Buffer 256 Mbit |
| **Kingst LA2016** | 200 MS/s | perlu dicek | Buffer 1 Gbit |
| Sipeed SLogic16U3 | 800 MS/s (4 ch) | 200 MS/s | Streaming USB 3 |
| Prototipe S9 (sekarang) | 100 MS/s | 100 MS/s | Buffer 64K (OLS) |
| **Target produk** | 200 MS/s | **200 MS/s** | Buffer 1 Gbit + streaming USB 2 |

Kesimpulan: secara global kelas ini sudah ramai, dan kelas USB 3 (Sipeed) sudah menawarkan
200 MS/s streaming di harga ±US$ 60–69. Target realistis kita adalah **kelas USB 2 / buffer
(Kingst LA2016)**: setara di samplerate dan memori, unggul di ambang, streaming, PulseView
native, harga, dan dukungan lokal (3c). Bersaing langsung dengan Sipeed butuh USB 3 + DDR
lebar dan bukan target v1.

## 3c. Target: mengalahkan Kingst LA2016

Spesifikasi LA2016 dari spec sheet lama dan toko (perlu dicek ulang): 16 ch, 200 MS/s,
memori 1 Gbit (50M sampel per channel, sampai 10G terkompres), bandwidth input 40 MHz,
pulsa minimum 12,5 ns, ambang tetap (< 0,8 V / > 1,6 V), mode buffer lewat USB 2, software
KingstVIS (libsigrok punya driver `kingst-la2016`, firmware harus diekstrak dari KingstVIS),
±US$ 300 di Newegg. **Harga di marketplace Indonesia perlu dicek.**

| | LA2016 | **Target kita** | Cara |
|---|---|---|---|
| Samplerate 16 ch | 200 MS/s | **200 MS/s semua channel** | Pin dicuplik di kedua tepi clock 100 MHz (IDDR), 2 sampel per clock |
| Memori | 1 Gbit | **≥ 1 Gbit DDR3** + RLE | DDR3 128 MB |
| Kedalaman mentah | 50M sampel | 64M sampel (0,32 s @200 MS/s) | — |
| Kedalaman RLE | 10G (terkompres) | Sebanding: entri RLE 64 bit di DDR | Format RLE `la16` |
| Pulsa minimum | 12,5 ns | **5 ns** | 200 MS/s + front-end cepat |
| Bandwidth input | 40 MHz | **≥ 50–100 MHz** | Comparator/buffer input cepat |
| Ambang | Tetap | **Bisa diatur** (mis. 0,5–5 V) | DAC + comparator |
| Streaming | Tidak ada | **±17 MS/s 16 ch, ±35 MS/s 8 ch** | USB 2 sync FIFO (FT232H) |
| Upload 128 MB | USB 2 | ±4 s (USB 2 ±35 MB/s) | — |
| PulseView | Perlu ekstrak firmware | **Native** | Driver `la16` (`docs/PROTOCOL_LA16.md`) |
| Harga | (cek lokal) | **Di bawah LA2016 di Indonesia** | BOM dihitung di P2 |

Jalur pembuktian:

1. **Board S9 (tanpa beli hardware):** 200 MS/s lewat IDDR, buffer di DDR3 milik PS lewat
   port AXI HP (400 MB/s tulis, teori port 800 MB/s). Bila DDR S9 256–512 MB, buffer
   2–4 Gbit. Upload masih lewat UART (≤ ±1,2 MB/s), jadi S9 membuktikan samplerate,
   trigger, dan kedalaman, bukan kecepatan upload. **Perlu dicek: tipe dan ukuran chip
   DDR di board S9**, serta parameter DDR untuk PS7.
2. **Hardware produk (P2):** dev board **Sipeed Tang Primer 20K** (Gowin GW2A-18 +
   DDR3 128 MB = 1 Gbit, perlu dicek) + modul **FT232H** sync FIFO.
3. **Front-end:** ambang yang bisa diatur, proteksi, bandwidth ≥ 50 MHz, diuji di
   breadboard/PCB kecil bersamaan dengan P2.

Risiko: pengendali DDR3 (PS di S9, IP DDR3 Gowin di produk) dan PCB 200 MS/s jauh lebih
sulit dari tahap sebelumnya; harga LA2016 lokal bisa sudah rendah; KingstVIS matang.

## 3b. Proyek open source sejenis (dikaji Oktober 2026)

| Aspek | **Milik kita** (SUMP3 + S9) | [logIP](https://github.com/meiniKi/logIP) (TU Graz) | [Enxor](https://github.com/lekgolo167/enxor-logic-analyzer) |
|---|---|---|---|
| Bahasa / ukuran | Verilog (SUMP3 + MesaBus) | SystemVerilog, ±1.850 baris | Verilog portabel, ±200 LUT / 223 FF |
| Channel | 16 eksternal + 32 internal (skalabel lewat hub/pod) | Sampai 32 | 8–32 (kelipatan 8) |
| Samplerate | 100 MHz tetap | Clock sistem + divider | 100 MHz + divider 16-bit |
| Penyimpanan | **RLE**, timestamp 30 bit | Sampel mentah (RLE hanya direncanakan) | Event + timestamp 8 bit (diam = 1 baris tiap 255 sampel) |
| Kedalaman | 4096 event | `2^MEM_DEPTH` sampel | 4096–8192 baris |
| Durasi sinyal diam @100 MHz | Sampai ±10 s | = jumlah sampel (4096 → 41 µs) | ±21 ms (8192 baris) |
| Trigger | OR/AND, rising/falling, multi-sinyal, Nth, delay, posisi 10–90 % | 4 stage mask/value (gaya SUMP) | 1 channel, rising/falling, delay, rasio pre-trigger |
| Protokol ke PC | MesaBus UART 921600 + bd_server | **SUMP/OLS lewat UART** | Protokol sendiri, UART 115200 |
| Software | sump3.py + PulseView (via VCD) | **PulseView langsung** (driver OLS) | GUI Python sendiri, tanpa decoder |
| Verifikasi | Smoke test + teruji di hardware S9 | Testbench per modul + **formal verification** | Testbench per modul |
| Lisensi | CERN OHL v1.2 + GPL | GPLv3 | GPLv3 |
| Commit terakhir | 2026 | 2022 | 2022 |

Pelajaran:

1. **OLS langsung di FPGA (logIP)**: perangkat yang menjawab protokol SUMP/OLS langsung
   dikenali driver OLS PulseView lewat port COM biasa (USB-serial FTDI), tanpa bridge
   Python dan tanpa com0com. Lihat alternatif Fase 2 di 5f.
2. **Pasar yang sama (Enxor)**: Enxor menyasar celah yang sama ("di antara analyzer
   ±15 dolar dan profesional ±400 dolar"), tetapi dengan timestamp 8 bit, trigger 1
   channel, dan GUI tanpa decoder. Ini mengonfirmasi kebutuhan pasar, dan pembeda kita
   (RLE panjang, trigger multi-sinyal, PulseView + decoder) bernilai.
3. **Sample-rate divider**: kedua proyek punya; pengguna consumer terbiasa memilih
   samplerate. Ditambahkan ke mode buffer (lihat 5d).
4. **Verifikasi**: tiru pendekatan logIP (testbench per modul + formal) untuk RTL produk.
5. **Lisensi**: keduanya GPLv3. Mempelajari aman; **menyalin kode** membawa kewajiban
   GPLv3 dan kecocokannya dengan CERN OHL v1.2 belum jelas. Tulis implementasi sendiri.

## 4. Kandidat pembeda

1. **Capture panjang lewat RLE**: hardware hanya mengirim *perubahan*, jadi link USB
   cukup untuk sinyal biasa (UART, I2C, SPI tidak kontinu) dalam waktu lama. Batasnya
   ada di PC: libsigrok/PulseView menyimpan sampel mentah, sehingga RAM yang terpakai
   = samplerate × 2 byte/s (100 MHz = 200 MB/s). Rekaman menit sampai jam dilakukan di
   samplerate 1–10 MHz. Resolusi penuh untuk durasi panjang butuh penyimpanan RLE di
   sisi PC (modifikasi PulseView atau viewer sendiri), pembeda jangka panjang, bukan v1.
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
| **A (disarankan)** | Dev board **Gowin Tang Primer 20K** (GW2A-18 + **DDR3 128 MB**) + modul **FT232H/FT2232H** mode *245 sync FIFO* | FPGA murah, memori 1 Gbit di board (target LA2016, 3c), mendekati BOM produk. Toolchain Gowin EDA (IP DDR3) | Pengendali DDR3 Gowin perlu dipelajari. Tang Nano 20K (SDRAM 64 Mbit) tidak cukup untuk target 1 Gbit |
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
| **2. Streaming RLE** | Event RLE dialirkan langsung ke PC, driver mengurainya ke samplerate pilihan | Link: 100–200 MHz; di PulseView sesuai RAM PC (praktis 1–10 MHz untuk rekaman menit) | Dibatasi RAM PC: samplerate × 2 byte/s | Sinyal dengan jeda: UART, I2C, GPIO; rekam menit sampai jam |
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
* **Sample-rate divider juga untuk mode 1 (buffer)**, seperti logIP dan Enxor: pengguna
  bisa memilih samplerate, dan RLE pada samplerate lebih rendah memperpanjang durasi.
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

## 5f. Alternatif Fase 2: protokol OLS langsung di FPGA

> **Status (dibuat):** varian `antminer_s9_ols` dengan engine OLS sendiri (`rtl/ols/`):
> 16 ch, 10 Hz–100 MHz, 64K sampel mentah, trigger 4 stage level. Lolos co-simulasi
> dengan driver OLS libsigrok asli (scan, urutan sampel, divider, trigger, decoder
> UART/SPI). Belum diuji di board. Engine ini juga menjadi langkah awal "jalan B"
> (engine capture sendiri, bagian 5e).

Terinspirasi logIP. Daripada bridge Python + COM virtual (`docs/ROADMAP_PULSEVIEW.md`
Fase 2), FPGA menjawab protokol SUMP/OLS sendiri lewat USB-serial (FTDI VCP):

```
PulseView ─driver OLS─► COM port (FTDI) ─UART─► FPGA: decoder perintah OLS ─► SUMP3 / engine capture
```

| | Bridge Python (Fase 2 roadmap) | **OLS di FPGA** |
|---|---|---|
| Instalasi pengguna | Python + bridge + com0com | Hanya PulseView + driver FTDI |
| Plug-and-play Windows | Tidak | **Ya** |
| Penerjemahan RLE → OLS | Di PC | Di FPGA (driver OLS libsigrok mendukung mode RLE) |
| Batasan | Batasan OLS: ≤ 32 ch, tanpa streaming, tanpa nama channel | Sama |

Cocok sebagai **langkah cepat** agar PulseView bisa Run/trigger langsung (sebelum driver
libsigrok native). Untuk tiga mode capture dan streaming (5d), driver native tetap
diperlukan.

Yang perlu diverifikasi: pemetaan event RLE SUMP3 ke format RLE OLS, batas jumlah
sampel/count OLS, dan kecepatan UART FTDI (sampai ±12 Mbaud di FT2232H) untuk download.
Protokol diimplementasikan sendiri dari spesifikasi SUMP/OLS publik, bukan menyalin kode
logIP (GPLv3).

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
- [x] Samplerate: ~~100 MHz~~ → **200 MS/s di 16 ch** (target LA2016, 3c). Prototipe S9 sekarang 100 MHz
- [x] Pasar awal: **Indonesia**
- [ ] Target harga jual dan target BOM (menentukan pilihan FPGA dan front-end)
- [ ] Rentang tegangan input dan tingkat proteksi
- [ ] Memory depth: usulan streaming RLE + buffer ±1 juta event (SDRAM internal FPGA), lihat 5c
- [x] Mode capture v1: **buffer 100 MHz + streaming RLE + streaming mentah** (lihat 5d)
- [x] Arsitektur sampai P2: **modifikasi SUMP3** (sadap encoder RLE) + blok streaming mentah (lihat 5e)
- [ ] Sebelum P3: tetap turunan SUMP3 (CERN OHL) atau engine capture sendiri (lihat 5e)
- [x] Langkah cepat PulseView: **protokol OLS langsung di FPGA** (5f), sudah dibuat (`antminer_s9_ols`)
- [x] Sample-rate divider untuk mode buffer (5d), mengikuti logIP/Enxor
- [ ] Analisis LCD SPI cepat (≥ 40 MHz) / frame penuh di SCLK tinggi: perlu samplerate
      lebih tinggi atau buffer lebih besar; tentukan apakah masuk target v1
- [x] Driver dan protokol sendiri (bukan OLS) untuk status capture, upload bertahap, trigger
      tepi, lalu streaming: rancangan v0 di `docs/PROTOCOL_LA16.md`, mulai di board S9 lewat UART
- [x] Target spesifikasi: **kalahkan Kingst LA2016** (3c); kelas USB 3 (Sipeed) bukan target v1
- [x] Chip DDR S9: 2× K4B2G1646F (DDR3L 2 Gbit x16) = 512 MB, 32 bit. **Lolos tes di board** dengan
      nilai register U-Boot S9 (`vivado/s9_ddr_init.tcl`, `s9_ddr_test.tcl`)
- [x] Harga di Indonesia: Kingst LA2016 Rp 4,5–5 juta, Tang Primer 20K Rp 1,5–2 juta
- [ ] Pilihan FPGA dan USB bridge (setelah P2; kandidat Tang Primer 20K + FT232H)
- [ ] Model distribusi: open hardware penuh, atau hardware terbuka + produk jadi berbayar
