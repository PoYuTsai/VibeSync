import '../entities/user_profile.dart';

/// 存檔後的成長框架預覽——純本地模板句，不呼叫 AI、不扣額度。
class GrowthPreviewBuilder {
  const GrowthPreviewBuilder();

  String build({
    required List<StuckPoint> stuckPoints,
    required List<PracticeGoal> goals,
    required InteractionStyle? comfortStyle,
  }) {
    final goalPhrase = goals.map(_goalPhrase).join('、');
    final stuckPhrase = stuckPoints.map(_stuckPhrase).join('、');

    final String main;
    if (goalPhrase.isNotEmpty && stuckPhrase.isNotEmpty) {
      main = '你想$goalPhrase。教練會盯著你$stuckPhrase的地方，幫你往前推一步。';
    } else if (goalPhrase.isNotEmpty) {
      main = '你想$goalPhrase。教練會照著這個方向，幫你一步步往前推。';
    } else if (stuckPhrase.isNotEmpty) {
      main = '教練會盯著你$stuckPhrase的地方，幫你找方法往前推一步。';
    } else {
      main = '教練會先摸清你的說話習慣和邊界，抓對時機幫你往前推一步。';
    }

    if (comfortStyle == null) return main;
    return '$main\n教練知道你平常偏${_styleLabel(comfortStyle)}，'
        '會照你的步調來，不會突然要你變一個人。';
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

  static String _styleLabel(InteractionStyle s) => switch (s) {
        InteractionStyle.steady => '穩重',
        InteractionStyle.direct => '直接',
        InteractionStyle.humorous => '幽默',
        InteractionStyle.gentle => '溫柔',
        InteractionStyle.playful => '俏皮',
      };
}
