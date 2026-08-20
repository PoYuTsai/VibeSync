// test/unit/android_contract_test.dart
// Slice 2 Android 契約靜態守門（AND-01～AND-04、CI-01，含審查 P1-1~P1-7）。
// P2 硬化：manifest／backup XML 用 package:xml、workflow 用 package:yaml
// 做結構化解析，不再對整段原文做字串切片。Gradle kts 與 shell 腳本沒有
// 結構化解析器，維持關鍵字對帳；其動態行為由 CI 的 SEC-01／AND-02 gate、
// signing-gate-negative-check.sh 與 install smoke 提供可執行證據。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

const _package = 'com.vibesync.app';
const _scheme = 'com.poyutsai.vibesync';
const _oauthHost = 'oauth-callback';
const _emailHost = 'login-callback';

// 缺檔直接丟 FileSystemException（訊息含路徑）
String _read(String path) => File(path).readAsStringSync();

// ---------- XML helpers ----------

String? _attr(XmlElement e, String name) => e.getAttribute('android:$name');

List<XmlElement> _activities(XmlDocument manifest) => manifest.rootElement
    .findElements('application')
    .single
    .findElements('activity')
    .toList();

XmlElement _activityByName(XmlDocument manifest, String name) {
  final matches = _activities(manifest)
      .where((a) => _attr(a, 'name') == name)
      .toList();
  expect(matches, hasLength(1), reason: '應恰有一個 $name activity');
  return matches.first;
}

bool _hasCategory(XmlElement filter, String category) => filter
    .findElements('category')
    .any((c) => _attr(c, 'name') == category);

/// activity 內所有宣告 [_scheme] 的 intent-filter data host
Set<String> _schemeHosts(XmlElement activity) => activity
    .findElements('intent-filter')
    .expand((f) => f.findElements('data'))
    .where((d) => _attr(d, 'scheme') == _scheme)
    .map((d) => _attr(d, 'host') ?? '')
    .toSet();

Set<String> _excludedDomains(XmlElement parent) => parent
    .findElements('exclude')
    .where((e) => e.getAttribute('path') == '.')
    .map((e) => e.getAttribute('domain') ?? '')
    .toSet();

// ---------- YAML helpers ----------

YamlMap _jobs(YamlMap workflow) => workflow['jobs'] as YamlMap;

YamlMap _job(YamlMap workflow, String id) {
  final job = _jobs(workflow)[id];
  expect(job, isNotNull, reason: '找不到 job $id');
  return job as YamlMap;
}

List<YamlMap> _steps(YamlMap workflow, String id) =>
    (_job(workflow, id)['steps'] as YamlList).cast<YamlMap>().toList();

String _run(YamlMap step) => (step['run'] ?? '').toString();

/// job 子樹內所有 scalar（key 與 value），供禁用字串掃描
Iterable<String> _scalars(Object? node) sync* {
  if (node is YamlMap) {
    for (final entry in node.entries) {
      yield entry.key.toString();
      yield* _scalars(entry.value);
    }
  } else if (node is YamlList) {
    for (final item in node) {
      yield* _scalars(item);
    }
  } else if (node != null) {
    yield node.toString();
  }
}

List<String> _needs(YamlMap job) {
  final needs = job['needs'];
  if (needs == null) return const [];
  if (needs is YamlList) return needs.map((n) => n.toString()).toList();
  return [needs.toString()];
}

void main() {
  final manifest =
      XmlDocument.parse(_read('android/app/src/main/AndroidManifest.xml'));
  final gradle = _read('android/app/build.gradle.kts');
  final distribute =
      loadYaml(_read('.github/workflows/distribute.yml')) as YamlMap;
  final release = loadYaml(_read('.github/workflows/release.yml')) as YamlMap;

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
      expect(
        Directory('android/app/src/main/kotlin/com/vibesync/vibesync')
            .existsSync(),
        isFalse,
        reason: '舊 com.vibesync.vibesync 目錄應已移除',
      );
    });

    test('manifest launcher 指向 .MainActivity（由 namespace 解析）', () {
      final main = _activityByName(manifest, '.MainActivity');
      final launcher = main.findElements('intent-filter').where(
            (f) => _hasCategory(f, 'android.intent.category.LAUNCHER'),
          );
      expect(launcher, hasLength(1));
    });
  });

  group('AND-03／P1-1 label 與深連結分流契約', () {
    test('App label 是 VibeSync', () {
      final application =
          manifest.rootElement.findElements('application').single;
      expect(_attr(application, 'label'), 'VibeSync');
    });

    test('CallbackActivity 是 $_scheme://$_oauthHost 唯一擁有者', () {
      final callback = _activityByName(
        manifest,
        'com.linusu.flutter_web_auth_2.CallbackActivity',
      );
      expect(_attr(callback, 'exported'), 'true');
      expect(_schemeHosts(callback), {_oauthHost});

      for (final activity in _activities(manifest)) {
        if (identical(activity, callback)) continue;
        expect(
          _schemeHosts(activity).contains(_oauthHost),
          isFalse,
          reason:
              '$_oauthHost 只能屬於 CallbackActivity，否則 OAuth 回跳會撞 activity 選擇器',
        );
      }
    });

    test('MainActivity 是 $_scheme://$_emailHost 唯一擁有者（email 深連結）', () {
      final main = _activityByName(manifest, '.MainActivity');
      expect(_schemeHosts(main), {_emailHost});

      final emailFilter = main.findElements('intent-filter').where(
            (f) => f
                .findElements('data')
                .any((d) => _attr(d, 'host') == _emailHost),
          );
      expect(emailFilter, hasLength(1));
      expect(
        _hasCategory(emailFilter.single, 'android.intent.category.BROWSABLE'),
        isTrue,
        reason: '瀏覽器／郵件 App 開啟需要 BROWSABLE',
      );
      expect(
        _hasCategory(emailFilter.single, 'android.intent.category.DEFAULT'),
        isTrue,
      );

      for (final activity in _activities(manifest)) {
        if (identical(activity, main)) continue;
        expect(
          _schemeHosts(activity).contains(_emailHost),
          isFalse,
          reason: '$_emailHost 只能屬於 MainActivity，否則密碼重設連結會被吞掉',
        );
      }
    });

    test('冷暖路由：MainActivity exported 且 singleTop（暖啟走 onNewIntent）',
        () {
      final main = _activityByName(manifest, '.MainActivity');
      expect(_attr(main, 'exported'), 'true');
      expect(
        _attr(main, 'launchMode'),
        'singleTop',
        reason: '暖啟時 login-callback 必須進既有實例的 onNewIntent，不得疊新實例',
      );
    });

    test('Dart 端 redirect 契約與 manifest 一致', () {
      final environment = _read('lib/core/config/environment.dart');
      expect(environment, contains("'$_scheme://$_emailHost'"));
      expect(environment, contains("'$_scheme://$_oauthHost'"));

      final socialAuth =
          _read('lib/core/services/social_auth/social_auth_native.dart');
      expect(
        socialAuth,
        contains('AppConfig.oauthRedirectUri'),
        reason: 'OAuth 必須走平台分流的 oauthRedirectUri',
      );
      expect(
        socialAuth.contains("'$_emailHost'"),
        isFalse,
        reason: 'social auth 不得再硬編 login-callback 字串常數',
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
      expect(gradle, contains('missingSigningKeys'));
    });

    test('keystore 與 key.properties 不進版控', () {
      final gitignore = _read('android/.gitignore');
      expect(gitignore, contains('key.properties'));
      expect(gitignore, contains('*.jks'));
    });

    test('P1-3 AAB gate：jarsigner 完整性＋釘版 bundletool 語意對帳', () {
      final gate = _read('tools/preflight/check-android-signing.sh');
      expect(gate, contains('jarsigner -verify'));
      expect(gate, contains('unsigned entries'));
      expect(gate, contains('BUNDLETOOL_VERSION="1.18.3"'));
      expect(
        gate,
        contains(
          'BUNDLETOOL_SHA256='
          '"a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29"',
        ),
      );
      expect(gate, contains('dump manifest'));
      expect(
        gate.contains(r'unzip -p "$artifact" base/manifest'),
        isFalse,
        reason: '位元組層級 grep 粗檢應已被 bundletool 語意抽取取代',
      );
    });

    test('P1-3 負向驗證腳本存在且涵蓋 tampered 與 wrong-package', () {
      final script =
          _read('tools/android/signing-gate-negative-check.sh');
      expect(script, contains('expect_gate_fail'));
      expect(script, contains('ANDROID_EXPECTED_PACKAGE=com.wrong.package'));
      expect(script, contains('zip -q'));
    });
  });

  group('AND-04／P1-5 backup fail-closed（官方九個 domain）', () {
    const domains = {
      'root',
      'file',
      'database',
      'sharedpref',
      'external',
      'device_root',
      'device_file',
      'device_database',
      'device_sharedpref',
    };

    test('manifest 關閉備份並掛上兩份 rules', () {
      final application =
          manifest.rootElement.findElements('application').single;
      expect(_attr(application, 'allowBackup'), 'false');
      expect(_attr(application, 'fullBackupContent'), '@xml/backup_rules');
      expect(
        _attr(application, 'dataExtractionRules'),
        '@xml/data_extraction_rules',
      );
    });

    test('backup_rules.xml 排除全部九個 domain 且無 include', () {
      final doc = XmlDocument.parse(
        _read('android/app/src/main/res/xml/backup_rules.xml'),
      );
      final root = doc.rootElement;
      expect(root.name.local, 'full-backup-content');
      expect(_excludedDomains(root), domains);
      expect(root.findElements('include'), isEmpty,
          reason: 'fail-closed：不得有任何 include');
    });

    test('data_extraction_rules.xml 兩個區塊都排除全部九個 domain', () {
      final doc = XmlDocument.parse(
        _read('android/app/src/main/res/xml/data_extraction_rules.xml'),
      );
      for (final section in ['cloud-backup', 'device-transfer']) {
        final element = doc.rootElement.findElements(section).single;
        expect(_excludedDomains(element), domains, reason: '$section 排除不齊');
        expect(element.findElements('include'), isEmpty,
            reason: 'fail-closed：$section 不得有 include');
      }
    });
  });

  group('CI-01／P1-2／P1-4／P1-7 distribute workflow 結構契約', () {
    test('build-android 只依賴 flutter-gate，且不含 iOS RevenueCat key', () {
      final job = _job(distribute, 'build-android');
      expect(_needs(job), ['flutter-gate']);
      for (final scalar in _scalars(job)) {
        expect(scalar.contains('appl_'), isFalse,
            reason: 'Android build 不得出現 iOS RevenueCat key');
        expect(scalar.contains('REVENUECAT'), isFalse);
      }
    });

    test('flutter-gate 不含 iOS keyboard contract', () {
      for (final scalar in _scalars(_job(distribute, 'flutter-gate'))) {
        expect(scalar.contains('check-keyboard-contract'), isFalse);
      }
    });

    test('P1-2：同 SHA 產出並驗證簽名 APK＋AAB，兩者都上傳 artifact', () {
      final steps = _steps(distribute, 'build-android');
      final runs = steps.map(_run).toList();
      expect(
        runs.any((r) => r.contains('flutter build apk --release')),
        isTrue,
      );
      expect(
        runs.any((r) => r.contains('flutter build appbundle --release')),
        isTrue,
      );
      expect(
        runs.where((r) => r.contains('--dart-define=GIT_SHA=')),
        hasLength(2),
        reason: 'APK 與 AAB 都要蓋上 exact SHA',
      );
      expect(
        runs.any((r) => r.contains('check-android-signing.sh keystore')),
        isTrue,
      );
      expect(
        runs.any((r) => r.contains(
            'check-android-signing.sh artifact build/app/outputs/flutter-apk/app-release.apk')),
        isTrue,
      );
      expect(
        runs.any((r) => r.contains(
            'check-android-signing.sh artifact build/app/outputs/bundle/release/app-release.aab')),
        isTrue,
      );
      expect(
        runs.any((r) => r.contains('signing-gate-negative-check.sh')),
        isTrue,
        reason: 'P1-3：每次 build 都要跑可執行負向驗證',
      );

      final uploadNames = steps
          .where((s) =>
              s['uses'].toString().startsWith('actions/upload-artifact@'))
          .map((s) => (s['with'] as YamlMap)['name'].toString())
          .toSet();
      expect(uploadNames, {'android-apk', 'android-aab'});
    });

    test('P1-4：emulator runner 釘 v2.38.0 immutable SHA，矩陣含 API 24＋36',
        () {
      final smoke = _job(distribute, 'android-install-smoke');
      expect(_needs(smoke), ['build-android']);

      final emulatorSteps = _steps(distribute, 'android-install-smoke')
          .where((s) => s['uses']
              .toString()
              .startsWith('ReactiveCircus/android-emulator-runner@'))
          .toList();
      expect(emulatorSteps, hasLength(1));
      expect(
        emulatorSteps.single['uses'].toString(),
        startsWith(
          'ReactiveCircus/android-emulator-runner@'
          'a421e43855164a8197daf9d8d40fe71c6996bb0d',
        ),
      );

      final matrixInclude =
          ((smoke['strategy'] as YamlMap)['matrix'] as YamlMap)['include']
              as YamlList;
      final apiLevels = matrixInclude
          .map((entry) => (entry as YamlMap)['api-level'] as int)
          .toSet();
      expect(apiLevels, {24, 36});
    });

    test('P1-7：Firebase 派發獨立成 job，且必須等兩個 smoke 變體都綠', () {
      final firebase = _job(distribute, 'firebase-distribute');
      expect(_needs(firebase), ['android-install-smoke']);

      final firebaseSteps = _steps(distribute, 'firebase-distribute');
      expect(
        firebaseSteps.any((s) => s['uses']
            .toString()
            .startsWith('wzieba/Firebase-Distribution-Github-Action@')),
        isTrue,
      );

      // build-android 本身不得再直接派發 Firebase
      for (final step in _steps(distribute, 'build-android')) {
        expect(
          step['uses'].toString().contains('Firebase-Distribution'),
          isFalse,
          reason: '未通過 smoke 的 build 絕不可派發',
        );
      }
    });
  });

  group('CI-01／P1-6 release workflow 結構契約', () {
    test('release 仍為手動觸發（無 push trigger）', () {
      // YAML 1.1 會把裸鍵 on 解析成 true，兩種都接
      final trigger = (release['on'] ?? release[true]) as YamlMap;
      expect(trigger.keys.map((k) => k.toString()), ['workflow_dispatch']);
    });

    test('release-android 不被 iOS 前置擋，且不含 iOS RevenueCat key', () {
      final job = _job(release, 'release-android');
      expect(_needs(job), ['production-preflight', 'flutter-gate']);
      for (final scalar in _scalars(job)) {
        expect(scalar.contains('appl_'), isFalse);
        expect(scalar.contains('REVENUECAT'), isFalse);
      }
    });

    test('共同 preflight 不含 iOS keyboard／RevenueCat 檢查', () {
      for (final scalar in _scalars(_job(release, 'production-preflight'))) {
        expect(scalar.contains('check-keyboard-contract'), isFalse);
        expect(scalar.contains('check-revenuecat-secret-smoke'), isFalse);
      }
    });

    test('P1-6：release-android 自己跑 build_runner，且在 appbundle 之前', () {
      final runs = _steps(release, 'release-android').map(_run).toList();
      final generateIndex =
          runs.indexWhere((r) => r.contains('build_runner build'));
      final bundleIndex =
          runs.indexWhere((r) => r.contains('flutter build appbundle'));
      expect(generateIndex, greaterThanOrEqualTo(0),
          reason: 'release-android 缺 Generate code');
      expect(bundleIndex, greaterThan(generateIndex));
    });

    test('release-android 掛 SEC-01 與 AND-02 守門', () {
      final runs = _steps(release, 'release-android').map(_run).toList();
      expect(
        runs.any((r) => r.contains('check-android-signing.sh keystore')),
        isTrue,
      );
      expect(
        runs.any((r) => r.contains('check-android-signing.sh artifact')),
        isTrue,
      );
    });
  });
}
