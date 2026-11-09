// SPDX-License-Identifier: Apache-2.0
#include <dirent.h>
#include <stdlib.h>
#include <unistd.h>

#include "check.h"
#include "outbox.h"

static hold_t g_hold;

static void persist_noop(uint32_t next, void *ctx) { (void)next; (void)ctx; }

static void rm_rf(const char *dir) {
    DIR *d = opendir(dir);
    if (d == NULL) return;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        if (e->d_name[0] == '.') continue;
        char p[256];
        snprintf(p, sizeof p, "%s/%s", dir, e->d_name);
        unlink(p);
    }
    closedir(d);
    rmdir(dir);
}

static void add_records(record_store_t *s, int n) {
    g_hold.held_at_ms = 5000;
    g_hold.n = 1;
    g_hold.lines[0].at_ms = 5000;
    strcpy(g_hold.lines[0].line, "He   0.5 %  O2  19.8 %  Ti  22.0 ~C  1029.5 hPa   2026/11/03 15:20:00");
    record_meta_t m = {.boot = 1, .up_ms = 5000, .wall_ms = 0, .live = false};
    char rid[24];
    for (int i = 0; i < n; i++) CHECK(record_store_put(s, &m, &g_hold, persist_noop, NULL, rid));
}

TEST_SUITE(test_outbox) {
    char dir[64] = "/tmp/outbox_XXXXXX";
    CHECK(mkdtemp(dir) != NULL);
    record_store_t s;
    CHECK(record_store_open(&s, dir, "1a2b3c4d", 1));
    add_records(&s, 3);

    outbox_t o;
    outbox_init(&o);
    // nothing is sent before TIME
    CHECK(outbox_next(&o, &s) == NULL);

    // after TIME the oldest comes, and NULL follows until its ACK
    outbox_on_time(&o);
    const char *r = outbox_next(&o, &s);
    CHECK(r != NULL);
    if (r != NULL) CHECK_STR_EQ(r, "1a2b3c4d-1");
    CHECK(outbox_next(&o, &s) == NULL);
    CHECK(outbox_next(&o, &s) == NULL);

    // an ACK for another stored rid deletes that one and leaves -1 in flight
    outbox_on_ack(&o, &s, "1a2b3c4d-3");
    CHECK(s.count == 2);
    CHECK(o.in_flight);
    CHECK(outbox_next(&o, &s) == NULL);

    // after the ACK the next rid comes
    outbox_on_ack(&o, &s, "1a2b3c4d-1");
    CHECK(s.count == 1 && !o.in_flight);
    r = outbox_next(&o, &s);
    CHECK(r != NULL);
    if (r != NULL) CHECK_STR_EQ(r, "1a2b3c4d-2");
    outbox_on_ack(&o, &s, "1a2b3c4d-2");
    CHECK(s.count == 0);
    CHECK(outbox_next(&o, &s) == NULL);  // empty

    // an ACK for something that is not stored changes nothing
    outbox_on_ack(&o, &s, "1a2b3c4d-77");
    CHECK(s.count == 0 && !o.in_flight);

    // disconnect mid-send resends the same record from REC
    outbox_init(&o);
    add_records(&s, 2);  // -4 and -5
    outbox_on_time(&o);
    r = outbox_next(&o, &s);
    CHECK(r != NULL);
    if (r != NULL) CHECK_STR_EQ(r, "1a2b3c4d-4");
    outbox_on_disconnect(&o);
    CHECK(!o.ready && !o.in_flight);
    CHECK(outbox_next(&o, &s) == NULL);  // no TIME yet on the new connection
    outbox_on_time(&o);
    r = outbox_next(&o, &s);
    CHECK(r != NULL);
    if (r != NULL) CHECK_STR_EQ(r, "1a2b3c4d-4");

    // a failed send (the link ran out of buffers) is tried again from REC
    outbox_on_send_failed(&o);
    CHECK(!o.in_flight && o.ready);
    r = outbox_next(&o, &s);
    CHECK(r != NULL);
    if (r != NULL) CHECK_STR_EQ(r, "1a2b3c4d-4");

    // an ACK that arrives for a record deleted meanwhile is harmless
    outbox_on_ack(&o, &s, "1a2b3c4d-4");
    outbox_on_ack(&o, &s, "1a2b3c4d-4");
    CHECK(s.count == 1);
    rm_rf(dir);
}
