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
#include "driver/gpio.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "line_splitter.h"
#include "power.h"
#include "settings.h"
#include "solo_line.h"
#include "usb_solo.h"

#define FW_VERSION "0.1.0"
#define STATUS_EVERY_MS 5000
#define DATA_FRESH_MS 1000  // ST data=1 when a data line came this recently

static const char *TAG = "solo_bridge";

typedef enum { EV_SUBSCRIBED, EV_DISCONNECTED, EV_ATTACH, EV_DETACH, EV_COMMAND } ev_kind_t;
typedef struct {
    ev_kind_t kind;
    proto_cmd_t cmd;
} event_t;

static QueueHandle_t s_events;
static char s_bridge_id[13];  // factory MAC, 12 lowercase hex digits
static volatile bool s_live;  // the phone asked for live lines
static volatile uint64_t s_last_data_ms;
static volatile uint32_t s_lines;

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
static void on_attach(void) { post(EV_ATTACH, NULL); }
static void on_detach(void) { post(EV_DETACH, NULL); }

static void on_line(uint64_t up_ms, const char *line) {
    if (solo_is_data_line(line)) s_last_data_ms = up_ms;
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
                       .pending = 0};
    char msg[256];
    if (proto_fmt_hello(msg, sizeof msg, &h) > 0) ble_link_send(msg);
}

static void send_status(void) {
    proto_status_t s = {.solo = usb_solo_attached(),
                        .data = data_flowing(),
                        .pending = 0,
                        .batt_mv = power_battery_mv(),
                        .up_ms = now_ms()};
    char msg[128];
    if (proto_fmt_status(msg, sizeof msg, &s) > 0) ble_link_send(msg);
}

static void handle_command(const proto_cmd_t *c) {
    switch (c->kind) {
        case CMD_LIVE:
            s_live = c->live_on;
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
            ESP_LOGI(TAG, "time %" PRIu64, c->time_ms);
            break;
        default:
            ESP_LOGI(TAG, "command %d ignored in v0", c->kind);
            break;
    }
}

static void main_task(void *arg) {
    (void)arg;
    uint64_t next_status = now_ms() + STATUS_EVERY_MS;
    for (;;) {
        event_t ev;
        if (xQueueReceive(s_events, &ev, pdMS_TO_TICKS(100)) == pdTRUE) {
            switch (ev.kind) {
                case EV_SUBSCRIBED:
                    gpio_set_level(PIN_LED_GREEN, 1);
                    send_hello();
                    next_status = now_ms() + STATUS_EVERY_MS;
                    break;
                case EV_DISCONNECTED:
                    gpio_set_level(PIN_LED_GREEN, 0);
                    break;
                case EV_ATTACH:
                case EV_DETACH:
                    gpio_set_level(PIN_LED_YELLOW, ev.kind == EV_DETACH);
                    send_status();
                    break;
                case EV_COMMAND:
                    handle_command(&ev.cmd);
                    break;
            }
        }
        if (now_ms() >= next_status) {
            next_status = now_ms() + STATUS_EVERY_MS;
            send_status();
        }
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
    led_init(PIN_LED_GREEN, 0);
    led_init(PIN_LED_YELLOW, 1);  // on while no SOLO is attached
    settings_init();

    uint8_t mac[6];
    esp_efuse_mac_get_default(mac);
    snprintf(s_bridge_id, sizeof s_bridge_id, "%02x%02x%02x%02x%02x%02x", mac[0], mac[1], mac[2],
             mac[3], mac[4], mac[5]);
    char name[32];
    snprintf(name, sizeof name, "Anchorline Bridge %02X%02X", mac[4], mac[5]);

    ESP_LOGI(TAG, "solo_bridge fw=%s bridge=%s boot=%" PRIu32 " epoch=%s batt=%" PRIu32 "mV",
             FW_VERSION, s_bridge_id, settings_boot(), settings_epoch(), power_battery_mv());
    power_set_vbus(settings_vbus());

    s_events = xQueueCreate(16, sizeof(event_t));
    xTaskCreate(main_task, "main", 6144, NULL, 4, NULL);

    const usb_solo_events_t usb = {.on_attach = on_attach, .on_detach = on_detach, .on_line = on_line};
    usb_solo_start(&usb);

    const ble_link_events_t ble = {
        .on_subscribed = on_subscribed, .on_disconnected = on_disconnected, .on_command = on_command};
    ble_link_start(&ble, name);
}
