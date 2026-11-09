// SPDX-License-Identifier: Apache-2.0
//
// The Bluetooth LE side: one phone at a time, Nordic UART Service.
#pragma once
#include <stdbool.h>

#include "bridge_proto.h"

typedef struct {
    void (*on_subscribed)(void);   // the phone enabled notifications on TX
    void (*on_disconnected)(void);
    void (*on_command)(const proto_cmd_t *cmd);  // one per line the phone wrote
} ble_link_events_t;

// Starts NimBLE and advertises as `name`. The callbacks run on the NimBLE
// host task: keep them short.
void ble_link_start(const ble_link_events_t *ev, const char *name);
bool ble_link_subscribed(void);

// Sends one message, appending '\n', split to the connection's MTU. Safe from
// any task; messages never interleave. False when no phone is subscribed or
// the stack ran out of buffers.
bool ble_link_send(const char *msg);
