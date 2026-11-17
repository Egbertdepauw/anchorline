// Global message numbers and field numbers of the FIT messages a dive file
// is read from. Units are noted per field; values stay raw here.

/// Global message numbers.
class FitMesg {
  static const deviceSettings = 2;
  static const sport = 12;
  static const session = 18;
  static const record = 20;
  static const event = 21;
  static const deviceInfo = 23;
  static const activity = 34;
  static const sensorProfile = 147;
  static const diveSettings = 258;
  static const diveGas = 259;
  static const diveSummary = 268;
  static const tankUpdate = 319;
  static const tankSummary = 323;
  static const fileId = 0;

  const FitMesg._();
}

/// Field present on every timestamped message.
const fitTimestampField = 253;

/// File id (0).
class FitFileIdField {
  /// 4 is an activity file.
  static const type = 0;
  static const manufacturer = 1;
  static const product = 2;
  static const serial = 3;
  static const timeCreated = 4;
  static const productName = 8;

  const FitFileIdField._();
}

const fitFileTypeActivity = 4;

/// Device settings (2).
class FitDeviceSettings {
  /// Seconds to add to UTC for local time. Stored as uint32 but signed.
  static const utcOffset = 1;
  static const timeOffset = 2;

  const FitDeviceSettings._();
}

/// Sport (12).
class FitSport {
  static const sport = 0;
  static const subSport = 1;

  const FitSport._();
}

/// Sport and sub-sport numbers for diving.
class FitSportKind {
  static const diving = 53;
  static const singleGas = 53;
  static const multiGas = 54;
  static const gauge = 55;
  static const apnea = 56;
  static const apneaHunting = 57;
  static const ccr = 63;

  const FitSportKind._();
}

/// Session (18).
class FitSession {
  static const startTime = 2;
  static const sport = 5;
  static const subSport = 6;

  /// Milliseconds.
  static const totalElapsedTime = 7;

  const FitSession._();
}

/// Record (20).
class FitRecord {
  /// Degrees Celsius (sint8).
  static const temperature = 13;

  /// Millimetres.
  static const depth = 92;

  /// Millimetres.
  static const nextStopDepth = 93;

  /// Seconds.
  static const nextStopTime = 94;

  /// Time to surface, seconds.
  static const timeToSurface = 95;

  /// No-decompression limit, seconds.
  static const ndl = 96;

  /// Percent.
  static const cnsLoad = 97;

  const FitRecord._();
}

/// Event (21).
class FitEvent {
  static const event = 0;
  static const type = 1;
  static const data = 3;
  static const group = 4;

  /// `event` value for a dive alert; `data` is a [FitDiveAlert].
  static const diveAlertEvent = 56;

  /// `event` value for a gas switch; `data` is the gas index.
  static const gasSwitchEvent = 57;

  const FitEvent._();
}

/// Dive alert codes (event 56 data).
class FitDiveAlert {
  static const decoRequired = 0;
  static const gasSwitchPrompted = 1;
  static const surface = 2;
  static const approachingNdl = 3;
  static const ppo2Warning = 4;
  static const ppo2CriticalHigh = 5;
  static const ppo2CriticalLow = 6;
  static const timeAlert = 7;
  static const depthAlert = 8;
  static const decoCeilingBroken = 9;
  static const decoCompleted = 10;
  static const safetyStopCeilingBroken = 11;
  static const safetyStopCompleted = 12;
  static const cnsWarning = 13;
  static const cnsCritical = 14;
  static const otuWarning = 15;
  static const otuCritical = 16;
  static const ascentSpeedCritical = 17;
  static const alertDismissed = 18;
  static const alertTimedOut = 19;
  static const batteryLow = 20;
  static const batteryCritical = 21;
  static const safetyStopBegin = 22;
  static const approachingDecoStop = 23;
  static const autoSwitchToLowSetpoint = 24;
  static const autoSwitchToHighSetpoint = 25;
  static const manualSwitchToLowSetpoint = 26;
  static const manualSwitchToHighSetpoint = 27;
  static const tankBatteryLow = 32;

  const FitDiveAlert._();
}

/// Device info (23).
class FitDeviceInfo {
  /// 0 is the main device.
  static const deviceIndex = 0;
  static const serial = 3;
  static const product = 4;

  /// Software version, hundredths (1600 is 16.00).
  static const softwareVersion = 5;

  const FitDeviceInfo._();
}

/// Activity (34).
class FitActivity {
  /// Local time in FIT seconds, at the message's own timestamp.
  static const localTimestamp = 5;

  const FitActivity._();
}

/// Sensor profile (147), one per paired sensor.
class FitSensorProfile {
  static const antChannelId = 0;
  static const name = 2;
  static const enabled = 3;

  /// 28 is a tank pod.
  static const sensorType = 52;

  /// 0 PSI, 1 kPa, 2 bar.
  static const pressureUnits = 74;
  static const ratedPressure = 75;
  static const reservePressure = 76;

  /// Cubic feet times 10 (PSI) or litres times 10 (bar).
  static const volume = 77;
  static const usedForGasRate = 78;

  const FitSensorProfile._();
}

/// Dive settings (258).
class FitDiveSettings {
  /// 0 is Buhlmann ZHL-16C.
  static const model = 1;
  static const gfLow = 2;
  static const gfHigh = 3;

  /// 0 fresh, 1 salt, 3 custom.
  static const waterType = 4;

  /// Float, kg/m3.
  static const waterDensity = 5;

  /// 0 manual, 1 automatic.
  static const lowSetpointSwitchMode = 22;

  /// Centibar.
  static const lowSetpoint = 23;

  /// Millimetres.
  static const lowSwitchDepth = 24;
  static const highSetpointSwitchMode = 25;
  static const highSetpoint = 26;
  static const highSwitchDepth = 27;

  const FitDiveSettings._();
}

/// Dive gas (259).
class FitDiveGas {
  /// Percent.
  static const helium = 0;

  /// Percent.
  static const oxygen = 1;

  /// 0 disabled, 1 enabled, 2 backup only.
  static const status = 2;

  /// 0 open circuit, 1 CCR diluent.
  static const type = 3;

  /// Position of the gas in the dive's gas list.
  static const messageIndex = 254;

  const FitDiveGas._();
}

/// Dive summary (268).
class FitDiveSummary {
  /// Global number of the message this summarises (18 session, 19 lap).
  static const referenceMessage = 0;

  /// Millimetres.
  static const maxDepth = 3;
  static const diveNumber = 10;

  /// Milliseconds.
  static const bottomTime = 11;

  const FitDiveSummary._();
}

/// Tank update (319).
class FitTankUpdate {
  /// Sensor id, matches [FitSensorProfile.antChannelId].
  static const sensor = 0;

  /// Bar times 100.
  static const pressure = 1;

  const FitTankUpdate._();
}

/// Tank summary (323).
class FitTankSummary {
  static const sensor = 0;

  /// Bar times 100.
  static const startPressure = 1;

  /// Bar times 100.
  static const endPressure = 2;

  /// Litres times 100.
  static const volumeUsed = 3;

  const FitTankSummary._();
}
