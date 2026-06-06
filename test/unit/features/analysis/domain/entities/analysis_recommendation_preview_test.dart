import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_recommendation_preview.dart';

void main() {
  group('AnalysisRecommendationPreview.fromJson', () {
    test('parses happy path payload from analyze-chat quick mode', () {
      final json = {
        'analysisRunId': 'run_abc123',
        'estimatedFullSeconds': 17,
        'quickResult': {
          'pick': 'resonate',
          'nextStep': '先接住她的情緒，再順勢延伸到她剛聊到的工作話題',
          'recommendedReply': '聽起來真的累爆，週末有沒有放空一下？',
          'shortReason': '對方剛抱怨完工作，先給情緒空間再開新話題',
          'insufficientContext': false,
          'confidence': 'high',
        },
      };

      final result = AnalysisRecommendationPreview.fromJson(json);

      expect(result.analysisRunId, 'run_abc123');
      expect(result.estimatedFullSeconds, 17);
      expect(result.pick, 'resonate');
      expect(result.nextStep, '先接住她的情緒，再順勢延伸到她剛聊到的工作話題');
      expect(result.recommendedReply, '聽起來真的累爆，週末有沒有放空一下？');
      expect(result.shortReason, '對方剛抱怨完工作，先給情緒空間再開新話題');
      expect(result.insufficientContext, false);
      expect(result.confidence, 'high');
    });

    test('fills optional defaults when present (shortReason/confidence/eta)',
        () {
      // Required fields supplied; optional fields omitted should fall back to
      // safe defaults — but required fields no longer have empty defaults.
      final json = {
        'analysisRunId': 'run_xyz',
        'quickResult': {
          'nextStep': '先接情緒再延伸',
          'recommendedReply': '聽起來累，要不要週末喝杯咖啡？',
        },
      };

      final result = AnalysisRecommendationPreview.fromJson(json);

      expect(result.analysisRunId, 'run_xyz');
      expect(result.pick, '');
      expect(result.shortReason, '');
      expect(result.insufficientContext, false);
      expect(result.confidence, 'medium');
      expect(result.estimatedFullSeconds, isNull);
    });

    test('rounds estimatedFullSeconds when server sends a double', () {
      final json = {
        'analysisRunId': 'run_1',
        'estimatedFullSeconds': 17.6,
        'quickResult': {
          'nextStep': '先接情緒再延伸',
          'recommendedReply': '聽起來累，要不要週末喝杯咖啡？',
        },
      };

      final result = AnalysisRecommendationPreview.fromJson(json);

      expect(result.estimatedFullSeconds, 18);
    });

    test('treats insufficientContext truthy only when literally true', () {
      final json = {
        'analysisRunId': 'run_1',
        'quickResult': {
          'nextStep': '先接情緒再延伸',
          'recommendedReply': '聽起來累，要不要週末喝杯咖啡？',
          'insufficientContext': 'true',
        },
      };

      final result = AnalysisRecommendationPreview.fromJson(json);

      expect(result.insufficientContext, false);
    });
  });

  group(
      'AnalysisRecommendationPreview.fromJson — fail-closed on required fields (P3)',
      () {
    test('throws FormatException when analysisRunId is missing', () {
      expect(
        () => AnalysisRecommendationPreview.fromJson(<String, dynamic>{
          'quickResult': {
            'nextStep': '先接情緒',
            'recommendedReply': '聽起來累，週末放空？',
          },
        }),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('analysisRunId'),
        )),
      );
    });

    test('throws FormatException when analysisRunId is whitespace-only', () {
      expect(
        () => AnalysisRecommendationPreview.fromJson(<String, dynamic>{
          'analysisRunId': '   ',
          'quickResult': {
            'nextStep': '先接情緒',
            'recommendedReply': '聽起來累，週末放空？',
          },
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException when nextStep is missing', () {
      expect(
        () => AnalysisRecommendationPreview.fromJson(<String, dynamic>{
          'analysisRunId': 'run_1',
          'quickResult': {
            'recommendedReply': '聽起來累，週末放空？',
          },
        }),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('nextStep'),
        )),
      );
    });

    test('throws FormatException when recommendedReply is empty', () {
      expect(
        () => AnalysisRecommendationPreview.fromJson(<String, dynamic>{
          'analysisRunId': 'run_1',
          'quickResult': {
            'nextStep': '先接情緒',
            'recommendedReply': '',
          },
        }),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('recommendedReply'),
        )),
      );
    });

    test('throws FormatException on entirely empty payload', () {
      expect(
        () => AnalysisRecommendationPreview.fromJson(<String, dynamic>{}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
