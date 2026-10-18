/// 草稿潤飾與回覆微調的迭代協調器：exactly-once 計費（fingerprint →
/// findPending → beginAttempt → send）、伺服器免費剩餘次數的唯一本地
/// 快取、微調稿 durable 暫存（先存得回來、才清付費身分）與
/// acknowledgePresented（畫面確認付費結果可見後才 markSuccess）。
/// 畫面保留同意書、面板與可見幀／route 判斷；順序與計費語意逐字沿用
/// 拆分前實作。計費 port／draft port／傳輸
/// callable 一律由 composition root（`analysis_providers.dart`）以
/// data adapter 組裝注入；這裡看不到 Hive store、session、runner 或
/// 具體 client 型別。
library;

import '../../conversation/domain/entities/session_context.dart';
import '../domain/entities/analysis_models.dart';
import '../domain/entities/analysis_telemetry.dart';
import '../domain/entities/guide_v3_result.dart';
import '../domain/entities/optimize_message_pending_request.dart';
import '../domain/errors/analysis_exceptions.dart';
import 'analysis_run_preparer.dart';
import 'ports/optimize_billing_port.dart';
import 'ports/reply_iteration_ports.dart';
import 'ports/reply_refine_draft_port.dart';

/// 一次成功潤飾：畫面憑 [pending] 在付費結果可見後 acknowledge。
class PolishRunResult {
  final OptimizeMessagePendingRequest pending;
  final AnalysisResult result;

  const PolishRunResult({required this.pending, required this.result});
}

/// 一次成功微調輪。[restorable] 為 true 表示 durable 暫存已落地，
/// 畫面可以在可見幀後 acknowledge（否則保留 pending 走 replay）。
class RefineRoundResult {
  final OptimizeMessagePendingRequest pending;
  final AnalysisResult result;
  final String refinedText;
  final int? freeRemaining;
  final int? freeDailyLimit;
  final bool chargedQuota;
  final bool restorable;

  const RefineRoundResult({
    required this.pending,
    required this.result,
    required this.refinedText,
    required this.freeRemaining,
    required this.freeDailyLimit,
    required this.chargedQuota,
    required this.restorable,
  });
}

class ReplyIterationCoordinator {
  ReplyIterationCoordinator({
    required OptimizeBillingPort billing,
    required ReplyRefineDraftPort draftStore,
    required OptimizeDraftCall optimizeDraft,
    required RefineReplyCall refineReply,
  })  : _billing = billing,
        _draftStore = draftStore,
        _optimizeDraft = optimizeDraft,
        _refineReply = refineReply;

  final OptimizeBillingPort _billing;
  final ReplyRefineDraftPort _draftStore;
  final OptimizeDraftCall _optimizeDraft;
  final RefineReplyCall _refineReply;

  OptimizeMessagePendingRequest? _pendingAwaitingPresentation;

  /// 今日剩餘免費微調次數。真相源在 server，這裡只記住最近一次回應帶回來
  /// 的數字，好讓下一次開面板時能在動手前就顯示；沒問過就是 null（不猜）。
  int? _refineFreeRemaining;

  /// 上一輪微調丟出例外，[_refineFreeRemaining] 就不再可信：伺服器可能已用掉
  /// 免費次數、結算才失敗。跟面板同一條規則，記在這裡是為了關掉重開的面板也標
  /// 待確認，不會又說還有 N 次免費（主審第 1 輪 P2，Eric 2026-10-18）。
  bool _refineFreeRemainingStale = false;

  /// 已產生但尚未在畫面上確認可見的付費潤飾結果身分。
  OptimizeMessagePendingRequest? get pendingAwaitingPresentation =>
      _pendingAwaitingPresentation;

  int? get refineFreeRemaining => _refineFreeRemaining;

  bool get refineFreeRemainingStale => _refineFreeRemainingStale;

  /// 草稿潤飾的唯一計費路徑。成功時記下 pending 等畫面 acknowledge；
  /// 取消（同意書拒絕／畫面離開）回 null。擋下與失敗以
  /// [AnalysisException] 上拋，文案分流由畫面決定。
  Future<PolishRunResult?> runPolish({
    required String ownerUserId,
    required AuxiliaryAnalysisContext context,
    required SessionContext? sessionContext,
    required String draft,
    required Future<bool> Function() onReadyToSend,
    required AnalysisTelemetryCallback onTelemetry,
  }) async {
    final optimizeFingerprint = _billing.fingerprintFor(
      messages: context.requestMessages,
      userDraft: draft,
      sessionContext: sessionContext,
      conversationSummary: context.conversationSummary,
      partnerSummary: context.partnerSummary,
      effectiveStyleContext: context.effectiveStyleContext,
      knownContactName: context.knownContactName,
    );
    final outcome = await _billing.run(
      ownerUserId: ownerUserId,
      fingerprint: optimizeFingerprint,
      onReadyToSend: onReadyToSend,
      send: (pending) async {
        final result = await _optimizeDraft(
          messages: context.requestMessages,
          sessionContext: sessionContext,
          conversationSummary: context.conversationSummary,
          partnerSummary: context.partnerSummary,
          effectiveStyleContext: context.effectiveStyleContext,
          knownContactName: context.knownContactName,
          userDraft: draft,
          requestId: pending.requestId,
          onTelemetry: onTelemetry,
        );
        if (result.optimizedMessage == null ||
            result.optimizedMessage!.optimized.trim().isEmpty) {
          throw AnalysisException(
            '這次沒有產生可用的優化結果，請稍後再試。',
            code: 'OPTIMIZE_MESSAGE_RESULT_INVALID',
            suggestedAction: AnalysisErrorAction.wait,
          );
        }
        return result;
      },
    );

    // cancelled：使用者拒絕同意或畫面已離開，什麼都沒送出也沒鑄身分。
    if (!outcome.isSuccess) return null;

    final pending = outcome.pending!;
    _pendingAwaitingPresentation = pending;
    return PolishRunResult(pending: pending, result: outcome.result!);
  }

  /// 畫面確認付費潤飾結果確實呈現後收尾：markSuccess 並清掉 pending。
  /// 身分不符（已被較新的一輪覆蓋）時 no-op，保留 replay 能力。
  Future<void> acknowledgePolishPresented(
    OptimizeMessagePendingRequest pending,
  ) async {
    if (_pendingAwaitingPresentation?.requestId != pending.requestId) {
      return;
    }
    await _billing.markSuccess(pending);
    if (_pendingAwaitingPresentation?.requestId == pending.requestId) {
      _pendingAwaitingPresentation = null;
    }
  }

  /// 讀回同一原句最近一次微調稿。讀失敗就當作沒有草稿：這只是方便用的
  /// 快取，不能為了它擋住面板。任務卡只讀同一個卡片規格存的稿。
  Future<ReplyRefineDraftSnapshot?> restoreRefineDraft({
    required String ownerUserId,
    required String originText,
    GuideV3RefineSpec? guideV3Card,
  }) async {
    try {
      return await _draftStore.loadFor(
        ownerUserId: ownerUserId,
        originText: originText,
        scope: _draftScope(guideV3Card),
      );
    } catch (_) {
      return null;
    }
  }

  /// 草稿分區：任務卡依卡片規格（任務、口吻、做法）分開，跟一般微調也分開。
  static String? _draftScope(GuideV3RefineSpec? card) => card == null
      ? null
      : 'guide_v3:${card.task}:${card.voice}:${card.method}';

  /// 回覆微調一輪：與潤飾共用同一條 exactly-once 帳本；指令進 fingerprint，
  /// 同一句話的兩種指令不會共用同一顆 requestId 而 replay 出上一輪結果。
  ///
  /// 順序不能反：先把已付費結果落到本機暫存，成功了才輪到畫面在可見幀後
  /// markSuccess。存檔失敗時保留 pending（restorable=false），同一份輸入的
  /// 下一次送出會走 replay 拿回同一個結果，不重複扣費。
  ///
  /// [guideV3Card]＝任務卡的再調：卡片規格跟指令一樣進 fingerprint 與請求，
  /// 計費照回覆微調。
  Future<RefineRoundResult?> runRefineRound({
    required String ownerUserId,
    required AuxiliaryAnalysisContext context,
    required SessionContext? sessionContext,
    required String currentText,
    required String instruction,
    required String anchorText,
    required Future<bool> Function() onReadyToSend,
    required AnalysisTelemetryCallback onTelemetry,
    GuideV3RefineSpec? guideV3Card,
  }) async {
    final fingerprint = _billing.fingerprintFor(
      messages: context.requestMessages,
      userDraft: currentText,
      sessionContext: sessionContext,
      conversationSummary: context.conversationSummary,
      partnerSummary: context.partnerSummary,
      effectiveStyleContext: context.effectiveStyleContext,
      knownContactName: context.knownContactName,
      refineInstruction: instruction,
      guideV3Card: guideV3Card,
    );
    final OptimizeBillingOutcome outcome;
    try {
      outcome = await _billing.run(
        ownerUserId: ownerUserId,
        fingerprint: fingerprint,
        onReadyToSend: onReadyToSend,
        send: (pending) async {
          final result = await _refineReply(
            messages: context.requestMessages,
            sessionContext: sessionContext,
            conversationSummary: context.conversationSummary,
            partnerSummary: context.partnerSummary,
            effectiveStyleContext: context.effectiveStyleContext,
            knownContactName: context.knownContactName,
            userDraft: currentText,
            refineInstruction: instruction,
            // 多輪漂移錨：永遠帶「這串微調最初的原句」，讓 server 的
            // anchor_action 條款有錨可判——第 N 版不得長出原句沒有的邀約。
            refineAnchorText: anchorText,
            guideV3Card: guideV3Card,
            requestId: pending.requestId,
            onTelemetry: onTelemetry,
          );
          final refined = result.optimizedMessage?.optimized.trim();
          // 任務卡：只收伺服器標了「已過任務卡定稿」的結果（主審第 2 輪；還沒升版的 Edge
          // 不會標），原稿有空格時也要照則留住空格。擋下用的錯誤碼不在 runner 的換身分
          // 清單裡：同一份輸入再按帶同一顆 requestId，伺服器 replay、不再扣。
          if (refined == null ||
              refined.isEmpty ||
              (guideV3Card != null &&
                  (result.rawResponse?['guideV3CardChecked'] != true ||
                      !guideV3RefineKeepsBlanks(
                        _cardLines(currentText),
                        _cardLines(refined),
                      )))) {
            throw AnalysisException(
              '這次沒有調出可用的版本，請再試一次。',
              code: 'OPTIMIZE_MESSAGE_RESULT_INVALID',
              suggestedAction: AnalysisErrorAction.wait,
            );
          }
          return result;
        },
      );
    } catch (_) {
      // 丟出例外不代表沒用掉免費次數（伺服器可能先用掉、結算才失敗）：記成待確認。
      // 取消回 null，什麼都沒送出，不動它。
      _refineFreeRemainingStale = true;
      rethrow;
    }
    if (!outcome.isSuccess) return null;

    final pending = outcome.pending!;
    final result = outcome.result!;
    final usage = result.rawResponse?['usage'];
    final freeRemaining = usage is Map ? usage['refineFreeRemaining'] : null;
    final freeDailyLimit = usage is Map ? usage['refineFreeDailyLimit'] : null;
    if (freeRemaining is num) {
      _refineFreeRemaining = freeRemaining.round();
      _refineFreeRemainingStale = false;
    }
    final refinedText = result.optimizedMessage!.optimized.trim();
    var restorable = false;
    try {
      await _draftStore.save(
        ownerUserId: ownerUserId,
        originText: anchorText,
        refinedText: refinedText,
        requestId: pending.requestId,
        scope: _draftScope(guideV3Card),
      );
      restorable = true;
    } catch (_) {}

    return RefineRoundResult(
      pending: pending,
      result: result,
      refinedText: refinedText,
      freeRemaining: freeRemaining is num ? freeRemaining.round() : null,
      freeDailyLimit: freeDailyLimit is num ? freeDailyLimit.round() : null,
      chargedQuota: usage is Map && usage['shouldChargeQuota'] == true,
      restorable: restorable,
    );
  }

  /// 任務卡的幾則用換行接成一段送（伺服器回來也是一則一行）。
  static List<String> _cardLines(String text) => text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  /// 微調後複製的獨立事件 key。原卡的 adviceId 是決定論的，覆寫它污染的
  /// 不只是統計：outcome digest 會回注 coach prompt，教練會以為你送出的是
  /// 原句。requestId 是這一輪微調的冪等鍵，重複複製同一版不會多記一筆；
  /// 沒有穩定冪等鍵就回 null——寧可少一筆樣本，也不要記出無法去重的髒資料。
  static String? refineCopyEventId({
    required String? originAdviceId,
    required String? requestId,
  }) {
    if (originAdviceId == null || requestId == null || requestId.isEmpty) {
      return null;
    }
    return 'refine:$originAdviceId:$requestId';
  }

  /// 微調結果呈現在面板（蓋在本頁上的 route）後的收尾：只 markSuccess，
  /// 不經過 polish 的 pending 身分（微調不使用 awaiting-presentation 槽）。
  Future<void> acknowledgeRefinePresented(
    OptimizeMessagePendingRequest pending,
  ) {
    return _billing.markSuccess(pending);
  }
}
