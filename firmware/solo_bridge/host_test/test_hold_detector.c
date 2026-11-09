// SPDX-License-Identifier: Apache-2.0
//
// The OK rule, tested like lib/analyzer/hold_detector.dart: against the two
// real SOLO captures, and with the same synthetic cases.
#include <stdlib.h>

#include "capture_reader.h"
#include "check.h"
#include "hold_detector.h"

static hold_detector_t d;
static hold_t hold;

static void data_line(char *out, size_t cap, int i, double ti) {
    snprintf(out, cap, "He   0.5 %%  O2  19.8 %%  Ti  %.1f ~C  1029.5 hPa   2026/11/03 15:20:%02d",
             ti, i % 60);
}

// A data line every 200 ms from from_ms to to_ms, both included.
static void flow(uint64_t from_ms, uint64_t to_ms, double ti) {
    char line[SOLO_LINE_MAX + 1];
    for (uint64_t t = from_ms; t <= to_ms; t += 200) {
        data_line(line, sizeof line, (int)(t / 200), ti);
        hold_detector_add_line(&d, t, line);
    }
}

// Ticks every 100 ms from from_ms to to_ms; returns how many holds fired and
// leaves the last one in `hold`.
static int ticks(uint64_t from_ms, uint64_t to_ms, uint64_t held_at[], int max) {
    int n = 0;
    for (uint64_t t = from_ms; t <= to_ms; t += 100) {
        if (hold_detector_tick(&d, t, &hold)) {
            if (n < max) held_at[n] = hold.held_at_ms;
            n++;
        }
    }
    return n;
}

static int count_ticks(uint64_t from_ms, uint64_t to_ms) {
    uint64_t at[8];
    return ticks(from_ms, to_ms, at, 8);
}

static bool has_text(const char *text) {
    for (size_t i = 0; i < hold.n; i++)
        if (strstr(hold.lines[i].line, text) != NULL) return true;
    return false;
}

// Plays a capture like a live session: time walks in 200 ms steps up to 3 s
// past the last event; each step delivers the events due, then ticks. An
// ERROR line resets the detector.
static int replay(const char *path, uint64_t held_at[], int max, const char *held_text[]) {
    size_t n = 0;
    cap_event_t *ev = capture_read(path, &n);
    CHECK(ev != NULL && n > 0);
    if (ev == NULL) return 0;
    hold_detector_reset(&d);
    uint64_t end = ev[n - 1].at_ms + 3000;
    size_t i = 0;
    int holds = 0;
    for (uint64_t t = 0; t <= end; t += 200) {
        while (i < n && ev[i].at_ms <= t) {
            if (ev[i].kind == CAP_RX) hold_detector_add_line(&d, ev[i].at_ms, ev[i].line);
            else hold_detector_reset(&d);
            i++;
        }
        if (hold_detector_tick(&d, t, &hold)) {
            if (holds < max) {
                held_at[holds] = hold.held_at_ms;
                // The window ends at the held line, spans at most 30 s, and the
                // held line is the one the hold names.
                CHECK(hold.lines[hold.n - 1].at_ms == hold.held_at_ms);
                CHECK(hold.held_at_ms - hold.lines[0].at_ms <= HOLD_WINDOW_MS);
                held_text[holds] = strstr(hold.lines[hold.n - 1].line, "Ti  22.0") ? "Ti  22.0"
                                   : strstr(hold.lines[hold.n - 1].line, "Ti  22.2") ? "Ti  22.2"
                                   : strstr(hold.lines[hold.n - 1].line, "Ti  22.5") ? "Ti  22.5"
                                                                                  : "?";
            }
            holds++;
        }
    }
    free(ev);
    return holds;
}

static void test_captures(void) {
    uint64_t at[8];
    const char *text[8];
    int n = replay("../../../test/fixtures/analyzer/solo_ok_presses_2026-11-03_a.txt", at, 8, text);
    CHECK(n == 2);
    if (n == 2) {
        CHECK(at[0] == 58357);
        CHECK(at[1] == 119677);
        CHECK_STR_EQ(text[0], "Ti  22.0");
        CHECK_STR_EQ(text[1], "Ti  22.2");
    }
    n = replay("../../../test/fixtures/analyzer/solo_ok_presses_2026-11-03_b.txt", at, 8, text);
    CHECK(n == 1);
    if (n == 1) {
        CHECK(at[0] == 17518);
        CHECK_STR_EQ(text[0], "Ti  22.5");
    }
}

static void test_arming(void) {
    uint64_t at[8];
    // no hold before 5 s of flow
    hold_detector_reset(&d);
    flow(0, 4800, 22.0);
    CHECK(count_ticks(4800, 10000) == 0);

    // 5 s of flow is enough for the first hold
    hold_detector_reset(&d);
    flow(0, 5000, 22.0);
    CHECK(ticks(5000, 10000, at, 8) == 1 && at[0] == 5000);

    // after a hold, 3 s of flow arms the next one
    hold_detector_reset(&d);
    flow(0, 10000, 22.0);
    CHECK(count_ticks(10000, 13000) == 1);
    flow(20000, 22800, 22.0);  // 2.8 s: not enough
    CHECK(count_ticks(22800, 29000) == 0);
    flow(30000, 33200, 22.0);  // 3.2 s: enough
    CHECK(ticks(33200, 40000, at, 8) == 1 && at[0] == 33200);

    // dips under 2 s do not reset arming: 5.9 s from first to last line
    hold_detector_reset(&d);
    flow(0, 3000, 22.0);
    CHECK(count_ticks(3000, 4500) == 0);
    flow(4500, 5900, 22.0);
    CHECK(ticks(5900, 9000, at, 8) == 1 && at[0] == 5900);

    // a silence of 2 s or more that did not fire restarts the flow
    hold_detector_reset(&d);
    flow(0, 4800, 22.0);
    CHECK(count_ticks(4800, 7300) == 0);
    flow(7300, 7700, 22.0);  // 0.4 s of fresh flow; the 7.7 s since the start must not count
    CHECK(count_ticks(7700, 11000) == 0);
    flow(12000, 17000, 22.0);
    CHECK(ticks(17000, 20000, at, 8) == 1 && at[0] == 17000);

    // a short resume and a second silence is not 3 s of flow
    hold_detector_reset(&d);
    flow(0, 10000, 22.0);
    CHECK(count_ticks(10000, 13000) == 1);
    flow(20000, 21000, 22.0);
    CHECK(count_ticks(21000, 25000) == 0);
    flow(26000, 27000, 22.0);
    CHECK(count_ticks(27000, 32000) == 0);
}

static void test_non_data_lines(void) {
    // non-data lines are not flow
    hold_detector_reset(&d);
    for (uint64_t t = 0; t <= 10000; t += 200) hold_detector_add_line(&d, t, "Divesoft SOLO");
    CHECK(count_ticks(0, 20000) == 0);

    // non-data lines do not start the flow
    hold_detector_reset(&d);
    hold_detector_add_line(&d, 0, "Divesoft SOLO");
    flow(4000, 8000, 22.0);
    CHECK(count_ticks(8000, 12000) == 0);

    // non-data lines do not make a resume
    hold_detector_reset(&d);
    flow(0, 10000, 22.0);
    CHECK(count_ticks(10000, 13000) == 1);
    hold_detector_add_line(&d, 20000, "Divesoft SOLO");
    flow(21000, 23200, 22.0);  // 2.2 s of flow after the real resume
    CHECK(count_ticks(23200, 30000) == 0);

    // non-data lines do not shorten a silence
    uint64_t at[8];
    hold_detector_reset(&d);
    flow(0, 10000, 22.0);
    for (uint64_t t = 10200; t <= 11800; t += 200) hold_detector_add_line(&d, t, "Divesoft SOLO");
    CHECK(ticks(10000, 12000, at, 8) == 1 && at[0] == 10000);
}

static void test_firing(void) {
    uint64_t at[8];
    // nothing before the first line
    hold_detector_reset(&d);
    CHECK(count_ticks(0, 20000) == 0);

    // a hold needs 2 s of silence, to the millisecond
    hold_detector_reset(&d);
    flow(0, 10000, 22.0);
    CHECK(!hold_detector_tick(&d, 11999, &hold));
    CHECK(hold_detector_tick(&d, 12000, &hold));
    CHECK(hold.held_at_ms == 10000);

    // one hold per silence
    hold_detector_reset(&d);
    flow(0, 10000, 22.0);
    CHECK(ticks(10000, 40000, at, 8) == 1 && at[0] == 10000);

    // the hold carries the last data line, as given
    hold_detector_reset(&d);
    flow(0, 9800, 22.0);
    const char *last = "He   0.5 %  O2  19.8 %  Ti  22.3 ~C  1029.5 hPa   2026/11/03 15:20:59";
    hold_detector_add_line(&d, 10000, last);
    CHECK(count_ticks(10000, 13000) == 1);
    CHECK_STR_EQ(hold.lines[hold.n - 1].line, last);

    // lines after a hold start the next flow and re-arm it
    hold_detector_reset(&d);
    flow(0, 10000, 22.0);
    CHECK(count_ticks(10000, 13000) == 1);
    flow(20000, 30000, 22.0);
    CHECK(ticks(30000, 40000, at, 8) == 1 && at[0] == 30000);
}

static void test_reset(void) {
    uint64_t at[8];
    // a detach before 2 s of silence cancels the hold
    hold_detector_reset(&d);
    flow(0, 10000, 22.0);
    CHECK(count_ticks(10000, 10900) == 0);
    hold_detector_reset(&d);
    CHECK(count_ticks(11000, 15000) == 0);

    // a detach after a hold forgets the hold count: 4.8 s is too little again
    hold_detector_reset(&d);
    flow(0, 10000, 22.0);
    CHECK(count_ticks(10000, 13000) == 1);
    hold_detector_reset(&d);
    flow(20000, 24800, 22.0);
    CHECK(count_ticks(24800, 30000) == 0);

    // and 5 s of flow arms the first hold again
    hold_detector_reset(&d);
    flow(0, 10000, 22.0);
    CHECK(count_ticks(10000, 13000) == 1);
    hold_detector_reset(&d);
    flow(20000, 25000, 22.0);
    CHECK(ticks(25000, 30000, at, 8) == 1 && at[0] == 25000);

    // a detach forgets the window: only the 6 s after it, 31 lines
    hold_detector_reset(&d);
    flow(0, 10000, 22.0);
    hold_detector_reset(&d);
    flow(20000, 26000, 22.0);
    CHECK(count_ticks(26000, 29000) == 1);
    CHECK(hold.n == 31);
    CHECK(hold.held_at_ms - hold.lines[0].at_ms == 6000);
}

static void test_window(void) {
    // holds the last 30 s, oldest first, ending at the held line: 151 lines
    hold_detector_reset(&d);
    flow(0, 60000, 22.0);
    CHECK(count_ticks(60000, 63000) == 1);
    CHECK(hold.held_at_ms == 60000);
    CHECK(hold.n == 151);
    CHECK(hold.lines[0].at_ms == 30000);
    bool ordered = true;
    for (size_t i = 1; i < hold.n; i++) ordered = ordered && hold.lines[i].at_ms > hold.lines[i - 1].at_ms;
    CHECK(ordered);

    // 20 minutes of lines: still bounded
    hold_detector_reset(&d);
    flow(0, 1200000, 22.0);
    CHECK(count_ticks(1200000, 1203000) == 1);
    CHECK(hold.n == 151);

    // a shorter flow gives a shorter window
    hold_detector_reset(&d);
    flow(0, 6000, 22.0);
    CHECK(count_ticks(6000, 9000) == 1);
    CHECK(hold.n == 31 && hold.lines[0].at_ms == 0);

    // only data lines are kept
    hold_detector_reset(&d);
    char line[SOLO_LINE_MAX + 1];
    for (uint64_t t = 0; t <= 6000; t += 200) {
        data_line(line, sizeof line, (int)(t / 200), 22.0);
        hold_detector_add_line(&d, t, line);
        hold_detector_add_line(&d, t, "Divesoft SOLO");
    }
    CHECK(count_ticks(6000, 9000) == 1);
    CHECK(hold.n == 31);
    CHECK(has_text("O2"));

    // a full ring drops the oldest line even when it is under 30 s old
    hold_detector_reset(&d);
    for (uint64_t t = 0; t < 250 * 100; t += 100) {  // 10 Hz: 250 lines in 25 s
        data_line(line, sizeof line, (int)(t / 100), 22.0);
        hold_detector_add_line(&d, t, line);
    }
    uint64_t last_at = 249 * 100;
    CHECK(count_ticks(last_at, last_at + 3000) == 1);
    CHECK(hold.n == HOLD_WINDOW_MAX_LINES);
    CHECK(hold.lines[hold.n - 1].at_ms == last_at);
    CHECK(hold.lines[0].at_ms == last_at - (HOLD_WINDOW_MAX_LINES - 1) * 100);
}

TEST_SUITE(test_hold_detector) {
    test_captures();
    test_arming();
    test_non_data_lines();
    test_firing();
    test_reset();
    test_window();
}
