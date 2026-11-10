// SPDX-License-Identifier: Apache-2.0
#include "check.h"
#include "line_splitter.h"
#include "solo_line.h"

typedef struct {
    int n;
    char lines[8][SOLO_LINE_MAX + 1];
} sink_t;

static void collect(const char *line, void *ctx) {
    sink_t *s = ctx;
    if (s->n < 8) snprintf(s->lines[s->n], sizeof s->lines[0], "%s", line);
    s->n++;
}

static void feed(line_splitter_t *sp, sink_t *sink, const char *text) {
    line_splitter_feed(sp, (const uint8_t *)text, strlen(text), collect, sink);
}

static const char *kCapture =
    "He   0.4 %  O2  19.8 %  Ti  21.7 ~C  1029.5 hPa   2026/11/03 15:19:15";

TEST_SUITE(test_line_splitter) {
    line_splitter_t sp;
    sink_t sink = {0};

    // A line split across two reads, CRLF, runs of spaces kept.
    line_splitter_reset(&sp);
    feed(&sp, &sink, "He  10.0 %\r\nO2 21");
    feed(&sp, &sink, ".0 %\r\n");
    CHECK(sink.n == 2);
    CHECK_STR_EQ(sink.lines[0], "He  10.0 %");
    CHECK_STR_EQ(sink.lines[1], "O2 21.0 %");

    // Empty lines are never emitted.
    memset(&sink, 0, sizeof sink);
    line_splitter_reset(&sp);
    feed(&sp, &sink, "\r\n\r\n\n");
    CHECK(sink.n == 0);

    // A lone CR inside a line is kept; only the one before LF goes.
    memset(&sink, 0, sizeof sink);
    line_splitter_reset(&sp);
    feed(&sp, &sink, "a\rb\r\n");
    CHECK(sink.n == 1);
    CHECK_STR_EQ(sink.lines[0], "a\rb");

    // An overlong line is dropped whole, the next one comes through.
    memset(&sink, 0, sizeof sink);
    line_splitter_reset(&sp);
    char big[201];
    memset(big, 'x', 200);
    big[200] = 0;
    feed(&sp, &sink, big);
    feed(&sp, &sink, "x\nO2 1\n");
    CHECK(sink.n == 1);
    CHECK_STR_EQ(sink.lines[0], "O2 1");

    // A line of exactly SOLO_LINE_MAX bytes fits.
    memset(&sink, 0, sizeof sink);
    line_splitter_reset(&sp);
    char max[SOLO_LINE_MAX + 2];
    memset(max, 'y', SOLO_LINE_MAX);
    max[SOLO_LINE_MAX] = '\n';
    max[SOLO_LINE_MAX + 1] = 0;
    feed(&sp, &sink, max);
    CHECK(sink.n == 1);
    CHECK(strlen(sink.lines[0]) == SOLO_LINE_MAX);

    // Reset drops a partial line (the SOLO was unplugged mid-line).
    memset(&sink, 0, sizeof sink);
    line_splitter_reset(&sp);
    feed(&sp, &sink, "O2 2");
    line_splitter_reset(&sp);
    feed(&sp, &sink, "O2 3\n");
    CHECK(sink.n == 1);
    CHECK_STR_EQ(sink.lines[0], "O2 3");

    // The capture line survives byte for byte.
    memset(&sink, 0, sizeof sink);
    line_splitter_reset(&sp);
    feed(&sp, &sink, kCapture);
    feed(&sp, &sink, "\r\n");
    CHECK_STR_EQ(sink.lines[0], kCapture);

    // solo_is_data_line
    CHECK(solo_is_data_line(kCapture));
    CHECK(solo_is_data_line("O2 ***.* %"));
    CHECK(solo_is_data_line("o2 20.9"));
    CHECK(solo_is_data_line("He 35.0 O2 20.9 % Ti 23.9 ~C 1004.1 hPa 2026/10/27 20:30:00"));
    CHECK(!solo_is_data_line("Divesoft SOLO"));
    CHECK(!solo_is_data_line(""));
    CHECK(!solo_is_data_line("O2"));
    CHECK(!solo_is_data_line("O2 %"));
    CHECK(!solo_is_data_line("CO2 20.9"));
    CHECK(solo_is_data_line("O2 % O2 20.9"));
}
