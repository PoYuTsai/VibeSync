import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/night_market/data/night_market_story.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('every night-market media file is present in the app bundle', () async {
    final scenario = buildNightMarketScenario();
    final paths = <String>{
      scenario.coverAsset,
      for (final beat in scenario.beats) beat.videoAsset,
    };
    expect(paths, hasLength(4));
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final bundled = manifest.listAssets().toSet();
    for (final path in paths) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: 'Missing media: $path');
      expect(bundled, contains(path),
          reason: 'Not in Flutter asset manifest: $path');
      expect(file.lengthSync(), greaterThan(1024),
          reason: 'Placeholder: $path');
      final directory = path.substring(0, path.lastIndexOf('/') + 1);
      expect(pubspec, contains(directory),
          reason: 'Asset root not bundled: $directory');
    }
  });
}
