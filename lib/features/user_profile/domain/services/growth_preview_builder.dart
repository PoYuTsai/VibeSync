import '../entities/user_profile.dart';

/// 存檔後的成長框架預覽——純本地模板句，不呼叫 AI、不扣額度。
///
/// 規格 PR-7：只說教練真的會讀的東西。互動風格不再送給教練，拿掉「教練知道
/// 你平常偏…」；常聊話題不會送給 AI，只填了話題時回 null、不顯示預覽。
class GrowthPreviewBuilder {
  const GrowthPreviewBuilder();

  String? build({
    required List<StuckPoint> stuckPoints,
    required List<PracticeGoal> goals,
    required bool hasNotes,
  }) {
    final goalPhrase = goals.map(_goalPhrase).join('、');
    final stuckPhrase = stuckPoints.map(_stuckPhrase).join('、');

    if (goalPhrase.isNotEmpty && stuckPhrase.isNotEmpty) {
      return '你想$goalPhrase。教練會盯著你$stuckPhrase的地方，幫你往前推一步。';
    }
    if (goalPhrase.isNotEmpty) {
      return '你想$goalPhrase。教練會照著這個方向，幫你一步步往前推。';
    }
    if (stuckPhrase.isNotEmpty) {
      return '教練會盯著你$stuckPhrase的地方，幫你找方法往前推一步。';
    }
    if (hasNotes) {
      return '教練會參考你寫的「想讓 AI 知道的事」，抓對時機幫你往前推一步。';
    }
    return null;
  }

  static String _goalPhrase(PracticeGoal g) => switch (g) {
        PracticeGoal.softInvite => '約得出來',
        PracticeGoal.comfortableChat => '先能自在聊天',
        PracticeGoal.humorousReply => '讓對話更幽默、有來有往',
        PracticeGoal.buildCloseness => '培養穩定的親近感',
        PracticeGoal.findCompatiblePartner => '找到聊得來的對象',
      };

  static String _stuckPhrase(StuckPoint s) => switch (s) {
        StuckPoint.fadesOut => '話題卡住接不下去',
        StuckPoint.dontKnowHowToAsk => '不知道怎麼開口約',
        StuckPoint.anxiousWontSend => '緊張不敢傳',
        StuckPoint.overExplains => '容易解釋太多',
        StuckPoint.leftOnRead => '已讀不回',
      };
}
