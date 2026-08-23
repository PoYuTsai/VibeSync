// test/unit/android/auth_callback_contract_test.dart
// AND-03：App label 與凍結 OAuth callback 三方契約（app scheme＋host／
// flutter_web_auth_2 CallbackActivity／Supabase redirect allowlist）。
// 凍結值唯一真相源是 contracts/auth-callback.json；本檔驗證 manifest、
// Dart 常數與 CI 守門都對帳同一份；Email callback 可共用 scheme 但不可
// 共用 OAuth host。
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'android_contract_helpers.dart';

void main() {
  final contract = AuthCallbackContract.load();
  final manifest = loadAndroidManifest();

  group('AND-03 label 與凍結 callback 契約', () {
    test('契約檔凍結值本身不漂移', () {
      expect(contract.scheme, 'com.poyutsai.vibesync');
      expect(contract.host, 'login-callback');
      expect(
        contract.callbackActivity,
        'com.linusu.flutter_web_auth_2.CallbackActivity',
        reason: 'Frozen Spec 指定 flutter_web_auth_2 的 CallbackActivity，'
            '不得換成自訂 dispatcher',
      );
    });

    test('Supabase allowlist 欄位由 scheme+host 推導且對帳 config.toml', () {
      expect(
        contract.supabaseAllowlistEntry,
        contract.uri,
        reason: '三方契約的 allowlist 條目必須等於 scheme://host，'
            '不得各自漂移',
      );
      expect(
        supabaseAdditionalRedirectUrlsBlock(),
        contains('"${contract.supabaseAllowlistEntry}"'),
        reason: 'supabase/config.toml 的 additional_redirect_urls 必須含'
            '凍結 callback URI（三方契約的 Supabase 端）',
      );
    });

    test('App label 是 VibeSync', () {
      expect(androidAttr(applicationElement(manifest), 'label'), 'VibeSync');
    });

    test('CallbackActivity 是凍結 URI 唯一擁有者（無 chooser）', () {
      final callback = activityByName(manifest, contract.callbackActivity);
      expect(androidAttr(callback, 'exported'), 'true');
      final matchingFilters = callback
          .findElements('intent-filter')
          .where(
            (filter) => callbackFilterMayMatch(
              filter,
              scheme: contract.scheme,
              host: contract.host,
            ),
          )
          .toList();
      expect(matchingFilters, hasLength(1));

      final filter = matchingFilters.single;
      expect(
        hasCategory(filter, 'android.intent.category.BROWSABLE'),
        isTrue,
        reason: '瀏覽器開啟 callback 需要 BROWSABLE',
      );
      expect(hasCategory(filter, 'android.intent.category.DEFAULT'), isTrue);

      for (final activity in manifestActivities(manifest)) {
        if (androidAttr(activity, 'name') == contract.callbackActivity) {
          continue;
        }
        expect(
          activity.findElements('intent-filter').where(
                (filter) => callbackFilterMayMatch(
                  filter,
                  scheme: contract.scheme,
                  host: contract.host,
                ),
              ),
          isEmpty,
          reason: '${contract.uri} 深連結只能屬於 CallbackActivity；'
              'Email callback 可共用 scheme，但不得共用 OAuth host，'
              '否則會撞 activity 選擇器',
        );
      }
    });

    test('不得出現自訂 dispatcher（Frozen Spec 衝突已裁定回凍結契約）', () {
      expect(
        manifestActivities(manifest).where(
          (a) => (androidAttr(a, 'name') ?? '').contains('Dispatcher'),
        ),
        isEmpty,
        reason: '自訂 AuthCallbackDispatcherActivity 不在凍結規格內',
      );
    });

    test('任何 activity 都不得宣告 taskAffinity（plugin 官方 troubleshooting）', () {
      // flutter_web_auth_2 4.1.0 官方 Android troubleshooting：manifest 不得
      // 設 taskAffinity（含空字串），否則 OAuth 回跳可能落在錯的 task，
      // authenticate 收不到結果
      for (final activity in manifestActivities(manifest)) {
        expect(
          androidAttr(activity, 'taskAffinity'),
          isNull,
          reason: '${androidAttr(activity, 'name')} 不得宣告 taskAffinity',
        );
      }
    });

    test('MainActivity exported、singleTop、只接 Email VIEW filter', () {
      final main = activityByName(manifest, '.MainActivity');
      expect(androidAttr(main, 'exported'), 'true');
      expect(androidAttr(main, 'launchMode'), 'singleTop');
      final viewFilters = main.findElements('intent-filter').where(
            (filter) => filter.findElements('action').any(
                (a) => androidAttr(a, 'name') == 'android.intent.action.VIEW'),
          );
      expect(viewFilters, hasLength(1));
      expect(
        main.findElements('intent-filter').where(
              (filter) => callbackFilterMayMatch(
                filter,
                scheme: contract.scheme,
                host: contract.host,
              ),
            ),
        isEmpty,
        reason: 'MainActivity 只能接獨立 Email host，不得接 OAuth host',
      );
    });

    test('Dart 端 redirect 契約對帳 contract JSON，無第二份硬編', () {
      final environment = readRepoFile('lib/core/config/environment.dart');
      expect(
        environment,
        contains("'${contract.uri}'"),
        reason: 'AppConfig 的 native redirect URI 必須等於契約檔凍結值',
      );

      final socialAuth = readRepoFile(
        'lib/core/services/social_auth/social_auth_native.dart',
      );
      expect(
        socialAuth,
        contains('AppConfig.authRedirectUri'),
        reason: 'OAuth 必須走 AppConfig.authRedirectUri',
      );
      expect(
        socialAuth.contains("'${contract.host}'"),
        isFalse,
        reason: 'social auth 不得硬編 callback host 字串常數',
      );
      expect(
        socialAuth.contains("'${contract.scheme}'"),
        isFalse,
        reason: 'social auth 不得硬編 callback scheme 字串常數',
      );
    });

    test('CI 守門與 smoke 都從契約檔讀凍結值', () {
      for (final path in [
        'tools/android/assert-merged-manifest.py',
        'tools/android/install-smoke.sh',
        'tools/android/install-smoke-negative-check.sh',
        'tools/android/manifest-gate-negative-check.sh',
      ]) {
        expect(
          readRepoFile(path),
          contains('contracts/auth-callback.json'),
          reason: '$path 必須對帳契約檔，不得硬編 scheme/host',
        );
      }
    });
  });
}
