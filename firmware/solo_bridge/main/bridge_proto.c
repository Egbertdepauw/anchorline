// SPDX-License-Identifier: Apache-2.0
#include "bridge_proto.h"

#include <ctype.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static size_t fmt(char *out, size_t cap, const char *f, ...) {
    va_list ap;
    va_start(ap, f);
    int n = vsnprintf(out, cap, f, ap);
    va_end(ap);
    if (n < 0 || (size_t)n >= cap) {
        if (cap > 0) out[0] = '\0';
        return 0;
    }
    return (size_t)n;
}

static const char *on_off(bool b) { return b ? "on" : "off"; }

size_t proto_fmt_hello(char *out, size_t cap, const proto_hello_t *h) {
    return fmt(out, cap,
               "HELLO proto=%d fw=%s bridge=%s epoch=%s boot=%" PRIu32 " up=%" PRIu64
               " solo=%d rec=%s vbus=%s batt=%" PRIu32 " pending=%" PRIu32,
               PROTO_VERSION, h->fw, h->bridge, h->epoch, h->boot, h->up_ms, h->solo ? 1 : 0,
               on_off(h->rec), on_off(h->vbus), h->batt_mv, h->pending);
}

size_t proto_fmt_status(char *out, size_t cap, const proto_status_t *s) {
    return fmt(out, cap, "ST solo=%d data=%d pending=%" PRIu32 " batt=%" PRIu32 " up=%" PRIu64,
               s->solo ? 1 : 0, s->data ? 1 : 0, s->pending, s->batt_mv, s->up_ms);
}

size_t proto_fmt_live_line(char *out, size_t cap, const char *solo_line) {
    return fmt(out, cap, "L %s", solo_line);
}

size_t proto_fmt_rec(char *out, size_t cap, const char *rid, uint32_t boot, uint64_t up_ms,
                     uint64_t wall_ms, bool live) {
    return fmt(out, cap, "REC %s boot=%" PRIu32 " up=%" PRIu64 " wall=%" PRIu64 " live=%d", rid, boot,
               up_ms, wall_ms, live ? 1 : 0);
}

size_t proto_fmt_w(char *out, size_t cap, int64_t offset_ms, const char *line) {
    return fmt(out, cap, "W %" PRId64 " %s", offset_ms, line);
}

size_t proto_fmt_h(char *out, size_t cap, const char *line) { return fmt(out, cap, "H %s", line); }

size_t proto_fmt_end(char *out, size_t cap, const char *rid) { return fmt(out, cap, "END %s", rid); }

// Copies at most cap-1 bytes of [from, to) into dst.
static void copy_span(char *dst, size_t cap, const char *from, const char *to) {
    size_t n = (size_t)(to - from);
    if (n >= cap) n = cap - 1;
    memcpy(dst, from, n);
    dst[n] = '\0';
}

// The next space-separated token: [*tok, *end). False when none is left.
static bool next_token(const char **p, const char **tok, const char **end) {
    while (**p == ' ') (*p)++;
    if (**p == '\0') return false;
    *tok = *p;
    while (**p != '\0' && **p != ' ') (*p)++;
    *end = *p;
    return true;
}

static bool span_is(const char *tok, const char *end, const char *word) {
    size_t n = strlen(word);
    return (size_t)(end - tok) == n && memcmp(tok, word, n) == 0;
}

static bool parse_u64(const char *tok, const char *end, uint64_t *v) {
    if (tok == end || end - tok > 19) return false;
    uint64_t r = 0;
    for (const char *c = tok; c < end; c++) {
        if (!isdigit((unsigned char)*c)) return false;
        r = r * 10 + (uint64_t)(*c - '0');
    }
    *v = r;
    return true;
}

// A record id: a non-empty token without '='.
static bool parse_rid(const char *tok, const char *end, char *rid, size_t cap) {
    if (tok == end || memchr(tok, '=', (size_t)(end - tok)) != NULL) return false;
    copy_span(rid, cap, tok, end);
    return true;
}

static int8_t on_off_value(const char *v, const char *end) {
    if (span_is(v, end, "on")) return 1;
    if (span_is(v, end, "off")) return 0;
    return -2;  // malformed
}

void proto_parse_cmd(const char *line, proto_cmd_t *out) {
    memset(out, 0, sizeof *out);
    out->kind = CMD_UNKNOWN;
    out->cfg_rec = out->cfg_vbus = -1;

    char buf[256];
    size_t len = strlen(line);
    if (len >= sizeof buf) return;
    memcpy(buf, line, len + 1);
    while (len > 0 && (buf[len - 1] == '\r' || buf[len - 1] == '\n')) buf[--len] = '\0';

    const char *p = buf, *tok, *end;
    if (!next_token(&p, &tok, &end)) return;

    if (span_is(tok, end, "TIME")) {
        if (next_token(&p, &tok, &end) && parse_u64(tok, end, &out->time_ms) &&
            !next_token(&p, &tok, &end))
            out->kind = CMD_TIME;
    } else if (span_is(tok, end, "LIVE")) {
        if (!next_token(&p, &tok, &end)) return;
        bool on = span_is(tok, end, "ON");
        if (!on && !span_is(tok, end, "OFF")) return;
        out->live_on = on;
        out->kind = CMD_LIVE;
    } else if (span_is(tok, end, "ACK")) {
        if (next_token(&p, &tok, &end) && parse_rid(tok, end, out->rid, sizeof out->rid))
            out->kind = CMD_ACK;
    } else if (span_is(tok, end, "FB")) {
        if (!next_token(&p, &tok, &end) || !parse_rid(tok, end, out->rid, sizeof out->rid)) return;
        if (!next_token(&p, &tok, &end)) return;
        copy_span(out->fb_code, sizeof out->fb_code, tok, end);
        if (*p == ' ') p++;  // the text is the rest of the line, spaces included
        copy_span(out->fb_text, sizeof out->fb_text, p, p + strlen(p));
        out->kind = CMD_FB;
    } else if (span_is(tok, end, "STATE")) {
        if (!next_token(&p, &tok, &end)) return;
        copy_span(out->state, sizeof out->state, tok, end);
        while (*p == ' ') p++;
        copy_span(out->mix, sizeof out->mix, p, p + strlen(p));
        out->kind = CMD_STATE;
    } else if (span_is(tok, end, "CFG")) {
        bool any = false;
        while (next_token(&p, &tok, &end)) {
            const char *eq = memchr(tok, '=', (size_t)(end - tok));
            if (eq == NULL || eq == tok) continue;
            int8_t v = on_off_value(eq + 1, end);
            if (span_is(tok, eq, "rec")) {
                if (v < 0) return;
                out->cfg_rec = v;
                any = true;
            } else if (span_is(tok, eq, "vbus")) {
                if (v < 0) return;
                out->cfg_vbus = v;
                any = true;
            }
        }
        if (any) out->kind = CMD_CFG;
    }
}

size_t proto_chunk_len(size_t len, uint16_t mtu, size_t i) {
    size_t max = mtu > 3 ? (size_t)mtu - 3 : 1;
    size_t start = i * max;
    if (start >= len) return 0;
    return len - start < max ? len - start : max;
}
