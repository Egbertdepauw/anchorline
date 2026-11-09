// SPDX-License-Identifier: Apache-2.0
#include "usb_solo.h"

#include "esp_log.h"
#include "esp_timer.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "line_splitter.h"
#include "usb/cdc_acm_host.h"
#include "usb/usb_host.h"

static const char *TAG = "usb_solo";

static usb_solo_events_t s_ev;
static line_splitter_t s_splitter;
static SemaphoreHandle_t s_gone;
static volatile bool s_attached;

static void host_lib_task(void *arg) {
    (void)arg;
    for (;;) {
        uint32_t flags;
        usb_host_lib_handle_events(portMAX_DELAY, &flags);
        if (flags & USB_HOST_LIB_EVENT_FLAGS_NO_CLIENTS) usb_host_device_free_all();
    }
}

static void emit_line(const char *line, void *ctx) {
    (void)ctx;
    s_ev.on_line((uint64_t)(esp_timer_get_time() / 1000), line);
}

static bool on_data(const uint8_t *data, size_t len, void *arg) {
    (void)arg;
    line_splitter_feed(&s_splitter, data, len, emit_line, NULL);
    return true;
}

static void on_event(const cdc_acm_host_dev_event_data_t *event, void *ctx) {
    (void)ctx;
    switch (event->type) {
        case CDC_ACM_HOST_DEVICE_DISCONNECTED:
            ESP_LOGI(TAG, "solo detach");
            cdc_acm_host_close(event->data.cdc_hdl);
            xSemaphoreGive(s_gone);
            break;
        case CDC_ACM_HOST_ERROR:
            ESP_LOGW(TAG, "CDC-ACM error %d", event->data.error);
            break;
        default:
            break;
    }
}

static void open_loop_task(void *arg) {
    (void)arg;
    const cdc_acm_host_device_config_t cfg = {
        .connection_timeout_ms = 1000,
        .out_buffer_size = 64,
        .in_buffer_size = 512,
        .event_cb = on_event,
        .data_cb = on_data,
        .user_arg = NULL,
    };
    for (;;) {
        cdc_acm_dev_hdl_t dev = NULL;
        line_splitter_reset(&s_splitter);
        if (cdc_acm_host_open(SOLO_VID, SOLO_PID, 0, &cfg, &dev) != ESP_OK) continue;

        cdc_acm_line_coding_t coding = {
            .dwDTERate = 115200, .bCharFormat = 0, .bParityType = 0, .bDataBits = 8};
        if (cdc_acm_host_line_coding_set(dev, &coding) != ESP_OK)
            ESP_LOGW(TAG, "line coding failed");
        if (cdc_acm_host_set_control_line_state(dev, true, false) != ESP_OK)
            ESP_LOGW(TAG, "DTR failed");

        ESP_LOGI(TAG, "solo attach");
        s_attached = true;
        s_ev.on_attach();
        xSemaphoreTake(s_gone, portMAX_DELAY);
        s_attached = false;
        line_splitter_reset(&s_splitter);
        s_ev.on_detach();
    }
}

void usb_solo_start(const usb_solo_events_t *ev) {
    s_ev = *ev;
    s_gone = xSemaphoreCreateBinary();
    const usb_host_config_t host = {.skip_phy_setup = false, .intr_flags = ESP_INTR_FLAG_LEVEL1};
    ESP_ERROR_CHECK(usb_host_install(&host));
    xTaskCreate(host_lib_task, "usb_host", 4096, NULL, 10, NULL);
    ESP_ERROR_CHECK(cdc_acm_host_install(NULL));
    xTaskCreate(open_loop_task, "usb_solo", 4096, NULL, 5, NULL);
}

bool usb_solo_attached(void) { return s_attached; }
