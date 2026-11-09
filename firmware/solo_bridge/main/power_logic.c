// SPDX-License-Identifier: Apache-2.0
#include "power_logic.h"

#include "board.h"

vbus_src_t power_pick_source(bool wanted, uint32_t batt_mv) {
    if (!wanted) return VBUS_SRC_OFF;
    return batt_mv >= BATTERY_PRESENT_MV ? VBUS_SRC_BATTERY : VBUS_SRC_DEV;
}

size_t power_sequence(vbus_src_t from, vbus_src_t to, pin_write_t out[6]) {
    (void)from;  // Every enable is driven low first, whatever the old state.
    size_t n = 0;
    if (to != VBUS_SRC_BATTERY) out[n++] = (pin_write_t){PIN_BOOST_EN, 0};
    if (to != VBUS_SRC_DEV) out[n++] = (pin_write_t){PIN_DEV_VBUS_EN, 0};
    out[n++] = (pin_write_t){PIN_LIMIT_EN, to == VBUS_SRC_OFF ? 0 : 1};
    if (to == VBUS_SRC_BATTERY) out[n++] = (pin_write_t){PIN_BOOST_EN, 1};
    if (to == VBUS_SRC_DEV) out[n++] = (pin_write_t){PIN_DEV_VBUS_EN, 1};
    return n;
}

uint32_t power_adc_to_mv(uint32_t pin_mv, uint32_t div_x10) {
    return (uint32_t)(((uint64_t)pin_mv * div_x10) / 10);
}

const char *power_source_name(vbus_src_t s) {
    switch (s) {
        case VBUS_SRC_DEV: return "dev";
        case VBUS_SRC_BATTERY: return "battery";
        default: return "off";
    }
}
