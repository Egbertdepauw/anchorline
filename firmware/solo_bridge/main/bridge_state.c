// SPDX-License-Identifier: Apache-2.0
#include "bridge_state.h"

#include <string.h>

#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"

static bridge_state_t s_state;
static SemaphoreHandle_t s_lock;

static SemaphoreHandle_t lock(void) {
    // First use happens from app_main, before any other task reads it.
    if (s_lock == NULL) s_lock = xSemaphoreCreateMutex();
    return s_lock;
}

void bridge_state_get(bridge_state_t *out) {
    SemaphoreHandle_t l = lock();
    xSemaphoreTake(l, portMAX_DELAY);
    *out = s_state;
    xSemaphoreGive(l);
}

void bridge_state_publish(const bridge_state_t *in) {
    SemaphoreHandle_t l = lock();
    xSemaphoreTake(l, portMAX_DELAY);
    s_state = *in;
    xSemaphoreGive(l);
}
