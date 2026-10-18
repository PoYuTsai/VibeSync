/// 對象頁的燈號紀錄（Eric 2026-10-18：Starter 主打「燈號紀錄＋邀約進度」，免費只看最新
/// 一次）。每次 v3 分析一筆、新到舊，只讀既有分析紀錄存的快照（伺服器 finalResult 的原樣）：
/// 不開新表、不打新 API。舊紀錄沒有的欄位（邀約進度）就是 null，畫面不顯示。
library;

import 'dart:convert';

import '../../../analysis/domain/entities/analysis_record.dart';
import '../../../analysis/domain/entities/guide_v3_result.dart';

class PartnerLightHistoryEntry {
  const PartnerLightHistoryEntry({
    required this.recordId,
    required this.analyzedAt,
    this.decision,
    this.careKind,
    this.light,
    this.inviteReadiness,
    this.previousLight,
    this.partial = false,
    this.recovered = false,
    this.deliveredCards = 0,
    this.deliverableCards = 0,
  });

  final String recordId;
  final DateTime analyzedAt;

  /// 快照讀不懂時是 null（只顯示日期與紀錄上的燈號）。
  final GuideV3Decision? decision;
  final GuideV3CareKind? careKind;

  /// 關心沒有燈號（畫面本來就不給 care 顯示燈號）。
  final GuideV3Light? light;
  final GuideV3InviteReadiness? inviteReadiness;

  /// 比這筆舊、最近一筆有燈號的燈號跟這筆不一樣時才有（畫面寫「綠 → 黃」）；關心跳過不比。
  final GuideV3Light? previousLight;

  /// 這一次存下來的結果完整度：伺服器標的 partial、續看重組的 recovered、送到幾張，以及這個
  /// 方案預定幾張（不含鎖住的）。快照讀不懂時是 false／0。
  final bool partial;
  final bool recovered;
  final int deliveredCards;
  final int deliverableCards;

  bool get isCare => decision == GuideV3Decision.care;

  /// 這次比預定的少（跟結果頁「這次比預定的少幾張」同一個判斷）：對象頁這時不推升級。
  bool get deliveredFewer => guideV3DeliveredFewer(
        partial: partial,
        recovered: recovered,
        deliveredCards: deliveredCards,
        deliverableCards: deliverableCards,
      );
}

/// [records] 不必排好；舊流程（v2）的紀錄不算。
List<PartnerLightHistoryEntry> buildPartnerLightHistory(
  Iterable<AnalysisRecord> records,
) {
  final v3 = records.where((record) => record.isGuideV3).toList()
    ..sort((a, b) {
      final byDate = b.createdAt.compareTo(a.createdAt);
      return byDate != 0 ? byDate : b.id.compareTo(a.id);
    });
  final results = [for (final record in v3) _resultOf(record)];
  final reads = [for (final result in results) result?.read];
  final lights = <GuideV3Light?>[
    for (var i = 0; i < v3.length; i++)
      reads[i]?.decision == GuideV3Decision.care
          ? null
          : reads[i]?.light ?? v3[i].light,
  ];
  // 從最舊的往新的走，記住上一個有燈號的燈號。
  final previous = List<GuideV3Light?>.filled(v3.length, null);
  GuideV3Light? older;
  for (var i = v3.length - 1; i >= 0; i--) {
    final light = lights[i];
    if (light == null) continue;
    if (older != null && older != light) previous[i] = older;
    older = light;
  }
  return List.unmodifiable([
    for (var i = 0; i < v3.length; i++)
      PartnerLightHistoryEntry(
        recordId: v3[i].id,
        analyzedAt: v3[i].createdAt,
        decision: reads[i]?.decision,
        careKind: reads[i]?.careKind,
        light: lights[i],
        inviteReadiness: reads[i]?.inviteReadiness,
        previousLight: previous[i],
        partial: results[i]?.partial ?? false,
        recovered: results[i]?.recovered ?? false,
        deliveredCards: results[i]?.cards.length ?? 0,
        deliverableCards: reads[i]?.deliverableCount ?? 0,
      ),
  ]);
}

/// 存檔的快照是伺服器 finalResult 的原樣（續看重組的已補回畫面上送到的卡）。
GuideV3Result? _resultOf(AnalysisRecord record) {
  try {
    final decoded = jsonDecode(record.analysisSnapshotJson);
    return decoded is Map
        ? GuideV3Result.fromJson(
            decoded.map((key, value) => MapEntry(key.toString(), value)),
          )
        : null;
  } catch (_) {
    return null;
  }
}
