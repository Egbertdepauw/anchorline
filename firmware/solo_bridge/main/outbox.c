// SPDX-License-Identifier: Apache-2.0
#include "outbox.h"

#include <string.h>

void outbox_init(outbox_t *o) { memset(o, 0, sizeof *o); }

void outbox_on_disconnect(outbox_t *o) {
    o->ready = false;
    o->in_flight = false;
}

void outbox_on_time(outbox_t *o) { o->ready = true; }

const char *outbox_next(outbox_t *o, const record_store_t *s) {
    if (!o->ready || o->in_flight) return NULL;
    if (!record_store_oldest(s, o->rid)) return NULL;
    o->in_flight = true;
    return o->rid;
}

void outbox_on_send_failed(outbox_t *o) { o->in_flight = false; }

void outbox_on_ack(outbox_t *o, record_store_t *s, const char *rid) {
    record_store_delete(s, rid);
    if (o->in_flight && strcmp(o->rid, rid) == 0) o->in_flight = false;
}
