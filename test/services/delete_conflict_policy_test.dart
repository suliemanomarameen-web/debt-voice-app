import 'package:flutter_test/flutter_test.dart';
import 'package:debt_voice_app/services/delete_conflict_policy.dart';

void main() {
  group('soft-delete conflict policy', () {
    test('soft deletion wins when selected', () {
      expect(
        DeleteConflictPolicy.resolveSoftDelete(
          modificationAlwaysWins: false,
          deleteAlwaysWins: true,
        ),
        'soft_delete',
      );
    });

    test('modification wins when selected', () {
      expect(
        DeleteConflictPolicy.resolveSoftDelete(
          modificationAlwaysWins: true,
          deleteAlwaysWins: false,
        ),
        'modification',
      );
    });

    test('latest wins when neither policy is selected', () {
      expect(
        DeleteConflictPolicy.resolveSoftDelete(
          modificationAlwaysWins: false,
          deleteAlwaysWins: false,
        ),
        'default',
      );
    });

    test('soft deletion is the safe fallback if both flags are enabled', () {
      expect(
        DeleteConflictPolicy.resolveSoftDelete(
          modificationAlwaysWins: true,
          deleteAlwaysWins: true,
        ),
        'soft_delete',
      );
    });
  });

  group('permanent-delete conflict policy', () {
    test('permanent deletion wins when selected', () {
      expect(
        DeleteConflictPolicy.resolvePermanentDelete(
          modificationAlwaysWins: false,
          deleteAlwaysWins: true,
        ),
        'permanent_delete',
      );
    });

    test('modification wins when selected', () {
      expect(
        DeleteConflictPolicy.resolvePermanentDelete(
          modificationAlwaysWins: true,
          deleteAlwaysWins: false,
        ),
        'modification',
      );
    });

    test('latest wins when neither policy is selected', () {
      expect(
        DeleteConflictPolicy.resolvePermanentDelete(
          modificationAlwaysWins: false,
          deleteAlwaysWins: false,
        ),
        'default',
      );
    });

    test('permanent deletion is the safe fallback if both flags are enabled', () {
      expect(
        DeleteConflictPolicy.resolvePermanentDelete(
          modificationAlwaysWins: true,
          deleteAlwaysWins: true,
        ),
        'permanent_delete',
      );
    });
  });

  test('soft and permanent deletion policies remain independent', () {
    expect(
      DeleteConflictPolicy.resolveSoftDelete(
        modificationAlwaysWins: false,
        deleteAlwaysWins: true,
      ),
      'soft_delete',
    );
    expect(
      DeleteConflictPolicy.resolvePermanentDelete(
        modificationAlwaysWins: true,
        deleteAlwaysWins: false,
      ),
      'modification',
    );
  });

  group('conflict timestamp parsing', () {
    test('uses preferred timestamp when valid', () {
      expect(
        resolveConflictTimestamp(
          preferred: '2026-11-19T10:00:00.000',
          fallback: '2026-11-18T10:00:00.000',
        ),
        DateTime.parse('2026-11-19T10:00:00.000'),
      );
    });

    test('falls back when preferred timestamp is empty', () {
      expect(
        resolveConflictTimestamp(
          preferred: '',
          fallback: '2026-11-18T10:00:00.000',
        ),
        DateTime.parse('2026-11-18T10:00:00.000'),
      );
    });

    test('falls back when preferred timestamp is malformed', () {
      expect(
        resolveConflictTimestamp(
          preferred: 'not-a-date',
          fallback: '2026-11-18T10:00:00.000',
        ),
        DateTime.parse('2026-11-18T10:00:00.000'),
      );
    });

    test('uses safe epoch when both timestamps are invalid', () {
      expect(
        resolveConflictTimestamp(
          preferred: null,
          fallback: 'not-a-date',
        ),
        DateTime(2000),
      );
    });
  });
}
