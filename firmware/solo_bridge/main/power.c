// SPDX-License-Identifier: Apache-2.0
#include "power.h"

#include "board.h"
#include "driver/gpio.h"
#include "esp_adc/adc_cali.h"
#include "esp_adc/adc_cali_scheme.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "power";

static adc_oneshot_unit_handle_t s_adc;
static adc_cali_handle_t s_cali[2];
static vbus_src_t s_src = VBUS_SRC_OFF;

static void output(int pin, int level) {
    gpio_reset_pin(pin);
    gpio_set_direction(pin, GPIO_MODE_OUTPUT);
    gpio_set_level(pin, level);
}

static void adc_channel(adc_channel_t ch) {
    adc_oneshot_chan_cfg_t cfg = {.atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT};
    ESP_ERROR_CHECK(adc_oneshot_config_channel(s_adc, ch, &cfg));
    adc_cali_curve_fitting_config_t cali = {
        .unit_id = ADC_UNIT_1, .chan = ch, .atten = ADC_ATTEN_DB_12, .bitwidth = ADC_BITWIDTH_DEFAULT};
    if (adc_cali_create_scheme_curve_fitting(&cali, &s_cali[ch]) != ESP_OK) {
        ESP_LOGW(TAG, "no ADC calibration for channel %d", ch);
        s_cali[ch] = NULL;
    }
}

void power_init(void) {
    // Both 5 V enables low before anything else: the default is off.
    output(PIN_BOOST_EN, 0);
    output(PIN_DEV_VBUS_EN, 0);
    output(PIN_LIMIT_EN, 0);
    output(PIN_USB_SEL, 1);
    gpio_reset_pin(PIN_OVER_CURRENT);
    gpio_set_direction(PIN_OVER_CURRENT, GPIO_MODE_INPUT);
    s_src = VBUS_SRC_OFF;

    adc_oneshot_unit_init_cfg_t unit = {.unit_id = ADC_UNIT_1};
    ESP_ERROR_CHECK(adc_oneshot_new_unit(&unit, &s_adc));
    adc_channel(ADC_CH_HOST_VBUS);
    adc_channel(ADC_CH_BATTERY);
}

static uint32_t read_mv(adc_channel_t ch, uint32_t div_x10) {
    int sum = 0, ok = 0;
    for (int i = 0; i < 8; i++) {
        int raw, mv;
        if (adc_oneshot_read(s_adc, ch, &raw) != ESP_OK) continue;
        if (s_cali[ch] == NULL || adc_cali_raw_to_voltage(s_cali[ch], raw, &mv) != ESP_OK) continue;
        sum += mv;
        ok++;
    }
    return ok == 0 ? 0 : power_adc_to_mv((uint32_t)(sum / ok), div_x10);
}

uint32_t power_battery_mv(void) { return read_mv(ADC_CH_BATTERY, BATTERY_DIV_X10); }
uint32_t power_host_vbus_mv(void) { return read_mv(ADC_CH_HOST_VBUS, HOST_VBUS_DIV_X10); }

void power_set_vbus(bool wanted) {
    vbus_src_t to = power_pick_source(wanted, power_battery_mv());
    pin_write_t w[6];
    size_t n = power_sequence(s_src, to, w);
    for (size_t i = 0; i < n; i++) gpio_set_level(w[i].pin, w[i].level);
    s_src = to;
    vTaskDelay(pdMS_TO_TICKS(200));
    ESP_LOGI(TAG, "vbus src=%s host_vbus=%lumV over_current=%d", power_source_name(to),
             (unsigned long)power_host_vbus_mv(), gpio_get_level(PIN_OVER_CURRENT));
}

vbus_src_t power_vbus_source(void) { return s_src; }
