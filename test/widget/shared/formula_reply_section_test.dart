// 公式回覆共用區塊 widget 測試（2026-07-24 公式回覆計畫 §12）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/shared/widgets/formula_reply_section.dart';

Future<List<String>> _mockClipboard(WidgetTester t) async {
  final copied = <String>[];
  t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => t.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return copied;
}

Widget _host(Widget child, {double width = 400}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

FormulaReplyEntry _entry(int n) => FormulaReplyEntry(
      openingLine: '公式開場$n：抓她一個具體線索加一點我的反應。',
      whyItWorks: '因為她只要補一個細節就能回（$n）。',
    );

void main() {
  testWidgets('空清單整區不渲染（不留標題／間距）', (t) async {
    await t.pumpWidget(_host(
      FormulaReplySection(
        title: '公式開場',
        entries: const [],
        onCopyOpeningLine: (_) {},
      ),
    ));
    expect(find.text('公式開場'), findsNothing);
    expect(find.text(FormulaReplySection.subtitle), findsNothing);
  });

  testWidgets('1／2 則正確渲染：標題＋副標＋為什麼好接；只有一則不補空卡', (t) async {
    for (final count in [1, 2]) {
      await t.pumpWidget(_host(
        FormulaReplySection(
          title: '公式新話題',
          entries: [for (var n = 1; n <= count; n++) _entry(n)],
          onCopyOpeningLine: (_) {},
        ),
      ));
      expect(find.text('公式新話題'), findsOneWidget);
      expect(find.text(FormulaReplySection.subtitle), findsOneWidget);
      expect(find.text('固定結構'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('formula-reply-section')),
        findsOneWidget,
      );
      // 2026-08-18 拍板：預設只展開第 1 則（主推），其餘收在「再看一組」。
      expect(find.text('為什麼好接'), findsOneWidget);
      expect(find.text('可直接傳'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('formula-reply-card-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('formula-reply-card-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('formula-reply-toggle-more')),
        count == 2 ? findsOneWidget : findsNothing,
        reason: '只有一則時不出現「再看一組」',
      );
    }
  });

  testWidgets('「再看一組」展開第 2 則、可再收起；換新 entries 自動收回', (t) async {
    Widget build(List<FormulaReplyEntry> entries) => _host(
          FormulaReplySection(
            title: '公式開場',
            entries: entries,
            onCopyOpeningLine: (_) {},
          ),
        );
    final firstEntries = [_entry(1), _entry(2)];
    await t.pumpWidget(build(firstEntries));

    await t.tap(find.byKey(const ValueKey('formula-reply-toggle-more')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('formula-reply-card-1')), findsOneWidget);
    expect(find.text('收起備選'), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('formula-reply-toggle-more')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('formula-reply-card-1')), findsNothing);
    expect(find.text('再看一組'), findsOneWidget);

    // 展開後換新一輪結果（新 list 實例）→ 回到只展開第 1 則。
    await t.tap(find.byKey(const ValueKey('formula-reply-toggle-more')));
    await t.pumpAndSettle();
    await t.pumpWidget(build([_entry(3), _entry(4)]));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('formula-reply-card-1')), findsNothing);
  });

  testWidgets('公式區以梅紫群組包住深色扁平卡，和上方一般回覆形成層級', (t) async {
    await t.pumpWidget(_host(
      FormulaReplySection(
        title: '公式開場',
        entries: [_entry(1), _entry(2)],
        onCopyOpeningLine: (_) {},
      ),
    ));

    final section = t.widget<Container>(
      find.byKey(const ValueKey('formula-reply-section')),
    );
    final sectionDecoration = section.decoration! as BoxDecoration;
    expect(sectionDecoration.gradient, isA<LinearGradient>());
    expect(
      (sectionDecoration.gradient! as LinearGradient).colors,
      contains(AppColors.coachSurfaceRaised),
    );

    final card = t.widget<Container>(
      find.byKey(const ValueKey('formula-reply-card-0')),
    );
    final cardDecoration = card.decoration! as BoxDecoration;
    expect(
      cardDecoration.color,
      AppColors.coachBackgroundMid.withValues(alpha: 0.84),
    );
  });

  testWidgets('複製只複製 openingLine（不含教練註解）', (t) async {
    final copied = await _mockClipboard(t);
    FormulaReplyEntry? tapped;
    await t.pumpWidget(_host(
      FormulaReplySection(
        title: '公式開場',
        entries: [_entry(1), _entry(2)],
        onCopyOpeningLine: (entry) {
          tapped = entry;
          Clipboard.setData(ClipboardData(text: entry.openingLine));
        },
      ),
    ));
    // 第 2 則預設收合，先展開再複製，確認回呼帶到的是對的 entry。
    await t.tap(find.byKey(const ValueKey('formula-reply-toggle-more')));
    await t.pumpAndSettle();
    await t.tap(find.text('複製').last);
    await t.pump();
    expect(tapped?.openingLine, _entry(2).openingLine);
    expect(copied, [_entry(2).openingLine]);
    expect(copied.single.contains(_entry(2).whyItWorks), isFalse);
  });

  testWidgets('複製按鈕維持至少 48dp 觸控高度', (t) async {
    await t.pumpWidget(_host(
      FormulaReplySection(
        title: '公式開場',
        entries: [_entry(1)],
        onCopyOpeningLine: (_) {},
      ),
    ));

    final button = t.widget<TextButton>(find.widgetWithText(TextButton, '複製'));
    final minimumSize = button.style?.minimumSize?.resolve({});
    expect(minimumSize, isNotNull);
    expect(minimumSize!.height, greaterThanOrEqualTo(48));
  });

  testWidgets('320px＋1.5 倍文字仍不 overflow', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(_host(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: FormulaReplySection(
          title: '公式開場',
          entries: [_entry(1), _entry(2)],
          onCopyOpeningLine: (_) {},
        ),
      ),
      width: 320,
    ));
    expect(t.takeException(), isNull);
  });

  testWidgets('hard-cap 邊界長文＋窄螢幕（320）不 overflow、不 ellipsis', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => t.binding.setSurfaceSize(null));
    final longEntry = FormulaReplyEntry(
      openingLine: '開' * 180,
      whyItWorks: '因' * 300,
    );
    await t.pumpWidget(_host(
      FormulaReplySection(
        title: '公式開場',
        entries: [longEntry],
        onCopyOpeningLine: (_) {},
      ),
      width: 320,
    ));
    // 沒有 RenderFlex overflow（有的話 pumpWidget 會收到 FlutterError）。
    expect(t.takeException(), isNull);
    final openingText = t.widget<Text>(
      find.text(longEntry.openingLine),
    );
    expect(openingText.overflow, isNot(TextOverflow.ellipsis),
        reason: '自適應高度，不得截斷 cap 內內容');
  });
}
