// 練習室泡泡改前改後截圖（PR #87 第一步：先分析、先出圖）。
//
// 同一支測試在不同工作區狀態各跑一次，輸出資料夾只由 --dart-define 決定，
// 畫面本身不帶任何改前／改後參數（DESIGN.md §10：先讓 Eric 看過圖才 commit）：
//
//   flutter test test/visual_proof/practice_chat_bubble_proof_test.dart \
//     --dart-define=PRACTICE_BUBBLE_STAGE=before
//
// 三段合成場景：
// - A 進行中的對話：她分則（換行拆顆）、我的短句「好」與換行長句、時間與已讀、
//   「我 →（已讀）→ 我」、最後一則逐顆跳出，再接她的輸入中三點。
// - B Game 模式：開頭教練卡、「她已封鎖你」、結尾拆解卡。
// - C 練習回顧：有 profileId 的場次，與沒有 profileId 的舊場次（也沒有時間）。
//
// 用 tester.view 設定 390／320 邏輯寬：MediaQuery 與版面同寬（#86 踩過
// pumpAndCapture 只改 surface、MediaQuery 仍是 800 寬的坑），而且截圖邊界包住
// 整個 MaterialApp，練習回顧這種 push 出來的頁面也拍得到。
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart' show Box;

import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_game_intro_store.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_learning_mode.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_message.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_chat_screen.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';
import 'package:vibesync/features/subscription/domain/services/subscription_tier_helper.dart';

import 'proof_support.dart';

const _stage = String.fromEnvironment(
  'PRACTICE_BUBBLE_STAGE',
  defaultValue: 'current',
);

String _out(String name) => outPath('practice_chat_bubble/$_stage/$name');

class _UnusedPracticeSessionBox extends Fake implements Box<PracticeSession> {}

class _FakePracticeSessionRepository extends PracticeSessionRepository {
  _FakePracticeSessionRepository() : super(_UnusedPracticeSessionBox());

  @override
  List<PracticeSession> recentSessions() => const [];

  @override
  Future<void> save(PracticeSession session) async {}
}

PracticeChatApiService _unusedApi() => PracticeChatApiService(
      invoker: (name, {required body}) async =>
          throw UnimplementedError('泡泡截圖不應打 practice-chat'),
    );

class _SeededPracticeChatController extends PracticeChatController {
  _SeededPracticeChatController(PracticeChatState seed)
      : super(
          api: _unusedApi(),
          repository: _FakePracticeSessionRepository(),
          sessionId: seed.sessionId,
          createdAt: seed.createdAt,
        ) {
    state = seed;
  }
}

class _SeededSubscriptionNotifier extends SubscriptionNotifier {
  _SeededSubscriptionNotifier(SubscriptionState seed) {
    state = seed;
  }
}

/// Game 教學卡已看過：不然進 Game 局會先彈教學 sheet 蓋住畫面。
class _SeenGameIntroStore implements PracticeGameIntroStore {
  @override
  Future<bool> isSeen() async => true;

  @override
  Future<void> markSeen() async {}

  @override
  Future<void> reset() async {}
}

final _mina = practiceGirlProfiles.firstWhere(
  (profile) => profile.profileId == 'practice_girl_067',
);
final _mia = practiceGirlProfiles.firstWhere(
  (profile) => profile.profileId == 'practice_girl_004',
);

DateTime _at(int hour, int minute) => DateTime(2026, 10, 4, hour, minute);

/// A：進行中的對話，最後一則（我的三段）逐顆跳出，接著她輸入中。
PracticeChatState _ongoingSeed() => PracticeChatState(
      sessionId: 'bubble-proof-ongoing',
      createdAt: _at(20, 30),
      girl: _mina,
      personaId: _mina.personaId,
      personaLabel: '幽默吐槽型',
      difficulty: 'normal',
      difficultyLabel: '一般',
      aiReplyCount: 3,
      isSending: true,
      messages: [
        PracticeMessage(
          role: 'user',
          text: '週末有出去走走嗎？',
          sentAt: _at(20, 31),
        ),
        PracticeMessage(
          role: 'ai',
          text: '有啊，跑去陽明山\n結果整片起霧什麼都沒看到，最後只好去吃一碗超貴的泡麵',
          sentAt: _at(20, 32),
        ),
        PracticeMessage(
          role: 'user',
          text: '哈哈哈 那碗泡麵最好是比山上的風景還好看，下次出門前記得先看一下天氣預報',
          sentAt: _at(20, 33),
        ),
        PracticeMessage(
          role: 'ai',
          text: '普通啦\n下次換你推薦好了',
          sentAt: _at(20, 34),
        ),
        PracticeMessage(role: 'user', text: '好', sentAt: _at(20, 34)),
        // 她已讀不回：不畫成泡泡，疊在上一則的時間上方。
        PracticeMessage(role: 'ai', text: '（已讀）', sentAt: _at(20, 35)),
        PracticeMessage(
          role: 'user',
          text: '我知道一家巷子裡的牛肉麵\n老闆會記得你上次點什麼\n這週末要不要一起去？',
          sentAt: _at(20, 37),
        ),
      ],
    );

/// B：Game 局被封鎖後的拆解畫面（教練卡在頂、封鎖提示、拆解卡在底）。
PracticeChatState _gameSeed() => PracticeChatState(
      sessionId: 'bubble-proof-game',
      createdAt: _at(21, 5),
      girl: _mia,
      personaId: _mia.personaId,
      personaLabel: '高冷慢熱型',
      difficulty: 'challenge',
      difficultyLabel: '挑戰',
      learningMode: PracticeLearningMode.game,
      temperatureScore: 12,
      aiReplyCount: 4,
      partnerStatus: 'blocked',
      messages: [
        PracticeMessage(role: 'user', text: '在幹嘛', sentAt: _at(21, 6)),
        PracticeMessage(
          role: 'ai',
          text: '剛下班\n在等公車',
          sentAt: _at(21, 6),
        ),
        PracticeMessage(
          role: 'user',
          text: '妳住哪一區啊 我開車去接妳',
          sentAt: _at(21, 7),
        ),
        PracticeMessage(role: 'ai', text: '不用了 謝謝', sentAt: _at(21, 7)),
        PracticeMessage(
          role: 'user',
          text: '幹嘛這麼冷淡 給個 LINE 嘛',
          sentAt: _at(21, 8),
        ),
        PracticeMessage(
          role: 'ai',
          text: kPracticeBlockedReplyText,
          sentAt: _at(21, 8),
        ),
      ],
      debrief: const PracticeDebrief(
        summary: '還沒建立任何舒服感就要住址和 LINE，她只能先保護自己。',
        strengths: ['開場簡短，沒有長篇自我介紹'],
        watchouts: ['第二句就問住哪、說要去接，壓迫感直接拉滿', '她回「不用了」之後又追要 LINE'],
        suggestedLine: '剛下班還要等公車也太累，今天最想吐槽的是哪件事？',
        vibe: '冷淡',
        dateChance: '低',
        dateChanceReason: '她已經封鎖，這局的信任感是負的。',
        nextInviteMove: '先讓她願意多回兩句，再談見面。',
        gameBreakdown: PracticeGameBreakdown(
          phaseReached: '開場',
          missedVariable: '舒服感',
          failureState: '越界被封鎖',
          nextFirstLine: '下班等車的時間最適合放空，妳都聽什麼？',
          inviteDirection: '先聊她的下班日常，熟一點再提一起吃飯',
        ),
      ),
    );

/// C：練習回顧兩場：有 profileId 的新場次，與沒有 profileId、也沒有時間的舊場次。
final _reviewWithProfile = PracticeSession(
  id: 'bubble-proof-review-profile',
  createdAt: _at(19, 40),
  aiReplyCount: 2,
  profileId: 'practice_girl_067',
  closed: true,
  messages: [
    PracticeMessage(role: 'user', text: '妳上次說的展還在嗎？', sentAt: _at(19, 41)),
    PracticeMessage(
      role: 'ai',
      text: '還在！到月底\n不過假日人超多，要排很久',
      sentAt: _at(19, 42),
    ),
    PracticeMessage(role: 'user', text: '那平日晚上去？', sentAt: _at(19, 43)),
    PracticeMessage(role: 'ai', text: '可以啊 週四我比較有空', sentAt: _at(19, 44)),
  ],
);

final _reviewLegacy = PracticeSession(
  id: 'bubble-proof-review-legacy',
  createdAt: DateTime(2026, 7, 2, 22, 15),
  aiReplyCount: 2,
  closed: true,
  messages: const [
    PracticeMessage(role: 'user', text: '最近有看什麼好看的劇嗎'),
    PracticeMessage(role: 'ai', text: '在追一部韓劇\n每集結尾都在吊胃口'),
    PracticeMessage(role: 'user', text: '哪一部？我也想找新的來追'),
    PracticeMessage(role: 'ai', text: '你先猜猜看'),
  ],
);

List<Override> _overrides(PracticeChatState seed) => [
      practiceChatControllerProvider.overrideWith(
        (ref) => _SeededPracticeChatController(seed),
      ),
      subscriptionProvider.overrideWith(
        (ref) => _SeededSubscriptionNotifier(
          const SubscriptionState(
            tier: SubscriptionTierHelper.starter,
            monthlyLimit: 100,
            dailyLimit: 30,
          ),
        ),
      ),
      practiceGameIntroStoreProvider.overrideWithValue(_SeenGameIntroStore()),
      recentPracticeSessionsProvider
          .overrideWithValue([_reviewWithProfile, _reviewLegacy]),
    ];

/// 照片是 asset 圖，要真的等解碼完才拍，不然頭像是空的。
Future<void> _waitForImages(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 700)),
  );
  await tester.pump();
}

/// 把對話面板捲到最底（真機上新訊息進來時也會自動捲到底）。
Future<void> _scrollChatToBottom(WidgetTester tester) async {
  final scrollable = find.descendant(
    of: find.byKey(const ValueKey('practice-chat-workspace')),
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable.first).position;
  position.jumpTo(position.maxScrollExtent);
  await tester.pump();
}

Future<void> _capture(
  WidgetTester tester, {
  required PracticeChatState seed,
  required String name,
  Size size = kPhone,
  Duration settle = const Duration(milliseconds: 1500),
  Future<void> Function(WidgetTester tester)? beforeCapture,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final rootKey = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: rootKey,
      child: ProviderScope(
        overrides: _overrides(seed),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'AppTC', useMaterial3: true),
          builder: (context, child) => DefaultTextStyle.merge(
            style: const TextStyle(fontFamily: 'AppTC'),
            child: child!,
          ),
          home: const PracticeChatScreen(),
        ),
      ),
    ),
  );
  // 只做固定時間的 pump：輸入中三點會一直動，pumpAndSettle 永遠等不完。
  // 逐顆跳出每秒一顆，settle 要大於（段數 − 1）秒。
  await tester.pump(settle);
  await _waitForImages(tester);
  if (beforeCapture != null) await beforeCapture(tester);

  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(rootKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 3);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    (File(_out(name))..createSync(recursive: true))
        .writeAsBytesSync(data!.buffer.asUint8List());
  });
}

/// 從「最近練習」打開指定日期的那場回顧。
Future<void> Function(WidgetTester tester) _openReview(String dateLabel) =>
    (tester) async {
      await tester.tap(find.byIcon(Icons.history));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await tester.tap(find.text(dateLabel));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      await _waitForImages(tester);
    };

void main() {
  setUpAll(loadProofFonts);

  testWidgets('A 進行中的對話 390×844（捲到最底）', (tester) async {
    await _capture(
      tester,
      seed: _ongoingSeed(),
      name: 'a_ongoing_390.png',
      settle: const Duration(milliseconds: 2600),
      beforeCapture: _scrollChatToBottom,
    );
  });

  testWidgets('A 進行中的對話 390×844（最上面）', (tester) async {
    await _capture(
      tester,
      seed: _ongoingSeed(),
      name: 'a_ongoing_390_top.png',
      settle: const Duration(milliseconds: 2600),
    );
  });

  testWidgets('A 進行中的對話 320×568（最小支援寬）', (tester) async {
    await _capture(
      tester,
      seed: _ongoingSeed(),
      name: 'a_ongoing_320.png',
      size: const Size(320, 568),
      settle: const Duration(milliseconds: 2600),
    );
  });

  testWidgets('B Game 模式：教練卡與開頭', (tester) async {
    await _capture(tester, seed: _gameSeed(), name: 'b_game_top.png');
  });

  testWidgets('B Game 模式：封鎖提示與拆解卡', (tester) async {
    await _capture(
      tester,
      seed: _gameSeed(),
      name: 'b_game_bottom.png',
      beforeCapture: _scrollChatToBottom,
    );
  });

  testWidgets('C 練習回顧：有 profileId', (tester) async {
    await _capture(
      tester,
      seed: _ongoingSeed().copyWith(isSending: false),
      name: 'c_review_profile.png',
      beforeCapture: _openReview('10/4 19:40'),
    );
  });

  testWidgets('C 練習回顧：舊場次沒有 profileId', (tester) async {
    await _capture(
      tester,
      seed: _ongoingSeed().copyWith(isSending: false),
      name: 'c_review_legacy.png',
      beforeCapture: _openReview('7/2 22:15'),
    );
  });
}
