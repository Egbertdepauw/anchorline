// SPDX-License-Identifier: Apache-2.0
//
// The bridge's colour screen: LVGL through the board support package's display
// part only. What to show is decided by ui_state.c.
#pragma once
#include <stdbool.h>
#include <stdint.h>

#include "ui_state.h"

// Starts LVGL, builds the screen and switches the backlight on. Touches no USB
// or power pin. Call once, after power_init().
void ui_start(void);

// Hands the screen its latest inputs (copied under a lock; callable from any
// task). `pending` is the number of records waiting for the phone. The screen
// redraws itself every 250 ms. inputs->now_ms is the uptime in ms.
void ui_set_inputs(const ui_inputs_t *in, uint32_t pending, bool vbus_on);

// Shows the info screen for 5 s, then goes back to the status screen.
void ui_show_info(const char *bridge_id, const char *fw, uint32_t batt_mv, uint32_t host_vbus_mv,
                  const char *vbus_src, const char *epoch);
