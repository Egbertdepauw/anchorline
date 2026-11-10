// SPDX-License-Identifier: Apache-2.0
//
// What the bridge knows about itself, for the screen and the LEDs. main.c
// refreshes it about every 100 ms and on every event; readers get a copy.
//
// The bridge never works out a gas state itself: `state`, `mix`, `fb_code`
// and `fb_text` are what the app sent in STATE and FB, kept verbatim with the
// uptime they arrived at.
#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct {
    uint64_t now_ms;  // uptime when the snapshot was made; compare the *_ms fields to it

    bool phone_connected;  // a phone is connected and subscribed now
    bool phone_ever;       // a phone has subscribed since power-on
    bool live_on;          // the phone asked for L lines (LIVE ON)

    bool solo_attached;
    uint64_t solo_attach_ms;  // uptime of the last attach; 0 while detached
    bool solo_had_line;       // a data line has come since that attach
    uint64_t last_data_ms;    // uptime of the last data line; 0 = none since power-on

    bool held_waiting_fb;  // a record was made and its FB has not come yet
    bool store_full;       // the queue is full: OK makes no records
    uint32_t pending;      // records waiting for the phone's ACK

    uint32_t batt_mv;  // 0 when unreadable; under 3000 means no battery
    bool vbus_on;      // the host port's 5 V is on

    uint64_t last_fb_ms;  // uptime the last FB arrived; 0 = none yet
    char fb_code[10];     // printed, saved, check, skipped or error
    char fb_text[25];

    uint64_t last_state_ms;  // uptime the last STATE arrived; 0 = none yet
    char state[16];          // settling, stable, sensor_error or air
    char mix[17];            // "" when none
} bridge_state_t;

// Copies the latest snapshot. Safe from any task. Zeroed before the first
// refresh.
void bridge_state_get(bridge_state_t *out);

// For main.c only: replaces the snapshot.
void bridge_state_publish(const bridge_state_t *in);
