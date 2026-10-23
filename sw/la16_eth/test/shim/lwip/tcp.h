/* Host test: the subset of the lwIP raw TCP API la16_server.c uses, on top of
 * POSIX sockets ( host_test.c ). Not lwIP: only for protocol logic tests. */
#ifndef SHIM_LWIP_TCP_H
#define SHIM_LWIP_TCP_H
#include <stdint.h>
#include "lwip/err.h"
struct pbuf { struct pbuf *next; void *payload; uint16_t len, tot_len; };
struct tcp_pcb { int fd; };
typedef err_t (*tcp_accept_fn)(void *arg, struct tcp_pcb *newpcb, err_t err);
typedef err_t (*tcp_recv_fn)(void *arg, struct tcp_pcb *tpcb, struct pbuf *p, err_t err);
typedef void (*tcp_err_fn)(void *arg, err_t err);
#define IPADDR_TYPE_ANY 46
#define IP_ANY_TYPE NULL
#define TCP_WRITE_FLAG_COPY 1
#define TCP_SND_QUEUELEN 64
struct tcp_pcb *tcp_new_ip_type(int type);
err_t tcp_bind(struct tcp_pcb *pcb, const void *ip, uint16_t port);
struct tcp_pcb *tcp_listen(struct tcp_pcb *pcb);
void tcp_accept(struct tcp_pcb *pcb, tcp_accept_fn fn);
void tcp_recv(struct tcp_pcb *pcb, tcp_recv_fn fn);
void tcp_err(struct tcp_pcb *pcb, tcp_err_fn fn);
void tcp_arg(struct tcp_pcb *pcb, void *arg);
void tcp_nagle_disable(struct tcp_pcb *pcb);
void tcp_nagle_enable(struct tcp_pcb *pcb);
uint32_t tcp_sndbuf(struct tcp_pcb *pcb);
uint32_t tcp_sndqueuelen(struct tcp_pcb *pcb);
err_t tcp_write(struct tcp_pcb *pcb, const void *data, uint32_t len, uint8_t flags);
err_t tcp_output(struct tcp_pcb *pcb);
void tcp_recved(struct tcp_pcb *pcb, uint16_t len);
err_t tcp_close(struct tcp_pcb *pcb);
void tcp_abort(struct tcp_pcb *pcb);
uint8_t pbuf_free(struct pbuf *p);
#endif
