import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/onboarding/domain/onboarding_repository.dart';

const _completedKey = 'onboarding_completed';
const _completedValue = 'true';

/// Stores the onboarding flag in the `app_settings` table.
class DriftOnboardingRepository implements OnboardingRepository {
  /// Creates a repository over [_db].
  DriftOnboardingRepository(this._db);

  final AppDatabase _db;

  @override
  Future<bool> isCompleted() async {
    final row = await (_db.select(_db.appSettings)
          ..where((setting) => setting.key.equals(_completedKey)))
        .getSingleOrNull();
    return row?.value == _completedValue;
  }

  @override
  Future<void> markCompleted() {
    return _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _completedKey,
            value: _completedValue,
          ),
        );
  }
}
