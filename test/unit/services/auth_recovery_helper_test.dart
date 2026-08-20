import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vibesync/core/services/auth_recovery_helper.dart';

void main() {
  group('AuthRecoveryHelper.normalizeAuthCallbackUri', () {
    test('converts hash fragment into query string when link has no query', () {
      final uri = Uri.parse(
        'com.poyutsai.vibesync://login-callback#type=recovery&access_token=abc',
      );

      final normalized = AuthRecoveryHelper.normalizeAuthCallbackUri(uri);

      expect(normalized.queryParameters['type'], 'recovery');
      expect(normalized.queryParameters['access_token'], 'abc');
    });

    test('preserves existing query and appends hash params with ampersand', () {
      final uri = Uri.parse(
        'com.poyutsai.vibesync://login-callback?foo=bar#type=recovery',
      );

      final normalized = AuthRecoveryHelper.normalizeAuthCallbackUri(uri);

      expect(normalized.queryParameters['foo'], 'bar');
      expect(normalized.queryParameters['type'], 'recovery');
    });
  });

  group('AuthRecoveryHelper.isPasswordRecoveryLink', () {
    test('returns true for recovery callback links', () {
      final uri = Uri.parse(
        'com.poyutsai.vibesync://login-callback#type=recovery',
      );

      expect(AuthRecoveryHelper.isPasswordRecoveryLink(uri), isTrue);
    });

    test('returns false for non-recovery auth links and null', () {
      final uri = Uri.parse(
        'com.poyutsai.vibesync://login-callback#type=signup',
      );

      expect(AuthRecoveryHelper.isPasswordRecoveryLink(uri), isFalse);
      expect(AuthRecoveryHelper.isPasswordRecoveryLink(null), isFalse);
    });
  });

  group('AuthRecoveryHelper.nextPasswordRecoveryState', () {
    test('enters recovery mode on passwordRecovery event', () {
      final result = AuthRecoveryHelper.nextPasswordRecoveryState(
        event: AuthChangeEvent.passwordRecovery,
        currentState: false,
      );

      expect(result, isTrue);
    });

    test('clears recovery mode on signed in and signed out', () {
      expect(
        AuthRecoveryHelper.nextPasswordRecoveryState(
          event: AuthChangeEvent.signedIn,
          currentState: true,
        ),
        isFalse,
      );
      expect(
        AuthRecoveryHelper.nextPasswordRecoveryState(
          event: AuthChangeEvent.signedOut,
          currentState: true,
        ),
        isFalse,
      );
    });

    test('keeps existing state for unrelated auth events', () {
      final result = AuthRecoveryHelper.nextPasswordRecoveryState(
        event: AuthChangeEvent.userUpdated,
        currentState: true,
      );

      expect(result, isTrue);
    });
  });

  // P1-1 分流後的 Android 深連結路由回歸：
  // 冷啟＝getInitialLink 拿到 launch intent 的 URI（login-callback 進
  // MainActivity）；暖啟＝singleTop onNewIntent 後由 supabase_flutter 發
  // auth 事件走 nextPasswordRecoveryState 狀態機。
  group('Android 冷暖深連結路由回歸（P1-1）', () {
    test('冷啟 initial link：login-callback 密碼重設連結（fragment 與 query 形態）都被辨識',
        () {
      final fragmentForm = Uri.parse(
        'com.poyutsai.vibesync://login-callback#access_token=abc&type=recovery',
      );
      final queryForm = Uri.parse(
        'com.poyutsai.vibesync://login-callback?code=xyz&type=recovery',
      );

      expect(AuthRecoveryHelper.isPasswordRecoveryLink(fragmentForm), isTrue);
      expect(AuthRecoveryHelper.isPasswordRecoveryLink(queryForm), isTrue);
    });

    test('oauth-callback 連結屬 OAuth 流程，不得誤判為密碼重設', () {
      final oauthCallback = Uri.parse(
        'com.poyutsai.vibesync://oauth-callback?code=abc123',
      );

      expect(AuthRecoveryHelper.isPasswordRecoveryLink(oauthCallback), isFalse);
    });

    test('冷啟 signup 確認連結不進 recovery 模式', () {
      final signupConfirm = Uri.parse(
        'com.poyutsai.vibesync://login-callback#access_token=abc&type=signup',
      );

      expect(
        AuthRecoveryHelper.isPasswordRecoveryLink(signupConfirm),
        isFalse,
      );
    });

    test('暖啟：recovery 事件進入、signedIn 退出（onNewIntent 後的事件序）', () {
      var state = AuthRecoveryHelper.nextPasswordRecoveryState(
        event: AuthChangeEvent.passwordRecovery,
        currentState: false,
      );
      expect(state, isTrue);

      state = AuthRecoveryHelper.nextPasswordRecoveryState(
        event: AuthChangeEvent.signedIn,
        currentState: state,
      );
      expect(state, isFalse);
    });
  });
}
