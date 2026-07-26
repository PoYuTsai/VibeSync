// test/widget/features/learning/ebook_entry_list_test.dart
//
// 條目庫：預設全收合（不出現長牆）、點開才顯示內文、可多條同時展開、
// 收合狀態不持久化、巢狀互動的 callback 一路傳得到、大字級不 overflow。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/learning/domain/models/ebook_block.dart';
import 'package:vibesync/features/learning/domain/models/ebook_progress.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_block_renderer.dart';

import '../../../helpers/ebook_test_content.dart';

EbookEntryListBlock buildLibrary({int entries = 3}) => EbookEntryListBlock(
      id: 'lib-1',
      title: '對話拆解庫',
      entries: [
        for (var i = 1; i <= entries; i++)
          EbookEntry(
            id: 'lib-1-e$i',
            title: '案例 $i · 查戶口式死亡',
            summary: '對話死在第 $i 句',
            blocks: [
              EbookParagraphBlock(id: 'lib-1-e$i-b1', text: '案例 $i 的完整內文。'),
            ],
          ),
      ],
    );

Future<List<String>> pumpLibrary(
  WidgetTester tester, {
  EbookEntryListBlock? block,
  double textScale = 1.0,
  Size size = const Size(390, 1400),
}) async {
  final quizzes = <String>[];
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: EbookBlockRenderer(
              block: block ?? buildLibrary(),
              progress: EbookBookProgress.empty,
              onQuizSubmitted: (quiz, _, __) => quizzes.add(quiz.id),
              onChecklistItemChanged: (_, __, ___) {},
              onFunnelTargetTap: (_, __) {},
            ),
          ),
        ),
      ),
    ),
  );
  return quizzes;
}

void main() {
  testWidgets('預設全部收合：看得到標題與摘要，看不到內文', (tester) async {
    await pumpLibrary(tester);

    expect(find.text('對話拆解庫'), findsOneWidget);
    expect(find.text('共 3 條，點開你需要的那一條'), findsOneWidget);
    for (var i = 1; i <= 3; i++) {
      expect(find.text('案例 $i · 查戶口式死亡'), findsOneWidget);
      expect(find.text('對話死在第 $i 句'), findsOneWidget);
      expect(find.text('案例 $i 的完整內文。'), findsNothing);
    }
  });

  testWidgets('點一條才展開那一條的內文', (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.text('案例 2 · 查戶口式死亡'));
    await tester.pumpAndSettle();

    expect(find.text('案例 2 的完整內文。'), findsOneWidget);
    expect(find.text('案例 1 的完整內文。'), findsNothing);
    expect(find.text('案例 3 的完整內文。'), findsNothing);
  });

  testWidgets('可以同時展開多條，再點一次收合', (tester) async {
    await pumpLibrary(tester);

    await tester.tap(find.text('案例 1 · 查戶口式死亡'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('案例 3 · 查戶口式死亡'));
    await tester.pumpAndSettle();
    expect(find.text('案例 1 的完整內文。'), findsOneWidget);
    expect(find.text('案例 3 的完整內文。'), findsOneWidget);

    await tester.tap(find.text('案例 1 · 查戶口式死亡'));
    await tester.pumpAndSettle();
    expect(find.text('案例 1 的完整內文。'), findsNothing);
    expect(find.text('案例 3 的完整內文。'), findsOneWidget);
  });

  testWidgets('條目裡的 Quiz 作答會回報給呼叫端（callback 傳得下去）',
      (tester) async {
    final block = EbookEntryListBlock(
      id: 'lib-2',
      entries: [
        EbookEntry(
          id: 'lib-2-e1',
          title: '帶測驗的條目',
          blocks: [buildTestQuiz(id: 'nested-quiz')],
        ),
        EbookEntry(
          id: 'lib-2-e2',
          title: '純文字條目',
          blocks: [
            EbookParagraphBlock(id: 'lib-2-e2-b1', text: '另一條。'),
          ],
        ),
      ],
    );

    final quizzes = await pumpLibrary(tester, block: block);

    await tester.tap(find.text('帶測驗的條目'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('發生什麼事，是人的問題還是事的問題'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('送出答案'));
    await tester.pumpAndSettle();

    expect(quizzes, ['nested-quiz']);
  });

  testWidgets('展開狀態不是進度：重建之後回到全部收合', (tester) async {
    await pumpLibrary(tester);
    await tester.tap(find.text('案例 1 · 查戶口式死亡'));
    await tester.pumpAndSettle();
    expect(find.text('案例 1 的完整內文。'), findsOneWidget);

    // 先卸載再重建，等同離開這一章再回來。
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await pumpLibrary(tester);
    expect(find.text('案例 1 的完整內文。'), findsNothing);
  });

  testWidgets('320 寬 + 2.0 字級不 overflow', (tester) async {
    await pumpLibrary(
      tester,
      textScale: 2.0,
      size: const Size(320, 2600),
    );
    await tester.tap(find.text('案例 1 · 查戶口式死亡'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });
}
