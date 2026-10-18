import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/partner/domain/services/partner_light_history.dart';

/// v3 分析紀錄：快照是伺服器 finalResult 的原樣（analysis_persistence_coordinator）。
AnalysisRecord _v3Record(
  String id,
  DateTime createdAt, {
  required String decision,
  String? light,
  String? inviteReadiness,
  String? careKind,
  String? snapshotOverride,
}) {
  final snapshot = snapshotOverride ??
      jsonEncode({
        'guideVersion': 'v3.5',
        'read': {
          'guideVersion': 'v3.5',
          'decision': decision,
          if (light != null) 'light': light,
          'judgment': '',
          if (careKind != null) 'careKind': careKind,
          if (inviteReadiness != null) 'inviteReadiness': inviteReadiness,
          if (inviteReadiness != null)
            'cold': {'c1': false, 'herPerfunctoryStreak': 0},
          'plannedCards': const [],
        },
        'cards': const [],
        'partial': false,
      });
  return AnalysisRecord(
    id: id,
    ownerUserId: 'u1',
    conversationId: 'c-$id',
    partnerId: 'p1',
    subjectName: 'Alice',
    segmentStart: 0,
    segmentEnd: 1,
    createdAt: createdAt,
    messages: [
      AnalysisRecordMessage.fromMessage(Message(
        id: 'm-$id',
        content: '好啊',
        isFromMe: false,
        timestamp: createdAt,
      )),
    ],
    analysisSnapshotJson: snapshot,
    analyzedContentRevision: 'rev-$id',
    completionKey: 'run-$id',
    sourcePlatform: null,
    enthusiasmScore: null,
    gameStageLabel: '',
    guideVersion: 'v3.5',
    guideV3Light: light,
  );
}

AnalysisRecord _v2Record(String id, DateTime createdAt) => AnalysisRecord(
      id: id,
      ownerUserId: 'u1',
      conversationId: 'c-$id',
      partnerId: 'p1',
      subjectName: 'Alice',
      segmentStart: 0,
      segmentEnd: 1,
      createdAt: createdAt,
      messages: [
        AnalysisRecordMessage.fromMessage(Message(
          id: 'm-$id',
          content: '嗯',
          isFromMe: false,
          timestamp: createdAt,
        )),
      ],
      analysisSnapshotJson: '{"enthusiasm":{"score":60}}',
      analyzedContentRevision: 'rev-$id',
      completionKey: 'run-$id',
      sourcePlatform: null,
      enthusiasmScore: 60,
      gameStageLabel: '建立連結',
    );

void main() {
  test('每次 v3 分析一筆、新到舊；舊流程紀錄不算', () {
    final entries = buildPartnerLightHistory([
      _v3Record('a', DateTime(2026, 10, 16, 9),
          decision: 'send', light: 'green'),
      _v2Record('legacy', DateTime(2026, 10, 17, 9)),
      _v3Record('c', DateTime(2026, 10, 18, 21, 5),
          decision: 'hold', light: 'yellow', inviteReadiness: 'hesitant'),
      _v3Record('b', DateTime(2026, 10, 17, 20),
          decision: 'close', light: 'red', inviteReadiness: 'declined'),
    ]);
    expect(entries.map((e) => e.recordId), ['c', 'b', 'a']);
    expect(entries.map((e) => e.decision), [
      GuideV3Decision.hold,
      GuideV3Decision.close,
      GuideV3Decision.send,
    ]);
    expect(entries.map((e) => e.light),
        [GuideV3Light.yellow, GuideV3Light.red, GuideV3Light.green]);
    expect(entries.first.inviteReadiness, GuideV3InviteReadiness.hesitant);
    expect(entries.first.analyzedAt, DateTime(2026, 10, 18, 21, 5));
  });

  test('相鄰兩筆燈號不同才記上一筆的燈號；關心沒有燈號、跳過不比', () {
    final entries = buildPartnerLightHistory([
      _v3Record('1', DateTime(2026, 10, 14), decision: 'send', light: 'green'),
      _v3Record('2', DateTime(2026, 10, 15), decision: 'send', light: 'green'),
      _v3Record('3', DateTime(2026, 10, 16), decision: 'hold', light: 'yellow'),
      _v3Record('4', DateTime(2026, 10, 17),
          decision: 'care', light: 'red', careKind: 'self_harm'),
      _v3Record('5', DateTime(2026, 10, 18), decision: 'stop', light: 'red'),
    ]);
    expect(entries.map((e) => e.recordId), ['5', '4', '3', '2', '1']);
    expect(entries.map((e) => e.previousLight), [
      GuideV3Light.yellow, // 紅（停）跟前一個有燈號的（黃）比，跳過關心
      null, // 關心沒有燈號
      GuideV3Light.green,
      null, // 綠 → 綠 沒變
      null, // 最早一筆
    ]);
    final care = entries[1];
    expect(care.isCare, isTrue);
    expect(care.light, isNull);
    expect(care.careKind, GuideV3CareKind.selfHarm);
    expect(care.inviteReadiness, isNull);
  });

  test('舊紀錄沒有邀約進度：照樣列出，邀約進度是 null；快照壞掉只留日期與紀錄上的燈號', () {
    final entries = buildPartnerLightHistory([
      _v3Record('old', DateTime(2026, 10, 17), decision: 'send', light: 'red'),
      _v3Record('broken', DateTime(2026, 10, 18),
          decision: 'send', light: 'green', snapshotOverride: '{not json'),
    ]);
    expect(entries.map((e) => e.recordId), ['broken', 'old']);
    final broken = entries.first;
    expect(broken.decision, isNull);
    expect(broken.light, GuideV3Light.green);
    expect(broken.previousLight, GuideV3Light.red);
    final old = entries.last;
    expect(old.decision, GuideV3Decision.send);
    expect(old.inviteReadiness, isNull);
  });

  test('沒有 v3 紀錄就是空清單', () {
    expect(buildPartnerLightHistory(const []), isEmpty);
    expect(
      buildPartnerLightHistory([_v2Record('legacy', DateTime(2026, 10, 1))]),
      isEmpty,
    );
  });
}
