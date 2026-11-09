// SPDX-License-Identifier: Apache-2.0
#include "settings.h"

#include <stdio.h>

#include "esp_log.h"
#include "esp_random.h"
#include "nvs.h"
#include "nvs_flash.h"

static const char *TAG = "settings";
static nvs_handle_t s_nvs;
static uint32_t s_boot;
static char s_epoch[9];

static uint8_t get_u8(const char *key, uint8_t fallback) {
    uint8_t v;
    return nvs_get_u8(s_nvs, key, &v) == ESP_OK ? v : fallback;
}

static void set_u8(const char *key, uint8_t v) {
    ESP_ERROR_CHECK(nvs_set_u8(s_nvs, key, v));
    ESP_ERROR_CHECK(nvs_commit(s_nvs));
}

void settings_init(void) {
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_LOGW(TAG, "NVS full or from a newer layout; erasing");
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    ESP_ERROR_CHECK(err);
    ESP_ERROR_CHECK(nvs_open("bridge", NVS_READWRITE, &s_nvs));

    uint32_t boot = 0;
    nvs_get_u32(s_nvs, "boot", &boot);
    s_boot = boot + 1;
    ESP_ERROR_CHECK(nvs_set_u32(s_nvs, "boot", s_boot));

    size_t len = sizeof s_epoch;
    if (nvs_get_str(s_nvs, "epoch", s_epoch, &len) != ESP_OK) {
        snprintf(s_epoch, sizeof s_epoch, "%08lx", (unsigned long)esp_random());
        ESP_ERROR_CHECK(nvs_set_str(s_nvs, "epoch", s_epoch));
    }
    ESP_ERROR_CHECK(nvs_commit(s_nvs));
}

bool settings_vbus(void) { return get_u8("vbus", 0) != 0; }
void settings_set_vbus(bool on) { set_u8("vbus", on ? 1 : 0); }
bool settings_rec(void) { return get_u8("rec", 0) != 0; }
void settings_set_rec(bool on) { set_u8("rec", on ? 1 : 0); }
uint32_t settings_boot(void) { return s_boot; }
const char *settings_epoch(void) { return s_epoch; }
