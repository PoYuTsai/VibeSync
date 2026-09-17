// 兩段式草稿延伸：flow 欄位往返、舊草稿相容、帳號隔離不變（附件 §9.5）。
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/opener/data/services/opener_result_cache_service.dart';
import 'package:vibesync/features/opener/data/services/opener_service.dart';
import 'package:vibesync/features/opener/domain/opener_flow_models.dart';

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_opener_result_cache_flow');
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

  OpenerDraftFlow flow() {
    final analysis = OpenerAnalysis.tryParse({
      'sessionId': 'sess-1',
      'analysisRevision': 1,
      'expiresAt': '2026-09-18T12:00:00Z',
      'approach': {'mode': 'fresh_topic', 'summary': '自介主要在寫篩選條件，可以另找話題', 'avoid': ['不用回應她的抱怨']},
      'cues': [{'id': 'cue_1', 'label': '美容師', 'source': 'manual_field'}],
      'question': null,
      'usage': {'firstGenerationCost': 3, 'includedGenerationCount': 3, 'generationsUsed': 1, 'quotaCharged': true},
    })!;
    const contribution = OpenerContribution(state: OpenerContributionState.answered, freeText: '我妹也是美容師');
    final generation = OpenerGeneration.fromServerBody({
      'sessionId': 'sess-1',
      'generationId': 'gen-1',
      'expiresAt': '2026-09-18T12:00:00Z',
      'openers': {'extend': '我妹也是美容師，妳做這行多久了', 'humor': 'h', 'tease': 't'},
      'recommendation': {'pick': 'extend', 'reason': '保留你妹妹這個主體'},
      'materialUse': {'inputState': 'answered', 'references': [{'style': 'extend', 'materialId': 'material_1', 'outputSpan': '我妹也是美容師'}], 'traceStatus': 'matched', 'displayNote': '這句接的是你妹妹的工作'},
      'access': {'contractVersion': 2, 'servedTier': 'free', 'visibleTypes': ['extend', 'humor', 'tease'], 'lockedTypes': ['resonate', 'coldRead']},
      'usage': {'chargedNow': 3, 'sessionChargedTotal': 3, 'generationsUsed': 1, 'generationsRemaining': 2, 'replayed': false},
    }, contribution: contribution)!;
    return OpenerDraftFlow(stage: OpenerDraftFlowStage.result, analysis: analysis, generation: generation, contributionDraft: const OpenerContributionDraft(freeText: '我妹也是美容師'));
  }

  test('flow 欄位隨草稿保存並完整讀回；到期／剩餘次數決定能否繼續', () async {
    final cache = OpenerResultCacheService(ownerIdResolver: () => 'user-a');
    final saved = await cache.saveDraft(result: flow().generation!.result, flow: flow(), sourceLabel: '手動輸入');
    final loaded = cache.loadDraft(saved.id)!;
    expect(loaded.flow, isNotNull);
    expect(loaded.flow!.analysis.sessionId, 'sess-1');
    expect(loaded.flow!.generation!.generationId, 'gen-1');
    expect(loaded.flow!.generation!.materialUse.displayNote, '這句接的是你妹妹的工作');
    expect(loaded.flow!.contributionDraft.freeText, '我妹也是美容師');
    expect(loaded.result!.requestId, 'gen-1', reason: '回報 ID 走 generationId');
    expect(loaded.flow!.canContinueAt(DateTime.utc(2026, 9, 18, 11)), isTrue);
    expect(loaded.flow!.canContinueAt(DateTime.utc(2026, 9, 18, 12)), isFalse);
  });

  test('舊單段草稿沒有 flow 欄位，照舊讀取；markDraftContinued 保留 flow', () async {
    final cache = OpenerResultCacheService(ownerIdResolver: () => 'user-a');
    final legacy = await cache.saveDraft(result: const OpenerResult(openers: {'extend': '舊句'}, requestId: 'req-old'));
    expect(cache.loadDraft(legacy.id)!.flow, isNull);
    final modern = await cache.saveDraft(result: flow().generation!.result, flow: flow());
    await cache.markDraftContinued(modern.id);
    expect(cache.loadDraft(modern.id)!.flow, isNotNull);
    expect(cache.loadDraft(modern.id)!.continuedAt, isNotNull);
  });

  test('帳號隔離：另一個帳號讀不到含兩段式資料的草稿', () async {
    final a = OpenerResultCacheService(ownerIdResolver: () => 'user-a');
    await a.saveDraft(result: flow().generation!.result, flow: flow());
    final b = OpenerResultCacheService(ownerIdResolver: () => 'user-b');
    expect(b.loadDrafts(), isEmpty);
    expect(OpenerResultCacheService(ownerIdResolver: () => null).loadDrafts(), isEmpty);
  });

  test('R2a：未完成階段的草稿（沒有 result）可保存與讀回；stage 與送出快照完整', () async {
    final cache = OpenerResultCacheService(ownerIdResolver: () => 'user-a');
    final f = flow();
    final pending = OpenerDraftFlow(
      stage: OpenerDraftFlowStage.generating,
      analysis: f.analysis,
      contributionDraft: const OpenerContributionDraft(freeText: '沒養過'),
      analysisRequestId: 'req-1',
      inputFingerprint: 'fp-1',
      pendingGeneration: const OpenerPendingGeneration(
        generationId: 'gen-9',
        contribution: OpenerContribution(state: OpenerContributionState.answered, freeText: '沒養過'),
      ),
    );
    final saved = await cache.saveDraft(flow: pending, sourceLabel: '手動輸入');
    final loaded = cache.loadDraft(saved.id)!;
    expect(loaded.result, isNull);
    expect(loaded.flow!.stage, OpenerDraftFlowStage.generating);
    expect(loaded.flow!.pendingGeneration!.generationId, 'gen-9');
    expect(loaded.flow!.pendingGeneration!.contribution.freeText, '沒養過');
    expect(loaded.flow!.analysisRequestId, 'req-1');
    expect(loaded.previewForAccess(isFreeUser: true), '生成中，尚未取得結果');
    expect(cache.loadLatestForScope(), isNull, reason: '沒有結果的草稿不進 latest');
  });
}
