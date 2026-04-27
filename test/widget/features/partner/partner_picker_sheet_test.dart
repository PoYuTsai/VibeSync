import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/widgets/partner_picker_sheet.dart';

Partner _p(String id, String name) => Partner(
      id: id,
      name: name,
      ownerUserId: 'u-1',
      createdAt: DateTime(2026, 4, 27),
      updatedAt: DateTime(2026, 4, 27),
    );

void main() {
  testWidgets('lists all partners except excludeId', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith(
          (_) => [_p('A', 'Alice'), _p('B', 'Bob'), _p('C', 'Cara')],
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PartnerPickerSheet(excludeId: 'A')),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Cara'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
  });

  testWidgets('filter TextField narrows by name (case-insensitive)',
      (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith(
          (_) => [_p('A', 'Alice'), _p('B', 'Bob'), _p('C', 'Cara')],
        ),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PartnerPickerSheet()),
      ),
    ));
    await t.pumpAndSettle();

    await t.enterText(find.byType(TextField), 'BO');
    await t.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Cara'), findsNothing);
  });

  testWidgets('tap on row invokes onSelected with that Partner', (t) async {
    Partner? captured;
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith((_) => [_p('A', 'Alice')]),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: PartnerPickerSheet(
            onSelected: (p) => captured = p,
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('Alice'));
    await t.pumpAndSettle();
    expect(captured?.id, 'A');
  });

  testWidgets('empty after exclude shows hint message', (t) async {
    await t.pumpWidget(ProviderScope(
      overrides: [
        partnerListProvider.overrideWith((_) => [_p('A', 'Alice')]),
      ],
      child: const MaterialApp(
        home: Scaffold(body: PartnerPickerSheet(excludeId: 'A')),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.textContaining('尚無其他對象'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });
}
