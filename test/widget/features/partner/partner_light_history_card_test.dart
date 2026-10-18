import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/partner/domain/services/partner_light_history.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_light_history_card.dart';

import '../../../helpers/motion_free_app.dart';

/// 已經拿掉的升級鈕（不分方案都看完整紀錄，Eric 2026-10-19）：測試確認它不會回來。
const _upgradeLabel = '升級 Starter 看完整走勢';

PartnerLightHistoryEntry _entry(
  String id,
  DateTime at, {
  GuideV3Decision? decision = GuideV3Decision.send,
  GuideV3Light? light = GuideV3Light.green,
  GuideV3InviteReadiness? invite,
  GuideV3CareKind? careKind,
  GuideV3Light? previousLight,
}) =>
    PartnerLightHistoryEntry(
      recordId: id,
      analyzedAt: at,
      decision: decision,
      careKind: careKind,
      light: light,
      inviteReadiness: invite,
      previousLight: previousLight,
    );

/// 新到舊三筆：黃（先別回，從綠變黃）、綠（出卡，含糊答應）、綠（收尾，沒機會）。
final _three = [
  _entry(
    'r3',
    DateTime(2026, 10, 18, 21, 5),
    decision: GuideV3Decision.hold,
    light: GuideV3Light.yellow,
    invite: GuideV3InviteReadiness.hesitant,
    previousLight: GuideV3Light.green,
  ),
  _entry(
    'r2',
    DateTime(2026, 10, 17, 20, 10),
    invite: GuideV3InviteReadiness.vagueYes,
  ),
  _entry(
    'r1',
    DateTime(2026, 10, 16, 9, 30),
    decision: GuideV3Decision.close,
    invite: GuideV3InviteReadiness.none,
  ),
];

Future<void> _pump(
  WidgetTester t,
  List<PartnerLightHistoryEntry> entries, {
  bool expanded = false,
  VoidCallback? onToggleExpanded,
}) async {
  await t.pumpWidget(motionFreeApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: PartnerLightHistoryCard(
          entries: entries,
          expanded: expanded,
          onToggleExpanded: onToggleExpanded,
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

Finder _row(String id) => find.byKey(ValueKey('partner-light-history-row-$id'));

void main() {
  testWidgets('只有一次分析：看得到那一次，不放鎖住的預覽也不放升級', (t) async {
    final latest = [
      _entry(
        'only',
        DateTime(2026, 10, 18, 21, 5),
        invite: GuideV3InviteReadiness.clearYes,
      ),
    ];
    await _pump(t, latest);

    expect(find.text('燈號紀錄'), findsOneWidget);
    expect(find.text('燈號只代表那一輪的局面'), findsOneWidget);
    expect(_row('only'), findsOneWidget);
    expect(find.text('10/18 21:05'), findsOneWidget);
    expect(find.text('綠燈'), findsOneWidget);
    expect(find.text('該回'), findsOneWidget);
    // 最新一次的邀約進度寫在上面那一行。
    expect(find.text('邀約進度：明確答應'), findsOneWidget);
    expect(find.byKey(const ValueKey('partner-light-history-locked')),
        findsNothing);
    expect(find.text(_upgradeLabel), findsNothing);
  });

  testWidgets('四次分析（不分方案，Eric 2026-10-19）：全部列出、標變化，沒有鎖住的預覽與升級鈕', (t) async {
    await _pump(t, [
      _entry(
        'r4',
        DateTime(2026, 10, 19, 8),
        invite: GuideV3InviteReadiness.sheProposed,
        previousLight: GuideV3Light.yellow,
      ),
      ..._three,
    ]);

    expect(_row('r4'), findsOneWidget);
    for (final older in _three) {
      expect(_row(older.recordId), findsOneWidget, reason: older.recordId);
    }
    expect(find.text('邀約進度：她自己提見面'), findsOneWidget);
    expect(find.text('黃 → 綠'), findsOneWidget);
    expect(find.text('綠 → 黃'), findsOneWidget);
    expect(find.text('先別回 · 邀約進度：猶豫'), findsOneWidget);
    expect(find.byKey(const ValueKey('partner-light-history-locked')),
        findsNothing);
    expect(find.textContaining('完整走勢'), findsNothing);
    expect(find.text(_upgradeLabel), findsNothing);
  });

  testWidgets('完整紀錄：相鄰燈號不同標「綠 → 黃」，舊的每筆帶邀約進度', (t) async {
    await _pump(t, _three);

    for (final entry in _three) {
      expect(_row(entry.recordId), findsOneWidget);
    }
    expect(find.text('10/18 21:05'), findsOneWidget);
    expect(find.text('10/17 20:10'), findsOneWidget);
    expect(find.text('10/16 09:30'), findsOneWidget);
    expect(find.text('黃燈'), findsOneWidget);
    expect(find.text('綠燈'), findsNWidgets(2));
    expect(find.text('綠 → 黃'), findsOneWidget);
    // 最新一次的邀約進度放在上面一行；舊的每筆自己帶。
    expect(find.text('邀約進度：猶豫'), findsOneWidget);
    expect(find.text('先別回'), findsOneWidget);
    expect(find.text('該回 · 邀約進度：含糊答應'), findsOneWidget);
    expect(find.text('收尾 · 邀約進度：沒機會'), findsOneWidget);
    expect(find.byKey(const ValueKey('partner-light-history-locked')),
        findsNothing);
    expect(find.text(_upgradeLabel), findsNothing);
    // 新到舊。
    expect(t.getTopLeft(_row('r3')).dy, lessThan(t.getTopLeft(_row('r2')).dy));
    expect(t.getTopLeft(_row('r2')).dy, lessThan(t.getTopLeft(_row('r1')).dy));
  });

  testWidgets('停顯示「先停」；關心只寫先確認安全或不提供建議，不放燈號與邀約進度', (t) async {
    await _pump(
      t,
      [
        _entry('stop', DateTime(2026, 10, 19, 10),
            decision: GuideV3Decision.stop,
            light: GuideV3Light.red,
            previousLight: GuideV3Light.yellow),
        _entry('minor', DateTime(2026, 10, 18, 10),
            decision: GuideV3Decision.care,
            light: null,
            careKind: GuideV3CareKind.minor),
        _entry('care', DateTime(2026, 10, 17, 10),
            decision: GuideV3Decision.care,
            light: null,
            careKind: GuideV3CareKind.selfHarm),
        _entry('hold', DateTime(2026, 10, 16, 10),
            decision: GuideV3Decision.hold, light: GuideV3Light.yellow),
      ],
    );

    expect(find.text('先停'), findsOneWidget);
    expect(find.text('黃 → 紅'), findsOneWidget);
    expect(
      find.descendant(of: _row('care'), matching: find.text('先確認安全')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: _row('minor'), matching: find.text('不提供建議')),
      findsOneWidget,
    );
    for (final id in ['care', 'minor']) {
      expect(
        find.descendant(of: _row(id), matching: find.textContaining('燈')),
        findsNothing,
        reason: id,
      );
      expect(
        find.descendant(of: _row(id), matching: find.textContaining('邀約進度')),
        findsNothing,
        reason: id,
      );
    }
  });

  testWidgets('舊紀錄沒有新欄位：照樣列出，沒有邀約進度就不寫；快照壞掉只寫日期與燈號', (t) async {
    await _pump(
      t,
      [
        _entry('broken', DateTime(2026, 10, 18, 10), decision: null),
        _entry('old', DateTime(2026, 10, 17, 10),
            decision: GuideV3Decision.send, light: GuideV3Light.red),
      ],
    );

    expect(_row('broken'), findsOneWidget);
    expect(_row('old'), findsOneWidget);
    expect(find.textContaining('邀約進度'), findsNothing);
    expect(find.text('紅燈'), findsOneWidget);
    expect(find.text('綠燈'), findsOneWidget);
    expect(find.text('該回'), findsOneWidget);
  });

  testWidgets('紀錄很多時先列最近幾筆，按「看全部」再展開（展開狀態由頁面持有）', (t) async {
    final many = List.generate(
      kPartnerLightHistoryCollapsedRows + 2,
      (i) => _entry('m$i', DateTime(2026, 10, 18).subtract(Duration(days: i))),
    );
    var toggles = 0;
    await _pump(t, many, onToggleExpanded: () => toggles++);

    for (var i = 0; i < many.length; i++) {
      expect(
          _row('m$i'),
          i < kPartnerLightHistoryCollapsedRows
              ? findsOneWidget
              : findsNothing);
    }
    await t.tap(find.text('看全部 ${many.length} 次'));
    await t.pumpAndSettle();
    expect(toggles, 1);

    await _pump(t, many, expanded: true, onToggleExpanded: () => toggles++);
    for (var i = 0; i < many.length; i++) {
      expect(_row('m$i'), findsOneWidget);
    }
    expect(find.text('收起'), findsOneWidget);
  });
}
