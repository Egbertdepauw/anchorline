// SPDX-License-Identifier: Apache-2.0
//
// Word wrapping for the bridge screen's main text. Pure: the caller passes a
// width measure for its font, so this runs on the host too.
#pragma once
#include <stddef.h>
#include <stdint.h>

// Width in pixels of the n bytes at s, in the caller's font.
typedef int32_t (*text_fit_measure_t)(const char *s, size_t n, void *ctx);

// Wraps `text` into lines no wider than max_width, breaking only between
// words (spaces) and at existing '\n'. Runs of spaces collapse to one and
// leading/trailing spaces go. Writes the lines joined by '\n' to out.
// Returns the number of lines, or -1 when it doesn't fit: a word wider than
// max_width, more than max_lines lines, or out too small.
int text_fit_wrap(const char *text, int32_t max_width, int max_lines, text_fit_measure_t measure,
                  void *ctx, char *out, size_t cap);
