/// Byte encoder and BLE write plan for the Phomemo M110 (issue #114).
///
/// Pure Dart: bytes in, bytes out, no Flutter, no BLE, no timers. The thin
/// BLE transport (`phomemo/ble/`) only executes the plan from
/// [planPhomemoM110Writes], so everything testable about the protocol lives
/// here.
///
/// None of this has been verified on an M110 yet. The byte sequence is the
/// one the reference implementations agree on; each command is a named
/// constant with its source so the bench session (Task 15 of the plan) can
/// correct one value at a time. References, researched 2026-10-31:
///
///  * vivier/phomemo-tools `2b76748`: `cups/filter/rastertopm110.py`.
///  * transcriptionstream/phomymo `1f58d3f`: `src/web/printer.js`, `ble.js`.
///  * Knightro63/phomemo `1c015d7`: the pub.dev package.
///  * Niko11111/SpoolmanScale `ee704a5`: `src/services/phomemo_m_series.cpp`
///    and `ble_service.cpp`, driving an M220.
///
/// One label is:
///
///     speed | density | media | raster header | raster rows | footer
///
/// There is no `ESC @` init: vivier removed it after testing on an M110.
library;

import 'dart:typed_data';

import '../label_bitmap.dart';

// --- BLE ids -------------------------------------------------------------

/// GATT service of the printer. Source: phomymo `src/web/constants.js`
/// (`BLE.SERVICE_UUID`) and SpoolmanScale `phomemo_m_series.h`
/// (`PHOMEMO_SERVICE_UUID`) agree.
const String kPhomemoServiceUuid = 'ff00';

/// Characteristic the print data is written to. Source: phomymo
/// `constants.js` (`BLE.WRITE_CHAR_UUID`) and SpoolmanScale
/// `phomemo_m_series.h` (`PHOMEMO_WRITE_UUID`) agree.
const String kPhomemoWriteUuid = 'ff02';

/// Characteristic status notifications arrive on. Source: phomymo
/// `constants.js` (`BLE.NOTIFY_CHAR_UUID`) and SpoolmanScale
/// `phomemo_m_series.h` (`PHOMEMO_STATUS_UUID`) agree.
const String kPhomemoNotifyUuid = 'ff03';

/// Advertised-name prefixes of Phomemo label printers. Only `Q199...` is
/// seen in the sources (phomymo `ble.js` notes an M110S advertising as
/// `Q199E...`); the others are a guess from the model names.
const List<String> kPhomemoNamePrefixes = ['Q199', 'M110', 'M120', 'M220'];

// --- Commands ------------------------------------------------------------

/// `ESC N 0D <speed>`: print speed. Source: vivier `select_speed`, phomymo
/// `printer.js` (`M110_CMD.SPEED`), SpoolmanScale `phomemo_m_series.cpp`
/// (`M110_SPEED`).
const List<int> kPhomemoSpeedCommand = [0x1B, 0x4E, 0x0D];

/// Default print speed. Range 1-5; every source sends 5.
const int kPhomemoDefaultSpeed = 5;

/// `ESC N 04 <density>`: print density. Source: vivier `select_density`,
/// phomymo `printer.js` (`M110_CMD.DENSITY`), SpoolmanScale (`M110_DENSITY`).
const List<int> kPhomemoDensityCommand = [0x1B, 0x4E, 0x04];

/// Default print density. Range up to 0x0F. vivier's filter and SpoolmanScale
/// send 10; phomymo's own default sends 0x0D.
const int kPhomemoDefaultDensity = 0x0A;

/// `US 11 <media>`: media type. Source: vivier `select_media_type`, phomymo
/// `printer.js` (`M110_CMD.MEDIA_TYPE`), SpoolmanScale (`M110_MEDIA`).
const List<int> kPhomemoMediaCommand = [0x1F, 0x11];

/// Media byte for labels with gaps. Source: vivier `print_header`
/// (`media_type = 10`), phomymo, SpoolmanScale. Other values seen: 0x0B
/// continuous, 0x26 black mark.
const int kPhomemoMediaGapLabel = 0x0A;

/// `GS v 0 00 <bytes per row, LE16> <rows, LE16>`, then the raster. Source:
/// vivier `print_raster`; the other three print sources send the same.
const List<int> kPhomemoRasterCommand = [0x1D, 0x76, 0x30, 0x00];

/// Sent after the raster of every label. Meaning undocumented in every
/// source. Source: vivier `print_footer`, phomymo `printer.js`
/// (`M110_CMD.FOOTER`), SpoolmanScale (`M110_FOOT_A` + `M110_FOOT_B`).
const List<int> kPhomemoFooter = [
  0x1F, 0xF0, 0x05, 0x00, //
  0x1F, 0xF0, 0x03, 0x00,
];

/// Status queries, answered on [kPhomemoNotifyUuid] (see
/// `phomemo_status.dart`). Source: phomymo `ble.js`.
const List<int> kPhomemoQueryPaper = [0x1F, 0x11, 0x11];
const List<int> kPhomemoQueryCover = [0x1F, 0x11, 0x12];
const List<int> kPhomemoQueryBattery = [0x1F, 0x11, 0x08];

// --- Pacing --------------------------------------------------------------
//
// Follows phomymo's pacing, with SpoolmanScale's 20 ms gap between chunks.

/// Raster bytes per BLE write. A transport on a small MTU passes less.
const int kPhomemoChunkSize = 128;

/// Pause after each header command and after the raster header.
const Duration kPhomemoCommandPause = Duration(milliseconds: 30);

/// Pause between raster chunks.
const Duration kPhomemoChunkPause = Duration(milliseconds: 20);

/// Pause after the last raster chunk, before the footer.
const Duration kPhomemoBeforeFooterPause = Duration(milliseconds: 300);

/// Pause after the footer.
const Duration kPhomemoAfterFooterPause = Duration(milliseconds: 500);

/// How long to wait for the printer's job-done notification, per copy.
/// Reaching the timeout counts as printed: the M110 may not send one.
const Duration kPhomemoDoneTimeout = Duration(seconds: 3);

/// Most copies one job prints; more is clamped.
const int kPhomemoMaxCopies = 9;

/// One BLE write in a print job.
class PhomemoWrite {
  const PhomemoWrite({required this.bytes, required this.pauseAfter});

  final Uint8List bytes;

  /// How long the transport waits after this write before the next one.
  final Duration pauseAfter;
}

/// Splits [data] into pieces of at most [chunkSize] bytes. Every piece but
/// the last is exactly [chunkSize] long, and the pieces concatenate back to
/// [data]. The pieces are copies.
List<Uint8List> chunkBytes(Uint8List data, int chunkSize) {
  if (chunkSize < 1) {
    throw ArgumentError.value(chunkSize, 'chunkSize', 'must be at least 1');
  }
  return [
    for (var i = 0; i < data.length; i += chunkSize)
      data.sublist(
        i,
        i + chunkSize < data.length ? i + chunkSize : data.length,
      ),
  ];
}

/// The BLE writes that print [copies] of [bitmap] on an M110, in order.
///
/// Per copy: three header commands (speed, density, media), the raster
/// header, the raster in [chunkSize] pieces, and the footer. Repeats the
/// whole sequence once per copy, as vivier does per page. [copies] is
/// clamped to 1-[kPhomemoMaxCopies].
///
/// Throws [ArgumentError] when [bitmap] is not [kLabelWidthDots] wide (the
/// M110 head is 48 bytes wide and the raster header says so) or has no rows
/// or more than 65535, when [density] or [speed] doesn't fit a byte, or when
/// [chunkSize] is shorter than the 8-byte footer, which is sent as one write.
List<PhomemoWrite> planPhomemoM110Writes(
  LabelBitmap bitmap, {
  int copies = 1,
  int density = kPhomemoDefaultDensity,
  int speed = kPhomemoDefaultSpeed,
  int chunkSize = kPhomemoChunkSize,
}) {
  if (bitmap.width != kLabelWidthDots) {
    throw ArgumentError.value(
      bitmap.width,
      'bitmap.width',
      'must be $kLabelWidthDots dots wide',
    );
  }
  if (bitmap.height < 1 || bitmap.height > 0xFFFF) {
    throw ArgumentError.value(
      bitmap.height,
      'bitmap.height',
      'must be 1-65535 rows',
    );
  }
  _checkByte(density, 'density');
  _checkByte(speed, 'speed');
  if (chunkSize < kPhomemoFooter.length) {
    throw ArgumentError.value(
      chunkSize,
      'chunkSize',
      'must be at least ${kPhomemoFooter.length}',
    );
  }

  final rasterHeader = [
    ...kPhomemoRasterCommand,
    bitmap.bytesPerRow & 0xFF,
    bitmap.bytesPerRow >> 8,
    bitmap.height & 0xFF,
    bitmap.height >> 8,
  ];
  final rasterChunks = chunkBytes(bitmap.bits, chunkSize);

  final oneLabel = <PhomemoWrite>[
    _write([...kPhomemoSpeedCommand, speed], kPhomemoCommandPause),
    _write([...kPhomemoDensityCommand, density], kPhomemoCommandPause),
    _write([
      ...kPhomemoMediaCommand,
      kPhomemoMediaGapLabel,
    ], kPhomemoCommandPause),
    _write(rasterHeader, kPhomemoCommandPause),
    for (var i = 0; i < rasterChunks.length; i++)
      PhomemoWrite(
        bytes: rasterChunks[i],
        pauseAfter: i == rasterChunks.length - 1
            ? kPhomemoBeforeFooterPause
            : kPhomemoChunkPause,
      ),
    _write(kPhomemoFooter, kPhomemoAfterFooterPause),
  ];

  final count = copies.clamp(1, kPhomemoMaxCopies).toInt();
  return [for (var c = 0; c < count; c++) ...oneLabel];
}

/// The bytes of a whole print job: [planPhomemoM110Writes] concatenated.
/// See there for what throws and how [copies] is treated.
Uint8List encodePhomemoM110Job(
  LabelBitmap bitmap, {
  int copies = 1,
  int density = kPhomemoDefaultDensity,
  int speed = kPhomemoDefaultSpeed,
}) {
  final out = BytesBuilder();
  for (final write in planPhomemoM110Writes(
    bitmap,
    copies: copies,
    density: density,
    speed: speed,
  )) {
    out.add(write.bytes);
  }
  return out.takeBytes();
}

PhomemoWrite _write(List<int> bytes, Duration pauseAfter) =>
    PhomemoWrite(bytes: Uint8List.fromList(bytes), pauseAfter: pauseAfter);

void _checkByte(int value, String name) {
  if (value < 0 || value > 0xFF) {
    throw ArgumentError.value(value, name, 'must fit in one byte (0-255)');
  }
}
