# la16 over Ethernet ( Antminer S9, ARM bare-metal )

Program ARM untuk bitstream `antminer_s9_la16eth`: server protokol `la16`
(`docs/PROTOCOL_LA16.md`) lewat **TCP port 5555** di Ethernet Gigabit S9.

```
PulseView ─TCP─► ARM: la16_server.c ( lwIP raw API )
                  ├─ CONFIG / ARM / ABORT / STATUS ─► la16_regs ( 0x43C0_0000, M_AXI_GP0 )
                  └─ DATA ◄─ ring DDR 0x0200_0000.. ( ditulis PL lewat S_AXI_HP0 )
```

| File | Isi |
|---|---|
| `la16_server.c` | Server la16, menggantikan `echo.c` di template Vitis *lWIP Echo Server* |
| `vitis_build.py` | Skrip Vitis 2025.x: platform dari XSA + lwip220 + aplikasi, salin `la16_eth.elf` ke folder build |
| `test/` | Uji di Linux: kode server yang sama di atas shim socket + model PL/DDR, dengan driver la16 asli (`run_host_test.sh`) |

## Build dan jalankan (Windows)

```powershell
cd D:\Project\internal\logic_analyzer_sump3_git\vivado
build.bat antminer_s9_la16eth
D:\Xilinx\2025.2\Vitis\bin\vitis.bat -s ..\sw\la16_eth\vitis_build.py          # atau --ip 192.168.x.y
s9_jtag_load.bat build_antminer_s9_la16eth
```

`s9_jtag_load` memuat bitstream, menginisialisasi PLL/clock, DDR (`s9_ddr_init.tcl`)
dan periferal PS, lalu mengunduh dan menjalankan `la16_eth.elf`.

**Jaringan**: IP statis **192.168.1.10** (default), netmask 255.255.255.0. Kabel langsung ke
laptop: set laptop ke misalnya 192.168.1.2/24, lalu `ping 192.168.1.10`. Link dipaksa
**1 Gbit/s** (PHY Broadcom di S9 tidak dikenali kode PHY lwIP; mode ini hanya memakai
register IEEE), jadi port laptop/switch harus Gigabit.

**PulseView**: Connect → driver **la16** → interface **Network (TCP)**, protokol **Raw TCP**,
host 192.168.1.10, port 5555 → Scan → *la16 AntMiner S9 Ethernet 0.2*.

LED D8 menyala saat klien terhubung. UART1 PS (MIO 48/49, 115200) mencetak log program.
