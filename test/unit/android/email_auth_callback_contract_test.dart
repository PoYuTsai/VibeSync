import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

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
        contract.purposes,
        containsAll([
          'signup_confirmation',
          'resend_confirmation',
          'password_recovery'
        ]),
      );
    });

    test('Supabase local redirect allowlist includes Email callback', () {
      expect(
        supabaseAdditionalRedirectUrlsBlock(),
        contains('"${contract.uri}"'),
      );
    });

    test('MainActivity is the sole exact Email callback owner', () {
      final main = activityByName(manifest, '.MainActivity');
      expect(androidAttr(main, 'exported'), 'true');
      expect(schemeHosts(main, contract.scheme), contains(contract.host));

      final emailFilters = main
          .findElements('intent-filter')
          .where((filter) => schemeHostsFromFilter(filter, contract.scheme)
              .contains(contract.host))
          .toList();
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
          schemeHosts(activity, contract.scheme).contains(contract.host),
          isFalse,
          reason: '${contract.uri} 只能由 MainActivity 擁有',
        );
      }
    });

    test('OAuth callback remains exclusively owned by CallbackActivity', () {
      final callback = activityByName(manifest, oauth.callbackActivity);
      expect(
        schemeHosts(callback, oauth.scheme),
        contains(oauth.host),
      );
      for (final activity in manifestActivities(manifest)) {
        if (androidAttr(activity, 'name') == oauth.callbackActivity) continue;
        expect(
          schemeHosts(activity, oauth.scheme).contains(oauth.host),
          isFalse,
          reason: '${oauth.uri} 不得由其他 activity 擁有',
        );
      }
    });

    test('Dart, Supabase service, and gate scripts reference the contract', () {
      final environment = readRepoFile('lib/core/config/environment.dart');
      expect(environment, contains(contract.uri));
      expect(
        readRepoFile('lib/core/services/supabase_service.dart'),
        contains('AppConfig.authEmailRedirectUri'),
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
      expect(readRepoFile('contracts/email-auth-callback.json'),
          isNot(contains('client_secret')));
    });
  });
}

Set<String> schemeHostsFromFilter(XmlElement filter, String scheme) => filter
    .findElements('data')
    .where((data) => androidAttrFromElement(data, 'scheme') == scheme)
    .map((data) => androidAttrFromElement(data, 'host') ?? '')
    .toSet();

String? androidAttrFromElement(XmlElement element, String name) =>
    element.getAttribute('android:$name');
