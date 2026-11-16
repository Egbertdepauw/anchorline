// SPDX-License-Identifier: LGPL-2.1-or-later
//
// Copyright (C) 2013 Jef Driesen (libdivecomputer)
// Copyright (C) 2026 Egbert de Pauw
//
// Translated to Dart from libdivecomputer's src/shearwater_common.c (the
// hardware ID to model table) and src/shearwater_common.h (the model
// numbers), and changed for Anchorline in 2026. Like the original, this
// file is free software under the GNU Lesser General Public License,
// version 2.1 or (at your option) any later version. See
// LICENSES/LGPL-2.1.txt and NOTICE.md.

/// Shearwater dive computer model identification.
///
/// Model number → model mapping from libdivecomputer shearwater_common.h,
/// and the older hardware ID → model mapping from shearwater_common.c.
library;

/// Shearwater dive computer models.
///
/// The [modelType] groups models by parser behavior:
/// predator (legacy format), petrel (PNF format), teric (PNF + timezone).
enum ShearwaterModel {
  predator(modelType: 2),
  petrel(modelType: 3),
  petrel2(modelType: 3),
  petrel3(modelType: 3),
  nerd(modelType: 3),
  nerd2(modelType: 3),
  perdix(modelType: 3),
  perdixAi(modelType: 3),
  perdix2(modelType: 3),
  teric(modelType: 8),
  peregrine(modelType: 3),
  peregrineTx(modelType: 3),
  tern(modelType: 3),
  unknown(modelType: 3);

  /// Parser model type: 2=Predator (legacy), 3=Petrel (PNF), 8=Teric (PNF+TZ).
  final int modelType;

  const ShearwaterModel({required this.modelType});

  /// Whether this model uses the Petrel parser (PNF-capable, 32-byte samples).
  bool get isPetrel => modelType != 2;

  /// Sample size in bytes.
  int get sampleSize => isPetrel ? 32 : 16;
}

/// Map a model number (from RDBI 0x8060) to a [ShearwaterModel].
///
/// The device reports the model numbers libdivecomputer uses
/// (`shearwater_common.h`, read directly since libdivecomputer
/// `f351434`). The Petrel and Petrel 2 share number 3, so [hardwareId]
/// (RDBI 0x8050) tells them apart: the original Petrel's hardware IDs
/// are in [modelFromHardware]'s table, and any other hardware ID with
/// number 3 is taken as a Petrel 2.
///
/// Number 14, the Perdix 3, uses a newer protocol variant Anchorline
/// doesn't support; it and any number not listed here map to
/// [ShearwaterModel.unknown].
ShearwaterModel modelFromNumber(int modelNumber, {required int hardwareId}) {
  return switch (modelNumber) {
    2 => ShearwaterModel.predator,
    3 => modelFromHardware(hardwareId) == ShearwaterModel.petrel
        ? ShearwaterModel.petrel
        : ShearwaterModel.petrel2,
    4 => ShearwaterModel.nerd,
    5 => ShearwaterModel.perdix,
    6 => ShearwaterModel.perdixAi,
    7 => ShearwaterModel.nerd2,
    8 => ShearwaterModel.teric,
    9 => ShearwaterModel.peregrine,
    10 => ShearwaterModel.petrel3,
    11 => ShearwaterModel.perdix2,
    12 => ShearwaterModel.tern, // Tern and Tern TX
    13 => ShearwaterModel.peregrineTx,
    _ => ShearwaterModel.unknown,
  };
}

/// Map a hardware ID (from RDBI 0x8050) to a [ShearwaterModel].
///
/// libdivecomputer dropped this table in `f351434` for the model number
/// ([modelFromNumber]), because new hardware IDs appear faster than the
/// table gets updated. Anchorline keeps it as the fallback for a device
/// that NAKs RDBI 0x8060, and to name a dive computer from the hardware
/// ID stored with it.
ShearwaterModel modelFromHardware(int hardwareId) {
  return switch (hardwareId) {
    0x0101 || 0x0202 => ShearwaterModel.predator,
    0x0404 || 0x0909 => ShearwaterModel.petrel,
    0x0505 ||
    0x0808 ||
    0x0838 ||
    0x08A5 ||
    0x0B0B ||
    0x7828 ||
    0x7B2C ||
    0x8838 =>
      ShearwaterModel.petrel2,
    0xB407 || 0xB429 => ShearwaterModel.petrel3,
    0x0606 || 0x0A0A => ShearwaterModel.nerd,
    0x0E0D || 0x7E2D => ShearwaterModel.nerd2,
    0x0707 => ShearwaterModel.perdix,
    0x0C0D || 0x425B || 0x7C2D || 0x8D6C => ShearwaterModel.perdixAi,
    0x704C || 0x924C || 0x9C64 || 0xC407 || 0xC429 || 0xC964 =>
      ShearwaterModel.perdix2,
    0x0F0F || 0x0F10 || 0x1F0A || 0x1F0F || 0x1F10 || 0x1F1A =>
      ShearwaterModel.teric,
    0x1512 || 0x1613 || 0x2623 || 0x63A5 => ShearwaterModel.peregrine,
    0x1712 || 0x813A => ShearwaterModel.peregrineTx,
    0xC0E0 => ShearwaterModel.tern,
    _ => ShearwaterModel.unknown,
  };
}
