// SPDX-License-Identifier: Apache-2.0
//
// What the bridge screen shows, decided without any hardware or LVGL access so
// it can be tested on the host. The firmware never works out gas states
// itself: LAST_RESULT and LIVE_STATE show only what the app sent in FB and
// STATE.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define UI_RESULT_MS 10000        // the last result shows this long after its FB
#define UI_STATE_STALE_MS 10000   // no STATE for longer than this: phone not responding
#define UI_SOLO_NO_DATA_MS 4000   // attached, no line since attach for longer than this

typedef enum {
    UI_BATTERY_EMPTY,
    UI_WAITING_FOR_PHONE,
    UI_CONNECTION_LOST,
    UI_PHONE_NOT_RESPONDING,
    UI_NO_SOLO,
    UI_SOLO_NO_DATA,
    UI_HELD_SAVING,
    UI_FULL,
    UI_BATTERY_LOW,
    UI_LAST_RESULT,
    UI_LIVE_STATE,
    UI_IDLE
} ui_main_t;

typedef struct {
    uint64_t now_ms;
    bool phone_ever, phone_connected, live_on;
    // When the last STATE arrived; 0 = never. While LIVE ON is active and no
    // STATE has come yet, the caller sets this to the time LIVE ON arrived so
    // the 10 s start there.
    uint64_t last_state_ms;
    // When the SOLO's current unbroken data flow began; 0 = no data flowing
    // now. The app only sends STATE while it has a reading, so the phone is
    // judged silent only while data flows, and only 10 s after it (re)started.
    uint64_t flow_start_ms;
    bool solo, solo_had_line;  // solo_had_line: a line since this attach
    uint64_t solo_attach_ms;
    bool held_waiting_fb, full;
    uint32_t batt_mv;          // under BATTERY_PRESENT_MV (3000) means no battery fitted
    uint64_t last_fb_ms;       // 0 = never
    // The last FB: wire code (printed, saved, check, skipped, error) and text.
    char fb_code[16];
    char fb_text[48];
    // The last STATE: wire code (settling, stable, sensor_error, air) and mix.
    char live_state[16];
    char live_mix[16];
} ui_inputs_t;

typedef enum { UI_TONE_NEUTRAL, UI_TONE_GREEN, UI_TONE_AMBER, UI_TONE_RED } ui_tone_t;

// The spec §2 order, with BATTERY_EMPTY first and BATTERY_LOW after FULL.
// A battery below BATTERY_PRESENT_MV (USB powered) gives no battery state.
ui_main_t ui_pick(const ui_inputs_t *in);

// The main-area text, ASCII only, always NUL terminated in buf. Returns buf.
// "WAITING FOR PHONE", "CONNECTION LOST", "PHONE NOT RESPONDING", "NO SOLO",
// "SOLO: TURN ON SEND DATA TO USB", "HELD - SAVING...", "FULL - CONNECT PHONE",
// "BATTERY EMPTY", "BATTERY LOW", "READY".
// LAST_RESULT by FB code: printed "PRINTED <TEXT>", saved "SAVED - <TEXT>",
// check "CHECK PHONE: <TEXT>", skipped and error just "<TEXT>" (e.g. "AIR - NOT
// LOGGED", "NO READING"; "SKIPPED"/"ERROR" when the text is empty).
// LIVE_STATE: "SETTLING... <MIX>", "STABLE <MIX>", "SENSOR ERROR", "AIR".
const char *ui_main_text(ui_main_t m, const ui_inputs_t *in, char *buf, size_t cap);

// Green: printed, saved, stable. Amber: check, settling, held, full, battery
// low, no SOLO, SOLO no data. Red: error, sensor error, connection lost, phone
// not responding, battery empty. Everything else neutral.
ui_tone_t ui_tone(ui_main_t m, const ui_inputs_t *in);

// LVGL built-in symbols (UTF-8 of LV_SYMBOL_OK and LV_SYMBOL_CLOSE), present in
// the built-in Montserrat fonts. Change these two if a font lacks them.
#define UI_GLYPH_YES "\xEF\x80\x8C"
#define UI_GLYPH_NO "\xEF\x80\x8D"

// "SOLO <y/n>  PHONE <y/n>  3.9V  5V". USB replaces the voltage when no
// battery is fitted; "5V" shows only while host 5 V is on. Returns buf.
const char *ui_status_line(char *buf, size_t cap, bool solo, bool phone, uint32_t batt_mv,
                           bool vbus_on);
