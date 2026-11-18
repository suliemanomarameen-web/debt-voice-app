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
