import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'practice_draw_sfx.dart';
import 'practice_reveal_timing.dart';

// ── 音量常數（集中於此，方便真機調整）─────────────────────────────────────
// 真機目檢時直接調這三個值即可，不必動播放邏輯。
// 咻聲 v2 母帶到 true peak −1.2 dBTP、bed v4 母帶到 −18 LUFS（v6 是它的片段＋紙聲，響度不變），
// 音量由參考混音反推：
// - 咻聲：手機上比揭曉高潮小 8 dB（舊版反而大 8.5 dB）。調大不要超過約 0.27，
//   高潮至少要比咻聲大 6 dB。
// - bed：翻牌後和舊版（F2 × 0.75）一樣大聲；紙聲已照原本的比例混在檔裡。
// - 收卡音：落點那一聲比揭曉高潮小約 6 dB（比咻聲大一點）。
const double _kWhooshVolume = 0.22;
const double _kRevealBedVolume = 0.74;
const double _kArchiveVolume = 0.42;

// 咻聲停止（抽牌失敗／離開畫面）：正在出聲時 0.5 秒淡出再停，不一刀切，跟畫面遮罩的
// 淡出（約 0.5 秒）同步。20 步，每步 25 ms，音量差很小，聽不出階梯。
const Duration _kWhooshFadeOut = Duration(milliseconds: 500);
const int _kWhooshFadeSteps = 20;

// ── 音檔路徑（相對 AudioCache 預設 prefix `assets/`）────────────────────────
// 咻聲 v2：實心起手，加一段一次性的暖尾巴（C–G 長音，最長 5.5 s）接住等待 server 的空檔。
const String _kWhooshAsset = 'audio/practice_draw/practice_draw_whoosh.m4a';
// bed v6：N／R／SR 同一條（規格 D3）。bed v4 從 4.95 s 剪到 8.25 s（120 ms 淡入、尾段 0.4 s
// 淡出），v4 的高潮落在 V3 單次翻牌（揭曉 1.35 s），翻牌紙聲也直接混在 1.35 s，和音樂同一個
// player、不會各自延遲；在 v4 的 8.5 s 落定重擊之前收掉，停住等點擊時不會突然一聲。
const String _kRevealBedAsset =
    'audio/practice_draw/practice_draw_reveal_bed_v6.m4a';
// 收卡音：0.8 s，0.45 s（光球落進那一格）一聲水晶鈴。
const String _kArchiveAsset =
    'audio/practice_draw/practice_draw_archive_v3.m4a';

// 揭曉配樂停止（點擊收卡／離開畫面）：正在出聲時 0.25 秒淡出再停，跟收卡光球同步。
const Duration _kRevealBedFadeOut = Duration(milliseconds: 250);
const int _kRevealBedFadeSteps = 10;

/// 翻牌音效的全域 AudioContext：尊重靜音鍵、不打斷使用者的背景音樂。
///
/// iOS 直接指定 `ambient`：它本身就會與其他 App 混音、尊重靜音鍵，**不要**再明確加
/// `mixWithOthers`。舊寫法 `AudioContextConfig(respectSilence: true, focus:
/// mixWithOthers)` 是 audioplayers_platform_interface 7.1.1 在 debug 用 assert 擋下的
/// 組合；release 沒有 assert，會把 `ambient＋mixWithOthers` 送給 iOS，被拒時 session
/// 停在 plugin 預設的 `playback`：不理會靜音鍵，還會打斷背景音樂。
/// Android 沿用同一組通用旗標，行為不變。
@visibleForTesting
AudioContext buildPracticeDrawAudioContext() {
  final generic = AudioContextConfig(
    respectSilence: true,
    focus: AudioContextConfigFocus.mixWithOthers,
  );
  return AudioContext(
    android: generic.buildAndroid(),
    iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
  );
}

/// 把音量從 [from] 分 [steps] 步線性降到 0，再呼叫 [stop]。每一步之前問一次 [stillWanted]；
/// 變成 false（例如又開始新的一抽）就收手，不再動音量、也不停。
@visibleForTesting
Future<void> fadeOutThenStop({
  required double from,
  required Duration duration,
  required int steps,
  required bool Function() stillWanted,
  required void Function(double volume) setVolume,
  required void Function() stop,
}) async {
  final step = duration ~/ steps;
  for (var i = 1; i <= steps; i++) {
    await Future<void>.delayed(step);
    if (!stillWanted()) return;
    setVolume(from * (1 - i / steps));
  }
  if (stillWanted()) stop();
}

/// 預載好就歸零重播。等預載與歸零之後各問一次 [stillWanted]；變成 false（例如儀式已經收掉、
/// 又開始新的一抽）就不播。已經開始播的不在這裡管，照常播完。
@visibleForTesting
Future<void> replayIfStillWanted({
  required Future<bool> ready,
  required bool Function() stillWanted,
  required Future<void> Function() rewind,
  required Future<void> Function() play,
}) async {
  if (!await ready || !stillWanted()) return;
  await rewind();
  if (!stillWanted()) return;
  await play();
}

/// 每日翻牌音效的真實實作（Batch 4.7B：把 4.7A 的 [NoopPracticeDrawSfx] 換成會真的
/// 播放的版本）。背後用 `audioplayers`。
///
/// 設計鐵則：
/// - **lazy + guarded**：建構不碰任何 platform channel（不建立 player）；player 在首次
///   播放時才建立。所有 play／stop／context 設定都吞掉同步與 async 例外，因此在 headless
///   ／widget-test 環境（無 audio platform channel）一律靜默、絕不丟例外、絕不留未監聽的
///   create 失敗。真機才會真的發聲。
/// - **獨立 player**：whoosh／揭曉配樂 bed／收卡音各自一個 player，避免互相截斷。
///   whoosh 是一次性（`ReleaseMode.release`）；bed 與收卡音由 [preloadReveal] 先載好
///   （`ReleaseMode.stop`，停止後保留音源），播放時從頭 resume，降低起播延遲。
/// - **咻聲停止**：[stopWhoosh] 在咻聲正在出聲時 0.5 秒淡出再停，還沒出聲就直接停。淡出用
///   Dart 計時器，只有 player 真的在播（真機）才會啟動；headless／widget test 裡 player 從未
///   進入播放狀態，所以不會留下計時器。
/// - **waiting loop 已退役**：build 326 證實等待期 shimmer 是殘留「西西簌簌」來源；
///   [playWaitingLoop]／[stopWaitingLoop] 暫留介面相容，但 production 實作固定 no-op。
/// - **AudioContext**：見 [buildPracticeDrawAudioContext]。iOS 用 `ambient`：尊重靜音鍵、
///   不中斷使用者背景音樂；非必要的浪漫音效在公共場合不擾人。
class AudioPlayersPracticeDrawSfx implements PracticeDrawSfx {
  AudioPlayersPracticeDrawSfx();

  AudioPlayer? _whooshPlayer;
  // 每次 playWhoosh 遞增；淡出途中又開始新的一抽，舊的淡出就收手。
  int _whooshGeneration = 0;
  // 正在淡出的那一輪：同一輪重複 stopWhoosh 不重來，音量才不會跳回去。
  int? _whooshFadingGeneration;
  // 揭曉配樂 bed 與收卡音：都預載成可重播（stop 歸零再 resume），預載邏輯共用。
  final _ReplayablePlayer _bed =
      _ReplayablePlayer(_kRevealBedAsset, _kRevealBedVolume);
  // 每次 playRevealBed 遞增；預載期間被停掉或重起時，只讓最後一次起播。
  int _bedGeneration = 0;
  final _ReplayablePlayer _archive =
      _ReplayablePlayer(_kArchiveAsset, _kArchiveVolume);
  // 每次 playArchive 遞增，新的一抽（playWhoosh）也遞增：還沒起播的那一聲就作廢。
  int _archiveGeneration = 0;

  bool _bedActive = false;

  /// bed 最後一次被設的音量。預載時設成 [_kRevealBedVolume]；收卡淡出會一路降到 0，
  /// 淡出走完再設回來。
  double _bedVolume = _kRevealBedVolume;
  bool _contextConfigured = false;
  bool _contextPending = false;

  /// 播放前設定全域 AudioContext。成功後才記為已設定；失敗（測試／無 platform／被系統
  /// 拒絕）靜默吞掉，下一次播放再試，不會卡在 plugin 預設的 `playback`。
  void _ensureContext() {
    if (_contextConfigured || _contextPending) return;
    _contextPending = true;
    unawaited(() async {
      try {
        await AudioPlayer.global
            .setAudioContext(buildPracticeDrawAudioContext());
        _contextConfigured = true;
      } catch (_) {
        // 音效非關鍵路徑：失敗不丟，留給下一次播放重試。
      } finally {
        _contextPending = false;
      }
    }());
  }

  /// Lazy 建立一個 player 並套用 release mode。
  ///
  /// headless 環境（無 audio platform channel）裡 audioplayers 的內部 `create` 會 reject；
  /// 緊接的 `setReleaseMode()` 內部會 `await` 該建立流程，故由它的 `.catchError` 一併消費
  /// 掉 create 失敗，不會留下未監聽的 async error。
  AudioPlayer _create(ReleaseMode mode) {
    final player = AudioPlayer();
    unawaited(player.setReleaseMode(mode).catchError((Object _) {}));
    return player;
  }

  void _playOneShot(AudioPlayer player, String asset, double volume) {
    try {
      _ensureContext();
      unawaited(
        player
            .play(AssetSource(asset), volume: volume)
            .catchError((Object _) {}),
      );
    } catch (_) {
      // 音效非關鍵路徑：任何同步例外都靜默。
    }
  }

  @override
  void playWhoosh() {
    _whooshGeneration++; // 新的一抽：取消進行中的淡出（play 會把音量設回來）。
    _archiveGeneration++; // 上一張還沒起播的收卡音作廢，不會在這一抽才冒出來。
    final player = _whooshPlayer ??= _create(ReleaseMode.release);
    _playOneShot(player, _kWhooshAsset, _kWhooshVolume);
  }

  @override
  void stopWhoosh() {
    final player = _whooshPlayer;
    if (player == null) return; // 從未播過 → no-op。
    final generation = _whooshGeneration;
    if (_whooshFadingGeneration == generation) return; // 這一輪已經在淡出。
    try {
      if (player.state != PlayerState.playing) {
        // 還沒出聲（載入中）或已經播完：直接停，沒有聲音可切，不會有斷層。
        unawaited(player.stop().catchError((Object _) {}));
        return;
      }
      _whooshFadingGeneration = generation;
      unawaited(
        fadeOutThenStop(
          from: _kWhooshVolume,
          duration: _kWhooshFadeOut,
          steps: _kWhooshFadeSteps,
          stillWanted: () => generation == _whooshGeneration,
          setVolume: (volume) =>
              unawaited(player.setVolume(volume).catchError((Object _) {})),
          stop: () => unawaited(player.stop().catchError((Object _) {})),
        ).catchError((Object _) {}),
      );
    } catch (_) {
      // 停止失敗也不丟。
    }
  }

  @override
  void playWaitingLoop() {
    // F3：刻意固定靜音。勿重新接回舊 asset；見 docs/bug-log.md 2026-07-16。
  }

  @override
  void stopWaitingLoop() {
    // 相容舊 lifecycle 出口的 idempotent no-op。
  }

  @override
  void preloadReveal() {
    try {
      _bed.ensurePrepared();
      _archive.ensurePrepared();
    } catch (_) {
      // 預載失敗不丟；播放時會再試。
    }
  }

  // 揭曉配樂 bed：與 `_reveal` 對好拍的配樂，揭曉起始播一次。高潮重音在 bed 裡，所以用
  // 預載好的 player 從頭 resume；同一個 player 先 stop 歸零再播，換一位時若上一條還沒播完
  // 也不會疊兩條。
  @override
  void playRevealBed() {
    try {
      _ensureContext();
      _bedActive = true;
      final generation = ++_bedGeneration;
      unawaited(_startBed(_bed.ensurePrepared(), generation));
    } catch (_) {
      // 啟動失敗也不丟；bed 視為未啟動。
      _bedActive = false;
    }
  }

  Future<void> _startBed(Future<bool> ready, int generation) async {
    bool stillWanted() => _bedActive && generation == _bedGeneration;
    try {
      if (!await ready) return;
      final player = _bed.player;
      if (player == null || !stillWanted()) return; // 預載期間已被停掉或重起。
      await player.stop(); // 位置歸零、音源保留（ReleaseMode.stop）。
      if (!stillWanted()) return;
      // 收卡淡出走完時就會把音量設回（[_stopAndRestoreBedVolume]），平常起播不必多等
      // 一次 setVolume。只有淡出被新的一抽打斷、音量停在半路時，才要先設回來。
      if (_bedVolume != _kRevealBedVolume) {
        await player.setVolume(_kRevealBedVolume);
        _bedVolume = _kRevealBedVolume;
        if (!stillWanted()) return;
      }
      await player.resume();
    } catch (_) {
      // 音效非關鍵路徑：失敗不丟。
    }
  }

  @override
  void playArchive() {
    try {
      _ensureContext();
      final generation = ++_archiveGeneration;
      final sinceTap = Stopwatch()..start();
      unawaited(
        _startArchive(_archive.ensurePrepared(), generation, sinceTap),
      );
    } catch (_) {
      // 音效非關鍵路徑：失敗不丟。
    }
  }

  /// 收卡音只在收卡動畫（[PracticeRevealTiming.archive]）走完前起播：預載失敗、點擊時重載
  /// 又太慢，寧可不出聲，也不在儀式收掉之後、甚至下一抽才冒出來。
  Future<void> _startArchive(
    Future<bool> ready,
    int generation,
    Stopwatch sinceTap,
  ) async {
    try {
      await replayIfStillWanted(
        ready: ready,
        stillWanted: () =>
            _archive.player != null &&
            generation == _archiveGeneration &&
            sinceTap.elapsed < PracticeRevealTiming.archive,
        // 位置歸零、音源保留（ReleaseMode.stop）。
        rewind: () => _archive.player!.stop(),
        play: () => _archive.player!.resume(),
      );
    } catch (_) {
      // 音效非關鍵路徑：失敗不丟。
    }
  }

  /// 停止揭曉配樂：正在出聲時 0.25 秒淡出再停（點擊收卡時不一刀切），還沒出聲就直接停。
  /// 淡出途中又開始新的一抽（[playRevealBed] 遞增 generation）就收手，不動新的那條。
  @override
  void stopRevealBed() {
    final player = _bed.player;
    if (player == null || !_bedActive) return; // 未建立／未播放 → idempotent no-op。
    _bedActive = false;
    final generation = _bedGeneration;
    try {
      if (player.state != PlayerState.playing) {
        unawaited(player.stop().catchError((Object _) {}));
        return;
      }
      unawaited(
        fadeOutThenStop(
          from: _kRevealBedVolume,
          duration: _kRevealBedFadeOut,
          steps: _kRevealBedFadeSteps,
          stillWanted: () => generation == _bedGeneration,
          setVolume: (volume) {
            _bedVolume = volume;
            unawaited(player.setVolume(volume).catchError((Object _) {}));
          },
          stop: () => unawaited(_stopAndRestoreBedVolume(player)),
        ).catchError((Object _) {}),
      );
    } catch (_) {
      // 停止失敗也不丟。
    }
  }

  /// 收卡淡出走完：停掉，再把音量設回起播音量（不在下一次起播的關鍵路徑上）。設回失敗
  /// 就讓 [_bedVolume] 留在淡出後的值，下一次起播會自己先補設。
  Future<void> _stopAndRestoreBedVolume(AudioPlayer player) async {
    try {
      await player.stop();
      await player.setVolume(_kRevealBedVolume);
      _bedVolume = _kRevealBedVolume;
    } catch (_) {
      // 音效非關鍵路徑：失敗不丟。
    }
  }
}

/// 預載成可重播的 player：`ReleaseMode.stop` 停止後保留音源，下一次 stop 歸零再 resume。
/// 同一次預載共用一個 future（預載中再呼叫拿到同一個）；失敗就清掉，下一次預載或播放再試。
/// bed 與收卡音各一個，這套邏輯只寫一份。
class _ReplayablePlayer {
  _ReplayablePlayer(this.asset, this.volume);

  final String asset;
  final double volume;

  /// 第一次預載時才建立（lazy：建構不碰 platform channel）。
  AudioPlayer? player;
  Future<bool>? _ready;

  Future<bool> ensurePrepared() {
    final current = _ready;
    if (current != null) return current;
    final next = _prepare();
    _ready = next;
    unawaited(
      next.then((ok) {
        if (!ok && identical(_ready, next)) _ready = null;
      }),
    );
    return next;
  }

  /// 建立 player 並載好音源。成功回 true；失敗（測試／無 platform）回 false、不丟。
  Future<bool> _prepare() async {
    try {
      final p = player ??= AudioPlayer();
      await p.setReleaseMode(ReleaseMode.stop);
      await p.setVolume(volume);
      await p.setSource(AssetSource(asset));
      return true;
    } catch (_) {
      return false;
    }
  }
}
