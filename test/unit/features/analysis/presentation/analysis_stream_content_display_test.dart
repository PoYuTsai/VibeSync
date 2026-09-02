// Phase 1c：串流中的 analysis.decision 顯示對映——不回決策沒有 nextStep 欄位，
// 不能被當空內容丟掉。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/data/services/analyze_stream_client.dart';
import 'package:vibesync/features/analysis/presentation/helpers/analysis_stream_content_display.dart';

void main() {
  const mapper = AnalysisStreamContentDisplayMapper();

  test('v1 decision 仍顯示下一步策略', () {
    final content = mapper.contentFromEvent({
      'type': 'analysis.decision',
      'nextStepTitle': '先接住',
      'nextStepBody': '回她的火鍋',
      'doThis': '一句就好',
    })!;
    expect(content.kind, AnalysisStreamContentKind.decision);
    expect(content.title, '先接住');
    expect(content.body, contains('回她的火鍋'));
    expect(content.body, contains('建議：一句就好'));
  });

  test('do_not_send decision 顯示判斷、原因與等待條件', () {
    final content = mapper.contentFromEvent({
      'type': 'analysis.decision',
      'messageDecision': 'do_not_send',
      'replyMode': 'none',
      'action': 'pause',
      'reason': '她只回哈哈',
      'stopCondition': '等她提新話題',
    })!;
    expect(content.title, '本輪判斷：先不要回');
    expect(content.body, contains('她只回哈哈'));
    expect(content.body, contains('等到：等她提新話題'));
  });

  test('未知或畸形 messageDecision 走 v1 對映，不勸使用者不要回', () {
    for (final junk in ['hold', 'DO_NOT_SEND', '', 42, null]) {
      final content = mapper.contentFromEvent({
        'type': 'analysis.decision',
        'messageDecision': junk,
        'nextStepTitle': '接球',
        'nextStepBody': '回火鍋',
        'reason': '不該被當成不回的理由',
      });
      expect(content?.title, '接球', reason: 'messageDecision=$junk');
      expect(content?.body, isNot(contains('不該被當成不回的理由')));
    }
    // 沒有 v1 欄位也沒有合法決策：空內容，由呼叫端丟棄。
    final empty = mapper.contentFromEvent({
      'type': 'analysis.decision',
      'messageDecision': 'hold',
      'reason': 'x',
    });
    expect(empty?.body.trim(), isEmpty);
  });

  test('need_context／acknowledge_and_stop 各有標題；send 走 v1 對映', () {
    expect(
      mapper.contentFromEvent({
        'type': 'analysis.decision',
        'messageDecision': 'need_context',
        'reason': '看不出誰說的',
        'stopCondition': '補完整截圖',
      })!.title,
      '本輪判斷：資料不夠',
    );
    expect(
      mapper.contentFromEvent({
        'type': 'analysis.decision',
        'messageDecision': 'acknowledge_and_stop',
        'reason': '她已經說改天',
        'stopCondition': '她再約',
        'closingMessage': '好，改天再聊。',
      })!.title,
      '本輪判斷：先收尾',
    );
    expect(
      mapper.contentFromEvent({
        'type': 'analysis.decision',
        'messageDecision': 'send',
        'nextStepTitle': '接球',
        'nextStepBody': '回火鍋',
      })!.title,
      '接球',
    );
  });
}
