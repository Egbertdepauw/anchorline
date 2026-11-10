# SOLO Bridge — Firmware and BLE Link (plan 2 of 3) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the ESP32-S3 bridge between the Divesoft SOLO and the app.
- Part A (spec build step 1): the SOLO's live readings reach the analyzer screen over Bluetooth on every platform, iPhone included. The bench answers the 5 V question.
- Part B (spec build step 2): an OK press on the SOLO becomes a record on the bridge. The record is kept in flash until the app has saved it. The bridge screen shows what happened.

**Architecture:**
- **Firmware** in `firmware/solo_bridge/`: an ESP-IDF project, Apache-2.0.
  - Every rule lives in a plain-C module with no ESP-IDF include, built and tested on the Mac by `host_test/Makefile`:
    - line splitting;
    - the wire protocol;
    - the 5 V switching order;
    - the OK hold rule;
    - the record store;
    - the send queue;
    - the screen-state priority.
  - Thin ESP-IDF glue calls them: USB host, NimBLE, GPIO/ADC, NVS, LittleFS, the LCD.
- **App:**
  - A pure-Dart `BridgeLink` interface, with a `flutter_blue_plus` implementation.
  - A `BleBridgeTransport` that is an ordinary `AnalyzerTransport`.
  - Pairing in Settings.
  - In Part B, a `BridgeOkHandler` that turns records into saved analyses through the existing `recordToAnalysis`. It shares one `OkRecordProcessor` with the USB logger.
- **Background running is plan 3.** In this plan, records are handled while the shell-owned `AnalyzerSession` is connected over the bridge: the app is in front, on any tab.

**Tech Stack:**
- Firmware: ESP-IDF v5.5.x (exact patch pinned in Task 1), NimBLE, managed components `espressif/usb_host_cdc_acm` and `espressif/esp32_s3_usb_otg` (BSP, display and buttons only), `joltwallet/littlefs`. Host tests: `cc -std=c11` and `make`.
- App: Flutter / Dart, `flutter_blue_plus` (already a dependency, no new ones), `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-03-background-gas-logging-design.md`. Read:
- §1 (the OK rule);
- §2 (the bridge);
- §3 (protocol v1);
- §4 "New code";
- §5 "Order of operations";
- §10 (failure cases);
- §12 steps 1–2.

Plan 1 (`docs/superpowers/plans/2026-11-03-log-on-ok-app-core.md`, merged in #152) already built `bridge_protocol.dart`, `record_to_analysis.dart`, `hold_detector.dart` and `usb_ok_logger.dart`. This plan uses them and does not change their behaviour.

**Not in this plan (plan 3):**
- the iOS `bluetooth-central` background mode and the Android foreground service;
- sessions that outlive the app being in front, and the 60-minute timeout;
- collecting waiting records on app start;
- Blend-target preselect for bridge records;
- background label rendering;
- store notes.

**Branches and PRs:** two issues, two PRs, each squash-merged with "Refs #113". Label P2, milestone "Gas analyzer (Divesoft SOLO)".
- Part A: issue "SOLO bridge v0: ESP32 USB→BLE firmware and the app's bridge transport", branch `feat/<issue>-solo-bridge-v0`.
- Part B: issue "SOLO bridge v1: OK records from the bridge", branch `feat/<issue>-solo-bridge-v1`, cut from main **after Part A has merged and the bench (Task 7) is done**.

## Hardware facts (Espressif ESP32-S3-USB-OTG user guide and the BSP header `esp32_s3_usb_otg.h`, checked 2026-11-09)

These replace the spec §2 pin table, which came from third-party listings.

| Signal | GPIO | Level |
|---|---|---|
| `USB_SEL` | 18 | high = the USB-A **host** port gets the native USB; low (default) = the DEV plug |
| `BOOST_EN` | 13 | high = 5 V boost from the battery |
| `DEV_VBUS_EN` | 12 | high = the DEV plug's 5 V passes through to the host port |
| `LIMIT_EN` | 17 | high = MIC2005A 500 mA limiter on |
| `OVER_CURRENT` | 21 | input; the guide says high = over-current, the BSP comment says active low. Log it, act on neither in v1 |
| LED green / yellow | 15 / 16 | high = on |
| LCD backlight | 9 | |
| Battery ADC | 2 (ADC1 ch1) | V_bat = 2 × pin |
| Host VBUS ADC | 1 (ADC1 ch0) | V_bus = 3.7 × pin |
| Buttons | OK 0 (also BOOT), UP+ 10, DW− 11, MENU 14 | active low |
| LCD ST7789 240×240 | SPI3: SCLK 6, MOSI 7, CS 5, DC 4, RST 8 | via the BSP |

**Host-port 5 V** (the guide's truth table):

| Mode | `BOOST_EN` | `DEV_VBUS_EN` | Notes |
|---|---|---|---|
| Off | 0 | 0 | |
| From the DEV plug | 0 | 1 | |
| From the battery | 1 | 0 | |
| **Undefined, never** | 1 | 1 | |

- **The DEBUG port** goes through a USB-UART bridge chip to UART0. It is used for flashing and the log console.
  - It cannot power the host port.
  - The guide calls it Micro-USB; Egbert's V1.1 board has a USB-C socket there.
- **Battery:**
  - The board has battery solder pads on the back and an on-board charger: 212.7 mA from the DEV plug, with a red LED while charging. The battery switch must be OFF while charging.
  - The guide names no charger chip and no low-voltage cut-off. Use a **protected** 18650, or keep powering from a power bank.
- **For the bench:** power the bridge from a power bank on the **DEV plug**. Only that path can feed the host port. Watch the log on the DEBUG port from the Mac at the same time.

## Global Constraints

- Everything in git is in English.
- **No new pub dependencies.**
- `lib/analyzer/**` stays pure Dart, **except** the two files named `*_fbp.dart` in this plan, which may import `flutter_blue_plus` and `flutter/foundation.dart`.
- Don't run `dart format` on whole existing files. New files may be formatted.
- **Firmware licence: Apache-2.0**, in `firmware/solo_bridge/LICENSE`. Every firmware source file starts with `// SPDX-License-Identifier: Apache-2.0`.
- **The bridge must not power or charge the SOLO by default.** Host 5 V is **off** at boot and stays off unless the persisted `vbus` setting is on. The two enable pins are never both high, not even for one write.
- **No gas logic in firmware.**
  - The firmware may check that a line *is* a SOLO data line: it has an `O2` token followed by a value token.
  - It never computes mixes, stability, depths or match grades.
  - The screen shows only what the app sends in `STATE` and `FB`.
- **Protocol v1 exactly as in spec §3,** ASCII, one message per `\n`-terminated line. SOLO lines travel byte for byte, with only the line terminator removed.
- **Names on the wire:**
  - the BLE name is `Anchorline Bridge XXXX`, where XXXX is the last 4 hex digits of the factory MAC, uppercase;
  - the bridge id in `HELLO` is the 12-hex-digit factory MAC, lowercase;
  - NUS service `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`, RX (app writes) `6E400002-…`, TX (bridge notifies) `6E400003-…`.
- **Named constants, the same in C and Dart:**
  - hold silence 2000 ms;
  - first-hold flow 5000 ms;
  - next-hold flow 3000 ms;
  - window 30000 ms;
  - store max 50 records;
  - `ST` every 5000 ms;
  - `STATE` heartbeat ≤ 3000 ms;
  - "phone not responding" after 10000 ms.
- **Before every commit:**
  - Firmware: `make -C firmware/solo_bridge/host_test` passes, and `idf.py build` passes in `firmware/solo_bridge`.
  - App: `flutter analyze` is clean, and the touched tests pass.
- **Before each PR:** the whole `flutter test` passes.

## Review Focus

The five inputs most likely to bite that the spec implies but no task's main tests would exercise. Each has a test in the task named.

1. **A SOLO line longer than one BLE notification.** iOS often gives an MTU of 185; a phone that never negotiates gives 23. The bridge must split a line into notifications of at most MTU − 3 bytes, and the app must rebuild it whole, runs of spaces intact. → Task 4 `chunks never exceed mtu-3 and rejoin to the line`; Task 5 `a line split over three notifications arrives whole`.
2. **The C formatter and the Dart parser disagree on a field.** Two codebases implement one protocol. → Task 4 writes `firmware/solo_bridge/host_test/golden/wire_v1.txt` from the C formatter and checks it; Task 5 parses every line of the same file with `parseBridgeMessage` and asserts none is `BridgeUnknown`. Part B extends the file with `REC`/`W`/`H`/`END`.
3. **Switching the 5 V source passes through the undefined state** (both enable pins high), for example going straight from DEV to battery. → Task 2 `no write sequence ever has both enables high`.
4. **Power lost while a record is being written,** then a reboot. The half-written file must not be sent, and its counter must never be reused. → Task 9 `a torn tmp file is deleted at open and the counter moves on`.
5. **The link drops while a record is being sent.** On reconnect the same record is sent again from its `REC` line. The app's assembler drops the partial one, and the app ACKs a record it had already saved. → Task 10 `disconnect mid-send resends the same record from REC`; Task 12 `a record saved before is ACKed again and not saved twice`.

---

## Part A — bridge v0 and the app's bridge transport (spec build step 1)

### Task 1: Toolchain and firmware skeleton

**Files:**
- Create:
  - `firmware/solo_bridge/CMakeLists.txt`
  - `firmware/solo_bridge/main/CMakeLists.txt`
  - `firmware/solo_bridge/main/main.c`
  - `firmware/solo_bridge/main/board.h`
  - `firmware/solo_bridge/main/idf_component.yml`
  - `firmware/solo_bridge/sdkconfig.defaults`
  - `firmware/solo_bridge/partitions.csv`
  - `firmware/solo_bridge/LICENSE`
  - `firmware/solo_bridge/README.md`
  - `firmware/solo_bridge/.gitignore`: `build/`, `sdkconfig`, `sdkconfig.old`, `managed_components/`, `dependencies.lock`
  - `firmware/solo_bridge/host_test/Makefile`
  - `firmware/solo_bridge/host_test/test_main.c`: a minimal runner with `CHECK(cond)` and `CHECK_STR_EQ(a, b)` macros that count failures and exit non-zero on any failure

**Interfaces:**
- Produces:
  - `board.h`: `#define` for every pin in the hardware table, named `PIN_USB_SEL`, `PIN_BOOST_EN`, `PIN_DEV_VBUS_EN`, `PIN_LIMIT_EN`, `PIN_OVER_CURRENT`, `PIN_LED_GREEN`, `PIN_LED_YELLOW`, `PIN_LCD_BL`, `PIN_BTN_OK`, `PIN_BTN_UP`, `PIN_BTN_DOWN`, `PIN_BTN_MENU`, plus `ADC_CH_BATTERY` (1), `ADC_CH_HOST_VBUS` (0), `BATTERY_DIV_X10` (20) and `HOST_VBUS_DIV_X10` (37).
  - `host_test/Makefile`: target `all` builds and runs `test_main`. Later tasks add their `.c` files to `SRCS` and their `test_*.c` files to `TESTS`. Flags: `-std=c11 -Wall -Wextra -Werror -I../main`.

- [ ] **Step 1: Install ESP-IDF on the Mac.** Run it in the background; it downloads about 1 GB.
  - `brew install cmake ninja dfu-util ccache`
  - `git clone -b v5.5.<latest patch> --recursive https://github.com/espressif/esp-idf.git ~/esp/esp-idf`
  - `~/esp/esp-idf/install.sh esp32s3`

  Expected: `install.sh` ends with "All done!".

  **Why v5.5 and not v6.1:** the BSP component (2.0.4) predates v6 and declares only `>=5.2`. If the build in Step 4 fails on the BSP and on nothing else, record that in the README and keep v5.5.

- [ ] **Step 2: Write the skeleton.**
  - `partitions.csv`: `nvs` 24K, `phy_init` 4K, `factory` app 3M, `storage` littlefs 1M.
  - `sdkconfig.defaults`:
    - `CONFIG_BT_ENABLED=y`, `CONFIG_BT_NIMBLE_ENABLED=y`, `CONFIG_BT_NIMBLE_MAX_CONNECTIONS=1`, `CONFIG_BT_NIMBLE_ATT_PREFERRED_MTU=247`;
    - `CONFIG_PARTITION_TABLE_CUSTOM=y` with `partitions.csv`;
    - `CONFIG_ESPTOOLPY_FLASHSIZE_8MB=y`;
    - `CONFIG_ESP_CONSOLE_UART_DEFAULT=y`, because the native USB belongs to the SOLO.
  - `idf_component.yml`: `espressif/usb_host_cdc_acm: "^2.4.1"`. The BSP and LittleFS come in Part B.
  - `main.c`: `app_main` logs `solo_bridge fw=0.1.0`, sets every output pin low, and blinks the green LED once.
  - `LICENSE`: the full Apache-2.0 text.
  - `README.md`:
    - the IDF version and its install commands;
    - build and flash: `idf.py set-target esp32s3`, `idf.py build`, `idf.py -p /dev/cu.<debug port> flash monitor`;
    - the hardware table above;
    - power: a power bank on the DEV plug, the battery solder pads, a protected cell;
    - the licence note from spec §2.

- [ ] **Step 3: Host-test runner smoke test.** `test_main.c` runs one `CHECK(1)`.

  Run: `make -C firmware/solo_bridge/host_test`. Expected: `0 failures`.

- [ ] **Step 4: Build.**

  Run: `. ~/esp/esp-idf/export.sh && cd firmware/solo_bridge && idf.py set-target esp32s3 && idf.py build`. Expected: `Project build complete`.

- [ ] **Step 5: Flash on the board (Egbert).**
  - Plug the DEBUG port into the Mac.
  - Run `idf.py -p /dev/cu.<port> flash monitor`. The port shows up as `cu.usbserial-*` or `cu.wchusbserial-*`.
  - If flashing doesn't start: hold OK/BOOT, press RESET, release OK.

  Expected: `solo_bridge fw=0.1.0` in the monitor and one green blink.

- [ ] **Step 6: Commit.**
  ```bash
  git add firmware/solo_bridge
  git commit -m "feat(bridge): ESP-IDF skeleton for the SOLO bridge firmware"
  ```

### Task 2: Power — host 5 V, battery and VBUS readings, persisted settings

**Files:**
- Create:
  - `firmware/solo_bridge/main/power_logic.c` and `power_logic.h`: pure.
  - `firmware/solo_bridge/main/power.c` and `power.h`: ESP-IDF glue.
  - `firmware/solo_bridge/main/settings.c` and `settings.h`: NVS.
- Test: `firmware/solo_bridge/host_test/test_power_logic.c`

**Interfaces:**
- Produces:
  ```c
  typedef enum { VBUS_SRC_OFF, VBUS_SRC_DEV, VBUS_SRC_BATTERY } vbus_src_t;
  #define BATTERY_PRESENT_MV 3000   /* below this: no battery fitted */
  #define BATTERY_LOW_MV     3500
  #define BATTERY_EMPTY_MV   3300
  /* wanted=false -> OFF; wanted with a battery -> BATTERY; wanted without -> DEV. */
  vbus_src_t power_pick_source(bool wanted, uint32_t batt_mv);
  typedef struct { uint8_t pin; uint8_t level; } pin_write_t;
  /* The ordered GPIO writes that move from `from` to `to`. Returns the count (<= 6). */
  size_t power_sequence(vbus_src_t from, vbus_src_t to, pin_write_t out[6]);
  uint32_t power_adc_to_mv(uint32_t pin_mv, uint32_t div_x10);   /* pin_mv * div_x10 / 10 */

  /* power.h: glue */
  void power_init(void);                 /* USB_SEL high (host), both enables low, LIMIT_EN low */
  void power_set_vbus(bool wanted);      /* picks the source, applies power_sequence, logs it */
  vbus_src_t power_vbus_source(void);
  uint32_t power_battery_mv(void);
  uint32_t power_host_vbus_mv(void);

  /* settings.h */
  void settings_init(void);              /* nvs_flash_init; boot counter += 1 */
  bool settings_vbus(void);              void settings_set_vbus(bool on);    /* default false */
  bool settings_rec(void);               void settings_set_rec(bool on);     /* default false */
  uint32_t settings_boot(void);          /* this boot's number, >= 1 */
  const char *settings_epoch(void);      /* 8 lowercase hex digits, made with esp_random() at first boot */
  ```

- [ ] **Step 1: Write the failing tests** in `test_power_logic.c`:
  - `power_pick_source(false, 4000) == VBUS_SRC_OFF`;
  - `power_pick_source(true, 3900) == VBUS_SRC_BATTERY`;
  - `power_pick_source(true, 120) == VBUS_SRC_DEV`;
  - **`no write sequence ever has both enables high`:** for every pair (from, to) of the three sources, replay `power_sequence` on a two-pin model starting from `from`'s levels, and `CHECK` after every write that `BOOST_EN && DEV_VBUS_EN` is false;
  - `to == VBUS_SRC_OFF` ends with `LIMIT_EN` low; any other `to` ends with `LIMIT_EN` high, and the enable is written last;
  - `power_adc_to_mv(1950, 20) == 3900`; `power_adc_to_mv(1351, 37) == 4998`.

- [ ] **Step 2: Run them; they fail to link.** `make -C firmware/solo_bridge/host_test`.

- [ ] **Step 3: Implement `power_logic.c`.** The sequence is always:
  1. the enable being dropped goes low;
  2. `LIMIT_EN` is set;
  3. the new enable goes high.

  Then implement `power.c`:
  - GPIO outputs;
  - ADC oneshot with curve-fitting calibration on ADC1 channels 0 and 1, averaged over 8 samples;
  - `power_set_vbus` logs `vbus src=<off|dev|battery> host_vbus=<mV>` 200 ms after switching.

  Then implement `settings.c` on NVS namespace `bridge`, keys `vbus`, `rec`, `boot`, `epoch`.

- [ ] **Step 4: Run the host tests** (expect `0 failures`) and `idf.py build`.

- [ ] **Step 5: Wire into `main.c`:**
  1. `settings_init()`;
  2. `power_init()`;
  3. `power_set_vbus(settings_vbus())`;
  4. log `boot=<n> epoch=<hex> batt=<mV>`.

- [ ] **Step 6: Commit** `feat(bridge): switchable host 5 V, battery reading, persisted settings`.

### Task 3: USB host — the SOLO's lines

**Files:**
- Create:
  - `firmware/solo_bridge/main/line_splitter.c` and `line_splitter.h`: pure.
  - `firmware/solo_bridge/main/solo_line.c` and `solo_line.h`: pure.
  - `firmware/solo_bridge/main/usb_solo.c` and `usb_solo.h`: glue.
- Test: `host_test/test_line_splitter.c`, `host_test/test_solo_line.c`

**Interfaces:**
- Produces:
  ```c
  #define SOLO_LINE_MAX 160
  typedef void (*line_cb_t)(const char *line, void *ctx);   /* NUL-terminated, no terminator */
  typedef struct { char buf[SOLO_LINE_MAX + 1]; size_t len; bool overflow; } line_splitter_t;
  void line_splitter_reset(line_splitter_t *s);
  /* Splits on '\n'; drops one '\r' right before it; never emits an empty line;
     a line longer than SOLO_LINE_MAX is dropped whole (overflow until the next '\n'). */
  void line_splitter_feed(line_splitter_t *s, const uint8_t *data, size_t n, line_cb_t cb, void *ctx);

  /* True when the line has a token "O2" (any case) followed by a token of [-0-9.*]+.
     Mirrors parseSoloLine's "has an O2 field" test, and nothing more. */
  bool solo_is_data_line(const char *line);

  /* usb_solo.h */
  #define SOLO_VID 0xA600
  #define SOLO_PID 0xE212
  typedef struct {
    void (*on_attach)(void);
    void (*on_detach)(void);
    void (*on_line)(uint64_t up_ms, const char *line);
  } usb_solo_events_t;
  void usb_solo_start(const usb_solo_events_t *ev);  /* USB host task + CDC-ACM; called once */
  bool usb_solo_attached(void);
  ```

- [ ] **Step 1: Write the failing tests:**
  - `"He  10.0 %\r\nO2 21"` then `".0 %\r\n"` gives exactly two lines, `"He  10.0 %"` and `"O2 21.0 %"`, with the double space kept;
  - `"\r\n\r\n"` gives none;
  - a lone `\r` inside a line is kept;
  - 200 bytes without `\n` and then `"x\nO2 1\n"` give only `"O2 1"`;
  - `solo_is_data_line`:
    - true for the capture line `He   0.4 %  O2  19.8 %  Ti  21.7 ~C  1029.5 hPa   2026/11/03 15:19:15`, for `"O2 ***.* %"` and for `"o2 20.9"`;
    - false for `"Divesoft SOLO"`, `""`, `"O2"` and `"O2 %"`.

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement the two pure modules, then `usb_solo.c`:**
  - `usb_host_install`, a client task, and `cdc_acm_host_install`;
  - open with VID/PID and `CDC_HOST_ANY_IFACE`;
  - on open, `cdc_acm_host_line_coding_set` 115200 8N1 and `cdc_acm_host_set_control_line_state(dtr=true, rts=false)`;
  - the data callback feeds the splitter and stamps lines with `esp_timer_get_time() / 1000`;
  - the device-event `CDC_ACM_HOST_DEVICE_DISCONNECTED` closes the device, resets the splitter, calls `on_detach`, and re-arms the open loop;
  - `USB_SEL` is set high in `power_init`, before `usb_host_install`.

- [ ] **Step 4: Host tests pass, and `idf.py build` passes.**

- [ ] **Step 5: Wire into `main.c`.**
  - Log `solo attach`, `solo detach`, and every 25th line as `line <text>`.
  - The yellow LED is on while no SOLO is attached.

- [ ] **Step 6: Commit** `feat(bridge): read SOLO lines over USB host`.

### Task 4: BLE link and protocol v0 (`HELLO`, `ST`, `L`, `LIVE`, `CFG`, `TIME`)

**Files:**
- Create:
  - `firmware/solo_bridge/main/bridge_proto.c` and `bridge_proto.h`: pure.
  - `firmware/solo_bridge/main/ble_link.c` and `ble_link.h`: NimBLE glue.
  - `firmware/solo_bridge/host_test/golden/wire_v1.txt`
- Modify: `main.c`
- Test: `host_test/test_bridge_proto.c`

**Interfaces:**
- Produces:
  ```c
  /* Formatters write one message WITHOUT '\n' into out (cap bytes incl. NUL) and return its length,
     or 0 when it would not fit. */
  typedef struct { const char *fw, *bridge, *epoch; uint32_t boot; uint64_t up_ms; bool solo, rec, vbus;
                   uint32_t batt_mv, pending; } proto_hello_t;
  typedef struct { bool solo, data; uint32_t pending, batt_mv; uint64_t up_ms; } proto_status_t;
  size_t proto_fmt_hello(char *out, size_t cap, const proto_hello_t *h);
  size_t proto_fmt_status(char *out, size_t cap, const proto_status_t *s);
  size_t proto_fmt_live_line(char *out, size_t cap, const char *solo_line);        /* "L <line>" */

  typedef enum { CMD_UNKNOWN, CMD_TIME, CMD_LIVE, CMD_STATE, CMD_ACK, CMD_FB, CMD_CFG } proto_cmd_kind_t;
  typedef struct {
    proto_cmd_kind_t kind;
    uint64_t time_ms;                         /* CMD_TIME */
    bool live_on;                             /* CMD_LIVE */
    char state[16], mix[17];                  /* CMD_STATE: wire code, optional mix */
    char rid[24];                             /* CMD_ACK, CMD_FB */
    char fb_code[10], fb_text[25];            /* CMD_FB */
    int8_t cfg_rec, cfg_vbus;                 /* CMD_CFG: -1 not given, 0 off, 1 on */
  } proto_cmd_t;
  /* Never fails: anything malformed is CMD_UNKNOWN. A trailing '\r' is ignored. */
  void proto_parse_cmd(const char *line, proto_cmd_t *out);

  /* Splits a message of len bytes (with its '\n') into notifications of at most mtu-3 bytes.
     Returns the size of chunk number i, or 0 past the end. */
  size_t proto_chunk_len(size_t len, uint16_t mtu, size_t i);

  /* ble_link.h */
  typedef struct { void (*on_subscribed)(void); void (*on_disconnected)(void);
                   void (*on_command)(const proto_cmd_t *cmd); } ble_link_events_t;
  void ble_link_start(const ble_link_events_t *ev, const char *name);
  bool ble_link_subscribed(void);
  bool ble_link_send(const char *msg);  /* appends '\n'; false when not subscribed or out of buffers */
  ```
- Consumed by the app (Task 5): the exact `HELLO`/`ST`/`L` text, through `wire_v1.txt`.

- [ ] **Step 1: Write the failing tests:**
  - `proto_fmt_hello` with fw `0.1.0`, bridge `a0b1c2d3e4f5`, epoch `1a2b3c4d`, boot 7, up 123456, solo 1, rec 0, vbus 0, batt 3987, pending 0 gives exactly `HELLO proto=1 fw=0.1.0 bridge=a0b1c2d3e4f5 epoch=1a2b3c4d boot=7 up=123456 solo=1 rec=off vbus=off batt=3987 pending=0`;
  - `proto_fmt_status` gives exactly `ST solo=1 data=0 pending=0 batt=3987 up=5000`;
  - `proto_fmt_live_line` keeps every byte of the capture line;
  - parsing:
    - `TIME 1762700000000`;
    - `LIVE ON`, `LIVE OFF`;
    - `CFG rec=on vbus=off`, `CFG vbus=on` (rec −1);
    - `ACK 1a2b3c4d-7`;
    - `FB 1a2b3c4d-7 saved SIGN OFF LATER` (text with spaces);
    - `STATE stable TX21/35`, `STATE air`;
    - and `HELLO`, `LIVE`, `CFG rec=maybe`, `ACK` and `""` are all `CMD_UNKNOWN`;
  - **`chunks never exceed mtu-3 and rejoin to the line`:** for a 140-byte message and MTUs 23, 185 and 247, every chunk is ≤ mtu − 3 and the sizes add up to 140;
  - **golden:** the test writes the three formatted messages above to `golden/wire_v1.txt.out` and `CHECK`s they equal `golden/wire_v1.txt` line for line. Commit the golden file by hand, from the expected strings.

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement `bridge_proto.c`, then `ble_link.c`:**
  - NimBLE host task; device name from `main.c`;
  - advertising data: flags and the 128-bit NUS UUID; scan response: the complete name;
  - one connection; re-advertise on disconnect;
  - GATT: the NUS service with RX (write and write-without-response) and TX (notify);
  - RX bytes go through a second `line_splitter_t` with `SOLO_LINE_MAX` 160, then `proto_parse_cmd`, then `on_command`;
  - TX sends `proto_chunk_len` slices with `ble_gatts_notify_custom`, using the connection's MTU from `ble_att_mtu`;
  - `on_subscribed` fires when the TX CCCD is enabled.

- [ ] **Step 4: Wire into `main.c`:**
  - Name: `Anchorline Bridge XXXX` from `esp_efuse_mac_get_default`. The bridge id is the same MAC as 12 lowercase hex digits.
  - On subscribe: send `HELLO` (`fw=0.1.0`, `rec` from settings, `pending=0`).
  - Every 5000 ms and on attach/detach: send `ST`. `data=1` when a data line came in the last 1000 ms.
  - Each SOLO line: send `L <line>` when `LIVE ON`. `LIVE` resets to off on disconnect.
  - `CMD_CFG`: persist the fields that are given; a `vbus` change calls `power_set_vbus`.
  - `CMD_TIME`: log it (Part B uses it).
  - Green LED on while a phone is subscribed.

- [ ] **Step 5: Host tests pass and `idf.py build` passes.** Then, on the board with the Mac, using nRF Connect or LightBlue on a phone:
  - the bridge advertises with the right name;
  - subscribing to TX shows `HELLO` and then `ST` every 5 s;
  - writing `LIVE ON\n` to RX starts `L` lines while the SOLO is attached with "send data to USB" on;
  - writing `CFG vbus=on\n` logs `vbus src=…` on the monitor.

- [ ] **Step 6: Commit** `feat(bridge): Nordic UART link with HELLO, ST and live lines`.

### Task 5: App — `BridgeLink` and `BleBridgeTransport`

**Files:**
- Create:
  - `lib/analyzer/bridge/bridge_link.dart`: pure.
  - `lib/analyzer/bridge/bridge_link_fbp.dart`: `flutter_blue_plus`.
  - `lib/analyzer/transport/ble_bridge_transport.dart`: pure.
  - `test/_helpers/fake_bridge_link.dart`
- Test:
  - `test/analyzer/transport/ble_bridge_transport_test.dart`
  - `test/analyzer/bridge/bridge_wire_golden_test.dart`

**Interfaces:**
- Consumes: `parseBridgeMessage`, `BridgeHello`, `BridgeStatus`, `BridgeLiveLine`, `formatTime`, `formatLive`, `formatConfig` and `kBridgeProtocolVersion` from `bridge_protocol.dart`; `SerialLineBuffer` from `serial_line_buffer.dart`; `AnalyzerTransport`.
- Produces:
  ```dart
  // bridge_link.dart
  const String kNusServiceUuid = '6e400001-b5a3-f393-e0a9-e50e24dcca9e';
  const String kNusRxUuid = '6e400002-b5a3-f393-e0a9-e50e24dcca9e'; // app writes
  const String kNusTxUuid = '6e400003-b5a3-f393-e0a9-e50e24dcca9e'; // bridge notifies
  const String kBridgeNamePrefix = 'Anchorline Bridge';
  const Duration kBridgeFirstConnectTimeout = Duration(seconds: 15);
  enum BridgeLinkState { disconnected, connecting, connected }
  class BridgeLinkException implements Exception { const BridgeLinkException(this.message); final String message; }
  abstract class BridgeLink {
    Stream<String> get lines;               // reassembled, terminator stripped; broadcast
    Stream<BridgeLinkState> get states;     // broadcast
    BridgeLinkState get state;
    /// First connection. Throws BridgeLinkException('Bridge not found. Is it switched on?')
    /// after kBridgeFirstConnectTimeout. After a first connection, drops reconnect by
    /// themselves (connecting -> connected) until disconnect().
    Future<void> connect();
    Future<void> send(String message);      // appends '\n'
    Future<void> disconnect();
    Future<void> dispose();
  }

  // bridge_link_fbp.dart
  class FbpBridgeLink implements BridgeLink { FbpBridgeLink({required String remoteId}); }
  class FoundBridge { const FoundBridge({required this.id, required this.name}); final String id, name; }
  /// Scans for devices that advertise the NUS service AND whose name starts with kBridgeNamePrefix.
  Stream<List<FoundBridge>> scanForBridges({Duration timeout = const Duration(seconds: 10)});
  Future<void> stopBridgeScan();

  // ble_bridge_transport.dart
  class BleBridgeTransport implements AnalyzerTransport {
    BleBridgeTransport({
      required BridgeLink link,
      required bool Function() recording,   // settings.analyzerLogOnOk, read at each (re)connect
      required bool Function() vbusOn,      // settings.analyzerBridgeVbus
      DateTime Function()? now,
      Duration helloTimeout = const Duration(seconds: 5),
    });
    String get name => 'Bridge';
    Stream<BridgeMessage> get messages;     // every parsed line except L; broadcast (Part B)
    BridgeHello? get lastHello;
    BridgeStatus? get lastStatus;           // also updated from HELLO
    Stream<void> get bridgeChanges;         // fires when lastHello/lastStatus change
    Future<void> send(String message);      // no-op unless the link is connected
    Future<void> sendConfig();              // formatConfig(recording(), vbusOn())
  }
  ```

**Behaviour of `BleBridgeTransport`:**

| Event | Status | Also |
|---|---|---|
| `connect()` called | `connecting` | `link.connect()` |
| link connected | stays `connecting` | sends `TIME`, then `CFG`, then `LIVE ON`, in that order |
| `HELLO` with `proto == kBridgeProtocolVersion` | `connected` | |
| `HELLO` with another `proto` | `error`: `Bridge firmware speaks protocol N. Update the app or the bridge.` | disconnects |
| no `HELLO` within `helloTimeout` of the link connecting | `error`: `The bridge did not answer.` | disconnects |
| first connect throws | `error`: the exception's message | |
| link drops after `connected` | `connecting` | waits for the link to reconnect, then the same steps again |
| `L <line>` | | `lines` emits `<line>` |
| `disconnect()` | `disconnected` | sends `LIVE OFF` if connected, then `link.disconnect()` |

- [ ] **Step 1: Write the failing tests** with `FakeBridgeLink`, which records `sent` and lets the test push `lines` and `states`:
  - `connect sends TIME, CFG and LIVE ON in order`: `sent` is `['TIME 1762700000000', 'CFG rec=off vbus=off', 'LIVE ON']`;
  - `HELLO makes the transport connected`;
  - `L lines come out as analyzer lines, spaces intact`;
  - `HELLO with proto=2 is an error naming the version`;
  - `no HELLO in 5 s is an error` (with `fakeAsync`);
  - `a dropped link goes back to connecting and resends TIME, CFG, LIVE ON on reconnect`;
  - `disconnect sends LIVE OFF`;
  - `ST updates lastStatus and fires bridgeChanges`;
  - in `bridge_wire_golden_test.dart`: every line of `firmware/solo_bridge/host_test/golden/wire_v1.txt` parses to something other than `BridgeUnknown`, and the `HELLO` line has `bridgeId == 'a0b1c2d3e4f5'`.

  A test for `FbpBridgeLink`'s reassembly goes through `SerialLineBuffer`: **`a line split over three notifications arrives whole`**. Feed it the byte chunks a 23-byte MTU would give for a 140-byte `L` line.

- [ ] **Step 2: Run them and see them fail.**

  Run: `flutter test test/analyzer/transport/ble_bridge_transport_test.dart test/analyzer/bridge/bridge_wire_golden_test.dart`

- [ ] **Step 3: Implement.**
  - `FbpBridgeLink` follows `PhomemoBlePrinter.connect` (`lib/label_printer/phomemo/ble/phomemo_ble_printer.dart`):
    - `waitForBluetoothOn`;
    - `connect(autoConnect: true, mtu: null)`, then wait for `connectionState == connected` with the first-connect timeout;
    - on Android, `requestMtu(247)`, with its failure only logged;
    - `discoverServices`, find TX/RX by UUID, `onValueReceived` into a `SerialLineBuffer`, `setNotifyValue(true)`;
    - writes are chunked to `mtuNow - 3`, with response when RX supports it.
  - The scanner follows `PhomemoBleScanner`: subscribe before `startScan(withServices: [Guid(kNusServiceUuid)])`, and filter on the name prefix.
  - The FBP code has no unit tests, like the printer's; it is checked on the bench.

- [ ] **Step 4: Run the tests; they pass.** `flutter analyze` is clean.

- [ ] **Step 5: Commit** `feat(analyzer): BLE bridge link and transport (#113)`.

### Task 6: App — pairing in Settings, the Bridge source, the 5 V switch

**Files:**
- Modify:
  - `lib/ui/notifiers/settings_notifier.dart`: keys `analyzer_bridge_id`, `analyzer_bridge_name`, `analyzer_bridge_vbus`.
  - `lib/analyzer/transport/analyzer_transport_options.dart`: `defaultAnalyzerTransportOptions({AnalyzerTransportOption? bridge})`.
  - `lib/ui/notifiers/analyzer_session.dart`:
    - pass the bridge option;
    - `_okWanted` is false while the transport is a `BleBridgeTransport` (Part B adds the bridge path);
    - send `sendConfig()` when `analyzerLogOnOk` or `analyzerBridgeVbus` changes while connected over the bridge.
  - `lib/ui/screens/settings/gas_tab.dart`: an "Analyzer bridge" section under "Label printer".
  - `lib/ui/widgets/analyzer/connection_strip.dart`: one bridge line.
- Create:
  - `lib/ui/widgets/analyzer/bridge_transport_option.dart`
  - `lib/ui/widgets/analyzer_bridge_settings_section.dart`
- Test:
  - `test/ui/widgets/analyzer_bridge_settings_section_test.dart`
  - `test/ui/notifiers/analyzer_session_test.dart` (extend)
  - `test/ui/notifiers/settings_notifier_test.dart` (extend)

**Interfaces:**
- Consumes: `BleBridgeTransport`, `BridgeLink`, `FbpBridgeLink`, `scanForBridges` and `FoundBridge` from Task 5.
- Produces:
  ```dart
  // SettingsNotifier
  String? get analyzerBridgeId;  String? get analyzerBridgeName;
  Future<void> setAnalyzerBridge({required String id, required String name});
  Future<void> forgetAnalyzerBridge();
  bool get analyzerBridgeVbus;               // default false
  Future<void> setAnalyzerBridgeVbus(bool on);

  // bridge_transport_option.dart
  /// The "Bridge" source. Offered on iOS, Android and macOS. When no bridge is paired,
  /// its picker opens the find dialog first and pairs the one picked.
  AnalyzerTransportOption bridgeTransportOption(
    SettingsNotifier settings, {
    BridgeLink Function(String remoteId)? linkFactory,                     // tests
    Future<FoundBridge?> Function(BuildContext context)? findBridge,       // tests
  });
  ```
- **Order of sources:**
  - iOS: Bridge, Demo, with Bridge selected by default.
  - Android: USB (Android), Bridge, Demo.
  - macOS: USB, Bridge, Demo.
  - Windows and Linux: unchanged (no bridge in v1).

**UI copy:**
- **Settings → Gas → "Analyzer bridge":**
  - a row with the bridge's name, or `No bridge set up`;
  - buttons `Find bridge` and `Forget bridge`;
  - a switch `Power the analyzer from the bridge`, with the helper `Off: the SOLO runs on its own battery. On: the bridge supplies 5 V, which also charges the SOLO.`
- **Connection strip,** while connected over the bridge: `Bridge · SOLO connected` or `Bridge · no SOLO`, then ` · battery 3.9 V` when `batt ≥ 3000`, else ` · USB powered`, then ` · 5 V on` when `vbusOn`.

- [ ] **Step 1: Write the failing tests:**
  - the settings round-trip (set, read back after reload, forget);
  - the section shows `No bridge set up`; `Find bridge` with an injected `findBridge` returning `FoundBridge(id: 'X', name: 'Anchorline Bridge 1A2B')` stores it, and the row shows the name;
  - turning the switch on calls `setAnalyzerBridgeVbus(true)`;
  - `AnalyzerSession` with a fake bridge option:
    - the Log on OK logger is **not** built while connected over the bridge, even with `analyzerLogOnOk` on;
    - toggling `analyzerBridgeVbus` while connected sends `CFG rec=off vbus=on`.

- [ ] **Step 2: Run them and see them fail.**

- [ ] **Step 3: Implement.** The find dialog reuses the shape of `_FindPrinterDialog` in `label_printer_settings_section.dart`.
  - A scan that ends with nothing found shows `No bridge found. Switch it on and keep it close.`
  - Bluetooth off shows `Bluetooth is off`.

- [ ] **Step 4: Tests pass, and `flutter analyze` is clean.**

- [ ] **Step 5: Commit** `feat(analyzer): pair the SOLO bridge and use it as a source (#113)`.

### Task 7: Bench — live readings over the bridge, and the 5 V question (Egbert, with the implementer)

There is no code in this task. The results go into the spec and the firmware README.

- [ ] **Step 1: Live readings.**
  - Bridge on a power bank (DEV plug), SOLO on the host port, the SOLO's "send data to USB" on.
  - Pair the bridge on the iPhone and on the Mac. Connect the Bridge source.
  - Expected: live readings and the stability pill on both, and the connection-strip line.
  - Switch the SOLO off and on: the strip shows `no SOLO`, then the readings come back.
  - Walk out of range and back: the screen shows connecting, then readings again, without a tap.

- [ ] **Step 2: Does the SOLO enumerate without host 5 V?**
  - With `Power the analyzer from the bridge` **off**, unplug and replug the SOLO, and switch it on.
  - Expected, if it works: the monitor logs `solo attach` and lines flow.
  - Write down yes or no.

- [ ] **Step 3: Meter readings.**
  - Put the USB power meter between the bridge's host port and the SOLO cable, and turn the switch on.
  - Read the current with the SOLO:
    - (a) off;
    - (b) on and idle;
    - (c) measuring;
    - (d) fully charged and measuring.
  - Also note `host_vbus` from the monitor log.

- [ ] **Step 4: Egbert decides the default** and whether "on" is allowed at all. Possible outcomes:
  - keep off (it enumerates without 5 V);
  - allow on but default off;
  - on only in combination with a hardware change.

  Record the table and the decision in a new section of the spec, "Bench results, step 1 (date)", and in the firmware README.

- [ ] **Step 5: Commit the doc changes. Open the Part A PR.** Its body has:
  - the bench table;
  - "Refs #113";
  - the release note "the bridge is a new analyzer source on iPhone, Android and Mac".

---

## Part B — bridge v1: OK records (spec build step 2)

Start only after the Part A PR has merged and Task 7 is recorded.

### Task 8: Hold detector in firmware, tested against the captures

**Files:**
- Create: `firmware/solo_bridge/main/hold_detector.c` and `hold_detector.h` (pure).
- Create: `firmware/solo_bridge/host_test/capture_reader.c` and `capture_reader.h`. These read `test/fixtures/analyzer/solo_ok_presses_2026-11-03_{a,b}.txt`; the format is described in `test/_helpers/solo_capture_log.dart`.
- Test: `host_test/test_hold_detector.c`

**Interfaces:**
- Consumes: `solo_is_data_line`, `SOLO_LINE_MAX`.
- Produces:
  ```c
  #define HOLD_SILENCE_MS          2000
  #define HOLD_FIRST_MIN_FLOW_MS   5000
  #define HOLD_NEXT_MIN_FLOW_MS    3000
  #define HOLD_WINDOW_MS          30000
  #define HOLD_WINDOW_MAX_LINES     200   /* 30 s at 5 Hz is 150 */
  typedef struct { uint64_t at_ms; char line[SOLO_LINE_MAX + 1]; } hold_line_t;
  typedef struct { uint64_t held_at_ms; size_t n; hold_line_t lines[HOLD_WINDOW_MAX_LINES]; } hold_t; /* oldest first, last = held */
  typedef struct { /* private: ring of hold_line_t, flow_start, holds, fired, has_flow */ } hold_detector_t;
  void hold_detector_reset(hold_detector_t *d);                                   /* = attach / detach */
  void hold_detector_add_line(hold_detector_t *d, uint64_t now_ms, const char *line);
  bool hold_detector_tick(hold_detector_t *d, uint64_t now_ms, hold_t *out);      /* true once per hold */
  ```
  The rule is exactly the Dart `HoldDetector` (`lib/analyzer/hold_detector.dart`):
  - non-data lines are ignored;
  - a line after a silence of ≥ 2000 ms, or after a fired hold, is a resume and clears the window;
  - the window holds only lines since the last resume, capped at 30000 ms;
  - min flow is 5000 ms for the first hold since reset and 3000 ms after that;
  - a hold fires once per silence.

- [ ] **Step 1: Write the failing tests.** Replay each capture: feed RX lines at their times, tick every 200 ms of capture time, and call reset at each ERROR line.
  - **capture a:** holds at `held_at_ms` 58357 and 119677, held lines containing `Ti  22.0` and `Ti  22.2`, `lines[n-1].at_ms == held_at_ms`, and `held_at_ms - lines[0].at_ms <= 30000`;
  - **capture b:** one hold, at 17518, containing `Ti  22.5`;
  - port the synthetic cases from `test/analyzer/hold_detector_test.dart`, same names and same numbers:
    - `no hold before 5 s of flow`;
    - `5 s of flow is enough for the first hold`;
    - `after a hold, 3 s of flow arms the next one`;
    - `dips under 2 s do not reset arming`;
    - `a silence of 2 s or more that did not fire restarts the flow`;
    - `a short resume and a second silence is not 3 s of flow`;
    - `non-data lines are not flow`.

- [ ] **Step 2: Run them and see them fail.** Then **Step 3: Implement.**
  - The window is a fixed ring of `HOLD_WINDOW_MAX_LINES`.
  - When it is full, the oldest line is dropped even if it is under 30 s old.

- [ ] **Step 4: The host tests pass.** **Step 5: Commit** `feat(bridge): OK hold detector, checked against the SOLO captures`.

### Task 9: Record store on LittleFS

**Files:**
- Create: `firmware/solo_bridge/main/record_store.c` and `record_store.h`: pure C stdio, `opendir`/`readdir`, `rename` and `fsync`; LittleFS is mounted through VFS on the device.
- Modify: `main/idf_component.yml` (add `joltwallet/littlefs`) and `main.c` (mount `storage` at `/rec`).
- Test: `host_test/test_record_store.c`, which uses a temp directory from `mkdtemp`.

**Interfaces:**
- Consumes: `hold_t` (keep it `static` in the caller: about 33 KB, too big for a task stack).
- Adds four formatters to `bridge_proto.c`/`.h` at the start of this task, with their golden lines. They take scalars, so `bridge_proto.h` does not include `record_store.h`.
- Produces:
  ```c
  #define RECORD_STORE_MAX 50
  typedef struct { char dir[64]; char epoch[9]; uint32_t next_counter; size_t count; } record_store_t;
  typedef struct { uint32_t boot; uint64_t up_ms; uint64_t wall_ms; bool live; } record_meta_t;
  /* Deletes *.tmp, counts *.rec. next_counter = max(persisted, highest counter on disk + 1). */
  bool record_store_open(record_store_t *s, const char *dir, const char *epoch, uint32_t persisted_counter);
  bool record_store_full(const record_store_t *s);
  /* Writes <epoch>-<counter>.tmp (the REC, W and H lines, '\n'-terminated), fsyncs, renames to .rec.
     Calls persist(next) BEFORE writing, so a counter is never reused. False when full or on I/O error. */
  bool record_store_put(record_store_t *s, const record_meta_t *m, const hold_t *h,
                        void (*persist)(uint32_t next, void *ctx), void *ctx, char rid_out[24]);
  bool record_store_oldest(const record_store_t *s, char rid_out[24]);   /* lowest counter of this epoch, then others */
  FILE *record_store_read(const record_store_t *s, const char *rid);      /* caller fcloses */
  bool record_store_delete(record_store_t *s, const char *rid);           /* false when not there */

  size_t proto_fmt_rec(char *out, size_t cap, const char *rid, uint32_t boot, uint64_t up_ms,
                       uint64_t wall_ms, bool live);                                     /* "REC <rid> boot= up= wall= live=" */
  size_t proto_fmt_w(char *out, size_t cap, int64_t offset_ms, const char *line);        /* "W <off> <line>" */
  size_t proto_fmt_h(char *out, size_t cap, const char *line);                           /* "H <line>" */
  size_t proto_fmt_end(char *out, size_t cap, const char *rid);                          /* "END <rid>" */
  ```
  `settings.h` gains `uint32_t settings_counter(void); void settings_set_counter(uint32_t)`.

- [ ] **Step 1: Write the failing tests:**
  - a put then a read gives the `REC` line, every `W` line with offset ≤ 0 (the last 0), and the `H` line, all byte for byte;
  - rids are `<epoch>-1`, `<epoch>-2`, …;
  - 50 puts succeed, the 51st returns false, and `full` is true; after one delete, a put succeeds again;
  - `oldest` returns the lowest counter;
  - delete of an unknown rid is false;
  - **`a torn tmp file is deleted at open and the counter moves on`:**
    - a put of counter 7 persists 8 *before* it writes, so a power cut leaves `1a2b3c4d-7.tmp` and a persisted 8;
    - write `1a2b3c4d-7.tmp` by hand and open with persisted counter 8;
    - the tmp file is gone, `count` is 0, and the next put returns `1a2b3c4d-8`;
    - a persist spy shows `persist(9)` was called while `1a2b3c4d-8.tmp` did not exist yet.
  - Golden: append one `REC`, one `W`, one `H` and one `END` line to `golden/wire_v1.txt`.

- [ ] **Step 2: Fail. Step 3: Implement. Step 4: Pass.** Also run `idf.py build`.

- [ ] **Step 5: Commit** `feat(bridge): record store in flash`.

### Task 10: Protocol v1 in firmware — making, sending and confirming records

**Files:**
- Create: `firmware/solo_bridge/main/outbox.c` and `outbox.h`: pure.
- Modify: `main.c` (the bridge's main loop), `bridge_proto.c` (`HELLO` gets the real `pending`).
- Test: `host_test/test_outbox.c`

**Interfaces:**
- Produces:
  ```c
  typedef struct { bool ready; bool in_flight; char rid[24]; } outbox_t;
  void outbox_on_disconnect(outbox_t *o);                 /* ready=false, in_flight=false */
  void outbox_on_time(outbox_t *o);                       /* the app's TIME: ready=true */
  /* The rid to send now, or NULL. Sends one at a time: NULL while one is in flight. */
  const char *outbox_next(outbox_t *o, const record_store_t *s);
  void outbox_on_ack(outbox_t *o, record_store_t *s, const char *rid);  /* deletes it if stored; clears in_flight if it matches */
  ```

**Rules in `main.c`:**
- **Making a record:**
  - The 200 ms tick calls `hold_detector_tick`.
  - On a hold: if `settings_rec()` is off, nothing.
  - If the store is full: no record, and the yellow LED goes on.
  - Otherwise, `record_store_put` with:
    - `boot`;
    - `up` = `held_at_ms`;
    - `wall` = `time_offset + held_at_ms` when a `TIME` has arrived this boot, else 0;
    - `live` = `ble_link_subscribed()`.
- **Sending:**
  - After the app's `TIME`, the bridge sends the oldest record: the file's lines, then `END <rid>`.
  - The next one goes only after its `ACK`.
- **Feedback:**
  - `FB` is kept for the screen with its arrival time.
  - `STATE` is kept for the screen with its arrival time.
- `CFG rec` persists.
- `ST`'s `pending` is the store count.
- **A hold while detached never fires:** `on_detach` resets the detector, as `on_attach` does.

- [ ] **Step 1: Write the failing tests** for `outbox`:
  - nothing is sent before `TIME`;
  - after `TIME` the oldest rid comes, and `NULL` follows until its `ACK`;
  - after the `ACK` the next rid comes;
  - an `ACK` for another stored rid deletes that one and leaves the in-flight one in flight;
  - **`disconnect mid-send resends the same record from REC`:** `TIME`, `next` gives rid 1, disconnect, `TIME`, and `next` gives rid 1 again.

- [ ] **Step 2: Fail. Step 3: Implement. Step 4: Pass.** Also run `idf.py build`.

- [ ] **Step 5: Bench with nRF Connect on a phone.** With `CFG rec=on`, a held OK on the SOLO shows `REC`… `END` after writing `TIME 1\n`, and writing `ACK <rid>\n` removes it (`pending` drops in `ST`).

- [ ] **Step 6: Commit** `feat(bridge): OK records with REC/ACK over the link`.

### Task 11: Bridge screen, LEDs and the info button

**Files:**
- Create:
  - `firmware/solo_bridge/main/ui_state.c` and `ui_state.h`: pure.
  - `firmware/solo_bridge/main/ui.c` and `ui.h`: BSP + LVGL.
- Modify: `main/idf_component.yml` (add `espressif/esp32_s3_usb_otg: "^2.0.4"`) and `main.c`.
- Test: `host_test/test_ui_state.c`

**Interfaces:**
- Produces:
  ```c
  typedef enum {
    UI_BATTERY_EMPTY, UI_WAITING_FOR_PHONE, UI_CONNECTION_LOST, UI_PHONE_NOT_RESPONDING,
    UI_NO_SOLO, UI_SOLO_NO_DATA, UI_HELD_SAVING, UI_FULL, UI_BATTERY_LOW,
    UI_LAST_RESULT, UI_LIVE_STATE, UI_IDLE
  } ui_main_t;
  typedef struct {
    uint64_t now_ms;
    bool phone_ever, phone_connected, live_on;
    uint64_t last_state_ms;                 /* 0 = never */
    bool solo, solo_had_line;               /* a line since this attach */
    uint64_t solo_attach_ms;
    bool held_waiting_fb, full;
    uint32_t batt_mv;
    uint64_t last_fb_ms;                    /* 0 = never */
  } ui_inputs_t;
  ui_main_t ui_pick(const ui_inputs_t *in);
  /* The main-area text: "WAITING FOR PHONE", "CONNECTION LOST", "PHONE NOT RESPONDING", "NO SOLO",
     "SOLO: TURN ON SEND DATA TO USB", "HELD - SAVING...", "FULL - CONNECT PHONE", "BATTERY EMPTY",
     "BATTERY LOW"; for LAST_RESULT the FB text upper-cased with its code
     ("PRINTED EAN32", "SAVED - SIGN OFF LATER", "CHECK PHONE: MISMATCH", "AIR - NOT LOGGED", "NO READING");
     for LIVE_STATE "SETTLING... TX21/35", "STABLE TX21/35", "SENSOR ERROR", "AIR". */
  ```

**Priority:** the spec §2 table, in its order. **One change:**
- `BATTERY_EMPTY` (< 3300 mV with a battery present) comes first, because the bridge is about to die.
- `BATTERY_LOW` (< 3500 mV) comes after `FULL`.
- With no battery (< 3000 mV, USB powered) there is no battery state.

**Timing rules:**
- `PHONE_NOT_RESPONDING`: connected, `live_on`, and `now − last_state_ms > 10000`.
- `SOLO_NO_DATA`: attached, no line since attach, and `now − solo_attach_ms > 4000`.
- `LAST_RESULT`: for 10000 ms after `last_fb_ms`.
- `LIVE_STATE`: when a `STATE` arrived in the last 10000 ms.
- Otherwise `IDLE`, which shows `READY`.

**Screen layout:**
- The status line: `SOLO ✓/✗  PHONE ✓/✗  3.9V  5V`, or `USB` instead of the voltage when there is no battery.
- Then `3 waiting for phone` when `pending > 0`.
- The main text in the largest built-in Montserrat font that fits two lines.
- Colours: green for printed, saved and stable; amber for check, settling, held and full; red for error, connection lost and battery empty.

**LEDs:**
- Green: a 300 ms blink on each `ACK`.
- Yellow: on while `pending > 0`, or the state is FULL, CONNECTION LOST or BATTERY LOW/EMPTY.

**Buttons:** MENU (GPIO14) shows an info screen for 5 s: the bridge id, fw, battery mV, host VBUS mV, VBUS source and epoch.

- [ ] **Step 1: Write the failing tests:** one case per priority row (each with all the higher rows false), plus:
  - empty battery beats waiting for phone;
  - no battery means no battery state;
  - last result for 9999 ms and not at 10001 ms;
  - not responding at 10001 ms and not at 9999 ms;
  - SOLO no data at 4001 ms.

- [ ] **Step 2: Fail. Step 3: Implement** `ui_state.c`, then `ui.c` (`bsp_display_start`, one LVGL screen, redrawn on a 250 ms timer from `ui_pick`). **Step 4: Pass**, and run `idf.py build`.

- [ ] **Step 5: Look on the board:**
  - `WAITING FOR PHONE` at boot;
  - `NO SOLO` with a phone connected and no SOLO;
  - `CONNECTION LOST` after the phone leaves;
  - the info screen on MENU.

- [ ] **Step 6: Commit** `feat(bridge): status screen, LEDs and info button`. Set `fw=1.0.0`.

### Task 12: App — records from the bridge become analyses

**Files:**
- Create:
  - `lib/analyzer/ok_record_processor.dart` (pure): the save, print and mark-complete steps moved out of `UsbOkLogger._process`/`_saveAndPrint` unchanged.
  - `lib/analyzer/ok_logger.dart` (pure): the interface the save card binds.
  - `lib/analyzer/bridge/bridge_ok_handler.dart` (pure)
  - `lib/analyzer/bridge/bridge_state_reporter.dart` (pure)
- Modify:
  - `lib/analyzer/usb_ok_logger.dart`: implements `OkLogger` and delegates to `OkRecordProcessor`.
  - `lib/ui/notifiers/analyzer_session.dart`: the bridge path.
  - the save card and controller: bind `OkLogger` instead of `UsbOkLogger`.
- Test:
  - `test/analyzer/bridge/bridge_ok_handler_test.dart`
  - `test/analyzer/bridge/bridge_state_reporter_test.dart`
  - `test/analyzer/usb_ok_logger_test.dart`: unchanged, and it must still pass. This is the refactor's check.
  - `test/ui/notifiers/analyzer_session_test.dart`: extend.

**Interfaces:**
- Consumes:
  - `recordToAnalysis`, `BridgeClock`, `LogOnOkSetup`, `SaveRecord`, `SkipRecord` (plan 1);
  - `BridgeRecordAssembler`, `formatAck`, `formatFeedback`, `formatState`, `BridgeLiveState`, `FeedbackCode`;
  - `BleBridgeTransport.messages`/`send`/`sendConfig` (Task 5);
  - `isRoomAir`/`gasMixName` (`gas_naming.dart`);
  - `ReadingStability`;
  - `CaptureSource.bridgeOk`.
- Produces:
  ```dart
  // ok_logger.dart
  abstract class OkLogger {
    Stream<OkLogResult> get results;
    OkSetup Function()? setupProvider;
  }

  // ok_record_processor.dart
  class OkRecordProcessor {
    OkRecordProcessor({
      required Future<bool> Function(String id, NewGasAnalysis a) save,   // false = row id existed
      required Future<void> Function(String id) markComplete,
      Future<void> Function(GasAnalysis a, int copies)? printLabel,
      void Function(Object error, StackTrace stack)? onError,
    });
    /// Steps 1, 3 and 4 of spec §5 "Order of operations". [afterSave] runs right after the
    /// row is committed, or right after the decision not to save (spec §5 step 2: the ACK).
    Future<OkLogResult> process({
      required BridgeRecord record, required String bridgeId, required CaptureSource source,
      required BridgeClock clock, required DateTime now, required bool active, required OkSetup setup,
      Future<void> Function()? afterSave,
    });
  }
  // OkLogResult gains: final bool alreadySaved;  // default false
  // When save() returns false the processor returns (error, 'SAVE FAILED', analysisId: null,
  // alreadySaved: true) and still calls afterSave. afterSave is called after a commit, after a
  // skip decision, or when the row existed; never when save() threw.

  // bridge_ok_handler.dart
  class BridgeOkHandler implements OkLogger {
    BridgeOkHandler({
      required OkRecordProcessor processor,
      required Future<void> Function(String message) send,
      required bool Function() active,    // the session is connected over the bridge (always true in this plan while attached)
      Duration Function()? elapsed, DateTime Function()? now,
      void Function(Object error, StackTrace stack)? onError,
    });
    void onMessage(BridgeMessage m);      // HELLO resets the assembler and the clock; records are handled one at a time
    Future<void> dispose();
  }

  // bridge_state_reporter.dart
  const Duration kStateHeartbeat = Duration(seconds: 3);
  /// sensorError when o2 is NaN or <= 0; air when isRoomAir; stable/settling from stability; null with no reading.
  ({BridgeLiveState state, String? mix})? liveStateFor(AnalyzerReading? r, ReadingStability s);
  class BridgeStateReporter {
    BridgeStateReporter({required Future<void> Function(String message) send, Duration? heartbeat});
    void update(AnalyzerReading? r, ReadingStability s);   // sends on change
    void start(); void stop();                              // heartbeat resends the last state
  }
  ```

**Handler rules:**
- **The bridge id** is the latest `HELLO.bridgeId`. Records that end before any `HELLO` are dropped without an `ACK`; the bridge sends them again.
- **The clock** is rebased at receipt. On each `HELLO`/`ST`, keep `(boot, upMs, elapsed())`. At handling time the clock is `BridgeClock(boot, upMs + (elapsed() − receivedAt))`. This is the ruling note from plan 1, Task 3.
- **For each assembled record:**
  - Call `processor.process` with source `bridgeOk`, `active: active()`, the setup from `setupProvider`, and `afterSave: () => send(formatAck(rid))`.
  - Then send `formatFeedback(rid, result.code, result.text)`.
- **When the save throws:** no `ACK`, so the record stays on the bridge. Send `FB <rid> error SAVE FAILED`.
- **When the row existed** (`save` returned false):
  - `alreadySaved: true`;
  - `ACK`, then `FB <rid> saved ALREADY SAVED`;
  - no print.
  - The USB logger still reports `SAVE FAILED` here, as today.
- **`FB` text is ASCII:** `AIR - NOT LOGGED`, never an em dash.

**Session rules (`AnalyzerSession`), while the transport is a `BleBridgeTransport`:**
- Build a `BridgeOkHandler` whenever connected, **whether Log on OK is on or off**: waiting records are always collected (spec §4 "Records and sessions").
- Its results go to `_watchOkResults`. The save card binds it as its `OkLogger` when Log on OK is on.
- `CFG` is sent on every change of `analyzerLogOnOk`.
- A `BridgeStateReporter` runs while connected, fed from the controller on each notification.
- The USB `UsbOkLogger` is never built for the bridge (Task 6).

- [ ] **Step 1: Write the failing tests:**
  - `a live record with name set saves, ACKs after the save, prints, then sends FB printed`. Assert the order of `save`, `send('ACK …')`, `printLabel` and `send('FB … printed EAN32')`.
  - `room air is ACKed and answered AIR - NOT LOGGED without saving`.
  - `a record saved before is ACKed again and not saved twice`: `save` returns false; `sent` has `ACK` and `FB … saved ALREADY SAVED`; `printLabel` is never called.
  - `a failed save is not ACKed`.
  - `a record before HELLO is not ACKed`.
  - `two records are handled one after the other`: the second `save` starts only after the first `FB`.
  - `the clock is rebased at receipt`: `ST up=10000` at elapsed 0, record `up=9000`, handled at elapsed 3000. `analysedAt` is `now − 4000 ms`.
  - `liveStateFor`: NaN → sensorError; 20.9/0 → air; stable EAN32 → `(stable, 'EAN32')`.
  - The reporter sends on change, not on repeats, and resends after 3 s (fakeAsync).
  - Session:
    - connected over a fake bridge with Log on OK **off**, a record still saves (late, flagged), and `ACK` is sent;
    - with it on, the save card's setup is used.

- [ ] **Step 2: Fail. Step 3: Implement.**
  - Move the code out of `UsbOkLogger` first.
  - Run `flutter test test/analyzer/usb_ok_logger_test.dart`; it passes **unchanged**.
  - Then add the handler, the reporter and the session wiring.

- [ ] **Step 4: Run all the touched tests and `flutter analyze`.** **Step 5: Commit** `feat(analyzer): save OK records from the bridge (#113)`.

### Task 13: Bench — OK through the bridge (Egbert, with the implementer)

- [ ] **Step 1:** iPhone in hand, app open, Log on OK on, "analysed by" set, printer on.
  - OK on the SOLO with a mix gives an entry, a label, and `PRINTED <mix>` on the bridge.
  - Repeat on the Mac.
- [ ] **Step 2:** With Log on OK off, OK saves nothing and the bridge shows no `HELD`.
- [ ] **Step 3:** A quick double OK gives no record. Switching the SOLO off while measuring gives no record.
- [ ] **Step 4:** OK on room air gives `AIR - NOT LOGGED`.
  - Remember Egbert's SOLO reads 19.7–19.8 % on air until it is calibrated (spec §5). Calibrate it first, or expect an entry named Hypoxic 20.
- [ ] **Step 5:** Close the app, press OK on two cylinders. The bridge shows `2 waiting for phone`. Open the app and connect: two flagged entries appear, with no labels, and the counter goes to 0.
- [ ] **Step 6:** Press OK with the app closed, power-cycle the bridge, then connect. The entry arrives with its time taken from `wall` or the SOLO clock.
- [ ] **Step 7:** Record the results in the spec under "Bench results, step 2". Open the Part B PR with "Refs #113".

---

## Calls made in this plan (for Egbert to check)

1. **Plan 2 covers spec steps 1 and 2,** as plan 1 promised. It ships as two PRs with the 5 V bench in between. Background running stays in plan 3.
2. **ESP-IDF v5.5.x, not the newest v6.1:** the board's support package predates v6.
3. **The board does have battery pads and a charger** (Espressif's guide: solder pads on the back, 212.7 mA charging from the DEV plug, a battery switch). No extra IP5306 board is needed.
   - The guide names no low-voltage cut-off, so use a protected cell.
   - Until then, a power bank on the **DEV plug** (not the DEBUG port) runs the board **and** can feed the SOLO when the switch is on.
4. **"5 V on" takes the battery boost when a battery is fitted, else the DEV plug's 5 V.** The two are never on together.
5. **No Log on OK over the bridge until the firmware detects the press (Part B).**
   - Running the app's USB hold detector on bridge lines could take a Bluetooth hiccup of two seconds for an OK press.
   - So Part A's bridge is live readings only.
6. **Records are always collected while the app is connected over the bridge,** even with Log on OK off. They come in late and flagged, never lost.
7. **The bridge screen puts "battery empty" above everything else.** The rest is the spec's order.
8. **Firmware host tests run on the Mac with plain `make`,** not in CI yet (CI is `flutter analyze` + `flutter test`). The shared golden file is checked by a Dart test that does run in CI.
9. **The "Power the analyzer from the bridge" switch** sits in Settings → Gas → Analyzer bridge, off by default. The bench decides whether it stays.
