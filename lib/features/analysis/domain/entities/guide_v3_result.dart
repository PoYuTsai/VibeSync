/// 對話分析 v3（任務卡）的結果：伺服器 `guide_v3/wire.ts` 的 App 端鏡像。
///
/// 只有宣告協定版本 3 的 App 會收到；伺服器開關關著時照舊回 v2（五種風格），
/// 由 [AnalysisResult] 處理。v3 沒有熱度、階段、雷達（Eric 2026-10-17），
/// 所以這裡刻意不提供任何分數欄位：解析 v3 快照的地方要先用
/// [isGuideV3Payload] 認形狀，不能丟給 `AnalysisResult.fromJson`（它會補熱度 50）。
library;

/// 需要他自己填的空格（伺服器 `BLANK_PATTERN`；提示詞要求寫成「＿＿」）。
const guideV3BlankMark = '＿';

bool guideV3TextHasBlank(String text) => text.contains(guideV3BlankMark);

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

  /// 自傷關心的固定文案（伺服器 `CARE_MESSAGE`）。
  final String? careMessage;
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
      plannedCards: List.unmodifiable(planned),
    );
  }
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

  GuideV3Decision get decision => read.decision;

  Map<String, dynamic>? get usage {
    final raw = rawResponse['usage'];
    if (raw is! Map) return null;
    return raw.map((key, value) => MapEntry(key.toString(), value));
  }

  /// 自傷關心不扣費（伺服器 chargeQuota=false），存檔不推進字數基準。
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
    );
  }
}
