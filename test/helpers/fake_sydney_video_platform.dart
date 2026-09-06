import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Fakes only the native boundary; tests retain the real player controller,
/// event subscription, initialization and disposal behavior.
class FakeSydneyVideoPlatform extends VideoPlayerPlatform {
  bool autoInitialize = true;
  bool failInitialization = false;
  bool failPlay = false;
  Completer<void>? creationGate;
  final creations = <VideoCreationOptions>[];
  final streams = <int, StreamController<VideoEvent>>{};
  final playCalls = <int>[];
  final pauseCalls = <int>[];
  final disposed = <int>[];
  final playing = <int, bool>{};
  final volumes = <int, double>{};
  final looping = <int, bool>{};
  final preventsDisplaySleep = <int, bool>{};

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = creations.length;
    creations.add(options);
    // Keep cancellation completion inside the test's async zone; the SDK's
    // shared completed future otherwise outlives a widget test's fake clock.
    streams[id] = StreamController<VideoEvent>(onCancel: () async {});
    if (failInitialization) {
      emitError(id);
    } else if (autoInitialize) {
      finishInitialization(id);
    }
    await creationGate?.future;
    return id;
  }

  void finishInitialization(int id) {
    streams[id]!.add(VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 10),
      size: const Size(540, 960),
    ));
  }

  void emitError(int id) {
    streams[id]!.addError(PlatformException(
      code: 'VideoError',
      message: 'The test decoder failed.',
    ));
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => streams[playerId]!.stream;

  @override
  Future<void> play(int playerId) async {
    playCalls.add(playerId);
    if (failPlay) {
      throw PlatformException(code: 'PlayError', message: 'Playback failed.');
    }
    playing[playerId] = true;
  }

  @override
  Future<void> pause(int playerId) async {
    pauseCalls.add(playerId);
    playing[playerId] = false;
  }

  @override
  Future<void> dispose(int playerId) async {
    disposed.add(playerId);
    playing[playerId] = false;
  }

  @override
  Future<void> setLooping(int playerId, bool value) async {
    looping[playerId] = value;
  }

  @override
  Future<void> setVolume(int playerId, double value) async {
    volumes[playerId] = value;
  }

  @override
  Future<void> setPreventsDisplaySleepDuringVideoPlayback(
    int playerId,
    bool value,
  ) async {
    preventsDisplaySleep[playerId] = value;
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setAllowBackgroundPlayback(bool allowBackgroundPlayback) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => ColoredBox(
        key: ValueKey('fake-sydney-video-${options.playerId}'),
        color: const Color(0xFF241832),
      );

  void close() {
    for (final stream in streams.values) {
      unawaited(stream.close());
    }
  }
}
