# logic_analyzer_sump3

Logic Analyzer FPGA untuk **Xilinx Zynq-7000 XC7Z010** memakai IP **SUMP3** dari
BlackMesaLabs (core + RLE Hub + RLE Pod), **UART MesaBus** + **bd_server.py** milik
BlackMesaLabs sebagai jalur komunikasi, dan **PulseView** (sigrok) sebagai penampil
gelombang.

```
 probe[15:0] ──► RLE Pod "probe_pod" ─┐
 sinyal internal ► RLE Pod "debug_pod" ┴► RLE Hub ─► sump3_core ─► LocalBus 32-bit
                                                                      │
                                                         ft232_xface (MesaBus UART)
                                                                      │ 921600 baud
 ┌────────────────────────── PC ──────────────────────────────────────┴──────────┐
 │ bd_server.py  ◄─TCP 21567─►  sump3.py  ──[Save_VCD]──►  sump3_vcd2sr.py  ──►  PulseView │
 │ (UART↔TCP)                  (arm, trigger,             (VCD → sigrok .sr)              │
 │                              download RLE)                                               │
 └──────────────────────────────────────────────────────────────────────────────────────────┘
```

Kenapa ada `sump3_vcd2sr.py`? PulseView tidak mengenal protokol SUMP3, jadi sump3.py
tetap dipakai untuk mengontrol hardware (arm, trigger, download, dekompresi RLE).
Hasilnya diekspor sebagai VCD, tapi VCD dari sump3.py memakai `$timescale 1ps` dan
importer VCD PulseView akan membuat 1 sampel per ps (memori meledak). Konverter ini
mengubah VCD menjadi file session sigrok (`.sr`) pada samplerate clock capture
(100 MHz), memecah vektor menjadi channel per-bit, lalu membuka PulseView otomatis.
Di PulseView semua protocol decoder (UART, SPI, I2C, dll.) bisa langsung dipakai.

## Isi repository

| Path | Keterangan |
|---|---|
| `rtl/la_top.v` | Top level: MMCM 125→100 MHz, sinkronizer probe, MesaBus, SUMP3, LED |
| `rtl/la_sump3.v` | Instance SUMP3: 1 hub (100 MHz), 2 RLE pod, View ROM (nama sinyal) |
| `rtl/la_test_pattern.v` | Pola uji bawaan (UART, SPI, counter, PWM, pulse) |
| `rtl/la_clk_gen.v` | MMCME2_BASE 125 MHz → 100 MHz |
| `constraints/zybo_z7_10.xdc` | Pin Digilent Zybo Z7-10 |
| `constraints/arty_z7_10.xdc` | Pin Digilent Arty Z7-10 |
| `constraints/timing.xdc` | Constraint clock & false path |
| `vivado/build.tcl` | Build non-project Vivado (synth → bitstream) |
| `vivado/program.tcl` | Program PL lewat JTAG |
| `host/la.py` | Launcher: `server` (bd_server), `gui` (sump3), `view` (PulseView) |
| `host/sump3_vcd2sr.py` | Konverter VCD SUMP3 → sigrok `.sr` + buka PulseView |
| `sim/` | Testbench Icarus Verilog (MesaBus UART → baca HW ID SUMP3) |
| `third_party/sump3` | Submodule [blackmesalabs/sump3](https://github.com/blackmesalabs/sump3) |
| `third_party/MesaBusProtocol` | Submodule [blackmesalabs/MesaBusProtocol](https://github.com/blackmesalabs/MesaBusProtocol) |

Clone dengan submodule:

```sh
git clone --recursive https://github.com/AhmadPanogari/logic_analyzer_sump3
# atau, jika sudah ter-clone:
git submodule update --init --recursive
```

## Spesifikasi

| Item | Nilai |
|---|---|
| FPGA | XC7Z010-1CLG400 (hanya PL, **tanpa PS7/FSBL**) |
| Clock capture | 100 MHz (resolusi 10 ns) |
| Channel eksternal | 16 (`D0`..`D15`), LVCMOS33, pull-down internal |
| Kedalaman `probe_pod` | 4096 event RLE × (16 data + 30 timestamp) → hingga 10,7 s per capture |
| Kedalaman `debug_pod` | 2048 event RLE × 32 sinyal internal |
| Interface host | UART 3.3V, MesaBus, autobaud (default 921600) |
| Alamat SUMP3 | ctrl `0x98`, data `0x9C` (`sump_uut_addr = 00000098`) |

Karena RLE hanya menyimpan *perubahan* sinyal, 4096 event bisa mencakup durasi yang
jauh lebih panjang daripada 4096 sampel biasa. Untuk capture lebih dalam, ubah
`rle_ram_depth_len`/`rle_ram_depth_bits` di `rtl/la_sump3.v` (harus 2^N; XC7Z010
punya 60 BRAM36, 8192 × 48 bit ≈ 11 BRAM36).

## Hardware

### Board yang didukung

* **Digilent Zybo Z7-10** (`zybo_z7_10`)
* **Digilent Arty Z7-10** (`arty_z7_10`)

Board XC7Z010 lain: salin salah satu file di `constraints/`, ganti pin, dan pastikan
ada clock 125 MHz di PL (kalau beda frekuensi, ubah `la_clk_gen.v`). Board tanpa
oscillator di PL (mis. EBAZ4205) butuh `FCLK_CLK0` dari PS7 — belum didukung di sini.

### Wiring

> USB-UART bawaan Zybo/Arty terhubung ke pin **MIO milik PS**, tidak bisa dipakai oleh
> desain PL ini. Gunakan kabel/modul **USB-UART 3.3V** terpisah (FT232R, CP2102, CH340).
> Jangan beri sinyal 5V ke pin FPGA.

| Fungsi | Zybo Z7-10 | Arty Z7-10 |
|---|---|---|
| `bd_rx` ← TXD adapter | Pmod JE pin 1 (V12) | Arduino IO0 (T14) |
| `bd_tx` → RXD adapter | Pmod JE pin 2 (W16) | Arduino IO1 (U12) |
| GND adapter | Pmod JE pin 5/11 | GND header |
| `D0`..`D7` | Pmod JC pin 1-4, 7-10 | Pmod JA pin 1-4, 7-10 |
| `D8`..`D15` | Pmod JD pin 1-4, 7-10 | Pmod JB pin 1-4, 7-10 |

Hubungkan juga **GND** target ke GND board.

| Kontrol | Fungsi |
|---|---|
| `sw[0]` = 1 | `D0..D15` diganti **pola uji internal** (tanpa kabel probe) |
| `btn[0]` | reset `demo_cnt` |
| `btn[1]` | pause `demo_cnt` |
| `led[0]` | heartbeat (≈0,75 Hz) |
| `led[1]` | MMCM locked |
| `led[2]` | pola uji aktif |
| `led[3]` | aktivitas UART RX |

### Pola uji (`sw[0] = 1`)

| Channel | Sinyal | Decoder PulseView |
|---|---|---|
| D0 | UART TX 115200 8N1, mengirim `Hello SUMP3 PulseView\r\n` | UART |
| D1 / D2 / D3 / D4 | SPI mode 0, 1 MHz: SCLK / MOSI / MISO / CS# (byte naik 00, 01, ...) | SPI |
| D5..D12 | Counter 8-bit (naik tiap 10,24 µs) | — |
| D13 | PWM 1 kHz, duty berubah 0–100 % | PWM |
| D14 | Pulse 10 ns tiap 1 ms | — |
| D15 | UART busy | — |

## 1. Build bitstream (Vivado)

Butuh Vivado (2019.1 atau lebih baru; WebPACK gratis sudah mendukung XC7Z010).

```sh
cd vivado
./build.sh zybo_z7_10          # Linux
build.bat  zybo_z7_10          # Windows (dari "Vivado Tcl Shell" / vivado di PATH)
# atau: vivado -mode batch -source build.tcl -tclargs arty_z7_10
```

Hasil: `vivado/build_<board>/la_top.bit` dan laporan timing/utilisasi.

## 2. Program FPGA

Set jumper boot ke **JTAG**, colok USB-JTAG/PROG, lalu:

```sh
vivado -mode batch -source vivado/program.tcl -tclargs zybo_z7_10
```

atau lewat Vivado Hardware Manager → *Program Device* → `la_top.bit`.
`led[0]` berkedip dan `led[1]` menyala menandakan desain berjalan.

## 3. Software di PC

Instal:

* Python 3.8+ dan paket: `pip install -r host/requirements.txt`
  (`pyserial`, `pygame-ce`, `pygame-gui==0.6.12` — versi pygame-gui dikunci sesuai
  peringatan di sump3.py)
* **PulseView** dari <https://sigrok.org/wiki/Downloads> (Windows: installer nightly
  ke `C:\Program Files\sigrok\PulseView\`, Linux: `apt install pulseview`).
  Kalau tidak ada di lokasi standar/PATH, pakai opsi `--pulseview PATH`.

> Letakkan repository di path **tanpa spasi**. sump3.py memanggil viewer dengan
> `os.system()` tanpa tanda kutip.

### Terminal 1 — bd_server (UART ↔ TCP)

```sh
python host/la.py server --port COM5            # Windows
python host/la.py server --port /dev/ttyUSB0    # Linux
```

`la.py` membuat `host/work/bd_server.ini` lalu menjalankan `bd_server.py` milik
MesaBusProtocol. FPGA autobaud dari karakter `\n` pertama yang dikirim bd_server,
jadi `--baud` bebas (default 921600; turunkan ke 115200 bila adapter tidak kuat).

### Terminal 2 — sump3.py + hook PulseView

```sh
python host/la.py gui
```

`la.py` menyiapkan `host/work/sump3.ini` (koneksi `bd_server` ke `127.0.0.1:21567`,
`sump_uut_addr = 00000098`, tanpa AES, download semua pod) dan memasang
`vcd_viewer_path` ke `host/work/pulseview_hook.(bat|sh)`. Setiap kali tombol
**Save_VCD** ditekan, sump3.py memanggil hook tersebut → VCD dikonversi ke `.sr`
→ PulseView terbuka.

### Alur capture

1. Di sump3.py klik **Acquisition → Connect**. Panel kanan bawah menampilkan info
   hardware (hub `ck100_hub`, pod `probe_pod` & `debug_pod`).
2. Pilih view **probes** (dan/atau **debug**) untuk window yang tampil.
3. Atur trigger: klik teks *Trig Type* (mis. `or_rising`), pilih sinyal (merah) lalu
   **Set_Trigs**. Posisi trigger diatur lewat `sump_trigger_location` (persen).
4. Klik **Acquire** (arm + tunggu trigger + download).
5. Klik **Save_VCD** → PulseView terbuka dengan channel `D0..D15`
   (dan `demo_cnt[0..23]`, `mesa_rx`, `mesa_tx`, ... dari debug pod).
6. Di PulseView tambahkan decoder, mis. UART pada `D0` @115200, SPI pada `D1..D4`.

Catatan: `save_vcd` hanya mengekspor sinyal yang ada di window sump3.py; kalau ada
sinyal yang di-*select*, hanya sinyal itu yang diekspor. Jika ada dua kursor aktif,
VCD dipotong di antara kursor.

### Konversi manual

```sh
python host/la.py view host/work/sump_vcd/sump3_0000.vcd
python host/sump3_vcd2sr.py capture.vcd -r 100M -o capture.sr
python host/sump3_vcd2sr.py capture.vcd -r 100M --start 0.002 --end 0.004 --include "^D[0-4]$" --open
```

| Opsi | Fungsi |
|---|---|
| `-r/--samplerate` | Samplerate output (= clock capture SUMP3, default di la.py `100M`; `auto` = tebak dari GCD timestamp) |
| `--start/--end` | Potong jendela waktu (detik dari awal capture) |
| `--max-samples` | Batas sampel (default 200 juta); di atas itu didesimasi otomatis dengan peringatan |
| `--include/--exclude` | Filter nama channel (regex) |
| `--hier` | Tambahkan nama scope VCD ke nama channel |
| `--open` / `--pulseview` | Buka PulseView / path pulseview |

RLE bisa menghasilkan capture beberapa detik; pada 100 MHz, 1 detik = 100 juta sampel
(PulseView menyimpan data tak terkompresi di RAM). Gunakan `--start/--end` untuk
memperbesar area penting daripada desimasi.

## Menambah / mengganti sinyal

1. Sambungkan sinyal ke `pod0_events`/`pod1_events` di `rtl/la_top.v` (atau tambah pod
   baru di `rtl/la_sump3.v`, naikkan `rle_pod_num` hub dan lebar `hub0_pod_mosi/miso`).
2. Beri nama di **View ROM** pada `u_sump3_core` (`rtl/la_sump3.v`):
   * `8'hF6, 16'd<bit>, "nama"` → satu channel PulseView
   * `8'hF7, 16'd<msb>, 16'd<lsb>, "nama[msb:lsb]"` → vektor; dipecah per bit oleh konverter
   * `8'hF4, "<hub>.<pod>"` sumber sinyal, `8'hF1` nama view, `8'hF5`/`8'hE5` group
3. `rle_ram_width` = `2 + rle_data_bits + rle_timestamp_bits`.
4. Kalau clock capture bukan 100 MHz: ubah `ck_freq_mhz` di hub & core, MMCM di
   `la_clk_gen.v`, dan `--samplerate` (`python host/la.py gui -r 125M`).

## Simulasi

Butuh [Icarus Verilog](https://steveicarus.github.io/iverilog/):

```sh
./sim/run_sim.sh
```

Testbench berperan sebagai bd_server: mengirim `\n` (autobaud 921600), menulis
`0x0B` (cmd `rd_hw_id_rev`) ke `0x98`, membaca `0x9C`, dan memeriksa balasan MesaBus
`F0FE0004 5301011C` (ID `0x53` "S3", rev 1, 1 hub, View ROM aktif). Testbench juga
men-decode UART pola uji (`Hello SUMP3 PulseView`).

## Troubleshooting

| Gejala | Cek |
|---|---|
| `Invalid Hardware ID` di sump3.py | TX/RX tertukar? GND tersambung? Port/baud bd_server benar? `led[3]` berkedip saat connect? |
| bd_server tidak bisa buka port | Port dipakai program lain (PuTTY, Vivado serial), nama port salah |
| PulseView tidak terbuka | Path repository mengandung spasi; PulseView tidak ditemukan → `python host/la.py gui --pulseview "C:\...\pulseview.exe"` |
| Waktu di PulseView salah skala | `--samplerate` tidak sama dengan `ck_freq_mhz` SUMP3 |
| Sinyal pod hilang dari VCD | View pod tersebut belum ditampilkan di window sump3.py |
| Channel tanpa kabel bergerak acak | Hubungkan GND; input sudah pull-down tapi kabel panjang tetap bisa menangkap noise |

## Lisensi

* Kode di `rtl/`, `host/`, `sim/`, `constraints/`, `vivado/` — repository ini.
* SUMP3 Verilog & MesaBus Verilog © Kevin Hubbard / BlackMesaLabs, **CERN OHL v1.2**
  (`rtl/la_sump3.v` diturunkan dari `sump3_top.v` contoh SUMP3).
* `sump3.py` dan `bd_server.py` © BlackMesaLabs, **GPL** — dipakai apa adanya lewat submodule.
* PulseView/sigrok © proyek sigrok, GPL.
