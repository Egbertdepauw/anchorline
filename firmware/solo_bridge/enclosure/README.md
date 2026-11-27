# Anchorline Bridge enclosure

A two-part 3D-printed case for the SOLO bridge board: an Espressif **ESP32-S3-USB-OTG**
(V1.1 layout) with its LCD sub-board stacked on top, as delivered. It is meant for a gas
fill station. It protects the board from knocks, dust and splashes, keeps the LCD
readable and the buttons usable, and leaves every connector reachable.

**Status: this has not been test-printed or test-fitted.** The first version uses
Espressif's published numbers. Several heights are not published; those are marked
`MEASURE` in the source and listed below.

| File | What |
| --- | --- |
| `bridge_enclosure.scad` | Parametric OpenSCAD source. All board numbers and tolerances are named parameters at the top. |
| `bridge_enclosure_base.stl` | Base, in print orientation |
| `bridge_enclosure_lid.stl` | Lid, in print orientation (upside down) |
| `previews/*.png` | Renders: base, lid, exploded assembly, closed views |

## How it works

- **Board stays assembled.** The stock kit screws the main PCB and the LCD sub-board
  together through octagonal spacers, and the bottom spacers act as feet. The case keeps
  that hardware. The feet sit in four shallow pockets in the base floor, and four rings
  on the lid ceiling press the sub-board down around the screw heads. The walls locate
  the PCB with 0.3 mm clearance.
- **Closure: 4 snap fits, no screws or inserts.** Two tabs are on the USB_DEV end wall
  and two are on the long walls next to the USB_HOST socket. Each lid tab drops into a
  pocket on the outside of the base and clicks into a groove. The pockets are open at
  the bottom. To open the case, push each tab tip outward with a small flat screwdriver
  from underneath. An outer lip on the base and the lid's inner skin overlap at the
  joint, which keeps splashes out of the seam.
- **Buttons: flexible tongues in the lid wall.** RST and MENU are on one long side;
  OK (BOOT), DW- and UP+ are on the other. Each tongue is cut free on three sides,
  hinged at the top, and has a nub that rests 0.15 mm off the side-push actuator. The
  button names are debossed on the lid top next to each tongue.
- **LCD:** the window is open (24 x 24 mm over the 23.4 mm active area). The outer face
  has a 26 x 26 x 1.0 mm recess for an optional clear plate: 1 mm acrylic or PETG sheet,
  glued in with a drop of CA or a thin ring of double-sided tape. Set `plate_t = 0` to
  drop the recess.
- **Openings:**
  - USB_HOST (analyzer) socket: the case end wraps the socket body. The socket face
    stands 0.5 mm proud, so a plug's overmould stops on the socket, not on the case.
  - USB_DEV plug: 12.5 mm of the plug sticks out past the case.
  - DEBUG port: an 11 x 8 mm opening that takes either a Micro-USB or a USB-C cable
    overmould.
  - Battery switch: a slot for the lever.
  - microSD: a card slot with a thumb scoop.
  - Green and yellow LEDs: two windows just under the PCB edge. The LEDs are on the
    board's bottom face.
  - The red charge LED gets no window, since no battery is fitted.
- **Bottom:** flat and closed. There are 3.5 mm of feet clearance for the bottom-side
  parts, battery pads and switch. "ANCHORLINE BRIDGE" is debossed underneath.
- **Lanyard / cable-tie tunnel:** a 2.8 mm tunnel runs across the base at the host end.
- **Outside size:** 77.5 x 36.6 x 20.1 mm, plus the USB_DEV plug sticking out.

## Printing

| | Base | Lid |
| --- | --- | --- |
| Orientation | As exported: floor on the plate | As exported: **top face on the plate** (upside down) |
| Supports | None | None |

- **Material:** PETG is recommended. The snap tabs and button tongues are flexures, and
  PETG tolerates that better than PLA. PLA works, but don't open the case often.
- **Settings:** 0.4 mm nozzle, 0.2 mm layers (0.16 mm gives crisper debossed text),
  3 walls, 15–20 % infill. Bambu Studio / Orca default PETG profile.
- **Elephant foot:** keep the slicer's elephant-foot compensation on (about 0.15 mm).
  The lid's window and labels are on the first layer.
- **Why no supports are needed:** every cut-out runs to the base/lid parting plane, so
  none needs a bridge. The lanyard tunnel is a teardrop.
- **Bambu Studio / Orca:** import both STLs, then use "Auto-orient: off". Don't rotate them.

## Adjusting it to your board

The board numbers come from Espressif. Your AliExpress board may differ, so measure it
with a caliper first (see "Things to measure" below). Then change the numbers at the top
of `bridge_enclosure.scad` and re-export.

1. Install OpenSCAD. The stable `openscad` Homebrew cask is disabled (Gatekeeper), so
   use `brew install --cask openscad@snapshot`.
2. Edit the parameters in the `BOARD` sections. The `CASE` section holds the wall,
   clearance and snap settings.
3. Re-export from this folder:

   ```sh
   openscad --backend=manifold -D 'part="base"' -o bridge_enclosure_base.stl bridge_enclosure.scad
   openscad --backend=manifold -D 'part="lid"'  -o bridge_enclosure_lid.stl  bridge_enclosure.scad
   ```

   Both should print `Status: NoError`. The console also echoes the outside size and the
   key heights.
4. Optional fit check. This command must produce only zero-thickness contacts: feet on
   the floor, socket on the base, rings on the sub-board. Any volume means a clash.

   ```sh
   openscad --backend=manifold -D 'part="clash"' -o /tmp/clash.stl bridge_enclosure.scad
   ```

5. Optional previews. Open the file in the OpenSCAD GUI with `part = "assembly"`, or
   with `part = "closed"` to see the case shut.

Other `part` values: `"board"` shows the board model alone.

Useful knobs:

- `clr`: board-to-wall clearance.
- `post_gap`: set it negative, for example -0.2, to preload the board if it rattles.
- `btn_rest`: the nub-to-button gap. Lower it if presses feel dead; raise it if a
  button is pressed all the time.
- `lip_clr`: the joint clearance.
- `snap_nub`: the snap strength.
- `dbg_open_w` / `dbg_open_h`: the DEBUG cable overmould opening.

## Things to measure (`MEASURE` parameters)

Use a caliper on the assembled board (LCD side up, USB_DEV plug to your left).

**Reference edges:**

- **Left edge:** the USB_DEV end of the main PCB. x is measured from here.
- **Front edge:** the long edge with OK/DW-/UP+, the switch and the DEBUG port. y is
  measured from here.
- **PCB top:** the top face of the main (lower) PCB. Heights are measured from here
  unless an item says otherwise.

| # | Measure | Parameter (default) |
| --- | --- | --- |
| 1 | Main PCB length and width | `pcb_l` (65.0), `pcb_w` (32.0) |
| 2 | Main PCB thickness | `pcb_t` (1.6) |
| 3 | Table to the main PCB bottom face, with the board standing on its feet | `foot_h` (3.5) |
| 4 | Foot / spacer width across the corners | `foot_d` (6.5) |
| 5 | Main PCB top face to the sub-board bottom face | `board_gap` (7.5) |
| 6 | Sub-board thickness | `sub_t` (1.6) |
| 7 | Sub-board top face to the top of the LCD glass | `lcd_t` (2.2) |
| 8 | Screw head diameter and height above the sub-board | `screw_head_d` (4.2), `screw_head_h` (1.6) |
| 9 | Centre of the lit LCD area, from the left edge and from the front edge | `lcd_cx` (33.2), `lcd_cy` (16.0) |
| 10 | Mounting-hole centres, from the left edge and the front edge | `hole_pos` (2.4 / 62.5, 1.95 / 30.0) |
| 11 | USB_HOST socket: width, height above PCB top, and how far it sticks out past the right PCB edge | `host_w` (13.2), `host_h` (6.0), `host_protrude` (10.2) |
| 12 | USB_DEV plug: gap under the plug above PCB top, and how far it sticks out past the left PCB edge | `dev_z0` (0.0), `dev_protrude` (15.3) |
| 13 | DEBUG port: Micro-USB or USB-C, its centre from the left edge, and its centre height above PCB top | `dbg_cx` (53.55), `dbg_cz` (1.5) |
| 14 | Each side button: centre from the left edge, actuator centre height above PCB top, and how far the actuator sticks out past the PCB edge | `buttons` (x values), `btn_z` (1.2), `btn_protrude` (0.5) |
| 15 | Battery switch lever: centre from the left edge, total travel, and height above PCB top | `sw_cx` (12.05), `sw_slot_w` (6.5), `sw_slot_h` (3.5) |
| 16 | microSD socket centre from the left edge, and the socket's top height above PCB top | `sd_cx` (24.15), `sd_open_h` (3.0) |
| 17 | Green and yellow LED centres from the left edge (LEDs are on the bottom face, at the front edge) | `leds_x` (27.0, 39.5) |

## Sources for the board numbers

- **[PCB]** Espressif PCB layout, `PCB_ESP32-S3_USB_OTG.pdf` (dl.espressif.com, linked
  from the user guide). The artwork is EV-BOARD V1.0 and carries 65.00 x 32.00 mm
  dimension lines.
  - What was read from it: the mounting holes, the USB pin rows, the switch, the
    Micro-USB shell legs, the button and LED footprints, the microSD shield tabs and
    the antenna notch.
  - How: read from the vector artwork at 0.1 mm per pixel, so expect ±0.2 mm.
- **[UG]** ESP32-S3-USB-OTG user guide (docs.espressif.com, esp-dev-kits).
  - USB_HOST is a USB-A female socket, and USB_DEV is a USB-A **male** plug.
  - The USB-to-UART (DEBUG) port is **Micro-USB**, not USB-C, on Espressif's board.
  - The green (GPIO15) and yellow (GPIO16) LEDs, a red charge LED, the battery switch
    and battery pads on the back, and a 1.3" ST7789 LCD on the SUB board.
- **[SUB]** `pic_sub.png` in esp-dev-kits `docs/_static/esp32-s3-usb-otg/`, scaled with
  the 28.1 mm hole pitch from [PCB]. This gives the LCD position, ±0.5 mm.
- **[STD]** Generic connector sizes: a USB-A plug is 12.0 x 4.5 mm, a microSD card is
  11 mm wide, and a 1.3" 240x240 panel has a 23.4 mm active area.
