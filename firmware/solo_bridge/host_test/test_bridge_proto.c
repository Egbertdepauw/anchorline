// SPDX-License-Identifier: Apache-2.0
#include "bridge_proto.h"
#include "check.h"

static const char *kCapture =
    "He   0.4 %  O2  19.8 %  Ti  21.7 ~C  1029.5 hPa   2026/11/03 15:19:15";

static void check_golden(const char *produced[], size_t n) {
    FILE *out = fopen("golden/wire_v1.txt.out", "w");
    CHECK(out != NULL);
    if (out == NULL) return;
    for (size_t i = 0; i < n; i++) fprintf(out, "%s\n", produced[i]);
    fclose(out);

    FILE *gold = fopen("golden/wire_v1.txt", "r");
    CHECK(gold != NULL);
    if (gold == NULL) return;
    char line[512];
    size_t i = 0;
    while (fgets(line, sizeof line, gold) != NULL) {
        line[strcspn(line, "\n")] = '\0';
        CHECK(i < n);
        if (i < n) CHECK_STR_EQ(produced[i], line);
        i++;
    }
    fclose(gold);
    CHECK(i == n);
}

TEST_SUITE(test_bridge_proto) {
    char hello[256], st[128], l[256];
    proto_hello_t h = {.fw = "0.1.0", .bridge = "a0b1c2d3e4f5", .epoch = "1a2b3c4d", .boot = 7,
                       .up_ms = 123456, .solo = true, .rec = false, .vbus = false,
                       .batt_mv = 3987, .pending = 0};
    CHECK(proto_fmt_hello(hello, sizeof hello, &h) > 0);
    CHECK_STR_EQ(hello,
                 "HELLO proto=1 fw=0.1.0 bridge=a0b1c2d3e4f5 epoch=1a2b3c4d boot=7 up=123456 "
                 "solo=1 rec=off vbus=off batt=3987 pending=0");

    proto_status_t s = {.solo = true, .data = false, .pending = 0, .batt_mv = 3987, .up_ms = 5000};
    CHECK(proto_fmt_status(st, sizeof st, &s) > 0);
    CHECK_STR_EQ(st, "ST solo=1 data=0 pending=0 batt=3987 up=5000");

    CHECK(proto_fmt_live_line(l, sizeof l, kCapture) == strlen(kCapture) + 2);
    CHECK(strncmp(l, "L ", 2) == 0);
    CHECK_STR_EQ(l + 2, kCapture);

    // Too small a buffer gives 0, never a cut message.
    char tiny[8];
    CHECK(proto_fmt_live_line(tiny, sizeof tiny, kCapture) == 0);
    CHECK(proto_fmt_hello(tiny, sizeof tiny, &h) == 0);

    char rec[128], rec2[128], w[256], w0[256], hl[256], end[64];
    CHECK(proto_fmt_rec(rec, sizeof rec, "1a2b3c4d-7", 3, 99000, 0, true) > 0);
    CHECK_STR_EQ(rec, "REC 1a2b3c4d-7 boot=3 up=99000 wall=0 live=1");
    CHECK(proto_fmt_rec(rec2, sizeof rec2, "1a2b3c4d-8", 3, 99000, 1762182000000ULL, false) > 0);
    CHECK_STR_EQ(rec2, "REC 1a2b3c4d-8 boot=3 up=99000 wall=1762182000000 live=0");
    CHECK(proto_fmt_w(w, sizeof w, -1200, kCapture) > 0);
    CHECK(strncmp(w, "W -1200 ", 8) == 0);
    CHECK_STR_EQ(w + 8, kCapture);
    CHECK(proto_fmt_w(w0, sizeof w0, 0, kCapture) > 0);
    CHECK(strncmp(w0, "W 0 ", 4) == 0);
    CHECK(proto_fmt_h(hl, sizeof hl, kCapture) == strlen(kCapture) + 2);
    CHECK(strncmp(hl, "H ", 2) == 0);
    CHECK_STR_EQ(hl + 2, kCapture);
    CHECK(proto_fmt_end(end, sizeof end, "1a2b3c4d-7") > 0);
    CHECK_STR_EQ(end, "END 1a2b3c4d-7");
    CHECK(proto_fmt_h(tiny, sizeof tiny, kCapture) == 0);  // too small gives 0

    const char *produced[] = {hello, st, l, rec, rec2, w, w0, hl, end};
    check_golden(produced, 9);

    proto_cmd_t c;
    proto_parse_cmd("TIME 1762700000000", &c);
    CHECK(c.kind == CMD_TIME && c.time_ms == 1762700000000ULL);
    proto_parse_cmd("LIVE ON\r", &c);
    CHECK(c.kind == CMD_LIVE && c.live_on);
    proto_parse_cmd("LIVE OFF", &c);
    CHECK(c.kind == CMD_LIVE && !c.live_on);
    proto_parse_cmd("CFG rec=on vbus=off", &c);
    CHECK(c.kind == CMD_CFG && c.cfg_rec == 1 && c.cfg_vbus == 0);
    proto_parse_cmd("CFG vbus=on", &c);
    CHECK(c.kind == CMD_CFG && c.cfg_rec == -1 && c.cfg_vbus == 1);
    proto_parse_cmd("ACK 1a2b3c4d-7", &c);
    CHECK(c.kind == CMD_ACK);
    CHECK_STR_EQ(c.rid, "1a2b3c4d-7");
    proto_parse_cmd("FB 1a2b3c4d-7 saved SIGN OFF LATER", &c);
    CHECK(c.kind == CMD_FB);
    CHECK_STR_EQ(c.rid, "1a2b3c4d-7");
    CHECK_STR_EQ(c.fb_code, "saved");
    CHECK_STR_EQ(c.fb_text, "SIGN OFF LATER");
    proto_parse_cmd("STATE stable TX21/35", &c);
    CHECK(c.kind == CMD_STATE);
    CHECK_STR_EQ(c.state, "stable");
    CHECK_STR_EQ(c.mix, "TX21/35");
    proto_parse_cmd("STATE air", &c);
    CHECK(c.kind == CMD_STATE);
    CHECK_STR_EQ(c.state, "air");
    CHECK_STR_EQ(c.mix, "");

    const char *bad[] = {"HELLO", "LIVE", "LIVE maybe", "CFG rec=maybe", "CFG", "ACK", "",
                         "TIME", "TIME 12x", "FB 1a-7", "STATE", "time 1"};
    for (size_t i = 0; i < sizeof bad / sizeof bad[0]; i++) {
        proto_parse_cmd(bad[i], &c);
        CHECK(c.kind == CMD_UNKNOWN);
    }

    // Chunks never exceed mtu-3 and rejoin to the line.
    const uint16_t mtus[] = {23, 185, 247};
    for (size_t m = 0; m < 3; m++) {
        size_t total = 0, i = 0, sz;
        while ((sz = proto_chunk_len(140, mtus[m], i++)) > 0) {
            CHECK(sz <= (size_t)mtus[m] - 3);
            total += sz;
        }
        CHECK(total == 140);
    }
    CHECK(proto_chunk_len(0, 23, 0) == 0);
}
