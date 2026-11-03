/// Shearwater protocol and dive log constants.
///
/// Ported from libdivecomputer shearwater_predator_parser.c and
/// shearwater_common.c. These are the canonical values from the
/// Shearwater binary format.
library;

// ── Record types (PNF format) ──────────────────────────────────

const int logRecordDiveSample = 0x01;
const int logRecordFreediveSample = 0x02;
const int logRecordAveloSample = 0x03;
const int logRecordOpening0 = 0x10;
const int logRecordOpening1 = 0x11;
const int logRecordOpening2 = 0x12;
const int logRecordOpening3 = 0x13;
const int logRecordOpening4 = 0x14;
const int logRecordOpening5 = 0x15;
const int logRecordOpening6 = 0x16;
const int logRecordOpening7 = 0x17;
const int logRecordOpening8 = 0x18;
const int logRecordOpening9 = 0x19;
const int logRecordClosing0 = 0x20;
const int logRecordClosing1 = 0x21;
const int logRecordClosing2 = 0x22;
const int logRecordClosing3 = 0x23;
const int logRecordClosing4 = 0x24;
const int logRecordClosing5 = 0x25;
const int logRecordClosing6 = 0x26;
const int logRecordClosing7 = 0x27;
const int logRecordClosing8 = 0x28;
const int logRecordClosing9 = 0x29;
const int logRecordInfoEvent = 0x30;
const int logRecordDiveSampleExt = 0xE1;
const int logRecordFinal = 0xFF;

const int infoEventTagLog = 38;

// ── Sample status flags ────────────────────────────────────────

const int statusGasSwitch = 0x01;
const int statusPpo2External = 0x02;
const int statusSetpointHigh = 0x04;
const int statusSc = 0x08;
const int statusOc = 0x10;

// ── Dive modes ─────────────────────────────────────────────────

enum DiveMode {
  cc(0), // Closed Circuit
  ocTec(1), // Open Circuit Technical
  gauge(2),
  ppo2(3),
  sc(4), // Semi-Closed
  cc2(5), // Closed Circuit variant 2
  ocRec(6), // Open Circuit Recreational
  freedive(7),
  avelo(12);

  final int value;
  const DiveMode(this.value);

  static DiveMode fromValue(int v) =>
      DiveMode.values.firstWhere((m) => m.value == v, orElse: () => ocTec);

  bool get isCcr => this == cc || this == cc2 || this == sc;
}

// ── Deco models ────────────────────────────────────────────────

enum DecoModel {
  gf(0), // Buhlmann with Gradient Factors
  vpmb(1),
  vpmbGfs(2),
  dciem(3);

  final int value;
  const DecoModel(this.value);

  static DecoModel fromValue(int v) =>
      DecoModel.values.firstWhere((m) => m.value == v, orElse: () => gf);
}

// ── Air integration modes ──────────────────────────────────────

const int aiOff = 0;
const int aiHpccr = 4;
const int aiOn = 5;
const int aiOnGps = 6;

// ── Units ──────────────────────────────────────────────────────

const int unitsMetric = 0;
const int unitsImperial = 1;

// ── Size constants ─────────────────────────────────────────────

const int szBlock = 0x80; // 128 bytes: legacy header/footer/final block
const int szSamplePredator = 0x10; // 16 bytes
const int szSamplePetrel = 0x20; // 32 bytes
const int szSampleFreedive = 0x08; // 8 bytes per sub-sample

// ── Limits ─────────────────────────────────────────────────────

const int maxGasMixes = 20;
const int fixedGasMixes = 10;
const int maxTanks = 6;
const int maxRecords = 10;

// ── Sentinel ───────────────────────────────────────────────────

const int undefined = 0xFFFFFFFF;

// ── RDBI IDs ───────────────────────────────────────────────────

const int idSerial = 0x8010;
const int idFirmware = 0x8011;
const int idHardware = 0x8050;
const int idLogUpload = 0x8021;
const int idTimeLocal = 0x9030;
const int idTimeUtc = 0x9031;
const int idUtcOffset = 0x9032;
const int idDstOffset = 0x9033;

// ── Manifest ───────────────────────────────────────────────────

const int manifestAddr = 0xE0000000;
const int manifestSize = 0x600; // 1536 bytes
const int manifestRecordSize = 0x20; // 32 bytes
const int manifestRecordCount = manifestSize ~/ manifestRecordSize; // 48
const int manifestHeaderValid = 0xA5C4;
const int manifestHeaderDeleted = 0x5A23;
