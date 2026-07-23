/// Opener 權益契約單點（contract v2，2026-07-24 Eric 拍板）。
///
/// 鏡像 server `opener_payload.ts` 的 OPENER_TYPES / OPENER_FREE_V2_TYPES /
/// OPENER_FREE_V2_LOCKED_TYPES；screen、cache、handoff 一律引用這裡，
/// 不得各自重複手寫集合。
abstract final class OpenerAccessContract {
  /// 新 App request 一律帶的契約版本；server 缺席／1 視為舊 App 單卡。
  static const int contractVersion = 2;

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
  });

  final int contractVersion;
  final String servedTier;
  final List<String> visibleTypes;
  final List<String> lockedTypes;

  bool get servedPaid => servedTier != 'free';

  Map<String, dynamic> toJson() => {
        'contractVersion': contractVersion,
        'servedTier': servedTier,
        'visibleTypes': visibleTypes,
        'lockedTypes': lockedTypes,
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
    );
  }
}
