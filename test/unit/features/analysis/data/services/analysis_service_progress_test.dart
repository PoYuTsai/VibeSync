import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';

void main() {
  test('OCR waiting milestones are ordered and end in result finalization', () {
    expect(
      ocrRecognitionProgressMilestones.map((item) => item.stage).toList(),
      const [
        AnalysisProgressStage.awaitingAi,
        AnalysisProgressStage.recognizingMessages,
        AnalysisProgressStage.resolvingSpeakers,
        AnalysisProgressStage.finalizingRecognition,
      ],
    );
    expect(
      ocrRecognitionProgressMilestones
          .map((item) => item.delay.inMilliseconds)
          .toList(),
      const [700, 4000, 9000, 15000],
    );
  });

  test('OCR waiting stages use concrete Traditional Chinese status copy', () {
    expect(
      AnalysisProgressStage.values.map(analysisProgressStageLabel).toList(),
      const [
        '準備圖片中',
        '上傳圖片中',
        'AI 讀取圖片中',
        '辨識訊息內容中',
        '校對說話者中',
        '整理辨識結果中',
      ],
    );
  });
}
