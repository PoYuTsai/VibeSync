import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import 'practice_draw_sfx.dart';

// ── 音量常數（集中於此，方便真機調整）─────────────────────────────────────
// 真機目檢時直接調這三個值即可，不必動播放邏輯。
const double _kWhooshVolume = 0.7; // 抽牌咻聲：建議 0.6–0.8。
const double _kWaitingLoopVolume = 0.22; // 等待 loop：建議 0.18–0.28，務必小聲。
const double _kRevealChimeVolume = 0.8; // 揭曉叮聲：建議 0.7–0.9。
const double _kRevealBedVolume = 0.75; // 揭曉配樂 bed（主配樂）：建議 0.6–0.85。

// ── 音檔路徑（相對 AudioCache 預設 prefix `assets/`）────────────────────────
const String _kWhooshAsset = 'audio/practice_draw/practice_draw_whoosh.wav';
const String _kWaitingLoopAsset =
    'audio/practice_draw/practice_draw_waiting_loop.wav';
const String _kRevealChimeAsset =
    'audio/practice_draw/practice_draw_reveal_chime.wav';
// E2：揭曉配樂 bed（復刻 音檔.mp4 音軌）。mp3 以控資產體積（~9s wav 會爆 <500KB 預算）。
const String _kRevealBedAsset =
    'audio/practice_draw/practice_draw_reveal_bed.mp3';

/// 每日翻牌音效的真實實作（Batch 4.7B：把 4.7A 的 [NoopPracticeDrawSfx] 換成會真的
/// 播放的版本）。背後用 `audioplayers`。
///
/// 設計鐵則：
/// - **lazy + guarded**：建構不碰任何 platform channel（不建立 player）；player 在首次
///   播放時才建立。所有 play／stop／context 設定都吞掉同步與 async 例外，因此在 headless
///   ／widget-test 環境（無 audio platform channel）一律靜默、絕不丟例外、絕不留未監聽的
///   create 失敗。真機才會真的發聲。
/// - **獨立 player**：whoosh／reveal chime／揭曉配樂 bed 各自一個一次性（`ReleaseMode.release`）
///   player 避免互相截斷；waiting loop 用 `ReleaseMode.loop` 的獨立 player，方便獨立 stop。
///   bed 與 loop 都可被明確 stop（[stopRevealBed]／[stopWaitingLoop]），離開出口一律收掉。
/// - **stopWaitingLoop idempotent**：未啟動或重複呼叫皆 no-op，呼叫端（揭曉儀式）在每個
///   離開 drawing 的出口（reveal／error／402／429／hidden／dispose／reduce-motion）呼叫，
///   loop 一律不殘留。
/// - **iOS AudioContext**：`respectSilence`（ambient，尊重靜音鍵）＋`mixWithOthers`
///   （不中斷使用者背景音樂）；非必要的浪漫音效在公共場合不擾人。
class AudioPlayersPracticeDrawSfx implements PracticeDrawSfx {
  AudioPlayersPracticeDrawSfx();

  AudioPlayer? _whooshPlayer;
  AudioPlayer? _loopPlayer;
  AudioPlayer? _chimePlayer;
  AudioPlayer? _bedPlayer;

  bool _loopActive = false;
  bool _bedActive = false;
  bool _contextConfigured = false;

  /// 首次播放時設定一次全域 AudioContext（尊重靜音鍵＋與他人音樂混音不中斷）。
  /// 失敗（測試／無 platform）靜默吞掉。
  void _ensureContext() {
    if (_contextConfigured) return;
    _contextConfigured = true;
    unawaited(
      AudioPlayer.global
          .setAudioContext(
            AudioContextConfig(
              respectSilence: true,
              focus: AudioContextConfigFocus.mixWithOthers,
            ).build(),
          )
          .catchError((Object _) {}),
    );
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
    final player = _whooshPlayer ??= _create(ReleaseMode.release);
    _playOneShot(player, _kWhooshAsset, _kWhooshVolume);
  }

  @override
  void playRevealChime() {
    final player = _chimePlayer ??= _create(ReleaseMode.release);
    _playOneShot(player, _kRevealChimeAsset, _kRevealChimeVolume);
  }

  @override
  void playWaitingLoop() {
    try {
      _ensureContext();
      final player = _loopPlayer ??= _create(ReleaseMode.loop);
      _loopActive = true;
      unawaited(
        player
            .play(AssetSource(_kWaitingLoopAsset),
                volume: _kWaitingLoopVolume)
            .catchError((Object _) {}),
      );
    } catch (_) {
      // 啟動失敗也不丟；loop 視為未啟動。
      _loopActive = false;
    }
  }

  @override
  void stopWaitingLoop() {
    final player = _loopPlayer;
    if (player == null || !_loopActive) return; // 未建立／未播放 → idempotent no-op。
    _loopActive = false;
    try {
      unawaited(player.stop().catchError((Object _) {}));
    } catch (_) {
      // 停止失敗也不丟。
    }
  }

  // E2：揭曉配樂 bed（復刻 音檔.mp4 音軌）。一條與 `_reveal`（~9s）同長的連續配樂，揭曉
  // 起始播一次，取代舊的離散 riser/settle accent。專屬 player（`ReleaseMode.release`，
  // 一次性、播完不留）；重抽時先 stop 再 play，確保同時只有一條 bed、不重疊。
  @override
  void playRevealBed() {
    try {
      _ensureContext();
      final player = _bedPlayer ??= _create(ReleaseMode.release);
      _bedActive = true;
      // 先 stop 再 play：保證每次揭曉只一條 bed（換一位若在前一條未播完時觸發也不疊）。
      unawaited(
        player
            .stop()
            .then(
              (_) => player.play(
                AssetSource(_kRevealBedAsset),
                volume: _kRevealBedVolume,
              ),
            )
            .catchError((Object _) {}),
      );
    } catch (_) {
      // 啟動失敗也不丟；bed 視為未啟動。
      _bedActive = false;
    }
  }

  @override
  void stopRevealBed() {
    final player = _bedPlayer;
    if (player == null || !_bedActive) return; // 未建立／未播放 → idempotent no-op。
    _bedActive = false;
    try {
      unawaited(player.stop().catchError((Object _) {}));
    } catch (_) {
      // 停止失敗也不丟。
    }
  }
}
