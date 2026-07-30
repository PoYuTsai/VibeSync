// Scoped visual proof — 學習頁書架（標題卡＋人物封面）。
// Run: flutter test test/visual_proof/ebook_shelf_proof_test.dart
// Out: build/visual_proof/ebook_shelf.png
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/learning/data/providers/ebook_providers.dart';
import 'package:vibesync/features/learning/data/repositories/ebook_progress_repository.dart';
import 'package:vibesync/features/learning/domain/models/ebook.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_access_gate.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_cover_badge.dart';
import 'package:vibesync/features/learning/presentation/widgets/ebook_shelf_section.dart';

import '../helpers/ebook_test_content.dart';
import '../helpers/ebook_widget_harness.dart';
import 'proof_support.dart';

Future<void> _loadFonts() async {
  // 絕不寫死本機字型路徑：這些 proof 會跟著 release gate 在 CI 上跑。
  for (final path in const [
    '/mnt/c/Windows/Fonts/msjh.ttc',
    '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    await (FontLoader('AppTC')
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
    break;
  }
  await loadProofFonts();
}

void main() {
  late EbookCatalog catalog;

  setUpAll(() async {
    await _loadFonts();
    // 內容資產一定要在 testWidgets 之外載入：>50KB 的 loadString 走 isolate，
    // 在 fake async 下永遠不會完成，測試會整個卡死。
    catalog = await loadProductionCatalog();
  });

  testWidgets('書架：標題卡與人物封面（免費使用者）', (tester) async {
    final container = ProviderContainer(
      overrides: [
        ebookSubscriptionAccessProvider
            .overrideWith((ref) => const EbookSubscriptionAccess.free()),
        ebookProgressOwnerProvider
            .overrideWith((ref) => Stream<String?>.value('proof-owner')),
        ebookProgressRepositoryProvider
            .overrideWithValue(EbookProgressRepository(box: InMemoryHiveBox())),
        ebookCatalogProvider.overrideWith((ref) async => catalog),
      ],
    );
    addTearDown(container.dispose);

    final rootKey = GlobalKey();
    final contentKey = GlobalKey();
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (_, __) => Container(
            color: AppColors.brandInk,
            child: SingleChildScrollView(
              child: KeyedSubtree(
                key: contentKey,
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: EbookShelfSection(),
                ),
              ),
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Future<void> pumpAt(double height) async {
      await tester.binding.setSurfaceSize(Size(390, height));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
            routerConfig: router,
            builder: (context, child) => RepaintBoundary(
              key: rootKey,
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontFamily: 'AppTC'),
                child: child!,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpAt(2200);
    // 封面是 Image.asset：不先在真 async 下解碼，截圖會是空白框。
    final context = tester.element(find.byType(EbookShelfSection));
    await tester.runAsync(() async {
      for (final book in catalog.books) {
        await precacheImage(AssetImage(ebookCoverPhotoAsset(book)), context);
      }
    });
    await tester.pumpAndSettle();

    final height = tester.getSize(find.byKey(contentKey)).height;
    await tester.binding.setSurfaceSize(Size(390, height.ceilToDouble()));
    await tester.pumpAndSettle();

    final boundary =
        tester.renderObject<RenderRepaintBoundary>(find.byKey(rootKey));
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      (File(outPath('ebook_shelf.png'))..createSync(recursive: true))
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
