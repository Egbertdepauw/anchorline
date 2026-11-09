// SPDX-License-Identifier: Apache-2.0
//
// A minimal test runner for the pure firmware modules, built on the Mac.
#pragma once
#include <stdio.h>
#include <string.h>

extern int g_checks;
extern int g_failures;

#define CHECK(cond)                                                          \
    do {                                                                     \
        g_checks++;                                                          \
        if (!(cond)) {                                                       \
            fprintf(stderr, "%s:%d: CHECK failed: %s\n", __FILE__, __LINE__, \
                    #cond);                                                  \
            g_failures++;                                                    \
        }                                                                    \
    } while (0)

#define CHECK_STR_EQ(a, b)                                                   \
    do {                                                                     \
        g_checks++;                                                          \
        const char *a_ = (a), *b_ = (b);                                     \
        if (a_ == NULL || b_ == NULL || strcmp(a_, b_) != 0) {               \
            fprintf(stderr, "%s:%d: expected \"%s\"\n  got      \"%s\"\n", \
                    __FILE__, __LINE__, b_ ? b_ : "(null)",                  \
                    a_ ? a_ : "(null)");                                     \
            g_failures++;                                                    \
        }                                                                    \
    } while (0)

// Each test file defines one entry point; test_main.c calls them in order.
#define TEST_SUITE(name) void name(void)
