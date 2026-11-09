// SPDX-License-Identifier: Apache-2.0
#include "ble_link.h"

#include <string.h>

#include "esp_log.h"
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "host/ble_hs.h"
#include "host/util/util.h"
#include "line_splitter.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

static const char *TAG = "ble_link";

// 6E400001-B5A3-F393-E0A9-E50E24DCCA9E and its RX (…02) and TX (…03),
// little-endian as NimBLE wants them.
#define NUS_UUID(b12) \
    BLE_UUID128_INIT(0x9e, 0xca, 0xdc, 0x24, 0x0e, 0xe5, 0xa9, 0xe0, 0x93, 0xf3, 0xa3, 0xb5, b12, 0x00, 0x40, 0x6e)
static const ble_uuid128_t kNusService = NUS_UUID(0x01);
static const ble_uuid128_t kNusRx = NUS_UUID(0x02);
static const ble_uuid128_t kNusTx = NUS_UUID(0x03);

static ble_link_events_t s_ev;
static char s_name[32];
static uint8_t s_addr_type;
static uint16_t s_conn = BLE_HS_CONN_HANDLE_NONE;
static uint16_t s_tx_handle;
static volatile bool s_subscribed;
static volatile uint16_t s_mtu = 23;
static line_splitter_t s_rx;
static SemaphoreHandle_t s_send_lock;

static void advertise(void);

static void on_rx_line(const char *line, void *ctx) {
    (void)ctx;
    proto_cmd_t cmd;
    proto_parse_cmd(line, &cmd);
    if (cmd.kind == CMD_UNKNOWN) {
        ESP_LOGW(TAG, "unknown from phone: %s", line);
        return;
    }
    s_ev.on_command(&cmd);
}

static int rx_access(uint16_t conn, uint16_t attr, struct ble_gatt_access_ctxt *ctxt, void *arg) {
    (void)conn;
    (void)attr;
    (void)arg;
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) return BLE_ATT_ERR_UNLIKELY;
    for (const struct os_mbuf *om = ctxt->om; om != NULL; om = SLIST_NEXT(om, om_next)) {
        line_splitter_feed(&s_rx, om->om_data, om->om_len, on_rx_line, NULL);
    }
    return 0;
}

static int tx_access(uint16_t conn, uint16_t attr, struct ble_gatt_access_ctxt *ctxt, void *arg) {
    (void)conn;
    (void)attr;
    (void)ctxt;
    (void)arg;
    return BLE_ATT_ERR_READ_NOT_PERMITTED;
}

static const struct ble_gatt_svc_def kServices[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &kNusService.u,
        .characteristics =
            (struct ble_gatt_chr_def[]){
                {.uuid = &kNusRx.u,
                 .access_cb = rx_access,
                 .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP},
                {.uuid = &kNusTx.u,
                 .access_cb = tx_access,
                 .val_handle = &s_tx_handle,
                 .flags = BLE_GATT_CHR_F_NOTIFY},
                {0},
            },
    },
    {0},
};

static int gap_event(struct ble_gap_event *event, void *arg) {
    (void)arg;
    switch (event->type) {
        case BLE_GAP_EVENT_CONNECT:
            if (event->connect.status == 0) {
                s_conn = event->connect.conn_handle;
                s_mtu = 23;
                line_splitter_reset(&s_rx);
                ESP_LOGI(TAG, "phone connected");
            } else {
                advertise();
            }
            break;
        case BLE_GAP_EVENT_DISCONNECT:
            ESP_LOGI(TAG, "phone disconnected (reason %d)", event->disconnect.reason);
            s_conn = BLE_HS_CONN_HANDLE_NONE;
            s_subscribed = false;
            s_ev.on_disconnected();
            advertise();
            break;
        case BLE_GAP_EVENT_SUBSCRIBE:
            if (event->subscribe.attr_handle == s_tx_handle) {
                bool was = s_subscribed;
                s_subscribed = event->subscribe.cur_notify;
                if (s_subscribed && !was) s_ev.on_subscribed();
            }
            break;
        case BLE_GAP_EVENT_MTU:
            s_mtu = event->mtu.value;
            ESP_LOGI(TAG, "mtu %d", s_mtu);
            break;
        case BLE_GAP_EVENT_ADV_COMPLETE:
            advertise();
            break;
        default:
            break;
    }
    return 0;
}

static void advertise(void) {
    struct ble_hs_adv_fields adv = {0};
    adv.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    adv.uuids128 = &kNusService;
    adv.num_uuids128 = 1;
    adv.uuids128_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&adv);
    if (rc != 0) ESP_LOGE(TAG, "adv fields: %d", rc);

    struct ble_hs_adv_fields rsp = {0};
    rsp.name = (const uint8_t *)s_name;
    rsp.name_len = strlen(s_name);
    rsp.name_is_complete = 1;
    rc = ble_gap_adv_rsp_set_fields(&rsp);
    if (rc != 0) ESP_LOGE(TAG, "scan response: %d", rc);

    struct ble_gap_adv_params params = {
        .conn_mode = BLE_GAP_CONN_MODE_UND,
        .disc_mode = BLE_GAP_DISC_MODE_GEN,
    };
    rc = ble_gap_adv_start(s_addr_type, NULL, BLE_HS_FOREVER, &params, gap_event, NULL);
    if (rc != 0 && rc != BLE_HS_EALREADY) ESP_LOGE(TAG, "adv start: %d", rc);
}

static void on_sync(void) {
    ble_hs_util_ensure_addr(0);
    ble_hs_id_infer_auto(0, &s_addr_type);
    advertise();
    ESP_LOGI(TAG, "advertising as %s", s_name);
}

static void host_task(void *arg) {
    (void)arg;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

void ble_link_start(const ble_link_events_t *ev, const char *name) {
    s_ev = *ev;
    strncpy(s_name, name, sizeof s_name - 1);
    s_send_lock = xSemaphoreCreateMutex();
    line_splitter_reset(&s_rx);

    ESP_ERROR_CHECK(nimble_port_init());
    ble_hs_cfg.sync_cb = on_sync;
    ble_svc_gap_init();
    ble_svc_gatt_init();
    ESP_ERROR_CHECK(ble_gatts_count_cfg(kServices));
    ESP_ERROR_CHECK(ble_gatts_add_svcs(kServices));
    ble_svc_gap_device_name_set(s_name);
    nimble_port_freertos_init(host_task);
}

bool ble_link_subscribed(void) { return s_subscribed; }

bool ble_link_send(const char *msg) {
    if (!s_subscribed) return false;
    char buf[300];
    size_t len = strlen(msg);
    if (len + 1 >= sizeof buf) return false;
    memcpy(buf, msg, len);
    buf[len++] = '\n';

    bool ok = true;
    xSemaphoreTake(s_send_lock, portMAX_DELAY);
    size_t off = 0, sz;
    for (size_t i = 0; ok && (sz = proto_chunk_len(len, s_mtu, i)) > 0; i++) {
        int rc = BLE_HS_ENOMEM;
        for (int attempt = 0; attempt < 20 && s_subscribed; attempt++) {
            struct os_mbuf *om = ble_hs_mbuf_from_flat(buf + off, sz);
            if (om == NULL) {
                vTaskDelay(pdMS_TO_TICKS(5));
                continue;
            }
            rc = ble_gatts_notify_custom(s_conn, s_tx_handle, om);
            if (rc == 0) break;
            vTaskDelay(pdMS_TO_TICKS(5));
        }
        ok = rc == 0;
        off += sz;
    }
    xSemaphoreGive(s_send_lock);
    return ok;
}
