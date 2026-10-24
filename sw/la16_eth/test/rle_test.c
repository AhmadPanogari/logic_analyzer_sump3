/*
 * Host check of the upload encoder ( make_block() in la16_server.c ): raw,
 * RLE and auto frames must decode back to the ring, also across the ring
 * end, at the 65536 run limit and for data RLE cannot shrink.
 *
 *   gcc -O2 -Wall -Ishim -I.. -o rle_test rle_test.c && ./rle_test
 *   ( Windows: MinGW gcc, same command, rle_test.exe )
 *
 * ddr_base is a 32 bit address, so the ring is mapped at a fixed low address.
 */
#ifdef _WIN32
#include <windows.h>
#else
#include <sys/mman.h>
#endif
#include <stdio.h>
#include <stdlib.h>
#include "la16_server.c"

u32 Xil_In32(uintptr_t a) { (void)a; return 0; }
void Xil_Out32(uintptr_t a, u32 v) { (void)a; (void)v; }
void XTime_GetTime(XTime *t) { *t = 0; }
struct tcp_pcb *tcp_new_ip_type(int t) { (void)t; return NULL; }
err_t tcp_bind(struct tcp_pcb *p, const void *i, uint16_t o) { (void)p; (void)i; (void)o; return 0; }
struct tcp_pcb *tcp_listen(struct tcp_pcb *p) { return p; }
void tcp_accept(struct tcp_pcb *p, tcp_accept_fn f) { (void)p; (void)f; }
void tcp_recv(struct tcp_pcb *p, tcp_recv_fn f) { (void)p; (void)f; }
void tcp_err(struct tcp_pcb *p, tcp_err_fn f) { (void)p; (void)f; }
void tcp_arg(struct tcp_pcb *p, void *a) { (void)p; (void)a; }
void tcp_nagle_disable(struct tcp_pcb *p) { (void)p; }
void tcp_nagle_enable(struct tcp_pcb *p) { (void)p; }
uint32_t tcp_sndbuf(struct tcp_pcb *p) { (void)p; return 0; }
uint32_t tcp_sndqueuelen(struct tcp_pcb *p) { (void)p; return 0; }
err_t tcp_write(struct tcp_pcb *p, const void *d, uint32_t l, uint8_t f) { (void)p; (void)d; (void)l; (void)f; return 0; }
err_t tcp_output(struct tcp_pcb *p) { (void)p; return 0; }
void tcp_recved(struct tcp_pcb *p, uint16_t l) { (void)p; (void)l; }
err_t tcp_close(struct tcp_pcb *p) { (void)p; return 0; }
void tcp_abort(struct tcp_pcb *p) { (void)p; }
uint8_t pbuf_free(struct pbuf *p) { (void)p; return 0; }

#define RING_BASE 0x10000000u
static u16 *ring;

static int run(const char *name, u32 ring_n, u32 start, u32 total, int fmt,
	       u16 (*gen)(u32 i))
{
	static u8 buf[MAX_PAYLOAD + 5];
	u16 *want = malloc(total * 2);
	u32 i, got = 0, frames = 0, raw = 0, rle = 0, bytes = 0;

	for (i = 0; i < total; i++) {
		want[i] = gen(i);
		ring[(start + i) % ring_n] = want[i];
	}
	ddr_base = RING_BASE; up_ring = ring_n; up_start = start;
	cfg_total = total; cfg_fmt = fmt; up_sent = 0;
	crc8_init();
	while (up_sent < cfg_total) {
		u32 n = make_block(buf), len = buf[2] | buf[3] << 8, first;
		const u8 *p = &buf[4];

		frames++; bytes += n;
		if (n != len + 5 || len > MAX_PAYLOAD || crc8(0, &buf[1], 3 + len) != buf[4 + len]) {
			printf("%s: bad frame %u\n", name, frames); return 1;
		}
		first = rl32(p);
		if (first != got) { printf("%s: frame %u starts at %u, want %u\n", name, frames, first, got); return 1; }
		if (buf[1] == R_DATA) {
			raw++;
			for (i = 4; i < len; i += 2, got++)
				if ((p[i] | p[i + 1] << 8) != want[got]) { printf("%s: raw mismatch at %u\n", name, got); return 1; }
		} else if (buf[1] == R_DATA_RLE) {
			rle++;
			for (i = 4; i < len; i += 4) {
				u32 v = p[i] | p[i + 1] << 8, c = (p[i + 2] | p[i + 3] << 8) + 1;
				while (c--) {
					if (got >= total || v != want[got]) { printf("%s: rle mismatch at %u\n", name, got); return 1; }
					got++;
				}
			}
		} else { printf("%s: frame type 0x%02x\n", name, buf[1]); return 1; }
	}
	if (got != total) { printf("%s: %u of %u samples\n", name, got, total); return 1; }
	printf("%-22s ok: %8u samples, %6u frames ( %u raw, %u RLE ), %.1f%% of raw size\n",
	       name, total, frames, raw, rle, 100.0 * bytes / (total * 2.0 + (total + 509) / 510 * 9));
	free(want);
	return 0;
}

static u16 g_const(u32 i) { (void)i; return 0x1234; }
static u16 g_count(u32 i) { return (u16)i; }
static u16 g_slow(u32 i) { return (u16)(i / 1000); }		/* runs of 1000 */
static u16 g_uart(u32 i) { return (i % 20000) < 17 ? 0 : 1; }	/* short pulses */
static u16 g_pairs(u32 i) { return (u16)(i / 2); }		/* runs of 2: RLE = raw size */
static u16 g_mixed(u32 i) { return i < 300000 ? (u16)(i * 7) : (u16)(i / 5000); }

int main(void)
{
	int bad = 0;

#ifdef _WIN32
	ring = VirtualAlloc((void *)(uintptr_t)RING_BASE, 64u << 20, MEM_RESERVE | MEM_COMMIT, PAGE_READWRITE);
#else
	ring = mmap((void *)(uintptr_t)RING_BASE, 64u << 20, PROT_READ | PROT_WRITE,
		    MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
#endif
	if (ring != (void *)(uintptr_t)RING_BASE) { printf("no memory at 0x%08x\n", RING_BASE); return 2; }
	bad |= run("auto const", 1 << 24, 12345, 10000000, FMT_AUTO, g_const);
	bad |= run("auto const wrap", 1 << 20, 1000000, 1 << 20, FMT_AUTO, g_const);
	bad |= run("auto count ( raw )", 1 << 22, 4000000, 3000000, FMT_AUTO, g_count);
	bad |= run("auto runs 1000", 1 << 22, 4194000, 4000000, FMT_AUTO, g_slow);
	bad |= run("auto uart-like", 1 << 23, 100, 8000000, FMT_AUTO, g_uart);
	bad |= run("auto runs of 2", 1 << 20, 7, 1000000, FMT_AUTO, g_pairs);
	bad |= run("auto mixed", 1 << 22, 3, 4000000, FMT_AUTO, g_mixed);
	bad |= run("rle count", 1 << 20, 999999, 1000000, FMT_RLE, g_count);
	bad |= run("raw uart-like", 1 << 23, 5, 2000000, FMT_RAW, g_uart);
	bad |= run("auto 1 sample", 1 << 20, 1048575, 1, FMT_AUTO, g_count);
	bad |= run("rle 16 samples wrap", 16, 9, 16, FMT_RLE, g_slow);
	bad |= run("auto const odd start", 1 << 22, 4194301, 4000000, FMT_AUTO, g_const);
	bad |= run("auto runs 1000 odd", (1 << 22) - 3, 4194299, 4000000, FMT_AUTO, g_slow);
	bad |= run("auto max runs", 1 << 22, 1, 3000000, FMT_AUTO, g_const);
	bad |= run("rle uart odd ring", 1000003, 999998, 1000000, FMT_RLE, g_uart);
	printf(bad ? "FAILED\n" : "all passed\n");
	return bad;
}
