// SPDX-License-Identifier: Apache-2.0
//
// SOLO bridge: reads a Divesoft SOLO gas analyzer over USB host and passes its
// lines to the Anchorline app over Bluetooth LE (Nordic UART).
//
// One main task owns the state. The USB and Bluetooth callbacks only post
// events to its queue, except live lines, which go straight out from the USB
// task so they keep their order and timing.

#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "ble_link.h"
#include "board.h"
#include "bridge_proto.h"
#include "bridge_state.h"
#include "ui.h"
#include "ui_state.h"
#include "driver/gpio.h"
#include "esp_littlefs.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "hold_detector.h"
#include "line_splitter.h"
#include "outbox.h"
#include "power.h"
#include "record_store.h"
#include "settings.h"
#include "solo_line.h"
#include "usb_solo.h"

#define FW_VERSION "1.0.0"
#define STATUS_EVERY_MS 5000
#define DATA_FRESH_MS 1000  // ST data=1 when a data line came this recently
#define HOLD_TICK_MS 200    // how often the hold detector is asked
#define SEND_RETRY_MS 1000  // wait before sending a record again after a failed send

static const char *TAG = "solo_bridge";

typedef enum { EV_SUBSCRIBED, EV_DISCONNECTED, EV_ATTACH, EV_DETACH, EV_COMMAND } ev_kind_t;
typedef struct {
    ev_kind_t kind;
    proto_cmd_t cmd;
} event_t;

static QueueHandle_t s_events;
static char s_bridge_id[13];  // factory MAC, 12 lowercase hex digits
static volatile bool s_live;  // the phone asked for live lines
static volatile uint64_t s_last_data_ms;  // uptime of the last data line, 0 = none
static volatile uint32_t s_lines;

static record_store_t s_store;
static outbox_t s_outbox;

// The detector is fed from the USB task (lines, attach, detach) and asked from
// the main task, so a mutex guards it. Both structs are big: static.
static SemaphoreHandle_t s_det_lock;
static hold_detector_t s_det;
static hold_t s_hold;

// Owned by the main task.
static bool s_phone_ever;
static bool s_has_time;
static int64_t s_time_offset_ms;  // wall ms = offset + uptime ms, once a TIME has come
static char s_waiting_rid[24];  // the latest record made, until its FB (or ACK) comes
static uint64_t s_send_retry_at;
static uint64_t s_fb_ms, s_state_ms;
static char s_fb_code[10], s_fb_text[25], s_state[16], s_mix[17];
static uint32_t s_batt_mv;
static uint64_t s_batt_read_ms;

// Written by the USB task, read by the main task.
static volatile uint64_t s_attach_ms;
static volatile bool s_had_line;

static uint64_t now_ms(void) { return (uint64_t)(esp_timer_get_time() / 1000); }

static void post(ev_kind_t kind, const proto_cmd_t *cmd) {
    event_t ev = {.kind = kind};
    if (cmd != NULL) ev.cmd = *cmd;
    if (xQueueSend(s_events, &ev, 0) != pdTRUE) ESP_LOGW(TAG, "event queue full");
}

// --- callbacks: post only ---------------------------------------------------

static void on_subscribed(void) { post(EV_SUBSCRIBED, NULL); }
static void on_disconnected(void) {
    s_live = false;
    post(EV_DISCONNECTED, NULL);
}
static void on_command(const proto_cmd_t *cmd) { post(EV_COMMAND, cmd); }
// Attach and detach reset the detector here, on the USB task, so no line is
// ever judged against the other side of one. A hold never fires across them.
static void on_attach(void) {
    xSemaphoreTake(s_det_lock, portMAX_DELAY);
    hold_detector_reset(&s_det);
    xSemaphoreGive(s_det_lock);
    s_had_line = false;
    s_attach_ms = now_ms();
    post(EV_ATTACH, NULL);
}
static void on_detach(void) {
    xSemaphoreTake(s_det_lock, portMAX_DELAY);
    hold_detector_reset(&s_det);
    xSemaphoreGive(s_det_lock);
    s_had_line = false;
    s_attach_ms = 0;
    post(EV_DETACH, NULL);
}

static void on_line(uint64_t up_ms, const char *line) {
    if (solo_is_data_line(line)) {
        s_last_data_ms = up_ms;
        s_had_line = true;
    }
    xSemaphoreTake(s_det_lock, portMAX_DELAY);
    hold_detector_add_line(&s_det, up_ms, line);
    xSemaphoreGive(s_det_lock);
    if (++s_lines % 25 == 0) ESP_LOGI(TAG, "line %s", line);
    if (!s_live) return;
    char msg[SOLO_LINE_MAX + 8];
    if (proto_fmt_live_line(msg, sizeof msg, line) > 0) ble_link_send(msg);
}

// --- the main task ----------------------------------------------------------

static bool data_flowing(void) {
    uint64_t last = s_last_data_ms;
    return last != 0 && now_ms() - last <= DATA_FRESH_MS;
}

static void settings_persist_counter(uint32_t next, void *ctx) {
    (void)ctx;
    settings_set_counter(next);
}

static void send_hello(void) {
    proto_hello_t h = {.fw = FW_VERSION,
                       .bridge = s_bridge_id,
                       .epoch = settings_epoch(),
                       .boot = settings_boot(),
                       .up_ms = now_ms(),
                       .solo = usb_solo_attached(),
                       .rec = settings_rec(),
                       .vbus = settings_vbus(),
                       .batt_mv = power_battery_mv(),
                       .pending = (uint32_t)s_store.count};
    char msg[256];
    if (proto_fmt_hello(msg, sizeof msg, &h) > 0) ble_link_send(msg);
}

static void send_status(void) {
    proto_status_t s = {.solo = usb_solo_attached(),
                        .data = data_flowing(),
                        .pending = (uint32_t)s_store.count,
                        .batt_mv = power_battery_mv(),
                        .up_ms = now_ms()};
    char msg[128];
    if (proto_fmt_status(msg, sizeof msg, &s) > 0) ble_link_send(msg);
}

static uint64_t s_live_ms;      // when LIVE ON arrived; stands in for STATE until the first one
static uint64_t s_ack_blink_ms;  // when the last ACK came, for the green blink
#define ACK_BLINK_MS 300

static void copy_str(char *dst, size_t cap, const char *src) {
    strncpy(dst, src, cap - 1);
    dst[cap - 1] = '\0';
}

// Hands the snapshot to the screen and sets the LEDs from the same picture:
// green blinks on each ACK; yellow is on while records wait, or the store is
// full, the phone is lost, or the battery is low or empty.
static void update_screen_and_leds(const bridge_state_t *st) {
    ui_inputs_t in = {0};
    in.now_ms = st->now_ms;
    in.phone_ever = st->phone_ever;
    in.phone_connected = st->phone_connected;
    in.live_on = st->live_on;
    in.last_state_ms = st->last_state_ms > s_live_ms ? st->last_state_ms : s_live_ms;
    in.solo = st->solo_attached;
    in.solo_had_line = st->solo_had_line;
    in.solo_attach_ms = st->solo_attach_ms;
    in.held_waiting_fb = st->held_waiting_fb;
    in.full = st->store_full;
    in.batt_mv = st->batt_mv;
    in.last_fb_ms = st->last_fb_ms;
    copy_str(in.fb_code, sizeof in.fb_code, st->fb_code);
    copy_str(in.fb_text, sizeof in.fb_text, st->fb_text);
    copy_str(in.live_state, sizeof in.live_state, st->state);
    copy_str(in.live_mix, sizeof in.live_mix, st->mix);
    ui_set_inputs(&in, st->pending, st->vbus_on);

    ui_main_t m = ui_pick(&in);
    bool yellow = st->pending > 0 || m == UI_FULL || m == UI_CONNECTION_LOST ||
                  m == UI_BATTERY_LOW || m == UI_BATTERY_EMPTY;
    gpio_set_level(PIN_LED_YELLOW, yellow);
    gpio_set_level(PIN_LED_GREEN,
                   s_ack_blink_ms != 0 && st->now_ms - s_ack_blink_ms < ACK_BLINK_MS);
}


static void refresh_state(void) {
    uint64_t now = now_ms();
    if (s_batt_read_ms == 0 || now - s_batt_read_ms >= 1000) {  // the ADC is not for every tick
        s_batt_mv = power_battery_mv();
        s_batt_read_ms = now;
    }
    bridge_state_t st = {0};
    st.now_ms = now;
    st.phone_connected = ble_link_subscribed();
    st.phone_ever = s_phone_ever;
    st.live_on = s_live;
    st.solo_attached = usb_solo_attached();
    st.solo_attach_ms = st.solo_attached ? s_attach_ms : 0;
    st.solo_had_line = s_had_line;
    st.last_data_ms = s_last_data_ms;
    st.held_waiting_fb = s_waiting_rid[0] != '\0';
    st.store_full = record_store_full(&s_store);
    st.pending = (uint32_t)s_store.count;
    st.batt_mv = s_batt_mv;
    st.vbus_on = power_vbus_source() != VBUS_SRC_OFF;
    st.last_fb_ms = s_fb_ms;
    strcpy(st.fb_code, s_fb_code);
    strcpy(st.fb_text, s_fb_text);
    st.last_state_ms = s_state_ms;
    strcpy(st.state, s_state);
    strcpy(st.mix, s_mix);
    bridge_state_publish(&st);
    update_screen_and_leds(&st);
}

// Sends one stored record: its REC, W and H lines, then END. False when the
// link could not take a line; the record then goes again from REC.
static bool send_record(const char *rid) {
    FILE *f = record_store_read(&s_store, rid);
    if (f == NULL) return false;
    char line[SOLO_LINE_MAX + 64];
    bool ok = true;
    while (ok && fgets(line, sizeof line, f) != NULL) {
        line[strcspn(line, "\r\n")] = '\0';
        ok = ble_link_send(line);
    }
    fclose(f);
    if (ok) {
        ok = proto_fmt_end(line, sizeof line, rid) > 0 && ble_link_send(line);
    }
    return ok;
}

static void pump_outbox(void) {
    if (!ble_link_subscribed() || now_ms() < s_send_retry_at) return;
    const char *rid = outbox_next(&s_outbox, &s_store);
    if (rid == NULL) return;
    if (send_record(rid)) {
        ESP_LOGI(TAG, "sent record %s", rid);
    } else {
        ESP_LOGW(TAG, "sending %s failed; will resend from REC", rid);
        outbox_on_send_failed(&s_outbox);
        s_send_retry_at = now_ms() + SEND_RETRY_MS;
    }
}

static void make_record(void) {
    if (!settings_rec()) return;  // "Log on OK" is off: OK makes no records at all
    if (record_store_full(&s_store)) {
        // Never overwrite an unconfirmed record: no record, and the yellow LED says so.
        ESP_LOGW(TAG, "hold at %" PRIu64 " ms, but the store is full", s_hold.held_at_ms);
        return;
    }
    record_meta_t m = {.boot = settings_boot(),
                       .up_ms = s_hold.held_at_ms,
                       .wall_ms = s_has_time ? (uint64_t)(s_time_offset_ms + (int64_t)s_hold.held_at_ms) : 0,
                       .live = ble_link_subscribed()};
    char rid[24];
    if (!record_store_put(&s_store, &m, &s_hold, settings_persist_counter, NULL, rid)) {
        ESP_LOGE(TAG, "hold at %" PRIu64 " ms: can't write the record", s_hold.held_at_ms);
        return;
    }
    strcpy(s_waiting_rid, rid);
    ESP_LOGI(TAG, "record %s: %u lines, %u waiting", rid, (unsigned)s_hold.n, (unsigned)s_store.count);
    send_status();  // pending changed
}

static void check_hold(void) {
    bool held;
    xSemaphoreTake(s_det_lock, portMAX_DELAY);
    held = hold_detector_tick(&s_det, now_ms(), &s_hold);
    xSemaphoreGive(s_det_lock);
    if (held) make_record();
}

static void handle_command(const proto_cmd_t *c) {
    switch (c->kind) {
        case CMD_LIVE:
            s_live = c->live_on;
            if (c->live_on) s_live_ms = now_ms();
            ESP_LOGI(TAG, "live %s", c->live_on ? "on" : "off");
            break;
        case CMD_CFG:
            if (c->cfg_rec >= 0) settings_set_rec(c->cfg_rec == 1);
            if (c->cfg_vbus >= 0 && (c->cfg_vbus == 1) != settings_vbus()) {
                settings_set_vbus(c->cfg_vbus == 1);
                power_set_vbus(c->cfg_vbus == 1);
            }
            ESP_LOGI(TAG, "cfg rec=%d vbus=%d", settings_rec(), settings_vbus());
            break;
        case CMD_TIME:
            s_time_offset_ms = (int64_t)c->time_ms - (int64_t)now_ms();
            s_has_time = true;
            outbox_on_time(&s_outbox);
            ESP_LOGI(TAG, "time %" PRIu64, c->time_ms);
            break;
        case CMD_ACK:
            outbox_on_ack(&s_outbox, &s_store, c->rid);
            if (strcmp(s_waiting_rid, c->rid) == 0) s_waiting_rid[0] = '\0';
            s_ack_blink_ms = now_ms();
            ESP_LOGI(TAG, "ack %s, %u waiting", c->rid, (unsigned)s_store.count);
            send_status();  // pending dropped
            break;
        case CMD_FB:
            strcpy(s_fb_code, c->fb_code);
            strcpy(s_fb_text, c->fb_text);
            s_fb_ms = now_ms();
            if (strcmp(s_waiting_rid, c->rid) == 0) s_waiting_rid[0] = '\0';
            ESP_LOGI(TAG, "fb %s %s", c->fb_code, c->fb_text);
            break;
        case CMD_STATE:
            strcpy(s_state, c->state);
            strcpy(s_mix, c->mix);
            s_state_ms = now_ms();
            break;
        default:
            ESP_LOGI(TAG, "command %d ignored", c->kind);
            break;
    }
}

// MENU (active low) shows the info screen for 5 s.
static void poll_menu(void) {
    static bool was_down;
    bool down = gpio_get_level(PIN_BTN_MENU) == 0;
    if (down && !was_down) {
        ui_show_info(s_bridge_id, FW_VERSION, power_battery_mv(), power_host_vbus_mv(),
                     power_source_name(power_vbus_source()), settings_epoch());
    }
    was_down = down;
}

static void main_task(void *arg) {
    (void)arg;
    uint64_t next_status = now_ms() + STATUS_EVERY_MS;
    uint64_t next_hold_tick = now_ms() + HOLD_TICK_MS;
    for (;;) {
        event_t ev;
        if (xQueueReceive(s_events, &ev, pdMS_TO_TICKS(100)) == pdTRUE) {
            switch (ev.kind) {
                case EV_SUBSCRIBED:
                    s_phone_ever = true;
                    send_hello();
                    next_status = now_ms() + STATUS_EVERY_MS;
                    break;
                case EV_DISCONNECTED:
                    outbox_on_disconnect(&s_outbox);
                    break;
                case EV_ATTACH:
                case EV_DETACH:
                    send_status();
                    break;
                case EV_COMMAND:
                    handle_command(&ev.cmd);
                    break;
            }
        }
        uint64_t now = now_ms();
        if (now >= next_hold_tick) {
            next_hold_tick = now + HOLD_TICK_MS;
            check_hold();
        }
        pump_outbox();
        if (now >= next_status) {
            next_status = now + STATUS_EVERY_MS;
            send_status();
        }
        poll_menu();
        refresh_state();
    }
}

static void led_init(int pin, int level) {
    gpio_reset_pin(pin);
    gpio_set_direction(pin, GPIO_MODE_OUTPUT);
    gpio_set_level(pin, level);
}

void app_main(void) {
    // Power first: the host port's 5 V must be off before anything else runs.
    power_init();
    ui_start();
    led_init(PIN_LED_GREEN, 0);
    led_init(PIN_LED_YELLOW, 0);
    gpio_reset_pin(PIN_BTN_MENU);
    gpio_set_direction(PIN_BTN_MENU, GPIO_MODE_INPUT);
    gpio_pullup_en(PIN_BTN_MENU);
    settings_init();

    esp_vfs_littlefs_conf_t fs = {
        .base_path = "/rec", .partition_label = "storage", .format_if_mount_failed = true};
    ESP_ERROR_CHECK(esp_vfs_littlefs_register(&fs));

    uint8_t mac[6];
    esp_efuse_mac_get_default(mac);
    snprintf(s_bridge_id, sizeof s_bridge_id, "%02x%02x%02x%02x%02x%02x", mac[0], mac[1], mac[2],
             mac[3], mac[4], mac[5]);
    char name[32];
    snprintf(name, sizeof name, "Anchorline Bridge %02X%02X", mac[4], mac[5]);

    ESP_LOGI(TAG, "solo_bridge fw=%s bridge=%s boot=%" PRIu32 " epoch=%s batt=%" PRIu32 "mV",
             FW_VERSION, s_bridge_id, settings_boot(), settings_epoch(), power_battery_mv());
    power_set_vbus(settings_vbus());

    if (!record_store_open(&s_store, "/rec", settings_epoch(), settings_counter()))
        ESP_LOGE(TAG, "record store: can't open /rec");
    ESP_LOGI(TAG, "record store: %u waiting, next counter %" PRIu32, (unsigned)s_store.count,
             s_store.next_counter);

    s_det_lock = xSemaphoreCreateMutex();
    hold_detector_reset(&s_det);
    outbox_init(&s_outbox);
    refresh_state();  // creates the snapshot's lock before any other task reads it

    s_events = xQueueCreate(16, sizeof(event_t));
    xTaskCreate(main_task, "main", 8192, NULL, 4, NULL);

    const usb_solo_events_t usb = {.on_attach = on_attach, .on_detach = on_detach, .on_line = on_line};
    usb_solo_start(&usb);

    const ble_link_events_t ble = {
        .on_subscribed = on_subscribed, .on_disconnected = on_disconnected, .on_command = on_command};
    ble_link_start(&ble, name);
}
