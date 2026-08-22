import '../../../conversation/domain/entities/conversation.dart';
import '../../../conversation/domain/entities/session_context.dart';
import '../../../partner/domain/entities/partner.dart';
import '../../../partner/domain/services/partner_memory_tag_catalog.dart';

/// Resolves the starting context shown before screenshot analysis.
///
/// 對象卡是 meetingContext／duration／goal 的最新真相：卡上有設定就蓋過
/// conversation 既有 context（閉環規則——改成「已是伴侶」後的下一個分析
/// 片段必須拿到最新設定，舊 context 不得靜默擋住）。conversation 專屬
/// 欄位（userStyle／interests／描述／本次補充背景）仍沿用既有 context；
/// legacy partner（未設預設）與孤兒對話退回既有 context 或產品預設。
class ScreenshotSessionContextDefaults {
  const ScreenshotSessionContextDefaults._();

  static SessionContext resolve({
    required Conversation? conversation,
    required Partner? partner,
  }) {
    final existing = conversation?.sessionContext;
    if (existing != null) {
      return SessionContext(
        meetingContext:
            partner?.defaultMeetingContext ?? existing.meetingContext,
        duration: partner?.defaultAcquaintanceDuration ?? existing.duration,
        goal: partner?.defaultGoal ?? existing.goal,
        userStyle: existing.userStyle,
        userInterests: existing.userInterests,
        targetDescription: existing.targetDescription,
        analysisContextNote: _normalized(existing.analysisContextNote),
      );
    }

    return SessionContext(
      meetingContext:
          partner?.defaultMeetingContext ?? MeetingContext.datingApp,
      duration:
          partner?.defaultAcquaintanceDuration ?? AcquaintanceDuration.justMet,
      goal: partner?.defaultGoal ?? UserGoal.dateInvite,
      analysisContextNote:
          PartnerMemoryTagCatalog.sanitizedNote(partner?.customNote),
    );
  }

  static String? _normalized(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
