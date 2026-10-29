// Gate-2 preview 錄製器（opt-in 工具，非回歸測試）。
//
// 設定 RECORD_CEREMONY=1 才會跑；平常 `flutter test` 全量會 skip，不寫檔不拖慢。
//   RECORD_CEREMONY=1 flutter test test/tools/ceremony_preview_recorder_test.dart
// 只錄某個稀有度：再加 RECORD_RARITY=n|r|sr（預設三個都錄）。
// 預設錄新角色（NEW、收集數字落位 +1）；RECORD_DUPLICATE=1 改錄重複角色（「已收藏」）。
// RECORD_WAIT_MS=1500 讓 server 晚 1.5 s 才回來，錄得到等待姿態與等待心跳（V3.1 §5.15）；
// 錄影長度與點擊收卡的那一幀跟著往後挪。
// RECORD_FPS=60 改用 60 fps 錄（預設 24），給閃光檢查 tools/practice-reveal-flash-check 用：
// 24 fps 會錯過兩幀之間最亮與最暗的那一下。
// 掛真實的角色圖鑑頁（儀式蓋在整頁最上層、底下是模糊的圖鑑），從按下翻牌起以固定
// 步長 pump、逐幀 RenderRepaintBoundary.toImage 截圖到 build/card_draw_preview/<稀有度>/，
// 之後由 ffmpeg 組 mp4（可再 mux 配樂、和參考片並排）。
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart' show Box;
import 'package:vibesync/features/practice_chat/data/providers/practice_chat_providers.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_draw_draft_store.dart';
import 'package:vibesync/features/practice_chat/data/repositories/practice_session_repository.dart';
import 'package:vibesync/features/practice_chat/data/services/practice_chat_api_service.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_catalog.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_girl_profile.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_hint.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_learning_mode.dart';
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_collection_screen.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_card_material.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_ceremony.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_sfx.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_reveal_card.dart';
import 'package:vibesync/features/subscription/data/providers/subscription_providers.dart';

String _outDir(String rarity) =>
    '${Directory.current.path}/build/card_draw_preview/$rarity';

// V3（單次翻牌＋停住＋收卡）：24fps × 5.25s = 126 frames。從按下翻牌起錄：
// 卡背入場 0.5s → 揭曉 2.7s → 停住約 1.0s → 第 [_tapFrame] 幀點擊收卡 → 收卡 0.7s → 尾巴。
// 幀數以 24 fps 計；RECORD_FPS 改 fps 時照比例換算。
const int _fps = 24;
const int _frameCount = 126;
const int _tapFrame = 101;
const double _dpr = 2.0; // 390×844 → 780×1688（偶數，ffmpeg 友善）

// Windows 內建繁中字型 → 預覽影片不出現 tofu（測試環境無 CJK 字型）。
const _cjkFontCandidates = <String>[
  'C:/Windows/Fonts/NotoSansTC-VF.ttf',
  'C:/Windows/Fonts/msjh.ttc',
  '/mnt/c/Windows/Fonts/NotoSansTC-VF.ttf',
  // Linux（CI 與雲端環境）：系統的文泉驛優先（實測逐幀不掉字），沒有再用 CI 裝的
  // Noto CJK 單檔。
  '/usr/share/fonts/truetype/wqy/wqy-zenhei.ttc',
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
];
const _materialIconsFontCandidates = <String>[
  'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
  'D:/tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
];

class _UnusedBox extends Fake implements Box<PracticeSession> {}

class _SeededCollection extends PracticeCollectionNotifier {
  _SeededCollection(this._ids);

  final Set<String> _ids;

  @override
  Future<Set<String>> build() async => _ids;
}

class _SeededSubscription extends SubscriptionNotifier {
  _SeededSubscription() {
    state = const SubscriptionState();
  }
}

class _MemoryRepo extends PracticeSessionRepository {
  _MemoryRepo() : super(_UnusedBox());
  final Map<String, PracticeSession> _s = {};
  @override
  Future<void> save(PracticeSession session) async => _s[session.id] = session;
  @override
  PracticeSession? getById(String id) => _s[id];
  @override
  List<PracticeSession> recentSessions() => const [];
  @override
  Future<void> delete(String id) async => _s.remove(id);
}

class _DrawApi extends PracticeChatApiService {
  _DrawApi(this._handler);
  final Future<PracticeDrawResult> Function() _handler;
  @override
  Future<PracticeDrawResult> drawProfile({
    required String requestId,
    String? currentProfileId,
    String? visiblePracticeThreadId,
    bool srTicket = false,
  }) =>
      _handler();
  @override
  Future<PracticeChatReply> sendMessage({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    PracticeLearningMode practiceMode = PracticeLearningMode.standard,
    int? temperatureScore,
    int? familiarityScore,
    PracticeHintReplyType? appliedHintType,
    String? appliedHintText,
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
  }) =>
      throw UnimplementedError();
  @override
  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    PracticeLearningMode practiceMode = PracticeLearningMode.standard,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
    String? memorySummary,
    PracticePartnerState? continuationPartnerState,
    List<PracticeAppliedHintTurnDto> appliedHintTurns = const [],
  }) =>
      throw UnimplementedError();
}

PracticeDrawResult _drawResultFor(PracticeGirlProfile g) => PracticeDrawResult(
      profile: PracticeDrawnProfile(
        profileId: g.profileId,
        nameId: g.nameId,
        professionId: g.professionId,
        photoId: g.photoId,
        personaId: g.personaId,
      ),
      draw: const PracticeDrawReceipt(
        costMessages: 0,
        freeAllowance: 1,
        freeUsed: 1,
        freeRemaining: 0,
        extraCostMessages: 5,
        nextResetAt: '2999-01-01T04:00:00.000Z',
      ),
      usage: const PracticeDrawUsage(
        monthlyUsed: 0,
        monthlyLimit: 30,
        dailyUsed: 0,
        dailyLimit: 30,
      ),
    );

Future<void> _loadFirstAvailableFont(
  String family,
  List<String> candidates,
) async {
  for (final fontPath in candidates) {
    final font = File(fontPath);
    if (!font.existsSync()) continue;
    final fontBytes = font.readAsBytesSync();
    await (FontLoader(family)
          ..addFont(Future.value(ByteData.view(fontBytes.buffer))))
        .load();
    return;
  }
}

void main() {
  final record = Platform.environment['RECORD_CEREMONY'] == '1';
  final only = Platform.environment['RECORD_RARITY'];
  final duplicate = Platform.environment['RECORD_DUPLICATE'] == '1';
  final waitMs =
      int.tryParse(Platform.environment['RECORD_WAIT_MS'] ?? '') ?? 0;
  final fps = int.tryParse(Platform.environment['RECORD_FPS'] ?? '') ?? _fps;
  final frameCount = (_frameCount * fps / _fps).round();
  final tapFrame = (_tapFrame * fps / _fps).round();
  final extraFrames = (waitMs * fps / 1000).round();

  // 錨點與 catalog 指定同步：001=N、010=R、004=SR（見 practice_persona.ts）。
  final girls = <String, PracticeGirlProfile>{
    'n': practiceGirlProfiles.first,
    'r': practiceGirlProfiles[9],
    'sr': practiceGirlProfiles[3],
  };

  for (final MapEntry(key: rarity, value: girl) in girls.entries) {
    testWidgets('record ceremony $rarity → frames', (tester) async {
      expect(girl.rarity.label.toLowerCase(), rarity); // 錨點保險
      final captureKey = GlobalKey();

      // 載入繁中字型，讓預覽影片文字正常顯示（否則 test 環境 CJK → tofu）。
      await _loadFirstAvailableFont('NotoTC', _cjkFontCandidates);
      await _loadFirstAvailableFont(
        'MaterialIcons',
        _materialIconsFontCandidates,
      );

      // 用 view 定尺寸（不是 setSurfaceSize）：MediaQuery 才會是 390×844，卡片尺寸與
      // 圖鑑捲動估算才和真機一致。
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final api = _DrawApi(() async {
        if (waitMs > 0) {
          await Future<void>.delayed(Duration(milliseconds: waitMs));
        }
        return _drawResultFor(girl);
      });
      // 圖鑑先解鎖幾張（底下的格子有真照片）。預設錄「新角色」：剛抽到的那位不在裡面，
      // 抽中後才 +1（看得到 NEW 與收集數字落位跳動）；RECORD_DUPLICATE=1 改錄重複角色。
      final unlocked = {
        for (final g in practiceGirlProfiles.take(8))
          if (g.profileId != girl.profileId) g.profileId,
        if (duplicate) girl.profileId,
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            practiceSessionRepositoryProvider.overrideWithValue(_MemoryRepo()),
            practiceDrawDraftStoreProvider
                .overrideWithValue(InMemoryPracticeDrawDraftStore()),
            practiceChatApiServiceProvider.overrideWithValue(api),
            // 測試環境無 audio platform channel → 用 no-op 免 MissingPluginException。
            practiceDrawSfxProvider
                .overrideWithValue(const NoopPracticeDrawSfx()),
            practiceCollectionProvider
                .overrideWith(() => _SeededCollection(unlocked)),
            subscriptionProvider.overrideWith((ref) => _SeededSubscription()),
            subscriptionScreenRefreshProvider.overrideWithValue(() async {}),
          ],
          child: MaterialApp(
            theme: ThemeData(fontFamily: 'NotoTC'),
            home: RepaintBoundary(
              key: captureKey,
              child: const PracticeCollectionScreen(),
            ),
          ),
        ),
      );
      await tester.pump();

      // 預載照片、光效貼圖與卡背素材（測試環境 asset 可載則顯真圖；不可載則 fallback 初始字）。
      // 卡背素材用儀式同一組 provider（解成卡片實際像素寬），儀式拿到的就是這裡解好的快取。
      final ctx = tester.element(find.byType(PracticeCollectionScreen));
      final cardPixelWidth = practiceCeremonyCardPixelWidth(ctx);
      await tester.runAsync(() async {
        for (final provider in <ImageProvider>[
          for (final asset in kPracticeRevealSpriteAssets) AssetImage(asset),
          for (final slot in PracticeCardMaterialSlot.values)
            slot.provider(cardPixelWidth),
          for (final g in practiceGirlProfiles.take(8))
            AssetImage(g.photoAssetPath),
          AssetImage(girl.photoAssetPath),
        ]) {
          try {
            await precacheImage(provider, ctx);
          } catch (_) {}
        }
      });
      await tester.pump();

      final dir = Directory(_outDir(rarity));
      if (dir.existsSync()) dir.deleteSync(recursive: true);
      dir.createSync(recursive: true);

      final boundary = captureKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final step = Duration(microseconds: 1000000 ~/ fps);

      // 按下翻牌：drawing（卡背入場）→ server 立即回來 → 入場走完才開始揭曉。
      unawaited(
        ProviderScope.containerOf(ctx)
            .read(practiceChatControllerProvider.notifier)
            .drawNewPracticeGirl(),
      );
      await tester.pump();

      for (var i = 0; i < frameCount + extraFrames; i++) {
        if (i == tapFrame + extraFrames) {
          // 停住等點擊：點一下收卡，光球飛進那一格。
          await tester.tap(
            find.byKey(const ValueKey('practice-draw-ceremony-continue')),
          );
        }
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: _dpr);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final bytes = data!.buffer.asUint8List();
          File('${dir.path}/frame_${i.toString().padLeft(4, '0')}.png')
              .writeAsBytesSync(Uint8List.fromList(bytes));
          image.dispose();
        });
        await tester.pump(step);
      }
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 250));

      final n = dir.listSync().whereType<File>().length;
      expect(n, frameCount + extraFrames, reason: 'should record all frames');
      // ignore: avoid_print
      print('RECORDED $n frames → ${dir.path}');
    }, skip: !record || (only != null && only != rarity));
  }
}
