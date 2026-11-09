// SPDX-License-Identifier: Apache-2.0
//
// SOLO bridge: reads a Divesoft SOLO gas analyzer over USB host and passes its
// lines to the Anchorline app over Bluetooth LE (Nordic UART).

#include "board.h"
#include "driver/gpio.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "power.h"
#include "settings.h"

#define FW_VERSION "0.1.0"

static const char *TAG = "solo_bridge";

static void led_init(int pin) {
    gpio_reset_pin(pin);
    gpio_set_direction(pin, GPIO_MODE_OUTPUT);
    gpio_set_level(pin, 0);
}

void app_main(void) {
    // Power first: the host port's 5 V must be off before anything else runs.
    power_init();
    led_init(PIN_LED_GREEN);
    led_init(PIN_LED_YELLOW);
    settings_init();
    ESP_LOGI(TAG, "solo_bridge fw=%s boot=%lu epoch=%s batt=%lumV", FW_VERSION,
             (unsigned long)settings_boot(), settings_epoch(), (unsigned long)power_battery_mv());
    power_set_vbus(settings_vbus());

    gpio_set_level(PIN_LED_GREEN, 1);
    vTaskDelay(pdMS_TO_TICKS(300));
    gpio_set_level(PIN_LED_GREEN, 0);
}
