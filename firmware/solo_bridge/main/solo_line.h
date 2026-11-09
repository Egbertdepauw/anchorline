// SPDX-License-Identifier: Apache-2.0
//
// Whether a line from the SOLO carries a reading. This is the only thing the
// firmware knows about the SOLO's lines: it never reads the values.
#pragma once
#include <stdbool.h>

// True when the line has a token "O2" (any case) followed by a value token
// made of digits, '.', '-' or '*'. The same test as the app's parseSoloLine
// "has an O2 field".
bool solo_is_data_line(const char *line);
