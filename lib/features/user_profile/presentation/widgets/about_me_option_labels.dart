import '../../domain/entities/user_profile.dart';

/// 「關於我」卡點與練習重點在畫面上的中文名稱：關於我頁面、摘要卡，以及教練
/// 「要不要加到關於我」那一行（規格 PR-9）共用這一份。給教練讀的短標籤在
/// EffectiveStylePromptBuilder，用途不同，不要合併。
String stuckPointLabel(StuckPoint s) => switch (s) {
      StuckPoint.fadesOut => '聊一聊就冷掉，不知道怎麼接下去',
      StuckPoint.dontKnowHowToAsk => '不知道怎麼開口約',
      StuckPoint.anxiousWontSend => '會緊張、怕講錯話不敢傳',
      StuckPoint.overExplains => '話太多、一直在解釋自己',
      StuckPoint.leftOnRead => '一直被已讀不回',
    };

String practiceGoalLabel(PracticeGoal g) => switch (g) {
      PracticeGoal.softInvite => '想約得出來',
      PracticeGoal.comfortableChat => '想先能自在聊天，不要那麼緊繃',
      PracticeGoal.humorousReply => '想讓對話更幽默、有來有往',
      PracticeGoal.buildCloseness => '想培養穩定的親近感',
      PracticeGoal.findCompatiblePartner => '想找到聊得來的對象、不設限交往',
    };
