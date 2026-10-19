/// 對話分析 v3（任務卡）的結果：伺服器 `guide_v3/wire.ts` 的 App 端鏡像。
///
/// 只有宣告協定版本 3 的 App 會收到；伺服器開關關著時照舊回 v2（五種風格），
/// 由 `AnalysisResult` 處理。v3 原本沒有熱度、階段、雷達（Eric 2026-10-17）；
/// 伺服器開了關係訊號才在判讀帶 [GuideV3Relation]（Bruce 2026-10-19 路線二），
/// 沒帶就是沒有，不補預設值：解析 v3 快照的地方要先用 [isGuideV3Payload] 認形狀，
/// 不能丟給 `AnalysisResult.fromJson`（它會補熱度 50）。
library;

import 'enthusiasm_level.dart';
import 'game_stage.dart';

/// 需要他自己填的空格（伺服器 `BLANK_PATTERN`；提示詞要求寫成「＿＿」）。
const guideV3BlankMark = '＿';

bool guideV3TextHasBlank(String text) => text.contains(guideV3BlankMark);

/// 一則裡有幾段空格（連著的「＿」算一段；跟伺服器 `refine_card.ts` 同一套算法）。
int guideV3BlankRuns(String text) =>
    RegExp('$guideV3BlankMark+').allMatches(text).length;

/// 「再調一下」的結果有沒有照則留住空格：原稿有空格時，則數要一樣、每一則的空格段數
/// 也要一樣（伺服器 `finalizeRefinedCard` 的同一條規則；還沒升版的 Edge 不查，App 這裡
/// 再擋一次，免得編出來的身分資料不經填空就被複製走；主審第 1 輪 P2-3／P2-5）。
bool guideV3RefineKeepsBlanks(List<String> before, List<String> after) {
  if (!before.any(guideV3TextHasBlank)) return true;
  if (before.length != after.length) return false;
  for (var i = 0; i < before.length; i++) {
    if (guideV3BlankRuns(before[i]) != guideV3BlankRuns(after[i])) return false;
  }
  return true;
}

/// 卡片任務（伺服器 `TASK_CODE`）。標籤直接給用戶看（設計文件第 5 節）。
enum GuideV3Task {
  accept('accept', '接住'),
  resonate('resonate', '共鳴'),
  tension('tension', '帶張力'),
  push('push', '推進'),
  close('close', '收');

  const GuideV3Task(this.wire, this.label);

  final String wire;
  final String label;

  static GuideV3Task? fromWire(Object? value) {
    for (final task in values) {
      if (task.wire == value) return task;
    }
    return null;
  }
}

/// 這一輪怎麼做（伺服器 `planTurn`）：出卡、收尾、先別回、停、自傷關心。
enum GuideV3Decision {
  send('send'),
  close('close'),
  hold('hold'),
  stop('stop'),
  care('care');

  const GuideV3Decision(this.wire);

  final String wire;

  static GuideV3Decision? fromWire(Object? value) {
    for (final decision in values) {
      if (decision.wire == value) return decision;
    }
    return null;
  }

  /// 會出卡的決定；其餘只有判讀（關心只有固定文案）。
  bool get hasCards =>
      this == GuideV3Decision.send || this == GuideV3Decision.close;

  /// 不催他回去找她：關心（自傷、未成年）與停（她拒絕或封鎖）之後，不問也不排 48 小時
  /// 跟進提醒，已排的那則收回（P1 安全修正）。先別回只是等一下，照舊。
  bool get silencesFollowUp =>
      this == GuideV3Decision.care || this == GuideV3Decision.stop;
}

/// 固定訊息（care）是哪一種（伺服器 `careKind`，Eric 2026-10-18 加未成年）：自傷關心，
/// 或涉及未成年。舊快照沒有這欄，當成自傷關心。
enum GuideV3CareKind {
  selfHarm('self_harm'),
  minor('minor');

  const GuideV3CareKind(this.wire);

  final String wire;

  static GuideV3CareKind fromWire(Object? value) =>
      value == GuideV3CareKind.minor.wire
          ? GuideV3CareKind.minor
          : GuideV3CareKind.selfHarm;
}

/// 局面燈號（讀局面的 light）。
enum GuideV3Light {
  green('green', '綠燈'),
  yellow('yellow', '黃燈'),
  red('red', '紅燈');

  const GuideV3Light(this.wire, this.label);

  final String wire;
  final String label;

  static GuideV3Light? fromWire(Object? value) {
    for (final light in values) {
      if (light.wire == value) return light;
    }
    return null;
  }
}

/// 邀約進度（伺服器 `INVITE_READINESS_CODE`；Eric 2026-10-18 燈號紀錄＋邀約進度）。標籤先
/// 沿用讀局面的類別名，Bruce 之後可能改字；App 只認代碼，不認得的當沒有。
enum GuideV3InviteReadiness {
  none('none', '沒機會'),
  declined('declined', '婉拒過'),
  vagueYes('vague_yes', '含糊答應'),
  clearYes('clear_yes', '明確答應'),
  sheProposed('she_proposed', '她自己提見面'),
  sheCancelled('she_cancelled', '她取消了'),
  hesitant('hesitant', '猶豫');

  const GuideV3InviteReadiness(this.wire, this.label);

  final String wire;
  final String label;

  static GuideV3InviteReadiness? fromWire(Object? value) {
    for (final readiness in values) {
      if (readiness.wire == value) return readiness;
    }
    return null;
  }
}

/// 她這一輪在做什麼（伺服器讀局面的 herMove，送 App 時換成 `guide_v3/wire.ts` 的
/// HER_MOVE_CODE）。[label] 是給用戶看的白話（Eric review 時核准）；App 只認代碼，不認得的
/// 當沒有。
enum GuideV3HerMove {
  dailyLife('daily_life', '聊她的日常'),
  emotion('emotion', '在講心情'),
  highPoint('high_point', '分享開心的事'),
  laughEnding('laugh_ending', '笑著收尾'),
  teasing('teasing', '在虧你'),
  testing('testing', '在試探你'),
  seriousQuestion('serious_question', '認真在問你'),
  asksAboutHim('asks_about_him', '想多了解你'),
  asksHisOpinion('asks_his_opinion', '想聽你的意見'),
  openWindow('open_window', '給你約她的機會'),
  braking('braking', '想放慢一點');

  const GuideV3HerMove(this.wire, this.label);

  final String wire;
  final String label;

  static GuideV3HerMove? fromWire(Object? value) {
    for (final move in values) {
      if (move.wire == value) return move;
    }
    return null;
  }
}

/// 回覆意願（讀局面的 replyWillingness：只看她有沒有延伸、反問、補內容）。
enum GuideV3Willingness {
  high('high', '她很想聊'),
  medium('medium', '有回，但沒多聊'),
  low('low', '興趣不高');

  const GuideV3Willingness(this.wire, this.label);

  final String wire;
  final String label;

  static GuideV3Willingness? fromWire(Object? value) {
    for (final willingness in values) {
      if (willingness.wire == value) return willingness;
    }
    return null;
  }
}

/// 五維雷達的鍵，跟 v2 的 dimensions 同一組（`AnalysisResult.dimensionScores` 的形狀）。
const guideV3RelationDimensionKeys = [
  'heat',
  'engagement',
  'topicDepth',
  'replyWillingness',
  'emotionalConnection',
];

/// 關係狀態（`analysis.read` 的 relation；伺服器開關 ANALYZE_GUIDE_V3_RELATION）：v2 的關係
/// 階段、熱度、五維雷達，加上她這一輪在做什麼與回覆意願（Bruce 2026-10-19 路線二：留在 v3，
/// 把 v2 好的部分帶回來）。開關沒開、改版前的結果、關心都沒有；伺服器丟掉或 App 讀不懂的
/// 欄位各自是 null，不影響判讀與卡。
class GuideV3Relation {
  const GuideV3Relation({
    this.stage,
    this.heat,
    this.dimensions,
    this.herMove,
    this.willingness,
  });

  /// 關係階段（v2 的五個代碼）。
  final GameStage? stage;

  /// 伺服器送的原始熱度（0–100 的整數，v2 定義）。顯示與存檔用 [visibleHeat]。
  final int? heat;

  /// 五維雷達（[guideV3RelationDimensionKeys] 五個都在、都是 0–100 的整數才收）。
  final Map<String, int>? dimensions;
  final GuideV3HerMove? herMove;
  final GuideV3Willingness? willingness;

  /// 給用戶看、存進對話與紀錄的熱度：v2 的投入度是伺服器收尾時照 ceil(原始 × 0.9) 換成
  /// 0–90（post_process.ts），v3 的熱度照同一個換法，新舊分數才能放在同一條趨勢上。
  int? get visibleHeat {
    final raw = heat;
    return raw == null ? null : calibrateVisibleInvestment(raw);
  }

  static bool _isScore(Object? value) =>
      value is int && value >= 0 && value <= 100;

  /// 不是物件、或每一欄都讀不懂就回 null（等於沒送）。
  static GuideV3Relation? fromJson(Object? json) {
    if (json is! Map) return null;
    final rawHeat = json['heat'];
    final rawDimensions = json['dimensions'];
    Map<String, int>? dimensions;
    if (rawDimensions is Map &&
        guideV3RelationDimensionKeys
            .every((key) => _isScore(rawDimensions[key]))) {
      dimensions = Map.unmodifiable({
        for (final key in guideV3RelationDimensionKeys)
          key: rawDimensions[key] as int,
      });
    }
    final relation = GuideV3Relation(
      stage: GameStage.tryFromString(
        json['stage'] is String ? json['stage'] as String : null,
      ),
      heat: _isScore(rawHeat) ? rawHeat as int : null,
      dimensions: dimensions,
      herMove: GuideV3HerMove.fromWire(json['herMove']),
      willingness: GuideV3Willingness.fromWire(json['willingness']),
    );
    final empty = relation.stage == null &&
        relation.heat == null &&
        relation.dimensions == null &&
        relation.herMove == null &&
        relation.willingness == null;
    return empty ? null : relation;
  }
}

/// 給新話題的冷訊號（伺服器 `cold`；不分方案，Eric 2026-10-18）。[c1]＝這一輪是 C1「他連續
/// 主動兩次、她都只回敷衍的字」判的先別回；[herPerfunctoryStreak]＝她最近連續幾輪只回敷衍的字。
class GuideV3ColdSignal {
  const GuideV3ColdSignal({
    required this.c1,
    required this.herPerfunctoryStreak,
  });

  final bool c1;
  final int herPerfunctoryStreak;

  static GuideV3ColdSignal? fromJson(Object? json) {
    if (json is! Map) return null;
    final c1 = json['c1'];
    final streak = json['herPerfunctoryStreak'];
    if (c1 is! bool || streak is! int || streak < 0) return null;
    return GuideV3ColdSignal(c1: c1, herPerfunctoryStreak: streak);
  }
}

/// 預定的一張卡（照順序）。locked＝這個方案看不到：免費方案只寫、只送前幾張，
/// 其餘伺服器不寫也不送，App 只顯示任務標籤與升級提示。
class GuideV3PlannedCard {
  const GuideV3PlannedCard({
    required this.slot,
    required this.task,
    required this.locked,
  });

  final int slot;
  final GuideV3Task task;
  final bool locked;

  static GuideV3PlannedCard? fromJson(Object? json) {
    if (json is! Map) return null;
    final slot = json['slot'];
    final task = GuideV3Task.fromWire(json['task']);
    if (slot is! int || slot < 1 || task == null) return null;
    return GuideV3PlannedCard(
      slot: slot,
      task: task,
      locked: json['locked'] == true,
    );
  }
}

/// 局面判讀（`analysis.read` 事件，也在最終結果的 `read`）。
class GuideV3Read {
  const GuideV3Read({
    required this.guideVersion,
    required this.decision,
    required this.light,
    required this.judgment,
    this.waitFor,
    this.careMessage,
    this.careKind,
    this.inviteReadiness,
    this.cold,
    this.relation,
    this.plannedCards = const [],
  });

  final String guideVersion;
  final GuideV3Decision decision;

  /// 讀不懂的燈號回 null，畫面就不顯示燈號（不猜顏色）。
  final GuideV3Light? light;

  /// 伺服器檢查過的判讀；被檢查拿掉時是空字串。
  final String judgment;

  /// 先別回時「要等她做什麼」。
  final String? waitFor;

  /// 固定訊息的文案（伺服器 `CARE_MESSAGE` 或 `MINOR_MESSAGE`）。
  final String? careMessage;

  /// 固定訊息的種類；不是 care 就是 null。
  final GuideV3CareKind? careKind;

  /// 邀約進度；care、舊快照（伺服器還沒送這欄）或不認得的代碼是 null。
  final GuideV3InviteReadiness? inviteReadiness;

  /// 冷訊號；care、舊快照或格式不對是 null。
  final GuideV3ColdSignal? cold;

  /// 關係狀態；伺服器開關沒開、改版前的快照、讀不懂都是 null。關心一律不收：固定訊息那次
  /// 不拿來算階段、熱度與雷達（跟伺服器 care 不送同一個做法）。
  final GuideV3Relation? relation;
  final List<GuideV3PlannedCard> plannedCards;

  List<GuideV3PlannedCard> get lockedCards =>
      plannedCards.where((card) => card.locked).toList(growable: false);

  bool get hasLockedCards => plannedCards.any((card) => card.locked);

  /// 這個方案會送到的張數（不含 locked）。
  int get deliverableCount => plannedCards.where((card) => !card.locked).length;

  static GuideV3Read? fromJson(Object? json) {
    if (json is! Map) return null;
    final decision = GuideV3Decision.fromWire(json['decision']);
    if (decision == null) return null;
    String? text(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    final planned = <GuideV3PlannedCard>[];
    final rawPlanned = json['plannedCards'];
    if (rawPlanned is List) {
      for (final raw in rawPlanned) {
        final card = GuideV3PlannedCard.fromJson(raw);
        if (card != null) planned.add(card);
      }
    }
    planned.sort((a, b) => a.slot.compareTo(b.slot));
    return GuideV3Read(
      guideVersion: text(json['guideVersion']) ?? '',
      decision: decision,
      light: GuideV3Light.fromWire(json['light']),
      judgment: text(json['judgment']) ?? '',
      waitFor: decision == GuideV3Decision.hold ? text(json['waitFor']) : null,
      careMessage:
          decision == GuideV3Decision.care ? text(json['careMessage']) : null,
      careKind: decision == GuideV3Decision.care
          ? GuideV3CareKind.fromWire(json['careKind'])
          : null,
      inviteReadiness: decision == GuideV3Decision.care
          ? null
          : GuideV3InviteReadiness.fromWire(json['inviteReadiness']),
      cold: decision == GuideV3Decision.care
          ? null
          : GuideV3ColdSignal.fromJson(json['cold']),
      relation: decision == GuideV3Decision.care
          ? null
          : GuideV3Relation.fromJson(json['relation']),
      plannedCards: List.unmodifiable(planned),
    );
  }
}

/// 伺服器 `VOICE_CODE`／`METHOD_CODE`（照他、預設；只用反應、用他說過的、留空格、照樣寫＋標示）。
const _guideV3VoiceWires = {'his', 'default'};
const _guideV3MethodWires = {'reaction', 'his_facts', 'blank', 'invented'};

/// 「再調一下」帶給伺服器的卡片規格：任務、口吻、「有他」做法（伺服器
/// `guide_v3/refine_card.ts` 只收出卡用的代碼，用來保住這張卡的任務與口吻）。
class GuideV3RefineSpec {
  const GuideV3RefineSpec({
    required this.task,
    required this.voice,
    required this.method,
  });

  final String task;
  final String voice;
  final String method;

  Map<String, String> toJson() => {
        'task': task,
        'voice': voice,
        'method': method,
      };

  @override
  bool operator ==(Object other) =>
      other is GuideV3RefineSpec &&
      other.task == task &&
      other.voice == voice &&
      other.method == method;

  @override
  int get hashCode => Object.hash(task, voice, method);
}

/// 一張任務卡（`analysis.card` 事件，也在最終結果的 `cards`）。
class GuideV3Card {
  const GuideV3Card({
    required this.slot,
    required this.task,
    required this.messages,
    required this.hasInventedDetail,
    required this.raw,
  });

  /// 預定的第幾張（1 起算）。
  final int slot;
  final GuideV3Task task;

  /// 一張卡可以是好幾則（分開傳）；伺服器送出前已定稿，App 不改字。
  final List<String> messages;

  /// 照樣寫＋標示：卡上有編的細節，要提醒他改成自己的。
  final bool hasInventedDetail;

  /// 伺服器送來的原樣（存檔、續看合併時照原樣寫回）。
  final Map<String, dynamic> raw;

  /// 空格以內容為準（「＿」），不只看伺服器旗標：有空格就一定要填好才能複製。
  bool get hasBlank => messages.any(guideV3TextHasBlank);

  /// 整張複製：跟 v2 回覆卡同樣用換行接起來。
  String get copyText => messages.join('\n');

  /// 「再調一下」要帶的規格；舊快照缺口吻或做法、或代碼不認得就回 null（不給再調）。
  GuideV3RefineSpec? get refineSpec {
    final voice = raw['voice'];
    final method = raw['method'];
    if (voice is! String ||
        method is! String ||
        !_guideV3VoiceWires.contains(voice) ||
        !_guideV3MethodWires.contains(method)) {
      return null;
    }
    return GuideV3RefineSpec(task: task.wire, voice: voice, method: method);
  }

  static GuideV3Card? fromJson(Object? json) {
    if (json is! Map) return null;
    final slot = json['slot'];
    final task = GuideV3Task.fromWire(json['task']);
    final rawMessages = json['messages'];
    if (slot is! int || slot < 1 || task == null || rawMessages is! List) {
      return null;
    }
    final messages = <String>[];
    for (final raw in rawMessages) {
      if (raw is! String) return null;
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) messages.add(trimmed);
    }
    if (messages.isEmpty) return null;
    return GuideV3Card(
      slot: slot,
      task: task,
      messages: List.unmodifiable(messages),
      hasInventedDetail: json['hasInventedDetail'] == true,
      raw: Map<String, dynamic>.unmodifiable(
        json.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
  }
}

/// 這次送到的比預定的少：伺服器標 partial（有卡被檢查拿掉，或寫到一半斷了）、續看時從扣費
/// 內容重組（recovered，原請求中途被終止），或送到的卡比這個方案預定的少。結果頁「這次比預定
/// 的少幾張」用這個判斷（對象頁燈號紀錄 10/19 起不推升級，不再用它）。
bool guideV3DeliveredFewer({
  required bool partial,
  required bool recovered,
  required int deliveredCards,
  required int deliverableCards,
}) =>
    partial || recovered || deliveredCards < deliverableCards;

/// 「為什麼這樣回」（伺服器 `analysis.card_explain`；兩段式實驗，Bruce 2026-10-19 路線二：
/// 結果頁每張卡下面一段）。卡都送完、done 之前，每張卡一則；[card] 是那張卡的 slot。
class GuideV3CardExplain {
  const GuideV3CardExplain({required this.card, required this.text});

  final int card;
  final String text;

  static GuideV3CardExplain? fromJson(Object? json) {
    if (json is! Map) return null;
    final card = json['card'];
    final text = json['text'];
    if (card is! int || card < 1 || text is! String) return null;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return GuideV3CardExplain(card: card, text: trimmed);
  }
}

/// App 自己存進 v3 快照的「為什麼這樣回」：伺服器的最終結果不帶（只在串流事件送），收到的
/// 照 slot 跟卡一起存，重開畫面、分析紀錄才看得到。舊快照沒有這欄。
const guideV3CardExplainsKey = 'cardExplains';

Map<int, String> _cardExplainsFrom(Object? json) {
  if (json is! List) return const {};
  final explains = <int, String>{};
  for (final raw in json) {
    final explain = GuideV3CardExplain.fromJson(raw);
    if (explain != null) explains.putIfAbsent(explain.card, () => explain.text);
  }
  return Map.unmodifiable(explains);
}

/// 伺服器 `isGuideV3FinalResult`：字串 guideVersion＋cards 陣列。
bool isGuideV3Payload(Object? json) =>
    json is Map && json['guideVersion'] is String && json['cards'] is List;

/// v3 的最終結果（`analysis.done` 的 finalResult，也是存檔的快照）。
class GuideV3Result {
  const GuideV3Result({
    required this.read,
    required this.cards,
    required this.partial,
    required this.recovered,
    required this.rawResponse,
    this.cardExplains = const {},
  });

  final GuideV3Read read;

  /// 照 slot 排好的卡（已送出、定稿過的）。
  final List<GuideV3Card> cards;

  /// 這次比預定的少（有卡被檢查拿掉，或寫到一半斷了）。
  final bool partial;

  /// 原請求中途被終止，續看時從扣費內容重組（只有判讀＋第一張卡）。
  final bool recovered;

  /// 伺服器送來的原樣（已剝掉伺服器專用欄位）；存檔與成效紀錄用。
  final Map<String, dynamic> rawResponse;

  /// 每張卡的「為什麼這樣回」（slot → 說明）；沒送或舊快照是空的。
  final Map<int, String> cardExplains;

  GuideV3Decision get decision => read.decision;

  /// 見 [guideV3DeliveredFewer]。
  bool get deliveredFewer => guideV3DeliveredFewer(
        partial: partial,
        recovered: recovered,
        deliveredCards: cards.length,
        deliverableCards: read.deliverableCount,
      );

  Map<String, dynamic>? get usage {
    final raw = rawResponse['usage'];
    if (raw is! Map) return null;
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  /// 結果頁給不給「我已有草稿，幫我修自然」：只有出卡與收尾給（Eric 2026-10-18）。潤飾會
  /// 保留草稿想說的事、只把壓力調低，停（她拒絕或封鎖）時等於幫他繼續施壓；先別回改成
  /// 導去問教練；固定訊息本來就不給。
  bool get offersDraftPolish => read.decision.hasCards;

  /// 固定訊息（自傷關心、涉及未成年）不扣費（伺服器 chargeQuota=false），存檔不推進字數
  /// 基準；畫面不給問教練、潤飾與回饋。
  bool get isCare => read.decision == GuideV3Decision.care;

  static GuideV3Result? fromJson(Map<String, dynamic> json) {
    if (!isGuideV3Payload(json)) return null;
    final read = GuideV3Read.fromJson(json['read']);
    if (read == null) return null;
    final bySlot = <int, GuideV3Card>{};
    for (final raw in json['cards'] as List) {
      final card = GuideV3Card.fromJson(raw);
      if (card != null) bySlot.putIfAbsent(card.slot, () => card);
    }
    final cards = bySlot.values.toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));
    return GuideV3Result(
      read: read,
      cards: List.unmodifiable(cards),
      partial: json['partial'] == true,
      recovered: json['recovered'] == true,
      rawResponse: json,
      cardExplains: _cardExplainsFrom(json[guideV3CardExplainsKey]),
    );
  }

  /// 串流收到的「為什麼這樣回」補進結果，連存檔的原樣一起改（[guideV3CardExplainsKey]）。
  /// 已經有的那張不覆蓋；沒有新的就回自己。
  GuideV3Result withCardExplains(Map<int, String> explains) {
    final merged = <int, String>{...explains, ...cardExplains};
    if (merged.length == cardExplains.length) return this;
    final slots = merged.keys.toList()..sort();
    return GuideV3Result(
      read: read,
      cards: cards,
      partial: partial,
      recovered: recovered,
      rawResponse: <String, dynamic>{
        ...rawResponse,
        guideV3CardExplainsKey: [
          for (final slot in slots) {'card': slot, 'text': merged[slot]},
        ],
      },
      cardExplains: Map.unmodifiable(merged),
    );
  }

  /// 續看重組（[recovered]）只帶回第一張卡；同一個 run 畫面上已經送到的卡要留著，
  /// 照 slot 補回來，連存檔的原樣一起改。沒有要補的就回自己。
  GuideV3Result withShownCards(List<GuideV3Card> shown) {
    final known = {for (final card in cards) card.slot};
    final missing = shown.where((card) => !known.contains(card.slot)).toList();
    if (missing.isEmpty) return this;
    final merged = [...cards, ...missing]
      ..sort((a, b) => a.slot.compareTo(b.slot));
    return GuideV3Result(
      read: read,
      cards: List.unmodifiable(merged),
      partial: partial,
      recovered: recovered,
      rawResponse: <String, dynamic>{
        ...rawResponse,
        'cards': merged.map((card) => card.raw).toList(growable: false),
      },
      cardExplains: cardExplains,
    );
  }
}
