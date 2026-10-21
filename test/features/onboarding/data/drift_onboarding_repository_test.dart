import 'package:cutter/core/db/app_database.dart';
import 'package:cutter/features/onboarding/data/drift_onboarding_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DriftOnboardingRepository repository;

  setUp(() {
    db = AppDatabase.inMemory();
    repository = DriftOnboardingRepository(db);
  });

  tearDown(() => db.close());

  test('is not completed on a fresh database', () async {
    expect(await repository.isCompleted(), isFalse);
  });

  test('remembers that it was completed, also when marked twice', () async {
    await repository.markCompleted();
    await repository.markCompleted();

    expect(await repository.isCompleted(), isTrue);
    expect(await db.select(db.appSettings).get(), hasLength(1));
  });
}
