import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibesync/features/auth/domain/auth_cancellation_policy.dart';

void main() {
  group('AuthCancellationPolicy', () {
    test('classifies FlutterWebAuth cancellation as silent and retryable', () {
      final result = AuthCancellationPolicy.classify(
        PlatformException(code: 'CANCELED', message: 'User canceled login'),
      );

      expect(result, AuthCancellationKind.userCancelled);
      expect(AuthCancellationPolicy.shouldShowError(result), isFalse);
      expect(AuthCancellationPolicy.canRetry(result), isTrue);
    });

    test('classifies OAuth access_denied callback as user cancellation', () {
      final result = AuthCancellationPolicy.classify(
        AuthException('OAuth callback denied', code: 'access_denied'),
      );

      expect(result, AuthCancellationKind.userCancelled);
      expect(AuthCancellationPolicy.shouldShowError(result), isFalse);
      expect(AuthCancellationPolicy.canRetry(result), isTrue);
    });

    test('keeps provider errors visible and retryable', () {
      final result = AuthCancellationPolicy.classify(
        AuthException('Apple provider unavailable', code: 'provider_error'),
      );

      expect(result, isNull);
      expect(AuthCancellationPolicy.shouldShowError(result), isTrue);
      expect(AuthCancellationPolicy.canRetry(result), isTrue);
    });
  });
}
