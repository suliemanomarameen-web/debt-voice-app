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
