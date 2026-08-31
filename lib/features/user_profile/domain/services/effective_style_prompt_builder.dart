import '../entities/partner_style_override.dart';
import '../entities/user_profile.dart';
import 'resolve_effective_style.dart';

/// Spec 2.5 — converts About Me + per-partner style settings into compact AI
/// context. This is the only contract layer that should translate profile
/// settings into prompt text.
///
/// 2026-08-04 拍板：關於我只用來增加 Coach 1:1 對使用者的了解，不再影響
/// analyze-chat 五風格回覆／開場白／新話題的實際輸出內容。互動風格／
/// 舒適區（延伸標記）概念一併移除——「關於我」的互動風格選擇區塊也已從
/// UI 拿掉。[buildForAnalysis]／[buildForOpener]／[buildForNewTopic] 因此
/// 恆定回傳 null；呼叫端本來就把 null 視為「沒有關於我設定」的正常狀態。
class EffectiveStylePromptBuilder {
  static const int coachFollowUpMaxChars = 900;

  const EffectiveStylePromptBuilder();

  /// analyze-chat / my_message / userDraft optimize 不再讀取關於我。
  String? buildForAnalysis({
    required UserProfile? global,
    required PartnerStyleOverride? partner,
    required bool includePartnerOverride,
  }) =>
      null;

  /// Opener (F3-1) 不再讀取關於我。
  String? buildForOpener({
    required UserProfile? global,
    required PartnerStyleOverride? partner,
    required bool includePartnerOverride,
  }) =>
      null;

  /// New Topic（破冰腦力）不再讀取關於我。
  String? buildForNewTopic({
    required UserProfile? global,
    required PartnerStyleOverride? partner,
    required bool includePartnerOverride,
  }) =>
      null;

  /// Lightweight slice for Spec 5 coach-follow-up.
  ///
  /// 2026-08 關於我重新定位案 批3：補讀 stuckPoints（現在卡住的處境）與
  /// notes（使用者邊界）——先前故意不讀是為了避免長期人格推斷，這次拍板
  /// 補上是因為處境與邊界屬於「現在」而非長期人格。Topics 仍不進來，
  /// 因為那是話題素材不是語氣/處境設定。
  String? buildForCoachFollowUp({
    required UserProfile? global,
    required PartnerStyleOverride? partner,
    required bool includePartnerOverride,
  }) {
    final effective = resolveEffectiveStyle(
      global: global,
      partner: includePartnerOverride ? partner : null,
    );
    final lines = <String>[];

    // 2026-08-31 語言守門案：標籤全中文——英文標籤（Stuck points／Boundary…）
    // 會被模型當成「這裡可以夾英文」的示範抄進可貼句（同 08-29「早safe」）。
    if (effective.stuckPoints.isNotEmpty) {
      lines.add(
        '- 卡住的處境：${effective.stuckPoints.map(_stuckPointLabel).join('、')}；'
        '回答時要接住這個情境，不要給通用建議。',
      );
    }

    if (effective.practiceGoals.isNotEmpty) {
      lines.add(
        '- 練習重點：${effective.practiceGoals.map(_goalLabel).join('、')}；'
        '${effective.practiceGoals.map(_goalPrompt).join(' ')}',
      );
    }

    final notes = effective.notes?.trim();
    if (notes != null && notes.isNotEmpty) {
      lines.add('- 使用者邊界：$notes；任何建議都不能違反。');
    }

    if (lines.isEmpty) return null;
    lines.add(
      '- 使用範圍：僅用來調整教練語氣與任務框架；不要拿來推斷對方或寫長期人格。',
    );
    return _truncate(lines.join('\n'), coachFollowUpMaxChars);
  }

  static String _stuckPointLabel(StuckPoint s) => switch (s) {
        StuckPoint.fadesOut => '話題卡住接不下去',
        StuckPoint.dontKnowHowToAsk => '不知道怎麼開口約',
        StuckPoint.anxiousWontSend => '緊張不敢傳',
        StuckPoint.overExplains => '容易解釋太多',
        StuckPoint.leftOnRead => '已讀不回',
      };

  static String _goalLabel(PracticeGoal goal) {
    switch (goal) {
      case PracticeGoal.softInvite:
        return '想約得出來';
      case PracticeGoal.comfortableChat:
        return '想先能自在聊天';
      case PracticeGoal.humorousReply:
        return '想讓對話更幽默、有來有往';
      case PracticeGoal.buildCloseness:
        return '想培養穩定的親近感';
      case PracticeGoal.findCompatiblePartner:
        return '想找到聊得來的對象';
    }
  }

  static String _goalPrompt(PracticeGoal goal) {
    switch (goal) {
      case PracticeGoal.softInvite:
        return '更早給清楚但低壓的邀約方向。';
      case PracticeGoal.comfortableChat:
        return '避免連續確認、追問或把對方反應綁到自我價值。';
      case PracticeGoal.humorousReply:
        return '優先給自然、短、好接的幽默。';
      case PracticeGoal.buildCloseness:
        return '多用情緒與小故事建立連結，不只交換資訊。';
      case PracticeGoal.findCompatiblePartner:
        return '保持開放、不預設對方要符合單一條件；重點是找到聊得來的感覺，不要急著篩選或設限。';
    }
  }

  static String _truncate(String value, int maxChars) {
    if (value.length <= maxChars) return value;
    return '${value.substring(0, maxChars - 1).trimRight()}…';
  }
}
