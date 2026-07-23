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
    expect(text, contains('最近熱度：72'));
    expect(text, contains('興趣：爬山、手沖'));
    expect(text, contains('只可使用以上明確紀錄，不得猜補對方興趣'));
    // 不得帶 analyze 語意的「當前對話優先」句。
    expect(text, isNot(contains('當前對話')));
  });

  test('只有名稱/對話數/日期＝無 actionable signal → promptText null 且無 placeholder header',
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

  test('零對話但有 customNote：必須成功輸出（customNote-only）', () {
    final context = builder.build(
      partner: _partner(customNote: '上週聊到她想去日本'),
      conversations: const [],
    );

    expect(context.hasActionableSignals, isTrue);
    expect(context.hasNoteSignals, isTrue);
    expect(context.promptText, contains('你的備註：上週聊到她想去日本'));
    // 零對話不輸出累計對話行。
    expect(context.promptText, isNot(contains('累計對話')));
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
      partner: _partner(customNote: '🥰' * 1600),
      conversations: const [],
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
}
