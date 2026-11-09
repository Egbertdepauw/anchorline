// SPDX-License-Identifier: Apache-2.0
#include "board.h"
#include "check.h"
#include "power_logic.h"

static const vbus_src_t kAll[] = {VBUS_SRC_OFF, VBUS_SRC_DEV, VBUS_SRC_BATTERY};

// The pin levels each source leaves behind.
static void levels_of(vbus_src_t s, int *boost, int *dev, int *limit) {
    *boost = s == VBUS_SRC_BATTERY;
    *dev = s == VBUS_SRC_DEV;
    *limit = s != VBUS_SRC_OFF;
}

TEST_SUITE(test_power_logic) {
    CHECK(power_pick_source(false, 4000) == VBUS_SRC_OFF);
    CHECK(power_pick_source(false, 0) == VBUS_SRC_OFF);
    CHECK(power_pick_source(true, 3900) == VBUS_SRC_BATTERY);
    CHECK(power_pick_source(true, BATTERY_PRESENT_MV) == VBUS_SRC_BATTERY);
    CHECK(power_pick_source(true, 120) == VBUS_SRC_DEV);

    // No write sequence ever has both enables high, and each ends in the
    // target's levels with the limiter on whenever 5 V is on.
    for (size_t f = 0; f < 3; f++) {
        for (size_t t = 0; t < 3; t++) {
            int boost, dev, limit;
            levels_of(kAll[f], &boost, &dev, &limit);
            pin_write_t w[6];
            size_t n = power_sequence(kAll[f], kAll[t], w);
            CHECK(n > 0 && n <= 6);
            int enabled_last = -1;
            for (size_t i = 0; i < n; i++) {
                if (w[i].pin == PIN_BOOST_EN) boost = w[i].level;
                else if (w[i].pin == PIN_DEV_VBUS_EN) dev = w[i].level;
                else if (w[i].pin == PIN_LIMIT_EN) limit = w[i].level;
                else CHECK(!"unexpected pin");
                CHECK(!(boost && dev));
                if (w[i].level == 1 && (w[i].pin == PIN_BOOST_EN || w[i].pin == PIN_DEV_VBUS_EN))
                    enabled_last = (int)i;
            }
            int eb, ed, el;
            levels_of(kAll[t], &eb, &ed, &el);
            CHECK(boost == eb && dev == ed && limit == el);
            if (kAll[t] != VBUS_SRC_OFF) CHECK(enabled_last == (int)n - 1);
        }
    }

    CHECK(power_adc_to_mv(1950, BATTERY_DIV_X10) == 3900);
    CHECK(power_adc_to_mv(1351, HOST_VBUS_DIV_X10) == 4998);
    CHECK(power_adc_to_mv(0, BATTERY_DIV_X10) == 0);
}
