import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/guide_v3_result.dart';
import 'package:vibesync/features/analysis/presentation/sections/guide_v3_result_section.dart';
import 'package:vibesync/features/analysis/presentation/widgets/guide_v3_task_card.dart';

GuideV3Read _read({
  String decision = 'send',
  String light = 'green',
  String judgment = '她有在接你的話，可以往前一步。',
  List<Map<String, dynamic>>? planned,
  String? waitFor,
  String? careMessage,
}) =>
    GuideV3Read.fromJson({
      'guideVersion': 'v3.4',
      'decision': decision,
      'light': light,
      'judgment': judgment,
      if (waitFor != null) 'waitFor': waitFor,
      if (careMessage != null) 'careMessage': careMessage,
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
  var upgrades = 0;
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
          onUpgrade: () => calls.upgrades++,
        ),
      ),
    ),
  ));
  return calls;
}

void main() {
  testWidgets('出卡：燈號、判讀、任務標籤；免費方案的卡只給標籤與升級', (tester) async {
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
    expect(find.text('推進'), findsOneWidget, reason: 'locked 卡只顯示任務標籤');
    expect(find.text('升級後才看得到這張'), findsOneWidget);
    expect(find.byKey(const ValueKey('guide-v3-partial-note')), findsNothing,
        reason: 'locked 不算比較少');

    await tester.tap(find.byKey(const ValueKey('guide-v3-locked-3-upgrade')));
    expect(calls.upgrades, 1);

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

  testWidgets('分析紀錄的鎖住卡：說法不承諾補寫，升級入口照樣有', (tester) async {
    var upgrades = 0;
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
            onUpgrade: () => upgrades++,
            lockedMessage: guideV3LockedArchivedMessage,
          ),
        ),
      ),
    ));
    expect(find.text('付費方案才有這張'), findsOneWidget);
    expect(find.text('升級後才看得到這張'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('guide-v3-locked-3-upgrade')));
    expect(upgrades, 1);
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
}
