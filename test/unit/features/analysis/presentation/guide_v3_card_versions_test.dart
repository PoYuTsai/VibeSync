// 結果頁 v3 任務卡的版本：自己改的、再調選定的、伺服器原樣，三者的先後與複製紀錄的
// 來源（Eric 2026-10-18：再調的版本不放進自己改的那一份）。
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/application/reply_iteration_coordinator.dart';
import 'package:vibesync/features/analysis/presentation/helpers/guide_v3_card_versions.dart';

void main() {
  const key = 'run_v3:2';
  const original = ['我是做＿＿的', '你呢'];

  test('面板帶回來的字一則一行，拆回每一則；空行拿掉', () {
    final version = GuideV3RefinedVersion.fromAdoptedText(
      ' 我做＿＿的 \n\n你呢？\n',
      requestId: 'req-1',
    );
    expect(version.messages, ['我做＿＿的', '你呢？']);
    expect(version.requestId, 'req-1');
  });

  test('顯示：自己改的 > 再調的 > 伺服器原樣', () {
    final versions = GuideV3CardVersions();
    expect(versions.displayed(key, original), original);

    versions.adoptRefined(
      key,
      const GuideV3RefinedVersion(messages: ['我做＿＿的', '你呢？'], requestId: 'r1'),
    );
    expect(versions.displayed(key, original), ['我做＿＿的', '你呢？']);
    expect(versions.editedFor(key), isNull, reason: '再調的版本不算「已改成你的」');

    versions.saveEdit(key, ['我做設計的', '你呢？']);
    expect(versions.displayed(key, original), ['我做設計的', '你呢？']);
    // 填完空格之後，複製紀錄還是那一輪微調。
    expect(versions.refinedFor(key)?.requestId, 'r1');
  });

  test('選定再調的版本會蓋掉之前自己改的（再調的原句就是那一份）', () {
    final versions = GuideV3CardVersions()..saveEdit(key, ['我做設計的', '你呢']);
    versions.adoptRefined(
      key,
      const GuideV3RefinedVersion(messages: ['我做設計的', '換你說'], requestId: 'r2'),
    );
    expect(versions.editedFor(key), isNull);
    expect(versions.displayed(key, original), ['我做設計的', '換你說']);
  });

  test('只動同一張卡；新的一輪分析整個清掉', () {
    final versions = GuideV3CardVersions()
      ..saveEdit('run_v3:1', ['第一張改過'])
      ..adoptRefined(
        key,
        const GuideV3RefinedVersion(messages: ['第二張調過'], requestId: 'r3'),
      );
    expect(versions.displayed('run_v3:1', ['原本']), ['第一張改過']);
    expect(versions.displayed('run_v3:3', ['原本']), ['原本']);
    versions.clear();
    expect(versions.displayed('run_v3:1', ['原本']), ['原本']);
    expect(versions.refinedFor(key), isNull);
  });

  test('複製紀錄：再調的卡記成獨立事件，adviceType 遠低於 48 字上限', () {
    final eventId = ReplyIterationCoordinator.refineCopyEventId(
      originAdviceId: 'analyze:conv-1:run_v3:v3:2:push',
      requestId: 'req-9',
    );
    expect(eventId, 'refine:analyze:conv-1:run_v3:v3:2:push:req-9');
    expect('refine:v3:2:push'.length, lessThan(48));
    // 沒有冪等鍵就不記（寧可少一筆，也不記成無法去重的髒資料）。
    expect(
      ReplyIterationCoordinator.refineCopyEventId(
        originAdviceId: 'analyze:conv-1:run_v3:v3:2:push',
        requestId: null,
      ),
      isNull,
    );
  });
}
