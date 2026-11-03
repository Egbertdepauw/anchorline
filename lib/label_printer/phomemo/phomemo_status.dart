/// Parser for the Phomemo M110's status notifications (issue #114).
///
/// Pure Dart, no Flutter or BLE imports. The transport feeds every
/// notification on the notify characteristic to [parsePhomemoNotification].
///
/// `1A 0F 0C` (job done) has been seen on an M220, and the paper status on
/// an M110. The other values come from one source, written for a Q30, and
/// have not been checked on an M110. The bench session (Task 15 of the
/// issue #114 plan) corrects them one constant at a time.
library;

/// Something a Phomemo printer told us. The transport maps these to
/// `PrinterFault`s (see `label_printer.dart`); this layer only decodes.
enum PhomemoEvent { jobDone, noLabels, lowBattery }

/// Job finished printing (`1A 0F 0C`).
///
/// Source: Niko11111/SpoolmanScale `ee704a5`,
/// `src/services/phomemo_m_series.cpp` (`PHOMEMO_DONE`, awaited after the
/// last byte on an M220). Also decoded by transcriptionstream/phomymo
/// `1f58d3f`, `src/web/ble.js` (`case 0x0F`, "print status alt").
const List<int> kPhomemoNotifyJobDone = [0x1A, 0x0F, 0x0C];

/// Paper out (`1A 06 88`; any other `1A 06 xx` is paper ok).
///
/// Source: phomymo `1f58d3f`, `src/web/ble.js` (`case 0x06`), whose status
/// parser comes from yaddran/thermal-print `73dd564`. Written for a Q30.
/// Bench, 2026-11-03: an M110 sends `1A 06 89` with labels loaded and
/// `1A 06 88` with the cover open, so an open cover is reported as this.
const List<int> kPhomemoNotifyNoLabels = [0x1A, 0x06, 0x88];

/// Battery level 0 (`1A 04 A4`); other `1A 04 xx` values are other levels.
///
/// Source: phomymo `1f58d3f`, `src/web/ble.js` (`case 0x04`), from
/// yaddran/thermal-print `73dd564`. Not verified on an M110.
const List<int> kPhomemoNotifyLowBattery = [0x1A, 0x04, 0xA4];

// Deliberately not decoded:
//  * `1A 05 xx`: cover status. The Q30 source reads `1A 05 98` as cover
//    open, but an M110 sends `1A 05 98` with the cover closed (bench,
//    2026-11-03). An open cover is caught as paper out instead.
//  * `01 xx`: per-chunk acknowledgement seen on the M220. Ignored until the
//    bench shows whether the M110 sends it.
//  * `1A 03 xx`: "hot" status. No source says which value means overheated,
//    so PrinterFault.overheated stays unmapped until the bench records it.

/// Decodes one notification, or returns null when it isn't one we act on.
///
/// A notification matches when it starts with a known 3-byte status. Both
/// reference implementations read the status from the first bytes and
/// tolerate a longer payload, so bytes after the status are ignored. Shorter
/// and unknown payloads are ignored rather than guessed at.
PhomemoEvent? parsePhomemoNotification(List<int> bytes) {
  if (_startsWith(bytes, kPhomemoNotifyJobDone)) return PhomemoEvent.jobDone;
  if (_startsWith(bytes, kPhomemoNotifyNoLabels)) return PhomemoEvent.noLabels;
  if (_startsWith(bytes, kPhomemoNotifyLowBattery)) {
    return PhomemoEvent.lowBattery;
  }
  return null;
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}
