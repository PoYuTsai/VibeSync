// 情境圖三方對帳（2026-08-25，PR #30 素材到位後的接線守門）。
//
// 三方＝Edge 閘門（moments_image_catalog.ts 的 AVAILABLE_MOMENT_IMAGE_IDS）、
// client 對照表（practice_moment_image.dart，經 resolveMomentImage 公開行為驗）、
// 磁碟上的素材檔案。任何一方漂移的症狀都一樣：**那個題材的圖文貼文
// 永遠安靜地退回純文字，不報錯、不 crash、看不出來**。所以用機械對帳釘死。
//
// Edge 端已有 deno 測試逐檔 stat（moments_image_gate_test.ts）；本檔守的是
// Dart 這一側與跨語言的一致性——deno 測試看不到 Dart 對照表。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_moment_image.dart';

const _assetDir = 'assets/images/practice_moments';
const _edgeCatalog =
    'supabase/functions/practice-chat/moments_image_catalog.ts';

Set<String> _edgeSceneIds() {
  // 讀 Edge 原始碼抽 id（跨語言只能文字對帳；抽法與宣告形狀綁定，
  // 宣告改形狀時這裡會回空集合、下面的斷言會爆，不會安靜漂移）。
  final source = File(_edgeCatalog).readAsStringSync();
  final ids = RegExp(r'"(moment_[a-z_]+)"')
      .allMatches(source)
      .map((m) => m.group(1)!)
      .where((id) => id != 'moment_self_portrait')
      .toSet();
  return ids;
}

void main() {
  final diskIds = Directory(_assetDir)
      .listSync()
      .whereType<File>()
      .map((f) => f.uri.pathSegments.last)
      .where((name) => name.endsWith('.webp'))
      .map((name) => name.substring(0, name.length - '.webp'.length))
      .toSet();

  test('磁碟上恰好 20 張場景圖', () {
    expect(diskIds.length, 20, reason: '實際檔案：$diskIds');
  });

  test('Edge 閘門的場景 id 與磁碟檔案一一對應', () {
    final edgeIds = _edgeSceneIds();
    expect(edgeIds.length, 20,
        reason: 'Edge catalog 抽出的 id 數不對，抽法或宣告形狀變了');
    expect(edgeIds.difference(diskIds), isEmpty,
        reason: 'Edge 開放了沒有檔案的 id（會送進 prompt 但畫面畫不出來）');
    expect(diskIds.difference(edgeIds), isEmpty,
        reason: '磁碟有檔案但 Edge 沒開放（白佔 App 體積）');
  });

  test('client 對照表：每個磁碟 id 都解析成正確路徑的場景圖', () {
    for (final id in diskIds) {
      final source = resolveMomentImage(id);
      expect(source, isA<MomentSceneImage>(),
          reason: 'id $id 在 client 對照表缺席——該題材會安靜退回純文字');
      final path = (source! as MomentSceneImage).assetPath;
      expect(path, '$_assetDir/$id.webp');
      expect(File(path).existsSync(), isTrue, reason: '對照表指向不存在的檔案 $path');
      expect(File(path).lengthSync(), greaterThan(0));
    }
  });

  test('自拍 sentinel 與未知 id 的行為不因開閘而改變', () {
    expect(resolveMomentImage(kMomentSelfPortraitImageId),
        isA<MomentSelfPortraitImage>());
    expect(resolveMomentImage('moment_scene_not_shipped_yet'), isNull,
        reason: '不認得的 id 必須降級純文字（向前相容鐵則）');
    expect(resolveMomentImage(null), isNull);
    expect(resolveMomentImage(''), isNull);
  });

  test('pubspec 掛了素材目錄（漏掛＝release 裝不進 bundle）', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec.contains('- assets/images/practice_moments/'), isTrue);
  });
}
