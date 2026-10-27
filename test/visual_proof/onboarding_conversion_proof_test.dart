// Visual proof for onboarding 轉換第 12 步：4 頁版 onboarding。
// 第 1 頁選路徑（Sydney 頭像＋三選一＋先逛逛）／第 2 頁內建題庫一題判讀（未作答、
// 答對、答錯）／第 3 頁目標問卷（未選、選 1）／第 4 頁三條路徑各自的下一步＋
// 免費額度＋AI 隱私一行／「看完整說明」sheet。Renders the REAL OnboardingScreen
// and walks the real buttons, asserting the target text before every capture so
// a wrong page can never be eyeballed as the right one.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/core/constants/ai_privacy_disclosure.dart';
import 'package:vibesync/features/learning/data/providers/chat_quiz_providers.dart';
import 'package:vibesync/features/learning/domain/models/chat_quiz.dart';
import 'package:vibesync/features/onboarding/data/onboarding_quiz.dart';
import 'package:vibesync/features/onboarding/presentation/screens/onboarding_screen.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_finish_page.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_intent_page.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_questionnaire_page.dart';
import 'package:vibesync/features/onboarding/presentation/widgets/onboarding_quiz_teaser_page.dart';

import '../helpers/chat_quiz_test_content.dart';
import 'proof_support.dart';

/// 同 chat_quiz proof：先載微軟正黑當 AppTC，單靠 loadProofFonts 的
/// fc-match 路徑在部分環境會整頁豆腐字。絕不寫死單一本機路徑。
Future<void> _loadFonts() async {
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
  // 題目裡的 🟢🟡🔴、😭 在無頭環境沒有字型會變豆腐；有 Windows 的 Segoe UI Emoji
  // 就載進來當後備字型（只影響截圖，真機用系統 emoji）。
  final emoji = File('/mnt/c/Windows/Fonts/seguiemj.ttf');
  if (emoji.existsSync()) {
    final bytes = emoji.readAsBytesSync();
    await (FontLoader(_emojiFamily)
          ..addFont(Future.value(ByteData.view(bytes.buffer))))
        .load();
  }
}

const _emojiFamily = 'ProofEmoji';

late ChatQuizCatalog _catalog;

ChatQuizQuestion get _question =>
    _catalog.findQuestion(kOnboardingQuizQuestionId)!;

void main() {
  setUpAll(() async {
    await _loadFonts();
    // 題庫從磁碟讀（不經 rootBundle：大 JSON 走 isolate 解碼，fake async 等不到）。
    _catalog = await loadProductionChatQuizCatalog();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<_Proof> pumpProof(
    WidgetTester tester, {
    Size size = const Size(390, 900),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final rootKey = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatQuizCatalogProvider.overrideWith((ref) async => _catalog),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            fontFamily: 'AppTC',
            fontFamilyFallback: const [_emojiFamily],
            useMaterial3: true,
          ),
          // RepaintBoundary 包住整個 Navigator：「看完整說明」的 sheet 是疊在上面的
          // route，包在 home 裡會拍不到。
          builder: (context, child) => RepaintBoundary(
            key: rootKey,
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                fontFamily: 'AppTC',
                fontFamilyFallback: [_emojiFamily],
              ),
              child: child!,
            ),
          ),
          home: const OnboardingScreen(),
        ),
      ),
    );
    final proof = _Proof(tester, rootKey);
    await proof.settle();
    return proof;
  }

  testWidgets('onboarding 4 頁：她回我了路徑（答對、選目標、看完整說明）', (tester) async {
    final proof = await pumpProof(tester);

    expect(find.text(OnboardingIntentPage.title), findsOneWidget);
    expect(find.text(OnboardingScreen.haveAccountLabel), findsOneWidget);
    await proof.capture('onboarding_page1_intent.png');

    await tester.tap(find.byKey(const ValueKey('onboarding-intent-analyze')));
    await proof.settle();
    expect(find.text(OnboardingQuizTeaserPage.title), findsOneWidget);
    expect(find.text(_question.question), findsOneWidget);
    expect(find.text(OnboardingScreen.skipQuizLabel), findsOneWidget);
    await proof.capture('onboarding_page2_quiz.png');

    final correctId = _question.correctChoice.id;
    await tester.tap(find.byKey(ValueKey('onboarding-quiz-choice-$correctId')));
    await proof.settle();
    expect(find.text('答對了'), findsOneWidget);
    await proof.capture('onboarding_page2_correct_top.png');
    await tester.ensureVisible(
      find.byKey(const ValueKey('onboarding-quiz-explanation')),
    );
    await proof.settle();
    expect(find.text(_question.takeaway), findsOneWidget);
    expect(find.text(_question.correctChoice.feedback), findsOneWidget);
    await proof.capture('onboarding_page2_correct_explained.png');

    await tester.tap(find.text(OnboardingScreen.nextLabel));
    await proof.settle();
    expect(find.text(OnboardingQuestionnairePage.title), findsOneWidget);
    await proof.capture('onboarding_page3_goals.png');

    await tester.tap(find.byKey(const ValueKey('onboarding-goal-softInvite')));
    await proof.settle();
    expect(
      find.byKey(const ValueKey('onboarding-mirror-card')),
      findsOneWidget,
    );
    await proof.capture('onboarding_page3_goals_selected1.png');

    await tester.tap(find.text(OnboardingScreen.nextLabel));
    await proof.settle();
    expect(find.text('登入後，丟一段對話截圖'), findsOneWidget);
    expect(find.text(OnboardingFinishPage.freeQuotaLine), findsOneWidget);
    expect(find.text(OnboardingFinishPage.goalsLine), findsOneWidget);
    expect(
      find.text(
        '${AiPrivacyDisclosure.onboardingLine}。'
        '${OnboardingFinishPage.privacyLinkLabel}',
      ),
      findsOneWidget,
    );
    expect(find.text(OnboardingScreen.finishLabel), findsOneWidget);
    await proof.capture('onboarding_page4_analyze.png');

    await tester.tap(find.byKey(const ValueKey('onboarding-privacy-link')));
    await proof.settle();
    expect(find.text(AiPrivacyDisclosure.description), findsOneWidget);
    await proof.capture('onboarding_page4_privacy_sheet.png');
  });

  testWidgets('onboarding 4 頁：還沒有對象路徑（答錯、直接開始）', (tester) async {
    final proof = await pumpProof(tester);

    await tester.tap(find.byKey(const ValueKey('onboarding-intent-practice')));
    await proof.settle();
    expect(find.text(OnboardingQuizTeaserPage.title), findsOneWidget);

    final wrong = _question.choices.firstWhere(
      (choice) => !_question.isCorrectChoice(choice.id),
    );
    await tester
        .tap(find.byKey(ValueKey('onboarding-quiz-choice-${wrong.id}')));
    await proof.settle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('onboarding-quiz-explanation')),
    );
    await proof.settle();
    expect(find.text('這一題再看一次'), findsOneWidget);
    expect(find.text(wrong.feedback), findsOneWidget);
    await proof.capture('onboarding_page2_wrong_explained.png');

    await tester.tap(find.text(OnboardingScreen.skipQuizLabel));
    await proof.settle();
    expect(find.text('登入後，先抽一位練習夥伴'), findsOneWidget);
    expect(find.text(OnboardingFinishPage.goalsLine), findsNothing);
    await proof.capture('onboarding_page4_practice.png');
  });

  testWidgets('onboarding 4 頁：剛配對路徑（直接開始）', (tester) async {
    final proof = await pumpProof(tester);

    await tester.tap(find.byKey(const ValueKey('onboarding-intent-opener')));
    await proof.settle();
    await tester.tap(find.text(OnboardingScreen.skipQuizLabel));
    await proof.settle();
    expect(find.text('登入後，丟她的自介截圖'), findsOneWidget);
    await proof.capture('onboarding_page4_opener.png');
  });

  // 小螢幕（iPhone SE 375×667）：第 1 頁三張卡＋先逛逛、第 4 頁標題與隱私一行都要排得下
  // （排不下會捲動，不能 overflow）。
  testWidgets('onboarding 4 頁：iPhone SE 寬高', (tester) async {
    final proof = await pumpProof(tester, size: const Size(375, 667));

    expect(find.text(OnboardingIntentPage.title), findsOneWidget);
    await proof.capture('onboarding_se_page1_intent.png');

    await tester.tap(find.byKey(const ValueKey('onboarding-intent-analyze')));
    await proof.settle();
    await tester.tap(find.text(OnboardingScreen.skipQuizLabel));
    await proof.settle();
    expect(find.text('登入後，丟一段對話截圖'), findsOneWidget);
    await proof.capture('onboarding_se_page4_analyze.png');
  });
}

class _Proof {
  _Proof(this.tester, this.rootKey);

  final WidgetTester tester;
  final GlobalKey rootKey;

  Future<void> settle() async {
    await tester.pumpAndSettle();
    // 讓 Sydney PNG 在真 async 裡完成 decode，否則截圖是空框。
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pump();
  }

  Future<void> capture(String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(rootKey),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 3.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      (File(outPath(name))..createSync(recursive: true))
          .writeAsBytesSync(data!.buffer.asUint8List());
    });
  }
}
