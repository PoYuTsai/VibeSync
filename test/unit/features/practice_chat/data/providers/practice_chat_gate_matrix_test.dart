import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_learning_mode.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_profile.dart';

/// 練習室動作閘門「行為保證書」：把今天四個 getter（canSend / canRequestHint /
/// canDebrief / canChangeLearningMode）的正確答案拍照存證，之後任何狀態管理
/// 重構都必須原樣通過這張表。
///
/// 這是產品可達狀態的**代表性**合約表（人工挑選的列），不是全狀態空間枚舉；
/// 期望值全部手寫，不得從 getter 導出（否則檢查恆真）；斷言的是行為，
/// 不鏡像 getter 的實作條件。
void main() {
  final girl = girlProfileById('practice_girl_010')!;

  PracticeChatState base() => PracticeChatState(
        sessionId: 'sess-gate',
        createdAt: DateTime(2026, 8, 28, 12),
        girl: girl,
        personaId: girl.personaId,
        personaLabel: '暖場',
        difficulty: 'normal',
        difficultyLabel: '普通',
        learningMode: PracticeLearningMode.beginner,
        messages: const [
          PracticeMessage(role: 'user', text: '嗨'),
          PracticeMessage(role: 'ai', text: '嗯？'),
        ],
        aiReplyCount: 1,
      );

  const debriefCard = PracticeDebrief(
    summary: '整體不錯',
    strengths: ['開場自然'],
    watchouts: [],
    suggestedLine: '下次直接約她',
    vibe: '暖',
    dateChance: 'medium',
    dateChanceReason: '她有回應。',
    nextInviteMove: '先丟一個模糊邀約。',
  );

  // (名稱, 狀態, canSend, canRequestHint, canDebrief, canChangeLearningMode)
  final rows = <(String, PracticeChatState, bool, bool, bool, bool)>[
    (
      '未翻牌：locked、無對象、無訊息 → 四個動作全部關閉',
      PracticeChatState(
        sessionId: 'sess-gate',
        createdAt: DateTime(2026, 8, 28, 12),
        girl: null,
        personaId: 'p',
        personaLabel: 'P',
        difficulty: 'normal',
        difficultyLabel: '普通',
        drawStatus: PracticeDrawStatus.locked,
      ),
      false, false, false, false,
    ),
    (
      '翻牌動畫中（drawing、無對象）：四個動作全部關閉',
      PracticeChatState(
        sessionId: 'sess-gate',
        createdAt: DateTime(2026, 8, 28, 12),
        girl: null,
        personaId: 'p',
        personaLabel: 'P',
        difficulty: 'normal',
        difficultyLabel: '普通',
        drawStatus: PracticeDrawStatus.drawing,
      ),
      false, false, false, false,
    ),
    (
      '剛翻牌還沒開聊（standard）：可送出、可改模式；沒有 AI 回覆前不能提示也不能拆解',
      base().copyWith(
        learningMode: PracticeLearningMode.standard,
        messages: const [],
        aiReplyCount: 0,
      ),
      true, false, false, true,
    ),
    (
      '剛翻牌還沒開聊（beginner）：同上，新手模式也要等第一則 AI 回覆才有提示',
      base().copyWith(messages: const [], aiReplyCount: 0),
      true, false, false, true,
    ),
    (
      '新手模式對話中（AI 剛回完）：送出／提示／拆解全開；已開聊不能再改模式',
      base(),
      true, true, true, false,
    ),
    (
      'standard 模式對話中：提示是輔助學習模式限定',
      base().copyWith(learningMode: PracticeLearningMode.standard),
      true, false, true, false,
    ),
    (
      '送出中（isSending，樂觀泡泡在場）：全部關閉，防平行請求交錯',
      base().copyWith(
        isSending: true,
        messages: const [
          PracticeMessage(role: 'user', text: '嗨'),
          PracticeMessage(role: 'ai', text: '嗯？'),
          PracticeMessage(role: 'user', text: '今天在忙什麼'),
        ],
      ),
      false, false, false, false,
    ),
    (
      // 隱藏規則存證：持久化中閘門 getter 不擋提示；實際攔截靠
      // sendMessage 的 pipeline token（_activeSendPipelineToken）。
      'AI 已回、本機持久化中（isPersistingTurn）：送出與拆解關閉；提示 getter 放行',
      base().copyWith(isPersistingTurn: true),
      false, true, false, false,
    ),
    (
      '提示生成中（isHintLoading）：全部關閉（與送出雙向互斥）',
      base().copyWith(isHintLoading: true),
      false, false, false, false,
    ),
    (
      '拆解生成中（isDebriefing、已 ended）：全部關閉',
      base().copyWith(isDebriefing: true, ended: true),
      false, false, false, false,
    ),
    (
      '拆解失敗可重試（ended、debriefFailed、retryable）：只剩「再拆解一次」',
      base().copyWith(ended: true, debriefFailed: true, debriefRetryable: true),
      false, false, true, false,
    ),
    (
      '拆解次數用完（ended、failed、不可重試、sessionComplete）：全部關閉',
      base().copyWith(
        ended: true,
        sessionComplete: true,
        debriefFailed: true,
        debriefRetryable: false,
      ),
      false, false, false, false,
    ),
    (
      '拆解完成（ended、sessionComplete、卡片在場）：全部關閉',
      base().copyWith(ended: true, sessionComplete: true, debrief: debriefCard),
      false, false, false, false,
    ),
    (
      '重開後舊拆解已退役（ended、hasRetiredDebrief）：不得再拆解',
      base().copyWith(ended: true, hasRetiredDebrief: true),
      false, false, false, false,
    ),
    (
      '20 則滿場（sessionComplete、未 ended）：不能再送出或提示；可以拆解收尾',
      base().copyWith(sessionComplete: true, aiReplyCount: 20),
      false, false, true, false,
    ),
    (
      '提示額度用完（hintLimitReached）：提示關閉，其餘不受影響',
      base().copyWith(
        hintLimitReached: true,
        hintUsedCount: kMaxPracticeHintsPerRound,
      ),
      true, false, true, false,
    ),
    (
      '提示額度用完但本輪有退役快照（hasRetiredHintForCurrentTurn）：准許同 id 替換一次',
      base().copyWith(
        hintLimitReached: true,
        hintUsedCount: kMaxPracticeHintsPerRound,
        hasRetiredHintForCurrentTurn: true,
      ),
      true, true, true, false,
    ),
    (
      '提示用滿上限（usedCount == cap、flag 未同步）：本機也要擋，不能靠 server flag',
      base().copyWith(hintUsedCount: kMaxPracticeHintsPerRound),
      true, false, true, false,
    ),
    (
      // 隱藏規則存證：429/402 牆不由這四個閘門收斂，靠錯誤文案與付費牆 UI；
      // 額度真的用罄時 server 會再擋一次。
      '429 額度用罄旗標（quotaExceeded）：四個閘門今天不看它',
      base().copyWith(quotaExceeded: true),
      true, true, true, false,
    ),
    (
      '402 續玩升級牆旗標（upgradeRequired）：四個閘門今天不看它',
      base().copyWith(upgradeRequired: true),
      true, true, true, false,
    ),
    (
      '最後一則是使用者訊息（她還沒回）：不能對自己的話要提示',
      base().copyWith(
        messages: const [
          PracticeMessage(role: 'user', text: '嗨'),
          PracticeMessage(role: 'ai', text: '嗯？'),
          PracticeMessage(role: 'user', text: '今天在忙什麼'),
        ],
      ),
      true, false, true, false,
    ),
  ];

  test('gate matrix：產品可達狀態下四個動作閘門的合約表', () {
    for (final (name, state, send, hint, debrief, mode) in rows) {
      expect(state.canSend, send, reason: '$name → canSend');
      expect(state.canRequestHint, hint, reason: '$name → canRequestHint');
      expect(state.canDebrief, debrief, reason: '$name → canDebrief');
      expect(state.canChangeLearningMode, mode,
          reason: '$name → canChangeLearningMode');
    }
  });

  test('gate matrix：在途請求互斥性質（任何列都不得違反）', () {
    for (final (name, state, _, _, _, _) in rows) {
      expect(state.canSend && state.isHintLoading, false,
          reason: '$name → hint 在途不得送出');
      expect(state.canSend && state.isSending, false,
          reason: '$name → 送出中不得再送出');
      expect(state.canRequestHint && state.isSending, false,
          reason: '$name → 送出中不得要提示');
      expect(state.canRequestHint && state.isHintLoading, false,
          reason: '$name → 提示在途不得再要提示');
      expect(state.canDebrief && (state.isSending || state.isHintLoading),
          false, reason: '$name → 送出／提示在途不得拆解');
    }
  });
}
