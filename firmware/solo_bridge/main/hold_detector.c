// SPDX-License-Identifier: Apache-2.0
#include "hold_detector.h"

#include <string.h>

#include "solo_line.h"

static hold_line_t *slot(hold_detector_t *d, size_t i) {
    return &d->ring[(d->head + i) % HOLD_WINDOW_MAX_LINES];
}

void hold_detector_reset(hold_detector_t *d) {
    d->head = 0;
    d->n = 0;
    d->flow_start = 0;
    d->has_flow = false;
    d->holds = 0;
    d->fired = false;
}

static void drop_oldest(hold_detector_t *d) {
    d->head = (d->head + 1) % HOLD_WINDOW_MAX_LINES;
    d->n--;
}

void hold_detector_add_line(hold_detector_t *d, uint64_t now_ms, const char *line) {
    if (!solo_is_data_line(line)) return;
    bool resume = !d->has_flow || d->fired;
    if (!resume && d->n > 0) resume = now_ms - slot(d, d->n - 1)->at_ms >= HOLD_SILENCE_MS;
    if (resume) {
        d->flow_start = now_ms;
        d->has_flow = true;
        d->fired = false;
        d->head = 0;
        d->n = 0;
    }
    if (d->n == HOLD_WINDOW_MAX_LINES) drop_oldest(d);  // full: oldest goes, even if young
    hold_line_t *l = slot(d, d->n);
    l->at_ms = now_ms;
    strncpy(l->line, line, SOLO_LINE_MAX);
    l->line[SOLO_LINE_MAX] = '\0';
    d->n++;
    while (d->n > 0 && now_ms - slot(d, 0)->at_ms > HOLD_WINDOW_MS) drop_oldest(d);
}

bool hold_detector_tick(hold_detector_t *d, uint64_t now_ms, hold_t *out) {
    if (d->n == 0 || !d->has_flow || d->fired) return false;
    uint64_t last = slot(d, d->n - 1)->at_ms;
    if (now_ms - last < HOLD_SILENCE_MS) return false;
    uint64_t min_flow = d->holds == 0 ? HOLD_FIRST_MIN_FLOW_MS : HOLD_NEXT_MIN_FLOW_MS;
    if (last - d->flow_start < min_flow) return false;

    d->fired = true;
    d->holds++;
    out->held_at_ms = last;
    out->n = d->n;
    for (size_t i = 0; i < d->n; i++) out->lines[i] = *slot(d, i);
    return true;
}
