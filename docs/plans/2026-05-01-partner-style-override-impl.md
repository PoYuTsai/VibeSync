# Spec 2: Partner Style Override — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.
> **Design**: `2026-05-01-partner-style-override-design.md`
> **TF gate cleared**: Spec 1 TF smoke 已 PASS（Eric 2026-05-01 確認）

**Goal:** Partner-scoped style override（`interactionStyle` / `practiceGoals` / `notes`），on top of Spec 1 global About Me，per-field inherit fallback。UI = Partner detail inline card + 編輯畫面 with per-field reset link。**不寫 prompt impl**。

**Architecture:** 新 Hive entity `PartnerStyleOverride`（typeId 13），獨立 box `partner_style_overrides` keyed by partnerId。Pure-function `resolveEffectiveStyle()` per-field merge global UserProfile。Riverpod `partnerStyleOverrideProvider(partnerId)` family for CRUD，`effectiveStyleProvider(partnerId)` family 給 UI placeholder + 未來 prompt builder。Spec 1 `UserProfileRepository` 不動。

**Tech Stack:** Flutter 3.x、Riverpod（`AsyncNotifierProviderFamily` + `Provider.family`）、Hive CE（AES-256 encrypted）、Dart 3 immutable classes、`go_router`（新 route `/partner/:id/my-style`）。

---

## Implementation Sequence Overview

| Phase | Tasks | Approx 時間 |
|-------|-------|------------|
| 1. Domain entity | 1 | ~15 min |
| 2. Hive 整合 | 2-4 | ~25 min |
| 3. Data layer | 5-7 | ~40 min |
| 4. Resolver | 8-10 | ~30 min |
| 5. UI inline card | 11-13 | ~40 min |
| 6. UI edit screen | 14-18 | ~70 min |
| 7. Verification | 19-20 | ~20 min |

每個 task 走 TDD：Red → Green → Refactor → Commit。**一個 commit 一件事**，commit 後**立即 push**（CLAUDE.md global rule）。

---

## Phase 1 — Domain Entity

### Task 1: PartnerStyleOverride domain entity（無 Hive）

**Files:**
- Create: `lib/features/user_profile/domain/entities/partner_style_override.dart`
- Test: `test/unit/features/user_profile/domain/partner_style_override_test.dart`

**Step 1: Write failing tests**

```dart
// test/unit/features/user_profile/domain/partner_style_override_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  final ts = DateTime(2026, 5, 1);
  group('PartnerStyleOverride.create', () {
    test('should construct minimal override when only partnerId given', () {
      final ov = PartnerStyleOverride.create(partnerId: 'p1', updatedAt: ts);
      expect(ov.partnerId, 'p1');
      expect(ov.interactionStyle, isNull);
      expect(ov.practiceGoals, isEmpty);
      expect(ov.notes, isNull);
      expect(ov.isEmpty, isTrue);
    });

    test('should reject partnerId empty', () {
      expect(
        () => PartnerStyleOverride.create(partnerId: '', updatedAt: ts),
        throwsArgumentError,
      );
    });

    test('should reject practiceGoals exceeding max 3', () {
      expect(
        () => PartnerStyleOverride.create(
          partnerId: 'p1',
          practiceGoals: const [
            PracticeGoal.softInvite,
            PracticeGoal.reduceAnxiety,
            PracticeGoal.humorousReply,
            PracticeGoal.buildCloseness,
          ],
          updatedAt: ts,
        ),
        throwsArgumentError,
      );
    });

    test('should reject notes exceeding 100 chars', () {
      expect(
        () => PartnerStyleOverride.create(
          partnerId: 'p1',
          notes: 'x' * 101,
          updatedAt: ts,
        ),
        throwsArgumentError,
      );
    });

    test('should trim notes and treat empty as null', () {
      final ov = PartnerStyleOverride.create(
        partnerId: 'p1',
        notes: '   ',
        updatedAt: ts,
      );
      expect(ov.notes, isNull);
    });

    test('should mark isEmpty false when any field is set', () {
      final ov = PartnerStyleOverride.create(
        partnerId: 'p1',
        interactionStyle: InteractionStyle.steady,
        updatedAt: ts,
      );
      expect(ov.isEmpty, isFalse);
    });

    test('should make practiceGoals unmodifiable', () {
      final ov = PartnerStyleOverride.create(
        partnerId: 'p1',
        practiceGoals: const [PracticeGoal.softInvite],
        updatedAt: ts,
      );
      expect(() => ov.practiceGoals.add(PracticeGoal.reduceAnxiety),
          throwsUnsupportedError);
    });
  });
}
```

**Step 2: Run test, verify failure**

```bash
flutter test test/unit/features/user_profile/domain/partner_style_override_test.dart
```
Expected: 全部 fail（檔案不存在）。

**Step 3: Implement minimal entity**

```dart
// lib/features/user_profile/domain/entities/partner_style_override.dart
import 'package:flutter/foundation.dart';
import 'user_profile.dart'; // reuses InteractionStyle / PracticeGoal enums

@immutable
class PartnerStyleOverride {
  static const int maxPracticeGoals = 3;
  static const int maxNotesLength = 100;

  final String partnerId;
  final InteractionStyle? interactionStyle;
  final List<PracticeGoal> practiceGoals;
  final String? notes;
  final DateTime updatedAt;

  const PartnerStyleOverride({
    required this.partnerId,
    this.interactionStyle,
    this.practiceGoals = const [],
    this.notes,
    required this.updatedAt,
  });

  factory PartnerStyleOverride.create({
    required String partnerId,
    InteractionStyle? interactionStyle,
    List<PracticeGoal> practiceGoals = const [],
    String? notes,
    required DateTime updatedAt,
  }) {
    if (partnerId.isEmpty) {
      throw ArgumentError('partnerId must not be empty');
    }
    if (practiceGoals.length > maxPracticeGoals) {
      throw ArgumentError('practiceGoals exceeds max $maxPracticeGoals');
    }
    final n = notes?.trim();
    if (n != null && n.length > maxNotesLength) {
      throw ArgumentError('notes exceeds $maxNotesLength chars');
    }
    return PartnerStyleOverride(
      partnerId: partnerId,
      interactionStyle: interactionStyle,
      practiceGoals: List.unmodifiable(practiceGoals),
      notes: (n == null || n.isEmpty) ? null : n,
      updatedAt: updatedAt,
    );
  }

  bool get isEmpty =>
      interactionStyle == null && practiceGoals.isEmpty && notes == null;
}
```

**Step 4: Run tests, verify pass**

```bash
flutter test test/unit/features/user_profile/domain/partner_style_override_test.dart
```
Expected: 7/7 pass。

**Step 5: Commit + push**

```bash
git add lib/features/user_profile/domain/entities/partner_style_override.dart \
        test/unit/features/user_profile/domain/partner_style_override_test.dart
git commit -m "[feat] PartnerStyleOverride domain entity (no Hive yet)"
git push
```

---

## Phase 2 — Hive 整合

### Task 2: 加 Hive `@HiveType(13)` annotation + adapter codegen

**Files:**
- Modify: `lib/features/user_profile/domain/entities/partner_style_override.dart`
- Generated: `lib/features/user_profile/domain/entities/partner_style_override.g.dart`
- Modify: `lib/hive_registrar.g.dart`（codegen 自動更新）

**Step 1: 加 Hive annotations**

```dart
// 改 partner_style_override.dart
import 'package:flutter/foundation.dart';
import 'package:hive_ce/hive_ce.dart';
import 'user_profile.dart';

part 'partner_style_override.g.dart';

@immutable
@HiveType(typeId: 13)
class PartnerStyleOverride {
  // ... unchanged ...

  @HiveField(0) final String partnerId;
  @HiveField(1) final InteractionStyle? interactionStyle;
  @HiveField(2) final List<PracticeGoal> practiceGoals;
  @HiveField(3) final String? notes;
  @HiveField(4) final DateTime updatedAt;

  // ... rest unchanged ...
}
```

**Step 2: Run codegen**

```bash
dart run build_runner build --delete-conflicting-outputs
```
Expected: `partner_style_override.g.dart` 出現；`hive_registrar.g.dart` 自動更新。

**Step 3: Run domain tests，確認沒回歸**

```bash
flutter test test/unit/features/user_profile/domain/partner_style_override_test.dart
```
Expected: 7/7 pass。

**Step 4: Commit + push**

```bash
git add lib/features/user_profile/domain/entities/partner_style_override.dart \
        lib/features/user_profile/domain/entities/partner_style_override.g.dart \
        lib/hive_registrar.g.dart
git commit -m "[feat] PartnerStyleOverride Hive adapter (typeId 13)"
git push
```

---

### Task 3: StorageService 註冊 adapter + 開 box

**Files:**
- Modify: `lib/core/services/storage_service.dart`
- Test: `test/unit/services/storage_service_partner_style_override_test.dart`

**Step 1: Write failing test (lock test for box wiring)**

```dart
// test/unit/services/storage_service_partner_style_override_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';
import 'package:vibesync/core/services/storage_service.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';

void main() {
  setUp(() async => StorageService.initialize());
  tearDown(() async => Hive.deleteFromDisk());

  test('should expose partnerStyleOverridesBox after initialize', () {
    final box = StorageService.partnerStyleOverridesBox;
    expect(box, isA<Box<PartnerStyleOverride>>());
    expect(box.isOpen, isTrue);
  });
}
```

**Step 2: Run test, verify fail**

```bash
flutter test test/unit/services/storage_service_partner_style_override_test.dart
```
Expected: fail（getter 不存在）。

**Step 3: Wire in StorageService**

`lib/core/services/storage_service.dart`：
1. import: `import '../../features/user_profile/domain/entities/partner_style_override.dart';`
2. `initialize()` 內 register adapter（在 TopicSeedAdapter 後）：
   ```dart
   Hive.registerAdapter(PartnerStyleOverrideAdapter()); // typeId=13
   ```
3. `initialize()` 內 open box（在 `user_profile` box 後）：
   ```dart
   await Hive.openBox<PartnerStyleOverride>(
     'partner_style_overrides',
     encryptionCipher: HiveAesCipher(encryptionKey),
   );
   ```
4. 加 getter（在 `userProfileBox` getter 後）：
   ```dart
   static Box<PartnerStyleOverride> get partnerStyleOverridesBox =>
       Hive.box<PartnerStyleOverride>('partner_style_overrides');
   ```

**Step 4: Run test，pass**

```bash
flutter test test/unit/services/storage_service_partner_style_override_test.dart
```

**Step 5: Commit + push**

```bash
git add lib/core/services/storage_service.dart \
        test/unit/services/storage_service_partner_style_override_test.dart
git commit -m "[feat] StorageService 開 partner_style_overrides 加密 box"
git push
```

---

### Task 4: `clearAll()` 補清 + lock test

**Files:**
- Modify: `lib/core/services/storage_service.dart`（`clearAll` method）
- Test: `test/unit/services/storage_service_clear_all_test.dart`（已存在，加新斷言）

**Step 1: 加新測試 case**

`storage_service_clear_all_test.dart` 加：
```dart
test('clearAll should also clear partner_style_overrides box', () async {
  final box = StorageService.partnerStyleOverridesBox;
  await box.put('p1', PartnerStyleOverride.create(
    partnerId: 'p1',
    interactionStyle: InteractionStyle.steady,
    updatedAt: DateTime(2026, 5, 1),
  ));
  expect(box.isNotEmpty, isTrue);

  await StorageService.clearAll();

  expect(box.isEmpty, isTrue);
});
```

**Step 2: Run test, verify fail**

```bash
flutter test test/unit/services/storage_service_clear_all_test.dart
```
Expected: 該 case fail（clearAll 還沒清此 box）。

**Step 3: 改 clearAll**

`storage_service.dart` 的 `clearAll`：
```dart
static Future<void> clearAll() async {
  await conversationsBox.clear();
  await partnersBox.clear();
  await userProfileBox.clear();
  await partnerStyleOverridesBox.clear(); // ← Spec 2
  await settingsBox.clear();
  await usageBox.clear();
}
```

**Step 4: Run test，pass**

**Step 5: Commit + push**

```bash
git commit -am "[fix] clearAll 同步清 partner_style_overrides box"
git push
```

---

## Phase 3 — Data Layer

### Task 5: PartnerStyleRepository (load / save / delete / clearAll)

**Files:**
- Create: `lib/features/user_profile/data/repositories/partner_style_repository.dart`
- Test: `test/unit/features/user_profile/data/partner_style_repository_test.dart`

**Step 1: Write failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/user_profile/data/repositories/partner_style_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/partner_style_override.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  late Box<PartnerStyleOverride> box;
  late PartnerStyleRepository repo;

  setUp(() async {
    Hive.init('.test_hive_ps');
    if (!Hive.isAdapterRegistered(13)) {
      Hive.registerAdapter(PartnerStyleOverrideAdapter());
    }
    if (!Hive.isAdapterRegistered(10)) {
      Hive.registerAdapter(InteractionStyleAdapter());
    }
    if (!Hive.isAdapterRegistered(11)) {
      Hive.registerAdapter(PracticeGoalAdapter());
    }
    box = await Hive.openBox<PartnerStyleOverride>('test_pso');
    repo = PartnerStyleRepository(box: box);
  });

  tearDown(() async => Hive.deleteFromDisk());

  test('should return null when partner has no override', () async {
    expect(await repo.load('p1'), isNull);
  });

  test('should round-trip a saved override', () async {
    final ov = PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.humorous,
      practiceGoals: const [PracticeGoal.softInvite],
      notes: '慢熟',
      updatedAt: DateTime(2026, 5, 1),
    );
    await repo.save(ov);
    final loaded = await repo.load('p1');
    expect(loaded?.interactionStyle, InteractionStyle.humorous);
    expect(loaded?.notes, '慢熟');
  });

  test('should delete row when saving an isEmpty override', () async {
    final filled = PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.steady,
      updatedAt: DateTime(2026, 5, 1),
    );
    await repo.save(filled);
    expect(await repo.load('p1'), isNotNull);

    final empty = PartnerStyleOverride.create(
      partnerId: 'p1',
      updatedAt: DateTime(2026, 5, 1),
    );
    await repo.save(empty);

    expect(await repo.load('p1'), isNull);
  });

  test('should delete by partnerId', () async {
    await repo.save(PartnerStyleOverride.create(
      partnerId: 'p2',
      interactionStyle: InteractionStyle.gentle,
      updatedAt: DateTime(2026, 5, 1),
    ));
    await repo.delete('p2');
    expect(await repo.load('p2'), isNull);
  });

  test('clearAll should empty box', () async {
    await repo.save(PartnerStyleOverride.create(
      partnerId: 'p3',
      interactionStyle: InteractionStyle.direct,
      updatedAt: DateTime(2026, 5, 1),
    ));
    await repo.clearAll();
    expect(box.isEmpty, isTrue);
  });
}
```

**Step 2: Run test, verify fail（檔案不存在）**

**Step 3: Implement repository**

```dart
// lib/features/user_profile/data/repositories/partner_style_repository.dart
import 'package:hive_ce/hive_ce.dart';
import '../../domain/entities/partner_style_override.dart';

class PartnerStyleRepository {
  PartnerStyleRepository({required this.box});
  final Box<PartnerStyleOverride> box;

  Future<PartnerStyleOverride?> load(String partnerId) async {
    return box.get(partnerId);
  }

  /// Save override; if `override.isEmpty` 改為 delete 該 row 避免 box 殘留 empty entry。
  Future<void> save(PartnerStyleOverride override) async {
    if (override.isEmpty) {
      await box.delete(override.partnerId);
    } else {
      await box.put(override.partnerId, override);
    }
  }

  Future<void> delete(String partnerId) async {
    await box.delete(partnerId);
  }

  Future<void> clearAll() async {
    await box.clear();
  }
}
```

**Step 4: Run tests, all pass**

**Step 5: Commit + push**

```bash
git add lib/features/user_profile/data/repositories/partner_style_repository.dart \
        test/unit/features/user_profile/data/partner_style_repository_test.dart
git commit -m "[feat] PartnerStyleRepository load/save/delete with isEmpty cleanup"
git push
```

---

### Task 6: Cascade delete — `PartnerRepository.delete` 也清 override

**Files:**
- Modify: `lib/features/partner/data/repositories/partner_repository.dart`
- Test: `test/unit/features/partner/data/partner_repository_cascade_test.dart`

**Step 1: 先 grep 確認 PartnerRepository.delete 簽名**

```bash
grep -n "Future.*delete\|delete(" lib/features/partner/data/repositories/partner_repository.dart
```

**Step 2: Write failing test**

```dart
test('PartnerRepository.delete should also clear partner style override', () async {
  // setup: partner exists in partners box, override exists in pso box
  // act: partnerRepo.delete(partnerId)
  // assert: override gone
});
```

**Step 3: Inject PartnerStyleRepository (or pass cleanup callback)**

選一條（看現有 PartnerRepository 結構）：
- A) constructor 注入 `PartnerStyleRepository styleRepo` → `delete()` 內順手 `styleRepo.delete(id)`
- B) Provider 層在 partner delete 後 fire-and-forget invalidate `partnerStyleOverrideProvider(id)`

優先 A — 資料層 cascade 邏輯在 repo 層比 provider 層好定位（避免 partial state）。如果 PartnerRepository 已被多處 instantiate 改 constructor 太貴，再走 B。

**Step 4: Run test, pass**

**Step 5: Commit + push**

```bash
git commit -am "[feat] Partner delete cascade 清 partner style override"
git push
```

---

### Task 7: Riverpod `partnerStyleOverrideProvider(partnerId)` family

**Files:**
- Create: `lib/features/user_profile/data/providers/partner_style_providers.dart`
- Test: `test/unit/features/user_profile/data/partner_style_providers_test.dart`

**Step 1: Write failing tests**

涵蓋：
- 初始 load = null（no override）
- save → state 更新為新值
- saveEmpty → state 變回 null
- 兩個 partnerId 互不干擾

**Step 2: Run test, verify fail**

**Step 3: Implement provider**

```dart
// lib/features/user_profile/data/providers/partner_style_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/storage_service.dart';
import '../../domain/entities/partner_style_override.dart';
import '../repositories/partner_style_repository.dart';

final partnerStyleRepositoryProvider = Provider<PartnerStyleRepository>(
  (ref) => PartnerStyleRepository(box: StorageService.partnerStyleOverridesBox),
);

class PartnerStyleOverrideController
    extends FamilyAsyncNotifier<PartnerStyleOverride?, String> {
  @override
  Future<PartnerStyleOverride?> build(String partnerId) async {
    return ref.read(partnerStyleRepositoryProvider).load(partnerId);
  }

  Future<void> save(PartnerStyleOverride override) async {
    state = const AsyncValue.loading();
    final repo = ref.read(partnerStyleRepositoryProvider);
    await repo.save(override);
    state = AsyncValue.data(override.isEmpty ? null : override);
  }

  Future<void> clear() async {
    final partnerId = arg;
    state = const AsyncValue.loading();
    await ref.read(partnerStyleRepositoryProvider).delete(partnerId);
    state = const AsyncValue.data(null);
  }
}

final partnerStyleOverrideProvider =
    AsyncNotifierProvider.family<PartnerStyleOverrideController,
        PartnerStyleOverride?, String>(
      PartnerStyleOverrideController.new,
    );
```

**Step 4: Run tests, pass**

**Step 5: Commit + push**

```bash
git commit -am "[feat] partnerStyleOverrideProvider AsyncNotifier family"
git push
```

---

## Phase 4 — Resolver + EffectiveStyle

### Task 8: EffectiveStyle value object + resolveEffectiveStyle pure function

**Files:**
- Create: `lib/features/user_profile/domain/entities/effective_style.dart`
- Create: `lib/features/user_profile/domain/services/resolve_effective_style.dart`
- Test: `test/unit/features/user_profile/domain/resolve_effective_style_test.dart`

**Step 1: Write failing tests (cover all fallback combinations)**

```dart
group('resolveEffectiveStyle', () {
  final ts = DateTime(2026, 5, 1);
  final globalStyle = UserProfile.create(
    interactionStyle: InteractionStyle.steady,
    practiceGoals: const [PracticeGoal.softInvite],
    notes: 'global notes',
    updatedAt: ts,
  );

  test('should return all global when no partner override', () {
    final r = resolveEffectiveStyle(global: globalStyle, partner: null);
    expect(r.interactionStyle, InteractionStyle.steady);
    expect(r.practiceGoals, [PracticeGoal.softInvite]);
    expect(r.notes, 'global notes');
  });

  test('should override interactionStyle but inherit goals + notes', () {
    final partner = PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.humorous,
      updatedAt: ts,
    );
    final r = resolveEffectiveStyle(global: globalStyle, partner: partner);
    expect(r.interactionStyle, InteractionStyle.humorous);
    expect(r.practiceGoals, [PracticeGoal.softInvite]);
    expect(r.notes, 'global notes');
  });

  test('should override practiceGoals when partner has any', () {
    final partner = PartnerStyleOverride.create(
      partnerId: 'p1',
      practiceGoals: const [PracticeGoal.reduceAnxiety],
      updatedAt: ts,
    );
    final r = resolveEffectiveStyle(global: globalStyle, partner: partner);
    expect(r.practiceGoals, [PracticeGoal.reduceAnxiety]);
  });

  test('should fall back to global goals when partner goals empty', () {
    final partner = PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.gentle,
      updatedAt: ts,
    );
    final r = resolveEffectiveStyle(global: globalStyle, partner: partner);
    expect(r.practiceGoals, [PracticeGoal.softInvite]);
  });

  test('should return all-null when both layers null', () {
    final r = resolveEffectiveStyle(global: null, partner: null);
    expect(r.interactionStyle, isNull);
    expect(r.practiceGoals, isEmpty);
    expect(r.notes, isNull);
  });

  test('should not crash when global null but partner has values', () {
    final partner = PartnerStyleOverride.create(
      partnerId: 'p1',
      interactionStyle: InteractionStyle.direct,
      updatedAt: ts,
    );
    final r = resolveEffectiveStyle(global: null, partner: partner);
    expect(r.interactionStyle, InteractionStyle.direct);
  });
});
```

**Step 2: Run test, verify fail**

**Step 3: Implement**

```dart
// effective_style.dart
import 'package:flutter/foundation.dart';
import 'user_profile.dart';

@immutable
class EffectiveStyle {
  final InteractionStyle? interactionStyle;
  final List<PracticeGoal> practiceGoals;
  final String? notes;

  const EffectiveStyle({
    this.interactionStyle,
    this.practiceGoals = const [],
    this.notes,
  });
}
```

```dart
// resolve_effective_style.dart
import '../entities/effective_style.dart';
import '../entities/partner_style_override.dart';
import '../entities/user_profile.dart';

EffectiveStyle resolveEffectiveStyle({
  UserProfile? global,
  PartnerStyleOverride? partner,
}) {
  return EffectiveStyle(
    interactionStyle: partner?.interactionStyle ?? global?.interactionStyle,
    practiceGoals: (partner?.practiceGoals.isNotEmpty ?? false)
        ? partner!.practiceGoals
        : (global?.practiceGoals ?? const []),
    notes: partner?.notes ?? global?.notes,
  );
}
```

**Step 4: Run tests, all pass**

**Step 5: Commit + push**

```bash
git commit -am "[feat] EffectiveStyle + resolveEffectiveStyle pure function"
git push
```

---

### Task 9: `effectiveStyleProvider(partnerId)` Riverpod family

**Files:**
- Modify: `lib/features/user_profile/data/providers/partner_style_providers.dart`
- Test: 加到既有 provider test 檔（Task 7 同檔）

**Step 1: Write failing test**

驗證：
- partner override null + global filled → effective = global
- partner override interactionStyle 覆蓋 → effective interactionStyle = partner，其他欄位 inherit global
- 改 partner override → effective 自動 invalidate

**Step 2: Implement**

```dart
import '../../domain/entities/effective_style.dart';
import '../../domain/services/resolve_effective_style.dart';
// import existing user profile provider
import 'user_profile_providers.dart' show userProfileProvider;

final effectiveStyleProvider =
    Provider.family<EffectiveStyle, String>((ref, partnerId) {
  final globalAsync = ref.watch(userProfileProvider);
  final partnerAsync = ref.watch(partnerStyleOverrideProvider(partnerId));
  return resolveEffectiveStyle(
    global: globalAsync.valueOrNull,
    partner: partnerAsync.valueOrNull,
  );
});
```

**Step 3: Run tests, pass**

**Step 4: Commit + push**

```bash
git commit -am "[feat] effectiveStyleProvider family for fallback resolution"
git push
```

---

### Task 10: Verification — typecheck + 所有 unit tests 跑一次

```bash
flutter analyze --no-fatal-infos lib test
flutter test test/unit/features/user_profile/
```

預期：0 issues、所有 user_profile 相關測試 PASS。如有 regression（特別是 Spec 1 既有測試）需先修。

如果一切綠 → 進 Phase 5 UI。沒有 commit 動作（純 verification）。

---

## Phase 5 — UI: Inline Card on Partner Detail

### Task 11: PartnerStyleEntryCard widget

**Files:**
- Create: `lib/features/user_profile/presentation/widgets/partner_style_entry_card.dart`
- Test: `test/widget/features/user_profile/partner_style_entry_card_test.dart`

**Step 1: Write failing widget tests**

```dart
testWidgets('shows 沿用全域預設 when override is null', (t) async {
  await pumpCard(t, partnerId: 'p1', overrideValue: null);
  expect(find.text('我的風格 · 對小明'), findsOneWidget);
  expect(find.text('沿用全域預設'), findsOneWidget);
});

testWidgets('shows 已自訂風格 when override has any value', (t) async {
  final ov = PartnerStyleOverride.create(
    partnerId: 'p1',
    interactionStyle: InteractionStyle.humorous,
    updatedAt: DateTime(2026, 5, 1),
  );
  await pumpCard(t, partnerId: 'p1', overrideValue: ov);
  expect(find.text('已自訂風格'), findsOneWidget);
});

testWidgets('uses glassTextPrimary / glassTextSecondary tokens (not onBackground)', (t) async {
  // mirror Spec 1 修補 commit eea34bd
  // ... 驗 textStyle.color
});

testWidgets('tapping card navigates to /partner/p1/my-style', (t) async {
  // ...
});
```

**Step 2: Implement widget**

UI 結構：玻璃 surface card（沿用 `AboutMeCard` 視覺 token）、title「我的風格 · {partner.name}」、subtitle「沿用全域預設」/「已自訂風格」、右側 `Icons.chevron_right`、整張可點。

讀取邏輯：`ref.watch(partnerStyleOverrideProvider(partnerId))`，依 `valueOrNull?.isEmpty != false` 顯示二態。

**Step 3-5: tests pass + commit + push**

```bash
git commit -am "[feat] PartnerStyleEntryCard inline 二態副標 + chevron"
git push
```

---

### Task 12: 整合 PartnerStyleEntryCard 進 PartnerDetailScreen

**Files:**
- Modify: `lib/features/partner/presentation/screens/partner_detail_screen.dart`（在 PartnerTraitsCard 下方插入）
- Test: `test/widget/features/partner/partner_detail_screen_with_style_card_test.dart`

**Step 1: Widget test — 卡片有出現在 PartnerDetail，PartnerTraitsCard 仍在原位**

**Step 2: Insert widget**

`partner_detail_screen.dart` ListView children，在 PartnerTraitsCard 後面、`Padding` traits hint 之前（或之後，看視覺結果）：
```dart
const SizedBox(height: 16),
PartnerStyleEntryCard(partnerId: partnerId, partnerName: partner.name),
```

**Step 3-5: tests pass + commit + push**

```bash
git commit -am "[feat] Partner detail 加 PartnerStyleEntryCard inline"
git push
```

---

### Task 13: 加 `/partner/:id/my-style` route

**Files:**
- Modify: `lib/app/routes.dart`
- Test: `test/widget/app/routes_partner_my_style_test.dart`

**Step 1: Write failing test (route resolves to PartnerStyleEditScreen — placeholder for now)**

**Step 2: Add route**

```dart
GoRoute(
  path: 'my-style',
  builder: (context, state) {
    final partnerId = state.pathParameters['id']!;
    return PartnerStyleEditScreen(partnerId: partnerId);
  },
),
```
（巢狀在現有 partner route 下）

Phase 6 才會真的把 `PartnerStyleEditScreen` 寫完，這個 task 先用 stub screen（顯示 placeholder text）讓 route 測試 pass。Edit screen 內容 Phase 6 再迭代。

**Step 3-5: stub + tests pass + commit + push**

```bash
git commit -am "[feat] route /partner/:id/my-style + stub PartnerStyleEditScreen"
git push
```

---

## Phase 6 — UI: Edit Screen

### Task 14: PartnerStyleEditScreen scaffold + AppBar

**Files:**
- Modify: `lib/features/user_profile/presentation/screens/partner_style_edit_screen.dart`（從 stub 擴充）
- Test: `test/widget/features/user_profile/partner_style_edit_screen_test.dart`

**Step 1-5:**
- Title「我的風格 · {partner.name}」，從 `partnerByIdProvider(partnerId)` 讀 name；找不到 partner → fallback「我的風格」
- 背景跟 PartnerDetail 一致玻璃感
- 三段欄位（Style / Goals / Notes）暫用 stub Container，下個 task 真的填
- 返回鍵自動觸發 save（透過 `WillPopScope` / `PopScope`）

```bash
git commit -am "[feat] PartnerStyleEditScreen scaffold + dynamic title"
git push
```

---

### Task 15: InteractionStyle chip section + reset link

**Files:**
- Modify: `partner_style_edit_screen.dart`
- 加 widget `lib/features/user_profile/presentation/widgets/style_chip_field.dart`（可 reuse Spec 1 的 chip pattern；如果 Spec 1 widget 抽出來合理就 reuse，否則新寫一個 partner-aware 版本）

**Step 1: Widget tests**
- `placeholder hint「（沿用全域：穩重）」shows when interactionStyle is null AND global has value`
- `placeholder hint shows「（尚未設定）」when both null`
- `selecting a chip updates state to that style`
- `「沿用全域」reset link 只在 interactionStyle 已自訂時顯示`
- `tapping reset link 清空 interactionStyle 回 null`

**Step 2-5: implement + commit + push**

```bash
git commit -am "[feat] PartnerStyleEdit interactionStyle chip + reset link"
git push
```

---

### Task 16: PracticeGoals chip section + reset link

跟 Task 15 同 pattern，差別：multi-select max 3、placeholder「（沿用全域：自然邀約、降低焦慮）」、reset link 在「practiceGoals.isNotEmpty」時顯示。

```bash
git commit -am "[feat] PartnerStyleEdit practiceGoals multi chip + reset link"
git push
```

---

### Task 17: Notes TextField + reset link

**Files:**
- Modify: `partner_style_edit_screen.dart`

**重點 UX:**
- placeholder 顯示「（沿用全域：xxx）」當 notes null AND global notes != null
- char counter 0/100
- Reset link 只在 notes != null 時顯示，點擊清空（同步清空 controller 文字）

**Tests:** placeholder 兩態 / char counter / reset link 行為。

```bash
git commit -am "[feat] PartnerStyleEdit notes TextField + reset link"
git push
```

---

### Task 18: Save / back / clear actions

**Files:**
- Modify: `partner_style_edit_screen.dart`
- Test: 整合 widget test

**Step 1-5:**
- 返回鍵 / system back → 自動 build PartnerStyleOverride.create + repo.save（會自動處理 isEmpty → delete）
- 加「重設整個對象風格」action（AppBar overflow 或底部 link，dim style）→ 二段確認 dialog → repo.delete
- 整合 widget test：
  - 從 entry card 進編輯 → 改 style → 返回 → entry card 副標變「已自訂風格」
  - 再進編輯 → 點 reset link 清掉 style → 返回 → 副標變回「沿用全域預設」（驗 isEmpty cascade delete）

```bash
git commit -am "[feat] PartnerStyleEdit auto-save on back + reset all action"
git push
```

---

## Phase 7 — Verification + Polish

### Task 19: Full integration widget test + cascade delete 端到端

**Files:**
- Create: `test/integration/spec2_partner_style_override_flow_test.dart`

**情境：**
1. 全新 partner → 進 detail → 看到 entry card「沿用全域預設」
2. 進 edit → 設 style + goals + notes → 返回 → 副標變「已自訂風格」
3. 重進 edit → 點 reset link 清空所有 → 返回 → 副標變回「沿用全域預設」
4. 刪除 partner → partner_style_overrides box 該 row 也消失（cascade delete）
5. 帳號清除 → partner_style_overrides 全空

**Commit 包：** 主要驗 cross-feature flow，沒 production code 改動只加測試。

```bash
git commit -am "[test] Spec 2 整合 flow 含 cascade delete + clearAll"
git push
```

---

### Task 20: Final lint + 全測試 + Codex code review handoff

```bash
flutter analyze --no-fatal-infos lib test
flutter test
```

預期：
- analyze: 0 issues
- test: 全綠（含 Spec 1 既有測試 + Spec 2 新增測試）

成功後：
1. 在 `docs/plans/2026-05-01-partner-style-override-impl.md` 底部加 `## Status: SHIPPED — <hash>` 或更新 `docs/snapshot.md`
2. 如果觸發架構分歧 → 寫 ADR-16 in `docs/decisions.md`
3. 通知 Codex 進 code review pipeline

```bash
git commit -am "[chore] Spec 2 ship — design + impl plan status update"
git push
```

---

## TF Smoke 收尾驗收（Spec 2 ship 後跑）

設備：iOS TestFlight 最新 build。Bruce / Eric 任一人跑：

1. Partner detail 第一次進入 → 看到「我的風格 · {name}」inline card，副標「沿用全域預設」
2. 點卡片 → 進編輯 → AppBar 顯示「我的風格 · {name}」、placeholder 顯示「（沿用全域：X）」
3. 設 style + 1 goal + notes → 返回 → 副標變「已自訂風格」
4. 重進 → 三個欄位下方都看到「沿用全域」灰字 link
5. 點 style 的 reset link → style 清空、placeholder 回灰字、reset link 消失
6. 全部清完 → 返回 → 副標變回「沿用全域預設」
7. 設定 → 刪 partner → 重開 app → 該 partner 不存在；設新 partner 同名 → 應該乾淨無殘留 override
8. 設定 → 清除帳號 → 重新登入 → 所有 partner 從零、AboutMeCard 也回空（驗 Spec 1 + Spec 2 雙清）

如 1-8 全綠 = Spec 2 TF smoke PASS。

---

## Status: SHIPPED — 2026-05-01

**全 20 tasks 通過 TDD red→green→refactor，分七批 push 完成。**

| Phase | Tasks | Hashes |
|-------|-------|--------|
| 1 Domain | 1 | `9f77c1c` |
| 2 Hive | 2-4 | `54ba98e` `62ac45f` `8bb410b` |
| 3 Data | 5-7 | `9b1a357` `907e418` `2f904cb` |
| 4 Resolver | 8-10 | `4cbf18e` `cad333b` |
| 5 Inline UI | 11-13 | `330e72f` `981dbb9` `80bea4c` |
| 6 Edit Screen | 14-18 | `a0a14e6` `33892d5` `aa2ed18` `537b273` `a161cd2` `ca713a1` |
| 7 Verification | 19-20 | `5a34b93` + this commit |

**Verification:**
- `flutter analyze --no-fatal-infos lib test` → 0 issues
- Spec 2 perimeter (`test/integration` + `test/widget/features/{user_profile,partner}` + `test/widget/app` + relevant unit tests) → **210/210 green**
- Full repo `flutter test` → 540 pass, 76 pre-existing stale failures (none touching Spec 2 code, baseline 86 per `reference_vibesync_test_suite_health.md`)

**Next:** Bruce / Eric run TF smoke checklist §1–8 above; if green → Codex code review handoff via `docs/shared-agent-rules.md` queue.
