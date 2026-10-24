# la16 over Ethernet ( Antminer S9, ARM bare-metal )

Program ARM untuk bitstream `antminer_s9_la16eth`: server protokol `la16`
(`docs/PROTOCOL_LA16.md`) lewat **TCP port 5555** di Ethernet S9.

```
PulseView ─TCP─► ARM: la16_server.c ( lwIP raw API )
                  ├─ CONFIG / ARM / ABORT / STATUS ─► la16_regs ( 0x43C0_0000, M_AXI_GP0 )
                  └─ DATA / DATA_RLE ◄─ ring DDR 0x0200_0000.. ( ditulis PL lewat S_AXI_HP0 )
```

| File | Isi |
|---|---|
| `la16_server.c` | Server la16, menggantikan `echo.c` di template Vitis *lWIP Echo Server*. Upload mentah atau RLE |
| `s9_phy.c` | PHY S9 (Broadcom BCM54612E): autonegosiasi 10/100/1000, delay RGMII, kecepatan GEM mengikuti link |
| `vitis_build.py` | Skrip Vitis 2024.2 / 2025.x: platform dari XSA + lwip220 + xiltimer + aplikasi, salin `la16_eth.elf` ke folder build |
| `test/` | Uji di Linux: kode server yang sama di atas shim socket + model PL/DDR, dengan driver la16 asli (`run_host_test.sh`). `rle_test.c`: encoder upload ( mentah / RLE / otomatis ), Windows atau Linux |

## Build dan jalankan (Windows)

**Vivado dan Vitis harus versi yang sama.** XSA dari Vivado yang lebih baru tidak bisa
dibaca Vitis yang lebih lama (error *System DTS File does not exist*). Contoh untuk 2024.2:

```powershell
cd D:\Project\internal\logic_analyzer_sump3_git\vivado
set VIVADO=D:\Xilinx\Vivado\2024.2\bin\vivado.bat
build.bat antminer_s9_la16eth
D:\Xilinx\Vitis\2024.2\bin\vitis.bat -s ..\sw\la16_eth\vitis_build.py          # atau --ip 192.168.x.y
s9_jtag_load.bat build_antminer_s9_la16eth
```

Simpan log Vitis ke file (output terminal terpotong): `... vitis_build.py > vitis_out.txt 2>&1`.

`s9_jtag_load` memuat bitstream, menginisialisasi PLL/clock, DDR (`s9_ddr_init.tcl`)
dan periferal PS, lalu mengunduh dan menjalankan `la16_eth.elf`. Semuanya volatil: setelah
daya dicabut, jalankan lagi.

`vitis_build.py` mengatur sendiri hal-hal yang tidak dibawa template:

* lwIP: RAW API, IP statis, `TCP_SND_BUF` 65535, 256 descriptor TX/RX GEM (64 bawaan lebih
  kecil dari window: paket dibuang, lwIP mencetak `pack dropped, no space`).
* xiltimer: interval timer di TTC0 (`ps7_ttc_0`, diaktifkan di `vivado/build.tcl`). Tanpa ini
  timer TCP lwIP tidak jalan.
* Aplikasi `-O2` (template `-O0`), `echo.c` → `la16_server.c` + `s9_phy.c`.
* `--profile`: `LA16_PROFILE=1`, sebelum `END` server mengirim frame teks 0x8E berisi waktu
  per langkah upload (driver mengabaikannya).

## Jaringan

IP statis **192.168.1.10** (default), netmask 255.255.255.0, gateway tidak perlu. Kabel langsung
ke laptop: set laptop ke misalnya 192.168.1.2/24, lalu `ping 192.168.1.10`.

PHY S9 adalah **Broadcom BCM54612E** (ID 0362/5E62, MDIO 1). Kode PHY lwIP hanya mengenal
Marvell/TI/Realtek/ADI dan cek link-nya me-reset PHY setiap kali link naik, sehingga link
tidak pernah stabil. `s9_phy.c` mematikan cek link lwIP, me-reset PHY sekali, mempertahankan
delay RGMII RX/TX (`rgmii-id`, bawaan chip), mengiklankan 10/100/1000, lalu mengikuti link
(kecepatan GEM + clock GEM0 125 / 25 / 2,5 MHz).

Setelah ELF lama (sebelum `s9_phy.c`) pernah jalan, PHY baru pulih dengan **mencabut daya
12 V**: tidak ada jalur reset PHY dari Zynq.

Kecepatan link: `Get-NetAdapter` di Windows. Di 100 Mbit/s upload mentah ±11,6 MB/s (batas
link). Link turun ke 100 walau kedua sisi Gigabit biasanya karena kabel 2 pasang / pasangan
putus (register PHY: kita mengiklankan 1000, partner `GBSR` = 0).

## Upload

* Mentah: frame `DATA` 510 sampel. Selama upload Nagle aktif supaya segmen TCP penuh.
* RLE: frame `DATA_RLE` ( nilai, jumlah ), dipakai bila host menyetel flag `CONFIG` offset 28
  bit0 (driver la16 baru, untuk perangkat dengan fitur `IDENT` bit3). Format otomatis memilih
  RLE per blok bila lebih kecil dari mentah. Driver la16 pertama tidak mengurai `DATA_RLE`,
  jadi tetap mendapat data mentah.

## PulseView

Connect → driver **la16** → interface **Network (TCP)**, protokol **Raw TCP**, host
192.168.1.10, port 5555 → Scan → *la16 AntMiner S9 Ethernet 0.2*. Butuh installer dari CI
dengan `host/sigrok/libsigrok-tcp-win32-readable.patch`: tanpa itu libsigrok di Windows tidak
pernah melihat data `tcp-raw` ("No la16 IDENT reply").

LED D8 menyala saat klien terhubung. UART konsol PS **J12** (UART1, MIO 48/49, 115200; bukan
J1) mencetak log program.
