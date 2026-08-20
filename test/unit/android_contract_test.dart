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
const _callbackHost = 'login-callback';
const _dispatcher = '.AuthCallbackDispatcherActivity';

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
  final matches =
      _activities(manifest).where((a) => _attr(a, 'name') == name).toList();
  expect(matches, hasLength(1), reason: '應恰有一個 $name activity');
  return matches.first;
}

bool _hasCategory(XmlElement filter, String category) =>
    filter.findElements('category').any((c) => _attr(c, 'name') == category);

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

  group('AND-03／P1 修訂：label 與凍結深連結 dispatcher 契約', () {
    test('App label 是 VibeSync', () {
      final application =
          manifest.rootElement.findElements('application').single;
      expect(_attr(application, 'label'), 'VibeSync');
    });

    test('Dispatcher 是 $_scheme://$_callbackHost 唯一擁有者（無 chooser）', () {
      final dispatcher = _activityByName(manifest, _dispatcher);
      expect(_attr(dispatcher, 'exported'), 'true');
      expect(_schemeHosts(dispatcher), {_callbackHost});

      final filter = dispatcher.findElements('intent-filter').single;
      expect(
        _hasCategory(filter, 'android.intent.category.BROWSABLE'),
        isTrue,
        reason: '瀏覽器／郵件 App 開啟需要 BROWSABLE',
      );
      expect(_hasCategory(filter, 'android.intent.category.DEFAULT'), isTrue);

      for (final activity in _activities(manifest)) {
        if (identical(activity, dispatcher)) continue;
        expect(
          _schemeHosts(activity),
          isEmpty,
          reason: '$_scheme 深連結只能屬於 dispatcher，否則會撞 activity 選擇器',
        );
      }
    });

    test('oauth-callback 與 plugin CallbackActivity 已移除（凍結單一 URI）', () {
      final manifestRaw = _read('android/app/src/main/AndroidManifest.xml');
      expect(
        manifestRaw.contains('oauth-callback'),
        isFalse,
        reason: '凍結 URI 是 login-callback，oauth-callback 已廢止',
      );
      expect(
        _activities(manifest).where(
          (a) => (_attr(a, 'name') ?? '').contains('flutter_web_auth_2'),
        ),
        isEmpty,
        reason: 'plugin CallbackActivity 不得再宣告，分流由 dispatcher 負責',
      );
    });

    test('task-hijacking 緩解：Main 與 dispatcher 都是空 taskAffinity', () {
      // 刻意偏離 pinned flutter_web_auth_2 README「移除 taskAffinity」：
      // 空 affinity 擋惡意 app 併 task；轉送正確性由 install smoke 的
      // dumpsys 單實例／單 task 證據扛（理由詳見 manifest 註解）
      expect(_attr(_activityByName(manifest, '.MainActivity'), 'taskAffinity'),
          '');
      expect(_attr(_activityByName(manifest, _dispatcher), 'taskAffinity'), '');
    });

    test('Dispatcher OAuth 收尾不得移除既有 app task（isTaskRoot 守門）', () {
      final kotlin = _read(
        'android/app/src/main/kotlin/com/vibesync/app/'
        'AuthCallbackDispatcherActivity.kt',
      );
      expect(
        kotlin,
        contains('if (isTaskRoot) finishAndRemoveTask() else finish()'),
        reason: '無條件 finishAndRemoveTask 會把含 MainActivity 的 task 整個清掉',
      );
    });

    test('P1-2 seam：Robolectric 測試 seed 真 plugin callbacks map', () {
      final seam = _read(
        'android/app/src/test/kotlin/com/vibesync/app/'
        'AuthCallbackDispatcherActivityTest.kt',
      );
      expect(seam, contains('FlutterWebAuth2Plugin.callbacks[scheme] = fake'));
      expect(seam, contains('"$_scheme"'));
      expect(seam, contains('$_callbackHost#'));
      expect(seam, contains('nextStartedActivity'));
      expect(seam, contains('RobolectricTestRunner'));
    });

    test('冷暖路由：MainActivity exported、singleTop、無 VIEW filter', () {
      final main = _activityByName(manifest, '.MainActivity');
      expect(_attr(main, 'exported'), 'true');
      expect(
        _attr(main, 'launchMode'),
        'singleTop',
        reason: '暖啟時深連結必須進既有實例的 onNewIntent，不得疊新實例',
      );
      expect(
        main
            .findElements('intent-filter')
            .expand((f) => f.findElements('action'))
            .where(
              (a) => _attr(a, 'name') == 'android.intent.action.VIEW',
            ),
        isEmpty,
        reason: 'MainActivity 不得自己接 VIEW，深連結一律經 dispatcher 轉送',
      );
    });

    test('Dispatcher Kotlin：live callback 交回 plugin、否則明確轉送 MainActivity', () {
      final kotlin = _read(
        'android/app/src/main/kotlin/com/vibesync/app/'
        'AuthCallbackDispatcherActivity.kt',
      );
      expect(kotlin, contains('FlutterWebAuth2Plugin.callbacks'));
      expect(kotlin, contains('MainActivity::class.java'));
      expect(kotlin, contains('Intent.ACTION_VIEW'));
      expect(kotlin, contains('FLAG_ACTIVITY_SINGLE_TOP'));
    });

    test('原生路由 log 決定性且非機密（只記 route 與 host）', () {
      final main = _read(
        'android/app/src/main/kotlin/com/vibesync/app/MainActivity.kt',
      );
      expect(main, contains('route=cold'));
      expect(main, contains('route=warm'));
      expect(main, contains('override fun onNewIntent'));

      final dispatcher = _read(
        'android/app/src/main/kotlin/com/vibesync/app/'
        'AuthCallbackDispatcherActivity.kt',
      );
      expect(dispatcher, contains('route=web-auth'));
      expect(dispatcher, contains('route=main'));
      for (final file in [main, dispatcher]) {
        for (final line in file.split('\n')) {
          if (!line.contains('Log.')) continue;
          expect(
            line.contains('toString') || line.contains('query'),
            isFalse,
            reason: 'route log 不得帶 query/fragment（token 不落 log）：$line',
          );
        }
      }
    });

    test('Dart 端 redirect 契約：單一凍結 URI，無 oauth-callback', () {
      final environment = _read('lib/core/config/environment.dart');
      expect(environment, contains("'$_scheme://$_callbackHost'"));
      expect(
        environment.contains('oauth-callback'),
        isFalse,
        reason: 'oauth-callback 已廢止，OAuth 與 email 共用凍結 URI',
      );

      final socialAuth =
          _read('lib/core/services/social_auth/social_auth_native.dart');
      expect(
        socialAuth,
        contains('AppConfig.oauthRedirectUri'),
        reason: 'OAuth 必須走 AppConfig.oauthRedirectUri',
      );
      expect(
        socialAuth.contains("'$_callbackHost'"),
        isFalse,
        reason: 'social auth 不得硬編 callback host 字串常數',
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

    test('P1 修訂：gate 含效期守門、指紋輸出與 signer 對帳', () {
      final gate = _read('tools/preflight/check-android-signing.sh');
      expect(
        gate,
        contains('2033-10-22'),
        reason: 'upload 憑證效期必須晚於 2033-10-22（fail closed）',
      );
      expect(
        gate,
        contains('keystore_sha256='),
        reason: 'normalized 公開 SHA-256 要寫進 GITHUB_OUTPUT 供產物對帳',
      );
      expect(gate, contains('GITHUB_OUTPUT'));
      expect(
        gate,
        contains('ANDROID_KEYSTORE_SHA256'),
        reason: 'artifact 模式要對帳產物 signer SHA-256 與 keystore fingerprint',
      );
      expect(gate, contains('normalize_sha256'));
    });

    test('P2：gate 不印 alias（GitHub secret）與 Owner，只放行效期與指紋', () {
      final gate = _read('tools/preflight/check-android-signing.sh');
      expect(gate.contains('Alias name:'), isFalse,
          reason: 'alias 是 GitHub secret，任何輸出路徑都不得含它');
      expect(gate, contains('grep -E "Valid from:|SHA256:|SHA-256"'));
    });

    test('P1-3 負向驗證涵蓋 tampered、wrong-package、wrong-fingerprint', () {
      final script = _read('tools/android/signing-gate-negative-check.sh');
      expect(script, contains('expect_gate_fail'));
      expect(script, contains('ANDROID_EXPECTED_PACKAGE=com.wrong.package'));
      expect(script, contains('ANDROID_KEYSTORE_SHA256='));
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
      expect(
        runs.any((r) => r.contains('install-smoke-negative-check.sh')),
        isTrue,
        reason: 'P1-1：ClassNotFound 掃描的 fail-closed 迴歸測試要進 CI',
      );
      expect(
        runs.any((r) =>
            r.contains('testReleaseUnitTest') &&
            r.contains('AuthCallbackDispatcherActivityTest')),
        isTrue,
        reason: 'P1-2：dispatcher seam 單元測試要進 CI',
      );
      expect(
        runs.any((r) =>
            r.contains('merged-release-AndroidManifest.xml') &&
            r.contains('com.poyutsai.vibesync')),
        isTrue,
        reason: 'P2：merged manifest 要有語意斷言，不只留檔',
      );

      final uploadNames = steps
          .where((s) =>
              s['uses'].toString().startsWith('actions/upload-artifact@'))
          .map((s) => (s['with'] as YamlMap)['name'].toString())
          .toSet();
      expect(
        uploadNames,
        {'android-apk', 'android-aab', 'android-merged-manifest'},
        reason: '真合併後的 release manifest 要留檔為 CI 證據',
      );
    });

    test('P1 修訂：keystore 指紋接進 APK/AAB signer 對帳（distribute）', () {
      final steps = _steps(distribute, 'build-android');
      final keystoreStep = steps.where(
        (s) => _run(s).contains('check-android-signing.sh keystore'),
      );
      expect(keystoreStep, hasLength(1));
      expect(keystoreStep.single['id'], 'keystore-gate',
          reason: '指紋要從 step outputs 流進 artifact 驗簽步驟');

      final artifactSteps = steps
          .where((s) => _run(s).contains('check-android-signing.sh artifact'))
          .toList();
      expect(artifactSteps, hasLength(2), reason: 'APK 與 AAB 各一');
      for (final step in artifactSteps) {
        expect(
          ((step['env'] as YamlMap?)?['ANDROID_KEYSTORE_SHA256'] ?? '')
              .toString(),
          contains('steps.keystore-gate.outputs.keystore_sha256'),
        );
      }
    });

    test('P1 修訂：firebase-distribute 對帳 secret app ID 與 google-services.json',
        () {
      final steps = _steps(distribute, 'firebase-distribute');
      expect(
        steps.any((s) => s['uses'].toString().startsWith('actions/checkout@')),
        isTrue,
        reason: '要 checkout 才能讀 tracked google-services.json',
      );
      final identityStep = steps.where(
        (s) => _run(s).contains('mobilesdk_app_id'),
      );
      expect(identityStep, hasLength(1));
      expect(
        _run(identityStep.single),
        contains('google-services.json'),
      );
    });

    test('P1 修訂：install smoke 涵蓋深連結唯一解析與冷暖路由', () {
      final smoke = _read('tools/android/install-smoke.sh');
      expect(smoke, contains('$_scheme://$_callbackHost'));
      expect(smoke, contains('AuthCallbackDispatcherActivity'));
      expect(smoke, contains('route=cold'));
      expect(smoke, contains('route=warm'));
      expect(smoke, contains('force-stop'));
      expect(
        smoke,
        contains('ResolverActivity'),
        reason: '要擋 chooser（深連結唯一擁有者被打破時）',
      );
      expect(
        smoke,
        contains('PID'),
        reason: '暖啟必須同 PID（onNewIntent），程序不得重複',
      );
    });

    test('P1-2：smoke 先建既有 Main 再送 callback，dumpsys 計數單實例／單 task', () {
      final smoke = _read('tools/android/install-smoke.sh');
      expect(smoke, contains('dumpsys activity activities'));
      expect(smoke, contains('assert_single_main_and_task'));
      expect(
        smoke.indexOf('MainActivity route=warm'),
        lessThan(smoke.indexOf('adb shell am force-stop')),
        reason: '必須先驗「既有 Main 收 callback 走 onNewIntent」，才做 force-stop 冷啟',
      );
    });

    test('P1-1：smoke 不得把 adb 輸出串進 grep（SIGPIPE 會漏報），且有負向測試', () {
      final smoke = _read('tools/android/install-smoke.sh');
      for (final line in smoke.split('\n')) {
        expect(
          RegExp(r'adb .*\|\s*grep').hasMatch(line),
          isFalse,
          reason: 'pipefail 下 grep -q 早退會讓上游 SIGPIPE 141 漏報：$line',
        );
      }
      final negative = _read('tools/android/install-smoke-negative-check.sh');
      expect(negative, contains('ClassNotFoundException'));
      expect(negative, contains('fail closed'));
      expect(negative, contains('fake'));
    });

    test('P1-4：emulator runner 釘 v2.38.0 immutable SHA，矩陣含 API 24＋36', () {
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

      final matrixInclude = ((smoke['strategy'] as YamlMap)['matrix']
          as YamlMap)['include'] as YamlList;
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

    test('release-android 掛 SEC-01 與 AND-02 守門，含 signer 指紋對帳', () {
      final steps = _steps(release, 'release-android');
      final runs = steps.map(_run).toList();
      expect(
        runs.any((r) => r.contains('check-android-signing.sh keystore')),
        isTrue,
      );
      expect(
        runs.any((r) =>
            r.contains('testReleaseUnitTest') &&
            r.contains('AuthCallbackDispatcherActivityTest')),
        isTrue,
        reason: 'P1-2：Play 通道也要跑 dispatcher seam 單元測試',
      );
      final artifactSteps = steps
          .where((s) => _run(s).contains('check-android-signing.sh artifact'))
          .toList();
      expect(artifactSteps, hasLength(1));
      expect(
        ((artifactSteps.single['env']
                    as YamlMap?)?['ANDROID_KEYSTORE_SHA256'] ??
                '')
            .toString(),
        contains('steps.keystore-gate.outputs.keystore_sha256'),
      );
    });

    test('P1 修訂：Android fastlane 走釘版 Gemfile＋bundle exec，無 ad-hoc gem install',
        () {
      final gemfile = _read('android/Gemfile');
      expect(gemfile, contains('gem "fastlane", "2.238.0"'));

      final runs = _steps(release, 'release-android').map(_run).toList();
      expect(
        runs.any((r) => r.contains('bundle exec fastlane internal')),
        isTrue,
      );
      expect(
        runs.any((r) => r.contains('gem install fastlane')),
        isFalse,
        reason: 'fastlane 版本由 Gemfile 釘住，不得 ad-hoc gem install',
      );

      final setupRuby = _steps(release, 'release-android').where(
        (s) => s['uses'].toString().startsWith('ruby/setup-ruby@'),
      );
      expect(setupRuby, hasLength(1));
      final withMap = setupRuby.single['with'] as YamlMap;
      expect(withMap['bundler-cache'], true);
      expect(withMap['working-directory'].toString(), 'android');
    });
  });
}
