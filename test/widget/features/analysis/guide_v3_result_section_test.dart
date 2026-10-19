import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/core/theme/app_icons.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis/presentation/sections/guide_v3_result_section.dart';
import 'package:vibesync/features/analysis/presentation/widgets/guide_v3_task_card.dart';

/// 預設排卡的第 3 張標 locked：伺服器改成免費也看全部的卡之前（Eric 2026-10-19）存的
/// 免費結果長這樣；畫面不畫它、也不推升級。
GuideV3Read _read({
  String decision = 'send',
  String light = 'green',
  String judgment = '她有在接你的話，可以往前一步。',
  List<Map<String, dynamic>>? planned,
  String? waitFor,
  String? careMessage,
  String? careKind,
  String? inviteReadiness,
  Map<String, dynamic>? relation,
}) =>
    GuideV3Read.fromJson({
      'guideVersion': 'v3.4',
      'decision': decision,
      'light': light,
      'judgment': judgment,
      if (waitFor != null) 'waitFor': waitFor,
      if (careMessage != null) 'careMessage': careMessage,
      if (careKind != null) 'careKind': careKind,
      if (inviteReadiness != null) 'inviteReadiness': inviteReadiness,
      if (relation != null) 'relation': relation,
      'plannedCards': planned ??
          [
            {'slot': 1, 'task': 'accept', 'locked': false},
            {'slot': 2, 'task': 'tension', 'locked': false},
            {'slot': 3, 'task': 'push', 'locked': true},
          ],
    })!;

GuideV3Card _card(
  int slot,
  String task,
  List<String> messages, {
  bool invented = false,
}) =>
    GuideV3Card.fromJson({
      'slot': slot,
      'task': task,
      'method': invented ? 'invented' : 'reaction',
      'voice': 'default',
      'messages': messages,
      'hasInventedDetail': invented,
      'hasBlank': false,
    })!;

class _Calls {
  final copies = <String>[];
  final toasts = <String>[];
  final edits = <int>[];
  final refines = <int>[];
}

Future<_Calls> _pump(
  WidgetTester tester, {
  required GuideV3Read read,
  required List<GuideV3Card> cards,
  bool isStreaming = false,
  bool isFinal = true,
  bool partial = false,
  bool recovered = false,
  Map<int, List<String>> edited = const {},
  Map<int, List<String>> refined = const {},
  bool withRefine = false,
  // 填空框、再調面板帶回來的字（null＝他關掉、沒選）。
  List<String>? editResult,
  List<String>? refineResult,
  Map<int, String> explanations = const {},
  bool showRelationRadar = true,
  bool reconnectWording = false,
  Widget? Function(GuideV3Card card)? footerFor,
}) async {
  final calls = _Calls();
  await tester.binding.setSurfaceSize(const Size(430, 1600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: GuideV3ResultSection(
          read: read,
          cards: cards,
          isStreaming: isStreaming,
          isFinal: isFinal,
          partial: partial,
          recovered: recovered,
          editedMessagesFor: (card) => edited[card.slot],
          onCopy: (card, text, toast) {
            calls.copies.add(text);
            calls.toasts.add(toast);
          },
          onEdit: (card) async {
            calls.edits.add(card.slot);
            return editResult;
          },
          refinedMessagesFor: (card) => refined[card.slot],
          onRefine: withRefine
              ? (card) async {
                  calls.refines.add(card.slot);
                  return refineResult;
                }
              : null,
          explanations: explanations,
          showRelationRadar: showRelationRadar,
          reconnectWording: reconnectWording,
          footerFor: footerFor,
        ),
      ),
    ),
  ));
  return calls;
}

void main() {
  testWidgets('出卡：燈號、判讀、任務標籤；舊快照裡鎖住的卡不畫、不推升級', (tester) async {
    final calls = await _pump(
      tester,
      read: _read(),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
        _card(2, 'tension', ['妳這樣說我會當真喔', '週末給妳機會證明']),
      ],
    );

    expect(find.text('局面判讀'), findsOneWidget);
    expect(find.text('綠燈'), findsOneWidget);
    expect(find.text('她有在接你的話，可以往前一步。'), findsOneWidget);
    expect(find.text('可以這樣回'), findsOneWidget);
    expect(find.text('接住'), findsOneWidget);
    expect(find.text('帶張力'), findsOneWidget);
    expect(find.text('推進'), findsNothing, reason: '舊快照裡鎖住的卡連標籤都不畫');
    expect(find.textContaining('付費方案還有'), findsNothing);
    expect(find.byKey(const ValueKey('guide-v3-locked-block')), findsNothing);
    expect(find.text('看方案'), findsNothing);
    expect(find.byKey(const ValueKey('guide-v3-partial-note')), findsNothing,
        reason: 'locked 不算比較少');

    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-copy')));
    await tester.pump();
    // 點泡泡只複製那一則；主按鈕接著指到下一則（第 2 則之後回到第 1 則）。
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-2-message-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-2-copy')));
    await tester.pump();
    expect(calls.copies, [
      '那家我也想吃吃看',
      '週末給妳機會證明',
      '妳這樣說我會當真喔',
    ]);
    expect(calls.toasts, ['已複製這句', '已複製第 2 則', '已複製第 1 則']);
    expect(find.text('複製這句'), findsOneWidget);
    expect(find.text('複製整組'), findsOneWidget, reason: '只有兩則的卡有整組複製');
  });

  testWidgets('兩則一組（Eric 2026-10-18）：主按鈕先複製第 1 則、再第 2 則，提示分 2 則傳；整組複製在次要位置',
      (tester) async {
    final calls = await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
        {'slot': 2, 'task': 'tension', 'locked': false},
      ]),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
        _card(2, 'tension', ['妳這樣說我會當真喔', '週末給妳機會證明']),
      ],
    );
    final primary = find.byKey(const ValueKey('guide-v3-card-2-copy'));
    expect(find.text('分 2 則傳'), findsOneWidget);
    expect(
      find.descendant(of: primary, matching: find.text('複製第 1 則')),
      findsOneWidget,
    );
    // 一則的卡跟以前一樣：沒有提示、沒有整組複製。
    expect(
        find.byKey(const ValueKey('guide-v3-card-1-split-hint')), findsNothing);
    expect(
        find.byKey(const ValueKey('guide-v3-card-1-copy-all')), findsNothing);

    await tester.tap(primary);
    await tester.pump();
    expect(
      find.descendant(of: primary, matching: find.text('複製第 2 則')),
      findsOneWidget,
    );
    await tester.tap(primary);
    await tester.pump();
    expect(calls.copies, ['妳這樣說我會當真喔', '週末給妳機會證明']);
    expect(calls.toasts, ['已複製第 1 則', '已複製第 2 則']);
    expect(
      find.descendant(of: primary, matching: find.text('複製第 1 則')),
      findsOneWidget,
      reason: '傳完一輪回到第 1 則',
    );

    await tester.tap(find.byKey(const ValueKey('guide-v3-card-2-copy-all')));
    await tester.pump();
    expect(calls.copies.last, '妳這樣說我會當真喔\n週末給妳機會證明');
    expect(calls.toasts.last, '已複製這組訊息');
  });

  testWidgets('有空格：不給複製，要先填；填好之後才出現複製', (tester) async {
    final blank = _card(1, 'accept', ['我是做＿＿的', '妳呢']);
    var calls = await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: [blank],
    );
    expect(find.byKey(const ValueKey('guide-v3-card-1-copy')), findsNothing);
    expect(find.text('填好空格再複製'), findsOneWidget);
    expect(find.text('分 2 則傳'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-card-1-copy-all')), findsNothing,
        reason: '有空格時整組複製也不給');
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-message-0')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-fill')));
    await tester.pump();
    // 整張有空格就先填：點沒有空格的那一則也一樣去填空，不能先拿走。
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-message-1')));
    await tester.pump();
    expect(calls.copies, isEmpty);
    expect(calls.edits, [1, 1, 1]);

    calls = await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: [blank],
      edited: {
        1: ['我是做設計的', '妳呢'],
      },
    );
    expect(find.text('已改成你的'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-copy')));
    expect(calls.copies, ['我是做設計的']);
  });

  testWidgets('填好空格回來：卡片接著複製第 1 則，主按鈕指到第 2 則', (tester) async {
    final calls = await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: [
        _card(1, 'accept', ['我是做＿＿的', '妳呢']),
      ],
      editResult: const ['我是做設計的', '妳呢'],
    );
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-fill')));
    await tester.pump();
    expect(calls.edits, [1]);
    expect(calls.copies, ['我是做設計的']);
    expect(calls.toasts, ['已複製第 1 則']);

    // 呼叫端存好（卡上換成填好的字）：主按鈕接著指到第 2 則。
    await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: [
        _card(1, 'accept', ['我是做＿＿的', '妳呢']),
      ],
      edited: {
        1: ['我是做設計的', '妳呢'],
      },
    );
    final primary = find.byKey(const ValueKey('guide-v3-card-1-copy'));
    expect(
      find.descendant(of: primary, matching: find.text('複製第 2 則')),
      findsOneWidget,
    );

    // 之後卡上的字又換了（例如再調過）：從第 1 則重新開始。
    await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: [
        _card(1, 'accept', ['我是做＿＿的', '妳呢']),
      ],
      refined: {
        1: ['我做設計', '換你說'],
      },
    );
    expect(
      find.descendant(of: primary, matching: find.text('複製第 1 則')),
      findsOneWidget,
    );
  });

  testWidgets('免費也看全部的卡（Bruce PR #97，Eric 2026-10-19）：5 張全部送到就全部畫出來，沒有鎖卡區塊與看方案',
      (tester) async {
    final read = _read(planned: [
      {'slot': 1, 'task': 'accept', 'locked': false},
      {'slot': 2, 'task': 'accept', 'locked': false},
      {'slot': 3, 'task': 'tension', 'locked': false},
      {'slot': 4, 'task': 'tension', 'locked': false},
      {'slot': 5, 'task': 'push', 'locked': false},
    ]);
    await _pump(
      tester,
      read: read,
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
        _card(2, 'accept', ['妳推薦哪道']),
        _card(3, 'tension', ['妳這樣說我會當真喔']),
        _card(4, 'tension', ['那我要排第一個']),
        _card(5, 'push', ['週六下午一起去？']),
      ],
    );
    for (var slot = 1; slot <= 5; slot++) {
      expect(find.byKey(ValueKey('guide-v3-card-$slot-copy')), findsOneWidget,
          reason: 'slot $slot');
    }
    expect(find.byKey(const ValueKey('guide-v3-locked-block')), findsNothing);
    expect(find.textContaining('付費方案還有'), findsNothing);
    expect(find.text('看方案'), findsNothing);
    expect(find.byKey(const ValueKey('guide-v3-partial-note')), findsNothing);
  });

  testWidgets('舊快照：伺服器改之前存的免費結果，排卡裡標 locked 的不畫、不出鎖卡區塊與看方案，也不算比較少',
      (tester) async {
    await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
        {'slot': 2, 'task': 'accept', 'locked': false},
        {'slot': 3, 'task': 'tension', 'locked': true},
        {'slot': 4, 'task': 'tension', 'locked': true},
        {'slot': 5, 'task': 'push', 'locked': true},
      ]),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
        _card(2, 'accept', ['妳推薦哪道']),
      ],
    );
    expect(find.byKey(const ValueKey('guide-v3-card-1-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-card-2-copy')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-locked-block')), findsNothing);
    expect(find.textContaining('付費方案還有'), findsNothing);
    expect(find.text('帶張力'), findsNothing);
    expect(find.text('推進'), findsNothing);
    expect(find.text('看方案'), findsNothing);
    expect(find.byKey(const ValueKey('guide-v3-partial-note')), findsNothing);
  });

  // ── 第一張卡是推薦（Bruce PR #97，Eric 2026-10-19）：跟開場救星、新話題同一個「AI 推薦」
  //    膠囊；卡片列表上面一行推薦理由，用第一張卡任務的固定說明，不花模型費 ──
  testWidgets('第一張卡標「AI 推薦」，卡片列表上面一行 AI 推薦理由（第一張卡任務的固定說明）', (tester) async {
    await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
        {'slot': 2, 'task': 'tension', 'locked': false},
        {'slot': 3, 'task': 'push', 'locked': false},
      ]),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
        _card(2, 'tension', ['妳這樣說我會當真喔']),
        _card(3, 'push', ['週六下午一起去？']),
      ],
    );

    final badge = find.byKey(const ValueKey('guide-v3-card-1-recommended'));
    expect(badge, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('guide-v3-card-1')),
        matching: find.text('AI 推薦'),
      ),
      findsOneWidget,
    );
    expect(find.text('AI 推薦'), findsOneWidget, reason: '只有第一張');
    final reason = find.text(
      'AI 推薦理由：先接她剛說的話，\n讓她知道你有在聽。',
    );
    expect(reason, findsOneWidget);
    // 理由在標題和第一張卡之間。
    expect(
      tester.getTopLeft(reason).dy,
      greaterThan(tester.getBottomLeft(find.text('可以這樣回')).dy),
    );
    expect(
      tester.getBottomLeft(reason).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('guide-v3-card-1'))).dy,
      ),
    );
  });

  testWidgets('「AI 推薦」膠囊與推薦理由的樣子照開場救星（顏色、圓角、字級）', (tester) async {
    await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'push', 'locked': false},
      ]),
      cards: [
        _card(1, 'push', ['週六下午一起去？']),
      ],
    );

    final pill = tester.widget<Container>(
      find.byKey(const ValueKey('guide-v3-card-1-recommended')),
    );
    final decoration = pill.decoration! as BoxDecoration;
    expect(decoration.color,
        AppColors.coachRecommendation.withValues(alpha: 0.16));
    expect(decoration.borderRadius, BorderRadius.circular(18));
    expect(
      (decoration.border! as Border).top.color,
      AppColors.coachRecommendation.withValues(alpha: 0.64),
    );
    final label = tester.widget<Text>(find.text('AI 推薦'));
    expect(label.style!.color, AppColors.coachRecommendation);
    expect(label.style!.fontSize, 12);
    expect(label.style!.fontWeight, FontWeight.w600);

    final icon = tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('guide-v3-recommendation-reason')),
        matching: find.byType(Icon),
      ),
    );
    expect(icon.icon, Icons.lightbulb_outline_rounded);
    expect(icon.size, 18);
    expect(icon.color, AppColors.coachRecommendation);
    final reason = tester.widget<Text>(
      find.text('AI 推薦理由：往見面靠近一步，\n例如提個想一起做的事，或約好時間。'),
    );
    expect(reason.style!.fontSize, 15);
    expect(reason.style!.color, AppColors.onBackgroundSecondary);
  });

  testWidgets('推薦理由在說明的第一個「，」後面換行，字跟任務標籤的說明一樣（五種任務）', (tester) async {
    for (final task in GuideV3Task.values) {
      await _pump(
        tester,
        read: _read(
          decision: task == GuideV3Task.close ? 'close' : 'send',
          planned: [
            {'slot': 1, 'task': task.wire, 'locked': false},
          ],
        ),
        cards: [
          _card(1, task.wire, ['好啊']),
        ],
      );
      final reason = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('guide-v3-recommendation-reason')),
              matching: find.byType(Text),
            ),
          )
          .data!;
      final purpose = guideV3TaskPurpose(task);
      expect(reason.replaceAll('\n', ''), 'AI 推薦理由：$purpose',
          reason: task.name);
      expect('\n'.allMatches(reason).length, 1, reason: task.name);
      expect(reason.indexOf('\n'), reason.indexOf('，') + 1, reason: task.name);
    }
  });

  testWidgets('收尾只有一張也標推薦；第 1 張被拿掉時標第一張送到的卡', (tester) async {
    await _pump(
      tester,
      read: _read(decision: 'close', planned: [
        {'slot': 1, 'task': 'close', 'locked': false},
      ]),
      cards: [
        _card(1, 'close', ['今天聊得很開心，早點休息']),
      ],
    );
    expect(find.byKey(const ValueKey('guide-v3-card-1-recommended')),
        findsOneWidget);
    expect(
      find.text('AI 推薦理由：讓這輪自然收個尾，\n不用硬聊下去。'),
      findsOneWidget,
    );

    await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
        {'slot': 2, 'task': 'resonate', 'locked': false},
      ]),
      cards: [
        _card(2, 'resonate', ['那一定很累吧']),
      ],
      partial: true,
    );
    expect(find.byKey(const ValueKey('guide-v3-card-2-recommended')),
        findsOneWidget);
    expect(find.text('AI 推薦'), findsOneWidget);
    expect(
      find.text('AI 推薦理由：站在她的感受這邊，\n讓她覺得你懂她。'),
      findsOneWidget,
    );
  });

  testWidgets('還在寫：第一張卡到了才出推薦與理由，正在寫的卡不標', (tester) async {
    final read = _read(planned: [
      {'slot': 1, 'task': 'accept', 'locked': false},
      {'slot': 2, 'task': 'push', 'locked': false},
    ]);
    await _pump(
      tester,
      read: read,
      cards: const [],
      isStreaming: true,
      isFinal: false,
    );
    expect(find.byKey(const ValueKey('guide-v3-pending-1')), findsOneWidget);
    expect(find.text('AI 推薦'), findsNothing);
    expect(find.textContaining('AI 推薦理由'), findsNothing);

    await _pump(
      tester,
      read: read,
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
      ],
      isStreaming: true,
      isFinal: false,
    );
    expect(find.byKey(const ValueKey('guide-v3-card-1-recommended')),
        findsOneWidget);
    expect(find.text('AI 推薦'), findsOneWidget, reason: '正在寫的第 2 張不標');
    expect(
      find.text('AI 推薦理由：先接她剛說的話，\n讓她知道你有在聽。'),
      findsOneWidget,
    );
  });

  testWidgets('沒有卡（先別回、停、關心、未成年、出卡但一張都沒送到）：不出推薦與理由', (tester) async {
    for (final (decision, careKind) in [
      ('hold', null),
      ('stop', null),
      ('care', null),
      ('care', 'minor'),
    ]) {
      await _pump(
        tester,
        read: _read(
          decision: decision,
          light: 'yellow',
          careMessage: decision == 'care' ? '先把安全放在第一位。' : null,
          careKind: careKind,
          planned: const [],
        ),
        cards: const [],
      );
      expect(find.text('AI 推薦'), findsNothing, reason: '$decision $careKind');
      expect(find.textContaining('AI 推薦理由'), findsNothing,
          reason: '$decision $careKind');
    }

    await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: const [],
      partial: true,
    );
    expect(find.text('AI 推薦'), findsNothing);
    expect(find.textContaining('AI 推薦理由'), findsNothing);
  });

  testWidgets('先別回、停、關心：就算排卡裡有鎖住的也不出升級', (tester) async {
    for (final decision in ['hold', 'stop', 'care']) {
      await _pump(
        tester,
        read: _read(
          decision: decision,
          light: 'yellow',
          careMessage: decision == 'care' ? '先把安全放在第一位。' : null,
          planned: [
            {'slot': 1, 'task': 'push', 'locked': true},
          ],
        ),
        cards: const [],
      );
      expect(find.byKey(const ValueKey('guide-v3-locked-block')), findsNothing,
          reason: decision);
      expect(find.text('看方案'), findsNothing, reason: decision);
    }
  });

  testWidgets('已升級、看的還是免費版：只給重新整理，不再叫他看方案', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GuideV3ResultSection(
            read: _read(),
            cards: [
              _card(1, 'accept', ['那家我也想吃吃看']),
              _card(2, 'tension', ['妳這樣說我會當真喔']),
            ],
            isStreaming: false,
            isFinal: true,
            editedMessagesFor: (_) => null,
            onCopy: (_, __, ___) {},
            onEdit: (_) async => null,
            showUpgradeRefresh: true,
            onRefreshAfterUpgrade: () {},
          ),
        ),
      ),
    ));
    expect(
        find.byKey(const ValueKey('guide-v3-upgrade-refresh')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-locked-block')), findsNothing);
    expect(find.text('看方案'), findsNothing);
  });

  testWidgets('照樣寫＋標示：提醒改成你的，可以直接複製也可以改', (tester) async {
    final calls = await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'resonate', 'locked': false},
      ]),
      cards: [
        _card(1, 'resonate', ['我上週也剛去爬了七星山'], invented: true),
      ],
    );
    expect(find.text(guideV3InventedNotice), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-edit')));
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-copy')));
    expect(calls.edits, [1]);
    expect(calls.copies, ['我上週也剛去爬了七星山']);
  });

  testWidgets('還在寫：排好但還沒到的卡顯示正在寫，不說比較少', (tester) async {
    await _pump(
      tester,
      read: _read(),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
      ],
      isStreaming: true,
      isFinal: false,
    );
    expect(find.byKey(const ValueKey('guide-v3-pending-2')), findsOneWidget);
    expect(find.text('正在寫這張…'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-partial-note')), findsNothing);
    expect(find.byKey(const ValueKey('guide-v3-pending-3')), findsNothing,
        reason: '鎖住的卡不顯示正在寫');
  });

  testWidgets('最終結果比預定少：標示這次比較少；續看重組另有說明', (tester) async {
    await _pump(
      tester,
      read: _read(),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
      ],
      partial: true,
    );
    expect(find.byKey(const ValueKey('guide-v3-pending-2')), findsNothing);
    expect(find.text('這次比預定的少幾張，已經寫好的可以直接用。'), findsOneWidget);

    await _pump(
      tester,
      read: _read(),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
      ],
      partial: true,
      recovered: true,
    );
    expect(find.text('連線中斷過，先給你已經寫好的卡。'), findsOneWidget);
  });

  testWidgets('先別回：燈號、判讀、要等她做什麼，沒有卡', (tester) async {
    await _pump(
      tester,
      read: _read(
        decision: 'hold',
        light: 'yellow',
        judgment: '你剛連傳兩則，球在她那邊。',
        waitFor: '等她回你，再看她怎麼接',
        planned: const [],
      ),
      cards: const [],
    );
    expect(find.text('先別回'), findsOneWidget);
    expect(find.text('黃燈'), findsOneWidget);
    expect(find.text('你剛連傳兩則，球在她那邊。'), findsOneWidget);
    expect(find.text('等到這時候再回：等她回你，再看她怎麼接'), findsOneWidget);
    expect(find.text('可以這樣回'), findsNothing);
  });

  testWidgets('先別回用琥珀色（Eric 2026-10-18）：黃燈不再放在紅框裡；停照舊是紅色', (tester) async {
    BoxDecoration panel() => tester
        .widget<Container>(find.byKey(const ValueKey('guide-v3-read')))
        .decoration! as BoxDecoration;
    Color iconColor() =>
        tester.widget<Icon>(find.byIcon(TablerIcons.hand_stop)).color!;

    await _pump(
      tester,
      read: _read(
        decision: 'hold',
        light: 'yellow',
        judgment: '你剛連傳兩則，球在她那邊。',
        planned: const [],
      ),
      cards: const [],
    );
    expect((panel().border! as Border).top.color,
        AppColors.warning.withValues(alpha: 0.32));
    expect(iconColor(), AppColors.warning);

    await _pump(
      tester,
      read: _read(
        decision: 'stop',
        light: 'red',
        judgment: '她說了不要，這段先停。',
        planned: const [],
      ),
      cards: const [],
    );
    expect((panel().border! as Border).top.color,
        AppColors.error.withValues(alpha: 0.32));
    expect(iconColor(), AppColors.error);
  });

  testWidgets('停：判讀，沒有卡', (tester) async {
    await _pump(
      tester,
      read: _read(
        decision: 'stop',
        light: 'red',
        judgment: '她說了不要，這段先停。',
        planned: const [],
      ),
      cards: const [],
    );
    expect(find.text('先停在這裡'), findsOneWidget);
    expect(find.text('紅燈'), findsOneWidget);
    expect(find.text('她說了不要，這段先停。'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-wait-for')), findsNothing);
  });

  testWidgets('關心：只顯示關心文案，沒有燈號、判讀與卡', (tester) async {
    await _pump(
      tester,
      read: _read(
        decision: 'care',
        light: 'red',
        judgment: '不該出現',
        careMessage: '先把安全放在第一位。\n情況緊急，打 110 或 119。',
        planned: const [],
      ),
      cards: const [],
    );
    expect(find.text('先關心安全'), findsOneWidget);
    expect(find.text('先把安全放在第一位。\n情況緊急，打 110 或 119。'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-light')), findsNothing);
    expect(find.text('不該出現'), findsNothing);
  });

  testWidgets('涉及未成年：另一個標題與固定說明，沒有燈號、判讀與卡', (tester) async {
    const message = '看起來對話裡有人未滿 18 歲或還在讀國中、高中，這類對話我們不提供回覆建議。這次不扣額度。';
    await _pump(
      tester,
      read: _read(
        decision: 'care',
        light: 'green',
        judgment: '不該出現',
        careMessage: message,
        careKind: 'minor',
        planned: const [],
      ),
      cards: const [],
    );
    expect(find.text('這段不提供建議'), findsOneWidget);
    expect(find.text('先關心安全'), findsNothing);
    expect(find.text(message), findsOneWidget);
    expect(find.byIcon(TablerIcons.info_circle), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-light')), findsNothing);
    expect(find.text('不該出現'), findsNothing);
    expect(find.text('可以這樣回'), findsNothing);
  });

  testWidgets('再調一下：畫面給了才出現，每張送到的卡各一個；鎖住、正在寫的卡沒有', (tester) async {
    final calls = await _pump(
      tester,
      read: _read(),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
        _card(2, 'tension', ['妳這樣說我會當真喔', '週末給妳機會證明']),
      ],
      withRefine: true,
    );
    expect(find.text('再調一下'), findsNWidgets(2));
    expect(
        find.byKey(const ValueKey('guide-v3-card-1-refine')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('guide-v3-card-2-refine')), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-card-3-refine')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-2-refine')));
    expect(calls.refines, [2]);
    expect(calls.copies, isEmpty, reason: '按再調不會複製');

    // 結果頁沒給（串流中、分析紀錄）：一顆都沒有。
    await _pump(
      tester,
      read: _read(),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
      ],
      isStreaming: true,
      isFinal: false,
    );
    expect(find.text('再調一下'), findsNothing);
    expect(find.byKey(const ValueKey('guide-v3-pending-2')), findsOneWidget);
  });

  testWidgets('再調一下：舊快照帶不出卡片規格的卡不給', (tester) async {
    final old = GuideV3Card.fromJson({
      'slot': 1,
      'task': 'accept',
      'messages': ['那家我也想吃吃看'],
      'hasInventedDetail': false,
    })!;
    await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: [old],
      withRefine: true,
    );
    expect(find.byKey(const ValueKey('guide-v3-card-1-refine')), findsNothing);
    expect(find.byKey(const ValueKey('guide-v3-card-1-copy')), findsOneWidget);
  });

  testWidgets('再調過的版本：顯示調過的字，編的細節提醒照留，不算「已改成你的」', (tester) async {
    final calls = await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'resonate', 'locked': false},
      ]),
      cards: [
        _card(1, 'resonate', ['我上週也剛去爬了七星山'], invented: true),
      ],
      refined: {
        1: ['我上週也去爬七星山', '腿現在還在痠'],
      },
      withRefine: true,
    );
    expect(find.text('我上週也去爬七星山'), findsOneWidget);
    expect(find.text('我上週也剛去爬了七星山'), findsNothing);
    expect(find.text(guideV3RefinedLabel), findsOneWidget);
    expect(find.text('已改成你的'), findsNothing);
    expect(find.text(guideV3InventedNotice), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-copy')));
    expect(calls.copies, ['我上週也去爬七星山']);
  });

  testWidgets('再調選定的版本：卡片接著複製第 1 則；還有＿＿就先開填空', (tester) async {
    var calls = await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看', '妳推薦哪道']),
      ],
      withRefine: true,
      refineResult: const ['那家我也想去', '妳最愛哪道'],
    );
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-refine')));
    await tester.pump();
    expect(calls.refines, [1]);
    expect(calls.edits, isEmpty);
    expect(calls.copies, ['那家我也想去']);

    calls = await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看', '妳推薦哪道']),
      ],
      withRefine: true,
      refineResult: const ['我是做＿＿的', '妳呢'],
      editResult: const ['我是做設計的', '妳呢'],
    );
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-refine')));
    await tester.pump();
    expect(calls.edits, [1], reason: '再調的版本還有空格：先填');
    expect(calls.copies, ['我是做設計的']);
  });

  testWidgets('再調過的版本還有＿＿：一樣要先填才能複製；自己改過就以改過的為準', (tester) async {
    var calls = await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: [
        _card(1, 'accept', ['我是做＿＿的', '妳呢']),
      ],
      refined: {
        1: ['我做＿＿', '換你說'],
      },
      withRefine: true,
    );
    expect(find.byKey(const ValueKey('guide-v3-card-1-copy')), findsNothing);
    expect(find.text('填好空格再複製'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-message-1')));
    expect(calls.copies, isEmpty);
    expect(calls.edits, [1]);

    calls = await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: [
        _card(1, 'accept', ['我是做＿＿的', '妳呢']),
      ],
      edited: {
        1: ['我做設計', '換你說'],
      },
      refined: {
        1: ['我做＿＿', '換你說'],
      },
      withRefine: true,
    );
    expect(find.text('已改成你的'), findsOneWidget);
    expect(find.text(guideV3RefinedLabel), findsNothing);
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-copy')));
    expect(calls.copies, ['我做設計']);
  });

  testWidgets('填空：還有＿＿就不能複製，填好才回傳', (tester) async {
    List<String>? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showGuideV3EditSheet(
                context,
                messages: const ['我是做＿＿的', '妳呢'],
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('把＿＿換成你的'), findsOneWidget);
    expect(find.text('還有＿＿沒填'), findsOneWidget);
    final copyButton = find.byKey(const ValueKey('guide-v3-edit-copy'));
    expect(tester.widget<FilledButton>(copyButton).onPressed, isNull);
    expect(
      find.descendant(of: copyButton, matching: find.text('複製第 1 則')),
      findsOneWidget,
      reason: '兩則的卡從第 1 則開始傳',
    );

    await tester.enterText(
      find.byKey(const ValueKey('guide-v3-edit-field-0')),
      '我是做設計的',
    );
    await tester.pump();
    expect(find.text('還有＿＿沒填'), findsNothing);
    expect(tester.widget<FilledButton>(copyButton).onPressed, isNotNull);

    await tester.tap(copyButton);
    await tester.pumpAndSettle();
    expect(result, ['我是做設計的', '妳呢']);
  });

  test('填空框帶回來的字：跟打開前一樣（去掉頭尾空白後）就算沒改', () {
    expect(guideV3EditChanged(const ['那家我也想吃吃看'], const ['那家我也想吃吃看']), isFalse);
    expect(
        guideV3EditChanged(const ['那家我也想吃吃看 '], const ['那家我也想吃吃看']), isFalse);
    expect(guideV3EditChanged(const ['那家我也想吃吃看'], const ['那家我也想去']), isTrue);
    expect(guideV3EditChanged(const ['我是做＿＿的', '妳呢'], const ['我是做設計的', '妳呢']),
        isTrue);
  });

  testWidgets('填空（Eric 2026-10-18）：一打開就停在第一個空格、整段＿＿先選好；沒有空格不搶焦點',
      (tester) async {
    Future<void> open(List<String> messages) async {
      // 上一次開的面板還在：整棵重建，才點得到 open。
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  showGuideV3EditSheet(context, messages: messages),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    EditableTextState field(int i) => tester.state<EditableTextState>(
          find.descendant(
            of: find.byKey(ValueKey('guide-v3-edit-field-$i')),
            matching: find.byType(EditableText),
          ),
        );

    // 空格在第二則：焦點在第二則，選好「＿＿」那一段。
    await open(const ['好啊', '我是做＿＿的']);
    expect(field(0).widget.focusNode.hasFocus, isFalse);
    expect(field(1).widget.focusNode.hasFocus, isTrue);
    expect(
      field(1).widget.controller.selection,
      const TextSelection(baseOffset: 3, extentOffset: 5),
    );

    // 改成我的（沒有空格）：照舊不自動跳鍵盤。
    await open(const ['我上週也剛去爬了七星山']);
    expect(field(0).widget.focusNode.hasFocus, isFalse);
  });

  // ── 為什麼（Eric 2026-10-18）：任務標籤、燈號點一下看說明，不花模型費 ──
  test('每種任務都有一句自己的用途', () {
    final purposes = {
      for (final task in GuideV3Task.values) guideV3TaskPurpose(task),
    };
    expect(purposes, hasLength(GuideV3Task.values.length));
    expect(purposes.every((p) => p.trim().isNotEmpty), isTrue);
  });

  testWidgets('點任務標籤：只展開那張卡的用途句，再點收起', (tester) async {
    await _pump(
      tester,
      read: _read(),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
        _card(2, 'tension', ['妳這樣說我會當真喔']),
      ],
    );
    final accept = guideV3TaskPurpose(GuideV3Task.accept);
    final tension = guideV3TaskPurpose(GuideV3Task.tension);
    expect(find.text(accept), findsNothing);

    await tester.tap(find.byKey(const ValueKey('guide-v3-task-chip-1')));
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('guide-v3-card-1')),
        matching: find.text(accept),
      ),
      findsOneWidget,
    );
    expect(find.text(tension), findsNothing, reason: '只展開點的那張');

    await tester.tap(find.byKey(const ValueKey('guide-v3-task-chip-1')));
    await tester.pump();
    expect(find.text(accept), findsNothing);
  });

  testWidgets('點燈號：三種燈各一行，最後一行說只看這一輪；再點收起', (tester) async {
    await _pump(
      tester,
      read: _read(light: 'yellow'),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
      ],
    );
    final explanation =
        find.byKey(const ValueKey('guide-v3-light-explanation'));
    expect(explanation, findsNothing);

    await tester.tap(find.byKey(const ValueKey('guide-v3-light')));
    await tester.pump();
    expect(explanation, findsOneWidget);
    for (final light in GuideV3Light.values) {
      expect(
        find.descendant(
          of: explanation,
          matching: find.text('${light.label}：${guideV3LightMeaning(light)}'),
        ),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(
          of: explanation, matching: find.text(guideV3LightRoundNote)),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('guide-v3-light')));
    await tester.pump();
    expect(explanation, findsNothing);
  });

  testWidgets('先別回也能點燈號看說明；關心沒有燈號就沒有說明', (tester) async {
    await _pump(
      tester,
      read: _read(
        decision: 'hold',
        light: 'red',
        judgment: '你剛連傳兩則，球在她那邊。',
        planned: const [],
      ),
      cards: const [],
    );
    await tester.tap(find.byKey(const ValueKey('guide-v3-light')));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('guide-v3-light-explanation')),
      findsOneWidget,
    );

    await _pump(
      tester,
      read: _read(
        decision: 'care',
        careMessage: '先把安全放在第一位。',
        planned: const [],
      ),
      cards: const [],
    );
    expect(find.byKey(const ValueKey('guide-v3-light')), findsNothing);
    expect(
      find.byKey(const ValueKey('guide-v3-light-explanation')),
      findsNothing,
    );
  });

  // ── 可及性（Eric 2026-10-18，只動 v3 結果的元件，不改全域主題） ──
  testWidgets('按鈕與可點的標籤都至少 44 高', (tester) async {
    await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
        {'slot': 2, 'task': 'tension', 'locked': false},
        {'slot': 3, 'task': 'resonate', 'locked': false},
        {'slot': 4, 'task': 'push', 'locked': true},
      ]),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
        _card(2, 'tension', ['妳這樣說我會當真喔', '週末給妳機會證明']),
        _card(3, 'resonate', ['我上週也剛去爬了七星山'], invented: true),
      ],
      withRefine: true,
    );
    final targets = {
      'copy': find.byKey(const ValueKey('guide-v3-card-1-copy')),
      'copy-all': find.byKey(const ValueKey('guide-v3-card-2-copy-all')),
      'edit': find.byKey(const ValueKey('guide-v3-card-3-edit')),
      'refine': find.byKey(const ValueKey('guide-v3-card-1-refine')),
      'task-chip': find.byKey(const ValueKey('guide-v3-task-chip-1')),
      'light': find.ancestor(
        of: find.byKey(const ValueKey('guide-v3-light')),
        matching: find.byType(InkWell),
      ),
    };
    for (final entry in targets.entries) {
      expect(entry.value, findsOneWidget, reason: entry.key);
      expect(tester.getSize(entry.value).height, greaterThanOrEqualTo(44),
          reason: entry.key);
    }

    await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: [
        _card(1, 'accept', ['我是做＿＿的']),
      ],
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('guide-v3-card-1-fill'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('卡上的文字鈕對卡底至少 4.5:1（原本的主題紫約 3.2:1）', (tester) async {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    // 卡底：brandInk@.45 疊在頁面漸層最亮的 brandSurface2 上（估計值；真機另量）。
    final cardBg = Color.alphaBlend(
      AppColors.brandInk.withValues(alpha: 0.45),
      AppColors.brandSurface2,
    );
    Color textColor(Finder button, String label) => tester
        .renderObject<RenderParagraph>(
          find.descendant(of: button, matching: find.text(label)),
        )
        .text
        .style!
        .color!;

    await _pump(
      tester,
      read: _read(),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看'], invented: true),
        _card(2, 'tension', ['妳這樣說我會當真喔', '週末給妳機會證明']),
      ],
    );
    final buttons = {
      '改成我的': find.byKey(const ValueKey('guide-v3-card-1-edit')),
      '複製整組': find.byKey(const ValueKey('guide-v3-card-2-copy-all')),
    };
    for (final entry in buttons.entries) {
      expect(
        contrast(textColor(entry.value, entry.key), cardBg),
        greaterThanOrEqualTo(4.5),
        reason: entry.key,
      );
    }

    // 已升級、看的還是免費版：重新整理鈕放在橘色淡底上。
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: GuideV3ResultSection(
            read: _read(),
            cards: [
              _card(1, 'accept', ['那家我也想吃吃看']),
              _card(2, 'tension', ['妳這樣說我會當真喔']),
            ],
            isStreaming: false,
            isFinal: true,
            editedMessagesFor: (_) => null,
            onCopy: (_, __, ___) {},
            onEdit: (_) async => null,
            showUpgradeRefresh: true,
            onRefreshAfterUpgrade: () {},
          ),
        ),
      ),
    ));
    final refreshBg = Color.alphaBlend(
      AppColors.ctaStart.withValues(alpha: 0.1),
      AppColors.brandSurface2,
    );
    final refresh = find.byKey(const ValueKey('guide-v3-upgrade-refresh'));
    expect(
      contrast(textColor(refresh, '重新產生完整分析'), refreshBg),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      tester
          .getSize(find.descendant(
            of: refresh,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          ))
          .height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('VoiceOver：複製鈕帶任務、泡泡有點兩下的提示、任務標籤與燈號唸得出來', (tester) async {
    final handle = tester.ensureSemantics();
    await _pump(
      tester,
      read: _read(),
      cards: [
        _card(1, 'accept', ['那家我也想吃吃看']),
        _card(2, 'tension', ['妳這樣說我會當真喔', '週末給妳機會證明']),
      ],
    );

    expect(
      tester.getSemantics(find.byKey(const ValueKey('guide-v3-card-1-copy'))),
      isSemantics(
        label: '複製這句（接住）',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('guide-v3-card-2-copy'))),
      isSemantics(label: '複製第 1 則（帶張力）', isButton: true),
    );
    expect(
      tester.getSemantics(
          find.byKey(const ValueKey('guide-v3-card-1-message-0'))),
      isSemantics(
        label: '那家我也想吃吃看',
        hint: '點兩下複製這句',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(
          find.byKey(const ValueKey('guide-v3-card-2-message-1'))),
      isSemantics(
        label: '週末給妳機會證明',
        hint: '點兩下只複製這一則',
        isButton: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('guide-v3-task-chip-1'))),
      isSemantics(
        label: '任務：接住',
        hint: '點兩下看這張卡在做什麼',
        isButton: true,
        hasTapAction: true,
      ),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('guide-v3-light'))),
      isSemantics(
        label: '燈號：綠燈',
        hint: '點兩下看燈號的意思',
        isButton: true,
        hasTapAction: true,
      ),
    );

    // 有空格的卡：點泡泡會先開填空。
    await _pump(
      tester,
      read: _read(planned: [
        {'slot': 1, 'task': 'accept', 'locked': false},
      ]),
      cards: [
        _card(1, 'accept', ['我是做＿＿的']),
      ],
    );
    expect(
      tester.getSemantics(
          find.byKey(const ValueKey('guide-v3-card-1-message-0'))),
      isSemantics(hint: '點兩下先填空格', isButton: true),
    );
    expect(
      tester.getSemantics(find.byKey(const ValueKey('guide-v3-card-1-fill'))),
      isSemantics(label: '填好空格再複製（接住）', isButton: true),
    );
    handle.dispose();
  });
  group('關係狀態與為什麼這樣回（Bruce 2026-10-19 路線二，A3）', () {
    const relation = <String, dynamic>{
      'stage': 'premise',
      'heat': 72,
      'dimensions': {
        'heat': 72,
        'engagement': 70,
        'topicDepth': 45,
        'replyWillingness': 78,
        'emotionalConnection': 60,
      },
      'herMove': 'high',
      'willingness': 'high',
    };
    final cards = [
      _card(1, 'accept', ['那當然 我挑的欸']),
      _card(2, 'tension', ['妳這樣說我會當真喔']),
    ];

    testWidgets('判讀帶了關係狀態：判讀下面一張卡，燈號、她在做什麼、回覆意願、邀約進度、關係階段', (tester) async {
      await _pump(
        tester,
        read: _read(relation: relation, inviteReadiness: 'none'),
        cards: cards,
      );

      final card = find.byKey(const ValueKey('guide-v3-relation'));
      expect(card, findsOneWidget);
      // 放在局面判讀與「可以這樣回」之間。
      expect(
        tester.getTopLeft(card).dy,
        greaterThan(tester
            .getBottomLeft(find.byKey(const ValueKey('guide-v3-read')))
            .dy),
      );
      expect(
        tester.getTopLeft(card).dy,
        lessThan(tester.getTopLeft(find.text('可以這樣回')).dy),
      );
      for (final text in [
        '關係狀態',
        '燈號',
        '她這一輪在做什麼',
        '分享開心的事',
        '回覆意願',
        '她很想聊',
        '邀約進度',
        '還沒提過見面',
        '關係階段',
      ]) {
        expect(find.descendant(of: card, matching: find.text(text)),
            findsOneWidget,
            reason: text);
      }
      final stage = find.byKey(const ValueKey('guide-v3-relation-stage'));
      expect(find.descendant(of: stage, matching: find.text('目前・升溫')),
          findsOneWidget);
      // v3 只有階段，沒有 v2 的「節奏」那一行。
      expect(find.textContaining('節奏'), findsNothing);
      // 熱度與雷達先收在「詳細」裡。
      expect(find.text('對方這次的投入度'), findsNothing);
      expect(
          find.byKey(const ValueKey('guide-v3-relation-radar')), findsNothing);
    });

    testWidgets('放大字（1.4 倍）：標籤欄跟著放寬，「她這一輪在做什麼」不斷成兩行', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(390, 1600),
            textScaler: TextScaler.linear(1.4),
          ),
          child: Scaffold(
            body: SingleChildScrollView(
              child: GuideV3ResultSection(
                read: _read(relation: relation, inviteReadiness: 'none'),
                cards: cards,
                isStreaming: false,
                editedMessagesFor: (_) => null,
                onCopy: (_, __, ___) {},
                onEdit: (_) async => null,
              ),
            ),
          ),
        ),
      ));

      double height(String text) => tester.getSize(find.text(text)).height;
      expect(height('她這一輪在做什麼'), height('回覆意願'));
    });

    testWidgets('點「詳細」展開熱度（換成 0–90）與五維雷達，再點收起', (tester) async {
      await _pump(tester, read: _read(relation: relation), cards: cards);

      final toggle = find.byKey(const ValueKey('guide-v3-relation-detail'));
      expect(find.descendant(of: toggle, matching: find.text('熱度・五維雷達')),
          findsOneWidget);
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(44));
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('對方這次的投入度'), findsOneWidget);
      expect(find.text('65'), findsOneWidget);
      expect(find.byKey(const ValueKey('guide-v3-relation-radar')),
          findsOneWidget);
      expect(find.text('五維度剖析'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('對方這次的投入度'), findsNothing);
    });

    testWidgets('雷達照 v2 只給付費方案：免費的詳細只有熱度', (tester) async {
      await _pump(
        tester,
        read: _read(relation: relation),
        cards: cards,
        showRelationRadar: false,
      );
      final toggle = find.byKey(const ValueKey('guide-v3-relation-detail'));
      expect(find.descendant(of: toggle, matching: find.text('熱度')),
          findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('對方這次的投入度'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('guide-v3-relation-radar')), findsNothing);
    });

    testWidgets('已是伴侶：破冰階段說成重新連線', (tester) async {
      await _pump(
        tester,
        read: _read(relation: {...relation, 'stage': 'opening'}),
        cards: cards,
        reconnectWording: true,
      );
      expect(find.text('目前・重新連線'), findsOneWidget);
    });

    testWidgets('只帶了一部分：沒有的那一列、階段、詳細都不畫', (tester) async {
      await _pump(
        tester,
        read: _read(relation: const {'willingness': 'low'}),
        cards: cards,
      );
      final card = find.byKey(const ValueKey('guide-v3-relation'));
      expect(find.descendant(of: card, matching: find.text('興趣不高')),
          findsOneWidget);
      expect(find.text('她這一輪在做什麼'), findsNothing);
      expect(find.text('邀約進度'), findsNothing);
      expect(find.text('關係階段'), findsNothing);
      expect(
          find.byKey(const ValueKey('guide-v3-relation-detail')), findsNothing);
    });

    testWidgets('改版前的 v3（判讀沒帶）：沒有關係狀態卡，頁面照舊', (tester) async {
      await _pump(tester, read: _read(inviteReadiness: 'none'), cards: cards);
      expect(find.byKey(const ValueKey('guide-v3-relation')), findsNothing);
      expect(find.text('關係狀態'), findsNothing);
      expect(find.text('可以這樣回'), findsOneWidget);
    });

    testWidgets('先別回、停也畫（伺服器照送）；關心的判讀不收關係狀態，不畫', (tester) async {
      await _pump(
        tester,
        read: _read(
          decision: 'hold',
          planned: const [],
          waitFor: '等她回你',
          relation: relation,
        ),
        cards: const [],
      );
      expect(find.byKey(const ValueKey('guide-v3-relation')), findsOneWidget);

      await _pump(
        tester,
        read: _read(
          decision: 'care',
          planned: const [],
          careMessage: '先把安全放在第一位。',
          relation: relation,
        ),
        cards: const [],
      );
      expect(find.byKey(const ValueKey('guide-v3-relation')), findsNothing);
    });

    testWidgets('每張卡下面「為什麼這樣回」：有說明的卡才畫，放在成效回報列下面', (tester) async {
      await _pump(
        tester,
        read: _read(),
        cards: cards,
        explanations: const {1: '接住她誇你，用短短一句收下。'},
        footerFor: (card) => card.slot == 1
            ? const SizedBox(key: ValueKey('outcome-bar-1'), height: 10)
            : null,
      );

      final why = find.byKey(const ValueKey('guide-v3-card-1-why'));
      final taskCard = find.byKey(const ValueKey('guide-v3-task-card-1'));
      expect(find.descendant(of: taskCard, matching: why), findsOneWidget);
      expect(find.descendant(of: why, matching: find.text('為什麼這樣回')),
          findsOneWidget);
      expect(find.text('接住她誇你，用短短一句收下。'), findsOneWidget);
      expect(
        tester.getTopLeft(why).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.byKey(const ValueKey('outcome-bar-1'))).dy,
        ),
      );
      expect(find.byKey(const ValueKey('guide-v3-card-2-why')), findsNothing);
      expect(find.text('為什麼這樣回'), findsOneWidget);
    });

    testWidgets('沒有說明（兩段式沒開、舊快照）：卡跟原本一樣', (tester) async {
      await _pump(tester, read: _read(), cards: cards);
      expect(find.text('為什麼這樣回'), findsNothing);
    });
  });
}
