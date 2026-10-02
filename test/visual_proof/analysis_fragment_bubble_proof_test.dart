import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/presentation/sections/analysis_fragment_section.dart';
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

/// 截圖匯入的群組聊天片段：引用第三人、引用對方、沒有名字的引用、
/// 同一人連發與多行長句都在這一屏。
class _FragmentBubbleProof extends StatelessWidget {
  const _FragmentBubbleProof();

  @override
  Widget build(BuildContext context) {
    final timestamp = DateTime(2026, 10, 2, 18, 15);
    Message message(
      String id,
      String content, {
      required bool isFromMe,
      String? quote,
      bool? quoteIsFromMe,
    }) =>
        Message(
          id: id,
          content: content,
          isFromMe: isFromMe,
          timestamp: timestamp,
          quotedReplyPreview: quote,
          quotedReplyPreviewIsFromMe: quoteIsFromMe,
        );

    final messages = [
      message('1', '可以一起', isFromMe: false),
      message(
        '2',
        '好',
        isFromMe: true,
        quote: '阿哲：感覺11點多到的就好',
        quoteIsFromMe: true,
      ),
      message(
        '3',
        '但小美不認識他們吧',
        isFromMe: true,
        quote: '阿哲：可以欸',
        quoteIsFromMe: true,
      ),
      message(
        '4',
        '隨便吧',
        isFromMe: false,
        quote: 'Kai Lin：但小美不認識他們吧',
        quoteIsFromMe: false,
      ),
      // 沒有名字的引用（截圖裡只看得到原文）。
      message('5', '隨便 social', isFromMe: false, quote: '哈哈好啊'),
      message('6', '嗯嗯', isFromMe: false),
      message('7', '那我先問小美要不要一起，晚點再跟妳說時間', isFromMe: true),
    ];

    return BrandScaffold(
      safeArea: false,
      title: '小雲',
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            AnalysisFragmentCard(
              isEmptyFragmentSetup: false,
              isPendingFragment: false,
              isCompletedFragment: true,
              showRecordRepairWarning: false,
              isScreenshotOnlyEmptyState: false,
              showEmptyState: false,
              messages: [
                for (final m in messages)
                  FragmentMessageItem(message: m, mutable: false),
              ],
              sourceLabel: '來源：LINE',
              sourceEditable: false,
              actions: const _NoopFragmentActions(),
              partnerName: '小雲',
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  setUpAll(loadProofFonts);

  testWidgets('capture analysis fragment bubbles', (tester) async {
    await pumpAndCapture(
      tester,
      // pumpAndCapture 只改 surface size，MediaQuery 仍是測試預設的 800 寬；
      // 泡泡上限是螢幕寬的比例，對齊 iPhone 寬度才跟真機一致。
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(size: kPhone),
          child: const _FragmentBubbleProof(),
        ),
      ),
      outPath: outPath('analysis_fragment_bubbles.png'),
    );
  });
}
