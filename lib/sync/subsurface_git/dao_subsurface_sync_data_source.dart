/// Production [SubsurfaceSyncDataSource] implementation.
///
/// Adapts the abstract seam declared in [sync_orchestrator.dart] to the
/// real PowerSync-backed DAOs ([DiveDao], [DiveAnnotationsDao],
/// [EquipmentDao]). Pure plumbing — no business logic, no caching.
///
/// Lives outside the orchestrator file so the orchestrator's tests can
/// keep using their in-memory `_FakeDataSource` without dragging the
/// PowerSync stack into the test process.
library;

import '../../data/db/database.dart' show Cylinder, Dive, DiveComputer;
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/dive_dao.dart';
import '../../data/db/equipment_dao.dart';
import 'package:subsurface_core/data/models/annotation.dart';
import 'package:subsurface_core/data/models/sample_set.dart';
import 'sync_orchestrator.dart';

/// Wires the orchestrator's [SubsurfaceSyncDataSource] seam to the real
/// production DAOs. Pass into [SubsurfaceSyncOrchestrator] at app boot.
class DaoSubsurfaceSyncDataSource implements SubsurfaceSyncDataSource {
  DaoSubsurfaceSyncDataSource({
    required DiveDao diveDao,
    required DiveAnnotationsDao annotationsDao,
    required EquipmentDao equipmentDao,
  })  : _diveDao = diveDao,
        _annotationsDao = annotationsDao,
        _equipmentDao = equipmentDao;

  final DiveDao _diveDao;
  final DiveAnnotationsDao _annotationsDao;
  final EquipmentDao _equipmentDao;

  @override
  Future<List<Dive>> getAllDives() => _diveDao.getAllDives();

  @override
  Future<SampleSet?> getSamples(String diveId) =>
      _diveDao.getSamples(diveId);

  @override
  Future<DiveAnnotation?> getAnnotation(String diveId) =>
      _annotationsDao.get(diveId);

  /// Resolves each per-dive (gas_mix_index → cylinder_id) row through the
  /// global cylinder table so the mapper sees full [Cylinder] records.
  /// Rows whose `cylinder_id` is null are skipped — the mapper falls back
  /// to a default-shaped cylinder for those slots. The [getCylinder]
  /// lookup is sequential rather than batched because a single dive
  /// rarely exceeds 4-5 distinct mix indexes; if that ever changes we
  /// can add an `EquipmentDao.getCylindersByIds` batch fetch.
  @override
  Future<Map<int, Cylinder>> cylindersByMixIndex(String diveId) async {
    final mappings = await _equipmentDao.listCylindersForDive(diveId);
    final out = <int, Cylinder>{};
    for (final m in mappings) {
      final cylId = m.cylinderId;
      if (cylId == null) continue;
      final cyl = await _equipmentDao.getCylinder(cylId);
      if (cyl == null) continue;
      out[m.gasMixIndex] = cyl;
    }
    return out;
  }

  @override
  Future<List<DiveComputer>> listAllDiveComputers() =>
      _equipmentDao.listDiveComputers();

  @override
  Future<void> markSubsurfaceUploaded(
          Iterable<String> diveIds, int whenSeconds) =>
      _diveDao.markSubsurfaceUploaded(diveIds, whenSeconds);
}
