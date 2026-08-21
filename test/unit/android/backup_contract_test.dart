// test/unit/android/backup_contract_test.dart
// AND-04：fail-closed 備份與資料轉移排除（docs/decisions.md ADR #43）。
// 官方九個 domain 全域 exclude、零 include；allowBackup=false 為主閘。
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'android_contract_helpers.dart';

void main() {
  final manifest = loadAndroidManifest();

  group('AND-04 backup fail-closed（官方九個 domain）', () {
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
      final application = applicationElement(manifest);
      expect(androidAttr(application, 'allowBackup'), 'false');
      expect(androidAttr(application, 'fullBackupContent'), '@xml/backup_rules');
      expect(
        androidAttr(application, 'dataExtractionRules'),
        '@xml/data_extraction_rules',
      );
    });

    test('backup_rules.xml 排除全部九個 domain 且無 include', () {
      final doc = XmlDocument.parse(
        readRepoFile('android/app/src/main/res/xml/backup_rules.xml'),
      );
      final root = doc.rootElement;
      expect(root.name.local, 'full-backup-content');
      expect(excludedDomains(root), domains);
      expect(root.findElements('include'), isEmpty,
          reason: 'fail-closed：不得有任何 include');
    });

    test('data_extraction_rules.xml 兩個區塊都排除全部九個 domain', () {
      final doc = XmlDocument.parse(
        readRepoFile('android/app/src/main/res/xml/data_extraction_rules.xml'),
      );
      for (final section in ['cloud-backup', 'device-transfer']) {
        final element = doc.rootElement.findElements(section).single;
        expect(excludedDomains(element), domains, reason: '$section 排除不齊');
        expect(element.findElements('include'), isEmpty,
            reason: 'fail-closed：$section 不得有 include');
      }
    });

    test('政策入 ADR、驗證步驟入 launch checklist（不另立政策檔）', () {
      expect(
        readRepoFile('docs/decisions.md'),
        contains('ADR #43'),
        reason: 'backup fail-closed 政策必須記錄在 docs/decisions.md',
      );
      expect(
        readRepoFile('docs/launch-readiness-checklist.md'),
        contains('Android 備份／重裝／轉機驗證（AND-04）'),
        reason: '實機驗證步驟必須併入既有 launch checklist',
      );
    });
  });
}
