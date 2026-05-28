import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/quick_analysis_result.dart';

void main() {
  group('QuickAnalysisResult.fromJson', () {
    test('parses happy path payload from analyze-chat quick mode', () {
      final json = {
        'analysisRunId': 'run_abc123',
        'estimatedFullSeconds': 17,
        'quickResult': {
          'nextStep': '先接住她的情緒，再順勢延伸到她剛聊到的工作話題',
          'recommendedReply': '聽起來真的累爆，週末有沒有放空一下？',
          'shortReason': '對方剛抱怨完工作，先給情緒空間再開新話題',
          'insufficientContext': false,
          'confidence': 'high',
        },
      };

      final result = QuickAnalysisResult.fromJson(json);

      expect(result.analysisRunId, 'run_abc123');
      expect(result.estimatedFullSeconds, 17);
      expect(result.nextStep, '先接住她的情緒，再順勢延伸到她剛聊到的工作話題');
      expect(result.recommendedReply, '聽起來真的累爆，週末有沒有放空一下？');
      expect(result.shortReason, '對方剛抱怨完工作，先給情緒空間再開新話題');
      expect(result.insufficientContext, false);
      expect(result.confidence, 'high');
    });

    test('returns safe defaults when quickResult fields are missing', () {
      final json = {
        'analysisRunId': 'run_xyz',
        'quickResult': <String, dynamic>{},
      };

      final result = QuickAnalysisResult.fromJson(json);

      expect(result.analysisRunId, 'run_xyz');
      expect(result.nextStep, '');
      expect(result.recommendedReply, '');
      expect(result.shortReason, '');
      expect(result.insufficientContext, false);
      expect(result.confidence, 'medium');
      expect(result.estimatedFullSeconds, isNull);
    });

    test('returns empty analysisRunId when missing (does not throw)', () {
      final result = QuickAnalysisResult.fromJson(<String, dynamic>{});

      expect(result.analysisRunId, '');
      expect(result.nextStep, '');
      expect(result.estimatedFullSeconds, isNull);
    });

    test('rounds estimatedFullSeconds when server sends a double', () {
      final json = {
        'analysisRunId': 'run_1',
        'estimatedFullSeconds': 17.6,
        'quickResult': <String, dynamic>{},
      };

      final result = QuickAnalysisResult.fromJson(json);

      expect(result.estimatedFullSeconds, 18);
    });

    test('treats insufficientContext truthy only when literally true', () {
      final json = {
        'analysisRunId': 'run_1',
        'quickResult': {'insufficientContext': 'true'},
      };

      final result = QuickAnalysisResult.fromJson(json);

      expect(result.insufficientContext, false);
    });
  });
}
