/// Abstract interface for [DivePlansDao] — extracted so the UI notifier
/// can depend on a thin contract without pulling in the PowerSync
/// concrete DAO, and so tests can fake it.
library;

import 'dive_plans_dao.dart' show DivePlanDraft, SavedDivePlan;

abstract class DivePlansDaoLike {
  Future<DivePlanDraft?> loadDraft();
  Future<void> upsertDraft(DivePlanDraft draft);
  Future<void> clearDraft();
  Future<List<SavedDivePlan>> listSaved();
  Future<DivePlanDraft?> loadSaved(String id);
  Future<SavedDivePlan> saveAs({required String name});

  /// Overwrites the content of an already-saved plan row in place.
  /// Used by the smart-save flow when the diver clicks Save on a
  /// loaded plan whose name hasn't changed.
  Future<void> updateSaved({
    required String id,
    required DivePlanDraft draft,
    required String name,
  });

  Future<void> softDelete(String id);
  Future<void> renameSaved(String id, String name);
  Stream<void> watchChanges();
}
