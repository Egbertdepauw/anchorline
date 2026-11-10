// SPDX-License-Identifier: Apache-2.0
//
// Pins of the Espressif ESP32-S3-USB-OTG board, from Espressif's user guide
// and the BSP header esp32_s3_usb_otg.h (checked 2026-11-09).
#pragma once

#define PIN_USB_SEL       18  // high: native USB to the USB-A host port; low: the DEV plug
#define PIN_BOOST_EN      13  // high: 5 V boost from the battery to the host port
#define PIN_DEV_VBUS_EN   12  // high: the DEV plug's 5 V passes through to the host port
#define PIN_LIMIT_EN      17  // high: MIC2005A 500 mA limiter on the host port
#define PIN_OVER_CURRENT  21  // input; polarity unclear between guide and BSP, only logged

#define PIN_LED_GREEN     15  // high: on
#define PIN_LED_YELLOW    16  // high: on
#define PIN_LCD_BL         9

#define PIN_BTN_OK         0  // also BOOT; active low
#define PIN_BTN_UP        10  // active low
#define PIN_BTN_DOWN      11  // active low
#define PIN_BTN_MENU      14  // active low

#define ADC_CH_HOST_VBUS   0  // ADC1 channel 0 (GPIO1)
#define ADC_CH_BATTERY     1  // ADC1 channel 1 (GPIO2)
#define HOST_VBUS_DIV_X10 37  // V_bus = 3.7 x pin voltage
#define BATTERY_DIV_X10   20  // V_bat = 2 x pin voltage
