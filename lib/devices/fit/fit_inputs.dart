/// What the user picked for a FIT import.
library;

sealed class FitInput {
  const FitInput(this.path);

  final String path;
}

/// One picked file: a `.fit` file or a `.zip` (a Garmin export).
class FitFileInput extends FitInput {
  const FitFileInput(super.path);
}

/// A picked folder, read recursively.
class FitFolderInput extends FitInput {
  const FitFolderInput(super.path);
}

/// How far a scan has come. The total grows while zips are opened.
class FitScanCounts {
  FitScanCounts({
    this.filesRead = 0,
    this.filesTotal,
    this.dives = 0,
    this.otherActivities = 0,
    this.apnea = 0,
    this.unreadable = 0,
  });

  int filesRead;
  int? filesTotal;
  int dives;
  int otherActivities;
  int apnea;
  int unreadable;

  FitScanCounts copy() => FitScanCounts(
    filesRead: filesRead,
    filesTotal: filesTotal,
    dives: dives,
    otherActivities: otherActivities,
    apnea: apnea,
    unreadable: unreadable,
  );
}
