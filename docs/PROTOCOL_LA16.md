# Protokol dan driver sendiri (`la16`, nama kerja)

Status: **v1 diimplementasikan** (RTL `rtl/la16/`, driver `host/sigrok/libsigrok-la16-driver.patch`), **diuji di board S9** (23-10-2026): capture, Run berulang, 200 MS/s, trigger tepi naik/turun, Stop saat menunggu trigger, status di log PulseView. Nama `la16` hanya nama kerja, mudah
diganti sebelum rilis.

## Kenapa

Protokol OLS tidak punya pesan status, dan data dikirim terbalik (sampel terbaru dulu).
Akibatnya PulseView tidak bisa menampilkan apa pun sebelum seluruh buffer diterima.
Protokol OLS juga tidak bisa dipakai untuk kebutuhan produk (`docs/PRODUCT_PLAN.md` 5c–5e):
memory > 64K, streaming, USB cepat, dan trigger tepi.

| | OLS (sekarang) | `la16` |
|---|---|---|
| Status armed / menunggu trigger / upload | Tidak ada | Frame `STATUS` periodik |
| Urutan data | Terbaru dulu, tampil setelah semua diterima | **Terlama dulu**, tampil bertahap |
| Posisi trigger | Dihitung driver dari rasio | Dikirim perangkat (`TRIGGER`) |
| Trigger | Level saja | **Level + tepi naik/turun/keduanya** |
| Jumlah sampel | ≤ ±256K (batas header OLS) | u32 |
| Deteksi error transport | Tidak ada | Sync + panjang + CRC-8 per frame |
| Streaming (fase berikutnya) | Tidak mungkin | Mode 1/2 di `CONFIG` |
| Transport | UART | UART sekarang, FT232H/FT2232H sync FIFO nanti (format frame sama) |

## Yang akan terlihat di PulseView

PulseView tidak punya API progres. Yang bisa dan tidak bisa:

| Fase capture | Tampilan PulseView | Sumber info tambahan |
|---|---|---|
| Armed, mengisi pra-trigger | Tombol Run 🔴 (*AwaitingTrigger*) | Log driver: `prefill N/M`. LED D6 |
| Menunggu trigger | 🔴 | Log: `waiting for trigger` |
| Trigger terjadi | Penanda trigger muncul, tombol 🟢 | `TRIGGER` diteruskan sebagai `SR_DF_TRIGGER` |
| Upload | **Gelombang tumbuh bertahap** dari kiri | Log: `upload N/M` |
| Selesai / Stop | Abu-abu. Stop mengirim `ABORT`, perangkat langsung idle | — |

Persentase di dalam PulseView sendiri (bukan di log) butuh perubahan PulseView. Itu di luar
v0 dan baru dipertimbangkan setelah driver di-upstream.

## Frame

Semua frame, dua arah:

```
+------+------+--------+--------+-------------------+-------+
| 0xA5 | type | len_lo | len_hi | payload (len B)   | crc8  |
+------+------+--------+--------+-------------------+-------+
```

* `len` ≤ 1024. Semua angka little endian.
* CRC-8, polinom 0x07, init 0x00, dihitung atas `type`, `len`, dan `payload`.
* Penerima yang menemukan CRC salah atau `type` tak dikenal membuang byte sampai `0xA5`
  berikutnya (resync). Perangkat membalas `ERROR` untuk perintah rusak.
* `type` bit 7 = 0: host → perangkat. Bit 7 = 1: perangkat → host.

## Perintah host → perangkat

| type | Nama | Payload | Balasan |
|---|---|---|---|
| 0x01 | `IDENT` | — | `IDENT` |
| 0x02 | `CONFIG` | struktur di bawah | `ACK` / `ERROR` |
| 0x03 | `ARM` | — | `ACK`, lalu `STATUS`… |
| 0x04 | `ABORT` | — | `ACK` (`END` dengan flag aborted bila sedang capture) |
| 0x05 | `STATUS?` | — | `STATUS` |

`CONFIG` (32 byte):

| Offset | Tipe | Isi |
|---|---|---|
| 0 | u8 | mode: 0 = buffer (v0). 1 = streaming mentah, 2 = streaming RLE (cadangan) |
| 1 | u8 | format upload: 0 = mentah, 1 = RLE, 2 = otomatis (perangkat memilih yang lebih kecil per blok) |
| 2 | u16 | channel aktif (bit per channel). v0 selalu mengirim 16 bit per sampel |
| 4 | u32 | divider: samplerate = clock dasar / (divider + 1). Clock dasar dari `IDENT` (S9 sekarang 100 MHz, target 200 MS/s) |
| 8 | u32 | jumlah sampel total |
| 12 | u32 | jumlah sampel pra-trigger (≤ total) |
| 16 | u16 | trigger level: mask |
| 18 | u16 | trigger level: nilai |
| 20 | u16 | trigger tepi naik: mask |
| 22 | u16 | trigger tepi turun: mask |
| 24 | u32 | timeout trigger dalam ms (0 = tanpa batas) |
| 28 | u32 | cadangan (0) |

Trigger terjadi pada sampel di mana **semua** syarat terpenuhi bersamaan (AND, sama dengan
semantik trigger satu stage sigrok): channel di mask level sama dengan nilainya, channel di
mask naik berubah 0→1, channel di mask turun berubah 1→0. Channel di kedua mask tepi =
*any edge*. Semua mask 0 = trigger langsung.

## Frame perangkat → host

| type | Nama | Payload |
|---|---|---|
| 0x81 | `IDENT` | u8 versi protokol (1), u8 jumlah channel (16), u32 clock dasar (100000000 atau 200000000), u32 sampel maks. (BRAM 64K, DDR ratusan juta), u16 fitur (bit0 trigger tepi, bit1 streaming mentah, bit2 streaming RLE), lalu string ASCII `vendor\0model\0versi\0` |
| 0x82 | `ACK` | u8 type perintah yang dijawab |
| 0x83 | `STATUS` | u8 state, u32 sampel tertangkap, u32 total. Dikirim tiap ±50 ms selama armed, dan setiap kali state berubah |
| 0x84 | `DATA` | u32 indeks sampel pertama, lalu N × u16 sampel (N ≤ 256), **terlama dulu** |
| 0x87 | `DATA_RLE` | u32 indeks sampel pertama, lalu N × (u16 nilai, u16 jumlah−1), **terlama dulu**. Driver mengurainya menjadi sampel biasa |
| 0x85 | `TRIGGER` | u32 indeks sampel trigger. Dikirim sebelum `DATA` pertama |
| 0x86 | `END` | u32 jumlah sampel terkirim, u8 flag (bit0 overflow, bit1 aborted, bit2 timeout) |
| 0x8F | `ERROR` | u8 kode (1 CRC, 2 type tak dikenal, 3 config tidak valid, 4 sibuk) |

State: 0 idle, 1 mengisi pra-trigger, 2 menunggu trigger, 3 capture pasca-trigger,
4 upload, 5 selesai.

Urutan capture mode buffer:

```
host: CONFIG ─► ACK
host: ARM    ─► ACK, STATUS(1) … STATUS(2) … STATUS(3)
                STATUS(4), TRIGGER(idx), DATA, DATA, …, END
```

## Memory depth dan streaming (ringkasan)

Detail dan angka ada di `docs/PRODUCT_PLAN.md` (3c, 5c, 5d).

* Penyimpanan: BRAM (S9: 64K mentah, ±32K–56K event RLE), DDR3 (S9: 256–512 MB perlu
  dicek; produk: 128 MB = 1 Gbit).
* Upload adalah hambatan di S9: UART 921600 ±90 KB/s, 12 Mbaud (FCLK1 96 MHz) ±1,2 MB/s.
  RLE (`DATA_RLE`) membuat capture panjang praktis untuk sinyal yang jarang berubah.
* 200 MS/s: pin dicuplik IDDR di kedua tepi clock 100 MHz. Engine memproses 2 sampel per
  clock (32 bit), indeks sampel tetap per sampel.
* Streaming (mode 1/2, nanti): dibatasi link dan RAM PC. libsigrok/PulseView menyimpan
  sampel mentah, sehingga RAM = samplerate × 2 byte/s.

## Driver libsigrok

* Lokasi: `src/hardware/la16/` (`api.c`, `protocol.c`, `protocol.h`). Disimpan di repo ini
  sebagai `host/sigrok/libsigrok-la16-driver.patch`, lalu dikirim ke upstream bila stabil.
* Transport: serial (`conn=COMx`, `serialcomm=921600/8n1`). Transport USB FIFO menyusul
  dengan format frame yang sama.
* `SR_CONF_SAMPLERATE` (100 MHz / N), `SR_CONF_LIMIT_SAMPLES`, `SR_CONF_CAPTURE_RATIO`,
  `SR_CONF_TRIGGER_MATCH` = level 0/1, rising, falling, edge.
* Penerimaan dengan parser frame per blok (tidak ada pembacaan per byte, pembacaan kosong
  diabaikan). Pelajaran dari driver OLS.
* `DATA` → `SR_DF_LOGIC` langsung. `TRIGGER` → `SR_DF_TRIGGER` di posisi yang tepat.
  `STATUS` → `sr_info` (terlihat di *Settings → Logging*).
* Stop di PulseView → `ABORT`, lalu tunggu `END` (maks. 200 ms).

## Rencana implementasi

| Langkah | Isi | Verifikasi |
|---|---|---|
| 1 | Spesifikasi ini | Ditinjau |
| 2 ✅ | RTL `rtl/la16/`: parser frame + CRC, engine capture (BRAM 64K, divider, trigger level/tepi, pra-trigger, upload terlama dulu, status periodik, **2 sampel per clock / 200 MS/s**). Bitstream `antminer_s9_la16`. Engine OLS tetap ada | cocotb: model host Python ⇄ RTL |
| 3 ✅ | Driver libsigrok `la16` | Co-sim: sigrok-cli dan `ols_multirun`-style ⇄ TCP ⇄ RTL (infrastruktur `sim/ols`) |
| 4 ✅ | Workflow CI membangun PulseView dengan patch OLS + driver `la16` | Installer dari Actions |
| 5 ✅ | Uji di board S9 | Run berulang, trigger tepi, Stop saat menunggu, gelombang bertahap |
| 6 | RLE di BRAM + `DATA_RLE` | Co-sim + board |
| 7 ✅ | Buffer DDR3 S9 lewat AXI HP0: varian `antminer_s9_la16ddr` (251M sampel). Lolos simulasi, co-sim driver, dan uji board (1M @200 MS/s, 4M @1 MS/s) | Board |
| 7b | Ethernet: ARM membaca DDR, protokol la16 lewat TCP (upload cepat), lalu mode streaming | Board |
| 8 | (Produk P2, Tang Primer 20K + FT232H) mode streaming mentah dan RLE, transport USB sync FIFO | — |
