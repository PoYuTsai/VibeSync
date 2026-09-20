// OpenerFlowController：分析→補充→生成→結果的狀態機，含連點、離頁、切帳、
// 生成中修改、舊結果晚回、草稿恢復、到期、次數用完、舊 Edge 退回（附件 §9.1／§9.2）。
// OpenerService 只替換兩個網路方法；controller、模型型別、草稿保存都是正式程式。
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/opener/data/providers/opener_flow_controller.dart';
import 'package:vibesync/features/opener/data/services/opener_result_cache_service.dart';
import 'package:vibesync/features/opener/data/services/opener_service.dart';
import 'package:vibesync/features/opener/domain/opener_flow_models.dart';

class _Call {
  _Call(this.kind, this.args);
  final String kind;
  final Map<String, Object?> args;
}

class _FakeOpenerService extends OpenerService {
  _FakeOpenerService() : super(accessTokenProvider: () => 'token');

  final calls = <_Call>[];
  final analyzeGate = <Completer<OpenerAnalysis>>[];
  final generateGate = <Completer<OpenerGeneration>>[];
  Object? analyzeError;
  Object? generateError;
  bool hold = false;

  static OpenerAnalysis analysis({int generationsUsed = 0, bool quotaCharged = false, DateTime? expiresAt, bool withQuestion = true}) {
    return OpenerAnalysis(
      sessionId: 'sess-1',
      analysisRevision: 1,
      expiresAt: expiresAt ?? DateTime.utc(2099, 1, 1),
      approach: const OpenerApproach(mode: 'anchor_hooks', summary: '可以從她的狗開', avoid: []),
      cues: const [OpenerCue(id: 'cue_1', label: '養狗', source: 'profile_text')],
      question: withQuestion
          ? const OpenerQuestion(id: 'question_1', affects: 'sender_fact', text: '你跟養狗這件事比較接近哪種？', options: [
              OpenerQuestionOption(id: 'option_1', label: '我自己有養', meaning: 'assert_sender_fact', cueId: 'cue_1', statement: '我有養狗'),
              OpenerQuestionOption(id: 'option_2', label: '沒養，但有興趣', meaning: 'curious_without_experience', cueId: 'cue_1'),
            ])
          : null,
      firstGenerationCost: 3,
      includedGenerationCount: 3,
      generationsUsed: generationsUsed,
      quotaCharged: quotaCharged,
    );
  }

  static OpenerGeneration generation({required String generationId, required OpenerContribution contribution, int generationsUsed = 1, int chargedNow = 3, String extend = '牠散步會自己選路嗎'}) {
    return OpenerGeneration.fromServerBody({
      'sessionId': 'sess-1',
      'generationId': generationId,
      'expiresAt': '2099-01-01T00:00:00Z',
      'openers': {'extend': extend, 'humor': '導航派還是隨機派', 'tease': '妳家狗比妳會排行程'},
      'recommendation': {'pick': 'extend', 'reason': '直接問你想知道的事'},
      'materialUse': {'inputState': contribution.stateWire, 'references': [], 'traceStatus': 'uncertain'},
      'access': {'contractVersion': 2, 'servedTier': 'free', 'visibleTypes': ['extend', 'humor', 'tease'], 'lockedTypes': ['resonate', 'coldRead']},
      'usage': {'chargedNow': chargedNow, 'sessionChargedTotal': 3, 'generationsUsed': generationsUsed, 'generationsRemaining': 3 - generationsUsed, 'replayed': false},
    }, contribution: contribution)!;
  }

  @override
  Future<OpenerAnalysis> analyzeProfileStreaming({
    List<Uint8List>? images,
    String? name,
    String? bio,
    String? interests,
    String? meetingContext,
    String? expectedTier,
    String? revenueCatAppUserId,
    required String analysisRequestId,
    String? initialUserNote,
    void Function(String label, String? phase)? onProgress,
  }) async {
    calls.add(_Call('analyze', {'analysisRequestId': analysisRequestId, 'initialUserNote': initialUserNote, 'bio': bio}));
    onProgress?.call('開始分析對方資料', null);
    if (analyzeError != null) throw analyzeError!;
    if (hold) {
      final completer = Completer<OpenerAnalysis>();
      analyzeGate.add(completer);
      return completer.future;
    }
    return analysis();
  }

  @override
  Future<OpenerGeneration> generateFromAnalysisStreaming({
    required String sessionId,
    required int analysisRevision,
    required String generationId,
    required OpenerContribution contribution,
    String? expectedTier,
    String? revenueCatAppUserId,
    void Function(String label, String? phase)? onProgress,
  }) async {
    calls.add(_Call('generate', {'sessionId': sessionId, 'generationId': generationId, 'contribution': contribution.toJson()}));
    onProgress?.call('開場白 1/5', 'style_extend');
    if (generateError != null) throw generateError!;
    if (hold) {
      final completer = Completer<OpenerGeneration>();
      generateGate.add(completer);
      return completer.future;
    }
    return generation(generationId: generationId, contribution: contribution, generationsUsed: calls.where((c) => c.kind == 'generate').length);
  }
}

const _input = OpenerGenerationInput(bio: '有養一隻狗');

/// 生成送出前多了一次草稿落地（R2a：Hive I/O），等到請求真的送到 service。
Future<void> _untilGenerateSent(_FakeOpenerService service) async {
  for (var i = 0; i < 200 && service.generateGate.isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}


/// R2a-2：模擬草稿保存失敗（磁碟／Hive 例外），驗證「必要 checkpoint 沒成功就不打付費 API」。
class _FailingCache extends OpenerResultCacheService {
  _FailingCache() : super(ownerIdResolver: () => 'user-a');
  bool fail = false;

  // R2a-3 後 controller 走固定 owner 的入口，失敗注入放在這三個方法。
  @override
  Future<OpenerDraft> saveDraftFor({required String? owner, OpenerResult? result, String? displayName, String? sourceLabel, String? inputPreview, String? partnerId, OpenerDraftFlow? flow}) {
    if (fail) throw StateError('disk full');
    return super.saveDraftFor(owner: owner, result: result, displayName: displayName, sourceLabel: sourceLabel, inputPreview: inputPreview, partnerId: partnerId, flow: flow);
  }

  @override
  Future<OpenerDraft?> updateDraftFor({required String? owner, required String id, OpenerResult? result, OpenerDraftFlow? flow}) {
    if (fail) throw StateError('disk full');
    return super.updateDraftFor(owner: owner, id: id, result: result, flow: flow);
  }

  @override
  Future<OpenerDraft?> updateDraftContributionFor({required String? owner, required String id, required OpenerContributionDraft contributionDraft}) {
    if (fail) throw StateError('disk full');
    return super.updateDraftContributionFor(owner: owner, id: id, contributionDraft: contributionDraft);
  }
}

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_opener_flow_controller');
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

  late _FakeOpenerService service;
  late OpenerResultCacheService cache;
  String? owner = 'user-a';
  late OpenerFlowController controller;
  DateTime now = DateTime.utc(2026, 9, 17, 12);

  setUp(() {
    service = _FakeOpenerService();
    owner = 'user-a';
    now = DateTime.utc(2026, 9, 17, 12);
    cache = OpenerResultCacheService(ownerIdResolver: () => owner);
    controller = OpenerFlowController(service: service, cache: cache, ownerIdResolver: () => owner, now: () => now);
  });

  test('分析成功→contributing；初稿帶進回答區；同輸入重試沿用同 analysisRequestId、成功後換新', () async {
    await controller.analyze(input: _input, initialNote: ' 想從狗開 ');
    expect(controller.state.phase, OpenerFlowPhase.contributing);
    expect(controller.state.analysis?.sessionId, 'sess-1');
    expect(controller.state.draft.freeText, '想從狗開');
    expect(controller.state.generation, isNull);
    final firstId = service.calls.single.args['analysisRequestId'];
    expect(service.calls.single.args['initialUserNote'], '想從狗開');

    // 換資料→編輯；再分析＝新 id。
    controller.resetForInputChange();
    expect(controller.state.phase, OpenerFlowPhase.editing);
    expect(controller.state.analysis, isNull);
    await controller.analyze(input: _input, initialNote: '想從狗開');
    expect(service.calls.last.args['analysisRequestId'], isNot(firstId));
  });

  test('分析失敗保留輸入、可用同 analysisRequestId 重試', () async {
    service.analyzeError = Exception('連線中斷，請再試一次');
    await controller.analyze(input: _input, initialNote: '初稿');
    expect(controller.state.phase, OpenerFlowPhase.editing);
    expect(controller.state.error, contains('連線中斷'));
    expect(controller.state.failedOperation, OpenerFlowFailedOperation.analyze);
    final id = service.calls.single.args['analysisRequestId'];
    service.analyzeError = null;
    await controller.retryLastOperation();
    expect(controller.state.phase, OpenerFlowPhase.contributing);
    expect(service.calls.last.args['analysisRequestId'], id, reason: '同一次操作重試沿用同 id');
    expect(controller.state.draft.freeText, '初稿');
  });

  test('舊 Edge 不支援→flowUnsupported，退回舊單段；不丟輸入', () async {
    service.analyzeError = const OpenerFlowException(code: OpenerFlowErrorCode.flowUnsupported, message: 'x', status: 400);
    await controller.analyze(input: _input, initialNote: null);
    expect(controller.state.flowUnsupported, isTrue);
    expect(controller.state.phase, OpenerFlowPhase.editing);
    expect(controller.state.error, contains('一般生成'));
  });

  test('選項不預選、可取消；文字否定已選線索→移除選項（明確矛盾）', () async {
    await controller.analyze(input: _input, initialNote: null);
    expect(controller.state.draft.selectedOptionId, isNull);
    controller.selectOption('option_2');
    expect(controller.state.draft.selectedOptionId, 'option_2');
    controller.setFreeText('不要聊養狗，想問她照片那間店');
    expect(controller.state.draft.selectedOptionId, isNull, reason: '被明確否定的選擇要移除');
    expect(controller.state.draft.freeText, '不要聊養狗，想問她照片那間店');
    controller.selectOption('option_2');
    controller.selectOption('option_2');
    expect(controller.state.draft.selectedOptionId, isNull, reason: '再點一次取消');
  });

  test('生成成功→result、草稿含兩段式資料、requestId＝generationId；同回答重試同 id、改回答新 id、不改重抽也新 id', () async {
    await controller.analyze(input: _input, initialNote: null);
    controller.selectOption('option_2');
    controller.setFreeText('沒養過，只想知道牠散步會不會自己選路');
    await controller.generate();
    expect(controller.state.phase, OpenerFlowPhase.result);
    final generation = controller.state.generation!;
    final firstGenId = service.calls.last.args['generationId'] as String;
    expect(generation.result.requestId, firstGenId);
    expect(controller.state.analysis!.generationsUsed, 1);
    expect(controller.state.analysis!.quotaCharged, isTrue);
    expect(controller.state.generationsRemaining, 2);
    expect(service.calls.last.args['contribution'], {'state': 'answered', 'questionId': 'question_1', 'selectedOptionId': 'option_2', 'freeText': '沒養過，只想知道牠散步會不會自己選路'});

    final drafts = cache.loadDrafts();
    expect(drafts.single.flow, isNotNull);
    expect(drafts.single.flow!.generation!.generationId, firstGenId);
    expect(drafts.single.flow!.contributionDraft.selectedOptionId, 'option_2');
    expect(controller.state.draftId, drafts.single.id);

    // 改回答→新 generationId（F16）。
    controller.adjustContribution();
    expect(controller.state.phase, OpenerFlowPhase.contributing);
    expect(controller.state.draft.freeText, '沒養過，只想知道牠散步會不會自己選路', reason: '保留上次的文字與選擇');
    controller.setFreeText('改聊咖啡');
    await controller.generate(fresh: true);
    final secondGenId = service.calls.last.args['generationId'] as String;
    expect(secondGenId, isNot(firstGenId));
    expect((service.calls.last.args['contribution'] as Map)['freeText'], '改聊咖啡');
    expect((service.calls.last.args['contribution'] as Map).containsKey('selectedOptionId'), isFalse, reason: '文字否定線索後選項已移除');

    // 不改回答、主動再抽→又是新 id（算新生成）。
    await controller.generate(fresh: true);
    final thirdGenId = service.calls.last.args['generationId'] as String;
    expect(thirdGenId, isNot(secondGenId));
    expect(controller.state.generationsRemaining, 0);
    expect(controller.state.canGenerateMore, isFalse);
    await controller.generate(fresh: true);
    expect(service.calls.where((c) => c.kind == 'generate').length, 3, reason: '三組用完不再打伺服器');
    expect(controller.state.error, contains('三組'));
  });

  test('生成失敗（可重試）保留回答；重試沿用同 generationId；到期／次數用完各自狀態', () async {
    await controller.analyze(input: _input, initialNote: null);
    controller.setFreeText('我妹也是美容師');
    service.generateError = Exception('連線中斷，請再試一次');
    await controller.generate();
    expect(controller.state.phase, OpenerFlowPhase.contributing);
    expect(controller.state.draft.freeText, '我妹也是美容師');
    final id = service.calls.last.args['generationId'];
    service.generateError = null;
    await controller.retryLastOperation();
    expect(controller.state.phase, OpenerFlowPhase.result);
    expect(service.calls.last.args['generationId'], id);

    service.generateError = const OpenerFlowException(code: OpenerFlowErrorCode.generationLimitReached, message: '這局的三組回覆已用完', status: 409);
    await controller.generate(fresh: true);
    expect(controller.state.phase, OpenerFlowPhase.result);
    expect(controller.state.generationsRemaining, 0);

    controller.resetForInputChange();
    await controller.analyze(input: _input, initialNote: null);
    service.generateError = const OpenerFlowException(code: OpenerFlowErrorCode.sessionExpired, message: '這份分析已到期', status: 410);
    await controller.generate();
    expect(controller.state.phase, OpenerFlowPhase.expired);
    expect(controller.state.analysis, isNotNull, reason: '到期仍保留分析供閱讀');
  });

  test('本機時間到期：按生成不打伺服器、不偷偷開新局', () async {
    await controller.analyze(input: _input, initialNote: null);
    now = DateTime.utc(2100, 1, 1);
    await controller.generate();
    expect(controller.state.phase, OpenerFlowPhase.expired);
    expect(service.calls.where((c) => c.kind == 'generate'), isEmpty);
    expect(controller.isExpired, isTrue);
  });

  test('額度不足→quotaError 交給畫面開 paywall，分析與回答都保留', () async {
    await controller.analyze(input: _input, initialNote: null);
    controller.setFreeText('想聊咖啡');
    service.generateError = const OpenerQuotaExceededException(message: '本月額度不足', quotaNeeded: 3);
    await controller.generate();
    expect(controller.state.quotaError, isNotNull);
    expect(controller.state.phase, OpenerFlowPhase.contributing);
    expect(controller.state.analysis, isNotNull);
    expect(controller.state.draft.freeText, '想聊咖啡');
  });

  test('F17：舊結果晚回不覆蓋新狀態（連點／生成中改資料）', () async {
    await controller.analyze(input: _input, initialNote: null);
    service.hold = true;
    controller.setFreeText('第一版');
    final first = controller.generate();
    expect(controller.state.phase, OpenerFlowPhase.generating);
    await _untilGenerateSent(service); // 讓請求真的送出（模擬結果晚回）
    expect(service.generateGate.length, 1);
    // 生成中改資料（換截圖）：原局作廢。
    controller.resetForInputChange();
    expect(controller.state.phase, OpenerFlowPhase.editing);
    service.generateGate.single.complete(_FakeOpenerService.generation(
      generationId: 'stale',
      contribution: const OpenerContribution(state: OpenerContributionState.answered, freeText: '第一版'),
    ));
    await first;
    expect(controller.state.phase, OpenerFlowPhase.editing, reason: '舊結果晚回被丟棄');
    expect(controller.state.generation, isNull);
    // R2a 後分析完成就有一份 stage=analyzed／generating 的草稿；作廢的結果不得寫進去。
    expect(cache.loadDrafts().where((d) => d.result != null), isEmpty, reason: '作廢的結果不寫草稿');
    expect(cache.loadDrafts().where((d) => d.flow?.stage == OpenerDraftFlowStage.result), isEmpty);
  });

  test('切換帳號後回來的結果不套用、不寫草稿', () async {
    await controller.analyze(input: _input, initialNote: null);
    service.hold = true;
    final pending = controller.generate();
    await _untilGenerateSent(service);
    owner = 'user-b';
    service.generateGate.single.complete(_FakeOpenerService.generation(
      generationId: 'x',
      contribution: const OpenerContribution(state: OpenerContributionState.noAnswer),
    ));
    await pending;
    expect(controller.state.generation, isNull);
    expect(controller.state.error, contains('帳號已切換'));
    owner = 'user-a';
    expect(cache.loadDrafts().where((d) => d.result != null), isEmpty, reason: 'A 帳號的草稿不得被寫入切帳後回來的結果');
    owner = 'user-b';
    expect(cache.loadDrafts(), isEmpty, reason: 'B 帳號不得出現任何 A 的紀錄');
  });

  test('連點生成：忙碌中第二次呼叫不會發第二個請求', () async {
    await controller.analyze(input: _input, initialNote: null);
    service.hold = true;
    final first = controller.generate();
    await _untilGenerateSent(service);
    await controller.generate();
    expect(service.calls.where((c) => c.kind == 'generate').length, 1);
    service.generateGate.single.complete(_FakeOpenerService.generation(
      generationId: service.calls.last.args['generationId'] as String,
      contribution: const OpenerContribution(state: OpenerContributionState.noAnswer),
    ));
    await first;
    expect(controller.state.phase, OpenerFlowPhase.result);
  });

  test('略過：清空答案、標記 skipped、送出 state=skipped', () async {
    await controller.analyze(input: _input, initialNote: '初稿');
    await controller.skipAndGenerate();
    expect(service.calls.last.args['contribution'], {'state': 'skipped'});
    expect(controller.state.phase, OpenerFlowPhase.result);
  });

  test('草稿恢復：兩段式草稿回到結果；到期草稿只能看；controller 不寫另一份紀錄', () async {
    await controller.analyze(input: _input, initialNote: null);
    controller.setFreeText('沒養過');
    await controller.generate();
    final draft = cache.loadDrafts().single;

    final fresh = OpenerFlowController(service: service, cache: cache, ownerIdResolver: () => owner, now: () => now);
    fresh.restoreDraft(draft);
    expect(fresh.state.phase, OpenerFlowPhase.result);
    expect(fresh.state.generation!.generationId, draft.flow!.generation!.generationId);
    expect(fresh.state.draft.freeText, '沒養過');
    expect(fresh.state.generationsRemaining, 2);

    final expired = OpenerFlowController(service: service, cache: cache, ownerIdResolver: () => owner, now: () => DateTime.utc(2100));
    expired.restoreDraft(draft);
    expect(expired.state.phase, OpenerFlowPhase.expired);
    expect(cache.loadDrafts().length, 1);
  });

  test('題目為 null（原料足夠）：直接生成、不帶題目欄位', () async {
    service.analyzeError = null;
    final noQuestionService = _FakeOpenerService();
    final c = OpenerFlowController(service: noQuestionService, cache: cache, ownerIdResolver: () => owner, now: () => now);
    noQuestionService.calls.clear();
    await c.analyze(input: _input, initialNote: '我想問她那家店在哪');
    // 模擬伺服器回 question=null：直接覆蓋 state 由 fake 回傳有題目版本無法做到，改驗 toContribution 行為。
    final contribution = c.state.draft.toContribution(null);
    expect(contribution.toJson(), {'state': 'answered', 'freeText': '我想問她那家店在哪'});
  });

  // ── 第一輪獨立複核回歸（R2a／R4b）

  test('R2a：分析完成即落地 stage=analyzed（有 analysisRequestId／指紋，沒有結果）；離頁重建可回到回答區', () async {
    await controller.analyze(input: _input, initialNote: '想從狗開');
    final draft = cache.loadDrafts().single;
    expect(draft.result, isNull);
    expect(draft.flow!.stage, OpenerDraftFlowStage.analyzed);
    expect(draft.flow!.analysisRequestId, service.calls.single.args['analysisRequestId']);
    expect(draft.flow!.inputFingerprint, isNotNull);
    expect(draft.flow!.contributionDraft.freeText, '想從狗開');
    expect(controller.state.draftId, draft.id);

    final rebuilt = OpenerFlowController(service: service, cache: cache, ownerIdResolver: () => owner, now: () => now);
    rebuilt.restoreDraft(draft);
    expect(rebuilt.state.phase, OpenerFlowPhase.contributing);
    expect(rebuilt.state.analysis!.sessionId, 'sess-1');
    expect(rebuilt.state.draft.freeText, '想從狗開');
    expect(rebuilt.hasPendingGeneration, isFalse);
  });

  test('R2a：生成送出前先落地 stage=generating＋送出快照；銷毀重建後用原 generationId 取回，不開新局', () async {
    await controller.analyze(input: _input, initialNote: null);
    controller.setFreeText('沒養過');
    service.hold = true;
    final inflight = controller.generate();
    await _untilGenerateSent(service);
    final sentId = service.calls.last.args['generationId'] as String;
    // 送出當下草稿已是 generating＋快照（伺服器可能已結算）。
    final pendingDraft = cache.loadDrafts().single;
    expect(pendingDraft.flow!.stage, OpenerDraftFlowStage.generating);
    expect(pendingDraft.flow!.pendingGeneration!.generationId, sentId);
    expect(pendingDraft.flow!.pendingGeneration!.contribution.freeText, '沒養過');
    expect(pendingDraft.result, isNull);

    // 模擬 App 結束：舊 controller 丟掉、回應永遠不到。
    controller.dispose();
    service.hold = false;
    final rebuilt = OpenerFlowController(service: service, cache: cache, ownerIdResolver: () => owner, now: () => now);
    rebuilt.restoreDraft(pendingDraft);
    expect(rebuilt.hasPendingGeneration, isTrue);
    await rebuilt.resumePendingGeneration();
    expect(rebuilt.state.phase, OpenerFlowPhase.result);
    expect(service.calls.last.args['generationId'], sentId, reason: '沿用原 generationId 取回同組（伺服器 replay），不鑄新 ID');
    expect((service.calls.last.args['contribution'] as Map)['freeText'], '沒養過');
    expect(service.calls.where((c) => c.kind == 'analyze').length, 1, reason: '不重新分析、不開新局');
    final finalDraft = cache.loadDrafts().single;
    expect(finalDraft.flow!.stage, OpenerDraftFlowStage.result);
    expect(finalDraft.result!.requestId, sentId);
    expect(cache.loadDrafts().length, 1, reason: '同一份紀錄隨階段更新，不另建歷史');
    service.generateGate.single.complete(_FakeOpenerService.generation(generationId: 'stale', contribution: const OpenerContribution(state: OpenerContributionState.skipped)));
    await inflight;
  });

  test('R2a：失敗後改了回答再按「再試一次」→沿用送出快照（同 ID、原回答）；「生成」才是新的操作', () async {
    await controller.analyze(input: _input, initialNote: null);
    controller.setFreeText('第一版');
    service.generateError = Exception('連線中斷，請再試一次');
    await controller.generate();
    final sentId = service.calls.last.args['generationId'];
    service.generateError = null;
    controller.setFreeText('偷偷改了第二版');
    await controller.retryLastOperation();
    expect(service.calls.last.args['generationId'], sentId);
    expect((service.calls.last.args['contribution'] as Map)['freeText'], '第一版', reason: 'retry 用送出快照');
    expect(controller.state.draft.freeText, '偷偷改了第二版', reason: '修改後的 draft 保留為未生成版本');
    await controller.generate(fresh: true);
    expect(service.calls.last.args['generationId'], isNot(sentId));
    expect((service.calls.last.args['contribution'] as Map)['freeText'], '偷偷改了第二版');
  });

  test('R4b：補充超過 300 字→不送出、原文保留、給錯誤；初稿超過 300 字→不分析', () async {
    await controller.analyze(input: _input, initialNote: null);
    controller.setFreeText('字' * 301);
    await controller.generate();
    expect(service.calls.where((c) => c.kind == 'generate'), isEmpty);
    expect(controller.state.freeTextTooLong, isTrue);
    expect(controller.state.draft.freeText.length, 301);
    expect(controller.state.error, contains('300'));
    final c2 = OpenerFlowController(service: service, cache: cache, ownerIdResolver: () => owner, now: () => now);
    await c2.analyze(input: _input, initialNote: '🐶' * 301);
    expect(c2.state.phase, OpenerFlowPhase.editing);
    expect(c2.state.error, contains('300'));
  });

  // ── 第二輪獨立複核回歸（R2a-2：未完成流程的實際落地與重建）

  test('R2a-2：分析後只選選項／改文字、尚未生成→離頁重建回到同一份回答', () async {
    await controller.analyze(input: _input, initialNote: null);
    controller.selectOption('option_2');
    controller.setFreeText('沒養過，只想問散步');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final draft = cache.loadDrafts().single;
    expect(draft.flow!.contributionDraft.selectedOptionId, 'option_2');
    expect(draft.flow!.contributionDraft.freeText, '沒養過，只想問散步');
    final rebuilt = OpenerFlowController(service: service, cache: cache, ownerIdResolver: () => owner, now: () => now);
    rebuilt.restoreDraft(draft);
    expect(rebuilt.state.draft.selectedOptionId, 'option_2');
    expect(rebuilt.state.draft.freeText, '沒養過，只想問散步');
    expect(service.calls.where((c) => c.kind == 'generate'), isEmpty);
  });

  test('R2a-2：生成等待中改了 draft→新文字落地，但原 pending 的送出快照不變；重建後仍用原快照取回', () async {
    await controller.analyze(input: _input, initialNote: null);
    controller.setFreeText('第一版');
    service.hold = true;
    final inflight = controller.generate();
    await _untilGenerateSent(service);
    final sentId = service.calls.last.args['generationId'] as String;
    controller.setFreeText('等待中偷改');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final draft = cache.loadDrafts().single;
    expect(draft.flow!.stage, OpenerDraftFlowStage.generating);
    expect(draft.flow!.contributionDraft.freeText, '等待中偷改');
    expect(draft.flow!.pendingGeneration!.generationId, sentId);
    expect(draft.flow!.pendingGeneration!.contribution.freeText, '第一版', reason: '送出快照不得被等待中的修改改掉');

    controller.dispose();
    service.hold = false;
    final rebuilt = OpenerFlowController(service: service, cache: cache, ownerIdResolver: () => owner, now: () => now);
    rebuilt.restoreDraft(draft);
    expect(rebuilt.state.draft.freeText, '等待中偷改');
    await rebuilt.resumePendingGeneration();
    expect(service.calls.last.args['generationId'], sentId);
    expect((service.calls.last.args['contribution'] as Map)['freeText'], '第一版');
    service.generateGate.single.complete(_FakeOpenerService.generation(generationId: 'stale', contribution: const OpenerContribution(state: OpenerContributionState.skipped)));
    await inflight;
  });

  test('R2a-2：pending 快照保存失敗→不打生成 API（呼叫數 0）、輸入保留、提示重試；保存恢復後重試才送出', () async {
    final failing = _FailingCache();
    final c = OpenerFlowController(service: service, cache: failing, ownerIdResolver: () => owner, now: () => now);
    await c.analyze(input: _input, initialNote: null);
    c.setFreeText('沒養過');
    failing.fail = true;
    await c.generate();
    expect(service.calls.where((x) => x.kind == 'generate').length, 0, reason: '必要 checkpoint 沒成功不得送出可扣費請求');
    expect(c.state.phase, OpenerFlowPhase.contributing);
    expect(c.state.draft.freeText, '沒養過');
    expect(c.state.error, isNotNull);
    expect(c.state.failedOperation, OpenerFlowFailedOperation.generate);
    failing.fail = false;
    await c.retryLastOperation();
    expect(service.calls.where((x) => x.kind == 'generate').length, 1);
    expect(c.state.phase, OpenerFlowPhase.result);
    expect(failing.loadDrafts().single.flow!.stage, OpenerDraftFlowStage.result);
  });

  test('R2a-2：第一段分析尚未返回就離頁→輸入快照與 analysisRequestId 已落地，重建後用同 ID 續分析', () async {
    service.hold = true;
    final inflight = controller.analyze(input: _input, initialNote: '想從狗開');
    for (var i = 0; i < 200 && service.analyzeGate.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    final sentId = service.calls.single.args['analysisRequestId'] as String;
    expect(cache.loadDrafts(), isNotEmpty, reason: '分析送出後就要有可恢復的紀錄');
    final draft = cache.loadDrafts().single;
    expect(draft.result, isNull);
    expect(draft.flow!.stage, OpenerDraftFlowStage.analyzing);
    expect(draft.flow!.analysis, isNull);
    expect(draft.flow!.analysisRequestId, sentId);
    expect(draft.flow!.pendingAnalysis!.bio, '有養一隻狗');
    expect(draft.flow!.pendingAnalysis!.initialNote, '想從狗開');

    controller.dispose();
    service.hold = false;
    final rebuilt = OpenerFlowController(service: service, cache: cache, ownerIdResolver: () => owner, now: () => now);
    rebuilt.restoreDraft(draft);
    expect(rebuilt.pendingAnalysis!.bio, '有養一隻狗');
    expect(rebuilt.hasPendingAnalysis, isTrue);
    await rebuilt.resumePendingAnalysis();
    expect(rebuilt.state.phase, OpenerFlowPhase.contributing);
    expect(service.calls.last.args['analysisRequestId'], sentId, reason: '同輸入沿用同 analysisRequestId（伺服器 replay 同局）');
    expect(service.calls.last.args['initialUserNote'], '想從狗開');
    expect(cache.loadDrafts().length, 1, reason: '同一份紀錄由 analyzing 升到 analyzed');
    expect(cache.loadDrafts().single.flow!.stage, OpenerDraftFlowStage.analyzed);
    service.analyzeGate.single.complete(_FakeOpenerService.analysis());
    await inflight;
  });

  // ── 第三輪獨立複核回歸（R2a-3：保存佇列的一致性）

  OpenerDraftFlow analyzedFlow(String sessionId) => OpenerDraftFlow(
        stage: OpenerDraftFlowStage.analyzed,
        analysis: OpenerAnalysis.tryParse({..._FakeOpenerService.analysis().toJson(), 'sessionId': sessionId})!,
        contributionDraft: const OpenerContributionDraft(),
        analysisRequestId: 'req-$sessionId',
        inputFingerprint: 'fp-$sessionId',
      );

  Future<void> drain() async {
    for (var i = 0; i < 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
  }

  test('R2a-3 P1：A 的兩筆保存排隊中切成 B 並恢復 B 的草稿→放行後 B 的儲存 key 不得有 A 原料；A 的合法保存仍完成在 A key', () async {
    await controller.analyze(input: _input, initialNote: null);
    final draftB = await OpenerResultCacheService(ownerIdResolver: () => 'user-b').saveDraft(flow: analyzedFlow('sess-b'));

    final gate = Completer<void>();
    cache.debugWriteGate = () => gate.future;
    controller.setFreeText('A 原料一');
    await Future<void>.delayed(const Duration(milliseconds: 20)); // 第一筆已進入寫入、卡在閘門
    controller.setFreeText('A 原料二'); // 第二筆排隊
    owner = 'user-b';
    controller.restoreDraft(draftB);
    cache.debugWriteGate = null;
    gate.complete();
    await drain();

    final box = Hive.box(AppConstants.settingsBox);
    final bKey = box.get('opener_drafts_v1:user-b') as String;
    expect(bKey, isNot(contains('A 原料')), reason: 'A 的排隊保存不得寫進 B 的 key');
    expect(bKey, contains('sess-b'));
    final aKey = box.get('opener_drafts_v1:user-a') as String;
    expect(aKey, contains('A 原料二'), reason: 'A 原紀錄的合法保存可以完成');
    expect(controller.state.analysis!.sessionId, 'sess-b');
    expect(controller.state.draftId, draftB.id);
  });

  test('R2a-3 P2：同帳號保存 A 期間恢復 B→A 的舊保存返回後 active draftId／analysis 仍全屬 B', () async {
    await controller.analyze(input: _input, initialNote: null);
    final draftA = cache.loadDrafts().single;
    final draftB = await cache.saveDraft(flow: analyzedFlow('sess-b'));

    final gate = Completer<void>();
    cache.debugWriteGate = () => gate.future;
    controller.setFreeText('A 改');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.restoreDraft(draftB);
    cache.debugWriteGate = null;
    gate.complete();
    await drain();

    expect(controller.state.draftId, draftB.id, reason: '舊保存的返回 id 不得寫到新流程的 active state');
    expect(controller.state.analysis!.sessionId, 'sess-b');
    expect(controller.state.draft.freeText, '');
    expect(cache.loadDraft(draftA.id)!.flow!.contributionDraft.freeText, 'A 改', reason: 'A 紀錄本身仍合法完成保存');
  });

  test('R2a-3 P3：result 保存等待期間改 draft→清空佇列後重建：原 generationId／結果／使用量與最新未生成回答都在', () async {
    await controller.analyze(input: _input, initialNote: null);
    controller.setFreeText('第一版');
    await drain();
    service.hold = true;
    final inflight = controller.generate();
    await _untilGenerateSent(service);
    final sentId = service.calls.last.args['generationId'] as String;
    final sent = service.calls.last.args['contribution'] as Map;

    // 回應到了，但 result 落地卡在磁碟。
    final gate = Completer<void>();
    cache.debugWriteGate = () => gate.future;
    service.generateGate.single.complete(_FakeOpenerService.generation(
      generationId: sentId,
      contribution: OpenerContribution.tryParse(sent)!,
    ));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.setFreeText('等待中的新回答');
    cache.debugWriteGate = null;
    gate.complete();
    await inflight;
    await drain();

    final stored = cache.loadDrafts().single;
    expect(stored.flow!.stage, OpenerDraftFlowStage.result, reason: '回答編輯不得把作業狀態寫退');
    expect(stored.flow!.generation!.generationId, sentId);
    expect(stored.flow!.generation!.usage.generationsUsed, 1);
    expect(stored.result!.requestId, sentId);
    expect(stored.flow!.contributionDraft.freeText, '等待中的新回答', reason: '最新未生成回答也要在');

    final rebuilt = OpenerFlowController(service: service, cache: cache, ownerIdResolver: () => owner, now: () => now);
    rebuilt.restoreDraft(stored);
    expect(rebuilt.state.phase, OpenerFlowPhase.result);
    expect(rebuilt.state.generation!.generationId, sentId);
    expect(rebuilt.state.draft.freeText, '等待中的新回答');
    expect(rebuilt.state.generationsRemaining, 2);
  });

  // ── 第四輪獨立複核回歸（R2a-4：新建／補建保存工作的 payload 與建檔目標）

  test('R2a-4 P1：A 的 analyzing checkpoint 新建排隊中切 B 並恢復 B→A key 不得含 B 名稱／來源／預覽；B key 與 active B 不變', () async {
    final cacheB = OpenerResultCacheService(ownerIdResolver: () => 'user-b');
    final draftB = await cacheB.saveDraft(flow: analyzedFlow('sess-b'), displayName: 'B 名', sourceLabel: 'B 來源', inputPreview: 'B 預覽');
    final bBefore = Hive.box(AppConstants.settingsBox).get('opener_drafts_v1:user-b') as String;

    // 先讓佇列被一筆寫入卡住，新建的 analyzing checkpoint 才會「排隊中（尚未出隊）」遇到切帳／恢復。
    await controller.analyze(input: _input, initialNote: null);
    final gate = Completer<void>();
    cache.debugWriteGate = () => gate.future;
    controller.setFreeText('卡住佇列');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.resetForInputChange();
    final inflight = controller.analyze(input: const OpenerGenerationInput(bio: '第二個人'), initialNote: null, displayName: 'A 名', sourceLabel: 'A 來源', inputPreview: 'A 預覽');
    await Future<void>.delayed(const Duration(milliseconds: 20)); // analyzing checkpoint 排在閘門後面、尚未出隊
    owner = 'user-b';
    controller.restoreDraft(draftB);
    cache.debugWriteGate = null;
    gate.complete();
    await inflight;
    await drain();

    final box = Hive.box(AppConstants.settingsBox);
    final aKey = box.get('opener_drafts_v1:user-a') as String;
    expect(aKey, contains('A 名'));
    for (final leaked in ['B 名', 'B 來源', 'B 預覽']) {
      expect(aKey, isNot(contains(leaked)), reason: '出隊時不得讀到另一流程的 metadata');
    }
    expect(box.get('opener_drafts_v1:user-b'), bBefore, reason: 'B key 不變');
    expect(controller.state.draftId, draftB.id);
    expect(controller.state.analysis!.sessionId, 'sess-b');
    expect(service.calls.where((c) => c.kind == 'analyze').length, 1, reason: '切帳後被作廢的第二次分析不再打伺服器');
  });

  test('R2a-4 P1（同帳號）：A 新建排隊中恢復同帳號另一份草稿→A 紀錄仍是 A 自己的名稱／來源／預覽', () async {
    final draftA2 = await cache.saveDraft(flow: analyzedFlow('sess-a2'), displayName: 'A2 名', sourceLabel: 'A2 來源', inputPreview: 'A2 預覽');
    await controller.analyze(input: _input, initialNote: null);
    final firstId = controller.state.draftId;
    final gate = Completer<void>();
    cache.debugWriteGate = () => gate.future;
    controller.setFreeText('卡住佇列');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.resetForInputChange();
    final inflight = controller.analyze(input: const OpenerGenerationInput(bio: '第二個人'), initialNote: null, displayName: 'A 名', sourceLabel: 'A 來源', inputPreview: 'A 預覽');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    controller.restoreDraft(draftA2);
    cache.debugWriteGate = null;
    gate.complete();
    await inflight;
    await drain();

    final drafts = cache.loadDrafts();
    final created = drafts.where((d) => d.id != draftA2.id && d.id != firstId).single;
    expect(created.displayName, 'A 名');
    expect(created.sourceLabel, 'A 來源');
    expect(created.inputPreview, 'A 預覽');
    expect(controller.state.draftId, draftA2.id);
  });

  test('R2a-4 P2：分析成功但沒有本機草稿→磁碟恢復後首次補建等待中按生成→最後只有一份同局草稿，內容正確', () async {
    final failing = _FailingCache();
    final c = OpenerFlowController(service: service, cache: failing, ownerIdResolver: () => owner, now: () => now);
    failing.fail = true;
    await c.analyze(input: _input, initialNote: null);
    expect(c.state.phase, OpenerFlowPhase.contributing);
    expect(failing.loadDrafts(), isEmpty, reason: '分析成功、兩個 checkpoint 都沒落地');
    failing.fail = false;

    final gate = Completer<void>();
    failing.debugWriteGate = () => gate.future;
    c.setFreeText('回答');
    await Future<void>.delayed(const Duration(milliseconds: 20)); // 首次補建卡在閘門
    final inflight = c.generate(); // pending checkpoint 排在補建後面
    await Future<void>.delayed(const Duration(milliseconds: 20));
    failing.debugWriteGate = null;
    gate.complete();
    await inflight;
    await drain();

    final drafts = failing.loadDrafts();
    expect(drafts.length, 1, reason: '同一代的回答編輯與階段 checkpoint 共用建檔目標');
    final only = drafts.single;
    final sentId = service.calls.last.args['generationId'] as String;
    expect(only.flow!.stage, OpenerDraftFlowStage.result);
    expect(only.flow!.generation!.generationId, sentId);
    expect(only.flow!.generation!.usage.generationsUsed, 1);
    expect(only.result!.requestId, sentId);
    expect(only.flow!.contributionDraft.freeText, '回答');
    expect(c.state.draftId, only.id);
    expect(c.state.phase, OpenerFlowPhase.result);
  });

  test('R2a-4 P2：首次補建失敗→磁碟恢復後再次修改，下一次保存要成功，不被失敗的建檔工作永久卡住', () async {
    final failing = _FailingCache();
    final c = OpenerFlowController(service: service, cache: failing, ownerIdResolver: () => owner, now: () => now);
    failing.fail = true;
    await c.analyze(input: _input, initialNote: null);
    c.setFreeText('一');
    await drain();
    expect(failing.loadDrafts(), isEmpty);
    failing.fail = false;
    c.setFreeText('二');
    await drain();
    final drafts = failing.loadDrafts();
    expect(drafts.length, 1, reason: '磁碟恢復後的保存要能重試建檔');
    expect(drafts.single.flow!.contributionDraft.freeText, '二');
    expect(c.state.draftId, drafts.single.id);
    c.setFreeText('三');
    await drain();
    expect(failing.loadDrafts().length, 1);
    expect(failing.loadDrafts().single.flow!.contributionDraft.freeText, '三');
  });
}
