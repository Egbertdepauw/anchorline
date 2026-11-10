// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Copyright (C) 2012 Jef Driesen (libdivecomputer)
// Copyright (C) 2026 Egbert de Pauw
//
// Translated to Dart from libdivecomputer's src/shearwater_predator_parser.c
// and changed for Anchorline in 2026. Like the original, this file is free
// software under the GNU Lesser General Public License, version 2.1 or (at
// your option) any later version. See LICENSES/LGPL-2.1.txt and NOTICE.md.

/// Pure-Dart Shearwater dive log parser.
///
/// Faithfully ported from libdivecomputer's shearwater_predator_parser.c.
/// No Flutter, no BLE, no I/O — takes bytes, returns parsed structures.
library;

import 'dart:typed_data';

import 'byte_reader.dart';
import 'constants.dart';
import 'hardware.dart';
import 'parsed_dive.dart';

export 'parsed_dive.dart';

/// Result of parsing one dive from a buffer that may contain more.
///
/// Used by [ShearwaterDiveParser.parseOne] to support iterating through
/// a single-session multi-dive blob (the format a Shearwater Petrel
/// emits when you ask it to download the entire on-flash log in one
/// request — all dives end-to-end, terminated by the LRE end-marker
/// at the very end of the log, with each dive's on-flash 128-byte
/// alignment padding preserved between them).
class ParseResult {
  /// The dive that was parsed.
  final ParsedDive dive;

  /// Number of input bytes the parser consumed for this dive.
  ///
  /// In a concatenated multi-dive buffer, the next dive starts at
  /// `offset + bytesConsumed`.
  final int bytesConsumed;

  const ParseResult(this.dive, this.bytesConsumed);
}

/// Parser for Shearwater dive log binary blobs.
///
/// A blob is a decompressed dive record as stored in the dive computer's
/// flash memory. It contains opening records (header), sample records,
/// closing records (footer), and optionally a final record.
class ShearwaterDiveParser {
  final ShearwaterModel model;

  ShearwaterDiveParser({required this.model});

  /// Parse a decompressed dive blob into a [ParsedDive].
  ///
  /// Assumes [data] contains exactly one dive. For multi-dive buffers,
  /// use [parseOne] which returns the end offset.
  ParsedDive parse(Uint8List data) => parseOne(data).dive;

  /// Parse one dive starting at [offset] in [data].
  ///
  /// Returns the parsed dive plus the number of input bytes consumed,
  /// so callers can iterate through a concatenated multi-dive buffer:
  ///
  /// ```dart
  /// var off = 0;
  /// while (off < blob.length) {
  ///   final r = parser.parseOne(blob, offset: off);
  ///   handle(r.dive);
  ///   off += r.bytesConsumed;
  /// }
  /// ```
  ParseResult parseOne(Uint8List data, {int offset = 0}) {
    if (offset < 0 || offset >= data.length) {
      throw FormatException(
          'parseOne: offset $offset out of range (data.length=${data.length})');
    }
    final endOffset = _findDiveEnd(data, offset, model);
    final slice = (offset == 0 && endOffset == data.length)
        ? data
        : Uint8List.sublistView(data, offset, endOffset);
    final cache = _CacheResult.build(slice, model);
    final samples = _parseSamples(slice, cache);
    final events = _parseEvents(slice, cache);

    return ParseResult(
      ParsedDive(
        header: cache.header,
        footer: cache.footer,
        gasMixes: cache.gasMixes,
        tanks: cache.tanks,
        samples: samples,
        events: events,
        finalRecord: cache.finalRecord,
      ),
      endOffset - offset,
    );
  }
}

/// Locate the end offset of one dive starting at [startOffset] in [data].
///
/// A Shearwater dive blob on flash ends with:
///   - (PNF) a [logRecordFinal] 32-byte record followed by zero bytes
///     padding up to the next 128-byte flash alignment boundary;
///   - (legacy/Predator) a 128-byte footer block, optionally followed by
///     a 128-byte final block.
///
/// When the Petrel streams the entire on-flash log in one download
/// session, these per-dive ends sit back-to-back in the decompressed
/// stream. This function finds where one dive's bytes stop and the
/// next dive's bytes begin.
///
/// Falls back to `data.length` when no boundary marker is found (i.e.
/// the buffer holds exactly one dive without trailing pad — the case
/// when callers feed a per-dive blob from `parse()`).
int _findDiveEnd(Uint8List data, int startOffset, ShearwaterModel model) {
  if (model.isPetrel) {
    // PNF: scan 32-byte records for the [logRecordFinal] (0xFF) marker.
    // Once seen, round up past the final record and any trailing zero
    // records to the next 128-byte boundary — that's where the next
    // dive (or end-of-log) starts.
    final sampleSize = model.sampleSize; // 32 for PNF
    var off = startOffset;
    while (off + sampleSize <= data.length) {
      final type = data[off];
      if (type == logRecordFinal) {
        // End of this dive's structured records. Consume the final
        // record and any zero-block padding up to the next 128-byte
        // alignment boundary.
        var end = off + sampleSize;
        // Distance into the 128-byte block, relative to startOffset.
        final relEnd = end - startOffset;
        final padded = ((relEnd + szBlock - 1) ~/ szBlock) * szBlock;
        end = startOffset + padded;
        if (end > data.length) end = data.length;
        return end;
      }
      off += sampleSize;
    }
    // No final marker found — assume the slice IS one dive.
    return data.length;
  } else {
    // Legacy (Predator): flat 128-byte header + samples + 128-byte
    // footer, optionally followed by a 128-byte final block. There's
    // no per-dive end-marker we can scan for, so callers feeding a
    // legacy multi-dive buffer would need an explicit length. For
    // the single-dive case (the only one supported on legacy today)
    // the slice IS the dive.
    return data.length;
  }
}

// ── Cache pass (pass 1) ────────────────────────────────────────
// Scans all records to locate opening/closing/final offsets and
// extract gas mixes, tank info, dive mode, etc.

class _CacheResult {
  final DiveHeader header;
  final DiveFooter footer;
  final List<GasMix> gasMixes;
  final List<TankInfo> tanks;
  final FinalRecord? finalRecord;

  // Internal offsets for pass 2.
  final bool pnf;
  final int sampleSize;
  final int headerSize;
  final int footerSize;
  final List<int> opening; // offsets for opening[0..9]
  final List<int> closing; // offsets for closing[0..9]
  final int logVersion;
  final int aiMode;
  final bool isPetrel;
  final int calibrated;
  final List<double> calibration;
  final List<int> tankIdx; // maps raw tank index → compacted index

  _CacheResult({
    required this.header,
    required this.footer,
    required this.gasMixes,
    required this.tanks,
    required this.finalRecord,
    required this.pnf,
    required this.sampleSize,
    required this.headerSize,
    required this.footerSize,
    required this.opening,
    required this.closing,
    required this.logVersion,
    required this.aiMode,
    required this.isPetrel,
    required this.calibrated,
    required this.calibration,
    required this.tankIdx,
  });

  /// Build the cache by scanning all records in [data].
  factory _CacheResult.build(Uint8List data, ShearwaterModel model) {
    if (data.length < 2) {
      throw FormatException('Dive data too short: ${data.length} bytes');
    }

    final isPetrel = model.isPetrel;
    final sampleSize = model.sampleSize;

    // PNF detection: if first uint16 is NOT 0xFFFF, it's PNF.
    final pnf = isPetrel && uint16BE(data, 0) != 0xFFFF;
    var headerSize = 0;
    var footerSize = 0;
    var finalOffset = undefined;

    // Opening and closing record offsets.
    final opening = List.filled(maxRecords, undefined);
    final closing = List.filled(maxRecords, undefined);

    var logVersion = 0;

    if (!pnf) {
      // Legacy format: flat 128-byte header and footer blocks.
      headerSize = szBlock;
      footerSize = szBlock;
      if (data.length < headerSize + footerSize) {
        throw FormatException('Legacy dive data too short');
      }

      // Check for final block.
      if (isPetrel || uint16BE(data, data.length - footerSize) == 0xFFFD) {
        footerSize += szBlock;
        if (data.length < headerSize + footerSize) {
          throw FormatException('Legacy dive data too short for final block');
        }
        finalOffset = data.length - szBlock;
      }

      // In legacy format, all records point to the same offsets.
      for (var i = 0; i <= 4; i++) {
        opening[i] = 0;
        closing[i] = data.length - footerSize;
      }

      logVersion = data[127];
    }

    // ── Scan records ──

    var diveMode = DiveMode.ocTec;
    final gasmix = List.generate(maxGasMixes, (_) => _GasMixState());
    final tank = List.generate(maxTanks, (_) => _TankState());
    var ngasmixes = fixedGasMixes;
    var aiMode = aiOff;
    // hpccr is tracked for Teric serial fix and future HP CCR handling.
    // ignore: unused_local_variable
    var hpccr = false;
    var o2Prev = undefined;
    var hePrev = undefined;
    var dilPrev = undefined;

    // Load fixed gas mixes from legacy header.
    if (!pnf) {
      for (var i = 0; i < fixedGasMixes; i++) {
        gasmix[i].oxygen = data[20 + i];
        gasmix[i].helium = data[30 + i];
        gasmix[i].diluent = i >= 5;
        gasmix[i].enabled = true;
      }
    }

    var offset = headerSize;
    final length = data.length - footerSize;

    while (offset + sampleSize <= length) {
      // Skip empty samples.
      if (_isAllZero(data, offset, sampleSize)) {
        offset += sampleSize;
        continue;
      }

      final type = pnf ? data[offset] : logRecordDiveSample;
      final pnfOffset = pnf ? 1 : 0;

      if (type == logRecordDiveSample || type == logRecordAveloSample) {
        // Status flags and CCR detection.
        var status = 0;
        var ccr = false;
        if (type != logRecordAveloSample) {
          status = data[offset + 11 + pnfOffset];
          ccr = (status & statusOc) == 0;
        }
        if (ccr) {
          diveMode = (status & statusSc) != 0 ? DiveMode.sc : DiveMode.cc;
        }

        // Gas change detection.
        final o2 = data[offset + 7 + pnfOffset];
        final he = data[offset + 8 + pnfOffset];
        if ((o2 != o2Prev || he != hePrev || ccr != (dilPrev == 1)) &&
            (o2 != 0 || he != 0)) {
          var idx = 0;
          while (idx < ngasmixes) {
            if (o2 == gasmix[idx].oxygen &&
                he == gasmix[idx].helium &&
                ccr == gasmix[idx].diluent) {
              break;
            }
            idx++;
          }
          if (idx >= ngasmixes) {
            if (idx >= maxGasMixes) {
              throw FormatException('Maximum number of gas mixes reached');
            }
            gasmix[idx].oxygen = o2;
            gasmix[idx].helium = he;
            gasmix[idx].diluent = ccr;
            ngasmixes = idx + 1;
          }
          gasmix[idx].active = true;
          o2Prev = o2;
          hePrev = he;
          dilPrev = ccr ? 1 : 0;
        }

        // Tank pressure (log version >= 7).
        if (logVersion >= 7) {
          const idx = [27, 19];
          final count = type == logRecordAveloSample ? 1 : 2;
          for (var i = 0; i < count; i++) {
            var pressure = uint16BE(data, offset + pnfOffset + idx[i]);
            final id = (aiMode == aiHpccr ? 4 : 0) + i;
            if (pressure < 0xFFF0) {
              pressure &= 0x0FFF;
              if (pressure != 0) {
                if (!tank[id].active) {
                  tank[id].active = true;
                  tank[id].beginPressure = pressure;
                  tank[id].endPressure = pressure;
                }
                tank[id].endPressure = pressure;
              }
            }
          }
        }
      } else if (type == logRecordDiveSampleExt) {
        // Extended tank pressures (log version >= 13).
        if (logVersion >= 13) {
          for (var i = 0; i < 2; i++) {
            var pressure = uint16BE(data, offset + pnfOffset + i * 2);
            final id = 2 + i;
            if (pressure < 0xFFF0) {
              pressure &= 0x0FFF;
              if (pressure != 0) {
                if (!tank[id].active) {
                  tank[id].active = true;
                  tank[id].beginPressure = pressure;
                  tank[id].endPressure = pressure;
                }
                tank[id].endPressure = pressure;
              }
            }
          }
        }
        // HP CCR tank pressures (log version >= 14).
        if (logVersion >= 14) {
          for (var i = 0; i < 2; i++) {
            final pressure = uint16BE(data, offset + pnfOffset + 4 + i * 2);
            final id = 4 + i;
            if (pressure != 0) {
              if (!tank[id].active) {
                tank[id].active = true;
                tank[id].enabled = true;
                tank[id].beginPressure = pressure;
                tank[id].endPressure = pressure;
                tank[id].usage = i == 0 ? TankUsage.diluent : TankUsage.oxygen;
                hpccr = true;
              }
              tank[id].endPressure = pressure;
            }
          }
        }
      } else if (type == logRecordFreediveSample) {
        diveMode = DiveMode.freedive;
      } else if (type >= logRecordOpening0 && type <= logRecordOpening9) {
        final recordIdx = type - logRecordOpening0;
        opening[recordIdx] = offset;

        if (type == logRecordOpening0) {
          for (var i = 0; i < fixedGasMixes; i++) {
            gasmix[i].oxygen = data[offset + 20 + i];
            gasmix[i].diluent = i >= 5;
          }
          for (var i = 0; i < 2; i++) {
            gasmix[i].helium = data[offset + 30 + i];
          }
        } else if (type == logRecordOpening1) {
          for (var i = 2; i < fixedGasMixes; i++) {
            gasmix[i].helium = data[offset + 1 + i - 2];
          }
        } else if (type == logRecordOpening4) {
          logVersion = data[offset + 16];

          if (logVersion >= 7) {
            aiMode = data[offset + 28];
            if (logVersion < 13) {
              if (aiMode == 1 || aiMode == 2) {
                tank[aiMode - 1].enabled = true;
              } else if (aiMode == 3) {
                tank[0].enabled = true;
                tank[1].enabled = true;
              }
            }
            if (logVersion < 14) {
              if (aiMode == aiHpccr) {
                for (var i = 0; i < 2; i++) {
                  tank[4 + i].enabled = true;
                  tank[4 + i].usage =
                      i == 0 ? TankUsage.diluent : TankUsage.oxygen;
                }
                hpccr = true;
              }
            }
          }

          // Gas mix on/off state.
          final state = uint16BE(data, offset + 17);
          for (var i = 0; i < fixedGasMixes; i++) {
            gasmix[i].enabled = (state & (1 << i)) != 0;
          }

          final gtrMode = data[offset + 29];
          if (_popcount(gtrMode) >= 2) {
            for (var i = 0; i < 4; i++) {
              if (gtrMode & (1 << i) != 0) {
                tank[i].usage = TankUsage.sidemount;
              }
            }
          }
        } else if (type == logRecordOpening5) {
          if (logVersion >= 9) {
            tank[0].serial = _bcd2dec(data, offset + 1, 3);
            tank[0].pressureMax = uint16BE(data, offset + 6);
            tank[0].pressureReserve = uint16BE(data, offset + 8);
            tank[1].serial = _bcd2dec(data, offset + 10, 3);
            tank[1].pressureMax = uint16BE(data, offset + 15);
            tank[1].pressureReserve = uint16BE(data, offset + 17);
          }
        } else if (type == logRecordOpening6) {
          if (logVersion >= 13) {
            tank[0].enabled = data[offset + 19] != 0;
            tank[0].name = String.fromCharCodes(data.sublist(offset + 20, offset + 22));
            tank[1].enabled = data[offset + 22] != 0;
            tank[1].name = String.fromCharCodes(data.sublist(offset + 23, offset + 25));
            tank[2].serial = _bcd2dec(data, offset + 25, 3);
            tank[2].pressureMax = uint16BE(data, offset + 28);
            tank[2].pressureReserve = uint16BE(data, offset + 30);
          }
        } else if (type == logRecordOpening7) {
          if (logVersion >= 13) {
            tank[2].enabled = data[offset + 1] != 0;
            tank[2].name = String.fromCharCodes(data.sublist(offset + 2, offset + 4));
            tank[3].serial = _bcd2dec(data, offset + 4, 3);
            tank[3].pressureMax = uint16BE(data, offset + 7);
            tank[3].pressureReserve = uint16BE(data, offset + 9);
            tank[3].enabled = data[offset + 11] != 0;
            tank[3].name = String.fromCharCodes(data.sublist(offset + 12, offset + 14));
          }
        }
      } else if (type >= logRecordClosing0 && type <= logRecordClosing9) {
        closing[type - logRecordClosing0] = offset;
      } else if (type == logRecordFinal) {
        finalOffset = offset;
      }

      offset += sampleSize;
    }

    // Verify required opening/closing records (0-4).
    for (var i = 0; i <= 4; i++) {
      if (opening[i] == undefined || closing[i] == undefined) {
        throw FormatException(
            'Missing opening or closing record $i');
      }
    }

    // ── Sensor calibration ──
    final calibration = List<double>.filled(3, 0.0);
    var calibrated = 0;
    final calBase = opening[3] + (pnf ? 6 : 86);
    var nSensors = 0;
    var nDefaults = 0;
    for (var i = 0; i < 3; i++) {
      final calRaw = uint16BE(data, calBase + 1 + i * 2);
      calibration[i] = calRaw / 100000.0;
      if (model == ShearwaterModel.predator) {
        calibration[i] *= 2.2;
      }
      if (data[calBase] & (1 << i) != 0) {
        if (calRaw == 2100) nDefaults++;
        nSensors++;
      }
    }
    if (nSensors > 0 && nSensors == nDefaults) {
      calibrated = 0; // All at factory default — disable
    } else {
      calibrated = data[calBase];
    }

    // ── Dive mode from header (log version >= 8) ──
    if (logVersion >= 8) {
      diveMode = DiveMode.fromValue(
          data[opening[4] + (pnf ? 1 : 112)]);
    }

    // ── Final record: update model ──
    FinalRecord? finalRecord;
    var effectiveModel = model;
    if (finalOffset != undefined) {
      finalRecord = FinalRecord(
        model: data[finalOffset + 13],
        serial: uint32BE(data, finalOffset + 2),
        firmware: _bcd2dec(data, finalOffset + 10, 1),
        raw: data.sublist(finalOffset, finalOffset + sampleSize),
      );
      // Could update model here if needed based on finalRecord.model
    }

    // ── Fix Teric tank serial ──
    if (effectiveModel == ShearwaterModel.teric) {
      for (var i = 0; i < maxTanks; i++) {
        final s = tank[i].serial;
        tank[i].serial = ((s ~/ 10000) % 100) +
            ((s ~/ 100) % 100) * 100 +
            (s % 100) * 10000;
      }
    }

    // ── Build final gas mix list ──
    final gasMixes = <GasMix>[];
    if (diveMode != DiveMode.freedive) {
      for (var i = 0; i < ngasmixes; i++) {
        if (gasmix[i].oxygen == 0 && gasmix[i].helium == 0) continue;
        if (!gasmix[i].enabled && !gasmix[i].active) continue;
        if (gasmix[i].diluent && !diveMode.isCcr) continue;
        gasMixes.add(GasMix(
          oxygenPercent: gasmix[i].oxygen,
          heliumPercent: gasmix[i].helium,
          isDiluent: gasmix[i].diluent,
        ));
      }
    }

    // ── Build tank list ──
    final tankIdx = List.filled(maxTanks, undefined);
    final tanks = <TankInfo>[];
    for (var i = 0; i < maxTanks; i++) {
      if (tank[i].active) {
        tankIdx[i] = tanks.length;
        tanks.add(TankInfo(
          beginPressureRaw: tank[i].beginPressure,
          endPressureRaw: tank[i].endPressure,
          serial: tank[i].serial,
          pressureMax: tank[i].pressureMax,
          pressureReserve: tank[i].pressureReserve,
          name: tank[i].name,
          usage: tank[i].usage,
        ));
      }
    }

    // ── Header ──
    final gfIdx = pnf ? opening[0] + 4 : 4;
    final decoModelIdx = pnf ? opening[2] + 18 : 67;
    final decoModelCode = data[decoModelIdx];
    final decoModel = DecoModel.fromValue(decoModelCode);

    var vpmbConservatism = 0;
    if (decoModel == DecoModel.vpmb || decoModel == DecoModel.vpmbGfs) {
      vpmbConservatism = data[decoModelIdx + 1];
    }

    var sampleIntervalMs = 10000;
    if (pnf && logVersion >= 9 && opening[5] != undefined) {
      sampleIntervalMs = uint16BE(data, opening[5] + 23);
    }

    // ── Scrubber stack time (logVersion >= 11, opening[6] / closing[6]) ──
    int? configuredStackSeconds;
    int? stackRemainingAtStartSeconds;
    int? stackRemainingAtEndSeconds;
    if (logVersion >= 11 && opening[6] != undefined) {
      final cfg = uint16BE(data, opening[6] + 1);
      if (cfg != 0) {
        configuredStackSeconds = cfg;
        stackRemainingAtStartSeconds = uint16BE(data, opening[6] + 3);
        if (closing[6] != undefined) {
          stackRemainingAtEndSeconds = uint16BE(data, closing[6] + 3);
        }
      }
    }

    final header = DiveHeader(
      startTimestamp: uint32BE(data, opening[0] + (pnf ? 12 : 12)),
      diveMode: diveMode,
      decoModel: decoModel,
      gfLow: data[gfIdx],
      gfHigh: data[gfIdx + 1],
      vpmbConservatism: vpmbConservatism,
      sampleIntervalMs: sampleIntervalMs,
      logVersion: logVersion,
      units: data[opening[0] + 8],
      sensorCalibration: calibration,
      calibratedSensorMask: calibrated,
      aiMode: aiMode,
      atmosphericPressureMbar:
          uint16BE(data, opening[1] + (pnf ? 16 : 47)),
      waterDensity: uint16BE(data, opening[3] + (pnf ? 3 : 83)),
      isPnf: pnf,
      configuredStackSeconds: configuredStackSeconds,
      stackRemainingAtStartSeconds: stackRemainingAtStartSeconds,
      stackRemainingAtEndSeconds: stackRemainingAtEndSeconds,
    );

    // ── Footer ──
    int diveTimeSeconds;
    if (pnf) {
      diveTimeSeconds = uint24BE(data, closing[0] + 6);
    } else {
      diveTimeSeconds = uint16BE(data, closing[0] + 6) * 60;
    }

    final footer = DiveFooter(
      maxDepthRaw: uint16BE(data, closing[0] + 4),
      diveTimeSeconds: diveTimeSeconds,
    );

    return _CacheResult(
      header: header,
      footer: footer,
      gasMixes: gasMixes,
      tanks: tanks,
      finalRecord: finalRecord,
      pnf: pnf,
      sampleSize: sampleSize,
      headerSize: headerSize,
      footerSize: footerSize,
      opening: opening,
      closing: closing,
      logVersion: logVersion,
      aiMode: aiMode,
      isPetrel: isPetrel,
      calibrated: calibrated,
      calibration: calibration,
      tankIdx: tankIdx,
    );
  }
}

// ── Sample parsing (pass 2) ────────────────────────────────────

List<DiveSample> _parseSamples(Uint8List data, _CacheResult cache) {
  final samples = <DiveSample>[];
  final pnf = cache.pnf;
  final pnfOffset = pnf ? 1 : 0;
  var time = 0;
  final interval = cache.header.sampleIntervalMs;

  var offset = cache.headerSize;
  final length = data.length - cache.footerSize;

  while (offset + cache.sampleSize <= length) {
    if (_isAllZero(data, offset, cache.sampleSize)) {
      offset += cache.sampleSize;
      continue;
    }

    final type = pnf ? data[offset] : logRecordDiveSample;

    if (type == logRecordDiveSample || type == logRecordAveloSample) {
      time += interval;

      final status =
          type != logRecordAveloSample ? data[offset + 11 + pnfOffset] : 0;
      final ccr = (status & statusOc) == 0 && type != logRecordAveloSample;

      // Tank pressures
      final tankPressures = <TankPressureReading>[];
      if (cache.logVersion >= 7) {
        const pressureOffsets = [27, 19];
        final count = type == logRecordAveloSample ? 1 : 2;
        for (var i = 0; i < count; i++) {
          final raw = uint16BE(data, offset + pnfOffset + pressureOffsets[i]);
          final id = (cache.aiMode == aiHpccr ? 4 : 0) + i;
          if (raw < 0xFFF0) {
            final pressure = raw & 0x0FFF;
            if (pressure != 0 && cache.tankIdx[id] != undefined) {
              tankPressures.add(TankPressureReading(
                tankIndex: cache.tankIdx[id],
                pressureRaw: pressure,
                batteryLevel: raw >> 12,
              ));
            }
          }
        }
      }

      samples.add(DiveSample(
        timeMs: time,
        depthRaw: uint16BE(data, offset + pnfOffset),
        temperatureRaw: int8(data, offset + pnfOffset + 13),
        statusFlags: status,
        ppo2Raw: ccr ? data[offset + pnfOffset + 6] : 0,
        cellMv0: ccr ? data[offset + pnfOffset + 12] : 0,
        cellMv1: ccr ? data[offset + pnfOffset + 14] : 0,
        cellMv2: ccr ? data[offset + pnfOffset + 15] : 0,
        setpointRaw: ccr && cache.isPetrel
            ? data[offset + pnfOffset + 18]
            : 0,
        cnsRaw: cache.isPetrel ? data[offset + pnfOffset + 22] : 0,
        o2Percent: data[offset + pnfOffset + 7],
        hePercent: data[offset + pnfOffset + 8],
        decoStopDepthRaw: uint16BE(data, offset + pnfOffset + 2),
        ndlOrDecoTimeMinutes: data[offset + pnfOffset + 9],
        ttsMinutes: uint16BE(data, offset + pnfOffset + 4),
        rbt: cache.logVersion >= 7 ? data[offset + pnfOffset + 21] : 0,
        tankPressures: tankPressures,
      ));
    } else if (type == logRecordDiveSampleExt) {
      // Extended tank pressures — attach to previous sample if exists.
      if (samples.isNotEmpty && cache.logVersion >= 13) {
        final extPressures = <TankPressureReading>[];
        for (var i = 0; i < 2; i++) {
          final raw = uint16BE(data, offset + pnfOffset + i * 2);
          final id = 2 + i;
          if (raw < 0xFFF0) {
            final pressure = raw & 0x0FFF;
            if (pressure != 0 && cache.tankIdx[id] != undefined) {
              extPressures.add(TankPressureReading(
                tankIndex: cache.tankIdx[id],
                pressureRaw: pressure,
                batteryLevel: raw >> 12,
              ));
            }
          }
        }
        if (cache.logVersion >= 14) {
          for (var i = 0; i < 2; i++) {
            final pressure = uint16BE(data, offset + pnfOffset + 4 + i * 2);
            final id = 4 + i;
            if (pressure != 0 && cache.tankIdx[id] != undefined) {
              extPressures.add(TankPressureReading(
                tankIndex: cache.tankIdx[id],
                pressureRaw: pressure,
                batteryLevel: 0,
              ));
            }
          }
        }
        if (extPressures.isNotEmpty) {
          // Replace last sample with extended tank pressures.
          final prev = samples.last;
          samples[samples.length - 1] = DiveSample(
            timeMs: prev.timeMs,
            depthRaw: prev.depthRaw,
            temperatureRaw: prev.temperatureRaw,
            statusFlags: prev.statusFlags,
            ppo2Raw: prev.ppo2Raw,
            cellMv0: prev.cellMv0,
            cellMv1: prev.cellMv1,
            cellMv2: prev.cellMv2,
            setpointRaw: prev.setpointRaw,
            cnsRaw: prev.cnsRaw,
            o2Percent: prev.o2Percent,
            hePercent: prev.hePercent,
            decoStopDepthRaw: prev.decoStopDepthRaw,
            ndlOrDecoTimeMinutes: prev.ndlOrDecoTimeMinutes,
            ttsMinutes: prev.ttsMinutes,
            rbt: prev.rbt,
            tankPressures: [...prev.tankPressures, ...extPressures],
          );
        }
      }
    } else if (type == logRecordFreediveSample) {
      // 4 sub-samples packed in one 32-byte record.
      for (var i = 0; i < 4; i++) {
        final subOffset = offset + i * szSampleFreedive;
        if (_isAllZero(data, subOffset, szSampleFreedive)) break;

        time += interval;
        samples.add(DiveSample(
          timeMs: time,
          depthRaw: uint16BE(data, subOffset + 1), // absolute pressure mbar
          temperatureRaw: int8(data, subOffset + 3), // simplified
          o2Percent: 0,
          hePercent: 0,
        ));
      }
    }
    // Other record types (opening, closing, final, info_event) are
    // skipped in sample iteration — they were handled in the cache pass.

    offset += cache.sampleSize;
  }

  return samples;
}

// ── Event parsing ──────────────────────────────────────────────

List<DiveEvent> _parseEvents(Uint8List data, _CacheResult cache) {
  final events = <DiveEvent>[];
  final pnf = cache.pnf;

  var time = 0;
  final interval = cache.header.sampleIntervalMs;

  var offset = cache.headerSize;
  final length = data.length - cache.footerSize;

  while (offset + cache.sampleSize <= length) {
    if (_isAllZero(data, offset, cache.sampleSize)) {
      offset += cache.sampleSize;
      continue;
    }

    final type = pnf ? data[offset] : logRecordDiveSample;

    if (type == logRecordDiveSample || type == logRecordAveloSample) {
      time += interval;
    } else if (type == logRecordFreediveSample) {
      for (var i = 0; i < 4; i++) {
        final subOffset = offset + i * szSampleFreedive;
        if (_isAllZero(data, subOffset, szSampleFreedive)) break;
        time += interval;
      }
    } else if (type == logRecordInfoEvent) {
      final event = data[offset + 1];
      final w1 = uint32BE(data, offset + 8);
      final w2 = uint32BE(data, offset + 12);

      if (event == infoEventTagLog) {
        events.add(DiveEvent(
          timeMs: time,
          type: DiveEventType.bookmark,
          bearing: w1 != 0xFFFFFFFF ? w1 : null,
          value: w2,
        ));
      }
    }

    offset += cache.sampleSize;
  }

  return events;
}

// ── Utility functions ──────────────────────────────────────────

// ── Mutable state classes for cache pass ───────────────────────

class _GasMixState {
  int oxygen = 0;
  int helium = 0;
  bool diluent = false;
  bool enabled = false;
  bool active = false;
}

class _TankState {
  bool active = false;
  bool enabled = false;
  int beginPressure = 0;
  int endPressure = 0;
  int serial = 0;
  int pressureMax = 0;
  int pressureReserve = 0;
  String name = '';
  TankUsage usage = TankUsage.none;
}

bool _isAllZero(Uint8List data, int offset, int length) {
  for (var i = 0; i < length; i++) {
    if (data[offset + i] != 0) return false;
  }
  return true;
}

int _popcount(int v) {
  var count = 0;
  while (v != 0) {
    count += v & 1;
    v >>= 1;
  }
  return count;
}

int _bcd2dec(Uint8List data, int offset, int length) {
  var result = 0;
  for (var i = 0; i < length; i++) {
    final byte = data[offset + i];
    result = result * 100 + (byte >> 4) * 10 + (byte & 0x0F);
  }
  return result;
}
