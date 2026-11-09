// SPDX-License-Identifier: Apache-2.0
//
// Bridge protocol v1 (spec section 3): plain ASCII, one message per
// '\n'-terminated line, over the Nordic UART Service. The app's side is
// lib/analyzer/bridge/bridge_protocol.dart; host_test/golden/wire_v1.txt
// holds lines both sides are tested against.
#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PROTO_VERSION 1

typedef struct {
    const char *fw, *bridge, *epoch;
    uint32_t boot;
    uint64_t up_ms;
    bool solo, rec, vbus;
    uint32_t batt_mv, pending;
} proto_hello_t;

typedef struct {
    bool solo, data;
    uint32_t pending, batt_mv;
    uint64_t up_ms;
} proto_status_t;

// The formatters write one message WITHOUT its '\n' into out (cap bytes,
// NUL included) and return its length, or 0 when it would not fit.
size_t proto_fmt_hello(char *out, size_t cap, const proto_hello_t *h);
size_t proto_fmt_status(char *out, size_t cap, const proto_status_t *s);
size_t proto_fmt_live_line(char *out, size_t cap, const char *solo_line);  // "L <line>"
// A record, as it is stored and sent: REC, one W per window line, H, END.
size_t proto_fmt_rec(char *out, size_t cap, const char *rid, uint32_t boot, uint64_t up_ms,
                     uint64_t wall_ms, bool live);  // "REC <rid> boot= up= wall= live="
size_t proto_fmt_w(char *out, size_t cap, int64_t offset_ms, const char *line);  // "W <off> <line>"
size_t proto_fmt_h(char *out, size_t cap, const char *line);                     // "H <line>"
size_t proto_fmt_end(char *out, size_t cap, const char *rid);                    // "END <rid>"

typedef enum { CMD_UNKNOWN, CMD_TIME, CMD_LIVE, CMD_STATE, CMD_ACK, CMD_FB, CMD_CFG } proto_cmd_kind_t;

typedef struct {
    proto_cmd_kind_t kind;
    uint64_t time_ms;          // CMD_TIME
    bool live_on;              // CMD_LIVE
    char state[16], mix[17];   // CMD_STATE: wire code, optional mix ("" when none)
    char rid[24];              // CMD_ACK, CMD_FB
    char fb_code[10], fb_text[25];  // CMD_FB
    int8_t cfg_rec, cfg_vbus;  // CMD_CFG: -1 not given, 0 off, 1 on
} proto_cmd_t;

// Parses one line from the app. Never fails: anything malformed is
// CMD_UNKNOWN. A trailing '\r' is ignored; types are case-sensitive; unknown
// CFG keys are ignored. Over-long fields are cut to their buffer.
void proto_parse_cmd(const char *line, proto_cmd_t *out);

// A message of len bytes (its '\n' included) goes out in notifications of at
// most mtu - 3 bytes. Returns the size of chunk number i, or 0 past the end.
size_t proto_chunk_len(size_t len, uint16_t mtu, size_t i);
