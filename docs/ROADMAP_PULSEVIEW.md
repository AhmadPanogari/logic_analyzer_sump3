# Roadmap: PulseView sebagai GUI utama

Tujuan: **PulseView dipakai untuk semuanya**, mulai dari Run/Stop, samplerate, jumlah
sampel, sampai trigger, dan terhubung ke hardware lewat `bd_server.py`. GUI `sump3.py`
tidak diperlukan lagi.

## Kondisi sekarang (Fase 0, selesai)

```
FPGA ─UART─► bd_server.py ─TCP─► sump3.py (GUI: arm, trigger, download) ─VCD─► sump3_vcd2sr.py ─.sr─► PulseView
```

PulseView di sini hanya **penampil**. Kontrol capture masih dilakukan di `sump3.py`.

## Target

```
                   ┌─ Fase 2 ─┐
PulseView ─driver OLS/SUMP─► sump3_ols_bridge.py ─TCP─► bd_server.py ─UART─► FPGA (SUMP3)
                                      │
                                      └─ memakai host/sump3_client.py (Fase 1)

Opsi akhir (Fase 3): PulseView ─driver libsigrok "sump3" (C)─► bd_server.py / UART ─► FPGA
```

PulseView tidak mengenal protokol SUMP3. Ada dua jalan:

| Jalan | Ide | Kelebihan | Kekurangan |
|---|---|---|---|
| **A. Bridge OLS** (Fase 2) | Program Python meniru perangkat *Openbench Logic Sniffer / SUMP*, yang sudah didukung PulseView bawaan, lalu menerjemahkannya ke SUMP3 | Memakai PulseView resmi tanpa build ulang. Semua di Python | Batas protokol OLS: maks. 32 channel, nama channel tidak terkirim, jumlah sampel terbatas |
| **B. Driver libsigrok native** (Fase 3) | Driver C `sump3` di libsigrok | Integrasi penuh: nama channel dari View ROM, banyak channel, trigger SUMP3 asli | Harus build libsigrok + PulseView sendiri (Windows: cross-compile MXE). Pekerjaan besar |

**Rekomendasi:** kerjakan Fase 1, lalu Fase 2. Fase 3 hanya jika batasan OLS benar-benar
mengganggu.

---

## Fase 1: Client SUMP3 tanpa GUI (`host/sump3_client.py`)

Fondasi untuk semua fase berikutnya. Isinya mengambil logika hardware dari `sump3.py`
(sekitar 16 ribu baris, menyatu dengan PyGame) ke modul kecil yang bisa diuji.

- [ ] **1.1 Transport bd_server**: format paket TCP `sump3.py` ↔ `bd_server.py`
      (class backdoor di `sump3.py`, sekitar baris 10459: `wr`, `rd`, `tx_tcp_packet`,
      `rx_tcp_packet`), tanpa AES.
- [ ] **1.2 Peta register**: ctrl `0x98` / data `0x9C`, kode perintah (`idle`, `arm`,
      `reset`, `init`, `rd_hw_id_rev`, ...), akses register hub/pod (`rd_pod` / `wr_pod`).
- [ ] **1.3 `rd_cfg()`**: baca HW ID, jumlah hub/pod, frekuensi clock, ukuran RAM tiap pod,
      lalu parse **View ROM** menjadi daftar nama sinyal per pod.
- [ ] **1.4 Kontrol capture**: set trigger, posisi trigger, arm, polling status,
      `force_trig`, `force_stop`.
- [ ] **1.5 Download + dekompresi RLE** per pod: rotasi pointer, rollover timestamp,
      buang sampel tidak valid (`rle_rotate`, `rle_time_roll`, `rle_time_cull` di
      `sump3.py`). Hasilnya daftar `(waktu, nilai)` per sinyal.
- [ ] **1.6 CLI** `host/sump3_capture.py`, contoh:
      `--trigger D0:rising --pos 50 -o cap.sr --open`. Menulis `.sr` langsung, memakai
      writer dari `sump3_vcd2sr.py`. Pada titik ini PulseView sudah bisa dipakai tanpa GUI
      `sump3.py`, walau trigger masih diatur lewat CLI.
- [ ] **1.7 Validasi**: capture yang sama diekspor lewat `sump3.py` (VCD) dan lewat client
      baru, lalu dibandingkan tepi demi tepi. Uji regresi otomatis memakai data dump.
- [ ] **1.8 Emulator hardware** untuk tes tanpa board: server TCP palsu yang menjawab
      seperti bd_server + SUMP3 (atau dijalankan dari simulasi Verilog di `sim/`).

## Fase 2: Bridge OLS/SUMP (`host/sump3_ols_bridge.py`)

PulseView memilih driver **"Openbench Logic Sniffer & SUMP compatibles"**, lalu
bridge menerjemahkan perintahnya ke SUMP3 lewat `sump3_client.py`.

### 2.1 Protokol OLS yang harus diemulasi

- [ ] `0x00` reset, `0x01` run (arm), `0x02` ID → balas `"1ALS"`.
- [ ] `0x04` metadata: nama perangkat, jumlah probe (32), ukuran memori sampel,
      samplerate maks. 100 MHz, versi protokol.
- [ ] `0x80` divider (samplerate), `0x81` read/delay count (jumlah sampel dan posisi
      trigger), `0x82` flags (channel group, RLE, demux).
- [ ] `0xC0..0xCF` trigger stage: mask, value, config.
- [ ] Format data balik: urutan sampel **terbalik** (terbaru dulu), byte per channel group
      yang aktif. Dukung mode **RLE OLS** agar periode diam tidak memakan memori.

### 2.2 Pemetaan PulseView → SUMP3

| Setelan di PulseView | Implementasi di bridge |
|---|---|
| Samplerate | SUMP3 selalu merekam RLE pada `clk_cap` 100 MHz. Bridge me-resample hasil RLE ke samplerate yang diminta |
| Jumlah sampel | Panjang jendela waktu yang dikirim. Data di luar jendela dibuang |
| Posisi trigger (delay count) | Dibulatkan ke posisi SUMP3 yang tersedia: 10 / 25 / 50 / 75 / 90 % |
| Trigger mask/value | SUMP3 punya `or_rising`, `or_falling`, `and_rising`, `and_falling` (+ eksternal/analog). Trigger OLS berbasis level/pola: pemetaan harus didefinisikan dan didokumentasikan (mis. pola → `and_rising` pada bit yang di-mask) |
| Run tanpa trigger | Arm lalu `force_trig` |
| Channel | Maks. 32: D0–D15 dari `probe_pod` + 16 sinyal dari `debug_pod` (atau pod lain yang dipilih lewat argumen bridge) |
| Nama channel | Protokol OLS tidak mendukung. Sediakan template session PulseView (`.pvs`) berisi nama dari View ROM |

### 2.3 Transport PulseView ↔ bridge (perlu diverifikasi)

Driver OLS di libsigrok berkomunikasi lewat **port serial**.

- [ ] **Windows**: pasangan COM virtual **com0com** (mis. `COM20 ↔ COM21`). Bridge membuka
      `COM20`, PulseView membuka `COM21`. Kandidat utama, karena libserialport melihatnya
      sebagai port COM biasa.
- [ ] **Linux**: hasil uji di libsigrok 0.5.2 (`sigrok-cli -d ols:conn=/dev/pts/N`): pty
      dari `socat` **ditolak** (`Attempt to open serial port with invalid parameters`).
      Alternatif: modul kernel `tty0tty`, atau libsigrok/PulseView versi nightly. Cek
      apakah versi itu mendukung `conn=tcp-raw/<host>/<port>` untuk driver serial. Di
      0.5.2, `tcp-raw` hanya dipakai driver BeagleLogic dan ditolak oleh driver OLS.
- [ ] Langkah pertama Fase 2 adalah prototipe kecil yang hanya menjawab ID + metadata,
      untuk memastikan PulseView di Windows bisa *scan* dan melihat perangkat lewat com0com.

### 2.4 Tes dan integrasi

- [ ] Tes otomatis memakai `sigrok-cli -d ols:conn=<port> --samples N` terhadap bridge +
      emulator hardware (1.8), dicek dengan decoder UART/SPI pada pola uji.
- [ ] Tes di board S9 dengan pola uji (jumper J9), dibandingkan dengan hasil Fase 0.
- [ ] Subcommand `python host/la.py bridge --port COM20` dan dokumentasi di README.

### Batasan Fase 2 yang sudah diketahui

- Maks. 32 channel per "perangkat" OLS.
- Nama channel tidak otomatis (pakai template `.pvs`).
- Bukan streaming: SUMP3 merekam ke buffer, lalu data dikirim setelah capture selesai.
  Mode *continuous* PulseView tidak didukung.
- Batas jumlah sampel dari field count OLS. Mode RLE OLS membantu untuk capture panjang
  yang jarang berubah.
- Waktu antar pod sudah sinkron di SUMP3 (satu hub, satu clock), tapi pod di hub/clock
  lain butuh resampling.

## Fase 3 (opsional): Driver libsigrok native `sump3`

- [ ] Driver C di `libsigrok/src/hardware/sump3/`: `conn=tcp/<host>/21567` ke bd_server,
      atau langsung serial MesaBus tanpa bd_server.
- [ ] Device scan → `rd_cfg`, channel group per pod, **nama channel dari View ROM**.
- [ ] Opsi perangkat: posisi trigger, tipe trigger SUMP3, pilihan pod.
- [ ] Data dikirim sebagai paket logic sigrok hasil ekspansi RLE, tanpa batas 32 channel.
- [ ] Build PulseView + libsigrok kustom (Windows: `sigrok-util` cross-build MXE), atau
      upstream ke proyek sigrok.

## Fase 4 (opsional): Pengembangan hardware yang membantu

- [ ] Ethernet sebagai pengganti UART: `bd_server.py` jalan di Linux board S9, ke FPGA
      lewat AXI (lebih cepat dari 921600 baud).
- [ ] Kedalaman RLE lebih besar (masih ada sekitar 50 BRAM36 kosong di XC7Z010).
- [ ] Channel tambahan dari konektor J2–J4 (12 I/O).
- [ ] Capture 200 MHz (FCLK0/MMCM), atau pod tanpa RLE untuk sinyal yang sangat rapat.

---

## Ringkasan prioritas

| # | Item | Hasil yang terasa |
|---|---|---|
| 1 | Fase 1.1–1.5 (client) | Fondasi; bisa diuji terhadap hasil `sump3.py` |
| 2 | Fase 1.6 (CLI capture → `.sr`) | Capture → PulseView tanpa GUI `sump3.py` |
| 3 | Prototipe Fase 2.3 (scan via com0com) | Kepastian PulseView bisa melihat bridge |
| 4 | Fase 2.1–2.2 (bridge lengkap) | **Run / trigger langsung dari PulseView** |
| 5 | Fase 3 | Integrasi native, tanpa batasan OLS |
