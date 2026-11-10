// SPDX-License-Identifier: Apache-2.0
//
// Splits a byte stream into lines. Used for the SOLO's USB output and for
// what the app writes over Bluetooth.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define SOLO_LINE_MAX 160

// line is NUL-terminated, without its terminator.
typedef void (*line_cb_t)(const char *line, void *ctx);

typedef struct {
    char buf[SOLO_LINE_MAX + 1];
    size_t len;
    bool overflow;
} line_splitter_t;

// Forgets any partial line.
void line_splitter_reset(line_splitter_t *s);

// Splits on '\n' and drops one '\r' right before it; a '\r' anywhere else is
// kept. Never emits an empty line. A line longer than SOLO_LINE_MAX is dropped
// whole: a cut line is not a reading.
void line_splitter_feed(line_splitter_t *s, const uint8_t *data, size_t n, line_cb_t cb,
                        void *ctx);
