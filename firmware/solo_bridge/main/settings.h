// SPDX-License-Identifier: Apache-2.0
//
// Settings kept in NVS across power-offs.
#pragma once
#include <stdbool.h>
#include <stdint.h>

// Initialises NVS and counts this boot.
void settings_init(void);

bool settings_vbus(void);  // host 5 V wanted; default off
void settings_set_vbus(bool on);
bool settings_rec(void);  // "Log on OK"; default off
void settings_set_rec(bool on);

uint32_t settings_boot(void);  // this boot's number, from 1

// 8 lowercase hex digits, made once at first boot. New after a flash erase,
// so a reset record counter can't collide with old record ids.
const char *settings_epoch(void);
