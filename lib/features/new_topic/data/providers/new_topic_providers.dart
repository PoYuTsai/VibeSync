import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../../user_profile/data/providers/partner_style_providers.dart';
import '../../../user_profile/data/providers/user_profile_providers.dart';
import '../../domain/services/new_topic_partner_context_builder.dart';

/// 新話題的 Spec 2.5 style context。鏡像 openerStyleContextProvider 的
/// Future-based 設計：async 依賴 await 完才 beginAttempt 鑄 requestId，
/// 避免冷啟動 sync 讀到 loading 造成指紋漂移（同 Codex R1 P2 教訓）。
final newTopicStyleContextProvider =
    FutureProvider.family<String?, String?>((ref, partnerId) async {
  final global = await ref.watch(userProfileControllerProvider.future);
  final builder = ref.watch(effectiveStylePromptBuilderProvider);

  final id = partnerId?.trim();
  if (id == null || id.isEmpty) {
    return builder.buildForNewTopic(
      global: global,
      partner: null,
      includePartnerOverride: false,
    );
  }

  // Spec 3: flagged partner card 暫停 partner-specific style memory。
  final includePartnerOverride =
      !ref.watch(dataQualityFlagProvider(id)).isFlagged;
  final partner = includePartnerOverride
      ? await ref.watch(partnerStyleOverrideProvider(id).future)
      : null;

  return builder.buildForNewTopic(
    global: global,
    partner: partner,
    includePartnerOverride: includePartnerOverride,
  );
});

/// 對象作戰板脈絡：owner-scoped Partner＋其 conversations。Partner 不存在
/// 回 empty（readiness 另行判 missingPartner）。
final newTopicPartnerContextProvider =
    Provider.family<NewTopicPartnerContext, String>((ref, partnerId) {
  final partner = ref.watch(partnerByIdProvider(partnerId));
  if (partner == null) return NewTopicPartnerContext.empty;
  final conversations = ref.watch(conversationsByPartnerProvider(partnerId));
  return NewTopicPartnerContextBuilder().build(
    partner: partner,
    conversations: conversations,
  );
});

/// 生成 readiness（計畫 §9.5）。
enum NewTopicReadiness {
  /// route/選擇的 partnerId 不在 owner-scoped partner list。
  missingPartner,

  /// Partner 被 data-quality flag 判定不可用：必須阻擋，不能用
  /// About Me／情境繞過。
  dataQualityBlocked,

  /// Partner 有實質作戰板訊號。
  readyWithPartnerSignals,

  /// Partner 合法但沒有實質訊號——仍可靠 style context 或 situation 生成
  /// （UI 應提示建議可能較通用）。
  readyWithoutPartnerSignals,
}

/// 有效 partnerId 必須存在於 owner-scoped partner list（不能只用未驗證
/// lookup）；之後才看 data-quality flag 與作戰板訊號。
final newTopicReadinessProvider =
    Provider.family<NewTopicReadiness, String>((ref, partnerId) {
  final partners = ref.watch(partnerListProvider);
  final exists = partners.any((p) => p.id == partnerId);
  if (!exists) return NewTopicReadiness.missingPartner;

  if (ref.watch(dataQualityFlagProvider(partnerId)).isFlagged) {
    return NewTopicReadiness.dataQualityBlocked;
  }

  final context = ref.watch(newTopicPartnerContextProvider(partnerId));
  return context.hasActionableSignals
      ? NewTopicReadiness.readyWithPartnerSignals
      : NewTopicReadiness.readyWithoutPartnerSignals;
});

/// Generation readiness 總判（計畫 §9.5）：
/// partner 存在 AND 未 flagged AND（作戰板有訊號 OR style context 非空 OR
/// situation 已選）。
bool canGenerateNewTopic({
  required NewTopicReadiness readiness,
  required String? styleContext,
  required String? situation,
}) {
  if (readiness == NewTopicReadiness.missingPartner ||
      readiness == NewTopicReadiness.dataQualityBlocked) {
    return false;
  }
  if (readiness == NewTopicReadiness.readyWithPartnerSignals) return true;
  return (styleContext?.trim().isNotEmpty ?? false) ||
      (situation?.trim().isNotEmpty ?? false);
}
