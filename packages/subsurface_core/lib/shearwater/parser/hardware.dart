/// Shearwater dive computer model identification.
///
/// Hardware ID → model mapping from libdivecomputer shearwater_common.c.
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

/// Map a hardware ID (from RDBI 0x8050) to a [ShearwaterModel].
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
