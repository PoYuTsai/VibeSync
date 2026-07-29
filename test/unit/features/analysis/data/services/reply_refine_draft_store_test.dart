import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/analysis/data/services/reply_refine_draft_store.dart';

const _ownerA = '11111111-1111-4111-8111-111111111111';
const _ownerB = '22222222-2222-4222-8222-222222222222';

void main() {
  late Box box;
  late DateTime now;

  setUp(() async {
    Hive.init('./.dart_tool/test_hive_reply_refine_draft');
    box = await Hive.openBox<dynamic>(
      'reply_refine_draft_${DateTime.now().microsecondsSinceEpoch}',
    );
    now = DateTime.utc(2026, 7, 29, 12);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  HiveReplyRefineDraftStore store() =>
      HiveReplyRefineDraftStore(() => box, now: () => now);

  test('存下的最後一版在 24 小時內讀得回來', () async {
    await store().save(
      ownerUserId: _ownerA,
      originText: '  這週要不要一起喝杯咖啡？  ',
      refinedText: '週末有空喝杯咖啡嗎',
      requestId: 'req-1',
    );

    now = now.add(const Duration(hours: 23, minutes: 59));
    final draft = await store().loadFor(
      ownerUserId: _ownerA,
      // 原句前後空白不影響命中。
      originText: '這週要不要一起喝杯咖啡？',
    );

    expect(draft?.refinedText, '週末有空喝杯咖啡嗎');
    expect(draft?.requestId, 'req-1');
  });

  test('超過 24 小時就當作沒有，並把過期的 row 刪掉', () async {
    await store().save(
      ownerUserId: _ownerA,
      originText: '原句',
      refinedText: '調過的',
    );
    final key = box.keys.firstWhere(
      (key) => key.toString().startsWith(HiveReplyRefineDraftStore.storageKeyPrefix),
    );

    now = now.add(const Duration(hours: 24));
    expect(
      await store().loadFor(ownerUserId: _ownerA, originText: '原句'),
      isNull,
    );
    expect(box.containsKey(key), isFalse);
  });

  test('換帳號讀不到別人的草稿', () async {
    await store().save(
      ownerUserId: _ownerA,
      originText: '原句',
      refinedText: '調過的',
    );

    expect(
      await store().loadFor(ownerUserId: _ownerB, originText: '原句'),
      isNull,
    );
    // A 自己的那份不能被 B 的查詢清掉。
    expect(
      (await store().loadFor(ownerUserId: _ownerA, originText: '原句'))
          ?.refinedText,
      '調過的',
    );
  });

  test('壞掉的 row 當作沒有草稿，不 throw、不擋畫面', () async {
    // 這裡和 optimize pending identity 刻意不同：那份讀不出來要 throw，
    // 因為它代表可能已扣過費的身分。
    await box.put(
      '${HiveReplyRefineDraftStore.storageKeyPrefix}broken',
      'not-json',
    );
    await store().save(
      ownerUserId: _ownerA,
      originText: '原句',
      refinedText: '調過的',
    );

    expect(
      (await store().loadFor(ownerUserId: _ownerA, originText: '原句'))
          ?.refinedText,
      '調過的',
    );
    // 存檔時順手掃掉讀不出來的殘骸。
    expect(
      box.containsKey('${HiveReplyRefineDraftStore.storageKeyPrefix}broken'),
      isFalse,
    );
  });

  test('存檔會掃掉其他已過期的草稿，鑰匙不會無限長大', () async {
    await store().save(
      ownerUserId: _ownerA,
      originText: '舊的原句',
      refinedText: '舊的版本',
    );

    now = now.add(const Duration(hours: 25));
    await store().save(
      ownerUserId: _ownerA,
      originText: '新的原句',
      refinedText: '新的版本',
    );

    final refineKeys = box.keys
        .where(
          (key) => key.toString().startsWith(
                HiveReplyRefineDraftStore.storageKeyPrefix,
              ),
        )
        .toList();
    expect(refineKeys, hasLength(1));
    final stored = ReplyRefineDraft.fromJson(
      jsonDecode(box.get(refineKeys.single) as String),
    );
    expect(stored?.refinedText, '新的版本');
  });
}
