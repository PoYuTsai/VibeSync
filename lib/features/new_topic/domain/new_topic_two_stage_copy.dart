// 新話題兩段式（先問兩題再生成）的畫面文案集中檔：選項、追問、教練提醒、
// 輸入框、「這組根據」。Bruce 改文案只改這一檔（實作規格 §5.1）。
// value 是 server 契約，不可改；label 可以改。

import 'package:characters/characters.dart';

typedef NewTopicOption = ({String label, String value});

/// 生成前已經組好的教練提醒兩行。
typedef NewTopicCoachTip = ({String open, String avoid});

/// 畫面上目前的答案（不可變）。生成時由它產生選填的 `topicContext`。
class NewTopicTwoStageAnswers {
  const NewTopicTwoStageAnswers({
    this.situation,
    this.coldDuration,
    this.coldStop,
    this.engagement,
    this.materialKind,
    this.materialText = '',
  });

  final String? situation;
  final String? coldDuration;
  final String? coldStop;
  final String? engagement;
  final String? materialKind;
  final String materialText;

  /// 選了前四種素材＝必須寫一句（`none` 不用寫）。
  bool get needsMaterialText => materialKind != null && materialKind != 'none';

  String get trimmedMaterialText => materialText.trim();

  int get materialLength => trimmedMaterialText.characters.length;

  bool get materialMissing => needsMaterialText && trimmedMaterialText.isEmpty;

  bool get materialTooLong =>
      needsMaterialText &&
      materialLength > NewTopicTwoStageCopy.materialMaxGraphemes;

  /// 只有選了任一追問或素材才送；只選第一問回 null（走 legacy）。
  /// 追問只在搭得上第一問時才帶，避免 server 400。
  Map<String, dynamic>? toTopicContextJson() {
    final cold = situation == 'went_cold';
    final engaged = situation != null && !cold;
    final json = <String, dynamic>{
      if (cold && coldDuration != null) 'coldDuration': coldDuration,
      if (cold && coldStop != null) 'coldStop': coldStop,
      if (engaged && engagement != null) 'engagement': engagement,
      if (materialKind != null) 'materialKind': materialKind,
      if (needsMaterialText) 'materialText': trimmedMaterialText,
    };
    return json.isEmpty ? null : json;
  }
}

abstract final class NewTopicTwoStageCopy {
  static const situationTitle = '你們現在是什麼狀況？（選填）';
  static const materialTitle = '你手上有什麼可以聊？（選填）';
  static const coachTipTitle = '教練提醒';
  static const adjustButton = '調整狀況';

  static const situationOptions = <NewTopicOption>[
    (label: '冷掉了，想重新聊', value: 'went_cold'),
    (label: '還在聊，但接不下去', value: 'stuck'),
    (label: '剛約完會', value: 'after_date'),
    (label: '聊得不錯，想更靠近', value: 'warm_up'),
  ];

  static const _situationShort = {
    'went_cold': '冷掉了',
    'stuck': '還在聊但接不下去',
    'after_date': '剛約完會',
    'warm_up': '想更靠近',
  };

  static const coldDurationTitle = '多久沒聊了？';
  static const coldDurationOptions = <NewTopicOption>[
    (label: '幾天到一週', value: 'days'),
    (label: '一到四週', value: 'weeks'),
    (label: '一個月以上', value: 'month_plus'),
  ];

  static const coldStopTitle = '上次是怎麼停的？';
  static const coldStopOptions = <NewTopicOption>[
    (label: '聊著聊著就停了', value: 'faded'),
    (label: '她沒回我', value: 'she_no_reply'),
    (label: '我沒回她', value: 'i_no_reply'),
    (label: '她最近都回很冷', value: 'she_cold'),
  ];

  static String engagementTitle(String situation) =>
      situation == 'after_date' ? '約完之後她的反應？' : '她最近回你的樣子？';

  static List<NewTopicOption> engagementOptions(String situation) =>
      situation == 'after_date'
          ? const [
              (label: '主動傳訊息或說開心', value: 'green'),
              (label: '有回，但普通', value: 'yellow'),
              (label: '還沒回或很冷淡', value: 'red'),
            ]
          : const [
              (label: '會反問、聊很多', value: 'green'),
              (label: '有回，但很短', value: 'yellow'),
              (label: '常只回哈哈、嗯', value: 'red'),
            ];

  /// 順序＝公式庫的素材順序：真的聊過的事排第一，幫我想排最後。
  static List<NewTopicOption> materialOptions(String? situation) => [
        (
          label: situation == 'after_date' ? '約會時聊到的事' : '之前聊過的事',
          value: 'past_topic'
        ),
        (label: '看到想到她的東西', value: 'trigger'),
        (label: '我最近遇到的事', value: 'my_story'),
        (label: '我們之間的梗', value: 'inside_joke'),
        (label: '沒有，幫我想', value: 'none'),
      ];

  static String? materialInputTitle(String? kind, String? situation) =>
      switch (kind) {
        'past_topic' => situation == 'after_date' ? '約會時聊到什麼？' : '她之前提過什麼？',
        'trigger' => '看到什麼？為什麼想到她？',
        'my_story' => '發生什麼事？',
        'inside_joke' => '那個梗是什麼？',
        _ => null,
      };

  static String materialInputHint(String? kind) => switch (kind) {
        'past_topic' => '一句就好，例如：她說在準備潛水證照',
        'trigger' => '例如：路過一家超浮誇的甜點店，她說過愛吃甜（也可以是她發的限動）',
        'my_story' => '例如：信心滿滿走進店裡，才發現走錯分店',
        'inside_joke' => '例如：她說我的五分鐘都是半小時',
        _ => '',
      };

  static const materialHelper = '寫給教練看的就好，不用寫成要傳給她的句子。';
  static const materialMaxGraphemes = 150;
  static const materialMissingHint = '寫一句你手上的素材，或改選「沒有，幫我想」。';
  static const materialTooLongHint = '素材超過 150 字，請縮短後再生成。';

  static String materialCounter(int count) => count > materialMaxGraphemes
      ? '$count / $materialMaxGraphemes，超過 ${count - materialMaxGraphemes} 字，請縮短後再生成'
      : '$count / $materialMaxGraphemes';

  static const advancedUnavailableTitle = '進階模式暫時無法使用，要用基本模式生成嗎？';
  static const advancedUnavailableCancel = '先不要';
  static const advancedUnavailableConfirm = '用基本模式生成';

  // ── 教練提醒（提案 §5 逐字）─────────────────────────────

  static const _coldDuration = {
    'days': ('話題還熱，直接把上次那條線接回來。', ['正式說「好久沒聊」']),
    'weeks': ('帶一個新東西出現：看到的、遇到的，或一個她會有意見的小題目。', ['檢討關係']),
  };
  static const _coldMonthSoft = ('可以輕鬆說一句有陣子沒聊，接著直接帶內容。', ['一上來就曖昧']);
  static const _coldMonthHard = ('隔很久了，這次帶著一個具體的新東西出現。', ['一上來就曖昧']);
  static const _coldNoDuration = ('有內容、低壓力、不追討。', ['「在嗎」式空敲門']);
  static const _coldStop = {
    'she_no_reply': ('不追上一則；有新的東西，再傳一則全新的內容。', ['「在嗎」「妳怎麼沒回」']),
    'i_no_reply': ('一句帶過就好，接著直接進內容。', ['長篇解釋', '過度道歉']),
    'she_cold': ('先降低頻率和強度：一則就好，看她會不會主動多聊。', ['連續補話題', '硬約']),
  };

  /// situation → engagement（沒選＝null 鍵）→（這次怎麼開, 先避開）。
  static const _engagementTips = {
    'stuck': {
      'green': ('她有在投入：接住她的話，再加一點你的料。', ['一直換題', '連續發問']),
      'yellow': ('別急著加大訊息量；再一兩輪沒變熱，就自然收。', ['連問', '長訊息']),
      'red': ('不要用更多問題去救：接住一句、自然收尾，留個下次的點。', ['追問「怎麼了」', '加碼曖昧']),
      null: ('換個角度或場景，一次只開一條線。', ['面試式連問']),
    },
    'after_date': {
      'green': ('趁熱延續約會裡的小事或梗；她有接，再往下次走。', ['問「妳覺得我怎樣」']),
      'yellow': ('用約會裡一件具體小事輕輕延續，先不約下次。', ['索取評價', '急約下次']),
      'red': ('最多一則輕鬆的內容；她沒接就先停。', ['追問感受', '急約下次']),
      null: ('承接約會的餘溫，不急著約下一次。', ['索取評價']),
    },
    'warm_up': {
      'green': ('可以加一點個人感：具體稱讚、共同想像。', ['突然告白', '越界']),
      'yellow': ('先讓聊天重新好玩，再談曖昧。', ['強行曖昧']),
      'red': ('現在不適合升溫，先低壓保持互動。', ['加大曖昧', '硬約']),
      null: ('想升溫先從輕的開始，看她接不接。', ['越級的親密']),
    },
  };

  /// 選了第一問才有；冷掉了照規格 §5.1 的組合規則。
  static NewTopicCoachTip? coachTip(NewTopicTwoStageAnswers answers) {
    final situation = answers.situation;
    if (situation == null) return null;
    final lines = <(String, List<String>)>[];
    if (situation == 'went_cold') {
      final duration = answers.coldDuration, stop = answers.coldStop;
      if (duration == 'month_plus' && stop == 'i_no_reply') {
        // 例外：免得出現兩次「帶過」。
        lines.add(_coldStop['i_no_reply']!);
      } else {
        if (duration == 'month_plus') {
          lines.add(stop == 'she_no_reply' || stop == 'she_cold'
              ? _coldMonthHard
              : _coldMonthSoft);
        } else if (_coldDuration[duration] != null) {
          lines.add(_coldDuration[duration]!);
        }
        if (_coldStop[stop] != null) lines.add(_coldStop[stop]!);
      }
      if (lines.isEmpty) lines.add(_coldNoDuration);
    } else {
      final tip = _engagementTips[situation]?[answers.engagement];
      if (tip == null) return null;
      lines.add(tip);
    }
    final avoids = <String>{for (final line in lines) ...line.$2};
    return (
      open: '這次怎麼開：${lines.map((line) => line.$1).join()}',
      avoid: '先避開：${avoids.join('、')}',
    );
  }

  // ── 這組根據 ───────────────────────────────────────────

  static String? _label(List<NewTopicOption> options, String? value) =>
      options.where((o) => o.value == value).firstOrNull?.label;

  /// `這組根據：<第一問短標>・<追問>｜<素材>`；沒選的段落省略，全沒選回 null。
  static String? basisLine(NewTopicTwoStageAnswers answers) {
    final situation = answers.situation;
    final first = [
      _situationShort[situation],
      if (situation == 'went_cold') ...[
        _label(coldDurationOptions, answers.coldDuration),
        _label(coldStopOptions, answers.coldStop),
      ] else if (situation != null)
        _label(engagementOptions(situation), answers.engagement),
    ].nonNulls;
    final material = _label(materialOptions(situation), answers.materialKind);
    if (first.isEmpty && material == null) return null;
    return '這組根據：${[
      if (first.isNotEmpty) first.join('・'),
      if (material != null) material,
    ].join('｜')}';
  }
}
