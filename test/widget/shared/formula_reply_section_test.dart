// 公式回覆共用區塊 widget 測試（2026-07-24 公式回覆計畫 §12）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(find.text('為什麼好接'), findsNWidgets(count));
      expect(find.text('可直接傳'), findsNWidgets(count));
      expect(find.byKey(const ValueKey('formula-reply-card-0')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('formula-reply-card-1')),
        count == 2 ? findsOneWidget : findsNothing,
      );
    }
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
    await t.tap(find.text('複製').last);
    await t.pump();
    expect(tapped?.openingLine, _entry(2).openingLine);
    expect(copied, [_entry(2).openingLine]);
    expect(copied.single.contains(_entry(2).whyItWorks), isFalse);
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
