import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_audio_sfx.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_sfx.dart';

/// Batch 4.7B 真音效實裝的安全網：真實 [AudioPlayersPracticeDrawSfx] 在 headless／
/// 測試環境（無 audio platform channel）必須可建立、可呼叫各方法皆不丟例外、也不留
/// 未監聽的 async 失敗。真機才會真的發聲；測試一律靜默（不真的播放）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('揭曉音檔 v4（bed＋咻聲 v2）', () {
    test('reveal bed 音檔實際 bundle 在 assets（避免 runtime 找不到 asset）', () {
      final bed =
          File('assets/audio/practice_draw/practice_draw_reveal_bed.mp3');
      expect(bed.existsSync(), isTrue,
          reason: 'reveal bed mp3 必須存在於 assets/audio/practice_draw/');
      // 非空（真音檔，不是 0-byte 佔位）；~10s mp3 應有數十 KB 以上。
      expect(bed.lengthSync(), greaterThan(10000));
    });

    test('reveal bed 鎖定 v4 master（F2 提前 0.37 s 對齊畫面＋補洞；避免誤換回 F2）', () {
      final bed =
          File('assets/audio/practice_draw/practice_draw_reveal_bed.mp3');

      expect(
        sha256.convert(bed.readAsBytesSync()).toString(),
        'f211ee0f1755b072ca3b0c27f665bc53b035e5602c13682c6d70630e71b11c07',
      );
    });

    test('咻聲 v2 改成 m4a（含等待尾巴）並鎖定 master；舊 wav 已移除', () {
      final whoosh =
          File('assets/audio/practice_draw/practice_draw_whoosh.m4a');
      expect(whoosh.existsSync(), isTrue,
          reason: '咻聲 m4a 必須存在於 assets/audio/practice_draw/');
      expect(
        sha256.convert(whoosh.readAsBytesSync()).toString(),
        '15e973f3620efa4f8eaf4f008a809a4d4d9e60d7d9e7bfdd79e585db3064e3aa',
      );
      expect(
        File('assets/audio/practice_draw/practice_draw_whoosh.wav')
            .existsSync(),
        isFalse,
        reason: '舊咻聲 wav 已由 m4a 取代，不要兩份並存',
      );
    });
  });

  group('AudioPlayersPracticeDrawSfx（headless 安全）', () {
    test('可建立，不丟例外', () {
      expect(AudioPlayersPracticeDrawSfx.new, returnsNormally);
    });

    test('七個呼叫點在無 platform 下皆靜默不丟', () async {
      final sfx = AudioPlayersPracticeDrawSfx();

      expect(() {
        sfx.playWhoosh();
        sfx.preloadReveal();
        sfx.playWaitingLoop();
        sfx.playRevealChime();
        sfx.playRevealBed();
        sfx.stopRevealBed();
        sfx.stopWaitingLoop();
      }, returnsNormally);

      // 讓 audioplayers 的 create／play future 在測試 zone 內 reject 並被吞掉，
      // 確認沒有 unhandled async error 冒出來污染測試。
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('waiting loop 已退役：start／stop 相容 API 固定 no-op 不丟', () async {
      final sfx = AudioPlayersPracticeDrawSfx();

      expect(() {
        sfx.stopWaitingLoop(); // 從未啟動 loop → no-op
        sfx.playWaitingLoop();
        sfx.stopWaitingLoop();
        sfx.stopWaitingLoop(); // 重複停 → no-op
      }, returnsNormally);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('stopRevealBed idempotent：未播放／重複呼叫＋重起皆 no-op 不丟', () async {
      final sfx = AudioPlayersPracticeDrawSfx();

      expect(() {
        sfx.stopRevealBed(); // 從未起 bed → no-op
        sfx.playRevealBed();
        sfx.playRevealBed(); // 重抽：stop-then-play 重起，不重疊
        sfx.stopRevealBed();
        sfx.stopRevealBed(); // 重複停 → no-op
      }, returnsNormally);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('preloadReveal：重複預載、預載後起播、停止與重起皆不丟', () async {
      final sfx = AudioPlayersPracticeDrawSfx();

      expect(() {
        sfx.preloadReveal();
        sfx.preloadReveal(); // 預載中再呼叫 → 共用同一次預載
        sfx.playRevealBed();
        sfx.stopRevealBed(); // 預載完成前就停 → 不起播
        sfx.playRevealBed(); // 換一位：從頭重起
      }, returnsNormally);

      // 預載在無 platform 下失敗並被吞掉；之後再預載、再播仍安全（會重試）。
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(() {
        sfx.preloadReveal();
        sfx.playRevealBed();
        sfx.stopRevealBed();
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
        sfx.preloadReveal();
        sfx.playWaitingLoop();
        sfx.stopWaitingLoop();
        sfx.playRevealChime();
        sfx.playRevealBed();
        sfx.stopRevealBed();
      }, returnsNormally);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });
}
