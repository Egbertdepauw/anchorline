# SOLO bridge firmware

Firmware for the Espressif **ESP32-S3-USB-OTG** board.
- It reads a Divesoft SOLO gas analyzer over the board's USB-A host port.
- It passes the SOLO's lines to the Anchorline app over Bluetooth LE (Nordic UART Service).

Design: `docs/superpowers/specs/2026-11-03-background-gas-logging-design.md`, §1–§3.
Build plan: `docs/superpowers/plans/2026-11-09-solo-bridge-firmware-and-link.md`.

The firmware moves and keeps bytes; it never judges a gas. Mix names, stability and depths stay in the app.

## Licence

Apache-2.0 (see `LICENSE`), the same as ESP-IDF and NimBLE.
- Their licence can't be combined with the app's GPLv2 inside one firmware image that someone else receives.
- The firmware is a separate program. It talks to the app only over Bluetooth, so the app stays GPLv2.

## Toolchain

**ESP-IDF v5.5.6.** Not v6.x: the board support package (`espressif/esp32_s3_usb_otg` 2.0.4) predates v6.

ESP-IDF v5.5 does not support Python 3.15, Homebrew's current default. Use Python 3.13 for both installing and building.

Install once:

```bash
brew install cmake ninja dfu-util ccache python@3.13
git clone -b v5.5.6 --recursive --shallow-submodules --depth 1 https://github.com/espressif/esp-idf.git ~/esp/esp-idf
PATH=/opt/homebrew/opt/python@3.13/libexec/bin:$PATH ~/esp/esp-idf/install.sh esp32s3
```

In every new shell:

```bash
export PATH=/opt/homebrew/opt/python@3.13/libexec/bin:$PATH
. ~/esp/esp-idf/export.sh
```

## Build, flash, watch

```bash
cd firmware/solo_bridge
idf.py set-target esp32s3     # once
idf.py build
idf.py -p /dev/cu.usbserial-XXXX flash monitor
```

- Flash and monitor go through the **DEBUG** port (USB-C on the V1.1 board). It is a USB-to-UART bridge to UART0, and the log console is on it.
- The DEBUG port's chip is a WCH CH342 (`1a86:7522`). macOS has no driver for it built in: install WCH's **CH34xVCPDriver** (Mac App Store, or wch-ic.com), allow it in System Settings, and replug. The port then shows up as `/dev/cu.wchusbserial*`.
- If flashing doesn't start: hold OK (it is also BOOT, GPIO0), press RESET, then release OK.
- Quit the monitor with `Ctrl-]`.

## Host tests

The pure modules (line splitting, protocol, power switching order, and later the OK rule and the record store) have no ESP-IDF includes. They build and run on the Mac:

```bash
make -C firmware/solo_bridge/host_test
```

CI does not run these yet. `host_test/golden/wire_v1.txt` holds the exact wire lines the firmware sends. A Dart test in the app (`test/analyzer/bridge/bridge_wire_golden_test.dart`) parses the same file, so the two sides can't drift apart unnoticed.

## Hardware

Pins, from Espressif's user guide and the BSP header (`board.h`):

| Signal | GPIO | Level |
|---|---|---|
| `USB_SEL` | 18 | high: the native USB goes to the USB-A **host** port; low (default): the DEV plug |
| `BOOST_EN` | 13 | high: 5 V boost from the battery to the host port |
| `DEV_VBUS_EN` | 12 | high: the DEV plug's 5 V passes through to the host port |
| `LIMIT_EN` | 17 | high: MIC2005A 500 mA limiter on |
| `OVER_CURRENT` | 21 | input; the guide and the BSP disagree on polarity, so it is only logged |
| LED green / yellow | 15 / 16 | high: on |
| LCD backlight | 9 | |
| Battery ADC | 2 (ADC1 ch1) | V_bat = 2 × pin |
| Host VBUS ADC | 1 (ADC1 ch0) | V_bus = 3.7 × pin |
| Buttons | OK 0 (also BOOT), UP+ 10, DW− 11, MENU 14 | active low |
| LCD ST7789 240×240 | SPI3: SCLK 6, MOSI 7, CS 5, DC 4, RST 8 | |

### Power

**Host-port 5 V** (the guide's truth table):

| Mode | `BOOST_EN` | `DEV_VBUS_EN` |
|---|---|---|
| Off | 0 | 0 |
| From the DEV plug | 0 | 1 |
| From the battery | 1 | 0 |
| **Never** | 1 | 1 |

- **The bridge does not power the SOLO by default.** Host 5 V is off at boot, and stays off unless the app's "Power the analyzer from the bridge" switch is on (`CFG vbus=on`, persisted).
- When it is on, the bridge uses the battery boost if a battery is fitted, otherwise the DEV plug's 5 V.
- **The DEBUG port can power the board, but never the host port.** With the board on the DEBUG port, the SOLO always runs on its own battery.
- **Bench 2026-11-09:** the SOLO enumerates and streams with host 5 V off, so the switch stays off by default. With the SOLO plugged in and host 5 V off, `host_vbus` still reads about 5.1 V: the SOLO seems to drive VBUS itself. Not yet checked with a meter.
- **Battery:**
  - The board has battery solder pads on the back and an on-board charger: 212.7 mA from the DEV plug, with a red LED while charging. The battery switch must be OFF while charging.
  - The guide names no low-voltage cut-off. Use a **protected** 18650 cell, or power the board from a power bank.
