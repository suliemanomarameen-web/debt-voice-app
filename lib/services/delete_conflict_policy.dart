/// Pure conflict-policy resolution shared by synchronization and unit tests.
class DeleteConflictPolicy {
  DeleteConflictPolicy._();

  /// Resolves soft-delete conflicts.
  ///
  /// The two policy flags are mutually exclusive in settings. If legacy or
  /// malformed data enables both, deletion wins as the safer fallback.
  static String resolveSoftDelete({
    required bool modificationAlwaysWins,
    required bool deleteAlwaysWins,
  }) {
    if (deleteAlwaysWins) return 'soft_delete';
    if (modificationAlwaysWins) return 'modification';
    return 'default';
  }

  /// Resolves permanent-delete (tombstone) conflicts.
  ///
  /// If both flags are enabled, permanent deletion wins as the safer fallback.
  static String resolvePermanentDelete({
    required bool modificationAlwaysWins,
    required bool deleteAlwaysWins,
  }) {
    if (deleteAlwaysWins) return 'permanent_delete';
    if (modificationAlwaysWins) return 'modification';
    return 'default';
  }
}


/// Parses the first valid timestamp, falling back when the preferred field is
/// null, empty, or malformed. Keeps legacy records with created_at usable.
DateTime resolveConflictTimestamp({
  required String? preferred,
  required String? fallback,
}) {
  final preferredTime =
      preferred == null || preferred.trim().isEmpty
          ? null
          : DateTime.tryParse(preferred);
  if (preferredTime != null) return preferredTime;

  final fallbackTime =
      fallback == null || fallback.trim().isEmpty
          ? null
          : DateTime.tryParse(fallback);
  return fallbackTime ?? DateTime(2000);
}

/// Determines whether a permanent-delete tombstone should be applied to a
/// transaction. This is kept pure so the synchronization decision is testable.
bool shouldApplyPermanentTombstone({
  required String mode,
  required bool localRowIsActive,
  required bool cloudRowIsActive,
  required DateTime tombstoneTime,
  required DateTime localTime,
  required DateTime cloudTime,
}) {
  if (mode == 'permanent_delete') return true;

  if (mode == 'modification') {
    // An active local row or active cloud row wins, regardless of age.
    return !localRowIsActive && !cloudRowIsActive;
  }

  // Latest wins: only a strictly newer active record defeats the tombstone.
  if (cloudRowIsActive && cloudTime.isAfter(tombstoneTime)) return false;
  if (localRowIsActive && localTime.isAfter(tombstoneTime)) return false;
  return true;
}


/// Chooses which tombstones to publish when building a full sync snapshot.
/// When permanent-delete sync is disabled, preserve the cloud tombstones
/// instead of replacing them with an empty list and erasing prior deletions.
List<Map<String, dynamic>> resolveTombstonesForUpload({
  required bool syncEnabled,
  required List<Map<String, dynamic>> localTombstones,
  required List<dynamic> cloudTombstones,
}) {
  if (syncEnabled) return localTombstones;
  return cloudTombstones
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
}
