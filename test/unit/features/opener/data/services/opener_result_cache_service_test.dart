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
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');

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
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');

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
    expect(drafts.first.previewForAccess(isFreeUser: false), '2 張截圖');
    expect(drafts.first.previewForAccess(isFreeUser: true), '2 張截圖');
    expect(drafts.first.result.bestOpenerText, 'First line');
    expect(service.loadLatest()!.bestOpenerText, 'First line');
  });

  test('draft cache keeps only newest 10 drafts', () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');

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
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');

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

  test('draft cache filters recent drafts by partner scope', () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');

    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line a'},
        recommendedPick: 'extend',
      ),
      displayName: 'A 對象',
      partnerId: 'partner-a',
    );
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line global'},
        recommendedPick: 'extend',
      ),
      displayName: '全域入口',
    );
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line b'},
        recommendedPick: 'extend',
      ),
      displayName: 'B 對象',
      partnerId: 'partner-b',
    );

    expect(
      service.loadDraftsForScope(partnerId: 'partner-a').map((d) => d.title),
      ['A 對象'],
    );
    expect(
      service.loadDraftsForScope(partnerId: 'partner-b').map((d) => d.title),
      ['B 對象'],
    );
    expect(
      service.loadDraftsForScope(partnerId: 'partner-c'),
      isEmpty,
    );
    expect(
      service.loadDraftsForScope().map((d) => d.title),
      ['全域入口'],
    );
  });

  test('partner-scoped drafts do not overwrite unscoped handoff latest',
      () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');

    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'global line'},
        recommendedPick: 'extend',
      ),
      displayName: '全域入口',
    );
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'partner line'},
        recommendedPick: 'extend',
      ),
      displayName: 'A partner',
      partnerId: 'partner-a',
    );

    expect(service.loadLatest()!.bestOpenerText, 'global line');
    expect(service.loadLatestForScope()!.bestOpenerText, 'global line');
    expect(
      service.loadLatestForScope(partnerId: 'partner-a')!.bestOpenerText,
      'partner line',
    );
  });

  test('unscoped handoff ignores partner-only drafts', () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');

    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'partner line'},
        recommendedPick: 'extend',
      ),
      displayName: 'A partner',
      partnerId: 'partner-a',
    );

    expect(service.loadLatest(), isNull);
    expect(service.loadLatestForScope(), isNull);
    expect(
      service.loadLatestForScope(partnerId: 'partner-a')!.bestOpenerText,
      'partner line',
    );
  });

  test('scoped latest uses partner draft instead of global latest', () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');

    await service.saveLatest(const OpenerResult(
      openers: {'extend': 'global line'},
      recommendedPick: 'extend',
    ));
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'partner line'},
        recommendedPick: 'extend',
      ),
      displayName: 'A partner',
      partnerId: 'partner-a',
    );

    expect(
      service.loadLatestForScope(partnerId: 'partner-a')!.bestOpenerText,
      'partner line',
    );
  });

  test('scoped latest does not fall back to another partner draft', () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');

    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'partner b line'},
        recommendedPick: 'extend',
      ),
      displayName: 'B partner',
      partnerId: 'partner-b',
    );

    expect(service.loadLatestForScope(partnerId: 'partner-a'), isNull);
  });

  test('draft cache trims partner scope before filtering', () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');

    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line'},
        recommendedPick: 'extend',
      ),
      displayName: '小美',
      partnerId: '  partner-123  ',
    );

    expect(
      service.loadDraftsForScope(partnerId: 'partner-123').map((d) => d.title),
      ['小美'],
    );
    expect(
      service.loadDraftsForScope(partnerId: '   '),
      isEmpty,
    );
  });

  test('legacy drafts without partnerId still parse', () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
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
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
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

  test('continue never downgrades the stored draft result', () async {
    // Batch 4 #4: a free/downgraded user continuing a paid-era draft must not
    // permanently strip the paid styles from local storage. Leak protection
    // is enforced at read time via visibleForAccess, not by rewriting drafts.
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
    final draft = await service.saveDraft(
      result: const OpenerResult(
        openers: {
          'extend': 'free line',
          'coldRead': 'locked line',
        },
        recommendedPick: 'coldRead',
        recommendedReason: 'locked reason',
      ),
      displayName: 'Grace',
      partnerId: 'partner-a',
    );

    await service.markDraftContinued(draft.id);

    final stored = service.loadDraft(draft.id)!;
    expect(stored.continuedAt, isNotNull);
    expect(stored.result.openers, {
      'extend': 'free line',
      'coldRead': 'locked line',
    });
    expect(stored.result.recommendedPick, 'coldRead');
    expect(stored.result.recommendedReason, 'locked reason');

    // Read-time gating still hides locked content from free users.
    final visible = stored.result.visibleForAccess(isFreeUser: true);
    expect(visible.openers, {'extend': 'free line'});
    expect(visible.recommendedPick, 'extend');
    expect(visible.recommendedReason, isNull);
  });

  test('draft preview never exposes a locked opener to free users', () async {
    // Codex P2 follow-up to Batch 4 #4: a draft without inputPreview falls
    // back to the opener text — that fallback must be access-aware, or the
    // recent-drafts list leaks the locked paid pick to free users.
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
    final draft = await service.saveDraft(
      result: const OpenerResult(
        openers: {
          'extend': 'free line',
          'coldRead': 'locked line',
        },
        recommendedPick: 'coldRead',
      ),
      displayName: 'Grace',
    );

    expect(draft.previewForAccess(isFreeUser: false), 'locked line');
    expect(draft.previewForAccess(isFreeUser: true), 'free line');
  });

  test('draft preview falls back to neutral copy when nothing is visible',
      () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
    final draft = await service.saveDraft(
      result: const OpenerResult(
        openers: {'coldRead': 'locked line'},
        recommendedPick: 'coldRead',
      ),
      displayName: 'Grace',
    );

    expect(draft.previewForAccess(isFreeUser: false), 'locked line');
    expect(draft.previewForAccess(isFreeUser: true), '已保存開場建議');
  });

  test('deleteDraftsForPartner removes only that partner scoped drafts',
      () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line a'},
        recommendedPick: 'extend',
      ),
      displayName: 'A 對象',
      partnerId: 'partner-a',
    );
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line b'},
        recommendedPick: 'extend',
      ),
      displayName: 'B 對象',
      partnerId: 'partner-b',
    );
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line global'},
        recommendedPick: 'extend',
      ),
      displayName: '全域入口',
    );

    await service.deleteDraftsForPartner('partner-a');

    expect(service.loadDraftsForScope(partnerId: 'partner-a'), isEmpty);
    expect(
      service.loadDraftsForScope(partnerId: 'partner-b').map((d) => d.title),
      ['B 對象'],
    );
    expect(
      service.loadDraftsForScope().map((d) => d.title),
      ['全域入口'],
    );
  });

  test('deleteDraftsForPartner with blank id never touches global drafts',
      () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line global'},
        recommendedPick: 'extend',
      ),
      displayName: '全域入口',
    );

    await service.deleteDraftsForPartner('   ');

    expect(
      service.loadDraftsForScope().map((d) => d.title),
      ['全域入口'],
    );
  });

  test('reassignDraftsPartner moves source drafts into target scope',
      () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line a'},
        recommendedPick: 'extend',
      ),
      displayName: 'A 對象',
      partnerId: 'partner-a',
    );
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line b'},
        recommendedPick: 'extend',
      ),
      displayName: 'B 對象',
      partnerId: 'partner-b',
    );
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line global'},
        recommendedPick: 'extend',
      ),
      displayName: '全域入口',
    );

    await service.reassignDraftsPartner(
      fromPartnerId: 'partner-a',
      toPartnerId: 'partner-b',
    );

    expect(service.loadDraftsForScope(partnerId: 'partner-a'), isEmpty);
    expect(
      service
          .loadDraftsForScope(partnerId: 'partner-b')
          .map((d) => d.title)
          .toSet(),
      {'A 對象', 'B 對象'},
    );
    expect(
      service.loadDraftsForScope().map((d) => d.title),
      ['全域入口'],
    );
  });

  test('reassignDraftsPartner with blank source never touches global drafts',
      () async {
    final service = OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
    await service.saveDraft(
      result: const OpenerResult(
        openers: {'extend': 'line global'},
        recommendedPick: 'extend',
      ),
      displayName: '全域入口',
    );

    await service.reassignDraftsPartner(
      fromPartnerId: '   ',
      toPartnerId: 'partner-b',
    );

    expect(service.loadDraftsForScope(partnerId: 'partner-b'), isEmpty);
    expect(
      service.loadDraftsForScope().map((d) => d.title),
      ['全域入口'],
    );
  });

  group('owner scoping（2026-08-07 稽核 #5：草稿跨帳號外洩）', () {
    const result = OpenerResult(
      openers: {'extend': 'Owner line'},
      recommendedPick: 'extend',
    );

    test('不同帳號互看不到草稿與 latest', () async {
      final ownerA =
          OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
      final ownerB =
          OpenerResultCacheService(ownerIdResolver: () => 'owner-b');

      await ownerA.saveDraft(result: result, displayName: 'A 的草稿');
      await ownerA.saveLatest(result);

      expect(ownerB.loadDrafts(), isEmpty);
      expect(ownerB.loadLatest(), isNull);
      expect(ownerA.loadDrafts().map((d) => d.title), ['A 的草稿']);
      expect(ownerA.loadLatest(), isNotNull);
    });

    test('沒有帳號時 fail closed：不寫入、讀取皆空', () async {
      final noOwner = OpenerResultCacheService(ownerIdResolver: () => null);

      await noOwner.saveDraft(result: result, displayName: '無主草稿');
      await noOwner.saveLatest(result);

      expect(noOwner.loadDrafts(), isEmpty);
      expect(noOwner.loadLatest(), isNull);
      // 也不得寫進未綁 key 讓下一個帳號吸走。
      final ownerA =
          OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
      expect(ownerA.loadDrafts(), isEmpty);
      expect(ownerA.loadLatest(), isNull);
    });

    test('舊未綁 key 一次性搬給目前帳號並刪除舊 key', () async {
      final box = Hive.box(AppConstants.settingsBox);
      final legacyService =
          OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
      // 先用 scoped 服務產生合法 payload，再手動搬回舊 key 模擬升級前資料。
      await legacyService.saveDraft(result: result, displayName: '舊草稿');
      await legacyService.saveLatest(result);
      final draftsRaw = box.get('opener_drafts_v1:owner-a');
      final latestRaw = box.get('opener_latest_result_v1:owner-a');
      await box.put('opener_drafts_v1', draftsRaw);
      await box.put('opener_latest_result_v1', latestRaw);
      await box.delete('opener_drafts_v1:owner-a');
      await box.delete('opener_latest_result_v1:owner-a');

      final ownerA =
          OpenerResultCacheService(ownerIdResolver: () => 'owner-a');
      expect(ownerA.loadDrafts().map((d) => d.title), ['舊草稿']);
      expect(ownerA.loadLatest(), isNotNull);
      // 搬遷後舊 key 必須消失，之後的帳號不會再吸到。
      expect(box.get('opener_drafts_v1'), isNull);
      expect(box.get('opener_latest_result_v1'), isNull);
      final ownerB =
          OpenerResultCacheService(ownerIdResolver: () => 'owner-b');
      expect(ownerB.loadDrafts(), isEmpty);
      expect(ownerB.loadLatest(), isNull);
    });
  });
}
