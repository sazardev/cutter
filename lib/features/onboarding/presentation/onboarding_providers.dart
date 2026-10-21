import 'package:cutter/features/editor/presentation/editor_providers.dart';
import 'package:cutter/features/onboarding/data/drift_onboarding_repository.dart';
import 'package:cutter/features/onboarding/domain/onboarding_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The domain port for the onboarding flag, backed by drift.
final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => DriftOnboardingRepository(ref.watch(appDatabaseProvider)),
);

/// Whether the user has already seen the onboarding. Invalidate it after
/// marking the onboarding as completed.
final onboardingCompletedProvider = FutureProvider<bool>(
  (ref) => ref.watch(onboardingRepositoryProvider).isCompleted(),
);
