// SPDX-License-Identifier: Apache-2.0
//
// The SOLO on the USB-A host port: attach, detach and its lines.
#pragma once
#include <stdbool.h>
#include <stdint.h>

#define SOLO_VID 0xA600
#define SOLO_PID 0xE212

typedef struct {
    void (*on_attach)(void);
    void (*on_detach)(void);
    // Called from the USB driver's task, one call per line, in order.
    // up_ms is the bridge's uptime when the line was complete.
    void (*on_line)(uint64_t up_ms, const char *line);
} usb_solo_events_t;

// Starts the USB host and waits for a SOLO in the background. Call once,
// after power_init() has routed the native USB to the host port.
void usb_solo_start(const usb_solo_events_t *ev);
bool usb_solo_attached(void);
