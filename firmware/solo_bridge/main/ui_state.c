// SPDX-License-Identifier: Apache-2.0
#include "ui_state.h"

#include <ctype.h>
#include <stdio.h>
#include <string.h>

#include "power_logic.h"

static uint64_t since(uint64_t now, uint64_t then) { return now > then ? now - then : 0; }

static bool has_battery(const ui_inputs_t *in) { return in->batt_mv >= BATTERY_PRESENT_MV; }

ui_main_t ui_pick(const ui_inputs_t *in) {
    if (has_battery(in) && in->batt_mv < BATTERY_EMPTY_MV) return UI_BATTERY_EMPTY;
    if (!in->phone_ever) return UI_WAITING_FOR_PHONE;
    if (!in->phone_connected) return UI_CONNECTION_LOST;
    if (in->live_on && since(in->now_ms, in->last_state_ms) > UI_STATE_STALE_MS)
        return UI_PHONE_NOT_RESPONDING;
    if (!in->solo) return UI_NO_SOLO;
    if (!in->solo_had_line && since(in->now_ms, in->solo_attach_ms) > UI_SOLO_NO_DATA_MS)
        return UI_SOLO_NO_DATA;
    if (in->held_waiting_fb) return UI_HELD_SAVING;
    if (in->full) return UI_FULL;
    if (has_battery(in) && in->batt_mv < BATTERY_LOW_MV) return UI_BATTERY_LOW;
    if (in->last_fb_ms != 0 && since(in->now_ms, in->last_fb_ms) < UI_RESULT_MS)
        return UI_LAST_RESULT;
    if (in->last_state_ms != 0 && since(in->now_ms, in->last_state_ms) <= UI_STATE_STALE_MS)
        return UI_LIVE_STATE;
    return UI_IDLE;
}

// Appends src upper-cased, truncating, keeping buf terminated.
static void put_upper(char *buf, size_t cap, const char *src) {
    size_t n = strlen(buf);
    for (; *src != '\0' && n + 1 < cap; src++) buf[n++] = (char)toupper((unsigned char)*src);
    buf[n] = '\0';
}

static void put_text(char *buf, size_t cap, const char *prefix, const char *text) {
    buf[0] = '\0';
    put_upper(buf, cap, prefix);
    if (text[0] != '\0') put_upper(buf, cap, text);
}

static void with_mix(char *buf, size_t cap, const char *word, const char *mix) {
    buf[0] = '\0';
    put_upper(buf, cap, word);
    if (mix[0] != '\0') {
        put_upper(buf, cap, " ");
        put_upper(buf, cap, mix);
    }
}

const char *ui_main_text(ui_main_t m, const ui_inputs_t *in, char *buf, size_t cap) {
    if (cap == 0) return buf;
    buf[0] = '\0';
    const char *fixed = NULL;
    switch (m) {
        case UI_BATTERY_EMPTY: fixed = "BATTERY EMPTY"; break;
        case UI_WAITING_FOR_PHONE: fixed = "WAITING FOR PHONE"; break;
        case UI_CONNECTION_LOST: fixed = "CONNECTION LOST"; break;
        case UI_PHONE_NOT_RESPONDING: fixed = "PHONE NOT RESPONDING"; break;
        case UI_NO_SOLO: fixed = "NO SOLO"; break;
        case UI_SOLO_NO_DATA: fixed = "SOLO: TURN ON SEND DATA TO USB"; break;
        case UI_HELD_SAVING: fixed = "HELD - SAVING..."; break;
        case UI_FULL: fixed = "FULL - CONNECT PHONE"; break;
        case UI_BATTERY_LOW: fixed = "BATTERY LOW"; break;
        case UI_IDLE: fixed = "READY"; break;
        case UI_LAST_RESULT: {
            const char *c = in->fb_code;
            if (strcmp(c, "printed") == 0) put_text(buf, cap, "PRINTED ", in->fb_text);
            else if (strcmp(c, "saved") == 0) {
                if (in->fb_text[0] != '\0') put_text(buf, cap, "SAVED - ", in->fb_text);
                else put_upper(buf, cap, "SAVED");
            } else if (strcmp(c, "check") == 0) put_text(buf, cap, "CHECK PHONE: ", in->fb_text);
            else if (in->fb_text[0] != '\0') put_upper(buf, cap, in->fb_text);
            else put_upper(buf, cap, strcmp(c, "skipped") == 0 ? "SKIPPED" : "ERROR");
            return buf;
        }
        case UI_LIVE_STATE: {
            const char *s = in->live_state;
            if (strcmp(s, "settling") == 0) with_mix(buf, cap, "SETTLING...", in->live_mix);
            else if (strcmp(s, "stable") == 0) with_mix(buf, cap, "STABLE", in->live_mix);
            else if (strcmp(s, "sensor_error") == 0 || strcmp(s, "error") == 0)
                put_upper(buf, cap, "SENSOR ERROR");
            else if (strcmp(s, "air") == 0) put_upper(buf, cap, "AIR");
            else put_upper(buf, cap, "READY");
            return buf;
        }
    }
    if (fixed != NULL) put_upper(buf, cap, fixed);
    return buf;
}

ui_tone_t ui_tone(ui_main_t m, const ui_inputs_t *in) {
    switch (m) {
        case UI_BATTERY_EMPTY:
        case UI_CONNECTION_LOST:
        case UI_PHONE_NOT_RESPONDING: return UI_TONE_RED;
        case UI_NO_SOLO:
        case UI_SOLO_NO_DATA:
        case UI_HELD_SAVING:
        case UI_FULL:
        case UI_BATTERY_LOW: return UI_TONE_AMBER;
        case UI_LAST_RESULT:
            if (strcmp(in->fb_code, "printed") == 0 || strcmp(in->fb_code, "saved") == 0)
                return UI_TONE_GREEN;
            if (strcmp(in->fb_code, "check") == 0) return UI_TONE_AMBER;
            if (strcmp(in->fb_code, "error") == 0) return UI_TONE_RED;
            return UI_TONE_NEUTRAL;
        case UI_LIVE_STATE:
            if (strcmp(in->live_state, "stable") == 0) return UI_TONE_GREEN;
            if (strcmp(in->live_state, "settling") == 0) return UI_TONE_AMBER;
            if (strcmp(in->live_state, "sensor_error") == 0 || strcmp(in->live_state, "error") == 0)
                return UI_TONE_RED;
            return UI_TONE_NEUTRAL;
        case UI_WAITING_FOR_PHONE:
        case UI_IDLE: break;
    }
    return UI_TONE_NEUTRAL;
}

const char *ui_status_line(char *buf, size_t cap, bool solo, bool phone, uint32_t batt_mv,
                           bool vbus_on) {
    if (cap == 0) return buf;
    char power[16];
    if (batt_mv >= BATTERY_PRESENT_MV) {
        uint32_t tenths = (batt_mv + 50) / 100;  // 3.9 V
        snprintf(power, sizeof power, "%u.%uV", (unsigned)(tenths / 10), (unsigned)(tenths % 10));
    } else {
        snprintf(power, sizeof power, "USB");
    }
    snprintf(buf, cap, "SOLO %s  PHONE %s  %s%s", solo ? UI_GLYPH_YES : UI_GLYPH_NO,
             phone ? UI_GLYPH_YES : UI_GLYPH_NO, power, vbus_on ? "  5V" : "");
    return buf;
}
