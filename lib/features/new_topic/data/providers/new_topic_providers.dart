import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../partner/presentation/providers/partner_providers.dart';
import '../../../user_profile/data/providers/data_quality_flag_provider.dart';
import '../../domain/services/new_topic_partner_context_builder.dart';
import '../services/new_topic_request_session.dart';

/// 非 autoDispose：離開畫面後仍在 app 的 ProviderScope 保留凍結請求。
/// 使用者與對象共同隔離；不落盤，App 關閉後不保留。
typedef NewTopicRequestSessionKey = ({String ownerId, String partnerId});

final newTopicRequestSessionProvider =
    Provider.family<NewTopicRequestSession, NewTopicRequestSessionKey>(
  (ref, key) => NewTopicRequestSession(),
);

/// 新話題送出的 effectiveStyleContext。「關於我」只給 Coach 1:1
/// （2026-08-04），這裡固定回 null，不讀任何關於我或對象風格設定；伺服器
/// 也不把它算成素材（2026-10-20）。
///
/// Provider 本身保留：畫面每次嘗試前會 await 它，再和 requestId 一起凍結進
/// 請求（同 openerStyleContextProvider）。拿掉它要一併改畫面與防重複邏輯，
/// 另案處理。
final newTopicStyleContextProvider =
    FutureProvider.family<String?, String?>((ref, partnerId) async => null);

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
  /// 情境或素材原文繞過。
  dataQualityBlocked,

  /// Partner 有實質作戰板訊號。
  readyWithPartnerSignals,

  /// Partner 合法但沒有實質訊號——仍可靠情境或素材原文生成
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
/// partner 存在 AND 未 flagged AND（作戰板有訊號 OR situation 已選 OR 有送
/// 素材原文；同 server hasNewTopicMaterial）。「關於我」只給 Coach 1:1，
/// 不算素材。
bool canGenerateNewTopic({
  required NewTopicReadiness readiness,
  required String? situation,
  bool hasMaterialText = false,
}) {
  if (readiness == NewTopicReadiness.missingPartner ||
      readiness == NewTopicReadiness.dataQualityBlocked) {
    return false;
  }
  if (readiness == NewTopicReadiness.readyWithPartnerSignals) return true;
  return hasMaterialText || (situation?.trim().isNotEmpty ?? false);
}
