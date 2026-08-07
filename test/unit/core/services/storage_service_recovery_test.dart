// 稽核 #6（2026-08-07）：加密 box 損毀/金鑰不符時，openBoxWithRecovery 必須
// 就地重建讓 App 能啟動，而不是丟 HiveError 進啟動死循環；健康 box 的資料
// 絕不能被重建誤殺。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:vibesync/core/services/storage_service.dart';

void main() {
  late Directory tempDir;
  final keyA = List<int>.generate(32, (i) => i);
  final keyB = List<int>.generate(32, (i) => 31 - i);

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_recovery_test');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  test('健康 box 開啟不動資料', () async {
    final box = await Hive.openBox(
      'healthy_box',
      encryptionCipher: HiveAesCipher(keyA),
    );
    await box.put('k', 'v');
    await box.close();

    final reopened = await StorageService.openBoxWithRecovery(
      'healthy_box',
      cipher: HiveAesCipher(keyA),
    );
    expect(reopened.get('k'), 'v');
  });

  test('box 檔是垃圾位元組 → 重建為可用空 box', () async {
    final file = File('${tempDir.path}/corrupt_box.hive');
    await file.writeAsBytes(List<int>.filled(64, 0x5a));

    final box = await StorageService.openBoxWithRecovery(
      'corrupt_box',
      cipher: HiveAesCipher(keyA),
    );
    expect(box.isEmpty, isTrue);
    await box.put('k', 'v');
    expect(box.get('k'), 'v');
  });

  test('金鑰不符（備份還原情境）→ 重建為可用空 box', () async {
    final box = await Hive.openBox(
      'keyswap_box',
      encryptionCipher: HiveAesCipher(keyA),
    );
    await box.put('k', 'v');
    await box.close();

    final recovered = await StorageService.openBoxWithRecovery(
      'keyswap_box',
      cipher: HiveAesCipher(keyB),
    );
    expect(recovered.isEmpty, isTrue);
    await recovered.put('k2', 'v2');
    expect(recovered.get('k2'), 'v2');
  });
}
