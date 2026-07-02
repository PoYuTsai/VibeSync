import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_draw_draft_store.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_draw_draft.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_learning_mode.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_profile.dart';

PracticeDrawDraft sampleDraft() => PracticeDrawDraft(
      sessionId: 'sess-1',
      visiblePracticeThreadId: 'sess-1',
      roundIndex: 1,
      profileId: 'practice_girl_007',
      personaId: 'cool_rational',
      difficulty: 'challenge',
      difficultyPreference: PracticeDifficultyPreference.challenge,
      freeAllowance: 3,
      freeUsed: 1,
      freeRemaining: 2,
      extraCostMessages: 5,
      learningMode: PracticeLearningMode.beginner,
      temperatureScore: 42,
      familiarityScore: 44,
      relationshipStageLabel: '可以聊個人',
      nextResetAt: DateTime.utc(2026, 6, 27, 4),
      createdAt: DateTime.utc(2026, 6, 26, 5),
    );

void main() {
  group('PracticeDrawDraft JSON', () {
    test('toJson / fromJson 來回保值', () {
      final d = sampleDraft();
      final back = PracticeDrawDraft.fromJson(d.toJson());

      expect(back.sessionId, d.sessionId);
      expect(back.visiblePracticeThreadId, d.visiblePracticeThreadId);
      expect(back.roundIndex, d.roundIndex);
      expect(back.profileId, d.profileId);
      expect(back.personaId, d.personaId);
      expect(back.difficulty, d.difficulty);
      expect(back.difficultyPreference, d.difficultyPreference);
      expect(back.freeAllowance, d.freeAllowance);
      expect(back.freeUsed, d.freeUsed);
      expect(back.freeRemaining, d.freeRemaining);
      expect(back.extraCostMessages, d.extraCostMessages);
      expect(back.learningMode, PracticeLearningMode.beginner);
      expect(back.temperatureScore, 42);
      expect(back.familiarityScore, 44);
      expect(back.relationshipStageLabel, '可以聊個人');
      expect(back.nextResetAt, d.nextResetAt);
      expect(back.createdAt, d.createdAt);
    });

    test('舊 draft 缺 learning 欄位 → fallback standard', () {
      final json = sampleDraft().toJson()
        ..remove('learningMode')
        ..remove('temperatureScore')
        ..remove('familiarityScore')
        ..remove('relationshipStageLabel');

      final back = PracticeDrawDraft.fromJson(json);

      expect(back.learningMode, PracticeLearningMode.standard);
      expect(back.temperatureScore, isNull);
      expect(back.familiarityScore, isNull);
      expect(back.relationshipStageLabel, isNull);
    });

    test('未知 difficultyPreference 名稱 → 兜底 normal', () {
      final json = sampleDraft().toJson()..['difficultyPreference'] = 'bogus';
      expect(PracticeDrawDraft.fromJson(json).difficultyPreference,
          PracticeDifficultyPreference.normal);
    });
  });

  group('InMemoryPracticeDrawDraftStore', () {
    test('save → load → clear', () async {
      final store = InMemoryPracticeDrawDraftStore();
      expect(store.load(), isNull);

      await store.save(sampleDraft());
      expect(store.load()!.profileId, 'practice_girl_007');

      await store.clear();
      expect(store.load(), isNull);
    });
  });

  group('HivePracticeDrawDraftStore', () {
    late Box box;

    setUp(() async {
      Hive.init('./.dart_tool/test_hive_draw_draft');
      final ts = DateTime.now().microsecondsSinceEpoch;
      box = await Hive.openBox('draw_draft_$ts');
    });

    tearDown(() async {
      await box.deleteFromDisk();
    });

    test('save 落地 → load 取回同一份', () async {
      final store = HivePracticeDrawDraftStore(box);
      await store.save(sampleDraft());

      final back = store.load();
      expect(back, isNotNull);
      expect(back!.profileId, 'practice_girl_007');
      expect(back.nextResetAt, DateTime.utc(2026, 6, 27, 4));
    });

    test('損毀資料 → load 回 null（不丟例外）', () async {
      await box.put('practice_draw_draft', 'not-json{');
      expect(HivePracticeDrawDraftStore(box).load(), isNull);
    });

    test('clear 後 load 回 null', () async {
      final store = HivePracticeDrawDraftStore(box);
      await store.save(sampleDraft());
      await store.clear();
      expect(store.load(), isNull);
    });
  });
}
