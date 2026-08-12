import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/analysis/domain/entities/analysis_models.dart';
import 'package:vibesync/features/analysis/presentation/widgets/screenshot_recognition_dialog.dart';
import 'package:vibesync/features/conversation/data/providers/conversation_providers.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/presentation/screens/add_partner_screen.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_room_entry_card.dart';

import 'proof_support.dart';

void main() {
  setUpAll(loadProofFonts);

  testWidgets('learning hero with quiet beam capture', (tester) async {
    await pumpAndCapture(
      tester,
      size: const Size(390, 760),
      rasterDecodeWait: const Duration(milliseconds: 500),
      child: const ProviderScope(
        child: Scaffold(
          body: SizedBox.expand(child: PracticeRoomEntryCard()),
        ),
      ),
      outPath: outPath('ocr_cleanup_hero_after.png'),
    );
  });

  testWidgets('add partner defaults capture', (tester) async {
    await pumpAndCapture(
      tester,
      child: TickerMode(
        enabled: false,
        child: ProviderScope(
          overrides: [
            authConversationScopeProvider.overrideWith(
              (ref) => Stream.value('u-proof'),
            ),
          ],
          child: const AddPartnerScreen(),
        ),
      ),
      outPath: outPath('ocr_cleanup_add_partner_after.png'),
    );
  });

  testWidgets('OCR confirmation with collapsed warning capture',
      (tester) async {
    final now = DateTime(2026, 8, 12);
    await pumpAndCapture(
      tester,
      child: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: TickerMode(
            enabled: false,
            child: ScreenshotRecognitionDialog(
              recognized: const RecognizedConversation(
                contactName: 'Bruce Chiang',
                messageCount: 2,
                summary: '識別到 2 則訊息',
                messages: [
                  RecognizedMessage(
                    side: 'left',
                    isFromMe: false,
                    content: '剛下超大雨，比有做好準備。',
                  ),
                  RecognizedMessage(
                    side: 'right',
                    isFromMe: true,
                    content: '妳有帶傘嗎？',
                  ),
                ],
              ),
              warningMessage:
                  '已自動把引用回覆的小卡片併回主訊息，保留它正在回覆的舊內容。這張截圖辨識到「Bruce Chiang」，和目前對象「ok」不同。若是另一人，請取消並回到正確對象；只有確認是目前這位對象時才能繼續。',
              initialName: 'ok',
              initialMeetingContext: MeetingContext.datingApp,
              initialDuration: AcquaintanceDuration.justMet,
              initialGoal: UserGoal.dateInvite,
              initialAnalysisContextNote: '',
              expectedPartnerName: 'ok',
              currentConversation: Conversation(
                id: 'c-proof',
                name: 'ok',
                partnerId: 'p-proof',
                messages: const [],
                createdAt: now,
                updatedAt: now,
              ),
            ),
          ),
        ),
      ),
      outPath: outPath('ocr_cleanup_confirmation_after.png'),
    );
  });
}
