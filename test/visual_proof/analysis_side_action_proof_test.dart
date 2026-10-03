import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/sections/analysis_fragment_section.dart';
import 'package:vibesync/features/analysis/presentation/widgets/analysis_action_widgets.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/shared/widgets/brand/brand_kit.dart';

import 'proof_support.dart';

class _NoopFragmentActions implements AnalysisFragmentActions {
  const _NoopFragmentActions();

  @override
  void chooseConversationSource() {}

  @override
  void editFragmentMessage(Message message) {}

  @override
  void swapFragmentMessageSide(Message message) {}

  @override
  void deleteFragmentMessage(Message message) {}
}

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
            // 用真正的片段卡，避免手刻舊卡配新泡泡的混合體。
            AnalysisFragmentCard(
              isEmptyFragmentSetup: false,
              isPendingFragment: true,
              isCompletedFragment: false,
              showRecordRepairWarning: false,
              isScreenshotOnlyEmptyState: false,
              showEmptyState: false,
              messages: [
                for (final message in messages)
                  FragmentMessageItem(message: message, mutable: true),
              ],
              sourceLabel: '來源未設定',
              sourceEditable: true,
              actions: const _NoopFragmentActions(),
              partnerName: 'Bruce',
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
