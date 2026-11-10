// SPDX-License-Identifier: Apache-2.0
#include "line_splitter.h"

void line_splitter_reset(line_splitter_t *s) {
    s->len = 0;
    s->overflow = false;
}

void line_splitter_feed(line_splitter_t *s, const uint8_t *data, size_t n, line_cb_t cb,
                        void *ctx) {
    for (size_t i = 0; i < n; i++) {
        uint8_t c = data[i];
        if (c == '\n') {
            size_t len = s->len;
            if (len > 0 && s->buf[len - 1] == '\r') len--;
            if (!s->overflow && len > 0) {
                s->buf[len] = '\0';
                cb(s->buf, ctx);
            }
            line_splitter_reset(s);
            continue;
        }
        if (s->overflow) continue;
        // One byte of room is kept for a '\r' that ends a full-length line.
        if (s->len >= SOLO_LINE_MAX + 1 || (s->len == SOLO_LINE_MAX && c != '\r')) {
            s->overflow = true;
            continue;
        }
        s->buf[s->len++] = (char)c;
    }
}
