import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/presentation/widgets/about_me_card.dart';

class _PendingProfile extends UserProfileController {
  final _pending = Completer<UserProfile?>();

  @override
  Future<UserProfile?> build() => _pending.future;
}

void main() {
  testWidgets('讀取關於我時保留卡片骨架，避免下方報告跳位', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileControllerProvider.overrideWith(_PendingProfile.new),
        ],
        child: const MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              disableAnimations: true,
              textScaler: TextScaler.linear(1.3),
            ),
            child: Scaffold(body: AboutMeCard()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('讓 VibeSync 更像你的教練'), findsOneWidget);
    expect(find.bySemanticsLabel('關於我設定載入中'), findsOneWidget);
    expect(tester.getSize(find.byType(AboutMeCard)).height, greaterThan(150));
  });
}
