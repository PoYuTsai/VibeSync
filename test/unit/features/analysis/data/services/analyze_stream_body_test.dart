// 情境 seam（對象卡互動階段閉環驗收 9）：從對象卡最新設定解析出的
// SessionContext，經 stream 請求 body builder 後，wire payload 必須真的
// 送出 `meetingContext: 已是伴侶`——不被舊 Conversation context 吃掉。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/analysis_transport_support.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/domain/services/screenshot_session_context_defaults.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

void main() {
  final now = DateTime(2026, 8, 22);

  test('對象卡改成已是伴侶後，下一個分析片段的 request payload 送出 已是伴侶', () {
    final partner = Partner(
      id: 'p-1',
      name: 'Alice',
      createdAt: now,
      updatedAt: now,
      defaultMeetingContext: MeetingContext.committedPartner,
      defaultAcquaintanceDuration: AcquaintanceDuration.monthPlus,
      defaultGoal: UserGoal.justChat,
    );
    final conversation = Conversation(
      id: 'c-1',
      name: 'Alice',
      messages: const [],
      createdAt: now,
      updatedAt: now,
      partnerId: 'p-1',
      // 舊 context：對象卡尚未改成已是伴侶前蓋章的值。
      sessionContext: SessionContext(
        meetingContext: MeetingContext.datingApp,
        duration: AcquaintanceDuration.justMet,
        goal: UserGoal.dateInvite,
      ),
    );

    final resolved = ScreenshotSessionContextDefaults.resolve(
      conversation: conversation,
      partner: partner,
    );

    final body = AnalyzeStreamClient.buildStreamBody(
      AnalyzeStreamRequest(
        messages: [
          Message(
            id: 'm1',
            content: '週六兩點去那間咖啡店？',
            isFromMe: false,
            timestamp: now,
          ),
        ],
        sessionContext: resolved,
      ),
      const AnalysisEntitlementContext(),
    );

    final sessionContext = body['sessionContext'] as Map<String, dynamic>;
    expect(sessionContext['meetingContext'], '已是伴侶');
    expect(sessionContext['duration'], '一個月+');
    expect(sessionContext['goal'], '純聊天');
    // 驗收 18：關於我不進 AnalyzeChat——buildForAnalysis 恆為 null，
    // wire payload 不得帶 effectiveStyleContext。
    expect(body.containsKey('effectiveStyleContext'), isFalse);
    // Phase 1c：宣告 Analyze V2 合約，後端才會開不回決策的閘門。
    expect(body['analysisContractVersion'], 2);
    expect(AnalyzeStreamClient.analysisContractVersion, 2);
  });

  test('上次有效階段（弱先驗）隨 wire payload 送出；缺值不帶 key', () {
    final message = Message(
      id: 'm1',
      content: '嗨',
      isFromMe: false,
      timestamp: now,
    );

    final withPrior = AnalyzeStreamClient.buildStreamBody(
      AnalyzeStreamRequest(
        messages: [message],
        previousStage: 'qualification',
      ),
      const AnalysisEntitlementContext(),
    );
    expect(withPrior['previousStage'], 'qualification');

    final withoutPrior = AnalyzeStreamClient.buildStreamBody(
      AnalyzeStreamRequest(messages: [message]),
      const AnalysisEntitlementContext(),
    );
    expect(withoutPrior.containsKey('previousStage'), isFalse);

    // 空白字串視同缺值：不帶 key，不讓垃圾進 Edge。
    final blankPrior = AnalyzeStreamClient.buildStreamBody(
      AnalyzeStreamRequest(messages: [message], previousStage: '  '),
      const AnalysisEntitlementContext(),
    );
    expect(blankPrior.containsKey('previousStage'), isFalse);
  });

  test('最新分析片段起點會進 wire payload', () {
    final message = Message(
      id: 'm1',
      content: '新片段',
      isFromMe: false,
      timestamp: now,
    );
    final body = AnalyzeStreamClient.buildStreamBody(
      AnalyzeStreamRequest(
        messages: [message],
        analysisFragmentStartIndex: 0,
      ),
      const AnalysisEntitlementContext(),
    );

    expect(body['analysisFragmentStartIndex'], 0);
  });
}
