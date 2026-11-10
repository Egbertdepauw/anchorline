// SPDX-License-Identifier: Apache-2.0
#include "text_fit.h"

#include <stdbool.h>
#include <string.h>

int text_fit_wrap(const char *text, int32_t max_width, int max_lines, text_fit_measure_t measure,
                  void *ctx, char *out, size_t cap) {
    if (cap == 0) return -1;
    size_t len = 0;       // bytes in out
    size_t line_at = 0;   // where the current line starts in out
    int lines = 0;        // finished lines plus the current one, if it has a word
    bool force_break = false;  // a '\n' came since the last word
    out[0] = '\0';

    const char *p = text;
    while (*p != '\0') {
        if (*p == ' ') {
            p++;
            continue;
        }
        if (*p == '\n') {  // a forced break: the next word starts a new line
            force_break = len > 0;
            p++;
            continue;
        }
        const char *w = p;
        while (*p != '\0' && *p != ' ' && *p != '\n') p++;
        size_t wn = (size_t)(p - w);
        if (measure(w, wn, ctx) > max_width) return -1;

        bool forced = force_break;
        force_break = false;
        bool fresh = len == 0;
        bool joins = false;
        if (!fresh && !forced) {
            // Does "<current line> <word>" still fit?
            size_t cur = len - line_at;
            char buf[192];
            if (cur + 1 + wn < sizeof buf) {
                memcpy(buf, out + line_at, cur);
                buf[cur] = ' ';
                memcpy(buf + cur + 1, w, wn);
                joins = measure(buf, cur + 1 + wn, ctx) <= max_width;
            }
        }
        size_t need = (fresh ? 0 : 1) + wn;
        if (len + need + 1 > cap) return -1;
        if (fresh) {
            lines = 1;
        } else {
            out[len++] = joins ? ' ' : '\n';
            if (!joins) {
                line_at = len;
                if (++lines > max_lines) return -1;
            }
        }
        memcpy(out + len, w, wn);
        len += wn;
        out[len] = '\0';
    }
    return lines;
}
