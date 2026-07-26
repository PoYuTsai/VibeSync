// test/widget/features/learning/ebook_block_renderer_test.dart
//
// Block renderer：每種 block type 都有 UI、三燈與死亡點同時有文字與圖示、
// callout 安全提醒有語意標籤、checklist 只回報 id + bool。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/domain/models/ebook_block.dart';
import 'package:vibesync/features/learning/domain/models/ebook_progress.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_block_renderer.dart';

import '../../../helpers/ebook_test_content.dart';

typedef ChecklistCall = ({String blockId, String itemId, bool checked});

Future<List<ChecklistCall>> pumpBlocks(
  WidgetTester tester,
  List<EbookBlock> blocks, {
  EbookBookProgress progress = EbookBookProgress.empty,
  double textScale = 1.0,
  Size size = const Size(390, 2400),
  void Function(EbookStageFunnelBlock block, EbookFunnelStage stage)?
      onFunnelTargetTap,
  void Function(EbookCrossRefBlock block)? onCrossRefTap,
}) async {
  final checklistCalls = <ChecklistCall>[];
  // setSurfaceSize 才會真的改 layout 約束（MediaQueryData.size 單獨改不會）。
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, widget) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: widget!,
      ),
      home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final block in blocks)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: EbookBlockRenderer(
                        block: block,
                        progress: progress,
                        onQuizSubmitted: (_, __, ___) {},
                        onFunnelTargetTap: (block, stage) =>
                            onFunnelTargetTap?.call(block, stage),
                        onCrossRefTap: (block) => onCrossRefTap?.call(block),
                        onChecklistItemChanged: (block, itemId, checked) {
                          checklistCalls.add((
                            blockId: block.id,
                            itemId: itemId,
                            checked: checked,
                          ));
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
    ),
  );
  return checklistCalls;
}

List<EbookBlock> allBlockTypes() => [
      const EbookHeadingBlock(id: 'h', text: '標題文字'),
      const EbookParagraphBlock(id: 'p', text: '段落文字'),
      const EbookBulletListBlock(
        id: 'bl',
        title: '清單標題',
        items: ['第一項', '第二項'],
        ordered: true,
      ),
      const EbookCalloutBlock(
        id: 'co',
        tone: EbookCalloutTone.safety,
        title: '安全標題',
        text: '安全內文',
      ),
      const EbookComparisonBlock(
        id: 'cm',
        title: '比較標題',
        caption: '比較說明',
        items: [
          EbookComparisonItem(
            id: 'cm-a',
            stance: EbookComparisonStance.weak,
            label: '弱',
            text: '弱句內容',
            note: '弱句原因',
          ),
          EbookComparisonItem(
            id: 'cm-b',
            stance: EbookComparisonStance.strong,
            label: '強',
            text: '強句內容',
          ),
        ],
      ),
      buildTestDialogue(id: 'dlg'),
      buildTestFlipCard(id: 'flip'),
      buildTestQuiz(id: 'quiz'),
      buildTestChecklist(id: 'check'),
      const EbookCrossRefBlock(
        id: 'xref',
        label: '案例 K · 完整弧線',
        contextLabel: '《續航 · 讓對話活下去》第 5 章',
        targetBookId: 'ebook-2-conversation',
        targetChapterId: 'ebook-2-chapter-5',
        targetEntryId: 'ebook-2-c5-lib-e11',
      ),
    ];

void main() {
  testWidgets('renders every block type', (tester) async {
    await pumpBlocks(tester, allBlockTypes());

    expect(find.text('標題文字'), findsOneWidget);
    expect(find.text('段落文字'), findsOneWidget);
    expect(find.text('清單標題'), findsOneWidget);
    expect(find.text('第一項'), findsOneWidget);
    expect(find.text('1.'), findsOneWidget);
    expect(find.text('安全標題'), findsOneWidget);
    expect(find.text('比較標題'), findsOneWidget);
    expect(find.text('弱句內容'), findsOneWidget);
    expect(find.text('強句內容'), findsOneWidget);
    expect(find.text('逐句標記示範'), findsOneWidget);
    expect(find.text('表面問題'), findsOneWidget);
    expect(find.text('情境測驗 · 單選'), findsOneWidget);
    expect(find.text('本週自評'), findsOneWidget);
    expect(find.text('案例 K · 完整弧線'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('交叉指涉按鈕：說得出目標與所在位置，點了才回報', (tester) async {
    final taps = <String>[];
    await pumpBlocks(
      tester,
      allBlockTypes(),
      onCrossRefTap: (block) => taps.add(block.targetEntryId ?? block.id),
    );

    // 按之前就要看得出會去哪：目標標題與所在的書／章都在按鈕上。
    expect(find.text('《續航 · 讓對話活下去》第 5 章'), findsOneWidget);
    expect(taps, isEmpty);

    await tester.tap(find.text('案例 K · 完整弧線'));
    await tester.pumpAndSettle();

    expect(taps, ['ebook-2-c5-lib-e11']);
  });

  testWidgets('safety callout announces itself in words, not just an icon',
      (tester) async {
    await pumpBlocks(tester, [
      const EbookCalloutBlock(
        id: 'co',
        tone: EbookCalloutTone.safety,
        text: '公開場所、自主交通、告知朋友。',
      ),
    ]);

    expect(find.text('安全與界線'), findsOneWidget);
    expect(find.byIcon(Icons.shield_outlined), findsOneWidget);
  });

  testWidgets('每種 callout tone 都有文字標籤', (tester) async {
    await pumpBlocks(tester, [
      for (final tone in EbookCalloutTone.values)
        EbookCalloutBlock(id: 'co-${tone.name}', tone: tone, text: '內文'),
    ]);

    for (final label in const [
      '補充',
      '原理',
      '本章目標',
      '安全與界線',
      '注意',
      '今天帶走',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '缺少 tone 標籤 $label');
    }
  });

  testWidgets('三燈與死亡點都是顏色＋圖示＋文字', (tester) async {
    await pumpBlocks(tester, [buildTestDialogue(id: 'dlg')]);

    expect(find.text('綠燈 · 可以推進'), findsOneWidget);
    expect(find.text('紅燈 · 退回或停止'), findsOneWidget);
    expect(find.text('死亡點'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
    expect(find.byIcon(Icons.do_not_disturb_on_outlined), findsOneWidget);
    expect(find.byIcon(Icons.heart_broken_outlined), findsOneWidget);

    expect(find.bySemanticsLabel(RegExp('綠燈，可以推進')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('死亡點：對話從這一句開始失去動能')),
        findsOneWidget);
  });

  testWidgets('對話標出說話者與逐句標記', (tester) async {
    await pumpBlocks(tester, [buildTestDialogue(id: 'dlg')]);

    expect(find.text('你'), findsNWidgets(2));
    expect(find.text('對方'), findsOneWidget);
    expect(find.text('V↑ E↑'), findsOneWidget);
  });

  testWidgets('checklist 勾選只回報 id 與 bool，並可還原', (tester) async {
    final progress = const EbookBookProgress(
      checklistStates: {
        'check': {'check-i1'},
      },
    );
    final calls = await pumpBlocks(
      tester,
      [buildTestChecklist(id: 'check')],
      progress: progress,
    );

    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byIcon(Icons.check_box_outlined), findsOneWidget);

    await tester.tap(find.text('我露出了關於自己的一點東西'));
    await tester.pumpAndSettle();

    expect(calls, [
      (blockId: 'check', itemId: 'check-i2', checked: true),
    ]);

    await tester.tap(find.text('我引用了對方檔案裡的具體東西'));
    await tester.pumpAndSettle();

    expect(calls.last, (blockId: 'check', itemId: 'check-i1', checked: false));
  });

  testWidgets('quiz 依 progress 還原（revision 相符）', (tester) async {
    const progress = EbookBookProgress(
      quizStates: {
        'quiz': EbookQuizState(
          quizRevision: 1,
          selectedChoiceIds: ['quiz-b'],
          solved: true,
        ),
      },
    );
    await pumpBlocks(tester, [buildTestQuiz(id: 'quiz')], progress: progress);

    expect(find.text('答對了'), findsOneWidget);
  });

  testWidgets('quiz revision 不符時視為未作答', (tester) async {
    const progress = EbookBookProgress(
      quizStates: {
        'quiz': EbookQuizState(
          quizRevision: 1,
          selectedChoiceIds: ['quiz-b'],
          solved: true,
        ),
      },
    );
    await pumpBlocks(
      tester,
      [buildTestQuiz(id: 'quiz', revision: 2)],
      progress: progress,
    );

    expect(find.text('答對了'), findsNothing);
    expect(find.text('送出答案'), findsOneWidget);
  });

  testWidgets('320px 寬 + 2.0 text scale 不 overflow', (tester) async {
    await pumpBlocks(
      tester,
      allBlockTypes(),
      textScale: 2.0,
      size: const Size(320, 6000),
    );
    expect(tester.takeException(), isNull);
  });
}
