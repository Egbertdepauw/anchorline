// SPDX-License-Identifier: Apache-2.0
#include <string.h>

#include "check.h"
#include "ui_state.h"

// A healthy, connected, idle bridge at t = 100 s; each test breaks one thing.
static ui_inputs_t healthy(void) {
    ui_inputs_t in;
    memset(&in, 0, sizeof in);
    in.now_ms = 100000;
    in.phone_ever = in.phone_connected = true;
    in.solo = in.solo_had_line = true;
    in.solo_attach_ms = 1000;
    in.batt_mv = 3900;
    return in;
}

static void set(char *dst, size_t cap, const char *src) {
    strncpy(dst, src, cap - 1);
    dst[cap - 1] = '\0';
}

static const char *text(const ui_inputs_t *in) {
    static char buf[64];
    return ui_main_text(ui_pick(in), in, buf, sizeof buf);
}

TEST_SUITE(test_ui_state) {
    ui_inputs_t in = healthy();
    CHECK(ui_pick(&in) == UI_IDLE);
    CHECK_STR_EQ(text(&in), "READY");

    // One case per priority row, every higher row false.
    in = healthy();
    in.batt_mv = 3200;
    CHECK(ui_pick(&in) == UI_BATTERY_EMPTY);
    CHECK_STR_EQ(text(&in), "BATTERY EMPTY");
    CHECK(ui_tone(UI_BATTERY_EMPTY, &in) == UI_TONE_RED);

    in = healthy();
    in.phone_ever = in.phone_connected = false;
    CHECK(ui_pick(&in) == UI_WAITING_FOR_PHONE);
    CHECK_STR_EQ(text(&in), "WAITING FOR PHONE");

    // Empty battery beats waiting for phone.
    in.batt_mv = 3200;
    CHECK(ui_pick(&in) == UI_BATTERY_EMPTY);

    in = healthy();
    in.phone_connected = false;
    CHECK(ui_pick(&in) == UI_CONNECTION_LOST);
    CHECK_STR_EQ(text(&in), "CONNECTION LOST");
    CHECK(ui_tone(UI_CONNECTION_LOST, &in) == UI_TONE_RED);

    in = healthy();
    in.live_on = true;
    in.flow_start_ms = in.now_ms - 60000;
    in.last_state_ms = in.now_ms - 10001;
    CHECK(ui_pick(&in) == UI_PHONE_NOT_RESPONDING);
    CHECK_STR_EQ(text(&in), "PHONE NOT RESPONDING");
    in.last_state_ms = in.now_ms - 9999;
    CHECK(ui_pick(&in) != UI_PHONE_NOT_RESPONDING);
    // With no data flowing the app has no reading and sends no STATE: fine.
    in.last_state_ms = in.now_ms - 20000;
    in.flow_start_ms = 0;
    CHECK(ui_pick(&in) != UI_PHONE_NOT_RESPONDING);
    // The 10 s count from when the flow (re)started, not from the old STATE.
    in.flow_start_ms = in.now_ms - 9999;
    CHECK(ui_pick(&in) != UI_PHONE_NOT_RESPONDING);
    in.flow_start_ms = in.now_ms - 10001;
    CHECK(ui_pick(&in) == UI_PHONE_NOT_RESPONDING);
    // Without LIVE ON a silent phone is fine.
    in.flow_start_ms = in.now_ms - 60000;
    in.live_on = false;
    in.last_state_ms = in.now_ms - 20000;
    CHECK(ui_pick(&in) == UI_IDLE);

    in = healthy();
    in.solo = false;
    CHECK(ui_pick(&in) == UI_NO_SOLO);
    CHECK_STR_EQ(text(&in), "NO SOLO");

    in = healthy();
    in.solo_had_line = false;
    in.solo_attach_ms = in.now_ms - 4001;
    CHECK(ui_pick(&in) == UI_SOLO_NO_DATA);
    CHECK_STR_EQ(text(&in), "SOLO: TURN ON SEND DATA TO USB");
    in.solo_attach_ms = in.now_ms - 4000;
    CHECK(ui_pick(&in) == UI_IDLE);

    in = healthy();
    in.held_waiting_fb = true;
    CHECK(ui_pick(&in) == UI_HELD_SAVING);
    CHECK_STR_EQ(text(&in), "HELD - SAVING...");
    CHECK(ui_tone(UI_HELD_SAVING, &in) == UI_TONE_AMBER);

    in = healthy();
    in.full = true;
    CHECK(ui_pick(&in) == UI_FULL);
    CHECK_STR_EQ(text(&in), "FULL - CONNECT PHONE");
    in.held_waiting_fb = true;  // held outranks full
    CHECK(ui_pick(&in) == UI_HELD_SAVING);

    in = healthy();
    in.batt_mv = 3400;
    CHECK(ui_pick(&in) == UI_BATTERY_LOW);
    CHECK_STR_EQ(text(&in), "BATTERY LOW");
    in.full = true;  // low comes after full
    CHECK(ui_pick(&in) == UI_FULL);
    in.full = false;
    in.batt_mv = 3500;
    CHECK(ui_pick(&in) == UI_IDLE);

    // No battery (USB powered): no battery state.
    in = healthy();
    in.batt_mv = 0;
    CHECK(ui_pick(&in) == UI_IDLE);
    in.batt_mv = 2999;
    CHECK(ui_pick(&in) == UI_IDLE);
    in.batt_mv = 3000;
    CHECK(ui_pick(&in) == UI_BATTERY_EMPTY);

    // Last result: 9999 ms yes, 10001 ms no (then the live state).
    in = healthy();
    set(in.fb_code, sizeof in.fb_code, "printed");
    set(in.fb_text, sizeof in.fb_text, "EAN32");
    in.last_fb_ms = in.now_ms - 9999;
    CHECK(ui_pick(&in) == UI_LAST_RESULT);
    CHECK_STR_EQ(text(&in), "PRINTED EAN32");
    CHECK(ui_tone(UI_LAST_RESULT, &in) == UI_TONE_GREEN);
    in.last_fb_ms = in.now_ms - 10001;
    CHECK(ui_pick(&in) == UI_IDLE);
    set(in.live_state, sizeof in.live_state, "stable");
    set(in.live_mix, sizeof in.live_mix, "TX21/35");
    in.last_state_ms = in.now_ms - 1000;
    CHECK(ui_pick(&in) == UI_LIVE_STATE);
    // A result outranks the live state.
    in.last_fb_ms = in.now_ms - 100;
    CHECK(ui_pick(&in) == UI_LAST_RESULT);

    // Last-result texts.
    in = healthy();
    in.last_fb_ms = in.now_ms - 100;
    set(in.fb_code, sizeof in.fb_code, "saved");
    set(in.fb_text, sizeof in.fb_text, "Sign off later");
    CHECK_STR_EQ(text(&in), "SAVED - SIGN OFF LATER");
    CHECK(ui_tone(UI_LAST_RESULT, &in) == UI_TONE_GREEN);
    set(in.fb_code, sizeof in.fb_code, "check");
    set(in.fb_text, sizeof in.fb_text, "MISMATCH");
    CHECK_STR_EQ(text(&in), "CHECK PHONE: MISMATCH");
    CHECK(ui_tone(UI_LAST_RESULT, &in) == UI_TONE_AMBER);
    set(in.fb_code, sizeof in.fb_code, "skipped");
    set(in.fb_text, sizeof in.fb_text, "AIR - NOT LOGGED");
    CHECK_STR_EQ(text(&in), "AIR - NOT LOGGED");
    CHECK(ui_tone(UI_LAST_RESULT, &in) == UI_TONE_NEUTRAL);
    set(in.fb_code, sizeof in.fb_code, "error");
    set(in.fb_text, sizeof in.fb_text, "NO READING");
    CHECK_STR_EQ(text(&in), "NO READING");
    CHECK(ui_tone(UI_LAST_RESULT, &in) == UI_TONE_RED);
    in.fb_text[0] = '\0';
    CHECK_STR_EQ(text(&in), "ERROR");
    set(in.fb_code, sizeof in.fb_code, "saved");
    CHECK_STR_EQ(text(&in), "SAVED");

    // Live-state texts.
    in = healthy();
    in.last_state_ms = in.now_ms - 500;
    set(in.live_state, sizeof in.live_state, "settling");
    set(in.live_mix, sizeof in.live_mix, "TX21/35");
    CHECK_STR_EQ(text(&in), "SETTLING... TX21/35");
    CHECK(ui_tone(UI_LIVE_STATE, &in) == UI_TONE_AMBER);
    set(in.live_state, sizeof in.live_state, "stable");
    CHECK_STR_EQ(text(&in), "STABLE TX21/35");
    CHECK(ui_tone(UI_LIVE_STATE, &in) == UI_TONE_GREEN);
    in.live_mix[0] = '\0';
    CHECK_STR_EQ(text(&in), "STABLE");
    set(in.live_state, sizeof in.live_state, "sensor_error");
    CHECK_STR_EQ(text(&in), "SENSOR ERROR");
    CHECK(ui_tone(UI_LIVE_STATE, &in) == UI_TONE_RED);
    set(in.live_state, sizeof in.live_state, "air");
    CHECK_STR_EQ(text(&in), "AIR");
    CHECK(ui_tone(UI_LIVE_STATE, &in) == UI_TONE_NEUTRAL);

    // Truncation keeps the buffer terminated.
    char tiny[6];
    ui_main_text(UI_NO_SOLO, &in, tiny, sizeof tiny);
    CHECK_STR_EQ(tiny, "NO SO");

    // Status line.
    char line[64];
    CHECK_STR_EQ(ui_status_line(line, sizeof line, true, false, 3900, true),
                 "SOLO " UI_GLYPH_YES "  PHONE " UI_GLYPH_NO "  3.9V  5V");
    CHECK_STR_EQ(ui_status_line(line, sizeof line, false, true, 4150, false),
                 "SOLO " UI_GLYPH_NO "  PHONE " UI_GLYPH_YES "  4.2V");
    CHECK_STR_EQ(ui_status_line(line, sizeof line, true, true, 0, false),
                 "SOLO " UI_GLYPH_YES "  PHONE " UI_GLYPH_YES "  USB");
}
