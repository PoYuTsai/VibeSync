// test/unit/android/ci_workflow_contract_test.dart
// CI-01：Android build／install-smoke 與 iOS keyboard／iOS RevenueCat key
// 前置解耦的 workflow 結構契約，加上 AND-02／AND-03 證據鏈在 CI 的接線。
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'android_contract_helpers.dart';

void main() {
  final distribute = loadWorkflow('.github/workflows/distribute.yml');
  final release = loadWorkflow('.github/workflows/release.yml');

  group('CI-01 distribute workflow 結構契約', () {
    test('build-android 只依賴 flutter-gate，且只接明確 Android key', () {
      final job = workflowJob(distribute, 'build-android');
      expect(jobNeeds(job), ['flutter-gate']);
      for (final scalar in yamlScalars(job)) {
        expect(scalar.contains('appl_'), isFalse,
            reason: 'Android build 不得出現 iOS RevenueCat key');
        expect(scalar.contains('REVENUECAT_PROD_KEY'), isFalse);
        expect(scalar.contains('REVENUECAT_API_KEY'), isFalse);
      }
      final runs = jobSteps(distribute, 'build-android').map(stepRun).toList();
      expect(
        runs.where(
            (run) => run.contains('--dart-define=REVENUECAT_ANDROID_API_KEY=')),
        hasLength(2),
        reason: 'APK 與 AAB 都要只傳明確 Android public key（可為空值）',
      );
      expect(
        yamlScalars(job)
            .where((scalar) => scalar.contains('REVENUECAT_ANDROID_API_KEY')),
        isNotEmpty,
      );
    });

    test('flutter-gate 不含 iOS keyboard contract；獨立 gate 只擋 build-ios', () {
      for (final scalar
          in yamlScalars(workflowJob(distribute, 'flutter-gate'))) {
        expect(scalar.contains('check-keyboard-contract'), isFalse);
      }
      final iosGate = workflowJob(distribute, 'ios-keyboard-gate');
      expect(
        yamlScalars(iosGate).any((s) => s.contains('check-keyboard-contract')),
        isTrue,
      );
      final buildIos = workflowJob(distribute, 'build-ios');
      expect(jobNeeds(buildIos),
          containsAll(['flutter-gate', 'ios-keyboard-gate']));

      // gate 的 if 必須與 build-ios 完全一致：手動 platform=android 時
      // gate 直接 skip，不會因 iOS gate 執行而讓整個 workflow 紅
      final gateIf = (iosGate['if'] ?? '').toString();
      expect(gateIf, isNotEmpty, reason: 'ios-keyboard-gate 缺 if 平台閘門');
      expect(gateIf, (buildIos['if'] ?? '').toString());
      expect(gateIf, contains("inputs.platform == 'ios'"));
      expect(
        gateIf.contains("inputs.platform == 'android'"),
        isFalse,
        reason: 'iOS gate 不得在 android-only dispatch 執行',
      );
      expect(
        jobNeeds(workflowJob(distribute, 'build-android')),
        isNot(contains('ios-keyboard-gate')),
        reason: 'Android 不得被 iOS keyboard gate 擋住',
      );
    });

    test('build-ios 明確注入已核對的 iOS public key，不讀 server secret', () {
      final job = workflowJob(distribute, 'build-ios');
      expect(
        yamlScalars(job),
        contains('appl_ZYVwxdvbEIAHxYUEHhdVkVLrkdY'),
      );
      expect(
        yamlScalars(job).any(
          (scalar) =>
              scalar.contains('REVENUECAT_IOS_API_KEY') ||
              scalar.contains('REVENUECAT_IOS_PUBLIC_SDK_KEY') ||
              scalar.contains('REVENUECAT_PROD_KEY'),
        ),
        isFalse,
        reason: 'iOS client build 不得讀 server／未知 secret input',
      );
      expect(
        yamlScalars(job).any(
          (scalar) => scalar.contains('secrets.REVENUECAT_IOS_PUBLIC_SDK_KEY'),
        ),
        isFalse,
        reason: '不存在的 iOS public key secret 不得成為 build prerequisite',
      );
      expect(
        yamlScalars(job).any((scalar) => scalar == 'REVENUECAT_KEY'),
        isTrue,
      );
      final runs = jobSteps(distribute, 'build-ios').map(stepRun).toList();
      expect(
        runs.any((run) => run
            .contains(r'--dart-define=REVENUECAT_API_KEY="$REVENUECAT_KEY"')),
        isTrue,
      );
    });

    test('同 SHA 產出並驗證簽名 APK＋AAB，證據鏈完整', () {
      final steps = jobSteps(distribute, 'build-android');
      final runs = steps.map(stepRun).toList();
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
        reason: '每次 build 都要跑可執行負向驗證',
      );
      expect(
        runs.any((r) => r.contains('install-smoke-negative-check.sh')),
        isTrue,
        reason: 'ClassNotFound 掃描的 fail-closed 迴歸測試要進 CI',
      );

      // merged manifest：先負向 harness（守門壞掉先紅、不假綠），再對
      // 真產物跑語意守門
      final negativeIndex = runs.indexWhere(
        (r) => r.contains('tools/android/manifest-gate-negative-check.sh'),
      );
      final gateIndex = runs.indexWhere(
        (r) => r.contains('python3 tools/android/assert-merged-manifest.py '
            'merged-release-AndroidManifest.xml'),
      );
      expect(negativeIndex, greaterThanOrEqualTo(0),
          reason: 'manifest gate 負向 harness 要進 CI');
      expect(gateIndex, greaterThan(negativeIndex),
          reason: '負向 harness 必須先於語意守門執行，守門壞掉時先紅');

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

    test('keystore 指紋接進 APK/AAB signer 對帳（distribute）', () {
      final steps = jobSteps(distribute, 'build-android');
      final keystoreStep = steps.where(
        (s) => stepRun(s).contains('check-android-signing.sh keystore'),
      );
      expect(keystoreStep, hasLength(1));
      expect(keystoreStep.single['id'], 'keystore-gate',
          reason: '指紋要從 step outputs 流進 artifact 驗簽步驟');

      final artifactSteps = steps
          .where(
              (s) => stepRun(s).contains('check-android-signing.sh artifact'))
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

    test('install smoke 涵蓋唯一 CallbackActivity owner 與 fail-closed 掃描', () {
      final smoke = readRepoFile('tools/android/install-smoke.sh');
      expect(smoke, contains('resolve-activity'));
      expect(smoke, contains('assert_unique_callback_owner'));
      expect(
        smoke,
        contains('ResolverActivity'),
        reason: '要擋 chooser（深連結唯一擁有者被打破時）',
      );
      expect(
        smoke,
        contains('PID'),
        reason: 'callback 後必須同 PID（程序不 crash 重啟）',
      );
      for (final line in smoke.split('\n')) {
        expect(
          RegExp(r'adb .*\|\s*grep').hasMatch(line),
          isFalse,
          reason: 'pipefail 下 grep -q 早退會讓上游 SIGPIPE 141 漏報：$line',
        );
      }
      final negative =
          readRepoFile('tools/android/install-smoke-negative-check.sh');
      expect(negative, contains('ClassNotFoundException'));
      expect(negative, contains('fail closed'));
      expect(negative, contains('wrong-owner'));
      expect(negative, contains('ResolverActivity'));
    });

    test('emulator runner 釘 v2.38.0 immutable SHA，矩陣含 API 24＋36', () {
      final smoke = workflowJob(distribute, 'android-install-smoke');
      expect(jobNeeds(smoke), ['build-android']);

      final emulatorSteps = jobSteps(distribute, 'android-install-smoke')
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

    test('Firebase 派發獨立成 job，且必須等兩個 smoke 變體都綠', () {
      final firebase = workflowJob(distribute, 'firebase-distribute');
      expect(jobNeeds(firebase), ['android-install-smoke']);

      final firebaseSteps = jobSteps(distribute, 'firebase-distribute');
      expect(
        firebaseSteps.any((s) => s['uses']
            .toString()
            .startsWith('wzieba/Firebase-Distribution-Github-Action@')),
        isTrue,
      );

      // build-android 本身不得再直接派發 Firebase
      for (final step in jobSteps(distribute, 'build-android')) {
        expect(
          step['uses'].toString().contains('Firebase-Distribution'),
          isFalse,
          reason: '未通過 smoke 的 build 絕不可派發',
        );
      }

      // SEC-01：secret 檢查只回報存在與否，不印子字串或長度
      final secretCheck = firebaseSteps.where(
        (s) => stepRun(s).contains('FIREBASE_ANDROID_APP_ID is not set'),
      );
      expect(secretCheck, hasLength(1));
      expect(
        stepRun(secretCheck.single).contains(':0:20'),
        isFalse,
        reason: '不得印 secret 子字串',
      );
      final identityStep = firebaseSteps.where(
        (s) => stepRun(s).contains('mobilesdk_app_id'),
      );
      expect(identityStep, hasLength(1),
          reason: 'secret 的 Firebase app ID 要對帳版控 google-services.json');
    });
  });

  group('CI-01 release workflow 結構契約', () {
    test('release 仍為手動觸發（無 push trigger）', () {
      // YAML 1.1 會把裸鍵 on 解析成 true，兩種都接
      final trigger = (release['on'] ?? release[true]) as YamlMap;
      expect(trigger.keys.map((k) => k.toString()), ['workflow_dispatch']);
    });

    test('release-android 不被 iOS 前置擋，且只接明確 Android key', () {
      final job = workflowJob(release, 'release-android');
      expect(jobNeeds(job), ['production-preflight', 'flutter-gate']);
      for (final scalar in yamlScalars(job)) {
        expect(scalar.contains('appl_'), isFalse);
        expect(scalar.contains('REVENUECAT_PROD_KEY'), isFalse);
        expect(scalar.contains('REVENUECAT_API_KEY'), isFalse);
      }
      expect(
        yamlScalars(job)
            .where((scalar) => scalar.contains('REVENUECAT_ANDROID_API_KEY')),
        isNotEmpty,
      );
      expect(
        jobSteps(release, 'release-android').map(stepRun).where(
            (run) => run.contains('--dart-define=REVENUECAT_ANDROID_API_KEY=')),
        hasLength(1),
      );
    });

    test('共同 preflight 不含 iOS keyboard／RevenueCat 檢查', () {
      for (final scalar
          in yamlScalars(workflowJob(release, 'production-preflight'))) {
        expect(scalar.contains('check-keyboard-contract'), isFalse);
        expect(scalar.contains('check-revenuecat-secret-smoke'), isFalse);
      }
      expect(
        jobNeeds(workflowJob(release, 'release-ios')),
        containsAll(['production-preflight', 'ios-preflight', 'flutter-gate']),
      );
    });

    test('release-ios 明確注入已核對的 iOS public key，不讀 server secret', () {
      final job = workflowJob(release, 'release-ios');
      expect(
        yamlScalars(job),
        contains('appl_ZYVwxdvbEIAHxYUEHhdVkVLrkdY'),
      );
      expect(
        yamlScalars(job).any(
          (scalar) =>
              scalar.contains('REVENUECAT_IOS_API_KEY') ||
              scalar.contains('REVENUECAT_IOS_PUBLIC_SDK_KEY') ||
              scalar.contains('REVENUECAT_PROD_KEY'),
        ),
        isFalse,
        reason: 'iOS client build 不得讀 server／未知 secret input',
      );
      expect(
        yamlScalars(job).any(
          (scalar) => scalar.contains('secrets.REVENUECAT_IOS_PUBLIC_SDK_KEY'),
        ),
        isFalse,
        reason: '不存在的 iOS public key secret 不得成為 build prerequisite',
      );
      expect(
        yamlScalars(job).any((scalar) => scalar == 'REVENUECAT_KEY'),
        isTrue,
      );
      final runs = jobSteps(release, 'release-ios').map(stepRun).toList();
      expect(
        runs.any((run) => run
            .contains(r'--dart-define=REVENUECAT_API_KEY="$REVENUECAT_KEY"')),
        isTrue,
      );

      final smokeStep = jobSteps(release, 'ios-preflight').singleWhere(
        (step) => stepRun(step).contains('check-revenuecat-secret-smoke.ps1'),
      );
      final smokeEnv = smokeStep['env'] as YamlMap;
      expect(
        smokeEnv['REVENUECAT_IOS_API_KEY'].toString(),
        contains('secrets.REVENUECAT_IOS_API_KEY'),
        reason: 'server smoke 必須繼續使用 Edge Functions server key',
      );
      expect(
        smokeEnv.containsKey('REVENUECAT_IOS_PUBLIC_SDK_KEY'),
        isFalse,
        reason: 'server smoke 不得改吃 client public SDK key',
      );
      expect(
        yamlScalars(job)
            .any((scalar) => scalar.contains('REVENUECAT_IOS_API_KEY')),
        isFalse,
        reason: 'iOS client build 不得注入 server key',
      );
    });

    test('release-android 自己跑 build_runner，且在 appbundle 之前', () {
      final runs = jobSteps(release, 'release-android').map(stepRun).toList();
      final generateIndex =
          runs.indexWhere((r) => r.contains('build_runner build'));
      final bundleIndex =
          runs.indexWhere((r) => r.contains('flutter build appbundle'));
      expect(generateIndex, greaterThanOrEqualTo(0),
          reason: 'release-android 缺 Generate code');
      expect(bundleIndex, greaterThan(generateIndex));
    });

    test('release-android 掛 SEC-01 與 AND-02 守門，含 signer 指紋對帳', () {
      final steps = jobSteps(release, 'release-android');
      final runs = steps.map(stepRun).toList();
      expect(
        runs.any((r) => r.contains('check-android-signing.sh keystore')),
        isTrue,
      );
      final artifactSteps = steps
          .where(
              (s) => stepRun(s).contains('check-android-signing.sh artifact'))
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

    test('Android fastlane 走釘版 Gemfile＋bundle exec，無 ad-hoc gem install', () {
      final gemfile = readRepoFile('android/Gemfile');
      expect(gemfile, contains('gem "fastlane", "2.238.0"'));

      // 真 Bundler lock 必須提交且釘住 fastlane 與 CI 平台
      final lock = readRepoFile('android/Gemfile.lock');
      expect(lock, contains('fastlane (2.238.0)'));
      expect(lock, contains('BUNDLED WITH'));
      expect(
        lock,
        contains('x86_64-linux'),
        reason: 'release-android 跑 ubuntu-latest，lock 需含 x86_64-linux 平台',
      );

      final runs = jobSteps(release, 'release-android').map(stepRun).toList();
      expect(
        runs.any((r) => r.contains('bundle exec fastlane internal')),
        isTrue,
      );
      expect(
        runs.any((r) => r.contains('gem install fastlane')),
        isFalse,
        reason: 'fastlane 版本由 Gemfile 釘住，不得 ad-hoc gem install',
      );

      final setupRuby = jobSteps(release, 'release-android').where(
        (s) => s['uses'].toString().startsWith('ruby/setup-ruby@'),
      );
      expect(setupRuby, hasLength(1));
      final withMap = setupRuby.single['with'] as YamlMap;
      expect(withMap['bundler-cache'], true);
      expect(withMap['working-directory'].toString(), 'android');
    });
  });
}
