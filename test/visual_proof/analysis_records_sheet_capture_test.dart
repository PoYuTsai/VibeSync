// 階段 C-2 對照：分析紀錄 sheet 整頁 capture（SLOP_STAGE=before|after）。
// fixture 抄自 analysis_records_ui_test.dart。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:vibesync/features/analysis/domain/entities/analysis_record.dart';
import 'package:vibesync/features/analysis/presentation/screens/partner_analysis_records_screen.dart';

import 'proof_support.dart';

AnalysisRecord _record({
  required String id,
  required DateTime createdAt,
  required String preview,
  String? sourcePlatform,
}) {
  return AnalysisRecord(
    id: id,
    ownerUserId: 'user-1',
    conversationId: 'conversation-$id',
    partnerId: 'partner-1',
    subjectName: '小雲',
    segmentStart: 0,
    segmentEnd: 2,
    createdAt: createdAt,
    messages: [
      AnalysisRecordMessage(
        id: '$id-1',
        content: '妳週末去哪裡玩？',
        isFromMe: true,
        timestamp: createdAt,
      ),
      AnalysisRecordMessage(
        id: '$id-2',
        content: preview,
        isFromMe: false,
        timestamp: createdAt.add(const Duration(minutes: 1)),
      ),
    ],
    enthusiasmScore: 72,
    sourcePlatform: sourcePlatform,
    analysisSnapshotJson: '{"ok":true}',
    analyzedContentRevision: 'revision-$id',
    completionKey: 'completion-$id',
    gameStageLabel: '建立男女感',
  );
}

void main() {
  setUpAll(loadProofFonts);

  testWidgets('capture analysis records sheet', (tester) async {
    final stage = Platform.environment['SLOP_STAGE'] ?? 'after';
    await tester.binding.setSurfaceSize(kPhone);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final rootKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: rootKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
          home: Scaffold(
            backgroundColor: const Color(0xFF1F1330),
            body: Padding(
              padding: const EdgeInsets.only(top: 120),
              child: PartnerAnalysisRecordsScreen(
                subjectName: '小雲',
                metVia: 'Omi',
                records: [
                  _record(
                    id: 'a',
                    createdAt: DateTime(2026, 7, 12, 21),
                    preview: 'Omi 上的新片段',
                    sourcePlatform: 'Omi',
                  ),
                  _record(
                    id: 'b',
                    createdAt: DateTime(2026, 7, 10, 21),
                    preview: 'LINE 上的舊片段',
                    sourcePlatform: 'LINE',
                  ),
                ],
                platformForRecord: (record) => record.sourcePlatform,
                onSetMetVia: (_) {},
                onDelete: (_) {},
              ),
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
      (File(outPath('$stage/analysis_records_sheet.png'))
            ..createSync(recursive: true))
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  });
}
