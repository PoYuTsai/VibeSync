/// 存檔層要的共同欄位：一次完成的分析是 v2（[AnalysisResult]）或 v3 任務卡
/// （[GuideV3Result]）。快照、分析紀錄、歷史事件、回滾都走同一套流程，只有這幾個
/// 欄位不同。v3 帶了關係狀態（[GuideV3Relation]，Bruce 2026-10-19 路線二）就照 v2 的
/// 欄位填熱度與階段，作戰板、報表、對象頁與對方檔案照舊讀得到；沒帶（改版前的結果、
/// 開關沒開）兩個都是 null：對話的熱度清掉、階段保留上次舊流程的、歷史事件不寫
/// （Eric 2026-10-17）。
library;

import 'analysis_models.dart';
import 'game_stage.dart';
import 'guide_v3_result.dart';

class PersistableAnalysis {
  const PersistableAnalysis._({
    required this.rawResponse,
    required this.enthusiasmScore,
    required this.validStage,
    required this.waivesCharBaseline,
    this.silencesFollowUp = false,
    this.guideVersion,
    this.guideV3Light,
    this.analysisRunId,
  });

  factory PersistableAnalysis.fromResult(AnalysisResult result) {
    final usage = result.rawResponse?['usage'];
    return PersistableAnalysis._(
      rawResponse: result.rawResponse,
      enthusiasmScore: result.enthusiasmScore,
      validStage:
          result.gameStage.hasValidStage ? result.gameStage.current : null,
      // 「資料不夠」免扣時不推進字數基準：補完資料那次要對整段計費。
      waivesCharBaseline: usage is Map && usage['quotaWaivedReason'] != null,
    );
  }

  /// [analysisRunId]：伺服器的 run id，存進快照 meta，重開畫面後複製紀錄的 key
  /// 不變（v3 的卡在 done 之前就能複製，key 只能用伺服器 runId）。
  factory PersistableAnalysis.fromGuideV3(
    GuideV3Result result, {
    String? analysisRunId,
  }) {
    final runId = analysisRunId?.trim();
    final relation = result.read.relation;
    return PersistableAnalysis._(
      rawResponse: result.rawResponse,
      enthusiasmScore: relation?.visibleHeat,
      validStage: relation?.stage,
      // 自傷關心沒扣費：字數基準不推進，下一次照整段計費。
      waivesCharBaseline: result.isCare,
      silencesFollowUp: result.decision.silencesFollowUp,
      guideVersion:
          result.read.guideVersion.isEmpty ? 'v3' : result.read.guideVersion,
      guideV3Light: result.read.light,
      analysisRunId: runId == null || runId.isEmpty ? null : runId,
    );
  }

  /// 伺服器送來的原樣（快照與紀錄存這份）。
  final Map<String, dynamic>? rawResponse;

  /// v2 的熱度；v3 是關係狀態的熱度（換成 0–90，見 [GuideV3Relation.visibleHeat]），
  /// 沒帶是 null。
  final int? enthusiasmScore;

  /// 有效的互動階段；缺值、非法值、沒帶關係狀態的 v3 都是 null（不寫新階段）。
  final GameStage? validStage;

  /// 不推進存檔的字數基準（這次沒照字數扣費）。
  final bool waivesCharBaseline;

  /// 這次之後不問、不排 48 小時跟進提醒，已排的收回（見
  /// [GuideV3Decision.silencesFollowUp]）；v2 一律 false。
  final bool silencesFollowUp;

  /// v3 的說明書版本；v2 是 null。
  final String? guideVersion;

  /// v3 的燈號（分析紀錄列表顯示用）。
  final GuideV3Light? guideV3Light;
  final String? analysisRunId;

  bool get isGuideV3 => guideVersion != null;

  /// 換一份原樣（存檔前補上要沿用的欄位）。
  PersistableAnalysis withRawResponse(Map<String, dynamic> rawResponse) =>
      PersistableAnalysis._(
        rawResponse: rawResponse,
        enthusiasmScore: enthusiasmScore,
        validStage: validStage,
        waivesCharBaseline: waivesCharBaseline,
        silencesFollowUp: silencesFollowUp,
        guideVersion: guideVersion,
        guideV3Light: guideV3Light,
        analysisRunId: analysisRunId,
      );
}
