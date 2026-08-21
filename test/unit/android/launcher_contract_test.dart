// test/unit/android/launcher_contract_test.dart
// AND-01：launcher package 對齊 com.vibesync.app 的靜態守門。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'android_contract_helpers.dart';

void main() {
  final manifest = loadAndroidManifest();
  final gradle = readRepoFile('android/app/build.gradle.kts');

  group('AND-01 launcher package 對齊', () {
    test('namespace 與 applicationId 凍結為 $kAndroidPackage', () {
      expect(gradle, contains('namespace = "$kAndroidPackage"'));
      expect(gradle, contains('applicationId = "$kAndroidPackage"'));
    });

    test('MainActivity Kotlin 檔位於對應 package 路徑', () {
      final kotlin = readRepoFile(
        'android/app/src/main/kotlin/com/vibesync/app/MainActivity.kt',
      );
      expect(kotlin, contains('package $kAndroidPackage'));
      expect(kotlin, contains('class MainActivity : FlutterActivity()'));
      expect(
        Directory('android/app/src/main/kotlin/com/vibesync/vibesync')
            .existsSync(),
        isFalse,
        reason: '舊 com.vibesync.vibesync 目錄應已移除',
      );
    });

    test('manifest launcher 指向 .MainActivity（由 namespace 解析）', () {
      final main = activityByName(manifest, '.MainActivity');
      final launcher = main.findElements('intent-filter').where(
            (f) => hasCategory(f, 'android.intent.category.LAUNCHER'),
          );
      expect(launcher, hasLength(1));
    });
  });
}
