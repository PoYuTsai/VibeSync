// 認識場合顯示文字：鏡像 server
// supabase/functions/practice-chat/acquaintance_origin.ts 的
// buildAcquaintanceOrigin — 同一個 profileId+threadId 永遠算出同一個管道，
// client 靠這份鏡像獨立算出跟 server 一致的值，不必為了顯示多打一次 API。
//
// 絕不自建分歧：id、順序、FNV-1a 演算法、seed 組法（profileId|threadId|
// acquaintance-origin）、campus 資格限制，全部逐字對照 server 檔案，這樣選中
// 的管道（哪一筆）才會跟 AI 對話裡帶出的場景一致；server 改這份清單時，這裡
// 必須同批改。sharedFact 的「文字內容」是唯一例外——server 版本是寫給 AI 人設
// 看的（第二人稱「你」＝她本人），client 版本是寫給真人使用者看的（第二人稱
// 「你」＝使用者），兩邊視角相反，逐字複製會讓某些管道（如 ig_cold_dm）讀起來
// 角色顛倒；只要傳達的事實一致，這裡的用字可以跟 server 不同。
library;

/// 單一認識管道的顯示內容（只保留 client 用得到的欄位；server 端還有
/// stancePrompt/unverifiedGuard/hintFocus/debriefStandard 這些純 prompt 欄位，
/// client 不需要）。
class PracticeAcquaintanceOrigin {
  const PracticeAcquaintanceOrigin({
    required this.id,
    required this.label,
    required this.sharedFact,
  });

  /// 對齊 server 端 AcquaintanceOriginId（snake_case）。
  final String id;

  /// 可見短標籤，如「朋友介紹」。
  final String label;

  /// 雙方都知道的既定事實，一句話——這是卡片上要顯示的文字。
  final String sharedFact;
}

class _OriginConfig {
  const _OriginConfig({
    required this.id,
    required this.label,
    required this.sharedFact,
    this.eligibleFor,
  });

  final String id;
  final String label;
  final String sharedFact;

  /// 缺席＝所有 profile 都適用；只有 campus 需要還在學校的身分。
  final bool Function(String professionId)? eligibleFor;
}

const Set<String> _campusProfessions = {'college_student', 'graduate_student'};

bool _isCampusEligible(String professionId) =>
    _campusProfessions.contains(professionId);

/// 逐字對照 server `ACQUAINTANCE_ORIGINS`，順序不可調動（deterministic seed
/// 依賴陣列索引，順序一變，既有進行中的 thread 就會換場景）。
const List<_OriginConfig> _origins = [
  _OriginConfig(
    id: 'friend_intro',
    label: '朋友介紹',
    sharedFact: '你們是共同朋友介紹認識的，前陣子才拿到彼此的聯絡方式，還沒單獨見過面。',
  ),
  _OriginConfig(
    id: 'dating_app',
    label: '交友軟體',
    sharedFact: '你們是在交友軟體上互相配對到才開始聊的，只看過對方的照片和幾行自介，沒見過面。',
  ),
  // sharedFact 刻意不逐字對照 server：server 版本「你」＝她本人（搭話的人是
  // 使用者），逐字搬來會變成「她在路上主動搭訕你」，不合常理。事實同一件——
  // 主動搭話、要聯絡方式的都是使用者——只是敘述視角換成讀者本人。
  _OriginConfig(
    id: 'street_approach',
    label: '街頭搭訕',
    sharedFact: '你那天在路上鼓起勇氣跟她搭話，聊沒幾句就跟她要了聯絡方式，她半推半就給了。',
  ),
  // sharedFact 刻意不逐字對照 server：server 版本是寫給 AI 人設看的（「你」=
  // 她本人，私訊的人是使用者），直接搬來給真人使用者看會變成「她主動私訊你」，
  // 讀起來不合常理（女生很少主動冷私訊陌生男生）。這裡改成對真人讀者的口吻，
  // 講的是同一件事——使用者才是那個主動私訊的人——只是敘述視角換成讀者本人。
  _OriginConfig(
    id: 'ig_cold_dm',
    label: 'IG 陌生私訊',
    sharedFact: '你們沒有共同朋友。你是在 IG 限動上看到她、好奇之下才私訊她的，這是你們第一次真正搭上話，之前你就只在她的頁面上看過大頭貼和版面。',
  ),
  _OriginConfig(
    id: 'nightclub',
    label: '夜店認識',
    sharedFact: '你們是那天晚上在夜店或酒吧認識的，現場很吵，只聊了幾句就互加聯絡方式。',
  ),
  _OriginConfig(
    id: 'social_gathering',
    label: '聚會認識',
    sharedFact: '你們是在朋友揪的聚會上認識的（一群人吃飯、桌遊或慶生那種），現場人多，你們只聊到片段。',
  ),
  _OriginConfig(
    id: 'campus',
    label: '校園認識',
    sharedFact: '你們是在學校認識的——同一堂課、系上活動或圖書館那種場合，平常還會在同個地方遇到。',
    eligibleFor: _isCampusEligible,
  ),
  _OriginConfig(
    id: 'hobby_class',
    label: '共同興趣場合',
    sharedFact: '你們是在共同興趣的場合認識的（課程、社團、球隊或工作坊那種），會固定在那裡碰到。',
  ),
  // sharedFact 刻意不逐字對照 server：server 版本「你」＝她本人（工作場合是
  // 她的），逐字搬來會變成「你的工作場合」，跟 AI 演的「她的工作、你是客人/
  // 合作對象」直接矛盾。
  _OriginConfig(
    id: 'work_encounter',
    label: '工作場合認識',
    sharedFact: '你們是在她工作（或打工）的場合認識的——你是客人、合作對象或同業那種關係，一開始只是公事往來。',
  ),
  _OriginConfig(
    id: 'travel_trip',
    label: '旅途中認識',
    sharedFact: '你們是在旅行途中認識的（同一段行程、同一間旅宿或路上聊起來那種），那時候心情放鬆才互加。',
  ),
];

/// FNV-1a：逐字對照 server `fnv1a`（同 offset/prime，32-bit 無號 wrap）。
int _fnv1a(String value) {
  const fnvOffset = 0x811c9dc5;
  const fnvPrime = 0x01000193;
  var hash = fnvOffset;
  for (final codeUnit in value.codeUnits) {
    hash ^= codeUnit;
    hash = (hash * fnvPrime) & 0xFFFFFFFF;
  }
  return hash;
}

List<_OriginConfig> _eligibleOrigins(String professionId) {
  final eligible = _origins
      .where((o) => o.eligibleFor == null || o.eligibleFor!(professionId))
      .toList();
  return eligible.isEmpty ? [_origins.first] : eligible;
}

/// 逐字對照 server `threadIdForPracticeRequest`：優先用穩定的
/// visiblePracticeThreadId，缺席或空字串才 fallback 到 sessionId。
String practiceThreadIdFor({
  required String sessionId,
  String? visiblePracticeThreadId,
}) {
  final trimmed = visiblePracticeThreadId?.trim();
  return (trimmed != null && trimmed.isNotEmpty) ? trimmed : sessionId;
}

/// 逐字對照 server `buildAcquaintanceOrigin`：
/// `pool[fnv1a('$profileId|$threadId|acquaintance-origin') % pool.length]`。
PracticeAcquaintanceOrigin practiceAcquaintanceOriginFor({
  required String profileId,
  required String professionId,
  required String threadId,
}) {
  final pool = _eligibleOrigins(professionId);
  final seed = '$profileId|$threadId|acquaintance-origin';
  final picked = pool[_fnv1a(seed) % pool.length];
  return PracticeAcquaintanceOrigin(
    id: picked.id,
    label: picked.label,
    sharedFact: picked.sharedFact,
  );
}
