// lib/features/learning/domain/models/ebook_block.dart
//
// 互動電子書的內容區塊模型。
//
// 設計約束（2026-07-25 施工規格）：
//   - 內容真源是 bundled JSON，解析後一律變成這裡的 typed sealed blocks，
//     renderer 對 sealed 做 exhaustive switch，新增型別時編譯器會迫使補 UI。
//   - JSON 只放 semantic keys：這裡不出現 Color / IconData / Widget / route。
//     三燈、callout tone、speaker 都是語意 enum，顏色與圖示在 presentation 決定。
//   - Quiz choice 一律用 stable string id，永不用陣列 index 當儲存值，
//     否則之後調整選項順序會讓已保存的答案指向錯的選項。
library;

/// 對話泡泡的角色。教材用語意角色，不綁真實使用者身分。
enum EbookSpeaker { you, other, coach }

/// 三燈。UI 必須同時輸出文字與圖示，不能只用紅黃綠顏色。
enum EbookSignal { green, yellow, red }

/// Callout 語意層級。`safety` 是安全／同意／撤退提醒，內容不變量會檢查
/// 涉及邀約與升級的章節至少有一個。
enum EbookCalloutTone { info, principle, goal, safety, warning, takeaway, fix }

/// 比較區塊裡每一項的立場。`weak` / `strong` 用於「弱版 vs 強版」對照，
/// `neutral` 用於單純並列（例如事實版 vs 狀態感受版的說明欄）。
enum EbookComparisonStance { weak, strong, neutral }

/// Quiz 作答模式。`multiple` 存在的理由：一句話可以同時動 V 與 E，
/// 不能硬逼使用者只選一個「正確變數」。
enum EbookQuizMode { single, multiple }

/// 答錯之後的行為。預設 [untilCorrect]；[lockedAfterSubmit] 只保留給
/// Eric／夥伴明確指定的題目，不寫死在 progress service。
enum EbookQuizRetryPolicy { untilCorrect, lockedAfterSubmit }

/// 章節內容區塊。
///
/// [id] 在整個 catalog 內唯一（catalog 載入時驗證），因為互動型區塊的 id
/// 同時是本機進度的儲存鍵。
sealed class EbookBlock {
  const EbookBlock({required this.id});

  final String id;
}

class EbookHeadingBlock extends EbookBlock {
  const EbookHeadingBlock({
    required super.id,
    required this.text,
  });

  final String text;
}

class EbookParagraphBlock extends EbookBlock {
  const EbookParagraphBlock({
    required super.id,
    required this.text,
  });

  final String text;
}

class EbookBulletListBlock extends EbookBlock {
  const EbookBulletListBlock({
    required super.id,
    required this.items,
    this.title,
    this.ordered = false,
  });

  final String? title;
  final List<String> items;
  final bool ordered;
}

class EbookCalloutBlock extends EbookBlock {
  const EbookCalloutBlock({
    required super.id,
    required this.tone,
    required this.text,
    this.title,
  });

  final EbookCalloutTone tone;
  final String? title;
  final String text;
}

class EbookComparisonItem {
  const EbookComparisonItem({
    required this.id,
    required this.stance,
    required this.label,
    required this.text,
    this.note,
  });

  final String id;
  final EbookComparisonStance stance;
  final String label;
  final String text;
  final String? note;
}

class EbookComparisonBlock extends EbookBlock {
  const EbookComparisonBlock({
    required super.id,
    required this.items,
    this.title,
    this.caption,
  });

  final String? title;
  final String? caption;
  final List<EbookComparisonItem> items;
}

/// 教材用對話泡泡的一句。display-only，不重用 production conversation bubble
/// （那會帶進時間戳、已讀狀態與互動依賴）。
class EbookDialogueLine {
  const EbookDialogueLine({
    required this.id,
    required this.speaker,
    required this.text,
    this.timeLabel,
    this.annotation,
    this.signal,
    this.isDeathPoint = false,
  });

  final String id;
  final EbookSpeaker speaker;
  final String text;

  /// 案例 D（回覆時間操作）需要顯示相對時間，其餘案例留空。
  final String? timeLabel;

  /// 逐句標記說明，例如「V↑ 側面露出生活；E↑ 自嘲」。
  final String? annotation;
  final EbookSignal? signal;

  /// 死亡點。UI 用文字標籤＋圖示標示，不只靠顏色。
  final bool isDeathPoint;
}

class EbookDialogueBlock extends EbookBlock {
  const EbookDialogueBlock({
    required super.id,
    required this.lines,
    this.title,
    this.caption,
  });

  final String? title;
  final String? caption;
  final List<EbookDialogueLine> lines;
}

/// 翻卡：正面情境／對話，背面機制與修正。翻面狀態刻意不持久化。
class EbookFlipCardBlock extends EbookBlock {
  const EbookFlipCardBlock({
    required super.id,
    required this.frontTitle,
    required this.frontText,
    required this.backTitle,
    required this.backText,
    this.backPoints = const <String>[],
  });

  final String frontTitle;
  final String frontText;
  final String backTitle;
  final String backText;
  final List<String> backPoints;
}

class EbookQuizChoice {
  const EbookQuizChoice({
    required this.id,
    required this.text,
    required this.isCorrect,
    required this.feedback,
  });

  final String id;
  final String text;
  final bool isCorrect;

  /// 每個選項自己的白話回饋，提交後才顯示。
  final String feedback;
}

class EbookQuizBlock extends EbookBlock {
  const EbookQuizBlock({
    required super.id,
    required this.question,
    required this.mode,
    required this.retryPolicy,
    required this.revision,
    required this.choices,
    required this.takeaway,
    this.scenario,
  });

  final String question;

  /// 題目前的情境敘述（可空）。
  final String? scenario;
  final EbookQuizMode mode;
  final EbookQuizRetryPolicy retryPolicy;

  /// 題目語意版本。改動選項語意時要 +1，讓舊答案失效重答。
  final int revision;
  final List<EbookQuizChoice> choices;
  final String takeaway;

  List<String> get correctChoiceIds => choices
      .where((choice) => choice.isCorrect)
      .map((choice) => choice.id)
      .toList(growable: false);

  /// 判定一組選擇是否算答對：正解集合必須完全相同。
  bool isSolvedBy(Set<String> selectedChoiceIds) {
    final correct = correctChoiceIds.toSet();
    return selectedChoiceIds.length == correct.length &&
        selectedChoiceIds.containsAll(correct);
  }
}

/// 漏斗自我診斷的一層。
///
/// 為什麼帶 target id 而不帶 route 字串：JSON 只放語意 key，route 組裝留在
/// presentation。target 是否真的存在由 catalog 載入時驗證，避免內容改章 id
/// 之後這裡靜默指向不存在的章節。
class EbookFunnelStage {
  const EbookFunnelStage({
    required this.id,
    required this.number,
    required this.stageName,
    required this.symptom,
    required this.verdictTitle,
    required this.verdictText,
    required this.targetBookId,
    required this.targetChapterId,
    required this.targetLabel,
  });

  final String id;

  /// 顯示用層號（例如 `0`）。刻意不用陣列 index，內容調整順序時才不會錯位。
  final String number;

  /// 階段名，例如「階段 · 開場」。
  final String stageName;

  /// 白話症狀敘述，讀者靠這句認自己，不必算任何數字。
  final String symptom;

  final String verdictTitle;
  final String verdictText;

  final String targetBookId;
  final String targetChapterId;

  /// 前往按鈕的文字，例如「前往〈六張照片，各有一個工作〉」。
  final String targetLabel;
}

/// 階段漏斗：讀者點選最像自己現況的一層，得到一段判斷與一個跳章入口。
///
/// 這個型別存在的理由（2026-07-26 夥伴回饋）：原本第一章要讀者先記錄六個
/// 數字、再讀一段教練示範對話、再答一題算術型 quiz 才知道自己卡在哪。實測
/// 「不方便閱讀」。漏斗把同一個診斷收斂成一次點選。
///
/// 選擇狀態刻意不持久化（與翻卡同理由）：這是讀者當下的自我定位，不是進度，
/// 也不該讓舊選擇在幾週後回來誤導人。
class EbookStageFunnelBlock extends EbookBlock {
  const EbookStageFunnelBlock({
    required super.id,
    required this.title,
    required this.intro,
    required this.stages,
  });

  final String title;
  final String intro;
  final List<EbookFunnelStage> stages;
}

/// 條目庫的一條。
///
/// [summary] 是列表上那一行摘要，[blocks] 是展開後的內容。刻意允許巢狀
/// block（案例要放對話＋註解＋修正），但 parser 禁止再放 entryList——
/// 兩層以上的收合在手機上找不回自己在哪。
class EbookEntry {
  const EbookEntry({
    required this.id,
    required this.title,
    required this.blocks,
    this.summary,
  });

  final String id;
  final String title;
  final String? summary;
  final List<EbookBlock> blocks;
}

/// 條目庫：列表 → 點開一條 → 才看到內文。
///
/// 存在理由（2026-07-27）：教材裡有一半篇幅是「查的」而不是「讀的」——
/// 開場範例 8 型、對話拆解 13 案例、疑難情境 8 條、FAQ 12 條。這些若攤成
/// 長捲，單一章節會出現四千字沒有段落標記的牆。
class EbookEntryListBlock extends EbookBlock {
  const EbookEntryListBlock({
    required super.id,
    required this.entries,
    this.title,
    this.caption,
  });

  final String? title;
  final String? caption;
  final List<EbookEntry> entries;
}

class EbookChecklistItem {
  const EbookChecklistItem({
    required this.id,
    required this.text,
    this.note,
  });

  final String id;
  final String text;
  final String? note;
}

/// Checklist 只保存 item id 與 bool，永不接受自由文字。
class EbookChecklistBlock extends EbookBlock {
  const EbookChecklistBlock({
    required super.id,
    required this.items,
    this.title,
    this.caption,
  });

  final String? title;
  final String? caption;
  final List<EbookChecklistItem> items;
}
