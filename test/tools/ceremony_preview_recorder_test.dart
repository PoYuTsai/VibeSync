// Gate-2 preview 錄製器（opt-in 工具，非回歸測試）。
//
// 設定 RECORD_CEREMONY=1 才會跑；平常 `flutter test` 全量會 skip，不寫檔不拖慢。
//   RECORD_CEREMONY=1 flutter test test/tools/ceremony_preview_recorder_test.dart
// 驅動真實 PracticeChatScreen 的揭曉儀式，從 _reveal t=0 起，以固定步長 pump、
// 逐幀 RenderRepaintBoundary.toImage 截圖到 scratchpad/cardrep/frames/，
// 之後由 ffmpeg 組 mp4 + mux master audio + 與參考片 side-by-side。
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
import 'package:vibesync/features/practice_chat/domain/entities/practice_session.dart';
import 'package:vibesync/features/practice_chat/presentation/screens/practice_chat_screen.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_sfx.dart';

final _outDir = '${Directory.current.path}/build/card_draw_preview/frames';

// 24fps × 10.0s = 240 frames，對齊參考片（音檔.mp4 720×1280 24fps 10.000s）。
const int _fps = 24;
const int _frameCount = 240;
const double _dpr = 2.0; // 390×844 → 780×1688（偶數，ffmpeg 友善）

// Windows 內建繁中字型 → 預覽影片不出現 tofu（測試環境無 CJK 字型）。
const _cjkFontCandidates = <String>[
  'C:/Windows/Fonts/NotoSansTC-VF.ttf',
  'C:/Windows/Fonts/msjh.ttc',
  '/mnt/c/Windows/Fonts/NotoSansTC-VF.ttf',
];
const _materialIconsFontCandidates = <String>[
  'build/unit_test_assets/fonts/MaterialIcons-Regular.otf',
  'D:/tools/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
];

class _UnusedBox extends Fake implements Box<PracticeSession> {}

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
  }) =>
      _handler();
  @override
  Future<PracticeChatReply> sendMessage({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
  }) =>
      throw UnimplementedError();
  @override
  Future<PracticeDebrief> requestDebrief({
    required String sessionId,
    required PracticeProfileDto profile,
    required List<PracticeTurnDto> turns,
    int roundIndex = 1,
    String? visiblePracticeThreadId,
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

  testWidgets('record ceremony reveal → frames', (tester) async {
    final captureKey = GlobalKey();
    final girl = practiceGirlProfiles.firstWhere(
      (g) => g.nameId == 'emily',
      orElse: () => practiceGirlProfiles[2],
    );

    // 載入繁中字型，讓預覽影片文字正常顯示（否則 test 環境 CJK → tofu）。
    await _loadFirstAvailableFont('NotoTC', _cjkFontCandidates);
    await _loadFirstAvailableFont(
      'MaterialIcons',
      _materialIconsFontCandidates,
    );

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final api = _DrawApi(() async => _drawResultFor(girl));

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
        ],
        child: MaterialApp(
          theme: ThemeData(fontFamily: 'NotoTC'),
          home: RepaintBoundary(
            key: captureKey,
            child: const PracticeChatScreen(),
          ),
        ),
      ),
    );

    // 嘗試預載真實照片（測試環境 asset 可載則前面卡顯真人；不可載則 fallback 初始字）。
    final ctx = tester.element(find.byType(PracticeChatScreen));
    await tester.runAsync(() async {
      try {
        await precacheImage(AssetImage(girl.photoAssetPath), ctx);
      } catch (_) {}
    });

    // 抽牌 → drawing → 立即完成 → revealing（_reveal.forward(from:0)）。
    await tester.tap(find.byKey(const ValueKey('practice-draw-cta')));
    await tester.pump(); // drawing
    await tester.pump(const Duration(milliseconds: 50)); // 入場推進
    await tester.pump(); // draw 完成 → 進 revealing（value≈0）

    final dir = Directory(_outDir);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);

    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    const step = Duration(microseconds: 1000000 ~/ _fps);

    for (var i = 0; i < _frameCount; i++) {
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: _dpr);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final bytes = data!.buffer.asUint8List();
        File('$_outDir/frame_${i.toString().padLeft(4, '0')}.png')
            .writeAsBytesSync(Uint8List.fromList(bytes));
        image.dispose();
      });
      await tester.pump(step);
    }

    final n = dir.listSync().whereType<File>().length;
    expect(n, _frameCount, reason: 'should record all frames');
    // ignore: avoid_print
    print('RECORDED $n frames → $_outDir');
  }, skip: !record);
}
