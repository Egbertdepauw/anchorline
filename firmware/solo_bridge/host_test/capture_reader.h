// SPDX-License-Identifier: Apache-2.0
//
// Reads the SOLO captures written by tool/solo_capture.py (the same format
// test/_helpers/solo_capture_log.dart reads):
//
//   <seconds since start> <wall clock> RX <line with \xNN escapes>
//   <seconds since start> <wall clock> GAP <seconds>
//   <seconds since start> <wall clock> ERROR <what went wrong>
//
// Only RX lines and ERROR lines (the USB cable going away) are returned.
#pragma once
#include <stddef.h>
#include <stdint.h>

#include "line_splitter.h"

typedef enum { CAP_RX, CAP_ERROR } cap_kind_t;

typedef struct {
    cap_kind_t kind;
    uint64_t at_ms;
    char line[SOLO_LINE_MAX + 1];  // CAP_RX: decoded, trailing CR LF removed
} cap_event_t;

// Returns a malloc'ed array of *n events in file order (caller frees), or
// NULL when the file can't be read.
cap_event_t *capture_read(const char *path, size_t *n);
