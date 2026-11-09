// SPDX-License-Identifier: Apache-2.0
#include <dirent.h>
#include <stdlib.h>
#include <sys/stat.h>
#include <unistd.h>

#include "bridge_proto.h"
#include "check.h"
#include "record_store.h"

static hold_t g_hold;  // about 35 KB: static, like on the device

static const char *kEpoch = "1a2b3c4d";

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

static bool make_dir(char out[64]) {
    snprintf(out, 64, "/tmp/rstore_XXXXXX");
    return mkdtemp(out) != NULL;
}

static void fill_hold(uint64_t held_at, size_t n) {
    g_hold.held_at_ms = held_at;
    g_hold.n = n;
    for (size_t i = 0; i < n; i++) {
        g_hold.lines[i].at_ms = held_at - (n - 1 - i) * 200;
        snprintf(g_hold.lines[i].line, sizeof g_hold.lines[i].line,
                 "He   0.5 %%  O2  19.8 %%  Ti  22.%zu ~C  1029.5 hPa   2026/11/03 15:20:%02zu", i % 10,
                 i % 60);
    }
}

typedef struct {
    int calls;
    uint32_t last;
    bool tmp_existed_at_call;
    const char *dir;
} spy_t;

static void persist_spy(uint32_t next, void *ctx) {
    spy_t *s = ctx;
    s->calls++;
    s->last = next;
    char p[160];
    snprintf(p, sizeof p, "%s/%s-%u.tmp", s->dir, kEpoch, (unsigned)(next - 1));
    s->tmp_existed_at_call = access(p, F_OK) == 0;
}

static void persist_noop(uint32_t next, void *ctx) { (void)next; (void)ctx; }

static void touch(const char *dir, const char *name, const char *content) {
    char p[160];
    snprintf(p, sizeof p, "%s/%s", dir, name);
    FILE *f = fopen(p, "w");
    if (f != NULL) {
        fputs(content, f);
        fclose(f);
    }
}

static void test_put_and_read(void) {
    char dir[64];
    CHECK(make_dir(dir));
    record_store_t s;
    CHECK(record_store_open(&s, dir, kEpoch, 1));
    CHECK(s.count == 0 && !record_store_full(&s));

    fill_hold(60000, 4);
    record_meta_t m = {.boot = 3, .up_ms = 60000, .wall_ms = 0, .live = true};
    spy_t spy = {.dir = dir};
    char rid[24];
    CHECK(record_store_put(&s, &m, &g_hold, persist_spy, &spy, rid));
    CHECK_STR_EQ(rid, "1a2b3c4d-1");
    CHECK(spy.calls == 1 && spy.last == 2 && !spy.tmp_existed_at_call);
    CHECK(s.count == 1);

    FILE *f = record_store_read(&s, rid);
    CHECK(f != NULL);
    if (f != NULL) {
        char got[256], want[256];
        CHECK(fgets(got, sizeof got, f) != NULL);
        proto_fmt_rec(want, sizeof want, rid, 3, 60000, 0, true);
        strcat(want, "\n");
        CHECK_STR_EQ(got, want);
        for (size_t i = 0; i < g_hold.n; i++) {
            CHECK(fgets(got, sizeof got, f) != NULL);
            int64_t off = (int64_t)g_hold.lines[i].at_ms - (int64_t)g_hold.held_at_ms;
            CHECK(off <= 0);
            proto_fmt_w(want, sizeof want, off, g_hold.lines[i].line);
            strcat(want, "\n");
            CHECK_STR_EQ(got, want);
            if (i == g_hold.n - 1) CHECK(strncmp(got, "W 0 ", 4) == 0);
        }
        CHECK(fgets(got, sizeof got, f) != NULL);
        proto_fmt_h(want, sizeof want, g_hold.lines[g_hold.n - 1].line);
        strcat(want, "\n");
        CHECK_STR_EQ(got, want);
        CHECK(fgets(got, sizeof got, f) == NULL);
        fclose(f);
    }

    // ids go on counting
    CHECK(record_store_put(&s, &m, &g_hold, persist_noop, NULL, rid));
    CHECK_STR_EQ(rid, "1a2b3c4d-2");
    CHECK(record_store_put(&s, &m, &g_hold, persist_noop, NULL, rid));
    CHECK_STR_EQ(rid, "1a2b3c4d-3");
    rm_rf(dir);
}

static void test_full_and_delete(void) {
    char dir[64];
    CHECK(make_dir(dir));
    record_store_t s;
    CHECK(record_store_open(&s, dir, kEpoch, 1));
    fill_hold(10000, 2);
    record_meta_t m = {.boot = 1, .up_ms = 10000, .wall_ms = 0, .live = false};
    char rid[24];
    int ok = 0;
    for (int i = 0; i < RECORD_STORE_MAX; i++) ok += record_store_put(&s, &m, &g_hold, persist_noop, NULL, rid);
    CHECK(ok == RECORD_STORE_MAX);
    CHECK(record_store_full(&s));
    CHECK(!record_store_put(&s, &m, &g_hold, persist_noop, NULL, rid));
    CHECK(s.count == RECORD_STORE_MAX);

    CHECK(record_store_oldest(&s, rid));
    CHECK_STR_EQ(rid, "1a2b3c4d-1");
    CHECK(record_store_delete(&s, "1a2b3c4d-1"));
    CHECK(!record_store_full(&s));
    CHECK(record_store_oldest(&s, rid));
    CHECK_STR_EQ(rid, "1a2b3c4d-2");  // lowest counter, not the first file listed
    CHECK(record_store_put(&s, &m, &g_hold, persist_noop, NULL, rid));
    CHECK_STR_EQ(rid, "1a2b3c4d-51");

    CHECK(!record_store_delete(&s, "1a2b3c4d-1"));   // already gone
    CHECK(!record_store_delete(&s, "1a2b3c4d-999"));  // never there
    CHECK(!record_store_delete(&s, "../etc/passwd"));
    CHECK(!record_store_delete(&s, ""));
    CHECK(record_store_read(&s, "../x") == NULL);
    CHECK(record_store_read(&s, "1a2b3c4d-1") == NULL);
    rm_rf(dir);
}

static void test_oldest(void) {
    char dir[64];
    CHECK(make_dir(dir));
    record_store_t s;
    char rid[24];
    CHECK(record_store_open(&s, dir, kEpoch, 1));
    CHECK(!record_store_oldest(&s, rid));  // empty
    // counters 9 and 10 sort 10 before 9 as text, but 9 is older
    touch(dir, "1a2b3c4d-10.rec", "x\n");
    touch(dir, "1a2b3c4d-9.rec", "x\n");
    touch(dir, "deadbeef-2.rec", "x\n");  // an older epoch
    CHECK(record_store_open(&s, dir, kEpoch, 1));
    CHECK(s.count == 3);
    CHECK(s.next_counter == 11);  // past the highest on disk, whatever was persisted
    CHECK(record_store_oldest(&s, rid));
    CHECK_STR_EQ(rid, "1a2b3c4d-9");
    CHECK(record_store_delete(&s, "1a2b3c4d-9"));
    CHECK(record_store_delete(&s, "1a2b3c4d-10"));
    CHECK(record_store_oldest(&s, rid));  // only the other epoch is left
    CHECK_STR_EQ(rid, "deadbeef-2");
    rm_rf(dir);
}

static void test_torn_tmp(void) {
    char dir[64];
    CHECK(make_dir(dir));
    // A put of counter 7 persisted 8 before it wrote; the power went mid-write.
    touch(dir, "1a2b3c4d-7.tmp", "REC 1a2b3c4d-7 boot=1 up=1 wall=0 live=0\nW -4");
    record_store_t s;
    CHECK(record_store_open(&s, dir, kEpoch, 8));
    char p[160];
    snprintf(p, sizeof p, "%s/1a2b3c4d-7.tmp", dir);
    CHECK(access(p, F_OK) != 0);  // gone
    CHECK(s.count == 0);
    char rid[24];
    CHECK(!record_store_oldest(&s, rid));

    fill_hold(10000, 2);
    record_meta_t m = {.boot = 2, .up_ms = 10000, .wall_ms = 0, .live = false};
    spy_t spy = {.dir = dir};
    CHECK(record_store_put(&s, &m, &g_hold, persist_spy, &spy, rid));
    CHECK_STR_EQ(rid, "1a2b3c4d-8");
    CHECK(spy.calls == 1 && spy.last == 9 && !spy.tmp_existed_at_call);

    // Even when the persisted counter is behind (NVS lost the write), the
    // counter in the torn file's name is not reused.
    touch(dir, "1a2b3c4d-20.tmp", "REC");
    CHECK(record_store_open(&s, dir, kEpoch, 3));
    CHECK(s.next_counter == 21);
    CHECK(s.count == 1);  // the finished -8 record stays
    rm_rf(dir);
}

static void test_bad_dir(void) {
    record_store_t s;
    CHECK(!record_store_open(&s, "/nonexistent/dir/for/test", kEpoch, 1));
}

TEST_SUITE(test_record_store) {
    test_put_and_read();
    test_full_and_delete();
    test_oldest();
    test_torn_tmp();
    test_bad_dir();
}
