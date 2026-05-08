/// Notifier for the dive detail screen.
///
/// Manages sample loading, trace visibility, and crosshair position.
library;

import 'package:flutter/foundation.dart';
import '../../data/db/database.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../data/models/sample_set.dart';
import '../../shearwater/parser/constants.dart';

/// The set of data traces that can be toggled on/off in the profile chart.
enum TraceType { ppo2, setpoint, deco, cells, tanks, gasChanges }

/// ChangeNotifier backing the dive detail screen.
///
/// Provides:
/// - Lazy sample loading from [DiveDao].
/// - Per-[TraceType] visibility toggle with notification.
/// - Crosshair index for the profile chart scrubber.
class DiveDetailNotifier extends ChangeNotifier {
  final Dive dive;
  final DiveDao _dao;
  final EquipmentDao? _equipmentDao;

  SampleSet? _samples;
  Map<int, OxygenCell> _activeCells = const {};
  Map<int, Cylinder> _mappedCylinders = const {};
  final Set<TraceType> _visibleTraces;
  int? _crosshairIndex;
  bool _loading = false;

  /// The loaded sample data, or `null` if [loadSamples] has not completed.
  SampleSet? get samples => _samples;

  /// Slot-keyed map of cells that were active at [dive.startTime].
  Map<int, OxygenCell> get activeCells => _activeCells;

  /// Channel-keyed cylinders mapped via [PressureMappings] for this dive's
  /// dive computer. Empty when no mappings exist.
  Map<int, Cylinder> get mappedCylinders => _mappedCylinders;

  /// Currently visible trace types.
  Set<TraceType> get visibleTraces => _visibleTraces;

  /// Current crosshair sample index, or `null` when no crosshair is active.
  int? get crosshairIndex => _crosshairIndex;

  /// `true` while [loadSamples] is in flight.
  bool get loading => _loading;

  DiveDetailNotifier({
    required this.dive,
    required DiveDao dao,
    EquipmentDao? equipmentDao,
  })  : _dao = dao,
        _equipmentDao = equipmentDao,
        _visibleTraces = _defaultTraces(dive.diveMode);

  static Set<TraceType> _defaultTraces(int diveModeValue) {
    final mode = DiveMode.fromValue(diveModeValue);
    if (mode.isCcr) {
      return {
        TraceType.ppo2,
        TraceType.setpoint,
        TraceType.deco,
        TraceType.gasChanges,
      };
    }
    return {TraceType.deco, TraceType.gasChanges};
  }

  /// Load samples from the database and notify listeners.
  Future<void> loadSamples() async {
    _loading = true;
    notifyListeners();
    _samples = await _dao.getSamples(dive.id);
    if (_equipmentDao != null) {
      _activeCells = await _equipmentDao.activeCellsAt(
        DateTime.fromMillisecondsSinceEpoch(dive.startTime * 1000),
      );
      _mappedCylinders = await _loadMappedCylinders(_equipmentDao, dive.dcSerial);
    }
    _loading = false;
    notifyListeners();
  }

  static Future<Map<int, Cylinder>> _loadMappedCylinders(
      EquipmentDao dao, int dcSerial) async {
    final dc = await dao.getDiveComputerBySerial(dcSerial);
    if (dc == null) return const {};
    final mappings = await dao.listPressureMappings(dc.id);
    final out = <int, Cylinder>{};
    for (final m in mappings) {
      final cylId = m.cylinderId;
      if (cylId == null) continue;
      final c = await dao.getCylinder(cylId);
      if (c == null || c.deletedAt != null) continue;
      out[m.channelIndex] = c;
    }
    return out;
  }

  /// Toggle the visibility of [trace] and notify listeners.
  void toggleTrace(TraceType trace) {
    if (_visibleTraces.contains(trace)) {
      _visibleTraces.remove(trace);
    } else {
      _visibleTraces.add(trace);
    }
    notifyListeners();
  }

  /// Set the crosshair to [index] and notify listeners.
  void setCrosshairIndex(int index) {
    _crosshairIndex = index;
    notifyListeners();
  }

  /// Clear the crosshair and notify listeners.
  void clearCrosshair() {
    _crosshairIndex = null;
    notifyListeners();
  }
}
