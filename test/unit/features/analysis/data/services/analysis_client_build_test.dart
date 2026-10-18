// 最低 App 版本閘門（Eric 2026-10-18）：analyze-chat 的兩個 client 都在 body
// 帶 clientBuild（App 的 build 號），讀不到就不帶。它只是多一個欄位：其他欄位
// 與序列化逐字不變（冪等／重播雜湊都只吃具名欄位，伺服器端由 Deno 測試鎖住）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:vibesync/features/analysis/data/services/analysis_service.dart';
import 'package:vibesync/features/analysis/data/services/analysis_transport_support.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

Message _msg(String content, {bool fromMe = false}) {
  return Message(
    id: content,
    content: content,
    isFromMe: fromMe,
    timestamp: DateTime(2026, 10, 18, 12),
  );
}

void _mockBuildNumber(String buildNumber) {
  PackageInfo.setMockInitialValues(
    appName: 'VibeSync',
    packageName: 'com.vibesync.app',
    version: '1.0.1',
    buildNumber: buildNumber,
    buildSignature: '',
  );
}

const Map<String, dynamic> _optimizedSuccessBody = {
  'enthusiasm': {'score': 70, 'level': 'warm'},
  'gameStage': {'current': 'premise', 'status': 'normal', 'nextStep': '繼續'},
  'psychology': {'subtext': '有興趣'},
  'topicDepth': {'current': 'personal', 'suggestion': '可深入'},
  'replies': {
    'extend': 'a',
    'resonate': 'b',
    'tease': 'c',
    'humor': 'd',
    'coldRead': 'e',
  },
  'finalRecommendation': {
    'pick': 'tease',
    'content': 'c',
    'reason': 'r',
    'psychology': 'p',
  },
  'strategy': '保持沉穩',
  'optimizedMessage': {
    'original': '要不要喝咖啡',
    'optimized': '這週要不要一起喝杯咖啡？',
    'improvements': ['更自然'],
  },
};

AnalysisAuxiliaryClient _auxiliary(
  List<Map<String, dynamic>> bodies, {
  required int? clientBuild,
}) {
  return AnalysisAuxiliaryClient(
    clientFactory: () => MockClient((request) async {
      bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
      return http.Response(
        jsonEncode(_optimizedSuccessBody),
        200,
        headers: {'content-type': 'application/json'},
      );
    }),
    accessTokenProvider: () => 'fake-token',
    expectedTierProvider: () => 'essential',
    revenueCatAppUserIdProvider: () async => r'$RCAnonymousID:char',
    clientBuildProvider: () async => clientBuild,
  );
}

Map<String, dynamic> _withoutClientBuild(Map<String, dynamic> body) =>
    Map<String, dynamic>.of(body)..remove('clientBuild');

void main() {
  group('defaultAnalysisClientBuild', () {
    test('讀 PackageInfo 的 build 號（iOS 的 CFBundleVersion）', () async {
      _mockBuildNumber('345');
      expect(await defaultAnalysisClientBuild(), 345);
      _mockBuildNumber(' 57 ');
      expect(await defaultAnalysisClientBuild(), 57);
    });

    test('空白、版本字串、0 或負數都當讀不到', () async {
      for (final raw in ['', '1.0.1', '0', '-3', 'abc']) {
        _mockBuildNumber(raw);
        expect(await defaultAnalysisClientBuild(), isNull, reason: raw);
      }
    });
  });

  group('AnalyzeStreamClient', () {
    final request = AnalyzeStreamRequest(
      messages: [_msg('今天好累喔'), _msg('辛苦了', fromMe: true)],
      previousStage: 'premise',
      analysisFragmentStartIndex: 0,
      previousAnalyzedCount: 2,
      previousAnalyzedCharCount: 9,
    );
    const entitlement = AnalysisEntitlementContext(
      expectedTier: 'essential',
      revenueCatAppUserId: 'rc-user',
    );

    test('buildStreamBody：帶 clientBuild 只多這一個欄位，其餘序列化逐字不變', () {
      final without = AnalyzeStreamClient.buildStreamBody(request, entitlement);
      final withBuild = AnalyzeStreamClient.buildStreamBody(
        request,
        entitlement,
        clientBuild: 345,
      );
      expect(without.containsKey('clientBuild'), isFalse);
      expect(withBuild['clientBuild'], 345);
      expect(
        jsonEncode(_withoutClientBuild(withBuild)),
        jsonEncode(without),
      );
    });

    test('stream()：送出的 body 帶 provider 給的 clientBuild；讀不到就不帶', () async {
      for (final clientBuild in <int?>[345, null]) {
        late Map<String, dynamic> body;
        final client = AnalyzeStreamClient(
          displayMapper: const AnalysisStreamContentDisplayMapper(),
          clientFactory: () => MockClient((httpRequest) async {
            body = jsonDecode(httpRequest.body) as Map<String, dynamic>;
            // 送出去就好：回一則錯誤事件讓串流結束。
            return http.Response.bytes(
              utf8.encode(jsonEncode({
                'type': 'analysis.error',
                'code': 'STREAM_FAILED',
                'message': '這次分析沒順利完成。',
                'recoverable': false,
              })),
              200,
              headers: {'content-type': 'application/x-ndjson'},
            );
          }),
          accessTokenProvider: () => 'fake-token',
          expectedTierProvider: () => null,
          revenueCatAppUserIdProvider: () async => null,
          clientBuildProvider: () async => clientBuild,
        );
        await expectLater(
          client.stream(AnalyzeStreamRequest(messages: [_msg('哈囉')])).toList(),
          throwsA(isA<StreamModeException>()),
        );
        if (clientBuild == null) {
          expect(body.containsKey('clientBuild'), isFalse);
        } else {
          expect(body['clientBuild'], clientBuild);
        }
        expect(body['responseMode'], 'stream');
      }
    });
  });

  group('AnalysisAuxiliaryClient', () {
    const requestId = '123e4567-e89b-42d3-a456-426614174000';

    test('截圖辨識、草稿潤飾、回覆微調的 body 都帶 clientBuild', () async {
      final bodies = <Map<String, dynamic>>[];
      final client = _auxiliary(bodies, clientBuild: 345);
      await client.optimizeDraft(
        messages: [_msg('最近有空嗎？')],
        userDraft: '要不要喝咖啡',
        requestId: requestId,
      );
      await client.refineReply(
        messages: [_msg('最近有空嗎？')],
        userDraft: '要不要喝咖啡',
        refineInstruction: '短一點',
        requestId: requestId,
      );
      // 這裡只看送出的 body；回應沿用同一份，辨識結果是什麼不重要。
      await client.recognizeScreenshots(
        images: [
          Uint8List.fromList([1, 2, 3])
        ],
      );
      expect(bodies, hasLength(3));
      for (final body in bodies) {
        expect(body['clientBuild'], 345);
      }
      expect(bodies[2]['recognizeOnly'], isTrue);
    });

    test('讀不到 build 號就不帶；帶了也只多這一個欄位（潤飾請求逐字不變）', () async {
      final withBuild = <Map<String, dynamic>>[];
      final without = <Map<String, dynamic>>[];
      for (final (bodies, clientBuild) in [(withBuild, 345), (without, null)]) {
        await _auxiliary(bodies, clientBuild: clientBuild).optimizeDraft(
          messages: [_msg('最近有空嗎？'), _msg('還好', fromMe: true)],
          userDraft: '要不要喝咖啡',
          requestId: requestId,
        );
      }
      expect(without.single.containsKey('clientBuild'), isFalse);
      expect(withBuild.single['clientBuild'], 345);
      expect(
        jsonEncode(_withoutClientBuild(withBuild.single)),
        jsonEncode(without.single),
      );
    });
  });
}
