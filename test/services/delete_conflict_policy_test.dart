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
}
