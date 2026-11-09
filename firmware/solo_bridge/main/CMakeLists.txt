# SPDX-License-Identifier: Apache-2.0
idf_component_register(
    SRCS "main.c"
         "power_logic.c" "power.c"
         "settings.c"
         "line_splitter.c" "solo_line.c" "usb_solo.c"
         "bridge_proto.c" "ble_link.c"
    INCLUDE_DIRS ".")
