// SPDX-License-Identifier: Apache-2.0
//
// The rules for the host port's 5 V, without any hardware access, so they
// can be tested on the host.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

typedef enum { VBUS_SRC_OFF, VBUS_SRC_DEV, VBUS_SRC_BATTERY } vbus_src_t;

#define BATTERY_PRESENT_MV 3000  // below this no battery is fitted (USB powered)
#define BATTERY_LOW_MV 3500
#define BATTERY_EMPTY_MV 3300

// Not wanted: off. Wanted: the battery boost when a battery is fitted, else
// the DEV plug's 5 V.
vbus_src_t power_pick_source(bool wanted, uint32_t batt_mv);

typedef struct {
    uint8_t pin;
    uint8_t level;
} pin_write_t;

// The ordered GPIO writes that move the host port from `from` to `to`:
// the enable being dropped goes low first, then the limiter is set, then the
// new enable goes high. BOOST_EN and DEV_VBUS_EN are never both high, not
// even between two writes. Returns the number of writes (at most 6).
size_t power_sequence(vbus_src_t from, vbus_src_t to, pin_write_t out[6]);

// pin_mv * div_x10 / 10, rounded down.
uint32_t power_adc_to_mv(uint32_t pin_mv, uint32_t div_x10);

const char *power_source_name(vbus_src_t s);
