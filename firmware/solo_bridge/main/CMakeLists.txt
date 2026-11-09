# SPDX-License-Identifier: Apache-2.0
idf_component_register(
    SRCS "main.c"
         "power_logic.c" "power.c"
         "settings.c"
         "line_splitter.c" "solo_line.c" "usb_solo.c"
         "bridge_proto.c" "ble_link.c"
         "hold_detector.c" "record_store.c" "outbox.c" "bridge_state.c"
         "ui_state.c" "ui.c"
    INCLUDE_DIRS ".")
