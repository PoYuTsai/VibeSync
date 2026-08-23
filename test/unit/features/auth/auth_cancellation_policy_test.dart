import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibesync/features/auth/presentation/auth_cancellation_policy.dart';

void main() {
  group('AuthCancellationPolicy', () {
    test('classifies typed FlutterWebAuth cancellation', () {
      final result = AuthCancellationPolicy.classify(
        PlatformException(code: 'CANCELED', message: 'User canceled login'),
      );

      expect(result, AuthCancellationKind.userCancelled);
    });

    test('classifies typed OAuth access_denied callback as cancellation', () {
      final result = AuthCancellationPolicy.classify(
        AuthException('OAuth callback denied', code: 'access_denied'),
      );

      expect(result, AuthCancellationKind.userCancelled);
    });

    test('classifies native Apple canceled authorization', () {
      final result = AuthCancellationPolicy.classify(
        const SignInWithAppleAuthorizationException(
          code: AuthorizationErrorCode.canceled,
          message: 'The user canceled the authorization request.',
        ),
      );

      expect(result, AuthCancellationKind.userCancelled);
    });

    test('keeps provider errors visible when their message says cancel', () {
      final result = AuthCancellationPolicy.classify(
        AuthException(
          'Apple provider canceled by upstream before completing',
          code: 'provider_error',
        ),
      );

      expect(result, isNull);
    });

    test('does not classify arbitrary text as cancellation', () {
      expect(
        AuthCancellationPolicy.classify(
          PlatformException(
            code: 'provider_error',
            message: 'The user canceled the provider request.',
          ),
        ),
        isNull,
      );
      expect(
        AuthCancellationPolicy.classify(
          const SignInWithAppleAuthorizationException(
            code: AuthorizationErrorCode.failed,
            message: 'The user canceled after a provider failure.',
          ),
        ),
        isNull,
      );
    });
  });
}
