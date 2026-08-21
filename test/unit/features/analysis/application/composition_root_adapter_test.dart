// composition root 與 data adapter 的行為回歸：
// 1. persistence factory 供給的依賴維持 per-call provider 解析新鮮度
//    （provider 內容更新後，既有 coordinator 讀到的是新值，不是建構時快照）。
// 2. 單一 AnalysisAuxiliaryClient 實例重複 recognizeScreenshots 等價
//    （screenshot 工廠改為重用一顆 client；client 無狀態，逐次請求獨立）。
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_providers.dart';
import 'package:vibesync/features/analysis/data/providers/analysis_record_providers.dart';
import 'package:vibesync/features/analysis/data/services/analysis_auxiliary_client.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';

void main() {
  test('persistence factory 的 recordOwner 依賴是 per-call 解析（provider 失效後讀到新值）',
      () async {
    var owner = 'owner-a';
    final container = ProviderContainer(overrides: [
      analysisRecordOwnerProvider.overrideWith((ref) => owner),
    ]);
    addTearDown(container.dispose);

    final coordinator =
        container.read(analysisPersistenceCoordinatorFactoryProvider)(
      conversationId: 'freshness-conv',
      notifyStateChanged: () {},
      invalidateRecordViews: (_) {},
      afterAnalysisPersisted: (_) async {},
    );

    final conversation = Conversation(
      id: 'freshness-conv',
      name: '小雲',
      messages: const [],
      createdAt: DateTime(2026, 5, 28),
      updatedAt: DateTime(2026, 5, 28),
    );
    expect(coordinator.recordOwnerFor(conversation), 'owner-a');

    // provider 內容更新：既有 coordinator 不得停留在建構時快照。
    owner = 'owner-b';
    container.invalidate(analysisRecordOwnerProvider);
    expect(coordinator.recordOwnerFor(conversation), 'owner-b');
  });

  test('同一顆 AnalysisAuxiliaryClient 重複 recognizeScreenshots：逐次請求獨立且等價',
      () async {
    final bodies = <Map<String, dynamic>>[];
    final client = AnalysisAuxiliaryClient(
      clientFactory: () => MockClient((request) async {
        bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode({
            'recognizedConversation': {
              'contactName': '小美',
              'messageCount': 1,
              'summary': '一則',
              'messages': [
                {'content': '嗨', 'isFromMe': false},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      accessTokenProvider: () => 'fake-token',
      expectedTierProvider: () => null,
      revenueCatAppUserIdProvider: () async => null,
    );

    final first = await client.recognizeScreenshots(
      images: [
        Uint8List.fromList([1, 2, 3])
      ],
    );
    final second = await client.recognizeScreenshots(
      images: [
        Uint8List.fromList([9, 8, 7])
      ],
      knownContactName: '小美',
    );

    expect(first.recognizedConversation?.contactName, '小美');
    expect(second.recognizedConversation?.contactName, '小美');
    expect(bodies, hasLength(2));
    // 兩次呼叫各自帶自己的 payload：client 內不殘留上一輪狀態。
    expect(bodies[0]['images'][0]['data'],
        base64Encode(Uint8List.fromList([1, 2, 3])));
    expect(bodies[0].containsKey('knownContactName'), isFalse);
    expect(bodies[1]['images'][0]['data'],
        base64Encode(Uint8List.fromList([9, 8, 7])));
    expect(bodies[1]['knownContactName'], '小美');
  });
}
