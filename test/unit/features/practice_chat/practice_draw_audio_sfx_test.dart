import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_audio_sfx.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_sfx.dart';

/// Batch 4.7B 真音效實裝的安全網：真實 [AudioPlayersPracticeDrawSfx] 在 headless／
/// 測試環境（無 audio platform channel）必須可建立、可呼叫四方法皆不丟例外、也不留
/// 未監聽的 async 失敗。真機才會真的發聲；測試一律靜默（不真的播放）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AudioPlayersPracticeDrawSfx（headless 安全）', () {
    test('可建立，不丟例外', () {
      expect(AudioPlayersPracticeDrawSfx.new, returnsNormally);
    });

    test('四個呼叫點在無 platform 下皆靜默不丟', () async {
      final sfx = AudioPlayersPracticeDrawSfx();

      expect(() {
        sfx.playWhoosh();
        sfx.playWaitingLoop();
        sfx.playRevealChime();
        sfx.stopWaitingLoop();
      }, returnsNormally);

      // 讓 audioplayers 的 create／play future 在測試 zone 內 reject 並被吞掉，
      // 確認沒有 unhandled async error 冒出來污染測試。
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('stopWaitingLoop idempotent：未播放／重複呼叫皆 no-op 不丟', () async {
      final sfx = AudioPlayersPracticeDrawSfx();

      expect(() {
        sfx.stopWaitingLoop(); // 從未啟動 loop → no-op
        sfx.playWaitingLoop();
        sfx.stopWaitingLoop();
        sfx.stopWaitingLoop(); // 重複停 → no-op
      }, returnsNormally);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });

  group('practiceDrawSfxProvider 預設實作', () {
    test('預設已換成真實 AudioPlayers 實作（非 Noop）', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sfx = container.read(practiceDrawSfxProvider);
      expect(sfx, isA<AudioPlayersPracticeDrawSfx>());
      expect(sfx, isNot(isA<NoopPracticeDrawSfx>()));
    });

    test('預設實作可被讀取並驅動，不丟例外', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final sfx = container.read(practiceDrawSfxProvider);
      expect(() {
        sfx.playWhoosh();
        sfx.playWaitingLoop();
        sfx.stopWaitingLoop();
        sfx.playRevealChime();
      }, returnsNormally);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });
}
