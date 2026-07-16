// test/unit/app/onboarding_service_cache_test.dart
//
// The router redirect reads onboarding completion synchronously via
// `OnboardingService.isCompletedSync`. This test pins that the in-memory cache
// is primed by `load()`, flipped synchronously by `markCompleted()` (so the
// post-completion `context.go('/')` already sees true), and cleared by
// `reset()`.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/onboarding/data/onboarding_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('load() primes the sync cache from persisted true', () async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await OnboardingService.load();
    expect(OnboardingService.isCompletedSync, isTrue);
  });

  test('load() primes the sync cache from persisted false/absent', () async {
    SharedPreferences.setMockInitialValues({});
    await OnboardingService.load();
    expect(OnboardingService.isCompletedSync, isFalse);
  });

  test('markCompleted() flips the sync cache before the await resolves',
      () async {
    await OnboardingService.load();
    expect(OnboardingService.isCompletedSync, isFalse);

    final pending = OnboardingService.markCompleted();
    // Synchronous flip: the redirect that fires on context.go('/') right after
    // must already observe completion without awaiting storage.
    expect(OnboardingService.isCompletedSync, isTrue);
    await pending;
    expect(OnboardingService.isCompletedSync, isTrue);
  });

  test('reset() clears the sync cache', () async {
    SharedPreferences.setMockInitialValues({'onboarding_completed': true});
    await OnboardingService.load();
    expect(OnboardingService.isCompletedSync, isTrue);

    await OnboardingService.reset();
    expect(OnboardingService.isCompletedSync, isFalse);
  });

  test('load() restores keyboard onboarding independently', () async {
    SharedPreferences.setMockInitialValues({
      'onboarding_completed': true,
      'keyboard_onboarding_completed': true,
    });
    await OnboardingService.load();

    expect(OnboardingService.isCompletedSync, isTrue);
    expect(OnboardingService.isKeyboardCompletedSync, isTrue);
  });

  test('markKeyboardCompleted() flips only the keyboard cache', () async {
    await OnboardingService.load();
    final pending = OnboardingService.markKeyboardCompleted();

    expect(OnboardingService.isCompletedSync, isFalse);
    expect(OnboardingService.isKeyboardCompletedSync, isTrue);
    await pending;
    expect(OnboardingService.isKeyboardCompletedSync, isTrue);

    await OnboardingService.resetKeyboard();
    expect(OnboardingService.isKeyboardCompletedSync, isFalse);
  });
}
