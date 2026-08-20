import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/new_topic/domain/services/new_topic_partner_context_builder.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

Partner _partner({
  String id = 'p-1',
  String name = '糖糖',
  String? customNote,
  String ownerUserId = 'u-1',
}) =>
    Partner(
      id: id,
      name: name,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 4, 1),
      ownerUserId: ownerUserId,
      customNote: customNote,
    );

Conversation _convo({
  required String id,
  required DateTime updatedAt,
  int? lastEnthusiasmScore,
  String? snapshotJson,
  String ownerUserId = 'u-1',
}) =>
    Conversation(
      id: id,
      name: 'c-$id',
      messages: const [],
      createdAt: updatedAt,
      updatedAt: updatedAt,
      lastEnthusiasmScore: lastEnthusiasmScore,
      currentRound: 0,
      lastAnalysisSnapshotJson: snapshotJson,
      ownerUserId: ownerUserId,
    );

String _snapshot({
  List<String> interests = const [],
  List<String> traits = const [],
  List<String> notes = const [],
}) =>
    jsonEncode({
      'targetProfile': {
        'provenanceVersion': 1,
        'interests': interests,
        'traits': traits,
        'notes': notes,
      },
    });

void main() {
  late NewTopicPartnerContextBuilder builder;

  setUp(() {
    builder = NewTopicPartnerContextBuilder();
  });

  test('有興趣/熱度訊號時輸出作戰板段落＋grounding 收尾句', () {
    final context = builder.build(
      partner: _partner(),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          lastEnthusiasmScore: 72,
          snapshotJson: _snapshot(interests: ['爬山', '手沖'], traits: ['直率']),
        ),
      ],
    );

    expect(context.hasActionableSignals, isTrue);
    expect(context.hasHeatSignal, isTrue);
    expect(context.hasInterestSignals, isTrue);
    expect(context.hasTraitSignals, isTrue);
    final text = context.promptText!;
    expect(text, contains('[對象作戰板：糖糖]'));
    expect(text, contains('最近互動投入：72'));
    expect(text, contains('不是關係階段或長期特質'));
    expect(text, contains('興趣：爬山、手沖'));
    expect(text, contains('不得猜補未列出的興趣'));
    // 不得帶 analyze 語意的「當前對話優先」句。
    expect(text, isNot(contains('當前對話')));
  });

  test(
      '只有名稱/對話數/日期＝無 actionable signal → promptText null 且無 placeholder header',
      () {
    final context = builder.build(
      partner: _partner(),
      conversations: [
        _convo(id: 'c1', updatedAt: DateTime(2026, 4, 1)),
        _convo(id: 'c2', updatedAt: DateTime(2026, 3, 1)),
      ],
    );

    expect(context.hasActionableSignals, isFalse);
    expect(context.promptText, isNull);
  });

  test('舊版無出處的寵物標籤不可進新話題對象卡', () {
    final legacy = jsonEncode({
      'targetProfile': {
        'interests': ['寵物互動玩笑'],
        'traits': ['幽默自信'],
        'notes': <String>[],
      },
    });
    final context = builder.build(
      partner: _partner(),
      conversations: [
        _convo(
          id: 'legacy',
          updatedAt: DateTime(2026, 8, 20),
          snapshotJson: legacy,
        ),
      ],
    );

    expect(context.promptText, isNull);
    expect(context.hasInterestSignals, isFalse);
    expect(context.hasTraitSignals, isFalse);
  });

  test('零對話但有 allowlisted chips：必須成功輸出', () {
    final context = builder.build(
      partner: _partner(customNote: '輪班、喜歡寵物'),
      conversations: const [],
    );

    expect(context.hasActionableSignals, isTrue);
    expect(context.hasNoteSignals, isTrue);
    expect(
      context.promptText,
      contains('使用者確認的對方資料：輪班工作、喜歡寵物'),
    );
    expect(context.promptText, contains('不能冒充她說過的話'));
    // 零對話不輸出累計對話行。
    expect(context.promptText, isNot(contains('累計對話')));
  });

  test('舊自由文字與關係狀態不算 actionable signal', () {
    final context = builder.build(
      partner: _partner(customNote: '上週聊到她想去日本、剛認識'),
      conversations: const [],
    );

    expect(context.hasActionableSignals, isFalse);
    expect(context.hasNoteSignals, isFalse);
    expect(context.promptText, isNull);
  });

  test('customNote 缺席才用近期 aggregate notes（最多 5 則）', () {
    final context = builder.build(
      partner: _partner(),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          snapshotJson: _snapshot(
            notes: ['n1', 'n2', 'n3', 'n4', 'n5', 'n6', 'n7'],
          ),
        ),
      ],
    );

    expect(context.hasNoteSignals, isTrue);
    final text = context.promptText!;
    expect(text, contains('過往備註：'));
    expect(text, isNot(contains('你的備註')));
  });

  test('owner mismatch 回 empty（blocked）', () {
    final context = builder.build(
      partner: _partner(ownerUserId: 'u-1'),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          ownerUserId: 'u-2',
          snapshotJson: _snapshot(interests: ['爬山']),
        ),
      ],
    );

    expect(context.hasActionableSignals, isFalse);
    expect(context.promptText, isNull);
  });

  test('grapheme cap 1500／code-unit cap 2000', () {
    final context = builder.build(
      partner: _partner(),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          snapshotJson: _snapshot(notes: ['🥰' * 1600]),
        ),
      ],
    );

    final text = context.promptText!;
    expect(
      text.characters.length,
      lessThanOrEqualTo(NewTopicPartnerContextBuilder.kHardCharCap),
    );
    expect(
      text.length,
      lessThanOrEqualTo(NewTopicPartnerContextBuilder.kServerCodeUnitCap),
    );
  });

  test('不可信 customNote 不會遮掉有出處的 aggregate notes', () {
    final context = builder.build(
      partner: _partner(customNote: '想約出來見面'),
      conversations: [
        _convo(
          id: 'c1',
          updatedAt: DateTime(2026, 4, 1),
          snapshotJson: _snapshot(notes: const ['她明說喜歡旅行']),
        ),
      ],
    );

    expect(context.promptText, isNot(contains('想約出來見面')));
    expect(context.promptText, contains('過往備註：她明說喜歡旅行'));
  });
}
