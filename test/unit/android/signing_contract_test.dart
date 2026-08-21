// test/unit/android/signing_contract_test.dart
// AND-02（release 簽名 fail-closed）與 SEC-01（既有 secrets 非機密驗證）
// 的靜態守門。動態行為由 CI 的 keystore／artifact gate 與
// signing-gate-negative-check.sh 提供可執行證據。
import 'package:flutter_test/flutter_test.dart';

import 'android_contract_helpers.dart';

void main() {
  final gradle = readRepoFile('android/app/build.gradle.kts');

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
      final gitignore = readRepoFile('android/.gitignore');
      expect(gitignore, contains('key.properties'));
      expect(gitignore, contains('*.jks'));
    });

    test('AAB gate：jarsigner 完整性＋釘版 bundletool 語意對帳', () {
      final gate = readRepoFile('tools/preflight/check-android-signing.sh');
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
    });

    test('gate 含效期守門、指紋輸出與 signer 對帳', () {
      final gate = readRepoFile('tools/preflight/check-android-signing.sh');
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

    test('SEC-01：gate 不印 alias（GitHub secret）與 Owner，只放行效期與指紋', () {
      final gate = readRepoFile('tools/preflight/check-android-signing.sh');
      expect(gate.contains('Alias name:'), isFalse,
          reason: 'alias 是 GitHub secret，任何輸出路徑都不得含它');
      expect(gate, contains('grep -E "Valid from:|SHA256:|SHA-256"'));
    });

    test('負向驗證涵蓋 tampered、wrong-package、wrong-fingerprint', () {
      final script =
          readRepoFile('tools/android/signing-gate-negative-check.sh');
      expect(script, contains('expect_gate_fail'));
      expect(script, contains('ANDROID_EXPECTED_PACKAGE=com.wrong.package'));
      expect(script, contains('ANDROID_KEYSTORE_SHA256='));
      expect(script, contains('zip -q'));
    });

    test('簽名產生腳本共用且對無效 Base64 fail closed（SEC-01 已知風險）', () {
      final setup = readRepoFile('tools/android/setup-release-signing.sh');
      expect(setup, contains('base64 -d'));
      expect(
        setup,
        contains('不是有效 Base64'),
        reason: 'ANDROID_KEYSTORE 曾是無效 Base64（run 32495993539），'
            '必須明確 fail closed 並停在 SEC-01 gate',
      );
      for (final workflow in [
        '.github/workflows/distribute.yml',
        '.github/workflows/release.yml',
      ]) {
        expect(
          readRepoFile(workflow),
          contains('tools/android/setup-release-signing.sh'),
          reason: '$workflow 必須走共用簽名腳本，不得各自複製邏輯',
        );
      }
    });
  });
}
