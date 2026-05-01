// test/widget/features/partner/partner_data_quality_banner_test.dart
//
// Spec 3 Phase 5 Task 18 — informational data-quality banner contract tests.
//
// Pure widget tests. The banner is RECEIVE-ONLY: it just renders the two
// candidate names + invokes callbacks. No Riverpod, no NamePair, no service
// calls — Task 19 wires the screen-level state.
//
// Tone contract (per design §4.2 / §4.3): the banner is INFORMATIONAL, not a
// warning. The "no warning visuals" assertion walks the widget tree and:
//   1. collects every Text widget's content + asserts none of the warning
//      lexicon (警告/異常/錯誤/⚠️/❌/🚨) appears
//   2. collects every Container's BoxDecoration color + asserts no Colors.red
//      shade or theme error color is used
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/partner/presentation/widgets/partner_data_quality_banner.dart';

const _warningLexicon = <String>['警告', '異常', '錯誤', '⚠️', '❌', '🚨'];

/// Walks every descendant Text widget under [finder] and returns the
/// concatenated rendered string content (Text.data + InlineSpan.toPlainText).
String _collectAllRenderedText(WidgetTester tester, Finder finder) {
  final buffer = StringBuffer();
  for (final element in finder.evaluate()) {
    final widget = element.widget;
    if (widget is Text) {
      if (widget.data != null) buffer.writeln(widget.data);
      if (widget.textSpan != null) buffer.writeln(widget.textSpan!.toPlainText());
    }
  }
  return buffer.toString();
}

/// Walks every descendant Container/DecoratedBox under [finder] and returns
/// the set of colors found in BoxDecoration.color or Container.color.
Set<Color> _collectAllSurfaceColors(WidgetTester tester, Finder finder) {
  final colors = <Color>{};
  for (final element in finder.evaluate()) {
    final widget = element.widget;
    if (widget is Container) {
      final dec = widget.decoration;
      if (dec is BoxDecoration && dec.color != null) {
        colors.add(dec.color!);
      }
      if (widget.color != null) colors.add(widget.color!);
    }
    if (widget is DecoratedBox) {
      final dec = widget.decoration;
      if (dec is BoxDecoration && dec.color != null) {
        colors.add(dec.color!);
      }
    }
  }
  return colors;
}

bool _isReddish(Color c) {
  // Reddish = R dominant + R noticeably higher than G & B. We accept the
  // VibeSync glass cream/lavender palette (R ~0xF5, G ~0xF0, B ~0xF8) as
  // non-red because R ≤ B. Anything where R > G + 30 AND R > B + 30 is red.
  final r = (c.r * 255.0).round();
  final g = (c.g * 255.0).round();
  final b = (c.b * 255.0).round();
  return r > g + 30 && r > b + 30 && r >= 0x80;
}

Widget _harness({
  String nameA = 'Anna',
  String nameB = 'May',
  VoidCallback? onMarkSamePerson,
  VoidCallback? onSplit,
}) {
  return MaterialApp(
    home: Scaffold(
      body: PartnerDataQualityBanner(
        nameA: nameA,
        nameB: nameB,
        onMarkSamePerson: onMarkSamePerson ?? () {},
        onSplit: onSplit ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('shows two names + 同一人 + 拆成新對象 actions', (tester) async {
    await tester.pumpWidget(_harness(nameA: 'Anna', nameB: 'May'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Anna'), findsWidgets);
    expect(find.textContaining('May'), findsWidgets);
    expect(find.text('這是同一人'), findsOneWidget);
    expect(find.text('拆成新對象'), findsOneWidget);
  });

  testWidgets('does NOT use 紅色 / 警告 / 異常 / ⚠️ / ❌ / 🚨', (tester) async {
    await tester.pumpWidget(_harness(nameA: 'Anna', nameB: 'May'));
    await tester.pumpAndSettle();

    final allTextFinder = find.byType(Text);
    final renderedText = _collectAllRenderedText(tester, allTextFinder);
    for (final token in _warningLexicon) {
      expect(
        renderedText.contains(token),
        isFalse,
        reason: 'Banner must not contain warning token "$token". '
            'Rendered text:\n$renderedText',
      );
    }

    final surfaceFinder = find.descendant(
      of: find.byType(PartnerDataQualityBanner),
      matching: find.byWidgetPredicate(
        (w) => w is Container || w is DecoratedBox,
      ),
    );
    final surfaceColors = _collectAllSurfaceColors(tester, surfaceFinder);
    for (final c in surfaceColors) {
      expect(
        _isReddish(c),
        isFalse,
        reason: 'Banner surface color $c is reddish — informational banner '
            'must not use red/error tones.',
      );
      expect(
        c,
        isNot(equals(Colors.red)),
        reason: 'Banner must not use Colors.red.',
      );
    }
  });

  testWidgets('tap 這是同一人 invokes onMarkSamePerson', (tester) async {
    var sameTapped = 0;
    var splitTapped = 0;
    await tester.pumpWidget(_harness(
      onMarkSamePerson: () => sameTapped++,
      onSplit: () => splitTapped++,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('這是同一人'));
    await tester.pumpAndSettle();

    expect(sameTapped, 1);
    expect(splitTapped, 0);
  });

  testWidgets('tap 拆成新對象 invokes onSplit', (tester) async {
    var sameTapped = 0;
    var splitTapped = 0;
    await tester.pumpWidget(_harness(
      onMarkSamePerson: () => sameTapped++,
      onSplit: () => splitTapped++,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('拆成新對象'));
    await tester.pumpAndSettle();

    expect(sameTapped, 0);
    expect(splitTapped, 1);
  });
}
