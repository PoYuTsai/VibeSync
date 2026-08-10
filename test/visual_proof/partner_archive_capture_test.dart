// 階段 C 遷移對照：partner_analysis_archive 整頁 capture。
// 遷移前後各跑一次，PNG 進 before/ 或 after/（由 SLOP_STAGE 環境變數決定，
// 預設 after）。fakes 抄自 partner_analysis_archive_screen_test.dart。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/analysis_history/data/providers/analysis_history_providers.dart';
import 'package:vibesync/features/analysis_history/domain/entities/analysis_history_event.dart';
import 'package:vibesync/features/analysis_history/domain/repositories/analysis_history_repository.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_archive_providers.dart';
import 'package:vibesync/features/conversation/data/repositories/conversation_archive_store.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/presentation/providers/partner_providers.dart';
import 'package:vibesync/features/partner/presentation/screens/partner_analysis_archive_screen.dart';

import 'proof_support.dart';

class _MemoryArchiveStore implements ConversationArchiveStore {
  final Map<String, ConversationArchiveEntry> entries = {};

  @override
  ConversationArchiveEntry? entryFor(Conversation conversation) =>
      entries[conversation.id];

  @override
  Future<void> markActive(
    Conversation conversation, {
    DateTime? changedAt,
    String? analyzedContentRevision,
  }) async {}

  @override
  Future<void> markArchived(
    Conversation conversation, {
    required DateTime archivedAt,
  }) async {
    entries[conversation.id] = ConversationArchiveEntry.archived(
      archivedAt: archivedAt,
      contentRevision: conversationContentRevision(conversation),
    );
  }

  @override
  Future<void> remove(Conversation conversation) async {}
}

class _FakeHistoryRepository implements AnalysisHistoryRepository {
  @override
  Stream<void> watchChanges() => const Stream<void>.empty();

  @override
  Future<void> append(AnalysisHistoryEvent event) async {}

  @override
  Future<void> clearAll() async {}

  @override
  List<AnalysisHistoryEvent> listByConversation(
    String conversationId, {
    int? limit,
  }) =>
      const [];

  @override
  List<AnalysisHistoryEvent> listByKind(
    AnalysisHistoryKind kind, {
    int? limit,
  }) =>
      const [];

  @override
  List<AnalysisHistoryEvent> listRecent({int? limit}) => const [];
}

Partner _partner() => Partner(
      id: 'p1',
      name: 'Alice',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 7, 11),
      ownerUserId: 'u1',
    );

Conversation _conversation(String id, DateTime updatedAt) => Conversation(
      id: id,
      name: id,
      messages: const [],
      createdAt: updatedAt,
      updatedAt: updatedAt,
      ownerUserId: 'u1',
      partnerId: 'p1',
      lastAnalysisSnapshotJson: '{"ok":true}',
      lastAnalyzedMessageCount: 0,
    );

void main() {
  setUpAll(loadProofFonts);

  testWidgets('capture partner analysis archive screen', (tester) async {
    final stage = Platform.environment['SLOP_STAGE'] ?? 'after';
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final july = _conversation('july', DateTime(2026, 7, 10));
    final june = _conversation('june', DateTime(2026, 6, 20));
    final store = _MemoryArchiveStore();
    await store.markArchived(july, archivedAt: DateTime(2026, 7, 11));
    await store.markArchived(june, archivedAt: DateTime(2026, 6, 21));

    final rootKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: ProviderScope(
          overrides: [
            conversationArchiveStoreProvider.overrideWithValue(store),
            analysisHistoryRepositoryProvider
                .overrideWithValue(_FakeHistoryRepository()),
            partnerByIdProvider('p1').overrideWith((_) => _partner()),
            conversationsByPartnerProvider('p1')
                .overrideWith((_) => [june, july]),
          ],
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
            routerConfig: GoRouter(
              initialLocation: '/archive',
              routes: [
                GoRoute(
                  path: '/archive',
                  builder: (_, __) =>
                      const PartnerAnalysisArchiveScreen(partnerId: 'p1'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(rootKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      (File(outPath('$stage/partner_archive.png'))..createSync(recursive: true))
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
