import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'practice_draw_sfx.dart';

// ── 音量常數（集中於此，方便真機調整）─────────────────────────────────────
// 真機目檢時直接調這三個值即可，不必動播放邏輯。
// 咻聲 v2 母帶到 true peak −1.2 dBTP、bed v4 母帶到 −18 LUFS，音量由參考混音反推：
// - 咻聲：手機上比揭曉高潮小 8 dB（舊版反而大 8.5 dB）。調大不要超過約 0.27，
//   高潮至少要比咻聲大 6 dB。
// - bed：翻牌後和舊版（F2 × 0.75）一樣大聲。
const double _kWhooshVolume = 0.22;
const double _kRevealChimeVolume = 0.8; // 揭曉叮聲：建議 0.7–0.9。
const double _kRevealBedVolume = 0.74;

// ── 音檔路徑（相對 AudioCache 預設 prefix `assets/`）────────────────────────
// 咻聲 v2：實心起手，加一段一次性的暖尾巴（C–G 長音，最長 5.5 s）接住等待 server 的空檔。
const String _kWhooshAsset = 'audio/practice_draw/practice_draw_whoosh.m4a';
const String _kRevealChimeAsset =
    'audio/practice_draw/practice_draw_reveal_chime.wav';
// bed v4：F2 整首提前 0.37 s 對齊畫面＋低頻整理；翻牌前與屏息補 C–G 長音，翻牌後回到原曲。
const String _kRevealBedAsset =
    'audio/practice_draw/practice_draw_reveal_bed.mp3';

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

/// 每日翻牌音效的真實實作（Batch 4.7B：把 4.7A 的 [NoopPracticeDrawSfx] 換成會真的
/// 播放的版本）。背後用 `audioplayers`。
///
/// 設計鐵則：
/// - **lazy + guarded**：建構不碰任何 platform channel（不建立 player）；player 在首次
///   播放時才建立。所有 play／stop／context 設定都吞掉同步與 async 例外，因此在 headless
///   ／widget-test 環境（無 audio platform channel）一律靜默、絕不丟例外、絕不留未監聽的
///   create 失敗。真機才會真的發聲。
/// - **獨立 player**：whoosh／reveal chime／揭曉配樂 bed 各自一個 player，避免互相截斷。
///   whoosh／chime 是一次性（`ReleaseMode.release`）；bed 由 [preloadReveal] 先載好
///   （`ReleaseMode.stop`，停止後保留音源），揭曉時從頭 resume，降低起播延遲。
/// - **waiting loop 已退役**：build 326 證實等待期 shimmer 是殘留「西西簌簌」來源；
///   [playWaitingLoop]／[stopWaitingLoop] 暫留介面相容，但 production 實作固定 no-op。
/// - **AudioContext**：見 [buildPracticeDrawAudioContext]。iOS 用 `ambient`：尊重靜音鍵、
///   不中斷使用者背景音樂；非必要的浪漫音效在公共場合不擾人。
class AudioPlayersPracticeDrawSfx implements PracticeDrawSfx {
  AudioPlayersPracticeDrawSfx();

  AudioPlayer? _whooshPlayer;
  AudioPlayer? _chimePlayer;
  AudioPlayer? _bedPlayer;
  // bed 預載：完成為 true；失敗會清掉，下一次預載或播放再試。
  Future<bool>? _bedReady;
  // 每次 playRevealBed 遞增；預載期間被停掉或重起時，只讓最後一次起播。
  int _bedGeneration = 0;

  bool _bedActive = false;
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
    // F3：刻意固定靜音。勿重新接回舊 asset；見 docs/bug-log.md 2026-07-16。
  }

  @override
  void stopWaitingLoop() {
    // 相容舊 lifecycle 出口的 idempotent no-op。
  }

  @override
  void preloadReveal() {
    try {
      _ensureBedPrepared();
    } catch (_) {
      // 預載失敗不丟；playRevealBed 會再試。
    }
  }

  /// 共用同一次預載：預載中再呼叫拿到同一個 future；失敗後清掉，下一次再試。
  Future<bool> _ensureBedPrepared() {
    final current = _bedReady;
    if (current != null) return current;
    final next = _prepareBed();
    _bedReady = next;
    unawaited(
      next.then((ok) {
        if (!ok && identical(_bedReady, next)) _bedReady = null;
      }),
    );
    return next;
  }

  /// 建立 bed player 並載好音源。成功回 true；失敗（測試／無 platform）回 false、不丟。
  Future<bool> _prepareBed() async {
    try {
      final player = _bedPlayer ??= AudioPlayer();
      await player.setReleaseMode(ReleaseMode.stop);
      await player.setVolume(_kRevealBedVolume);
      await player.setSource(AssetSource(_kRevealBedAsset));
      return true;
    } catch (_) {
      return false;
    }
  }

  // 揭曉配樂 bed：與 `_reveal`（10 s）同長同步的連續配樂，揭曉起始播一次。v4 的三個重音
  // 都在 bed 裡，所以用預載好的 player 從頭 resume；同一個 player 先 stop 歸零再播，
  // 換一位時若上一條還沒播完也不會疊兩條。
  @override
  void playRevealBed() {
    try {
      _ensureContext();
      _bedActive = true;
      final generation = ++_bedGeneration;
      unawaited(_startBed(_ensureBedPrepared(), generation));
    } catch (_) {
      // 啟動失敗也不丟；bed 視為未啟動。
      _bedActive = false;
    }
  }

  Future<void> _startBed(Future<bool> ready, int generation) async {
    bool stillWanted() => _bedActive && generation == _bedGeneration;
    try {
      if (!await ready) return;
      final player = _bedPlayer;
      if (player == null || !stillWanted()) return; // 預載期間已被停掉或重起。
      await player.stop(); // 位置歸零、音源保留（ReleaseMode.stop）。
      if (!stillWanted()) return;
      await player.resume();
    } catch (_) {
      // 音效非關鍵路徑：失敗不丟。
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
