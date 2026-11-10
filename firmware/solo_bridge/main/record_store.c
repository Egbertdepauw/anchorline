// SPDX-License-Identifier: Apache-2.0
#include "record_store.h"

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <inttypes.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "bridge_proto.h"

#define NAME_MAX_LEN 48

// A rid is <epoch>-<counter>: letters, digits and '-' only, so it can never
// name another directory.
static bool rid_ok(const char *rid) {
    size_t n = rid == NULL ? 0 : strlen(rid);
    if (n == 0 || n > 23) return false;
    for (size_t i = 0; i < n; i++)
        if (!isalnum((unsigned char)rid[i]) && rid[i] != '-') return false;
    return true;
}

static bool path_for(const record_store_t *s, const char *rid, const char *ext, char *out, size_t cap) {
    int n = snprintf(out, cap, "%s/%s.%s", s->dir, rid, ext);
    return n > 0 && (size_t)n < cap;
}

// Splits "<epoch>-<counter>.<ext>" into epoch (<= 8 chars kept as given) and
// counter. False for any other name.
static bool parse_name(const char *name, const char *ext, char epoch[24], uint32_t *counter) {
    size_t len = strlen(name), elen = strlen(ext);
    if (len <= elen + 1 || strcmp(name + len - elen, ext) != 0 || name[len - elen - 1] != '.') return false;
    char base[NAME_MAX_LEN];
    size_t blen = len - elen - 1;
    if (blen >= sizeof base) return false;
    memcpy(base, name, blen);
    base[blen] = '\0';
    char *dash = strrchr(base, '-');
    if (dash == NULL || dash == base || dash[1] == '\0') return false;
    char *end;
    errno = 0;
    unsigned long long c = strtoull(dash + 1, &end, 10);
    if (*end != '\0' || errno != 0 || c > UINT32_MAX) return false;
    *dash = '\0';
    if (!rid_ok(base) || blen > 23) return false;
    strcpy(epoch, base);
    *counter = (uint32_t)c;
    return true;
}

bool record_store_open(record_store_t *s, const char *dir, const char *epoch,
                       uint32_t persisted_counter) {
    memset(s, 0, sizeof *s);
    if (strlen(dir) >= sizeof s->dir || strlen(epoch) >= sizeof s->epoch) return false;
    strcpy(s->dir, dir);
    strcpy(s->epoch, epoch);
    DIR *d = opendir(dir);
    if (d == NULL) return false;

    uint32_t next = persisted_counter > 0 ? persisted_counter : 1;
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        char ep[24];
        uint32_t c;
        if (parse_name(e->d_name, "tmp", ep, &c)) {
            char p[sizeof s->dir + sizeof e->d_name + 2];
            snprintf(p, sizeof p, "%s/%s", dir, e->d_name);
            unlink(p);  // a torn write: never sent
            if (strcmp(ep, epoch) == 0 && c >= next) next = c + 1;
        } else if (parse_name(e->d_name, "rec", ep, &c)) {
            s->count++;
            if (strcmp(ep, epoch) == 0 && c >= next) next = c + 1;
        }
    }
    closedir(d);
    s->next_counter = next;
    return true;
}

bool record_store_full(const record_store_t *s) { return s->count >= RECORD_STORE_MAX; }

bool record_store_put(record_store_t *s, const record_meta_t *m, const hold_t *h,
                      void (*persist)(uint32_t next, void *ctx), void *ctx, char rid_out[24]) {
    if (record_store_full(s) || h->n == 0) return false;
    uint32_t counter = s->next_counter;
    char rid[24];
    snprintf(rid, sizeof rid, "%s-%" PRIu32, s->epoch, counter);
    char tmp[160], fin[160];
    if (!path_for(s, rid, "tmp", tmp, sizeof tmp) || !path_for(s, rid, "rec", fin, sizeof fin)) return false;

    // The counter is spent from here on, whatever happens to the file.
    s->next_counter = counter + 1;
    if (persist != NULL) persist(counter + 1, ctx);

    FILE *f = fopen(tmp, "w");
    if (f == NULL) return false;
    char line[SOLO_LINE_MAX + 64];
    bool ok = proto_fmt_rec(line, sizeof line, rid, m->boot, m->up_ms, m->wall_ms, m->live) > 0 &&
              fprintf(f, "%s\n", line) > 0;
    for (size_t i = 0; ok && i < h->n; i++) {
        int64_t off = (int64_t)h->lines[i].at_ms - (int64_t)h->held_at_ms;
        ok = proto_fmt_w(line, sizeof line, off, h->lines[i].line) > 0 && fprintf(f, "%s\n", line) > 0;
    }
    ok = ok && proto_fmt_h(line, sizeof line, h->lines[h->n - 1].line) > 0 &&
         fprintf(f, "%s\n", line) > 0;
    ok = ok && fflush(f) == 0 && fsync(fileno(f)) == 0;
    ok = (fclose(f) == 0) && ok;
    if (ok) ok = rename(tmp, fin) == 0;
    if (!ok) {
        unlink(tmp);
        return false;
    }
    s->count++;
    strcpy(rid_out, rid);
    return true;
}

bool record_store_oldest(const record_store_t *s, char rid_out[24]) {
    DIR *d = opendir(s->dir);
    if (d == NULL) return false;
    bool have_own = false, have_other = false;
    uint32_t own = 0, other = 0;
    char other_epoch[24] = "";
    struct dirent *e;
    while ((e = readdir(d)) != NULL) {
        char ep[24];
        uint32_t c;
        if (!parse_name(e->d_name, "rec", ep, &c)) continue;
        if (strcmp(ep, s->epoch) == 0) {
            if (!have_own || c < own) own = c;
            have_own = true;
        } else if (!have_other || strcmp(ep, other_epoch) < 0 ||
                   (strcmp(ep, other_epoch) == 0 && c < other)) {
            strcpy(other_epoch, ep);
            other = c;
            have_other = true;
        }
    }
    closedir(d);
    char rid[64];  // a rid from parse_name is at most 23 characters
    if (have_own) snprintf(rid, sizeof rid, "%s-%" PRIu32, s->epoch, own);
    else if (have_other) snprintf(rid, sizeof rid, "%s-%" PRIu32, other_epoch, other);
    else return false;
    strncpy(rid_out, rid, 23);
    rid_out[23] = '\0';
    return true;
}

FILE *record_store_read(const record_store_t *s, const char *rid) {
    char p[160];
    if (!rid_ok(rid) || !path_for(s, rid, "rec", p, sizeof p)) return NULL;
    return fopen(p, "r");
}

bool record_store_delete(record_store_t *s, const char *rid) {
    char p[160];
    if (!rid_ok(rid) || !path_for(s, rid, "rec", p, sizeof p)) return false;
    if (unlink(p) != 0) return false;
    if (s->count > 0) s->count--;
    return true;
}
