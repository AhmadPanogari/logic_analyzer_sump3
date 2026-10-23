# logic_analyzer_sump3

Logic Analyzer FPGA untuk **Xilinx Zynq-7000 XC7Z010** (board kontrol bekas
**Antminer S9**, Zybo Z7-10, Arty Z7-10) memakai IP **SUMP3** dari
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
| `rtl/la_core.v` | Logika inti (semua board): sinkronizer probe, MesaBus UART, SUMP3, pola uji, LED |
| `rtl/la_top_s9.v` | Top level **Antminer S9**: clock dari PS7 `FCLK_CLK0` (100 MHz) |
| `rtl/ols/` | **Mode OLS**: engine SUMP/OLS sendiri + top `la_top_s9_ols` (PulseView langsung) |
| `rtl/la_top.v` | Top level Zybo/Arty Z7: MMCM 125 → 100 MHz dari oscillator PL |
| `rtl/la_sump3.v` | Instance SUMP3: 1 hub (100 MHz), 2 RLE pod, View ROM (nama sinyal) |
| `rtl/la_test_pattern.v` | Pola uji bawaan (UART, SPI, counter, PWM, pulse) |
| `rtl/la_clk_gen.v` | MMCME2_BASE 125 MHz → 100 MHz (hanya Zybo/Arty) |
| `constraints/antminer_s9.xdc` | Pin board kontrol Antminer S9 |
| `constraints/zybo_z7_10.xdc` | Pin Digilent Zybo Z7-10 |
| `constraints/arty_z7_10.xdc` | Pin Digilent Arty Z7-10 |
| `vivado/build.tcl` | Build Vivado batch (untuk S9 juga membuat block design PS7) → `.bit` + `.bit.bin` |
| `vivado/program.tcl` | Program PL lewat JTAG (Zybo/Arty) |
| `vivado/s9_jtag_load.tcl` | S9 tanpa SD/Linux: program PL + nyalakan clock PS (FCLK0) lewat XSDB/XSCT |
| `host/la.py` | Launcher: `server` (bd_server), `gui` (sump3), `view` (PulseView) |
| `host/sump3_vcd2sr.py` | Konverter VCD SUMP3 → sigrok `.sr` + buka PulseView |
| `host/s9_load_bitstream.sh` | Dijalankan di Linux board S9: muat bitstream lewat FPGA manager |
| `docs/ROADMAP_PULSEVIEW.md` | Rencana pengembangan: PulseView sebagai GUI utama |
| `docs/PRODUCT_PLAN.md` | Draf rencana produk logic analyzer consumer |
| `sim/ols/` | Uji mode OLS: level pin (UART) + co-simulasi dengan driver OLS libsigrok |
| `sim/` | Testbench Icarus Verilog (MesaBus UART → baca HW ID SUMP3) |
| `fetch_third_party.py` | Mengisi `third_party/` (git submodule, atau unduh ZIP jika tanpa git) |
| `third_party/sump3` | Submodule [blackmesalabs/sump3](https://github.com/blackmesalabs/sump3) |
| `third_party/MesaBusProtocol` | Submodule [blackmesalabs/MesaBusProtocol](https://github.com/blackmesalabs/MesaBusProtocol) |

Source SUMP3 dan MesaBus adalah **git submodule**. Ambil dengan salah satu cara:

```sh
git clone --recursive https://github.com/AhmadPanogari/logic_analyzer_sump3
# atau, jika sudah ter-clone / diunduh sebagai ZIP:
python fetch_third_party.py
```

> Unduhan **"Download ZIP"** dari GitHub tidak menyertakan isi submodule, sehingga
> `third_party/` kosong dan build berhenti dengan `third_party submodules missing`.
> `fetch_third_party.py` menjalankan `git submodule update` jika ada git, atau mengunduh
> commit yang dipatok dari GitHub (cukup Python, tanpa git).

## Spesifikasi

Angka **terukur** berasal dari uji di board kontrol Antminer S9 (Vivado 2025.2, JTAG
lewat FT2232H CJMCU). Sisanya mengikuti desain di `rtl/`.

### Hardware

| Item | Nilai |
|---|---|
| FPGA | Zynq **XC7Z010-1CLG400** (board kontrol Antminer S9; juga Zybo Z7-10 / Arty Z7-10) |
| Clock capture | **100 MHz** → resolusi **10 ns**. S9: `FCLK_CLK0` dari PS. Zybo/Arty: MMCM dari oscillator PL |
| Pulsa terpendek | 10 ns (**terukur**: pulsa 10 ns di D14 tertangkap) |
| Frekuensi sinyal | Teori sampai 50 MHz; **disarankan ≤ 25 MHz** (≥ 4 sampel per periode) |
| Channel eksternal | **16** (`D0`..`D15`). S9: J5–J8 pin 5/11/12/15 |
| Channel internal | 32 sinyal debug (`demo_cnt[23:0]`, `mesa_rx`, `mesa_tx`, `lb_wr`, `lb_rd`, `btn0..3`) |
| Level input | LVCMOS33: rendah ≤ 0,8 V, tinggi ≥ 2,0 V. **Maks. 3,3 V, tidak tahan 5 V** |
| Input | Pull-down internal, sinkronizer 2 flip-flop (flop pertama di IOB) |
| Pola uji bawaan | S9: jumper J9 pin 5 → GND. Zybo/Arty: `sw[0]`. UART 115200, SPI 1 MHz, counter, PWM, pulsa 10 ns |
| Indikator (S9) | D5 heartbeat, D6 clock OK, D7 pola uji, D8 aktivitas UART RX |

### Memori dan kompresi RLE

| Item | `probe_pod` (D0–D15) | `debug_pod` (internal) |
|---|---|---|
| Kedalaman | **4096 event** | 2048 event |
| Lebar entri | 48 bit (2 kode + 30 timestamp + 16 data) | 64 bit (2 + 30 + 32) |
| Rentang waktu maks. | **10,7 s** (2³⁰ × 10 ns) | 10,7 s |

RLE hanya menyimpan **perubahan** sinyal, jadi lama rekaman tergantung aktivitas sinyal:

| Kondisi sinyal | Perkiraan lama rekaman |
|---|---|
| Jarang berubah (tombol, enable, status) | Sampai ±10 s |
| Pola uji (SPI 1 MHz + counter + UART) | **±3,4 ms** (**terukur**: −169 µs … +3,2 ms) |
| Satu clock 1 MHz terus berdetak | ±2 ms (2 juta perubahan/detik) |

Channel yang tidak penting bisa di-*mask* (ViewConfig → MaskSig) supaya tidak menghabiskan
event (belum diuji di board). Untuk capture lebih dalam, ubah
`rle_ram_depth_len`/`rle_ram_depth_bits` di `rtl/la_sump3.v` (harus 2^N; XC7Z010 punya
60 BRAM36, 8192 × 48 bit ≈ 11 BRAM36).

### Trigger

| Item | Nilai |
|---|---|
| Tipe | `or_rising`, `or_falling`, `and_rising`, `and_falling` |
| Sumber | Bit mana pun di D0–D15 dan sinyal debug, boleh beberapa sekaligus |
| Posisi | 10 / 25 / 50 / 75 / 90 % buffer (di GUI: 0/25/50/75/100 %) |
| Lainnya | Trig Delay, Trig Nth (kejadian ke-N), Force_Trig |
| Tidak tersedia | Trigger eksternal dan analog (tidak dipakai di desain ini) |
| **Terukur** | `or_falling` di D0, Trig Pos 0 % |

### Interface dan software

| Item | Nilai |
|---|---|
| Program FPGA (S9) | JTAG + XSDB (`vivado/s9_jtag_load.tcl`), volatile. **Terukur** dengan FT2232H CJMCU (`program_ftdi`) |
| Komunikasi | UART MesaBus 3,3 V, autobaud, default **921600 baud** |
| Alamat SUMP3 | ctrl `0x98`, data `0x9C` (`sump_uut_addr = 00000098`) |
| Jembatan PC | `bd_server.py`, TCP port 21567 |
| Kontrol capture | GUI `sump3.py` (Connect → Apply view → Set_Trigs → Acquire) |
| Penampil | PulseView via Save_VCD → `.sr` 100 MHz. **Terukur**: decoder UART dan SPI benar |
| Waktu download | Beberapa detik per capture (belum diukur) |

### Resource FPGA dan timing (build `antminer_s9`, Vivado 2025.2)

| Item | Nilai |
|---|---|
| Block RAM | 9 RAMB36 + 2 RAMB18 ≈ 10 dari 60 BRAM36 (±17 %) |
| Timing @ 100 MHz | WNS **+3,57 ns**, WHS +0,036 ns, 0 critical warning |
| Ruang pengembangan | ±50 BRAM36 kosong, 12 I/O bebas di J2–J4 |

### Batasan saat ini

* **Tidak streaming**: trigger → isi buffer → download → tampil (lihat Fase 5 di roadmap).
* Samplerate tetap 100 MHz; dengan RLE, menurunkan samplerate tidak diperlukan untuk
  menghemat memori.
* Satu domain clock (1 hub).
* Kontrol capture masih di GUI `sump3.py`; PulseView hanya penampil (lihat roadmap).
* Belum diuji di board: mask channel, posisi trigger selain 0 %, sinyal rangkaian luar.

## Hardware

Board yang didukung (argumen `<board>` untuk skrip build):

| Board | `<board>` | Clock PL | Top level |
|---|---|---|---|
| **Board kontrol Bitmain Antminer S9** (AntMiner ControlBoard XC7010) | `antminer_s9` | PS7 `FCLK_CLK0` | `la_top_s9` |
| Digilent Zybo Z7-10 | `zybo_z7_10` | 125 MHz oscillator | `la_top` |
| Digilent Arty Z7-10 | `arty_z7_10` | 125 MHz oscillator | `la_top` |

### Antminer S9

Hal penting tentang board kontrol S9 (dari skematik, didokumentasikan oleh proyek
[Ardzy](https://github.com/chrysovalantischryso/ardzy) dan
[polprog/antminer_zynq](https://github.com/polprog/antminer_zynq)):

* **PL tidak punya oscillator** (Y2/Y3 100 MHz tidak terpasang). Clock 100 MHz diambil
  dari PS (`FCLK_CLK0`), jadi clock PS harus dinyalakan lebih dulu: lewat JTAG dengan
  `vivado/s9_jtag_load.tcl` (tanpa SD/Linux), atau oleh boot loader Linux dari microSD.
* UART konsol J12 milik PS (Linux `ttyPS0`), **tidak** dipakai untuk MesaBus. MesaBus
  memakai USB-UART 3.3V terpisah di konektor J1.
* Semua I/O PL ada di 9 konektor hash-board J1..J9 (2×9 pin), semuanya 3,3 V.
* 4 LED PL (D5..D8) active-low. Tidak ada tombol/switch di PL.

Layout setiap konektor J1..J9 (dilihat dari nomor pin di PCB — cek posisi pin 1 secara visual):

| Pin | Fungsi | Pin | Fungsi |
|---|---|---|---|
| 1 | GND | 2 | GND |
| 3 | SDA (I2C, pull-up 1k) | 4 | SCL (I2C, pull-up 1k) |
| 5 | **IO0** | 6 | strap alamat (jangan dipakai) |
| 7 | strap alamat | 8 | strap alamat |
| 9 | GND | 10 | GND |
| 11 | **IO1** | 12 | **IO2** |
| 13 | GND | 14 | GND |
| 15 | **IO3** | 16 | 3,3 V out (beban kecil) |
| 17 | NC | 18 | EN (GPIO ARM, 2,5 V) |

Wiring logic analyzer di S9:

| Fungsi | Konektor / pin | Pin FPGA |
|---|---|---|
| `bd_tx` → RXD adapter USB-UART | J1 pin 11 | T12 |
| `bd_rx` ← TXD adapter USB-UART | J1 pin 12 | U12 |
| GND adapter | J1 pin 1 | — |
| `D0` `D1` `D2` `D3` | J5 pin 5, 11, 12, 15 | T16 V15 W15 U17 |
| `D4` `D5` `D6` `D7` | J6 pin 5, 11, 12, 15 | U14 U18 U19 U15 |
| `D8` `D9` `D10` `D11` | J7 pin 5, 11, 12, 15 | T20 V20 W20 U20 |
| `D12` `D13` `D14` `D15` | J8 pin 5, 11, 12, 15 | Y18 V16 W16 Y19 |
| Pilih pola uji | J9 pin 5 (R16): **terbuka = probe**, **jumper ke J9 pin 1 (GND) = pola uji** | R16 |

Hubungkan juga **GND target** ke salah satu pin GND konektor. **Jangan beri 5 V** ke pin
mana pun (pakai level shifter / pembagi resistor).

LED S9: D5 (F16) heartbeat, D6 (L19) clock OK, D7 (M19) pola uji aktif, D8 (M17)
aktivitas UART RX. Posisi fisik D5..D8 terhadap pin FPGA belum dipastikan oleh sumber
dokumentasi; cek sendiri.

### Zybo Z7-10 / Arty Z7-10

> USB-UART bawaan Zybo/Arty terhubung ke pin **MIO milik PS**, tidak bisa dipakai oleh
> desain PL ini. Gunakan kabel/modul **USB-UART 3.3V** terpisah (FT232R, CP2102, CH340).

| Fungsi | Zybo Z7-10 | Arty Z7-10 |
|---|---|---|
| `bd_rx` ← TXD adapter | Pmod JE pin 1 (V12) | Arduino IO0 (T14) |
| `bd_tx` → RXD adapter | Pmod JE pin 2 (W16) | Arduino IO1 (U12) |
| GND adapter | Pmod JE pin 5/11 | GND header |
| `D0`..`D7` | Pmod JC pin 1-4, 7-10 | Pmod JA pin 1-4, 7-10 |
| `D8`..`D15` | Pmod JD pin 1-4, 7-10 | Pmod JB pin 1-4, 7-10 |

| Kontrol | Fungsi |
|---|---|
| `sw[0]` = 1 | `D0..D15` diganti **pola uji internal** |
| `btn[0]` / `btn[1]` | reset / pause `demo_cnt` |
| `led[0..3]` | heartbeat, MMCM locked, pola uji aktif, aktivitas UART RX |

### Pola uji

Aktif dengan jumper J9 pin 5 → GND (S9) atau `sw[0] = 1` (Zybo/Arty):

| Channel | Sinyal | Decoder PulseView |
|---|---|---|
| D0 | UART TX 115200 8N1, mengirim `Hello SUMP3 PulseView\r\n` | UART |
| D1 / D2 / D3 / D4 | SPI mode 0, 1 MHz: SCLK / MOSI / MISO / CS# (byte naik 00, 01, ...) | SPI |
| D5..D12 | Counter 8-bit (naik tiap 10,24 µs) | — |
| D13 | PWM 1 kHz, duty berubah 0–100 % | PWM |
| D14 | Pulse 10 ns tiap 1 ms | — |
| D15 | UART busy | — |

## 1. Build bitstream (Vivado)

Butuh Vivado (2019.2 atau lebih baru, sudah diuji build dengan **2025.2**; edisi
gratis Standard/WebPACK sudah mendukung XC7Z010). Hasil build `antminer_s9` di 2025.2:
WNS +3,57 ns @100 MHz, 9 RAMB36 + 2 RAMB18, 0 critical warning.

```sh
cd vivado
./build.sh antminer_s9          # Linux
build.bat  antminer_s9          # Windows (dari "Vivado Tcl Shell" / vivado di PATH)
# atau: vivado -mode batch -source build.tcl -tclargs zybo_z7_10
```

Untuk `antminer_s9`, skrip membuat block design `la_ps` berisi `processing_system7`
(hanya `FCLK_CLK0` = 100 MHz yang diekspor ke PL), lalu membangun `la_top_s9`.

Hasil di `vivado/build_<board>/`:
* `la_top.bit` — untuk JTAG (Vivado Hardware Manager)
* `la_top.bit.bin` — untuk FPGA manager Linux (word di-byte-swap, setara `bootgen -process_bitstream bin`)
* `ps7_init.tcl` — inisialisasi PS untuk `s9_jtag_load.tcl` (S9)
* `la_top.xsa` — hardware platform (S9), jika ingin membuat FSBL sendiri
* laporan timing/utilisasi/IO

## 2. Memuat bitstream

### Antminer S9 — JTAG saja (tanpa SD card / Linux)

Cara paling sederhana untuk verifikasi. Yang dibutuhkan:

* Kabel JTAG Xilinx/Digilent (Platform Cable USB, JTAG-HS2/HS3, atau klon FT2232H yang
  dikenali Vivado) ke **J10** (header JTAG Xilinx 14-pin standar; pin 2 = VREF 3,3 V,
  pin ganjil = GND).
* **XSDB** (ikut terpasang bersama Vivado: `<Vivado>\bin\xsdb.bat`) atau **XSCT** (Vitis /
  Xilinx SDK). Vivado Hardware Manager saja tidak cukup, karena tidak bisa menjalankan
  inisialisasi PS. Launcher memakai `xsct` jika ada di PATH, jika tidak `xsdb`.

#### Memakai FT2232H generik (mis. modul CJMCU-2232HL)

`hw_server` (dipakai Vivado/XSDB) hanya mengenali kabel Xilinx/Digilent, atau FTDI yang
EEPROM-nya sudah diprogram dengan utilitas Vivado **`program_ftdi`**. Setelah diprogram,
**channel A** menjadi JTAG dan **channel B tetap UART** (COM port). Artinya satu modul
CJMCU bisa sekaligus menjadi JTAG dan adapter UART MesaBus.

1. **Pastikan modul punya EEPROM** (IC 8 pin 93C46/93C56/93C66 di dekat FT2232H). Tanpa
   EEPROM, `program_ftdi` tidak bisa dipakai.
2. **Driver**: pakai driver FTDI resmi (CDM/D2XX, biasanya otomatis dari Windows Update).
   Jika modul pernah di-*Zadig* ke WinUSB/libusb (untuk OpenOCD), kembalikan ke driver
   FTDI lewat Device Manager.
3. **Tulis EEPROM** (tutup dulu Vivado/hw_server, hanya colok satu FTDI):

   ```powershell
   D:\Xilinx\2025.2\Vivado\bin\program_ftdi.bat -write -ftdi=FT2232H -serial=S9JTAG01 -vendor="CJMCU" -board="AntminerS9" -desc="FT2232H JTAG"
   D:\Xilinx\2025.2\Vivado\bin\program_ftdi.bat -read
   ```

   Cabut-colok modul. Isi EEPROM lama tertimpa; kalau ingin dikembalikan, bisa memakai
   FT_PROG dari FTDI. (Ada laporan `program_ftdi` bermasalah di Vivado 2024.1; jika 2025.2
   gagal, coba dari instalasi 2023.2.)
4. **Wiring JTAG** CJMCU (channel A, pin ADBUS) ke **J10** S9:

   | CJMCU (FT2232H) | Sinyal | J10 S9 |
   |---|---|---|
   | AD0 (ADBUS0) | TCK | pin 6 |
   | AD1 (ADBUS1) | TDI | pin 10 |
   | AD2 (ADBUS2) | TDO | pin 8 |
   | AD3 (ADBUS3) | TMS | pin 4 |
   | GND | GND | pin 1/3/5/... (ganjil) |
   | — | VREF 3,3 V | pin 2 (jangan disambung ke 3V3 CJMCU; cukup untuk cek tegangan) |
   | — | SRST | pin 14 (biarkan) |

   I/O FT2232H di modul ini 3,3 V, cocok dengan JTAG S9 (3,3 V). Pakai kabel sependek
   mungkin; resistor seri 33–100 Ω di TCK/TMS/TDI membantu bila sinyal tidak stabil.
5. **Wiring UART MesaBus** (channel B) ke **J1** S9:

   | CJMCU (FT2232H) | Sinyal | J1 S9 |
   |---|---|---|
   | BD0 (BDBUS0) | TXD (keluar dari FTDI) | pin 12 (`bd_rx`) |
   | BD1 (BDBUS1) | RXD (masuk ke FTDI) | pin 11 (`bd_tx`) |
   | GND | GND | pin 1 |

   Port COM channel B inilah yang dipakai di `python host\la.py server --port COMx`.
6. **Cek**: Vivado Hardware Manager → *Open Target → Auto Connect*. Harus muncul kabel
   `Xilinx/S9JTAG01` dengan `xc7z010_1` dan `arm_dap_0`. Tutup lagi Hardware Manager
   sebelum menjalankan skrip XSDB.
7. Jika JTAG tidak stabil (target hilang / error baca), turunkan TCK:

   ```powershell
   set S9_JTAG_HZ=1000000
   D:\Xilinx\2025.2\Vivado\bin\xsdb.bat vivado\s9_jtag_load.tcl
   ```

Jika `program_ftdi` tidak bisa dipakai (mis. modul tanpa EEPROM), alternatifnya adalah
OpenOCD (driver `ftdi`, target `zynq_7000.cfg`). Alur OpenOCD untuk S9 **belum** dibuat di
repo ini.

Langkah:

1. Matikan board. Set jumper boot **JP1..JP4 semua 0 (Cascade JTAG)**.
2. Sambungkan kabel JTAG ke J10 dan adapter USB-UART ke J1 (lihat tabel wiring). Nyalakan 12 V.
3. Build (sekali): `vivado/build.sh antminer_s9`. Selain bitstream, build ini juga
   menghasilkan `ps7_init.tcl`.
4. Tutup Vivado Hardware Manager (kabel hanya bisa dipakai satu program), lalu:

```sh
vivado/s9_jtag_load.sh            # Linux    ( = xsdb/xsct vivado/s9_jtag_load.tcl )
vivado\s9_jtag_load.bat           # Windows
```

Skrip tersebut:
1. Melakukan `rst -system` lalu memprogram `la_top.bit` ke PL.
2. Menjalankan **hanya** bagian PLL dan clock dari `ps7_init.tcl`. Inisialisasi DDR dan
   MIO dilewati karena tidak dipakai logic analyzer, dan setting DDR di block design ini
   memang tidak disesuaikan untuk S9.
3. Menjalankan `ps7_post_config`: menyalakan level shifter PS↔PL (tanpa ini FCLK0 tidak
   sampai ke PL) dan melepas reset FPGA.
4. Membaca balik register clock dan mencetak frekuensinya, misalnya:

```
 IO PLL      : 1000.000 MHz ( FDIV 30, locked 1 )
 FCLK0       : 100.000 MHz ( DIV0 10, DIV1 1 )
 LVL_SHFTR_EN: 0xF ( expect 0xF )
OK: LED D5 should now blink ( ~0.75 Hz ) and D6 be on.
```

Checklist verifikasi di board:

| Langkah | Tanda berhasil |
|---|---|
| Setelah skrip JTAG | Output `FCLK0 : 100.000 MHz`, LED D5 berkedip ±0,75 Hz, D6 menyala |
| Jumper J9 pin 5 → GND | LED D7 menyala (pola uji aktif) |
| `python host/la.py server --port COMx` lalu `python host/la.py gui` → **Connect** | LED D8 berkedip; sump3.py menampilkan `ck100_hub`, `probe_pod`, `debug_pod` |
| **Acquire** → **Save_VCD** | PulseView terbuka; decoder UART di D0 @115200 membaca `Hello SUMP3 PulseView` |

Semua bersifat volatile: setelah board mati, jalankan lagi langkah 4. CPU ARM tetap
dalam keadaan halt; itu tidak masalah karena PL hanya butuh FCLK0.

### Antminer S9 — alternatif: dari Linux di board

Jika board di-boot dari microSD (jumper **TF card**: JP1=0, JP2=1, JP3=0, JP4=1; mis.
image Ardzy yang men-set FCLK0 = 100 MHz):

1. Hentikan program/servis yang mengakses desain PL sebelumnya lewat AXI. Setelah desain
   ini dimuat, alamat AXI tersebut kosong, dan akses ke sana membuat bus macet sehingga
   watchdog me-reset board.
2. Salin dan muat:

```sh
scp vivado/build_antminer_s9/la_top.bit.bin host/s9_load_bitstream.sh root@<ip-board>:/tmp/
ssh root@<ip-board> sh /tmp/s9_load_bitstream.sh /tmp/la_top.bit.bin
```

> Firmware asli Bitmain (boot NAND) tidak disarankan: FCLK0 belum tentu 100 MHz dan
> software Bitmain terus mengakses FPGA-nya.

### Zybo Z7-10 / Arty Z7-10

Set jumper boot ke **JTAG**, colok USB-JTAG/PROG, lalu:

```sh
vivado -mode batch -source vivado/program.tcl -tclargs zybo_z7_10
```

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
   hardware (hub `ck100_hub`, pod `probe_pod` & `debug_pod`). Window waveform masih
   **kosong**: view belum ditampilkan.
2. **Tampilkan view.** Klik sekali di dalam window waveform (agar window terpilih), lalu
   **ViewConfig** → pilih `probes` di daftar bawah → **Apply** (atau **ApplyAll** untuk
   `probes` + `debug`). Lewat bd_shell: `apply_view_all`. Tanpa langkah ini tidak ada
   sinyal yang bisa dijadikan trigger atau diekspor.
3. **Pasang trigger** (menu **Acquisition**):
   * Klik nama sinyal, mis. `D0` (warna oranye = bisa jadi trigger) sampai **kuning**, lalu
     **Set_Trigs** sekali. Sinyal jadi **merah**, muncul di *Trigger List*, `Num Trigs = 1`.
     Set_Trigs bersifat toggle: klik dua kali = batal. Lewat bd_shell:
     `sump_clear_trigs` lalu `sump_set_trigs D0`.
   * **Trig Type**: klik baris teks `Trig Type = ...` di panel kanan bawah, lalu scroll
     mouse / panah: `or_rising`, `or_falling`, `and_rising`, `and_falling`, ...
   * **Trig Pos**: klik barisnya lalu scroll. Pilihan di GUI berkelipatan 25 %
     (0/25/50/75/100) dan dipetakan ke posisi RLE pod 10/25/50/75/90 %: **0 % = trigger
     di dekat awal buffer** (sebagian besar data sesudah trigger), 100 % = di dekat akhir.
   * Alternatif: `sump_trigger_type` / `sump_trigger_location` di `host/work/sump3.ini`
     (saat sump3.py tertutup).
4. Klik **Acquire** (arm + tunggu trigger + download). Jika tertahan di *Waiting for
   trigger*: cek *Trigger List* tidak kosong; **Force_Trig** memaksa capture.
5. Klik **Save_VCD** → PulseView terbuka dengan channel `D0..D15`
   (dan `demo_cnt[0..23]`, `mesa_rx`, `mesa_tx`, ... dari debug pod).
6. Di PulseView tambahkan decoder, mis. UART pada `D0` @115200, SPI pada `D1..D4`.

Catatan: `save_vcd` hanya mengekspor sinyal yang ada di window sump3.py; kalau ada
sinyal yang di-*select*, hanya sinyal itu yang diekspor. Jika ada dua kursor aktif,
VCD dipotong di antara kursor.

### Status verifikasi di hardware

Diuji pada **board kontrol Antminer S9**, JTAG lewat **FT2232H CJMCU** (`program_ftdi`),
Vivado 2025.2, Windows:

| Langkah | Hasil |
|---|---|
| `s9_jtag_load.tcl` (XSDB) | PL terprogram, FCLK0 100 MHz |
| Connect sump3.py ↔ bd_server ↔ MesaBus UART | `ck100_hub 100 MHz`, `probe_pod 4096x48`, `debug_pod 2048x64` |
| Pola uji, trigger `or_falling` D0, Trig Pos 0 % | Capture −169 µs … +3,2 ms |
| Save_VCD → PulseView, decoder UART D0 @115200 | `Hello SUMP3 PulseView\r\n` terbaca utuh; pulsa 10 ns D14 tiap 1 ms tertangkap |
| Decoder SPI D1–D4, mode 0 | MOSI naik berurutan (0x17, 0x18, …), MISO = ~MOSI (0xE8, 0xE7, …) |

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

## Mode OLS: PulseView mengontrol langsung (Antminer S9)

Varian bitstream **`antminer_s9_ols`** menjawab protokol **SUMP / Openbench Logic Sniffer
(OLS)** langsung dari FPGA. PulseView memakai driver bawaannya *"Openbench Logic Sniffer &
SUMP compatibles"* lewat port COM, sehingga **Run, samplerate, jumlah sampel, dan trigger
diatur dari PulseView**. Mode ini tidak memakai `sump3.py`, `bd_server.py`, atau
konversi VCD.

Engine-nya (`rtl/ols/`) ditulis sendiri dari spesifikasi protokol SUMP/OLS publik dan
tidak memakai HDL SUMP3, MesaBus, atau proyek lain. Pin dan clock sama dengan varian
`antminer_s9`.

| Item | Mode OLS (`antminer_s9_ols`) | Mode SUMP3 (`antminer_s9`) |
|---|---|---|
| Kontrol | **PulseView langsung** | `sump3.py` + bd_server, lalu Save_VCD ke PulseView |
| Channel | 16 (D0–D15) | 16 + 32 internal |
| Samplerate | **10 Hz – 100 MHz** (divider) | 100 MHz tetap |
| Penyimpanan | **64K sampel mentah** (64K × 16 bit, 32 BRAM36) | 4096 event RLE |
| Durasi | 655 µs @100 MHz, 65 ms @1 MHz, 6,5 s @10 kHz | 3 ms – 10 s, tergantung aktivitas |
| Trigger | 4 stage mask/value, **level** 0/1 | OR/AND rising/falling |
| UART | 921600 baud, 8N1 (channel B CJMCU) | 921600 autobaud (MesaBus) |
| Download 64K sampel | ±1,4 s | beberapa detik |

### Build dan muat

```powershell
cd vivado
build.bat antminer_s9_ols
cd ..
D:\Xilinx\2025.2\Vivado\bin\xsdb.bat vivado\s9_jtag_load.tcl vivado\build_antminer_s9_ols
```

Wiring sama dengan mode SUMP3: JTAG di J10, USB-UART (channel B CJMCU) di J1 pin 11/12,
probe di J5–J8, jumper pola uji di J9 pin 5. LED: D5 heartbeat, **D6 menyala = menunggu
trigger**, D7 pola uji, D8 aktivitas UART.

Cek komunikasi tanpa PulseView:

```powershell
python host\la.py ols-probe --port COM5
```

Hasilnya harus `ID: b'1ALS'` dan nama `AntMiner S9 LA`.

### Di PulseView

1. **Connect to a Device** (ikon perangkat di toolbar):
   * Driver: **Openbench Logic Sniffer & SUMP compatibles**
   * Interface: **Serial Port**, pilih port COM channel B CJMCU, baud rate **921600**
   * **Scan for devices** → muncul *AntMiner S9 LA … with 16 channels* → OK
2. Atur **jumlah sampel** (maks. 65536) dan **samplerate** (maks. 100 MHz) di toolbar.
3. **Trigger** (opsional): klik nama channel, lalu pilih kondisi **0** atau **1**. OLS hanya
   mendukung trigger level, tidak mendukung tepi. Untuk UART (idle tinggi), trigger
   `D0 = 0` menangkap start bit pertama. Sampel pra-trigger dikumpulkan dulu sebelum
   trigger aktif, jadi bagian sebelum trigger tidak berisi data basi.
4. **Opsi perangkat** (ikon roda gigi): *Pattern mode = Internal* menampilkan pola uji
   tanpa jumper. **Biarkan RLE = off**: mode RLE OLS tidak didukung, dan jika dinyalakan
   bit tertinggi (D15) dipaksa 0.
5. Klik **Run**. D6 menyala selama menunggu trigger, lalu data diunduh dan tampil.
6. Tambahkan decoder (UART, SPI, I2C, …) seperti biasa.

Tips samplerate: untuk SPI/LCD 10–25 MHz pakai 100 MHz (655 µs per capture). Untuk
UART/I2C lambat, turunkan samplerate agar durasi lebih panjang, misalnya 1 MHz = 65 ms.

### Verifikasi

* `sim/ols/run_uart_sim.sh`: uji level pin `la_top_s9_ols` lewat UART 921600 (ID, 42 byte
  metadata, 32 byte sampel).
* `sim/ols/run_cosim.sh`: **driver OLS libsigrok asli** (sigrok-cli dari libsigrok git)
  ⇄ TCP ⇄ cocotb ⇄ RTL `ols_engine` di Icarus. Lolos:

  | Uji | Hasil |
  |---|---|
  | Scan | `AntMiner S9 LA FPGA version 1.0 with 16 channels`, maks. 65536 sampel |
  | Urutan sampel @100 MHz (probe = counter) | 4096 sampel, 0 error |
  | Divider ke 1 MHz | 2048 sampel, 0 error |
  | Trigger nilai 0x1234, capture ratio 25 % | Tepat di sampel 1024 |
  | Pattern Internal @1 MHz → decoder UART | `Hello SUMP3 PulseView` berulang |
  | Pattern Internal @100 MHz → decoder SPI | Byte berurutan, 0 error |

  Transport TCP libsigrok (`tcp-raw`) perlu patch kecil khusus pengujian
  (`sim/ols/libsigrok-tcpraw-testharness.patch`). Driver OLS tidak diubah.
* Belum diuji: build Vivado varian ini dan PulseView di board S9 sungguhan.

## Menambah / mengganti sinyal

1. Sambungkan sinyal ke `pod0_events`/`pod1_events` di `rtl/la_core.v` (atau tambah pod
   baru di `rtl/la_sump3.v`, naikkan `rle_pod_num` hub dan lebar `hub0_pod_mosi/miso`).
2. Beri nama di **View ROM** pada `u_sump3_core` (`rtl/la_sump3.v`):
   * `8'hF6, 16'd<bit>, "nama"` → satu channel PulseView
   * `8'hF7, 16'd<msb>, 16'd<lsb>, "nama[msb:lsb]"` → vektor; dipecah per bit oleh konverter
   * `8'hF4, "<hub>.<pod>"` sumber sinyal, `8'hF1` nama view, `8'hF5`/`8'hE5` group
3. `rle_ram_width` = `2 + rle_data_bits + rle_timestamp_bits`.
4. Kalau clock capture bukan 100 MHz: ubah `ck_freq_mhz` di hub & core, MMCM di
   `la_clk_gen.v` (Zybo/Arty) atau `PCW_FPGA0_PERIPHERAL_FREQMHZ` di `vivado/build.tcl`
   **dan** FCLK0 dari boot loader (S9), lalu `--samplerate` (`python host/la.py gui -r 125M`).

## Simulasi

Butuh [Icarus Verilog](https://steveicarus.github.io/iverilog/):

```sh
./sim/run_sim.sh        # top Zybo/Arty
./sim/run_sim.sh s9     # top Antminer S9 (PS7 diganti stub clock 100 MHz)
```

Testbench berperan sebagai bd_server: mengirim `\n` (autobaud 921600), menulis
`0x0B` (cmd `rd_hw_id_rev`) ke `0x98`, membaca `0x9C`, dan memeriksa balasan MesaBus
`F0FE0004 5301011C` (ID `0x53` "S3", rev 1, 1 hub, View ROM aktif). Testbench juga
men-decode UART pola uji (`Hello SUMP3 PulseView`).

## Troubleshooting

| Gejala | Cek |
|---|---|
| Build: `third_party submodules missing` | Repo diunduh sebagai ZIP → jalankan `python fetch_third_party.py` di root repo |
| `Invalid Hardware ID` di sump3.py | TX/RX tertukar? GND tersambung? Port/baud bd_server benar? LED UART RX (S9: D8, Zybo/Arty: `led[3]`) berkedip saat connect? |
| S9: LED heartbeat tidak berkedip | FCLK0 tidak jalan. JTAG: lihat output `s9_jtag_load.tcl` (FCLK0, `LVL_SHFTR_EN`). Linux: cek `cat /sys/class/fpga_manager/fpga0/state` = `operating` |
| S9: XSCT tidak menemukan target `APU` / `A9` | Jumper boot bukan Cascade JTAG, VREF/kabel J10, atau Vivado Hardware Manager masih memegang kabel |
| FT2232H/CJMCU tidak terdeteksi Vivado/XSDB | EEPROM belum diprogram `program_ftdi`, modul tanpa EEPROM, atau driver WinUSB (Zadig) masih terpasang |
| JTAG terdeteksi tapi tidak stabil | Kabel terlalu panjang; `set S9_JTAG_HZ=1000000`, tambah resistor seri, cek GND |
| S9: board reboot setelah load bitstream | Ada program yang masih mengakses desain PL lama lewat AXI → hentikan dulu |
| S9: waktu di PulseView meleset | FCLK0 bukan 100 MHz; samakan `--samplerate` dengan frekuensi FCLK0 sebenarnya |
| bd_server tidak bisa buka port | Port dipakai program lain (PuTTY, Vivado serial), nama port salah |
| PulseView tidak terbuka | Path repository mengandung spasi; PulseView tidak ditemukan → `python host/la.py gui --pulseview "C:\...\pulseview.exe"` |
| Waktu di PulseView salah skala | `--samplerate` tidak sama dengan `ck_freq_mhz` SUMP3 |
| Sinyal pod hilang dari VCD | View pod tersebut belum ditampilkan di window sump3.py |
| Channel tanpa kabel bergerak acak | Hubungkan GND; input sudah pull-down tapi kabel panjang tetap bisa menangkap noise |

## Pengembangan

Rencana menjadikan **PulseView sebagai GUI utama** (Run/Stop, samplerate, trigger langsung
dari PulseView ke hardware lewat bd_server, tanpa GUI `sump3.py`) ada di
[`docs/ROADMAP_PULSEVIEW.md`](docs/ROADMAP_PULSEVIEW.md):

1. **Fase 1**: client SUMP3 tanpa GUI (`host/sump3_client.py`) + CLI capture langsung ke `.sr`.
2. **Fase 2**: bridge yang meniru perangkat *OLS/SUMP*, sehingga PulseView resmi bisa
   mengontrol SUMP3 (Windows: lewat COM virtual com0com).
3. **Fase 3** (opsional): driver libsigrok native `sump3`.
4. **Fase 4** (opsional): Ethernet, kedalaman RLE lebih besar, channel tambahan, 200 MHz.
5. **Fase 5** (opsional): deep capture ke DDR3 lewat AXI HP + Ethernet, dan streaming
   kontinu terbatas ±11 MB/s (Ethernet S9 100 Mbit/s). SUMP3 sendiri tidak bisa streaming.

Arah jangka panjang menjadi **produk logic analyzer consumer** (board sendiri, USB
plug-and-play, front-end input, driver PulseView native) ada di
[`docs/PRODUCT_PLAN.md`](docs/PRODUCT_PLAN.md).

## Lisensi

* Kode di `rtl/`, `host/`, `sim/`, `constraints/`, `vivado/` — repository ini.
* Pinout Antminer S9 diambil dari skematik Bitmain sebagaimana didokumentasikan proyek
  [Ardzy](https://github.com/chrysovalantischryso/ardzy).
* SUMP3 Verilog & MesaBus Verilog © Kevin Hubbard / BlackMesaLabs, **CERN OHL v1.2**
  (`rtl/la_sump3.v` diturunkan dari `sump3_top.v` contoh SUMP3).
* `sump3.py` dan `bd_server.py` © BlackMesaLabs, **GPL** — dipakai apa adanya lewat submodule.
* PulseView/sigrok © proyek sigrok, GPL.
