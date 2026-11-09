// Anchorline Bridge enclosure
// Two-part snap-fit case for the Espressif ESP32-S3-USB-OTG board (V1.1 layout)
// with its LCD sub-board (ESP32-S3-USB-OTG_SUB) stacked on top.
//
// Coordinate system (all numbers in mm):
//   origin  = lower-left corner of the MAIN PCB seen from the LCD side,
//             with the USB_DEV plug on the left and the USB_HOST socket on the right;
//   +x      = along the board, from USB_DEV (x = 0) to USB_HOST (x = pcb_l);
//   +y      = across the board, from the BOOT/DW-/UP+/Micro-USB edge (y = 0)
//             to the RST/MENU/microSD edge (y = pcb_w);
//   +z      = up, from the bottom face of the base (z = 0) towards the LCD.
//
// Sources for the board numbers:
//   [PCB]  Espressif PCB layout PDF, https://dl.espressif.com/dl/schematics/PCB_ESP32-S3_USB_OTG.pdf
//          (EV-BOARD V1.0 artwork, 65.00 x 32.00 mm dimension lines). Positions were read off the
//          vector artwork at 0.1 mm/pixel; expect +-0.2 mm.
//   [UG]   ESP32-S3-USB-OTG user guide, docs.espressif.com (esp-dev-kits) - connector types, LEDs.
//   [SUB]  esp-dev-kits docs/_static/esp32-s3-usb-otg/pic_sub.png (photo of the LCD sub-board),
//          scaled with the 28.1 mm mounting-hole pitch from [PCB]; expect +-0.5 mm.
//   [STD]  Generic connector standards / typical datasheets.
//   MEASURE = not published; a safe guess. Check it with a caliper on the real board (see README).
//
// Export:  openscad -D 'part="base"' -o bridge_enclosure_base.stl bridge_enclosure.scad
//          openscad -D 'part="lid"'  -o bridge_enclosure_lid.stl  bridge_enclosure.scad
// Parts:   "base", "lid" (both in print orientation), "assembly" (exploded, with board model),
//          "closed" (lid in place, with board model), "board", "clash" (board vs case overlap; must be empty).

part = "assembly";

/* ============================ BOARD: main PCB ============================ */
pcb_l   = 65.0;   // [PCB] dimension line
pcb_w   = 32.0;   // [PCB] dimension line
pcb_t   = 1.6;    // MEASURE (standard FR4; not published)

// Mounting holes (4x), centres. [PCB] pad centroids.
hole_pos = [[2.4, 1.95], [2.4, 30.0], [62.5, 1.95], [62.5, 30.0]];
// The stock kit stacks the boards with screws through octagonal spacers; the
// bottom spacers act as feet. The case keeps that hardware in place.
foot_h  = 3.5;    // MEASURE height of the bottom spacer (main PCB bottom face to the table)
foot_d  = 6.5;    // MEASURE spacer size across corners (the photos show it overhangs the PCB edge)
board_gap = 7.5;  // MEASURE main PCB top face -> LCD sub-board bottom face (top spacer length)
screw_head_d = 4.2; // MEASURE head diameter of the screws on top of the sub-board
screw_head_h = 1.6; // MEASURE head height above the sub-board

/* ============================ BOARD: LCD sub-board ======================== */
sub_t   = 1.6;    // MEASURE sub-board thickness
lcd_t   = 2.2;    // MEASURE sub-board top face -> top of the LCD glass
lcd_cx  = 33.2;   // [SUB] centre of the LCD active area, x   MEASURE
lcd_cy  = 16.0;   // [SUB] centre of the LCD active area, y   MEASURE
lcd_aa  = 23.4;   // [STD] 1.3" 240x240 ST7789 panel active area (square)
lcd_glass = 26.5; // [STD] typical 1.3" glass outline (board model only)

/* ============================ BOARD: connectors =========================== */
// USB_DEV: USB-A MALE plug on the x = 0 end, sitting on the main PCB top face. [UG][PCB]
dev_cy  = 16.0;   // [PCB] pin row centre
dev_w   = 12.0;   // [STD] USB-A plug shell width
dev_h   = 4.5;    // [STD] USB-A plug shell height
dev_z0  = 0.0;    // MEASURE gap between PCB top face and plug shell bottom
dev_protrude = 15.3; // [PCB] courtyard outline beyond the PCB edge   MEASURE

// USB_HOST: USB-A FEMALE socket on the x = pcb_l end (the analyzer plugs in here). [UG][PCB]
host_cy = 16.0;   // [PCB] pin row centre
host_w  = 13.2;   // [STD] receptacle shell width (outline in [PCB] is 13.0)   MEASURE
host_h  = 6.0;    // MEASURE receptacle height above the PCB top face
host_protrude = 10.2; // [PCB] courtyard outline beyond the PCB edge   MEASURE

// USB-to-UART (DEBUG) port on the y = 0 edge. Espressif's V1.1 has MICRO-USB [UG];
// some clones use USB-C. The opening below fits either cable's overmould.
dbg_cx  = 53.55;  // [PCB] shell-leg centre
dbg_cz  = 1.5;    // MEASURE port centre above the PCB top face
dbg_open_w = 11.0; // overmould clearance, width
dbg_open_h = 8.0;  // overmould clearance, height

// Battery slide switch on the y = 0 edge (lever sticks out past the PCB edge). [PCB]
sw_cx   = 12.05;  // [PCB] middle pin
sw_slot_w = 6.5;  // lever travel + lever width + clearance   MEASURE
sw_slot_h = 3.5;  // slot height above the PCB top face   MEASURE

// microSD push-push socket, card goes in through the y = pcb_w edge. [PCB]
sd_cx   = 24.15;  // [PCB] centre between the socket's two shield tabs (x 16.4 / 31.9)
sd_open_w = 13.0; // card is 11.0 wide [STD]
sd_open_h = 3.0;  // above the PCB top face   MEASURE (socket height ~1.8 [STD])

// Side-actuated buttons on the main PCB top face: [x, side, label]; side 0 = y = 0 edge, 1 = y = pcb_w edge.
// [PCB] centres of the 4-pad footprints. BOOT is the OK button (GPIO0).
buttons = [[10.40, 1, "RST"], [36.20, 1, "MENU"],
           [20.55, 0, "OK"],  [32.50, 0, "DW-"], [45.25, 0, "UP+"]];
btn_z   = 1.2;    // MEASURE actuator centre above the PCB top face
btn_protrude = 0.5; // MEASURE how far the actuator sticks out past the PCB edge

// Green (x 27.0) and yellow (x 39.5) LEDs: BOTTOM face of the main PCB, at the y = 0 edge. [PCB][UG]
leds_x  = [27.0, 39.5];
// (The red charge LED is mid-board on the bottom face; no battery is fitted, so it gets no window.)

/* ============================ CASE ======================================== */
clr      = 0.3;   // board-to-wall clearance
wall     = 2.0;   // long walls and the host-end wall
wall_dev = 2.5;   // USB_DEV end wall (thicker: carries two snap catches)
floor_t  = 2.0;
top_t    = 2.0;
corner_r = 2.5;   // outer vertical edge radius
foot_pocket = 0.6; // locating pockets for the feet in the floor
ceil_gap = 0.3;   // LCD glass -> lid ceiling
host_face_inset = 0.5; // case end sits this far behind the USB_HOST socket face

// Rim joint: the base carries an outer lip, the lid's inner wall skin drops inside it.
lip_t   = 1.0;
lip_h   = 1.5;
lip_clr = 0.15;

// Lid posts that press the sub-board down around the screw heads.
post_od  = 6.0;
post_gap = 0.0;   // + = gap above the sub-board, - = preload (interference)

// Flexible button tongues cut into the lid's long walls.
tongue_w   = 5.0;
tongue_len = 7.0;  // free end at the rim, hinge above
tongue_t   = 1.2;
slit       = 0.6;
nub_l      = 0.4;
btn_rest   = 0.15; // gap between nub and actuator at rest

// Snap fits (4): lid tabs drop into pockets on the outside of the base and click into a groove.
snap_d      = 1.2;  // pocket depth into the wall
snap_groove = 0.6;  // extra depth of the catch groove
snap_nub    = 0.5;  // nub height
snap_tip_z  = 1.0;  // tab tip height above the case bottom (pocket is open at the bottom for a screwdriver)
catch_z     = 2.6;  // groove bottom edge
catch_h     = 1.2;
snaps = [["W", 7.3, 4.0], ["W", pcb_w - 7.3, 4.0],
         ["S", pcb_l + clr + 2.8, 5.0], ["N", pcb_l + clr + 2.8, 5.0]];

// LCD window: open; the outer face has a recess for an optional clear plate.
win_size  = 24.0;  // opening (active area + margin)
win_r     = 1.0;
plate_size = 26.0; // recess for a 26 x 26 mm plate
plate_t    = 1.0;  // recess depth (set 0 to drop the recess)

lanyard_d = 2.8;   // cable-tie / lanyard tunnel through the base, across the host end

text_on    = true;
text_depth = 0.4;
font       = "Liberation Sans:style=Bold";

$fn = 48;

/* ============================ DERIVED ===================================== */
z_pcb_bot = floor_t - foot_pocket + foot_h;
z_pcb_top = z_pcb_bot + pcb_t;
z_split   = z_pcb_top;                 // base / lid parting plane
z_sub_bot = z_pcb_top + board_gap;
z_sub_top = z_sub_bot + sub_t;
z_lcd_top = z_sub_top + lcd_t;
z_ceil    = z_lcd_top + ceil_gap;
z_top     = z_ceil + top_t;

x_min = -clr - wall_dev;
x_max = pcb_l + host_protrude - host_face_inset;
y_min = -clr - wall;
y_max = pcb_w + clr + wall;

echo(str("Case outside: ", x_max - x_min, " x ", y_max - y_min, " x ", z_top, " mm"));
echo(str("z: pcb_bot ", z_pcb_bot, "  split ", z_split, "  sub_top ", z_sub_top, "  lcd_top ", z_lcd_top, "  top ", z_top));
echo(str("USB_DEV plug exposed beyond the case: ", dev_protrude - clr - wall_dev, " mm"));

// tongue geometry (depth t measured inward from the outer face)
t_act      = wall + clr - btn_protrude;          // actuator face
t_nub_in   = t_act - btn_rest;                   // nub tip
t_plate_in = t_nub_in - nub_l;                   // tongue inner face
t_plate_out = t_plate_in - tongue_t;             // tongue outer face
assert(t_plate_out >= 0, "Button actuators protrude too far: reduce tongue_t or nub_l");

/* ============================ HELPERS ===================================== */
module rrect(x0, y0, x1, y1, r) {
    translate([x0 + r, y0 + r]) offset(r = r) square([x1 - x0 - 2 * r, y1 - y0 - 2 * r]);
}
module outline() { rrect(x_min, y_min, x_max, y_max, corner_r); }

// Box addressed relative to one outer wall: a = along the wall, t = depth in from the outer face.
module wbox(side, a0, a1, t0, t1, z0, z1) {
    if (side == "S") translate([a0, y_min + t0, z0]) cube([a1 - a0, t1 - t0, z1 - z0]);
    if (side == "N") translate([a0, y_max - t1, z0]) cube([a1 - a0, t1 - t0, z1 - z0]);
    if (side == "W") translate([x_min + t0, a0, z0]) cube([t1 - t0, a1 - a0, z1 - z0]);
    if (side == "E") translate([x_max - t1, a0, z0]) cube([t1 - t0, a1 - a0, z1 - z0]);
}
function side_wall(s) = s == "W" ? wall_dev : wall;
function btn_side(b) = b[1] == 0 ? "S" : "N";

/* ============================ CAVITIES & CUTS ============================= */
module cavity_board(z0, z1) {
    translate([-clr, -clr, z0]) cube([pcb_l + 2 * clr, pcb_w + 2 * clr, z1 - z0]);
    for (h = hole_pos) translate([h[0], h[1], z0]) cylinder(d = foot_d + 2 * clr, h = z1 - z0);
}
module cavity_host(z0, z1) {   // room for the USB_HOST socket beyond the PCB end (lid only)
    translate([pcb_l, -clr, z0]) cube([x_max - wall - pcb_l, pcb_w + 2 * clr, z1 - z0]);
}

// Openings shared by base and lid. Everything opens onto the parting plane,
// so neither part needs bridges or supports.
module cuts() {
    zt = z_pcb_top;
    // USB_DEV plug
    wbox("W", dev_cy - dev_w / 2 - 0.4, dev_cy + dev_w / 2 + 0.4, -1, wall_dev + 0.05,
         zt + dev_z0 - 0.3, zt + dev_z0 + dev_h + 0.4);
    // USB_HOST socket (bottom edge sits on the base: the base supports the socket)
    wbox("E", host_cy - host_w / 2 - 0.3, host_cy + host_w / 2 + 0.3, -1, wall + 0.05,
         zt, zt + host_h + 0.3);
    // DEBUG (Micro-USB / USB-C) cable overmould
    wbox("S", dbg_cx - dbg_open_w / 2, dbg_cx + dbg_open_w / 2, -1, wall + 0.05,
         zt + dbg_cz - dbg_open_h / 2, zt + dbg_cz + dbg_open_h / 2);
    // battery switch lever
    wbox("S", sw_cx - sw_slot_w / 2, sw_cx + sw_slot_w / 2, -1, wall + 0.05, zt - 0.3, zt + sw_slot_h);
    // microSD: card slot plus a thumb scoop that thins the wall around it
    wbox("N", sd_cx - sd_open_w / 2, sd_cx + sd_open_w / 2, -1, wall + 0.05, zt - 0.3, zt + sd_open_h);
    wbox("N", sd_cx - sd_open_w / 2 - 1.5, sd_cx + sd_open_w / 2 + 1.5, -1, 1.2, zt - 2.5, zt + sd_open_h + 1.5);
    // LED windows below the PCB edge
    for (x = leds_x) wbox("S", x - 1.0, x + 1.0, -1, wall + 0.05, z_pcb_bot - 1.5, zt);
    // button tongue windows (the tongue itself is added back to the lid)
    for (b = buttons)
        wbox(btn_side(b), b[0] - tongue_w / 2 - slit, b[0] + tongue_w / 2 + slit, -1, wall + 0.05,
             zt - 0.01, zt + tongue_len);
}

/* ============================ BASE ======================================== */
module base_model() {
    difference() {
        union() {
            linear_extrude(z_split) outline();
            translate([0, 0, z_split]) linear_extrude(lip_h)
                difference() { outline(); offset(delta = -lip_t) outline(); }
        }
        cavity_board(floor_t, z_split + lip_h + 1);
        // locating pockets for the feet
        for (h = hole_pos) translate([h[0], h[1], floor_t - foot_pocket])
            cylinder(d = foot_d + 2 * clr, h = foot_pocket + 0.01);
        cuts();
        // snap pockets (open at the bottom for a screwdriver) and catch grooves
        for (s = snaps) {
            wbox(s[0], s[1] - s[2] / 2, s[1] + s[2] / 2, -1, snap_d, -1, z_split + lip_h + 1);
            wbox(s[0], s[1] - s[2] / 2, s[1] + s[2] / 2, snap_d - 0.01, snap_d + snap_groove,
                 catch_z, catch_z + catch_h);
        }
        // lanyard / cable-tie tunnel across the host end (teardrop: prints without support)
        translate([x_max - 1.4 - lanyard_d / 2, y_min - 1, floor_t + lanyard_d / 2 + 0.6])
            rotate([-90, 0, 0]) linear_extrude(y_max - y_min + 2)
                hull() { circle(d = lanyard_d); rotate(-45) square(lanyard_d / 2); }
        // text on the underside
        if (text_on) translate([pcb_l / 2, pcb_w / 2, -0.01]) linear_extrude(text_depth)
            mirror([1, 0, 0]) text("ANCHORLINE BRIDGE", size = 3.2, font = font, halign = "center", valign = "center");
    }
}

/* ============================ LID ========================================= */
module lid_model() {
    tab_in = snap_d - 0.15;
    difference() {
        union() {
            difference() {
                translate([0, 0, z_split]) linear_extrude(z_top - z_split) outline();
                // room for the base lip
                translate([0, 0, z_split - 0.01]) linear_extrude(lip_h + 0.01)
                    difference() { outline(); offset(delta = -(lip_t + lip_clr)) outline(); }
                cavity_board(z_split - 1, z_ceil);
                cavity_host(z_split - 1, z_ceil);
                cuts();
            }
            // posts pressing the sub-board down around the four screw heads
            for (h = hole_pos) translate([h[0], h[1], z_sub_top + post_gap])
                difference() {
                    cylinder(d = post_od, h = z_ceil - z_sub_top - post_gap + 0.01);
                    translate([0, 0, -0.01]) cylinder(d = screw_head_d + 0.6, h = screw_head_h + 0.3);
                }
            // button tongues: hinged at the top, free at the rim, with a nub facing the actuator
            for (b = buttons) {
                s = btn_side(b);
                wbox(s, b[0] - tongue_w / 2, b[0] + tongue_w / 2, t_plate_out, t_plate_in,
                     z_split + 0.4, z_split + tongue_len + 0.01);
                wbox(s, b[0] - 1.2, b[0] + 1.2, t_plate_in - 0.01, t_nub_in,
                     z_pcb_top + btn_z - 0.8, z_pcb_top + btn_z + 0.8);
            }
            // snap tabs
            for (s = snaps) {
                wbox(s[0], s[1] - s[2] / 2 + 0.2, s[1] + s[2] / 2 - 0.2, 0, tab_in,
                     snap_tip_z, z_split + lip_h + 0.01);
                hull() {
                    wbox(s[0], s[1] - s[2] / 2 + 0.5, s[1] + s[2] / 2 - 0.5, tab_in - 0.01, tab_in + snap_nub,
                         catch_z + 0.15, catch_z + catch_h - 0.15);
                    wbox(s[0], s[1] - s[2] / 2 + 0.5, s[1] + s[2] / 2 - 0.5, tab_in - 0.01, tab_in,
                         snap_tip_z, snap_tip_z + 0.01);
                }
            }
        }
        // LCD window and plate recess
        translate([lcd_cx, lcd_cy, z_ceil - 1]) linear_extrude(top_t + 2)
            rrect(-win_size / 2, -win_size / 2, win_size / 2, win_size / 2, win_r);
        if (plate_t > 0) translate([lcd_cx, lcd_cy, z_top - plate_t]) linear_extrude(plate_t + 1)
            rrect(-plate_size / 2 - 0.15, -plate_size / 2 - 0.15, plate_size / 2 + 0.15, plate_size / 2 + 0.15, 1.0);
        // debossed labels
        if (text_on) translate([0, 0, z_top - text_depth]) linear_extrude(text_depth + 1) {
            for (b = buttons) translate([b[0], b[1] == 0 ? 1.0 : pcb_w - 1.0])
                text(b[2], size = 2.4, font = font, halign = "center", valign = "center");
            translate([(lcd_cx + plate_size / 2 + x_max) / 2 - 2.6, lcd_cy]) rotate(90)
                text("ANCHORLINE", size = 3.4, font = font, halign = "center", valign = "center");
            translate([(lcd_cx + plate_size / 2 + x_max) / 2 + 2.6, lcd_cy]) rotate(90)
                text("BRIDGE", size = 3.4, font = font, halign = "center", valign = "center");
            translate([x_max - 2.6, lcd_cy]) rotate(90)
                text("ANALYZER", size = 1.8, font = font, halign = "center", valign = "center");
        }
    }
}

/* ============================ BOARD MODEL (fit check only) ================= */
module board_model() {
    zt = z_pcb_top;
    color("darkgreen") difference() {
        translate([0, 0, z_pcb_bot]) cube([pcb_l, pcb_w, pcb_t]);
        translate([41.7, 26.7, z_pcb_bot - 1]) cube([16.9, 6, pcb_t + 2]);  // antenna notch [PCB]
        for (h = hole_pos) translate([h[0], h[1], z_pcb_bot - 1]) cylinder(d = 2.2, h = pcb_t + 2);
    }
    color("dimgray") for (h = hole_pos) {
        translate([h[0], h[1], floor_t - foot_pocket]) cylinder(d = foot_d, h = foot_h, $fn = 8);
        translate([h[0], h[1], zt]) cylinder(d = foot_d, h = board_gap, $fn = 8);
        translate([h[0], h[1], z_sub_top]) cylinder(d = screw_head_d, h = screw_head_h);
    }
    color("black") translate([0, 0, z_sub_bot]) cube([pcb_l, pcb_w, sub_t]);
    color("royalblue") translate([lcd_cx - lcd_glass / 2, lcd_cy - lcd_glass / 2, z_sub_top]) cube([lcd_glass, lcd_glass, lcd_t]);
    color("silver") {
        translate([-dev_protrude, dev_cy - dev_w / 2, zt + dev_z0]) cube([dev_protrude + 4, dev_w, dev_h]);
        translate([pcb_l - 4, host_cy - host_w / 2, zt]) cube([host_protrude + 4, host_w, host_h]);
        translate([dbg_cx - 4, -0.3, zt]) cube([8, 5.5, 2.6]);                 // Micro-USB
        translate([sw_cx - 4.3, 0.5, zt]) cube([8.6, 3.5, 3.0]);               // switch body
        translate([sw_cx - 0.6, -2.0, zt + 0.8]) cube([1.2, 2.6, 1.5]);        // lever   MEASURE
        translate([sd_cx - 7, pcb_w - 14.5, zt]) cube([14, 14.5, 1.8]);        // microSD socket
    }
    color("white") for (b = buttons) {
        yb = b[1] == 0 ? 0 : pcb_w;
        dir = b[1] == 0 ? -1 : 1;
        translate([b[0] - 1.75, b[1] == 0 ? 0 : pcb_w - 3.5, zt]) cube([3.5, 3.5, 2.4]);
        translate([b[0] - 0.75, b[1] == 0 ? -btn_protrude : pcb_w, zt + btn_z - 0.6]) cube([1.5, btn_protrude, 1.2]);
    }
    color("yellow") for (x = leds_x) translate([x - 0.8, 0.1, z_pcb_bot - 0.6]) cube([1.6, 0.8, 0.6]);
}

/* ============================ OUTPUT ====================================== */
module lid_print() { translate([0, 0, z_top]) mirror([0, 0, 1]) lid_model(); }

if (part == "base") base_model();
else if (part == "lid") lid_print();
else if (part == "board") board_model();
else if (part == "closed") { color("gainsboro") base_model(); board_model(); color("steelblue") lid_model(); }
else if (part == "clash") {
    intersection() { board_model(); union() { base_model(); lid_model(); } }
}
else { // exploded assembly
    color("gainsboro") base_model();
    board_model();
    color("steelblue") translate([0, 0, 22]) lid_model();
}
