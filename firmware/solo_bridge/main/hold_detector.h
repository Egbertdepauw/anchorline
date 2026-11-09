// SPDX-License-Identifier: Apache-2.0
//
// Recognises an OK press on the SOLO from its line stream (spec section 1).
// OK suspends the SOLO's measurement and its USB output stops completely until
// OK is pressed again, so a press is a silence in a stream that had been
// flowing, and the last line before it is the reading the display froze on.
//
// This is the C twin of lib/analyzer/hold_detector.dart, with the same named
// thresholds; both are tested against the same two captures.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "line_splitter.h"  // SOLO_LINE_MAX

#define HOLD_SILENCE_MS 2000
#define HOLD_FIRST_MIN_FLOW_MS 5000
#define HOLD_NEXT_MIN_FLOW_MS 3000
#define HOLD_WINDOW_MS 30000
#define HOLD_WINDOW_MAX_LINES 200 /* 30 s at 5 Hz is 150 */

typedef struct {
    uint64_t at_ms;
    char line[SOLO_LINE_MAX + 1];
} hold_line_t;

// One detected OK press. Big (about 35 KB): keep it static, not on a task stack.
typedef struct {
    uint64_t held_at_ms;
    size_t n;
    hold_line_t lines[HOLD_WINDOW_MAX_LINES];  // oldest first; the last is the held line
} hold_t;

// Private fields; use only through the functions. Big, like hold_t.
typedef struct {
    hold_line_t ring[HOLD_WINDOW_MAX_LINES];
    size_t head;  // index of the oldest line
    size_t n;     // lines in the ring
    uint64_t flow_start;
    bool has_flow;  // flow_start is set
    uint32_t holds;  // holds fired since reset
    bool fired;      // a hold fired for the silence that is still going on
} hold_detector_t;

// Forgets everything: the SOLO attached or detached. A hold that was waiting
// for its silence to be long enough is cancelled.
void hold_detector_reset(hold_detector_t *d);

// Feeds one line, complete, arriving at now_ms. Lines that carry no reading
// are not flow and are ignored. A data line after a silence of
// HOLD_SILENCE_MS or more, or after a fired hold, is a resume: it restarts
// the flow and drops the lines before it.
void hold_detector_add_line(hold_detector_t *d, uint64_t now_ms, const char *line);

// True, once per silence, when an OK press has happened; *out then holds the
// held line and the window (data lines since the last resume, at most
// HOLD_WINDOW_MS before the held line). Call at least every 200 ms.
bool hold_detector_tick(hold_detector_t *d, uint64_t now_ms, hold_t *out);
