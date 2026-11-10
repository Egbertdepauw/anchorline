// SPDX-License-Identifier: Apache-2.0
#include <string.h>

#include "check.h"
#include "text_fit.h"

// Every character is 10 px wide, so widths are easy to reason about.
static int32_t ten_px(const char *s, size_t n, void *ctx) {
    (void)s;
    (void)ctx;
    return (int32_t)n * 10;
}

void test_text_fit(void) {
    char out[64];

    // One short line stays one line.
    CHECK(text_fit_wrap("READY", 100, 4, ten_px, NULL, out, sizeof out) == 1);
    CHECK_STR_EQ(out, "READY");

    // Breaks only between words: never "HYPOXI" / "C 20".
    CHECK(text_fit_wrap("STABLE HYPOXIC 20", 100, 4, ten_px, NULL, out, sizeof out) == 2);
    CHECK_STR_EQ(out, "STABLE\nHYPOXIC 20");

    // Greedy: words share a line while they fit.
    CHECK(text_fit_wrap("SAVED - SIGN OFF LATER", 120, 4, ten_px, NULL, out, sizeof out) == 2);
    CHECK_STR_EQ(out, "SAVED - SIGN\nOFF LATER");
    CHECK(text_fit_wrap("SAVED - SIGN OFF LATER", 80, 4, ten_px, NULL, out, sizeof out) == 3);
    CHECK_STR_EQ(out, "SAVED -\nSIGN OFF\nLATER");

    // A word wider than the line doesn't fit this font.
    CHECK(text_fit_wrap("HYPOXIC", 60, 4, ten_px, NULL, out, sizeof out) == -1);

    // More lines than allowed doesn't fit this font.
    CHECK(text_fit_wrap("A B C D E", 10, 4, ten_px, NULL, out, sizeof out) == -1);
    CHECK(text_fit_wrap("A B C D", 10, 4, ten_px, NULL, out, sizeof out) == 4);
    CHECK_STR_EQ(out, "A\nB\nC\nD");

    // Runs of spaces collapse; leading and trailing spaces go.
    CHECK(text_fit_wrap("  NO   SOLO ", 100, 4, ten_px, NULL, out, sizeof out) == 1);
    CHECK_STR_EQ(out, "NO SOLO");

    // An existing line break is kept as a forced break.
    CHECK(text_fit_wrap("SETTLING...\nTX21/35", 200, 4, ten_px, NULL, out, sizeof out) == 2);
    CHECK_STR_EQ(out, "SETTLING...\nTX21/35");

    // Empty text is zero lines.
    CHECK(text_fit_wrap("", 100, 4, ten_px, NULL, out, sizeof out) == 0);
    CHECK_STR_EQ(out, "");

    // Too small an output buffer is reported as not fitting, never overrun.
    char tiny[4];
    CHECK(text_fit_wrap("READY", 100, 4, ten_px, NULL, tiny, sizeof tiny) == -1);
}
