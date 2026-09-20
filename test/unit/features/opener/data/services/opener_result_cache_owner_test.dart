// R2b（第一輪獨立複核）：saveDraft 內部 _saveDrafts→await→saveLatest 會重新解析
// owner；A 帳號的結果不得因中途切帳而寫進 B 的 draft／latest key。
// 這裡驗的是真正的儲存 key，不是 controller 狀態。
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/opener/data/services/opener_result_cache_service.dart';
import 'package:vibesync/features/opener/data/services/opener_service.dart';

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_opener_result_cache_owner');
  });
  setUp(() async {
    await Hive.openBox(AppConstants.settingsBox);
  });
  tearDown(() async {
    await Hive.deleteBoxFromDisk(AppConstants.settingsBox);
  });
  tearDownAll(() async {
    await Hive.close();
  });

  test('saveDraft 期間帳號 A→B：A 的結果不會寫到 B 的 drafts／latest key', () async {
    // 第一次解析（saveDraft 起點）是 A；之後每次再解析都回 B，模擬 await 期間切帳。
    var resolves = 0;
    final cache = OpenerResultCacheService(
      ownerIdResolver: () => resolves++ == 0 ? 'user-a' : 'user-b',
    );
    const result = OpenerResult(openers: {'extend': 'A 的句子'}, requestId: 'req-a');
    await cache.saveDraft(result: result);

    final box = Hive.box(AppConstants.settingsBox);
    expect(box.get('opener_drafts_v1:user-b'), isNull, reason: 'B 的草稿清單不得出現 A 的結果');
    expect(box.get('opener_latest_result_v1:user-b'), isNull, reason: 'B 的 latest 不得出現 A 的結果');
    expect(box.get('opener_drafts_v1:user-a'), isNotNull);
    expect(box.get('opener_latest_result_v1:user-a'), isNotNull);
  });

  test('updateDraft 同樣綁定操作起點的帳號', () async {
    final a = OpenerResultCacheService(ownerIdResolver: () => 'user-a');
    final saved = await a.saveDraft(result: const OpenerResult(openers: {'extend': '一'}, requestId: 'r1'));
    var resolves = 0;
    final switching = OpenerResultCacheService(
      ownerIdResolver: () => resolves++ == 0 ? 'user-a' : 'user-b',
    );
    await switching.updateDraft(saved.id, result: const OpenerResult(openers: {'extend': '二'}, requestId: 'r1'));
    final box = Hive.box(AppConstants.settingsBox);
    expect(box.get('opener_drafts_v1:user-b'), isNull);
    expect(a.loadDraft(saved.id)!.result!.openers['extend'], '二');
  });
}
