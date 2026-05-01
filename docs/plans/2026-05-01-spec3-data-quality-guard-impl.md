# Spec 3: Partner Data Quality Guard — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.
> **Design**: `2026-05-01-spec3-data-quality-guard-design.md` @ 892cf10
> **Codex spec review**: 🟡 APPROVED-WITH-AMENDMENTS @ c7cfee5（5 點 P1–P5 全 amend，無分歧）

**Goal:** 守住 Partner 卡記憶可信度 — 偵測同一卡內疑似混入不同人（名字不一致），客戶端 gate `PartnerContextResolver` 防止污染 aggregate 進 AI，提供 banner + 拆卡 / 標記同一人兩個整理動作。**不寫 prompt impl，不動 OCR / analyze-chat / Edge Function**。

**Architecture:** 垂直切片 TDD 排序 — Phase 1 先鎖 `PartnerContextResolver` gating 契約（Eric directive #1）；Phase 2-3 補 Hive 與 repo cascade（含 split 新路徑，Eric directive #5）；Phase 4 偵測引擎（純本地 heuristic）；Phase 5 UI；Phase 6 驗證。新 entity `PartnerDataQualityState`（typeId 14），獨立 box `partner_data_quality_states` AES-256。偵測 read-time on Partner detail open，scan cap = Conversation.name primary + N=5 incoming-message regex fallback。

**Tech Stack:** Flutter 3.x、Dart 3 immutable classes、Hive CE（typeId 14、AES-256）、Riverpod（`Provider.family` + `AsyncNotifierProviderFamily`，沿用 Spec 2 layered split）、純本地 Dart heuristic。

---

## Implementation Sequence Overview

| Phase | Tasks | 重點 | Approx |
|---|---|---|---|
| 1. Resolver gating（TDD-lock first） | 1-5 | 鎖 `PartnerContextResolver` 契約：flagged-unresolved → return `null`，不注入 aggregate | ~50 min |
| 2. Hive 整合 | 6-9 | typeId 14、box wiring、clearAll cascade | ~30 min |
| 3. Repository + cascade | 10-13 | CRUD + delete / merge / **split** cascade（split 是新路徑） | ~50 min |
| 4. 偵測引擎 | 14-17 | name candidate 抽取（placeholder filter + N=5 cap）+ cross-conversation 比對 + provider | ~60 min |
| 5. UI | 18-21 | `PartnerDataQualityBanner` + Partner detail 整合 + 兩個 action handler | ~70 min |
| 6. Verification | 22-23 | lint + perimeter + full suite + plan Status block | ~20 min |

每個 task 走 TDD：Red → Green → Refactor → Commit。**一個 commit 一件事**，commit 後**立即 push**。

---

## Phase 1 — Resolver Gating（TDD-lock first per Eric directive #1）

### Task 1: 寫失敗測試 — `PartnerContextResolver` flagged 時 return `null`

**Files:**
- Modify: `test/unit/features/analysis/services/partner_context_resolver_test.dart`（既有檔擴張）

**Step 1: Write failing test**

加入新 group「flagged-unresolved gating」，寫至少 3 個 case：

```dart
group('flagged-unresolved gating', () {
  test('returns null when partner has unresolved data-quality flag', () {
    final partner = Partner(id: 'p1', name: 'Anna', ownerUserId: 'u1', updatedAt: DateTime.now());
    final conv = Conversation(id: 'c1', partnerId: 'p1', /* ... */);
    final resolver = PartnerContextResolver(
      partnerRepo: _StubPartnerRepo({'p1': partner}),
      conversationRepo: _StubConvRepo({'p1': [conv]}),
      summaryBuilder: PartnerSummaryBuilder(),
      dataQualityRepo: _StubDataQualityRepo(flagged: {'p1': true}),
    );
    expect(resolver.resolve(conv), isNull);
  });

  test('returns full summary when partner is unflagged', () {
    // setup with dataQualityRepo flagged: {} → unflagged
    // expect summary string非空
  });

  test('returns full summary when partner flag is resolved (confirmed same person)', () {
    // setup with dataQualityRepo flagged: {'p1': false} → flag exists but resolved
    // expect 行為 = unflagged
  });
});
```

新增 stub：

```dart
class _StubDataQualityRepo implements PartnerDataQualityRepoView {
  _StubDataQualityRepo({Map<String, bool> flagged = const {}}) : _flagged = flagged;
  final Map<String, bool> _flagged;
  @override
  bool isFlaggedUnresolved(String partnerId) => _flagged[partnerId] ?? false;
}
```

**Step 2: Run test to verify it fails**

```bash
flutter test test/unit/features/analysis/services/partner_context_resolver_test.dart
```
Expected: FAIL — `PartnerDataQualityRepoView` undefined / `dataQualityRepo` 不是 PartnerContextResolver 建構式參數。

**Step 3: Commit failing test (red phase, allowed because surrounded by next 4 tasks pushing green)**

```bash
git add test/unit/features/analysis/services/partner_context_resolver_test.dart
git commit -m "[test] PartnerContextResolver gating contract（red）"
git push
```

---

### Task 2: Minimal `PartnerDataQualityRepoView` 介面（read-only stub for resolver gating）

**Files:**
- Create: `lib/features/user_profile/data/repositories/partner_data_quality_repo_view.dart`

**Step 1: 寫 minimal interface**

```dart
/// Read-only surface needed by [PartnerContextResolver] to know whether a
/// partner has an unresolved data-quality flag. Real repository (built in
/// Phase 3 Task 10) implements this; tests provide an in-memory stub.
abstract class PartnerDataQualityRepoView {
  bool isFlaggedUnresolved(String partnerId);
}
```

**Step 2: Run analyze**

```bash
flutter analyze --no-fatal-infos lib/features/user_profile/data/repositories/partner_data_quality_repo_view.dart
```
Expected: 0 issues.

**Step 3: Commit**

```bash
git add lib/features/user_profile/data/repositories/partner_data_quality_repo_view.dart
git commit -m "[feat] PartnerDataQualityRepoView read-only stub for resolver gating"
git push
```

---

### Task 3: 注入 `dataQualityRepo` 到 `PartnerContextResolver` + gate

**Files:**
- Modify: `lib/features/analysis/data/services/partner_context_resolver.dart`

**Step 1: Edit resolver**

```dart
import '../../../user_profile/data/repositories/partner_data_quality_repo_view.dart';

class PartnerContextResolver {
  PartnerContextResolver({
    required this.partnerRepo,
    required this.conversationRepo,
    required this.summaryBuilder,
    required this.dataQualityRepo,
  });

  final PartnerRepoView partnerRepo;
  final ConversationListByPartnerView conversationRepo;
  final PartnerSummaryBuilder summaryBuilder;
  final PartnerDataQualityRepoView dataQualityRepo;

  String? resolve(Conversation conversation) {
    final partnerId = conversation.partnerId;
    if (partnerId == null) return null;

    if (dataQualityRepo.isFlaggedUnresolved(partnerId)) {
      // Spec 3 §5.3 — gate 注入：flagged-unresolved 時不送 aggregate context。
      // L1 即時回覆仍走當下 conversation 文本（在呼叫端組合）。
      return null;
    }

    final partner = partnerRepo.getById(partnerId);
    if (partner == null) return null;

    final conversations = conversationRepo.listByPartner(partnerId);
    final summary = summaryBuilder.build(
      partner: partner,
      conversations: conversations,
    );
    return summary.isEmpty ? null : summary;
  }
}
```

**Step 2: Run resolver test**

```bash
flutter test test/unit/features/analysis/services/partner_context_resolver_test.dart
```
Expected: PASS（含 Task 1 三個 new tests + 既有 tests）。

**Step 3: Commit**

```bash
git add lib/features/analysis/data/services/partner_context_resolver.dart
git commit -m "[feat] PartnerContextResolver flagged-unresolved gating (Spec 3 §5.3)"
git push
```

---

### Task 4: 串 resolver 的呼叫端（provider / DI）

**Files:**
- Modify: `lib/features/analysis/data/providers/analysis_providers.dart`（找 `PartnerContextResolver` 建構處）

**Step 1: Grep 找呼叫處**

```bash
grep -rn "PartnerContextResolver(" lib/ test/ 2>/dev/null
```

**Step 2: 在每個建構點加 `dataQualityRepo` 參數**

provider 端先用一個 NoOp 實作（Phase 3 Task 10 換成真實 repo）：

```dart
class _NoopDataQualityRepo implements PartnerDataQualityRepoView {
  @override
  bool isFlaggedUnresolved(String partnerId) => false;
}
```

掛進 provider：

```dart
final partnerContextResolverProvider = Provider<PartnerContextResolver>((ref) {
  return PartnerContextResolver(
    partnerRepo: ref.watch(partnerRepoProvider),
    conversationRepo: ref.watch(conversationRepoProvider),
    summaryBuilder: PartnerSummaryBuilder(),
    dataQualityRepo: _NoopDataQualityRepo(), // Phase 3 Task 10 換成 PartnerDataQualityRepository
  );
});
```

**Step 3: Run all unit tests**

```bash
flutter test test/unit/features/analysis/
```
Expected: 全綠。

**Step 4: Commit**

```bash
git add lib/features/analysis/data/providers/analysis_providers.dart
git commit -m "[feat] analysis providers 注入 NoopDataQualityRepo（Phase 3 換真實實作）"
git push
```

---

### Task 5: Phase 1 驗證 + 標記

**Step 1: Run perimeter**

```bash
flutter test test/unit/features/analysis/
flutter analyze --no-fatal-infos lib/features/analysis/ test/unit/features/analysis/
```
Expected: 全綠、0 issues。

**Step 2: 在 plan doc 插入 Phase 1 完成標記（不 commit；累積到 Task 23）**

無 commit；下一 phase 開始。

---

## Phase 2 — Hive 整合

### Task 6: `PartnerDataQualityState` 與 `NamePair` 域 entity（含 Hive annotations）

**Files:**
- Create: `lib/features/user_profile/domain/entities/partner_data_quality_state.dart`
- Test: `test/unit/features/user_profile/domain/partner_data_quality_state_test.dart`

**Step 1: Write failing tests**

```dart
group('NamePair', () {
  test('canonicalizes to lower-case sorted pair', () {
    final p = NamePair.canonical('May', 'Anna');
    expect(p.first, 'anna');
    expect(p.second, 'may');
  });
  test('rejects empty names', () {
    expect(() => NamePair.canonical('', 'May'), throwsArgumentError);
  });
  test('equality is order-independent', () {
    expect(NamePair.canonical('Anna', 'May'), NamePair.canonical('May', 'Anna'));
  });
});

group('PartnerDataQualityState', () {
  test('defaults to empty confirmed pairs', () {
    final s = PartnerDataQualityState.empty('p1', updatedAt: DateTime(2026, 5, 1));
    expect(s.partnerId, 'p1');
    expect(s.confirmedSamePersonPairs, isEmpty);
  });
  test('confirmsSamePerson is true after marking', () {
    final s = PartnerDataQualityState.empty('p1', updatedAt: DateTime(2026, 5, 1))
      .withConfirmed(NamePair.canonical('Anna', 'May'), at: DateTime(2026, 5, 1));
    expect(s.confirmsSamePerson(NamePair.canonical('May', 'Anna')), isTrue);
    expect(s.confirmsSamePerson(NamePair.canonical('Anna', 'Lily')), isFalse);
  });
});
```

**Step 2: Run failing**

```bash
flutter test test/unit/features/user_profile/domain/partner_data_quality_state_test.dart
```
Expected: FAIL — undefined.

**Step 3: Implement entity**

```dart
import 'package:hive_ce/hive_ce.dart';

part 'partner_data_quality_state.g.dart';

@HiveType(typeId: 15)
class NamePair {
  @HiveField(0) final String first;
  @HiveField(1) final String second;

  const NamePair._(this.first, this.second);

  factory NamePair.canonical(String a, String b) {
    final na = a.trim().toLowerCase();
    final nb = b.trim().toLowerCase();
    if (na.isEmpty || nb.isEmpty) {
      throw ArgumentError('NamePair: names must be non-empty');
    }
    final sorted = [na, nb]..sort();
    return NamePair._(sorted[0], sorted[1]);
  }

  @override
  bool operator ==(Object o) =>
      o is NamePair && o.first == first && o.second == second;
  @override
  int get hashCode => Object.hash(first, second);
}

@HiveType(typeId: 14)
class PartnerDataQualityState {
  @HiveField(0) final String partnerId;
  @HiveField(1) final List<NamePair> confirmedSamePersonPairs;
  @HiveField(2) final DateTime updatedAt;

  const PartnerDataQualityState({
    required this.partnerId,
    required this.confirmedSamePersonPairs,
    required this.updatedAt,
  });

  factory PartnerDataQualityState.empty(String partnerId, {required DateTime updatedAt}) =>
      PartnerDataQualityState(
        partnerId: partnerId,
        confirmedSamePersonPairs: const [],
        updatedAt: updatedAt,
      );

  bool confirmsSamePerson(NamePair pair) =>
      confirmedSamePersonPairs.contains(pair);

  PartnerDataQualityState withConfirmed(NamePair pair, {required DateTime at}) {
    if (confirmsSamePerson(pair)) return this;
    return PartnerDataQualityState(
      partnerId: partnerId,
      confirmedSamePersonPairs: [...confirmedSamePersonPairs, pair],
      updatedAt: at,
    );
  }
}
```

**Step 4: Run codegen**

```bash
dart run build_runner build --delete-conflicting-outputs
```

**Step 5: Run tests + analyze**

```bash
flutter test test/unit/features/user_profile/domain/partner_data_quality_state_test.dart
flutter analyze --no-fatal-infos lib/features/user_profile/domain/entities/partner_data_quality_state.dart
```
Expected: PASS / 0 issues.

**Step 6: Commit**

```bash
git add lib/features/user_profile/domain/entities/partner_data_quality_state.dart \
        lib/features/user_profile/domain/entities/partner_data_quality_state.g.dart \
        test/unit/features/user_profile/domain/partner_data_quality_state_test.dart
git commit -m "[feat] PartnerDataQualityState + NamePair entity (typeId 14/15)"
git push
```

> **Note**: Spec design §7.4 寫 typeId = 14；本檔細分後 14 = `PartnerDataQualityState`，15 = `NamePair`（List 內 Hive 物件需獨立 typeId）。下個可用 typeId = 16。

---

### Task 7: 註冊 Hive adapters

**Files:**
- Modify: `lib/core/services/storage_service.dart`（adapter registration）
- Reference: 沿用 Spec 2 PartnerStyleOverride 註冊 pattern

**Step 1: Find adapter registration block**

```bash
grep -n "registerAdapter" lib/core/services/storage_service.dart
```

**Step 2: 加 adapter 註冊**

於 `Hive.registerAdapter(PartnerStyleOverrideAdapter());` 之後加：

```dart
Hive.registerAdapter(PartnerDataQualityStateAdapter());
Hive.registerAdapter(NamePairAdapter());
```

**Step 3: Run hive init test**

```bash
flutter test test/unit/services/storage_service_init_test.dart
```
（若該檔不存在則 skip 此驗證，下個 task 的 box wiring 測會涵蓋）

**Step 4: Commit**

```bash
git add lib/core/services/storage_service.dart
git commit -m "[feat] StorageService 註冊 PartnerDataQualityState/NamePair adapters"
git push
```

---

### Task 8: StorageService 開 `partner_data_quality_states` 加密 box + clearAll cascade

**Files:**
- Modify: `lib/core/services/storage_service.dart`
- Test: `test/unit/services/storage_service_clear_all_test.dart`（既有檔擴張）

**Step 1: Write failing test**

```dart
test('clearAll() purges partner_data_quality_states box', () async {
  // setup：put 一筆 state
  StorageService.partnerDataQualityStatesBox.put('p1',
    PartnerDataQualityState.empty('p1', updatedAt: DateTime(2026, 5, 1)));
  await StorageService.clearAll();
  expect(StorageService.partnerDataQualityStatesBox.isEmpty, isTrue);
});
```

**Step 2: Run failing**

```bash
flutter test test/unit/services/storage_service_clear_all_test.dart
```
Expected: FAIL — `partnerDataQualityStatesBox` undefined.

**Step 3: Implement**

於 `partnerStyleOverridesBox` getter 後加：

```dart
static Box<PartnerDataQualityState> get partnerDataQualityStatesBox =>
    Hive.box<PartnerDataQualityState>('partner_data_quality_states');
```

於 `initialize()`（或開箱處）加：

```dart
await Hive.openBox<PartnerDataQualityState>(
  'partner_data_quality_states',
  encryptionCipher: HiveAesCipher(_encryptionKey),
);
```

於 `clearAll()` 加：

```dart
await partnerDataQualityStatesBox.clear();
```

**Step 4: Run tests + analyze**

```bash
flutter test test/unit/services/storage_service_clear_all_test.dart
flutter analyze --no-fatal-infos lib/core/services/storage_service.dart
```
Expected: PASS / 0 issues.

**Step 5: Commit**

```bash
git add lib/core/services/storage_service.dart \
        test/unit/services/storage_service_clear_all_test.dart
git commit -m "[feat] StorageService 開 partner_data_quality_states 加密 box + clearAll 連動"
git push
```

---

### Task 9: Phase 2 驗證

```bash
flutter test test/unit/features/user_profile/ test/unit/services/
flutter analyze --no-fatal-infos lib test
```
Expected: 全綠 / 0 issues。

---

## Phase 3 — Repository + Cascade

### Task 10: `PartnerDataQualityRepository`（含 `PartnerDataQualityRepoView` impl）

**Files:**
- Create: `lib/features/user_profile/data/repositories/partner_data_quality_repository.dart`
- Test: `test/unit/features/user_profile/data/partner_data_quality_repository_test.dart`

**Step 1: Write failing tests**

```dart
group('PartnerDataQualityRepository', () {
  test('load returns empty state when none stored', () { /* ... */ });
  test('save persists state', () { /* ... */ });
  test('delete removes state', () { /* ... */ });
  test('markSamePerson appends NamePair to confirmed list', () { /* ... */ });
  test('isFlaggedUnresolved returns false when no candidate names', () { /* ... */ });
  test('isFlaggedUnresolved returns true when 2 unconfirmed names', () { /* ... */ });
  test('isFlaggedUnresolved returns false after marking same person', () { /* ... */ });
});
```

**Step 2: Implement**

```dart
class PartnerDataQualityRepository implements PartnerDataQualityRepoView {
  PartnerDataQualityRepository({Box<PartnerDataQualityState>? injectedBox})
      : _injectedBox = injectedBox;

  final Box<PartnerDataQualityState>? _injectedBox;
  Box<PartnerDataQualityState> get _box =>
      _injectedBox ?? StorageService.partnerDataQualityStatesBox;

  PartnerDataQualityState load(String partnerId) =>
      _box.get(partnerId) ??
      PartnerDataQualityState.empty(partnerId, updatedAt: DateTime.now());

  Future<void> save(PartnerDataQualityState state) async {
    await _box.put(state.partnerId, state);
  }

  Future<void> delete(String partnerId) async {
    await _box.delete(partnerId);
  }

  Future<void> markSamePerson(String partnerId, NamePair pair) async {
    final current = load(partnerId);
    final updated = current.withConfirmed(pair, at: DateTime.now());
    await save(updated);
  }

  /// Read-only flag check — used by [PartnerContextResolver].
  /// Implementation 注意：此函式查 confirmedSamePersonPairs 與 detection
  /// 算出的 candidate name pair。candidate detection 在 Phase 4 完成；
  /// 本 task 先實作純查詢路徑（candidates injection 走 detector provider）。
  @override
  bool isFlaggedUnresolved(String partnerId) {
    // Phase 4 偵測引擎完成後改為查 detector provider；
    // 本 task 先回 false，讓 Phase 1 整合測試保持綠（NoopDataQualityRepo 路徑等價）。
    return false;
  }
}
```

> **Note**: `isFlaggedUnresolved` 真實偵測邏輯在 Phase 4 Task 16（`dataQualityFlagProvider`）完成；本 task 先建好 storage CRUD 與骨架，避免一次改太大塊。

**Step 3: Wire into provider（替換 Task 4 的 NoopDataQualityRepo）**

修改 `lib/features/analysis/data/providers/analysis_providers.dart`：

```dart
final partnerDataQualityRepoProvider = Provider<PartnerDataQualityRepository>((ref) {
  return PartnerDataQualityRepository();
});

final partnerContextResolverProvider = Provider<PartnerContextResolver>((ref) {
  return PartnerContextResolver(
    partnerRepo: ref.watch(partnerRepoProvider),
    conversationRepo: ref.watch(conversationRepoProvider),
    summaryBuilder: PartnerSummaryBuilder(),
    dataQualityRepo: ref.watch(partnerDataQualityRepoProvider),
  );
});
```

**Step 4: Run tests + analyze**

```bash
flutter test test/unit/features/user_profile/data/partner_data_quality_repository_test.dart \
              test/unit/features/analysis/services/partner_context_resolver_test.dart
flutter analyze --no-fatal-infos lib test
```
Expected: PASS / 0 issues.

**Step 5: Commit**

```bash
git add lib/features/user_profile/data/repositories/partner_data_quality_repository.dart \
        lib/features/analysis/data/providers/analysis_providers.dart \
        test/unit/features/user_profile/data/partner_data_quality_repository_test.dart
git commit -m "[feat] PartnerDataQualityRepository CRUD + 取代 NoopDataQualityRepo"
git push
```

---

### Task 11: Partner delete cascade — 清 quality state

**Files:**
- Modify: `lib/features/partner/data/repositories/partner_repository.dart`
- Test: `test/unit/features/partner/repositories/partner_repository_cascade_test.dart`（既有檔擴張）

**Step 1: Write failing test**

```dart
test('delete cascades to PartnerDataQualityRepository', () async {
  // setup partner + 一筆 quality state
  // call repo.delete(partnerId)
  // expect quality state 被清除
});
```

**Step 2: Implement**

仿 `_styleRepo` lazy injection：

```dart
PartnerDataQualityRepository get _qualityRepo =>
    _injectedQualityRepo ?? PartnerDataQualityRepository();
```

於 `delete()` 末尾加：

```dart
await _qualityRepo.delete(partnerId);
```

**Step 3: Run + commit**

```bash
flutter test test/unit/features/partner/repositories/partner_repository_cascade_test.dart
git add lib/features/partner/data/repositories/partner_repository.dart \
        test/unit/features/partner/repositories/partner_repository_cascade_test.dart
git commit -m "[feat] Partner delete cascade 清 partner_data_quality_state"
git push
```

---

### Task 12: Partner merge cascade — 清 source 的 quality state

**Files:**
- Modify: `lib/features/partner/data/repositories/partner_repository.dart`
- Test: `test/unit/features/partner/repositories/partner_repository_merge_test.dart`（既有檔擴張）

**Step 1: Write failing test**

```dart
test('merge cascades quality state cleanup on source partner', () async {
  // setup A + B partners, A 有 quality state, B 有 quality state
  // call repo.merge(fromId: A, toId: B)
  // expect A 的 quality state 被清；B 的 quality state 仍保留
});
```

**Step 2: Implement**

於 `merge()` 末尾、`await _box.delete(fromId);` 之後、`await _styleRepo.delete(fromId);` 之後加：

```dart
await _qualityRepo.delete(fromId);
```

**Step 3: Run + commit**

```bash
flutter test test/unit/features/partner/repositories/partner_repository_merge_test.dart
git add lib/features/partner/data/repositories/partner_repository.dart \
        test/unit/features/partner/repositories/partner_repository_merge_test.dart
git commit -m "[feat] Partner merge cascade 清 source partner data quality state"
git push
```

---

### Task 13: Partner split — 新 cascade 路徑（**獨立測試，不類比 merge per Eric directive #5**）

**Files:**
- Modify: `lib/features/partner/data/repositories/partner_repository.dart`
- Create: `test/unit/features/partner/repositories/partner_repository_split_test.dart`

**Step 1: Write failing tests（獨立 split path 測試）**

```dart
group('PartnerRepository.split', () {
  test('moves only conversations matching the new-partner name', () async { /* ... */ });
  test('source partner keeps its name + style override', () async { /* ... */ });
  test('new partner has empty PartnerStyleOverride (走 global About Me)', () async { /* ... */ });
  test('source partner keeps its data-quality state (confirmed pairs 仍對源卡有意義)', () async { /* ... */ });
  test('new partner has empty data-quality state', () async { /* ... */ });
  test('throws when matching conversation list is empty (no-op guard)', () async { /* ... */ });
  test('mixed-name conversation stays on source (per design §6.3)', () async { /* ... */ });
});
```

**Step 2: Implement `split()`**

於 `PartnerRepository` 加：

```dart
/// Split conversations matching [matchedConversationIds] from [sourcePartnerId]
/// to a freshly-created partner with [newPartnerName].
///
/// Per Spec 3 §6.3:
///   - Source keeps its name + PartnerStyleOverride + PartnerDataQualityState
///   - New partner gets empty override + empty data-quality state
///   - Mixed-name conversations are NOT moved (caller pre-filters)
///   - Caller must confirm; this method does no AI judgment
///
/// Returns the new partner's id.
Future<String> split({
  required String sourcePartnerId,
  required String newPartnerName,
  required List<String> matchedConversationIds,
  required PartnerIdFactory idFactory,
}) async {
  if (matchedConversationIds.isEmpty) {
    throw ArgumentError('split: matchedConversationIds must be non-empty');
  }
  final source = _box.get(sourcePartnerId);
  if (source == null) {
    throw ArgumentError('split: source partner not found');
  }

  final newId = idFactory.generate();
  final now = DateTime.now();
  final newPartner = Partner(
    id: newId,
    name: newPartnerName,
    ownerUserId: source.ownerUserId,
    createdAt: now,
    updatedAt: now,
  );
  await _box.put(newId, newPartner);

  for (final convId in matchedConversationIds) {
    final c = _conversationBox.get(convId);
    if (c != null && c.partnerId == sourcePartnerId) {
      c.partnerId = newId;
      await c.save();
    }
  }

  // 不 cascade 拷貝 style override（per G3：override 留原卡）
  // 不 cascade 拷貝 data-quality state（per §7.6：source 保留 confirmed pairs；new = empty）
  return newId;
}
```

**Step 3: Run + commit**

```bash
flutter test test/unit/features/partner/repositories/partner_repository_split_test.dart
git add lib/features/partner/data/repositories/partner_repository.dart \
        test/unit/features/partner/repositories/partner_repository_split_test.dart
git commit -m "[feat] PartnerRepository.split — 新 cascade 路徑（獨立測試，不類比 merge）"
git push
```

---

## Phase 4 — Detection Engine

### Task 14: Name candidate extractor — `Conversation.name` placeholder filter

**Files:**
- Create: `lib/features/user_profile/domain/services/name_candidate_extractor.dart`
- Test: `test/unit/features/user_profile/domain/name_candidate_extractor_test.dart`

**Step 1: Write failing tests — placeholder rejection**

```dart
group('NameCandidateExtractor.fromConversationName', () {
  test('rejects 新對話 / 新的對話 / 互動紀錄 / 第 X 段 / 空字串', () {
    for (final placeholder in ['新對話', '新的對話', '互動紀錄', '第 1 段', '第3段', '', '   ']) {
      expect(extractor.fromConversationName(placeholder), isNull,
          reason: 'should reject "$placeholder"');
    }
  });
  test('rejects pure date-like titles', () {
    for (final s in ['2026/05/01', '5月1日', '2026-05-01']) {
      expect(extractor.fromConversationName(s), isNull, reason: s);
    }
  });
  test('accepts looks-like-person-name', () {
    expect(extractor.fromConversationName('Anna'), 'anna');
    expect(extractor.fromConversationName('小明'), '小明');
    expect(extractor.fromConversationName('Anna Smith'), 'anna smith');
  });
  test('rejects long sentences (not name-like)', () {
    expect(extractor.fromConversationName('我跟她聊天'), isNull);
  });
});
```

**Step 2: Implement extractor**

```dart
class NameCandidateExtractor {
  static const _placeholders = {'新對話', '新的對話', '互動紀錄'};
  static final _segmentPattern = RegExp(r'^第\s*\d+\s*段$');
  static final _datePattern = RegExp(r'^\d{4}[-/]\d{1,2}[-/]\d{1,2}$|^\d{1,2}月\d{1,2}日$');
  static const _maxNameLen = 20; // 超過視為句子，不採用

  String? fromConversationName(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.isEmpty) return null;
    if (_placeholders.contains(s)) return null;
    if (_segmentPattern.hasMatch(s)) return null;
    if (_datePattern.hasMatch(s)) return null;
    if (s.length > _maxNameLen) return null;
    return s.toLowerCase();
  }
}
```

**Step 3: Run + commit**

```bash
flutter test test/unit/features/user_profile/domain/name_candidate_extractor_test.dart
git add lib/features/user_profile/domain/services/name_candidate_extractor.dart \
        test/unit/features/user_profile/domain/name_candidate_extractor_test.dart
git commit -m "[feat] NameCandidateExtractor — Conversation.name placeholder filter"
git push
```

---

### Task 15: Name candidate extractor — message regex fallback（前 5 + 後 5 incoming，極窄）

**Files:**
- Modify: `lib/features/user_profile/domain/services/name_candidate_extractor.dart`
- Modify: `test/unit/features/user_profile/domain/name_candidate_extractor_test.dart`

**Step 1: Write failing tests**

```dart
group('NameCandidateExtractor.fromMessages', () {
  test('only scans 前 5 + 後 5 incoming messages', () { /* ... */ });
  test('ignores outgoing (isFromMe) messages', () { /* ... */ });
  test('matches "我叫 X" / "Hi I\'m X" / "Call me X"', () { /* ... */ });
  test('does NOT do full-text NER (e.g. "她是 May" 不抽 May)', () {
    // 確保極窄 regex，不全文掃
  });
  test('returns null when no incoming match', () { /* ... */ });
});
```

**Step 2: Implement**

```dart
extension on NameCandidateExtractor {
  // ...
  String? fromMessages(List<Message> messages, {int n = 5}) {
    final incoming = messages.where((m) => !m.isFromMe).toList();
    if (incoming.isEmpty) return null;

    // 前 N + 後 N（去重，若總數 ≤ 2N 全用）
    final sample = incoming.length <= 2 * n
        ? incoming
        : [...incoming.take(n), ...incoming.skip(incoming.length - n)];

    final patterns = [
      RegExp(r'我叫\s*([一-龥A-Za-z]{2,10})'),
      RegExp(r"(?:Hi,?\s*)?I[''']?m\s+([A-Za-z]{2,15})", caseSensitive: false),
      RegExp(r'Call\s+me\s+([A-Za-z]{2,15})', caseSensitive: false),
    ];

    for (final m in sample) {
      for (final p in patterns) {
        final match = p.firstMatch(m.content);
        if (match != null) return match.group(1)!.toLowerCase();
      }
    }
    return null;
  }
}
```

**Step 3: Run + commit**

```bash
flutter test test/unit/features/user_profile/domain/name_candidate_extractor_test.dart
git add lib/features/user_profile/domain/services/name_candidate_extractor.dart \
        test/unit/features/user_profile/domain/name_candidate_extractor_test.dart
git commit -m "[feat] NameCandidateExtractor — 前 5 後 5 incoming regex fallback"
git push
```

---

### Task 16: Cross-conversation comparator + `dataQualityFlagProvider`

**Files:**
- Create: `lib/features/user_profile/data/providers/data_quality_flag_provider.dart`
- Test: `test/unit/features/user_profile/data/data_quality_flag_provider_test.dart`

**Step 1: Write failing tests**

```dart
group('dataQualityFlagProvider(partnerId)', () {
  test('returns unflagged when conversations have only 1 candidate name', () { /* ... */ });
  test('returns unflagged when all conversations have null candidate', () { /* ... */ });
  test('returns flagged when ≥ 2 distinct candidates and not in confirmed pairs', () { /* ... */ });
  test('returns unflagged when the two candidates are in confirmed pairs', () { /* ... */ });
  test('returns flagged with conflicting NamePair when 3rd new name appears', () { /* ... */ });
});
```

**Step 2: Implement Provider.family**

```dart
class DataQualityFlag {
  final bool isFlagged;
  final NamePair? conflictingPair;
  const DataQualityFlag.unflagged()
      : isFlagged = false, conflictingPair = null;
  const DataQualityFlag.flagged(this.conflictingPair) : isFlagged = true;
}

final dataQualityFlagProvider =
    Provider.family<DataQualityFlag, String>((ref, partnerId) {
  final conversations = ref.watch(conversationsByPartnerProvider(partnerId));
  final qualityState = ref.watch(partnerDataQualityRepoProvider).load(partnerId);
  final extractor = NameCandidateExtractor();

  final candidates = <String>{};
  for (final c in conversations) {
    final name = extractor.fromConversationName(c.name) ??
                 extractor.fromMessages(c.messages);
    if (name != null) candidates.add(name);
  }

  if (candidates.length < 2) return const DataQualityFlag.unflagged();

  final list = candidates.toList()..sort();
  for (var i = 0; i < list.length; i++) {
    for (var j = i + 1; j < list.length; j++) {
      final pair = NamePair.canonical(list[i], list[j]);
      if (!qualityState.confirmsSamePerson(pair)) {
        return DataQualityFlag.flagged(pair);
      }
    }
  }
  return const DataQualityFlag.unflagged();
});
```

**Step 3: 連回 `PartnerDataQualityRepository.isFlaggedUnresolved`**

```dart
// 在 repo 把 isFlaggedUnresolved 改為去 ref.read provider — 但 repo 不該 know about Riverpod
// 解法：在 analysis_providers.dart 包一層 view-adapter
final partnerDataQualityRepoViewProvider =
    Provider<PartnerDataQualityRepoView>((ref) {
  return _ProviderBackedDataQualityRepoView(ref);
});

class _ProviderBackedDataQualityRepoView implements PartnerDataQualityRepoView {
  _ProviderBackedDataQualityRepoView(this._ref);
  final Ref _ref;
  @override
  bool isFlaggedUnresolved(String partnerId) =>
      _ref.read(dataQualityFlagProvider(partnerId)).isFlagged;
}
```

並把 `partnerContextResolverProvider` 換成 watch 這個 view provider。

**Step 4: Run + commit**

```bash
flutter test test/unit/features/user_profile/data/data_quality_flag_provider_test.dart
git add lib/features/user_profile/data/providers/data_quality_flag_provider.dart \
        lib/features/analysis/data/providers/analysis_providers.dart \
        test/unit/features/user_profile/data/data_quality_flag_provider_test.dart
git commit -m "[feat] dataQualityFlagProvider 串到 PartnerContextResolver gating"
git push
```

---

### Task 17: invalidate-on-save wiring

**Files:**
- Modify: `lib/features/conversation/data/providers/conversation_write_controller.dart`（save 後 invalidate `dataQualityFlagProvider(partnerId)`）

**Step 1: Find write hook**

```bash
grep -n "save\|invalidate\|partnerId" lib/features/conversation/data/providers/conversation_write_controller.dart
```

**Step 2: 在 conversation save 完成後加**

```dart
ref.invalidate(dataQualityFlagProvider(savedConversation.partnerId));
```

（具體位置依 controller 結構調整）

**Step 3: Test — write triggers invalidate**

簡單 ProviderContainer test：mock save → expect provider 被 invalidate。

**Step 4: Run + commit**

```bash
flutter test test/unit/features/conversation/data/conversation_write_controller_test.dart
git commit -m "[feat] conversation save 後 invalidate dataQualityFlagProvider"
git push
```

---

## Phase 5 — UI

### Task 18: `PartnerDataQualityBanner` widget

**Files:**
- Create: `lib/features/partner/presentation/widgets/partner_data_quality_banner.dart`
- Test: `test/widget/features/partner/partner_data_quality_banner_test.dart`
- Reference: `lib/features/partner/presentation/widgets/same_name_dedupe_banner.dart`（reuse visual lineage）

**Step 1: Write failing widget tests**

```dart
testWidgets('shows two names + 同一人 + 拆成新對象 actions', (tester) async {
  await tester.pumpWidget(MaterialApp(home: PartnerDataQualityBanner(
    nameA: 'Anna',
    nameB: 'May',
    onMarkSamePerson: () {},
    onSplit: () {},
  )));
  expect(find.textContaining('Anna'), findsOneWidget);
  expect(find.textContaining('May'), findsOneWidget);
  expect(find.text('這是同一人'), findsOneWidget);
  expect(find.text('拆成新對象'), findsOneWidget);
});

testWidgets('does NOT use 紅色 / 警告 / 異常 / ⚠️', (tester) async {
  // assert no red color tokens, no warning glyphs in tree
});
```

**Step 2: Implement**

仿 `SameNameDedupeBanner` 的 glassmorphic structure，文案見 design §4.2 / §4.3。

**Step 3: Run + commit**

```bash
flutter test test/widget/features/partner/partner_data_quality_banner_test.dart
git add lib/features/partner/presentation/widgets/partner_data_quality_banner.dart \
        test/widget/features/partner/partner_data_quality_banner_test.dart
git commit -m "[feat] PartnerDataQualityBanner widget (sibling of SameNameDedupeBanner)"
git push
```

---

### Task 19: Partner detail 整合 banner

**Files:**
- Modify: `lib/features/partner/presentation/screens/partner_detail_screen.dart`

**Step 1: Wire `dataQualityFlagProvider` consumer**

於 traits / summary 區段附近（per design §4.5），加 banner conditional rendering：

```dart
final flag = ref.watch(dataQualityFlagProvider(partner.id));
if (flag.isFlagged && flag.conflictingPair != null)
  PartnerDataQualityBanner(
    nameA: flag.conflictingPair!.first,
    nameB: flag.conflictingPair!.second,
    onMarkSamePerson: () => _handleMarkSamePerson(ref, partner.id, flag.conflictingPair!),
    onSplit: () => _handleSplit(context, ref, partner, flag.conflictingPair!),
  ),
```

**Step 2: Widget integration test**

開新測試或擴張 `partner_detail_screen_test.dart`，確認 flagged partner detail 顯示 banner。

**Step 3: Commit**

```bash
git commit -m "[feat] PartnerDetailScreen 整合 PartnerDataQualityBanner（traits 附近）"
git push
```

---

### Task 20: 「這是同一人」action handler

**Step 1: Implement `_handleMarkSamePerson`**

```dart
Future<void> _handleMarkSamePerson(WidgetRef ref, String partnerId, NamePair pair) async {
  await ref.read(partnerDataQualityRepoProvider).markSamePerson(partnerId, pair);
  ref.invalidate(dataQualityFlagProvider(partnerId));
}
```

**Step 2: Widget test — tap 後 banner 收掉**

**Step 3: Commit**

```bash
git commit -m "[feat] 這是同一人 action — markSamePerson + invalidate"
git push
```

---

### Task 21: 「拆成新對象」action handler + 確認流程

**Step 1: 拆卡確認 dialog**

顯示「Anna 留在原卡 / May 移到新卡 → 確認 / 取消」。

**Step 2: 確認後執行**

```dart
Future<void> _handleSplit(...) async {
  final confirmed = await _showSplitConfirmDialog(...);
  if (!confirmed) return;
  final matchedIds = _filterConvsMatchingName(conversations, pair.second);
  if (matchedIds.isEmpty) return; // 退化保護
  await ref.read(partnerRepoProvider).split(
    sourcePartnerId: partner.id,
    newPartnerName: pair.second,
    matchedConversationIds: matchedIds,
    idFactory: PartnerIdFactory(),
  );
  // refresh provider
  ref.invalidate(partnersProvider);
  ref.invalidate(dataQualityFlagProvider(partner.id));
}
```

**Step 3: Widget test — 拆卡後 banner 收掉、conversations 搬到新卡**

**Step 4: Commit**

```bash
git commit -m "[feat] 拆成新對象 action — confirm dialog + repo.split + provider invalidation"
git push
```

---

## Phase 6 — Verification

### Task 22: lint + perimeter + full suite

```bash
flutter analyze --no-fatal-infos lib test
flutter test test/unit/features/user_profile/ \
              test/unit/features/partner/ \
              test/unit/features/analysis/ \
              test/widget/features/partner/
flutter test  # full suite
```

**Pass criteria（per CLAUDE.md / Spec 1, 2 baseline）:**
- analyze 0 issues on lib + test
- Spec 3 perimeter green（含 P1–P5 amendment 對應的所有測試）
- Full suite: 0 new regressions vs baseline 76 stale (post Spec 2)

---

### Task 23: Plan doc Status block + commit

**Files:**
- Modify: `docs/plans/2026-05-01-spec3-data-quality-guard-impl.md`（本檔）

**加入末段：**

```markdown
---

## Status: SHIPPED — 2026-05-01

| Phase | Tasks | Final commits |
|---|---|---|
| 1. Resolver gating | 1–5 | <hashes> |
| 2. Hive 整合 | 6–9 | <hashes> |
| 3. Repository + cascade | 10–13 | <hashes> |
| 4. 偵測引擎 | 14–17 | <hashes> |
| 5. UI | 18–21 | <hashes> |
| 6. Verification | 22–23 | <hashes> |

**Verification**:
- analyze: 0 issues
- Spec 3 perimeter: <X>/<X> green
- Full repo: <pass>/<stale> (baseline 76, 0 new regressions)
```

**Commit + push**

```bash
git commit -m "[chore] Spec 3 ship — impl plan status update"
git push
```

---

## TF Smoke Checklist Spec 3 §1–8（送 Eric / Bruce 跑）

1. 建立兩段聊天用不同名字 → 進 Partner detail → banner 顯示「Anna / May」+ 兩個 action
2. 點「這是同一人」→ banner 立即收掉、再次進入 detail 仍不顯示
3. 加第三段含第三個新名字（e.g. Lily）→ banner 重新顯示「Anna / Lily」（同一人 confirmed pair 不誤判）
4. 點「拆成新對象」→ confirm dialog → 確認 → 新對象卡建立、聊天搬過去、原卡 banner 收掉
5. 拆卡後新卡 PartnerStyleOverride 為空（走 global About Me）→ 進 Partner Style Edit 看 placeholder 走全域
6. flagged-unresolved 狀態下，分析新訊息 → AI 回覆內容**不應**引用其他段聊天的特質 / 興趣（resolver gating 生效）
7. mark same-person 後，再分析新訊息 → AI 回覆**恢復**引用 aggregate
8. 設定 → 清除帳號 → 進 Partner detail（資料已清）→ 不應看到 banner / 不應 crash

---

## Open Questions（從 design §11，implementation 階段需處理或記錄）

- §11.2 「明顯不同」normalize 規則 — 目前 implementation 用 lowercase + trim，若 TF 看到「Anna / Anne」誤觸再加 Levenshtein 距離 filter（Phase 4 後評估）
- §11.3 banner 顯示時機 race — `dataQualityFlagProvider` 是 sync `Provider.family`，無 loading state 閃爍
- §11.4 split atomic — 目前 split 不是原子；失敗 rollback 留 v2，v1 接受半搬狀態（用戶可手動再 split / merge 修正）
- §11.6 OCR provenance marker — v1 不加；implementation 階段確認 `Conversation.name` 不論來源都走 placeholder filter
- §11.7 in-memory cache — v1 不做；TF perf 數據後評估
