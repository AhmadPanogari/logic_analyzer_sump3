/* ols_multirun: several acquisitions on one open OLS device, like pressing
 * Run repeatedly in PulseView ( the port stays open between runs ).
 *   ols_multirun <conn> [runs] [samples] [loglevel]
 * Exit status 0 when every run returns samples*2 bytes ( 16 channels ). */
#include <stdio.h>
#include <stdlib.h>
#include <glib.h>
#include <libsigrok/libsigrok.h>

static uint64_t total;
static void cb(const struct sr_dev_inst *sdi, const struct sr_datafeed_packet *p, void *d)
{
	(void)sdi; (void)d;
	if (p->type == SR_DF_LOGIC)
		total += ((const struct sr_datafeed_logic *)p->payload)->length;
}

int main(int argc, char **argv)
{
	struct sr_context *ctx;
	struct sr_dev_driver **drivers, *drv = NULL;
	struct sr_session *sess;
	GSList *opts = NULL, *devs;
	struct sr_dev_inst *sdi;
	struct sr_config *src;
	int i, fail = 0, runs = argc > 2 ? atoi(argv[2]) : 2;
	uint64_t samples = argc > 3 ? strtoull(argv[3], NULL, 0) : 4096;

	sr_init(&ctx);
	sr_log_loglevel_set(argc > 4 ? atoi(argv[4]) : 2);
	drivers = sr_driver_list(ctx);
	for (i = 0; drivers[i]; i++)
		if (!g_strcmp0(drivers[i]->name, "ols")) drv = drivers[i];
	sr_driver_init(ctx, drv);
	src = g_malloc0(sizeof(*src));
	src->key = SR_CONF_CONN; src->data = g_variant_new_string(argv[1]);
	opts = g_slist_append(opts, src);
	devs = sr_driver_scan(drv, opts);
	if (!devs) { printf("no device\n"); return 1; }
	sdi = devs->data;
	sr_session_new(ctx, &sess);
	sr_session_datafeed_callback_add(sess, cb, NULL);
	sr_dev_open(sdi);
	sr_session_dev_add(sess, sdi);
	sr_config_set(sdi, NULL, SR_CONF_SAMPLERATE, g_variant_new_uint64(1000000));
	sr_config_set(sdi, NULL, SR_CONF_LIMIT_SAMPLES, g_variant_new_uint64(samples));
	for (i = 0; i < runs; i++) {
		total = 0;
		int r = sr_session_start(sess);
		if (r == SR_OK) r = sr_session_run(sess);
		printf("run %d: rc=%d logic bytes=%llu ( expect %llu )\n", i + 1, r,
		       (unsigned long long)total, (unsigned long long)(samples * 2));
		fflush(stdout);
		if (r != SR_OK || total != samples * 2)
			fail = 1;
	}
	sr_dev_close(sdi);
	sr_exit(ctx);
	return fail;
}
