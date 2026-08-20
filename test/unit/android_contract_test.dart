// test/unit/android_contract_test.dart
// Slice 2 Android 契約靜態守門（AND-01／AND-02／AND-03／AND-04、CI-01）。
// 只讀 repo 檔案對帳，不碰裝置、不碰 secrets；動態證據（安裝、簽名）
// 由 CI 的 SEC-01／AND-02 gate 與 install smoke 提供。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _package = 'com.vibesync.app';
const _callbackScheme = 'com.poyutsai.vibesync';
const _callbackHost = 'login-callback';

// 缺檔直接丟 FileSystemException（訊息含路徑），不在測試本體外用 expect
String _read(String path) => File(path).readAsStringSync();

/// 取出 manifest 中包含 [nameMarker] 的 `<activity>...</activity>` 區塊
String _activityBlock(String manifest, String nameMarker) {
  final blocks = RegExp(r'<activity[\s\S]*?</activity>')
      .allMatches(manifest)
      .map((m) => m.group(0)!)
      .where((b) => b.contains(nameMarker))
      .toList();
  expect(blocks, hasLength(1), reason: '應恰有一個 $nameMarker activity 區塊');
  return blocks.first;
}

void main() {
  final manifest = _read('android/app/src/main/AndroidManifest.xml');
  final gradle = _read('android/app/build.gradle.kts');

  group('AND-01 launcher package 對齊', () {
    test('namespace 與 applicationId 凍結為 $_package', () {
      expect(gradle, contains('namespace = "$_package"'));
      expect(gradle, contains('applicationId = "$_package"'));
    });

    test('MainActivity Kotlin 檔位於對應 package 路徑', () {
      final kotlin = _read(
        'android/app/src/main/kotlin/com/vibesync/app/MainActivity.kt',
      );
      expect(kotlin, contains('package $_package'));
      expect(kotlin, contains('class MainActivity : FlutterActivity()'));
      // 舊的錯位 package 目錄不得殘留
      expect(
        Directory('android/app/src/main/kotlin/com/vibesync/vibesync')
            .existsSync(),
        isFalse,
        reason: '舊 com.vibesync.vibesync 目錄應已移除',
      );
    });

    test('manifest launcher 指向 .MainActivity（由 namespace 解析）', () {
      final main = _activityBlock(manifest, '".MainActivity"');
      expect(main, contains('android.intent.category.LAUNCHER'));
    });
  });

  group('AND-03 label 與 OAuth callback 契約', () {
    test('App label 是 VibeSync', () {
      expect(manifest, contains('android:label="VibeSync"'));
    });

    test('CallbackActivity 是 $_callbackScheme://$_callbackHost 唯一擁有者', () {
      final callback = _activityBlock(
        manifest,
        'com.linusu.flutter_web_auth_2.CallbackActivity',
      );
      expect(callback, contains('android:scheme="$_callbackScheme"'));
      expect(callback, contains('android:host="$_callbackHost"'));
      expect(callback, contains('android:exported="true"'));

      // MainActivity 不得重複宣告同 scheme，否則系統跳 activity 選擇器
      final main = _activityBlock(manifest, '".MainActivity"');
      expect(
        main.contains(_callbackScheme),
        isFalse,
        reason: 'deep-link scheme 只能屬於 CallbackActivity',
      );
    });

    test('Dart 端 redirect URI 與 manifest 契約一致', () {
      final environment = _read('lib/core/config/environment.dart');
      expect(
        environment,
        contains("'$_callbackScheme://$_callbackHost'"),
      );
    });
  });

  group('AND-02 release 簽名', () {
    test('release 讀 key.properties 且不得回退 debug 簽名', () {
      expect(gradle, contains('key.properties'));
      expect(
        gradle,
        contains('signingConfig = signingConfigs.getByName("release")'),
      );
      expect(
        gradle.contains('signingConfigs.getByName("debug")'),
        isFalse,
        reason: 'release 禁止 debug 簽名',
      );
      // fail-closed 守門必須存在
      expect(gradle, contains('missingSigningKeys'));
    });

    test('keystore 與 key.properties 不進版控', () {
      final gitignore = _read('android/.gitignore');
      expect(gitignore, contains('key.properties'));
      expect(gitignore, contains('*.jks'));
    });
  });

  group('AND-04 backup／data extraction fail-closed', () {
    const domains = ['root', 'file', 'database', 'sharedpref'];

    test('manifest 關閉備份並掛上兩份 rules', () {
      expect(manifest, contains('android:allowBackup="false"'));
      expect(manifest, contains('android:fullBackupContent="@xml/backup_rules"'));
      expect(
        manifest,
        contains('android:dataExtractionRules="@xml/data_extraction_rules"'),
      );
    });

    test('backup_rules.xml 全域排除四個 domain', () {
      final rules = _read('android/app/src/main/res/xml/backup_rules.xml');
      for (final domain in domains) {
        expect(
          rules,
          contains('<exclude domain="$domain" path="." />'),
          reason: 'backup_rules 缺 $domain 排除',
        );
      }
    });

    test('data_extraction_rules.xml 的 cloud-backup 與 device-transfer 都全排除',
        () {
      final rules =
          _read('android/app/src/main/res/xml/data_extraction_rules.xml');
      for (final section in ['cloud-backup', 'device-transfer']) {
        final match = RegExp('<$section>([\\s\\S]*?)</$section>')
            .firstMatch(rules);
        expect(match, isNotNull, reason: '缺 <$section> 區塊');
        for (final domain in domains) {
          expect(
            match!.group(1),
            contains('<exclude domain="$domain" path="." />'),
            reason: '$section 缺 $domain 排除',
          );
        }
      }
    });
  });

  group('CI-01 Android 路徑解耦', () {
    final distribute = _read('.github/workflows/distribute.yml');
    final release = _read('.github/workflows/release.yml');

    String section(String source, String from, String to) {
      final start = source.indexOf(from);
      expect(start, greaterThanOrEqualTo(0), reason: '找不到 $from');
      final end = source.indexOf(to, start);
      expect(end, greaterThan(start), reason: '找不到 $to');
      return source.substring(start, end);
    }

    test('distribute 的 Android build 不注入 iOS RevenueCat key', () {
      final buildAndroid = section(distribute, '\n  build-android:', '\n  build-ios:');
      expect(buildAndroid.contains('appl_'), isFalse);
      expect(buildAndroid.contains('REVENUECAT'), isFalse);
    });

    test('distribute 共同 gate 不含 iOS keyboard contract', () {
      final gate = section(distribute, '\n  flutter-gate:', '\n  ios-keyboard-gate:');
      expect(gate.contains('check-keyboard-contract'), isFalse);
    });

    test('distribute 的 Android build 掛 SEC-01／AND-02 守門與 smoke', () {
      final buildAndroid = section(distribute, '\n  build-android:', '\n  build-ios:');
      expect(
        buildAndroid,
        contains('check-android-signing.sh keystore'),
      );
      expect(
        buildAndroid,
        contains('check-android-signing.sh artifact'),
      );
      expect(distribute, contains('android-install-smoke'));
      expect(distribute, contains('tools/android/install-smoke.sh'));
    });

    test('release 的 Android 段不注入 iOS RevenueCat key 且掛守門', () {
      final releaseAndroid = section(release, '\n  release-android:', 'fastlane internal');
      expect(releaseAndroid.contains('appl_'), isFalse);
      expect(releaseAndroid.contains('REVENUECAT'), isFalse);
      expect(releaseAndroid, contains('check-android-signing.sh keystore'));
      expect(releaseAndroid, contains('check-android-signing.sh artifact'));
    });

    test('release 仍為手動觸發且 iOS 前置只擋 iOS', () {
      expect(release, contains('workflow_dispatch'));
      expect(release.contains('\n  push:'), isFalse);
      final commonPreflight =
          section(release, '\n  production-preflight:', '\n  ios-preflight:');
      expect(commonPreflight.contains('check-keyboard-contract'), isFalse);
      expect(commonPreflight.contains('check-revenuecat-secret-smoke'), isFalse);
    });
  });
}
