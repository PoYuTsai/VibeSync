/// 一位陪練女孩的「display-only」profile（與 Edge `practice_persona.ts` 的
/// `PracticeGirlProfile` 對齊，但**不含** prompt／reactionModel／signalStyle 等
/// server-only 欄位）。client 只拿來顯示與送 allowlisted id，絕不送 prompt 文字。
class PracticeGirlProfile {
  const PracticeGirlProfile({
    required this.profileId,
    required this.nameId,
    required this.displayName,
    required this.age,
    required this.heightCm,
    required this.city,
    required this.zodiac,
    required this.relationshipGoal,
    required this.professionId,
    required this.professionLabel,
    required this.photoId,
    required this.personaId,
    required this.personalityTags,
    required this.interestTags,
    required this.lifestyleTags,
    required this.selfIntro,
  });

  final String profileId;
  final String nameId;
  final String displayName;
  final int age;
  final int heightCm;
  final String city;
  final String zodiac;
  final String relationshipGoal;
  final String professionId;
  final String professionLabel;
  final String photoId;
  final String personaId;
  final List<String> personalityTags;
  final List<String> interestTags;
  final List<String> lifestyleTags;
  final String selfIntro;

  /// bundled 照片 asset 路徑（photoId == profileId == practice_girl_NNN）。
  /// 對應 `assets/images/practice_girls/`，由 tools/gen-practice-photos 產生。
  String get photoAssetPath => 'assets/images/practice_girls/$photoId.jpg';
}
