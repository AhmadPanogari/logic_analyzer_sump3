# Status proyek (24-10-2026)

Catatan serah terima untuk melanjutkan pekerjaan di session lain. Detail ada di `README.md`,
`docs/PRODUCT_PLAN.md`, `docs/PROTOCOL_LA16.md`, `sw/la16_eth/README.md`, dan
`docs/BUILD_PULSEVIEW_WINDOWS.md`.

## Tujuan

Logic analyzer 16 channel untuk pasar Indonesia, dipakai dari PulseView. Target v1
mengalahkan Kingst LA2016 (Rp 4,5–5 jt): 200 MS/s di 16 channel, memory ≥ 1 Gbit,
threshold bisa diatur, streaming, dan didukung PulseView secara native. Pesaing terkuat
adalah Sipeed SLogic16U3/32U3 (USB3), bukan target v1. Kandidat produk P2: Tang Primer 20K
(Rp 1,5–2 jt) + FT232H.

Prototipe: board kontrol Antminer S9 bekas (Zynq XC7Z010-1CLG400, DDR3L 512 MB,
2× K4B2G1646F-BYMA, Ethernet Gigabit BCM5461x).

## Lingkungan pengguna

* Windows. Repo: `D:\Project\internal\logic_analyzer_sump3_git`.
* Vivado 2024.2 (`D:\Xilinx\Vivado\2024.2`) + Vitis 2024.2 (`D:\Xilinx\Vitis\2024.2`).
  Ada juga Vivado 2025.2, tapi **build Ethernet wajib memakai 2024.2** (versi XSA harus
  sama dengan Vitis).
* JTAG lewat FT2232H CJMCU: channel A = JTAG, channel B = UART. Boot JTAG saja.
* Ubuntu 22.04 di VMware (cadangan, tidak wajib).
* Bahasa komunikasi: Indonesia.

## Sudah selesai dan diuji di board

| Bagian | Status |
|---|---|
| Bitstream OLS + patch driver OLS libsigrok (Run berulang, 115200 / 921600) | ✅ board |
| Installer PulseView Windows (MXE di GitHub Actions, `.github/workflows/pulseview-windows.yml`, patch OLS + driver `la16`) | ✅ run 39973273719 |
| Protokol `la16` + RTL `rtl/la16/` + driver `host/sigrok/libsigrok-la16-driver.patch` | ✅ sim, co-sim, board |
| `antminer_s9_la16` (BRAM 64K, 200 MS/s, trigger level/tepi, Stop) | ✅ board, uji a–g |
| Init DDR S9 (`vivado/s9_ddr_init.tcl`, nilai dari U-Boot antminer_s9) + `s9_ddr_test` | ✅ board, semua PASS |
| `antminer_s9_la16ddr` (ring DDR lewat HP0, maks. 251.658.240 sampel) | ✅ board: 1M @200 MS/s, 4M @1 MS/s benar |
| `antminer_s9_la16eth` bitstream (HP0 + GP0 register `la16_regs.v` @0x43C00000, TTC0) | ✅ build 2024.2, WNS 0,311 ns |
| Server ARM `sw/la16_eth/la16_server.c` (lwIP RAW, TCP 5555) | ✅ uji host (`sw/la16_eth/test/`) |
| `la16_eth.elf` lewat `vitis_build.py` (Vitis 2024.2, workspace `D:\la16ws`) | ✅ build 24-10-2026, belum diuji di board |

## Sedang dikerjakan

Uji Ethernet di board dengan `vivado\build_antminer_s9_la16eth\la16_eth.elf` (langkah 1 di
bawah). Build ulang dari nol:

```
cd vivado
build.bat antminer_s9_la16eth          (Vivado 2024.2, set VIVADO=...\2024.2\bin\vivado.bat)
vitis -s ..\sw\la16_eth\vitis_build.py > vitis_out.txt 2>&1
```

Masalah build yang sudah diatasi:

1. "System DTS File does not exist": XSA dari Vivado 2025.2 → build ulang dengan 2024.2.
2. `sdtgen.bat` tidak ada di 2024.2 → sdtgen dijalankan lewat `xsct -eval`.
3. "antminer_s9_la16eth.dtsi board file is not present in DTG": variabel `BOARD` yang tertinggal
   di jendela cmd → `build.bat` memakai `setlocal`/`TARGET`, `vitis_build.py` menghapus `board`.
4. ".xpfm does not exist in the repository" → `client.find_platform_in_repos` + cadangan.
5. Build FSBL macet → platform dengan `no_boot_bsp=True`.
6. Jalur Windows > 260 karakter → workspace `D:\la16ws` (opsi `--ws`).
7. Template `lwip_echo_server`: "requires at least one timer hardware instance" → TTC0 diaktifkan
   di PS7 (`vivado/build.tcl`, tanpa pin). SCU timer tidak dihitung oleh template.
8. Interval timer xiltimer mati di BSP (pengaturan library template tidak terbawa, sama seperti
   DHCP) → `vitis_build.py` men-set `XILTIMER_en_interval_timer=true`,
   `XILTIMER_tick_timer=ps7_ttc_0`, dan memberi WARNING bila BSP tetap tanpa tick timer. Tanpa
   ini timer TCP lwIP tidak pernah jalan.
9. `UserConfig.cmake` app mendaftar `echo.c` secara eksplisit → diganti `la16_server.c`.
10. `xtime_l.h` tidak ada di BSP SDT → `la16_server.c` memakai `xiltimer.h` bila `SDT`.
11. Vitis server tertinggal mengunci `D:\la16ws\_ide\.wsdata\.lock` setelah build gagal →
    skrip sekarang memanggil `vitis.dispose()` sebelum keluar. Kalau masih terkunci: tutup
    proses `java.exe` (RigelApp) milik Vitis.

Pengaturan lwIP sudah dicek masuk ke BSP (`lwipopts.h` di `D:\la16ws\s9_platform\export\...`):
`TCP_WND 16384`, `TCP_SND_BUF 32768`, `MEM_SIZE 262144`, `PBUF_POOL_SIZE 2048`, `LWIP_DHCP 0`,
`CONFIG_LINKSPEED1000 1` (di `lwipopts.h`, bukan `xlwipconfig.h`). `xtimer_config.h`:
`XTICKTIMER_IS_TTCPS`, base 0xF8001000.

## Langkah berikutnya

1. Uji Ethernet di board:
   * `s9_jtag_load.bat build_antminer_s9_la16eth` (init MIO + DDR, bitstream, `dow` ELF, `con`).
   * Laptop 192.168.1.2/24 di port Gigabit, `ping 192.168.1.10`.
   * PulseView (installer run 39973273719): driver `la16`, Network / Raw TCP
     `192.168.1.10:5555`. Uji capture kecil, lalu besar (puluhan–ratusan juta sampel), ukur
     kecepatan upload.
2. Mode streaming (`CONFIG` mode 1/2): DDR sebagai FIFO, ARM mengirim di belakang pointer
   tulis. Perlu register pointer tulis di `la16_regs.v` dan dukungan di driver.
3. RLE (`DATA_RLE`), threshold yang bisa diatur (hardware front-end produk), lalu P2
   (Tang Primer 20K + FT232H sync FIFO).

## Catatan teknis penting

* IP statis 192.168.1.10 (opsi `--ip` di `vitis_build.py`). PHY di alamat MDIO 1, ID
  0362/5e62 (Broadcom). lwIP memakai `CONFIG_LINKSPEED1000` (hanya register IEEE).
* `tcp-raw` di libsigrok upstream tidak punya drain → driver `la16` menganggap `SR_ERR_NA` OK.
* Konfigurasi DDR preset Vivado merusak data di S9: selalu pakai `s9_ddr_init.tcl`.
* Simulasi: `sim/la16/` (cocotb + Icarus): `make`, `make USE_DDR=1`, `run_cosim.sh`,
  `make -f Makefile.eth`.
* Git: kerja di branch `claude/determined-cerf-xd6tlq`. Jangan buat PR kecuali diminta.
