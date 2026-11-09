// SPDX-License-Identifier: Apache-2.0
#include "check.h"

int g_checks = 0;
int g_failures = 0;

// Each task adds its suite here and its files to the Makefile.
#define SUITES(X) X(test_smoke) X(test_power_logic) X(test_line_splitter)

#define DECLARE(name) TEST_SUITE(name);
SUITES(DECLARE)

TEST_SUITE(test_smoke) { CHECK(1); }

int main(void) {
#define RUN(name) name();
    SUITES(RUN)
    printf("%d checks, %d failures\n", g_checks, g_failures);
    return g_failures == 0 ? 0 : 1;
}
