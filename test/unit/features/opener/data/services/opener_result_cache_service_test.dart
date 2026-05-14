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

  test('draft cache stores opener result with local metadata', () async {
    const result = OpenerResult(
      openers: {
        'extend': 'First line',
        'humor': 'Second line',
      },
      recommendedPick: 'extend',
      recommendedReason: 'Best first hook.',
      costUsed: 5,
    );
    final service = OpenerResultCacheService();

    final draft = await service.saveDraft(
      result: result,
      displayName: 'Grace',
      sourceLabel: '截圖自介',
      inputPreview: '2 張截圖',
    );

    final drafts = service.loadDrafts();
    expect(drafts, hasLength(1));
    expect(drafts.first.id, draft.id);
    expect(drafts.first.title, 'Grace');
    expect(drafts.first.preview, '2 張截圖');
    expect(drafts.first.result.bestOpenerText, 'First line');
    expect(service.loadLatest()!.bestOpenerText, 'First line');
  });

  test('draft cache keeps only newest 10 drafts', () async {
    final service = OpenerResultCacheService();

    for (var i = 0; i < 12; i += 1) {
      await service.saveDraft(
        result: OpenerResult(
          openers: {'extend': 'line $i'},
          recommendedPick: 'extend',
        ),
        displayName: 'draft $i',
      );
    }

    final drafts = service.loadDrafts();
    expect(drafts, hasLength(OpenerResultCacheService.maxDrafts));
    expect(drafts.first.title, 'draft 11');
    expect(drafts.last.title, 'draft 2');
  });

  test('draft cache persists partnerId so drafts can be linked to a person',
      () async {
    final service = OpenerResultCacheService();

    final draft = await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line'},
        recommendedPick: 'extend',
      ),
      displayName: '小美',
      partnerId: 'partner-123',
    );

    expect(draft.partnerId, 'partner-123');

    final reloaded = service.loadDraft(draft.id);
    expect(reloaded, isNotNull);
    expect(reloaded!.partnerId, 'partner-123');
    expect(reloaded.displayName, '小美');
  });

  test('legacy drafts without partnerId still parse', () async {
    final service = OpenerResultCacheService();
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'legacy'},
        recommendedPick: 'extend',
      ),
      displayName: 'legacy',
    );

    final drafts = service.loadDrafts();
    expect(drafts, hasLength(1));
    expect(drafts.first.partnerId, isNull);
  });

  test('draft cache can mark continued and delete draft', () async {
    final service = OpenerResultCacheService();
    final draft = await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line'},
        recommendedPick: 'extend',
      ),
      displayName: 'Grace',
    );

    await service.markDraftContinued(draft.id);
    expect(service.loadDraft(draft.id)!.continuedAt, isNotNull);

    await service.deleteDraft(draft.id);
    expect(service.loadDrafts(), isEmpty);
  });
}
