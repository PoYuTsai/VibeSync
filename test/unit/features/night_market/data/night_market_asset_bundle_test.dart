import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/night_market/data/night_market_story.dart';
import 'package:vibesync/features/night_market/domain/night_market_scenario.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('every reachable night-market media file is present in the app bundle',
      () async {
    final paths = <String>{'assets/audio/night_market/market-bed.mp3'};
    final videos = <String>{};
    for (final variant in NightMarketRunVariant.values) {
      final scenario = buildNightMarketScenario(variant: variant);
      for (final beat in scenario.beats) {
        if (!beat.textOnly) {
          paths.add(beat.videoAsset);
          videos.add(beat.videoAsset);
        }
        if (beat.posterAsset case final String poster) paths.add(poster);
        if (beat.sfxAsset case final String sfx) paths.add(sfx);
        for (final choice in beat.choices) {
          if (choice.audioAsset case final String voice) paths.add(voice);
        }
      }
    }
    expect(videos, hasLength(14));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final bundled = manifest.listAssets().toSet();
    for (final path in paths) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'Missing media: $path');
      expect(bundled, contains(path), reason: 'Not in Flutter asset manifest: $path');
      expect(file.lengthSync(), greaterThan(1024),
          reason: 'Placeholder: $path');
      final directory = path.substring(0, path.lastIndexOf('/') + 1);
      expect(pubspec, contains(directory),
          reason: 'Asset root not bundled: $directory');
    }
  });
}
