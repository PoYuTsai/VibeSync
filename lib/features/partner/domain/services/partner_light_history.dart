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

  bool get isCare => decision == GuideV3Decision.care;
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
  final reads = [for (final record in v3) _readOf(record)];
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
      ),
  ]);
}

GuideV3Read? _readOf(AnalysisRecord record) {
  try {
    final decoded = jsonDecode(record.analysisSnapshotJson);
    return decoded is Map ? GuideV3Read.fromJson(decoded['read']) : null;
  } catch (_) {
    return null;
  }
}
