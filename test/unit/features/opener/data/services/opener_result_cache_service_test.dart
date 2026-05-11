import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/core/constants/app_constants.dart';
import 'package:vibesync/features/opener/data/services/opener_result_cache_service.dart';
import 'package:vibesync/features/opener/data/services/opener_service.dart';

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_opener_result_cache');
  });

  setUp(() async {
    await Hive.openBox(AppConstants.settingsBox);
  });

  tearDown(() async {
    await Hive.deleteBoxFromDisk(AppConstants.settingsBox);
  });

  tearDownAll(() async {
    await Hive.close();
  });

  test('OpenerResult survives json round trip', () {
    const result = OpenerResult(
      profileAnalysis: {
        'masterObservation': 'reads the profile without over-explaining',
      },
      openers: {
        'extend': 'You look like you have a very specific chaos playlist.',
        'coldRead': 'You seem like you choose songs by mood, not genre.',
      },
      pioneerPlan: {
        'ifCold': 'Do not chase; switch to one easy hook.',
      },
      recommendedPick: 'coldRead',
      recommendedReason: 'Matches the most concrete hook.',
      costUsed: 5,
    );

    final restored = OpenerResult.fromJson(result.toJson());

    expect(restored.profileAnalysis, result.profileAnalysis);
    expect(restored.openers, result.openers);
    expect(restored.pioneerPlan, result.pioneerPlan);
    expect(restored.recommendedPick, result.recommendedPick);
    expect(restored.recommendedReason, result.recommendedReason);
    expect(restored.costUsed, result.costUsed);
  });

  test('OpenerResult picks recommended opener for conversation handoff', () {
    const result = OpenerResult(
      openers: {
        'extend': 'First line',
        'coldRead': 'Better line',
      },
      recommendedPick: 'coldRead',
    );

    expect(result.bestOpenerType, 'coldRead');
    expect(result.bestOpenerText, 'Better line');
  });

  test('OpenerResult falls back to first usable opener when pick is missing',
      () {
    const result = OpenerResult(
      openers: {
        'extend': '',
        'humor': 'Fallback line',
      },
      recommendedPick: 'missing',
    );

    expect(result.bestOpenerType, 'humor');
    expect(result.bestOpenerText, 'Fallback line');
  });

  test('cache persists latest opener result in settings box', () async {
    const result = OpenerResult(
      openers: {
        'extend': 'First line',
        'humor': 'Second line',
      },
      recommendedPick: 'extend',
      costUsed: 3,
    );
    final service = OpenerResultCacheService();

    await service.saveLatest(result);

    final restored = service.loadLatest();
    expect(restored, isNotNull);
    expect(restored!.openers, result.openers);
    expect(restored.recommendedPick, result.recommendedPick);
    expect(restored.costUsed, result.costUsed);
  });
}
