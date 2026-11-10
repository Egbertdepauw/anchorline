// SPDX-License-Identifier: Apache-2.0
#include "ui.h"

#include <stdio.h>
#include <string.h>

#include "bsp/esp32_s3_usb_otg.h"
#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "lvgl.h"
#include "text_fit.h"

#define REDRAW_MS 250
#define INFO_MS 5000
#define MARGIN 8
#define STATUS_Y 6
#define PENDING_Y 26
#define MAIN_TOP 50  // the main text lives in y = MAIN_TOP .. 240 - MARGIN

static const char *TAG = "ui";

#define COL_BG lv_color_hex(0x0B0F14)
#define COL_NEUTRAL lv_color_hex(0xE6EDF3)
#define COL_DIM lv_color_hex(0x8B97A5)
#define COL_GREEN lv_color_hex(0x3DDC84)
#define COL_AMBER lv_color_hex(0xFFB020)
#define COL_RED lv_color_hex(0xFF5A5A)

#define MAIN_MAX_LINES 4
#define MAIN_H (240 - MARGIN - MAIN_TOP)
#define MAIN_W (240 - 2 * MARGIN)

// Largest first; the first one that fits the text in at most MAIN_MAX_LINES
// lines, breaking only between words, is used.
static const lv_font_t *const kMainFonts[] = {&lv_font_montserrat_48, &lv_font_montserrat_40,
                                              &lv_font_montserrat_32, &lv_font_montserrat_28,
                                              &lv_font_montserrat_24, &lv_font_montserrat_20};

typedef struct {
    char bridge_id[16], fw[16], vbus_src[16], epoch[16];
    uint32_t batt_mv, host_vbus_mv;
    uint64_t until_ms;  // 0 = not showing
} info_t;

static SemaphoreHandle_t s_lock;
static ui_inputs_t s_in;
static uint32_t s_pending;
static bool s_vbus_on;
static info_t s_info;

static lv_obj_t *s_status, *s_pending_lbl, *s_main;
static int32_t s_shown_y = -1;
// What the labels show now, so an unchanged screen is not touched.
static char s_shown_status[64], s_shown_pending[32], s_shown_main[160];
static const lv_font_t *s_shown_font;
static uint32_t s_shown_color = 0xFFFFFFFF;

static uint64_t now_ms(void) { return (uint64_t)(esp_timer_get_time() / 1000); }

static lv_color_t tone_color(ui_tone_t t) {
    switch (t) {
        case UI_TONE_GREEN: return COL_GREEN;
        case UI_TONE_AMBER: return COL_AMBER;
        case UI_TONE_RED: return COL_RED;
        case UI_TONE_NEUTRAL: break;
    }
    return COL_NEUTRAL;
}

static void set_label(lv_obj_t *l, char *shown, size_t cap, const char *text) {
    if (strcmp(shown, text) == 0) return;
    snprintf(shown, cap, "%s", text);
    lv_label_set_text(l, text);
}

// Width of n bytes of one line in the font passed as ctx.
static int32_t measure(const char *s, size_t n, void *ctx) {
    char buf[160];
    if (n >= sizeof buf) n = sizeof buf - 1;
    memcpy(buf, s, n);
    buf[n] = '\0';
    lv_point_t size;
    lv_text_get_size(&size, buf, (const lv_font_t *)ctx, 0, 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
    return size.x;
}

// Picks the largest font that fits `text` in the main area in at most
// MAIN_MAX_LINES lines without splitting a word, and writes the text with its
// line breaks to `wrapped`. Sets *lines. Falls back to the smallest font and
// LVGL's own wrapping when nothing fits.
static const lv_font_t *fit_text(const char *text, char *wrapped, size_t cap, int *lines) {
    const size_t n = sizeof kMainFonts / sizeof kMainFonts[0];
    for (size_t i = 0; i < n; i++) {
        const lv_font_t *f = kMainFonts[i];
        int max_lines = MAIN_H / lv_font_get_line_height(f);
        if (max_lines > MAIN_MAX_LINES) max_lines = MAIN_MAX_LINES;
        if (max_lines < 1) continue;
        int got = text_fit_wrap(text, MAIN_W, max_lines, measure, (void *)f, wrapped, cap);
        if (got >= 0) {
            *lines = got;
            return f;
        }
    }
    snprintf(wrapped, cap, "%s", text);
    *lines = MAIN_MAX_LINES;
    return kMainFonts[n - 1];
}

// Shows the main text; `lines` centres the block vertically (0 = top).
static void show_main(const char *text, const lv_font_t *font, int lines, lv_color_t color,
                      lv_text_align_t align) {
    uint32_t rgb = lv_color_to_u32(color);
    int32_t y = MAIN_TOP;
    if (lines > 0) {
        int32_t h = lines * lv_font_get_line_height(font);
        if (h < MAIN_H) y += (MAIN_H - h) / 2;
    }
    if (y != s_shown_y) {
        lv_obj_set_y(s_main, y);
        lv_obj_set_height(s_main, 240 - MARGIN - y);
        s_shown_y = y;
    }
    set_label(s_main, s_shown_main, sizeof s_shown_main, text);
    if (font != s_shown_font) {
        lv_obj_set_style_text_font(s_main, font, 0);
        s_shown_font = font;
    }
    if (rgb != s_shown_color) {
        lv_obj_set_style_text_color(s_main, color, 0);
        s_shown_color = rgb;
    }
    lv_obj_set_style_text_align(s_main, align, 0);
}

static void redraw(lv_timer_t *timer) {
    (void)timer;
    ui_inputs_t in;
    info_t info;
    uint32_t pending;
    bool vbus_on;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    in = s_in;
    info = s_info;
    pending = s_pending;
    vbus_on = s_vbus_on;
    xSemaphoreGive(s_lock);

    char line[160];
    if (info.until_ms != 0 && now_ms() < info.until_ms) {
        set_label(s_status, s_shown_status, sizeof s_shown_status, "INFO");
        set_label(s_pending_lbl, s_shown_pending, sizeof s_shown_pending, "");
        snprintf(line, sizeof line,
                 "ID %s\nFW %s\nBATT %u mV\nHOST VBUS %u mV\n5V SRC %s\nEPOCH %s", info.bridge_id,
                 info.fw, (unsigned)info.batt_mv, (unsigned)info.host_vbus_mv, info.vbus_src,
                 info.epoch);
        show_main(line, &lv_font_montserrat_16, 0, COL_NEUTRAL, LV_TEXT_ALIGN_LEFT);
        return;
    }

    char status[64];
    ui_status_line(status, sizeof status, in.solo, in.phone_connected, in.batt_mv, vbus_on);
    set_label(s_status, s_shown_status, sizeof s_shown_status, status);

    char pend[32] = "";
    if (pending > 0) snprintf(pend, sizeof pend, "%u waiting for phone", (unsigned)pending);
    set_label(s_pending_lbl, s_shown_pending, sizeof s_shown_pending, pend);

    ui_main_t m = ui_pick(&in);
    ui_main_text(m, &in, line, sizeof line);
    char wrapped[sizeof line];
    int lines;
    const lv_font_t *font = fit_text(line, wrapped, sizeof wrapped, &lines);
    show_main(wrapped, font, lines, tone_color(ui_tone(m, &in)), LV_TEXT_ALIGN_CENTER);
}

static lv_obj_t *make_label(const lv_font_t *font, lv_color_t color, int32_t y) {
    lv_obj_t *l = lv_label_create(lv_screen_active());
    lv_obj_set_width(l, 240 - 2 * MARGIN);
    lv_obj_set_pos(l, MARGIN, y);
    lv_label_set_long_mode(l, LV_LABEL_LONG_MODE_CLIP);
    lv_obj_set_style_text_font(l, font, 0);
    lv_obj_set_style_text_color(l, color, 0);
    lv_label_set_text(l, "");
    return l;
}

void ui_start(void) {
    s_lock = xSemaphoreCreateMutex();
    // Display, SPI3, LVGL task and the backlight PWM only; the BSP's USB and
    // power functions are never called.
    lv_display_t *disp = bsp_display_start();
    if (disp == NULL) {
        ESP_LOGE(TAG, "display start failed");
        return;
    }
    bsp_display_lock(0);
    lv_obj_t *scr = lv_screen_active();
    lv_obj_set_style_bg_color(scr, COL_BG, 0);
    lv_obj_set_style_bg_opa(scr, LV_OPA_COVER, 0);
    lv_obj_set_scrollable(scr, false);

    s_status = make_label(&lv_font_montserrat_14, COL_DIM, STATUS_Y);
    s_pending_lbl = make_label(&lv_font_montserrat_16, COL_AMBER, PENDING_Y);
    s_main = make_label(&lv_font_montserrat_24, COL_NEUTRAL, MAIN_TOP);
    lv_obj_set_height(s_main, 240 - MARGIN - MAIN_TOP);
    lv_label_set_long_mode(s_main, LV_LABEL_LONG_MODE_WRAP);
    lv_obj_set_style_text_align(s_main, LV_TEXT_ALIGN_CENTER, 0);

    lv_timer_create(redraw, REDRAW_MS, NULL);
    redraw(NULL);
    bsp_display_unlock();
    bsp_display_backlight_on();
}

void ui_set_inputs(const ui_inputs_t *in, uint32_t pending, bool vbus_on) {
    if (s_lock == NULL) return;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    s_in = *in;
    s_pending = pending;
    s_vbus_on = vbus_on;
    xSemaphoreGive(s_lock);
}

void ui_show_info(const char *bridge_id, const char *fw, uint32_t batt_mv, uint32_t host_vbus_mv,
                  const char *vbus_src, const char *epoch) {
    if (s_lock == NULL) return;
    xSemaphoreTake(s_lock, portMAX_DELAY);
    snprintf(s_info.bridge_id, sizeof s_info.bridge_id, "%s", bridge_id);
    snprintf(s_info.fw, sizeof s_info.fw, "%s", fw);
    snprintf(s_info.vbus_src, sizeof s_info.vbus_src, "%s", vbus_src);
    snprintf(s_info.epoch, sizeof s_info.epoch, "%s", epoch);
    s_info.batt_mv = batt_mv;
    s_info.host_vbus_mv = host_vbus_mv;
    s_info.until_ms = now_ms() + INFO_MS;
    xSemaphoreGive(s_lock);
}
