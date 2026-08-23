import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:vibesync/core/config/environment.dart';

import 'android_contract_helpers.dart';

void main() {
  final contract = EmailAuthCallbackContract.load();
  final oauth = AuthCallbackContract.load();
  final manifest = loadAndroidManifest();

  group('Android Email callback contract', () {
    test('machine-readable contract freezes the independent callback', () {
      expect(contract.scheme, oauth.scheme);
      expect(contract.host, 'email-callback');
      expect(contract.callbackActivity, 'com.vibesync.app.MainActivity');
      expect(contract.uri, 'com.poyutsai.vibesync://email-callback');
      expect(
        contract.flowPaths,
        {'signup': '/signup', 'recovery': '/recovery'},
      );
      expect(
        contract.purposes,
        containsAll([
          'signup_confirmation',
          'resend_confirmation',
          'password_recovery'
        ]),
      );
      expect(
        contract.supabaseAllowlistEntries,
        containsAll([
          'com.poyutsai.vibesync://email-callback/signup',
          'com.poyutsai.vibesync://email-callback/recovery',
        ]),
      );
    });

    test('Supabase local redirect allowlist includes Email callback', () {
      expect(
        supabaseAdditionalRedirectUrlsBlock(),
        contains('"${contract.supabaseAllowlistEntries[0]}"'),
      );
      expect(
        supabaseAdditionalRedirectUrlsBlock(),
        contains('"${contract.supabaseAllowlistEntries[1]}"'),
      );
      expect(
        AppConfig.authEmailSignupRedirectUri,
        contract.supabaseAllowlistEntries[0],
      );
      expect(
        AppConfig.authEmailRecoveryRedirectUri,
        contract.supabaseAllowlistEntries[1],
      );
    });

    test('MainActivity is the sole exact Email callback owner', () {
      final main = activityByName(manifest, '.MainActivity');
      expect(androidAttr(main, 'exported'), 'true');
      expect(
        matchingCallbackFilters(
          main,
          scheme: contract.scheme,
          host: contract.host,
        ),
        hasLength(1),
      );

      final emailFilters = matchingCallbackFilters(
        main,
        scheme: contract.scheme,
        host: contract.host,
      );
      expect(emailFilters, hasLength(1));
      final emailFilter = emailFilters.single;
      expect(
        hasCategory(emailFilter, 'android.intent.category.BROWSABLE'),
        isTrue,
      );
      expect(
        hasCategory(emailFilter, 'android.intent.category.DEFAULT'),
        isTrue,
      );

      for (final activity in manifestActivities(manifest)) {
        if (androidAttr(activity, 'name') == '.MainActivity') continue;
        expect(
          matchingCallbackFilters(
            activity,
            scheme: contract.scheme,
            host: contract.host,
          ),
          isEmpty,
          reason: '${contract.uri} 只能由 MainActivity 擁有',
        );
      }
    });

    test('OAuth callback remains exclusively owned by CallbackActivity', () {
      final callback = activityByName(manifest, oauth.callbackActivity);
      expect(
        matchingCallbackFilters(
          callback,
          scheme: oauth.scheme,
          host: oauth.host,
        ),
        hasLength(1),
      );
      for (final activity in manifestActivities(manifest)) {
        if (androidAttr(activity, 'name') == oauth.callbackActivity) continue;
        expect(
          matchingCallbackFilters(
            activity,
            scheme: oauth.scheme,
            host: oauth.host,
          ),
          isEmpty,
          reason: '${oauth.uri} 不得由其他 activity 擁有',
        );
      }
    });

    test('Dart, Supabase service, and gate scripts reference the contract', () {
      final environment = readRepoFile('lib/core/config/environment.dart');
      expect(environment, contains(contract.uri));
      expect(
        readRepoFile('lib/core/services/supabase_service.dart'),
        contains('AppConfig.authEmailSignupRedirectUri'),
      );
      expect(
        readRepoFile('lib/core/services/supabase_service.dart'),
        contains('AppConfig.authEmailRecoveryRedirectUri'),
      );
      for (final path in [
        'tools/android/assert-merged-manifest.py',
        'tools/android/install-smoke.sh',
        'tools/android/install-smoke-negative-check.sh',
        'tools/android/manifest-gate-negative-check.sh',
      ]) {
        expect(
          readRepoFile(path),
          contains('contracts/email-auth-callback.json'),
          reason: '$path 必須從 Email callback contract 讀取值',
        );
      }
    });

    test('contract JSON is valid and contains no secret material', () {
      final value = jsonDecode(
        readRepoFile('contracts/email-auth-callback.json'),
      ) as Map<String, dynamic>;
      expect(value['scheme'], isA<String>());
      expect(value['host'], isA<String>());
      expect(value['androidCallbackActivity'], isA<String>());
      expect(value['purposes'], isA<List<dynamic>>());
      expect(value['flowPath'], isA<Map<String, dynamic>>());
      expect(value['supabaseRedirectAllowlistEntries'], isA<List<dynamic>>());
      expect(readRepoFile('contracts/email-auth-callback.json'),
          isNot(contains('client_secret')));
    });

    test('Dart helper models scheme-only and split data as matching owners',
        () {
      final schemeOnly = XmlDocument.parse('''
        <intent-filter xmlns:android="http://schemas.android.com/apk/res/android">
          <data android:scheme="com.poyutsai.vibesync" />
        </intent-filter>
      ''').rootElement;
      final split = XmlDocument.parse('''
        <intent-filter xmlns:android="http://schemas.android.com/apk/res/android">
          <data android:scheme="com.poyutsai.vibesync" />
          <data android:host="email-callback" />
        </intent-filter>
      ''').rootElement;

      expect(
        callbackFilterMayMatch(
          schemeOnly,
          scheme: contract.scheme,
          host: contract.host,
        ),
        isTrue,
      );
      expect(
        callbackFilterMayMatch(
          split,
          scheme: contract.scheme,
          host: contract.host,
        ),
        isTrue,
      );
    });

    test(
        'leading wildcard host competitors match Email callback conservatively',
        () {
      for (final host in ['*', '*callback', '*-callback']) {
        final wildcard = XmlDocument.parse('''
          <intent-filter xmlns:android="http://schemas.android.com/apk/res/android">
            <data android:scheme="${contract.scheme}" android:host="$host" />
          </intent-filter>
        ''').rootElement;

        expect(
          callbackFilterMayMatch(
            wildcard,
            scheme: contract.scheme,
            host: contract.host,
          ),
          isTrue,
          reason: 'host pattern $host may claim the Email callback',
        );
      }
    });
  });
}
