/// Whether the user has already seen the onboarding, owned by the domain and
/// implemented at the edge.
abstract interface class OnboardingRepository {
  /// True once the user finished or skipped the onboarding.
  Future<bool> isCompleted();

  /// Remembers that the onboarding was seen, so it is not shown again.
  Future<void> markCompleted();
}
