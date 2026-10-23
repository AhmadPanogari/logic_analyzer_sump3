/*
 * Host test of la16_server.c: the server code runs unchanged on Linux on top
 * of a POSIX socket shim ( shim/lwip/tcp.h ) and a model of the PL:
 *   - la16_regs at 0x43C0_0000 ( Xil_In32 / Xil_Out32 )
 *   - the DDR ring at 0x0200_0000 ( mmap at that address )
 * A capture "runs" for ~20 ms per 100k samples ( STATUS 1 -> 2 -> 3 -> 5 ),
 * then the ring holds a 16 bit counter stepping by divider + 1, rotated by a
 * random start index, with the trigger condition true exactly at `pre`
 * ( level value, or rising / falling edge of the lowest set edge bit ).
 *
 *   host_test                 then: sigrok-cli -d la16:conn=tcp-raw/127.0.0.1/5555 ...
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>
#include "xil_io.h"
#include "xtime_l.h"
#include "lwip/tcp.h"

void print_app_header(void);
int start_application(void);
int transfer_data(void);

#define DDR_BASE 0x02000000u
#define MAX_SAMPLES (4u << 20)
static uint16_t *ddr;
static uint32_t r_div, r_total, r_pre, r_lvl, r_edge, r_cfg, r_start, r_ring;
static int cap_state, cap_ovf;
static uint64_t cap_t0;
static int listen_fd = -1;
static struct tcp_pcb listen_pcb, conn_pcb;
static tcp_accept_fn accept_fn;
static tcp_recv_fn recv_fn;
static tcp_err_fn err_fn;
static int connected;

static uint64_t now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ull + ts.tv_nsec;
}

void XTime_GetTime(XTime *t) { *t = now_ns(); }

static void fill_ring(void)
{
	uint32_t step = r_div + 1, i, k, tlm = r_lvl & 0xFFFF, tlv = r_lvl >> 16;
	uint32_t trm = r_edge & 0xFFFF, tfm = r_edge >> 16, target;

	r_ring = (r_total + 63) & ~63u;
	r_start = (uint32_t)rand() % r_ring;
	if (tlm)
		target = tlv;
	else if (trm)
		target = trm & -trm;			/* lowest rising bit just set */
	else if (tfm)
		target = 0;				/* previous sample has the bit */
	else
		target = 0x1000;
	k = (target - r_pre * step) & 0xFFFF;		/* sample[pre] == target */
	for (i = 0; i < r_ring; i++)			/* junk outside the result */
		ddr[i] = 0xDEAD;
	for (i = 0; i < r_total; i++)
		ddr[(r_start + i) % r_ring] = (uint16_t)(k + i * step);
}

static int cap_status(void)
{
	uint64_t ms;

	if (!cap_state)
		return 0;
	ms = (now_ns() - cap_t0) / 1000000;
	if (cap_state == 5)
		return 5;
	if (ms < 10)
		return r_pre ? 1 : 2;
	if (ms < 20)
		return 2;
	if (ms < 20 + r_total / 5000)
		return 3;
	fill_ring();
	cap_state = 5;
	return 5;
}

u32 Xil_In32(uintptr_t a)
{
	int s;

	switch (a - 0x43C00000u) {
	case 0x00: return 0x4C413136;
	case 0x08: return r_div;
	case 0x0C: return r_total;
	case 0x10: return r_pre;
	case 0x1C:
		s = cap_status();
		return s | (s == 5 ? 0x08 : 0) | 0x10 | (cap_ovf ? 0x20 : 0);
	case 0x20: return cap_status() == 5 ? r_total : r_total / 2;
	case 0x24: return r_start;
	case 0x28: return r_ring;
	case 0x2C: return DDR_BASE;
	case 0x30: return MAX_SAMPLES;
	case 0x34: return r_cfg;
	case 0x38: return 200000000;
	default: return 0;
	}
}

void Xil_Out32(uintptr_t a, u32 v)
{
	switch (a - 0x43C00000u) {
	case 0x04:
		if (v & 1) { cap_state = 1; cap_t0 = now_ns(); }
		if (v & 2) cap_state = 0;
		break;
	case 0x08: r_div = v; break;
	case 0x0C: r_total = v; break;
	case 0x10: r_pre = v; break;
	case 0x14: r_lvl = v; break;
	case 0x18: r_edge = v; break;
	case 0x34: r_cfg = v; break;
	default: break;
	}
}

/* --- socket shim --- */
struct tcp_pcb *tcp_new_ip_type(int type) { (void)type; return &listen_pcb; }
err_t tcp_bind(struct tcp_pcb *pcb, const void *ip, uint16_t port)
{
	struct sockaddr_in sa = { .sin_family = AF_INET, .sin_port = htons(port) };
	int one = 1;
	(void)ip;
	pcb->fd = socket(AF_INET, SOCK_STREAM, 0);
	setsockopt(pcb->fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
	sa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	return bind(pcb->fd, (struct sockaddr *)&sa, sizeof(sa)) ? ERR_MEM : ERR_OK;
}
struct tcp_pcb *tcp_listen(struct tcp_pcb *pcb) { listen(pcb->fd, 4); listen_fd = pcb->fd; return pcb; }
void tcp_accept(struct tcp_pcb *pcb, tcp_accept_fn fn) { (void)pcb; accept_fn = fn; }
void tcp_recv(struct tcp_pcb *pcb, tcp_recv_fn fn) { (void)pcb; recv_fn = fn; }
void tcp_err(struct tcp_pcb *pcb, tcp_err_fn fn) { (void)pcb; err_fn = fn; }
void tcp_arg(struct tcp_pcb *pcb, void *arg) { (void)pcb; (void)arg; }
void tcp_nagle_disable(struct tcp_pcb *pcb) { int one = 1; setsockopt(pcb->fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one)); }
void tcp_nagle_enable(struct tcp_pcb *pcb) { int zero = 0; setsockopt(pcb->fd, IPPROTO_TCP, TCP_NODELAY, &zero, sizeof(zero)); }
uint32_t tcp_sndbuf(struct tcp_pcb *pcb) { (void)pcb; return 32768; }
uint32_t tcp_sndqueuelen(struct tcp_pcb *pcb) { (void)pcb; return 0; }
err_t tcp_write(struct tcp_pcb *pcb, const void *data, uint32_t len, uint8_t flags)
{
	const uint8_t *d = data;
	(void)flags;
	while (len) {
		ssize_t n = send(pcb->fd, d, len, MSG_NOSIGNAL);
		if (n < 0) {
			if (errno == EAGAIN) { usleep(100); continue; }
			return ERR_MEM;
		}
		d += n; len -= n;
	}
	return ERR_OK;
}
err_t tcp_output(struct tcp_pcb *pcb) { (void)pcb; return ERR_OK; }
void tcp_recved(struct tcp_pcb *pcb, uint16_t len) { (void)pcb; (void)len; }
err_t tcp_close(struct tcp_pcb *pcb) { close(pcb->fd); connected = 0; return ERR_OK; }
void tcp_abort(struct tcp_pcb *pcb) { close(pcb->fd); connected = 0; }
uint8_t pbuf_free(struct pbuf *p) { (void)p; return 1; }

int main(void)
{
	int port = 5555;			/* LA16_TCP_PORT */
	uint8_t buf[4096];

	ddr = mmap((void *)(uintptr_t)DDR_BASE, MAX_SAMPLES * 2 + 4096, PROT_READ | PROT_WRITE,
		   MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED_NOREPLACE, -1, 0);
	if (ddr == MAP_FAILED || (uintptr_t)ddr != DDR_BASE) {
		perror("mmap DDR model at 0x02000000");
		return 1;
	}
	srand(1);
	print_app_header();
	if (start_application()) {		/* binds and listens on 5555 */
		fprintf(stderr, "start failed\n");
		return 1;
	}
	printf("LISTENING %d\n", port);
	fflush(stdout);
	for (;;) {
		struct pollfd pf = { .fd = connected ? conn_pcb.fd : listen_fd, .events = POLLIN };

		if (poll(&pf, 1, 1) > 0) {
			if (!connected) {
				conn_pcb.fd = accept(listen_fd, NULL, NULL);
				connected = 1;
				accept_fn(NULL, &conn_pcb, ERR_OK);
			} else {
				ssize_t n = recv(conn_pcb.fd, buf, sizeof(buf), 0);
				if (n <= 0) {
					recv_fn(NULL, &conn_pcb, NULL, ERR_OK);
				} else {
					struct pbuf p = { NULL, buf, (uint16_t)n, (uint16_t)n };
					recv_fn(NULL, &conn_pcb, &p, ERR_OK);
				}
			}
		}
		transfer_data();
	}
}
