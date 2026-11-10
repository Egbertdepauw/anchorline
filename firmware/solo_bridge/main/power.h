// SPDX-License-Identifier: Apache-2.0
//
// The board's power: the host port's 5 V, and the battery and host-VBUS
// voltages.
#pragma once
#include <stdbool.h>
#include <stdint.h>

#include "power_logic.h"

// USB_SEL high (the native USB goes to the host port), host 5 V off.
void power_init(void);

// Switches the host port's 5 V on or off; see power_pick_source.
void power_set_vbus(bool wanted);
vbus_src_t power_vbus_source(void);

// 0 when the ADC could not be read. A battery under BATTERY_PRESENT_MV means
// none is fitted.
uint32_t power_battery_mv(void);
uint32_t power_host_vbus_mv(void);
