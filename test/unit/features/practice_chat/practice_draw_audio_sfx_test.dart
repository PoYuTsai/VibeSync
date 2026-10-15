import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_audio_sfx.dart';
import 'package:vibesync/features/practice_chat/presentation/widgets/practice_draw_sfx.dart';

/// Batch 4.7B 真音效實裝的安全網：真實 [AudioPlayersPracticeDrawSfx] 在 headless／
/// 測試環境（無 audio platform channel）必須可建立、可呼叫各方法皆不丟例外、也不留
/// 未監聽的 async 失敗。真機才會真的發聲；測試一律靜默（不真的播放）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('揭曉音檔（bed v6＋收卡音＋咻聲 v2）', () {
    test('reveal bed 音檔實際 bundle 在 assets（避免 runtime 找不到 asset）', () {
      final bed =
          File('assets/audio/practice_draw/practice_draw_reveal_bed_v6.m4a');
      expect(bed.existsSync(), isTrue,
          reason: 'reveal bed m4a 必須存在於 assets/audio/practice_draw/');
      // 非空（真音檔，不是 0-byte 佔位）；3.3 s AAC 應有數十 KB。
      expect(bed.lengthSync(), greaterThan(10000));
    });

    test('reveal bed 鎖定 v6（N／R／SR 同一條，翻牌紙聲混在 1.35 s）；v4／v5 已移除', () {
      final bed =
          File('assets/audio/practice_draw/practice_draw_reveal_bed_v6.m4a');

      expect(
        sha256.convert(bed.readAsBytesSync()).toString(),
        'f49e9de1c45c432c606b6b71ce939c1e9044184754dc4026ba6ccef00ebf8b72',
      );
      for (final old in [
        'practice_draw_reveal_bed.mp3',
        'practice_draw_reveal_bed_v5.m4a',
      ]) {
        expect(
          File('assets/audio/practice_draw/$old').existsSync(),
          isFalse,
          reason: '$old 已由 v6 取代，不要兩份 bed 並存',
        );
      }
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

    test('收卡音 bundle 並鎖定 master', () {
      final archive =
          File('assets/audio/practice_draw/practice_draw_archive_v3.m4a');
      expect(archive.existsSync(), isTrue,
          reason: '收卡音 m4a 必須存在於 assets/audio/practice_draw/');
      expect(
        sha256.convert(archive.readAsBytesSync()).toString(),
        '4a1b490e8b1c1950d4bad19bdc06194270e263c1655eec796063c2bb9fcba23e',
      );
    });

    test('翻牌紙聲已混進 bed、舊 reveal chime 已退役：檔案都不再 bundle', () {
      for (final old in [
        'practice_draw_flip_snap_1.wav',
        'practice_draw_flip_snap_2.wav',
        'practice_draw_flip_snap_3.wav',
        'practice_draw_reveal_chime.wav',
      ]) {
        expect(
          File('assets/audio/practice_draw/$old').existsSync(),
          isFalse,
          reason: '$old 已沒有呼叫點',
        );
      }
    });
  });

  group('AudioContext（尊重靜音鍵、不打斷背景音樂）', () {
    test('iOS 用 ambient，不明確加 mixWithOthers（避免被拒而退回 playback）', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      try {
        final context = buildPracticeDrawAudioContext();
        expect(context.iOS.category, AVAudioSessionCategory.ambient);
        expect(context.iOS.options, isEmpty);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    test('Android 沿用原本的通用旗標，行為不變', () {
      final context = buildPracticeDrawAudioContext();
      expect(
        context.android,
        AudioContextConfig(
          respectSilence: true,
          focus: AudioContextConfigFocus.mixWithOthers,
        ).buildAndroid(),
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
        sfx.playRevealBed();
        sfx.playArchive();
        sfx.stopRevealBed();
        sfx.stopWaitingLoop();
      }, returnsNormally);

      // 讓 audioplayers 的 create／play future 在測試 zone 內 reject 並被吞掉，
      // 確認沒有 unhandled async error 冒出來污染測試。
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('stopWhoosh：未播放／播放後／重複停皆靜默不丟', () async {
      final sfx = AudioPlayersPracticeDrawSfx();

      expect(() {
        sfx.stopWhoosh(); // 從未播過咻聲 → no-op
        sfx.playWhoosh();
        sfx.stopWhoosh(); // 抽牌失敗／離開畫面：停掉尾巴
        sfx.stopWhoosh(); // 重複停 → no-op
        sfx.playWhoosh(); // 停過之後再抽仍可播
      }, returnsNormally);

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

    test('playArchive：預載前後、連續多次（從頭重起）皆不丟', () async {
      final sfx = AudioPlayersPracticeDrawSfx();

      expect(() {
        sfx.playArchive(); // 沒預載也安全：會先預載
        sfx.preloadReveal();
        for (var i = 0; i < 3; i++) {
          sfx.playArchive(); // 連續收卡：每次從頭重起
        }
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

  // 「沒有真的出聲就直接停、不啟動淡出計時器」由圖鑑頁的 widget 測試守住：它們用真實音效
  // 實作，若 headless 也啟動淡出，會因為「還有計時器沒跑完」而失敗。
  group('咻聲停止：淡出，不一刀切', () {
    test('fadeOutThenStop：音量分步線性降到 0，最後停一次', () async {
      final volumes = <double>[];
      var stops = 0;
      await fadeOutThenStop(
        from: 0.2,
        duration: const Duration(milliseconds: 20),
        steps: 4,
        stillWanted: () => true,
        setVolume: volumes.add,
        stop: () => stops++,
      );

      expect(volumes, [
        closeTo(0.15, 1e-9),
        closeTo(0.10, 1e-9),
        closeTo(0.05, 1e-9),
        closeTo(0.0, 1e-9),
      ]);
      expect(stops, 1);
    });

    test('fadeOutThenStop：途中又開始新的一抽就收手，不再動音量也不停', () async {
      final volumes = <double>[];
      var stops = 0;
      await fadeOutThenStop(
        from: 0.2,
        duration: const Duration(milliseconds: 20),
        steps: 4,
        stillWanted: () => volumes.length < 2, // 第 3 步前開始新的一抽
        setVolume: volumes.add,
        stop: () => stops++,
      );

      expect(volumes, hasLength(2));
      expect(stops, 0);
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
        sfx.playRevealBed();
        sfx.playArchive();
        sfx.stopRevealBed();
      }, returnsNormally);

      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
  });
}
