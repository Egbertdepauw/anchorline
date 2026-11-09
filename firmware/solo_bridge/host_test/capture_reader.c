// SPDX-License-Identifier: Apache-2.0
#include "capture_reader.h"

#include <ctype.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int hex_val(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

// Decodes \xNN escapes and strips trailing CR/LF. Runs of spaces are kept.
static void decode(const char *in, char *out, size_t cap) {
    size_t o = 0;
    for (const char *p = in; *p != '\0' && o + 1 < cap; p++) {
        if (p[0] == '\\' && p[1] == 'x' && hex_val(p[2]) >= 0 && hex_val(p[3]) >= 0) {
            out[o++] = (char)(hex_val(p[2]) * 16 + hex_val(p[3]));
            p += 3;
        } else {
            out[o++] = *p;
        }
    }
    while (o > 0 && (out[o - 1] == '\r' || out[o - 1] == '\n')) o--;
    out[o] = '\0';
}

cap_event_t *capture_read(const char *path, size_t *n) {
    FILE *f = fopen(path, "r");
    if (f == NULL) return NULL;
    size_t cap = 64, count = 0;
    cap_event_t *ev = malloc(cap * sizeof *ev);
    char raw[1024];
    while (ev != NULL && fgets(raw, sizeof raw, f) != NULL) {
        raw[strcspn(raw, "\n")] = '\0';
        const char *p = raw;
        while (*p == ' ') p++;
        char *end;
        double sec = strtod(p, &end);
        if (end == p || *end != ' ') continue;
        p = end + 1;  // the wall clock: skip to the next single space
        const char *sp = strchr(p, ' ');
        if (sp == NULL) continue;
        p = sp + 1;
        const char *kind_end = strchr(p, ' ');
        size_t kind_len = kind_end ? (size_t)(kind_end - p) : strlen(p);
        const char *payload = kind_end ? kind_end + 1 : "";

        cap_kind_t kind;
        if (kind_len == 2 && strncmp(p, "RX", 2) == 0) kind = CAP_RX;
        else if (kind_len == 5 && strncmp(p, "ERROR", 5) == 0) kind = CAP_ERROR;
        else continue;

        if (count == cap) {
            cap *= 2;
            cap_event_t *bigger = realloc(ev, cap * sizeof *ev);
            if (bigger == NULL) { free(ev); ev = NULL; break; }
            ev = bigger;
        }
        cap_event_t *e = &ev[count++];
        e->kind = kind;
        e->at_ms = (uint64_t)llround(sec * 1000.0);
        e->line[0] = '\0';
        if (kind == CAP_RX) decode(payload, e->line, sizeof e->line);
    }
    fclose(f);
    *n = count;
    return ev;
}
