import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/core/theme/app_colors.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_action_widgets.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/presentation/widgets/message_bubble.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';

import 'proof_support.dart';

class _AnalysisActionProof extends StatelessWidget {
  const _AnalysisActionProof();

  @override
  Widget build(BuildContext context) {
    final timestamp = DateTime(2026, 7, 19, 20);
    final messages = [
      Message(
        id: '1',
        content: '這週末想去走走',
        isFromMe: false,
        timestamp: timestamp,
      ),
      Message(
        id: '2',
        content: '妳有想去哪一區嗎？',
        isFromMe: true,
        timestamp: timestamp,
      ),
      Message(
        id: '3',
        content: '東區吧',
        isFromMe: false,
        timestamp: timestamp,
      ),
      Message(
        id: '4',
        content: '但我選擇障礙哈哈',
        isFromMe: false,
        timestamp: timestamp,
      ),
      Message(
        id: '5',
        content: '而且下午才有空',
        isFromMe: false,
        timestamp: timestamp,
      ),
    ];

    return BrandScaffold(
      safeArea: false,
      title: 'Bruce',
      floatingActionButtonLocation: const AnalysisSideCenterFabLocation(),
      floatingActionButton: FloatingAnalysisActionButton(onPressed: () {}),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 120),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.96),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.ctaStart.withValues(alpha: 0.24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '待分析的新片段',
                    style: TextStyle(
                      color: AppColors.glassTextPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '這批新聊天會獨立分析，不會接回上一筆紀錄。',
                    style: TextStyle(
                      color: AppColors.glassTextSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ...messages.map((message) => MessageBubble(message: message)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUpAll(loadProofFonts);

  testWidgets('capture right-center analysis orb', (tester) async {
    await pumpAndCapture(
      tester,
      child: const _AnalysisActionProof(),
      outPath: outPath('analysis_side_orb_scan.png'),
      settle: const Duration(milliseconds: 320),
    );
    await pumpAndCapture(
      tester,
      child: const _AnalysisActionProof(),
      outPath: outPath('analysis_side_orb_idle.png'),
    );
  });
}
