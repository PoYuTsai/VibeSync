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
  final edits = <int>[];
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
          onCopy: (card, text, toast) => calls.copies.add(text),
          onEdit: (card) => calls.edits.add(card.slot),
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
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-2-message-1')));
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-2-copy')));
    expect(calls.copies, [
      '那家我也想吃吃看',
      '週末給妳機會證明',
      '妳這樣說我會當真喔\n週末給妳機會證明',
    ]);
    expect(find.text('複製這句'), findsOneWidget);
    expect(find.text('複製整組'), findsOneWidget);
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
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-message-0')));
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-fill')));
    expect(calls.copies, isEmpty);
    expect(calls.edits, [1, 1]);
    // 不含空格的那一則可以單獨複製。
    await tester.tap(find.byKey(const ValueKey('guide-v3-card-1-message-1')));
    expect(calls.copies, ['妳呢']);

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
    expect(calls.copies, ['我是做設計的\n妳呢']);
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
    expect(find.text('要等她：等她回你，再看她怎麼接'), findsOneWidget);
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
