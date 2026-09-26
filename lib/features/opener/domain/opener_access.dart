/// Opener 權益契約單點（contract v2，2026-07-24 Eric 拍板）。
///
/// 鏡像 server `opener_payload.ts` 的 OPENER_TYPES / OPENER_FREE_V2_TYPES /
/// OPENER_FREE_V2_LOCKED_TYPES；screen、cache、handoff 一律引用這裡，
/// 不得各自重複手寫集合。
abstract final class OpenerAccessContract {
  /// 新 App request 一律帶的契約版本；server 缺席／1 視為舊 App 單卡。
  static const int contractVersion = 2;

  /// 這版 App 看得懂的卡片組（2026-09-25 Eric 選 B）：2＝一句推薦＋四句備選，
  /// 標籤見 OpeningRescueScreen.openerCardSet2Labels。生成請求帶 openerCardSet，
  /// server 實際給哪一組以回應的 access.cardSet 為準（旗標關時仍是五風格）。
  static const int cardSet = 2;

  /// Canonical 付費五型展示序（＝server OPENER_TYPES）。
  static const List<String> canonicalPaidOrder = [
    'extend',
    'resonate',
    'tease',
    'humor',
    'coldRead',
  ];

  /// Free v2 解鎖三型，順序即 Free UI 展示序（＝server OPENER_FREE_V2_TYPES）。
  static const List<String> freeUnlockedOrder = ['extend', 'humor', 'tease'];

  static const Set<String> freeUnlockedTypes = {'extend', 'humor', 'tease'};

  /// Free 永遠鎖住的兩型（＝server OPENER_FREE_V2_LOCKED_TYPES）。
  static const List<String> paidOnlyOrder = ['resonate', 'coldRead'];
}

/// Server 權威 access metadata（response `access` 欄）。
/// Client 不可只靠「有幾張卡」猜 tier；舊 Edge 未帶 access 時為 null，
/// 讀取端 fallback 只能以 paid-only keys 判斷。
class OpenerAccess {
  const OpenerAccess({
    required this.contractVersion,
    required this.servedTier,
    required this.visibleTypes,
    required this.lockedTypes,
    this.cardSet = 1,
    this.directions = const {},
  });

  final int contractVersion;
  /// 1＝五風格（延展／共鳴／調情／幽默／冷讀）；2＝一句推薦＋四句備選。
  final int cardSet;

  /// 方向＋範例卡（2026-09-26 Bruce／Eric）：類型 → 給用戶的方向。那張卡的句子是範例，
  /// 要用戶換成自己的經驗再傳；畫面依此標示，不當可原封送出的句子。
  final Map<String, String> directions;
  final String servedTier;
  final List<String> visibleTypes;
  final List<String> lockedTypes;

  bool get servedPaid => servedTier != 'free';

  Map<String, dynamic> toJson() => {
        'contractVersion': contractVersion,
        'servedTier': servedTier,
        'visibleTypes': visibleTypes,
        'lockedTypes': lockedTypes,
        if (cardSet == 2) 'cardSet': cardSet,
        if (directions.isNotEmpty) 'directions': directions,
      };

  /// 防禦式解析：形狀不對回 null（呼叫端當作「沒有 server access」，
  /// 絕不能因 metadata 壞掉讓整份結果解析失敗）。
  static OpenerAccess? tryParse(dynamic raw) {
    if (raw is! Map) return null;

    final servedTier = raw['servedTier'];
    if (servedTier is! String || servedTier.trim().isEmpty) return null;

    final rawVisible = raw['visibleTypes'];
    if (rawVisible is! List) return null;
    final visibleTypes = rawVisible
        .whereType<String>()
        .map((type) => type.trim())
        .where((type) => type.isNotEmpty)
        .toList(growable: false);
    if (visibleTypes.isEmpty) return null;

    final rawLocked = raw['lockedTypes'];
    final lockedTypes = rawLocked is List
        ? rawLocked
            .whereType<String>()
            .map((type) => type.trim())
            .where((type) => type.isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    final rawVersion = raw['contractVersion'];
    final contractVersion =
        rawVersion is num && rawVersion.round() >= 1 ? rawVersion.round() : 1;

    return OpenerAccess(
      contractVersion: contractVersion,
      servedTier: servedTier.trim(),
      visibleTypes: visibleTypes,
      lockedTypes: lockedTypes,
      cardSet: raw['cardSet'] == 2 ? 2 : 1,
      directions: _parseDirections(raw['directions']),
    );
  }

  static Map<String, String> _parseDirections(dynamic raw) {
    if (raw is! Map) return const {};
    final out = <String, String>{};
    raw.forEach((key, value) {
      if (key is String &&
          OpenerAccessContract.canonicalPaidOrder.contains(key) &&
          value is String &&
          value.trim().isNotEmpty) {
        out[key] = value.trim();
      }
    });
    return out;
  }
}
