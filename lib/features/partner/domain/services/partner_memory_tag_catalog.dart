/// 「關於她」手動記憶的唯一真相源。
///
/// 這些資料會進 analyze-chat、Coach 與新話題，因此每個值都必須能安全補成
/// 「她……」，且不能把雙方關係進度、回覆速度或使用者自己的目標混進來。
/// 底層仍沿用 `Partner.customNote` 的「、」串接格式，避免 Hive schema migration；
/// 舊自由文字保留在裝置上，但所有 AI 消費端都必須先經 [sanitizedNote]。
class PartnerMemoryTag {
  const PartnerMemoryTag(
    this.label, {
    this.exclusiveGroup,
    this.aliases = const <String>[],
  });

  final String label;

  /// 同一互斥組只能留一個，例如「早睡早起」與「夜貓子」。
  final String? exclusiveGroup;

  /// 已上線舊 chips 的安全別名。只做 exact-token 映射，不從自由句猜意圖。
  final List<String> aliases;
}

class PartnerMemoryTagGroup {
  const PartnerMemoryTagGroup(
    this.title,
    this.tags, {
    required this.maxSelections,
  });

  final String title;
  final List<PartnerMemoryTag> tags;

  /// 避免把同一分類的通用描述全勾，讓 AI 仍看得出真正重點。
  final int maxSelections;
}

abstract final class PartnerMemoryTagCatalog {
  static const groups = <PartnerMemoryTagGroup>[
    PartnerMemoryTagGroup(
      '工作／學業',
      <PartnerMemoryTag>[
        PartnerMemoryTag('工作忙碌'),
        PartnerMemoryTag('輪班工作', aliases: <String>['輪班']),
        PartnerMemoryTag('遠端工作'),
        PartnerMemoryTag('自由工作者', aliases: <String>['自由工作']),
        PartnerMemoryTag('還在念書'),
        PartnerMemoryTag('常出差'),
      ],
      maxSelections: 2,
    ),
    PartnerMemoryTagGroup(
      '地點／距離',
      <PartnerMemoryTag>[
        PartnerMemoryTag(
          '住同縣市',
          exclusiveGroup: 'homeLocation',
          aliases: <String>['同縣市'],
        ),
        PartnerMemoryTag(
          '住不同縣市',
          exclusiveGroup: 'homeLocation',
          aliases: <String>['異地'],
        ),
        PartnerMemoryTag('住海外', exclusiveGroup: 'homeLocation'),
        PartnerMemoryTag('常在外地'),
        PartnerMemoryTag('住得近', exclusiveGroup: 'distance'),
        PartnerMemoryTag(
          '住得較遠',
          exclusiveGroup: 'distance',
          aliases: <String>['距離有點遠'],
        ),
      ],
      maxSelections: 3,
    ),
    PartnerMemoryTagGroup(
      '作息／生活',
      <PartnerMemoryTag>[
        PartnerMemoryTag('早睡早起', exclusiveGroup: 'sleepSchedule'),
        PartnerMemoryTag('夜貓子', exclusiveGroup: 'sleepSchedule'),
        PartnerMemoryTag('平日較忙'),
        PartnerMemoryTag('休假不固定'),
        PartnerMemoryTag('不喝酒'),
        PartnerMemoryTag('吃素'),
      ],
      maxSelections: 3,
    ),
    PartnerMemoryTagGroup(
      '個性／互動',
      <PartnerMemoryTag>[
        PartnerMemoryTag('慢熱'),
        PartnerMemoryTag('外向健談', exclusiveGroup: 'sociability'),
        PartnerMemoryTag('安靜內向', exclusiveGroup: 'sociability'),
        PartnerMemoryTag('幽默愛鬧'),
        PartnerMemoryTag('直接坦率'),
        PartnerMemoryTag('重視個人空間'),
      ],
      maxSelections: 3,
    ),
    PartnerMemoryTagGroup(
      '聊天偏好',
      <PartnerMemoryTag>[
        PartnerMemoryTag('喜歡深入聊'),
        PartnerMemoryTag('喜歡互虧'),
        PartnerMemoryTag('偏好文字聊天'),
        PartnerMemoryTag('喜歡語音聊天'),
        PartnerMemoryTag('不想聊工作'),
        PartnerMemoryTag('不喜歡被催回'),
      ],
      maxSelections: 3,
    ),
    PartnerMemoryTagGroup(
      '興趣',
      <PartnerMemoryTag>[
        PartnerMemoryTag('喜歡美食', aliases: <String>['吃貨']),
        PartnerMemoryTag('愛喝咖啡'),
        PartnerMemoryTag('喜歡旅行'),
        PartnerMemoryTag('喜歡戶外'),
        PartnerMemoryTag('有在健身'),
        PartnerMemoryTag('喜歡寵物'),
        PartnerMemoryTag('喜歡音樂'),
        PartnerMemoryTag('愛看劇／電影', aliases: <String>['愛看劇']),
        PartnerMemoryTag('喜歡閱讀'),
        PartnerMemoryTag('喜歡遊戲'),
      ],
      maxSelections: 5,
    ),
  ];

  static final List<PartnerMemoryTag> tags = <PartnerMemoryTag>[
    for (final group in groups) ...group.tags,
  ];

  static final Map<String, PartnerMemoryTag> _byToken =
      <String, PartnerMemoryTag>{
    for (final tag in tags) tag.label: tag,
    for (final tag in tags)
      for (final alias in tag.aliases) alias: tag,
  };

  static final Map<String, PartnerMemoryTagGroup> _groupByLabel =
      <String, PartnerMemoryTagGroup>{
    for (final group in groups)
      for (final tag in group.tags) tag.label: group,
  };

  /// 從 Hive 舊字串讀出 canonical selection。
  ///
  /// 只接受完整 token；「她很慢熱」不會因包含「慢熱」就被誤收。Repository
  /// 舊 merge 格式的 `[from 名稱] ` 前綴會先剝掉，再做相同 exact match。
  static Set<String> parse(String? stored) {
    final selected = <String>{};
    if (stored == null || stored.trim().isEmpty) return selected;

    for (final raw in _tokens(stored)) {
      final tag = _byToken[_withoutMergePrefix(raw)];
      if (tag != null) _insert(selected, tag);
    }
    return selected;
  }

  /// UI 點選用：再點同一顆取消；選互斥值時自動移除舊值。
  static Set<String> toggle(Set<String> current, String label) {
    final next = Set<String>.of(current);
    final tag = _byToken[label];
    if (tag == null) return next;
    if (!next.remove(tag.label)) _insert(next, tag);
    return next;
  }

  /// UI 是否應允許這次點擊。已選項永遠可取消；互斥替換會先扣掉舊值。
  static bool canToggle(Set<String> current, String label) {
    final tag = _byToken[label];
    if (tag == null) return false;
    if (current.contains(tag.label)) return true;
    return _insert(Set<String>.of(current), tag);
  }

  /// 依畫面分類順序序列化，讓 prompt、測試與 UI preview 都穩定。
  static String serialize(Iterable<String> selected) {
    final values = selected.toSet();
    return <String>[
      for (final tag in tags)
        if (values.contains(tag.label)) tag.label,
    ].join('、');
  }

  /// AI 邊界唯一允許使用的手動背景。沒有可信 token 就回 null（fail closed）。
  static String? sanitizedNote(String? stored) {
    final value = serialize(parse(stored));
    return value.isEmpty ? null : value;
  }

  /// 是否含有不再允許進 AI 的舊資料。用於 UI 提醒使用者重新選 chips。
  static bool hasUnrecognizedContent(String? stored) {
    if (stored == null || stored.trim().isEmpty) return false;
    return _tokens(stored).any(
      (raw) => !_byToken.containsKey(_withoutMergePrefix(raw)),
    );
  }

  /// 對象建立頁的單列摘要，避免 30 多顆選項把 form row 撐爆。
  static String compactSummary(Iterable<String> selected) {
    final ordered =
        serialize(selected).split('、').where((e) => e.isNotEmpty).toList();
    if (ordered.isEmpty) return '';
    if (ordered.length <= 2) return ordered.join('、');
    return '${ordered.take(2).join('、')} ＋${ordered.length - 2}';
  }

  static Iterable<String> _tokens(String stored) => stored
      .split(RegExp(r'[、，,\n]'))
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty);

  static String _withoutMergePrefix(String token) =>
      token.replaceFirst(RegExp(r'^\[from [^\]]+\]\s*'), '').trim();

  static bool _insert(Set<String> selected, PartnerMemoryTag tag) {
    final candidate = Set<String>.of(selected);
    final exclusiveGroup = tag.exclusiveGroup;
    if (exclusiveGroup != null) {
      candidate.removeWhere(
        (label) => _byToken[label]?.exclusiveGroup == exclusiveGroup,
      );
    }

    final group = _groupByLabel[tag.label];
    if (group == null) return false;
    final selectedInGroup = group.tags
        .where((candidateTag) => candidate.contains(candidateTag.label))
        .length;
    if (selectedInGroup >= group.maxSelections) return false;

    candidate.add(tag.label);
    selected
      ..clear()
      ..addAll(candidate);
    return true;
  }
}
