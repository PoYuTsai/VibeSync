# Spec 1 About Me Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
>
> **Status:** v2, Codex plan review 🟡 APPROVED-WITH-AMENDMENTS @ 2026-04-30 — 3 patches applied below.
> **Date:** 2026-04-30
> **Parent design:** `docs/plans/2026-04-30-two-layer-profile-spec1-about-me-design.md`
> **Roadmap:** `docs/plans/2026-04-30-vibesync-memory-coach-roadmap.md`

### Codex Review Resolution Log

| Verdict | Patch | Where applied |
|---|---|---|
| 🟡 P1 | Box key 改 owner-scoped (`profile:$ownerUserId`) + 加帳號隔離測試（privacy boundary，非 edge case） | Architecture 段、Task 3 / Task 4 全段、Task 9 |
| 🟡 P2 | `UserProfile` drop `_sentinel` + private constructor；改 public `const UserProfile(...)` 給 Hive codegen，validation 集中在 `UserProfile.create(...)` factory | Task 1 Step 3 |
| 🟡 P2 | Final scope guard 不可用 `origin/main..HEAD`（direct-push main 後失準），改記 START_SHA 後 diff `START_SHA..HEAD` | §0 新增 Step 5、Task 9 Step 4 |
| ✅ D1 | 確認新建 `InteractionStyle` typeId=10，**不** reuse legacy `UserStyle` typeId=7（語意分離 / 防 prompt 混淆 / 防 migration 歧義）| §12 Q1 |
| ✅ Q5 | Codex 已 grep verify：既有 test 沒 assert `你的風格 / 你的興趣` chip，破壞面只在 `new_conversation_screen.dart` 本身。Plan「破了就改、不刪 assertion」原則保留 | Task 8 |
| ❎ telemetry | 不補 local counter，dogfood 期靠 visual smoke（避免假訊號） | §10 維持原狀 |

**Goal:** 在不改 analyze-chat / OCR / prompt 的前提下，建立全域 `關於我` 資料層 + 我的報告頂部入口卡 + `/profile/about-me` 編輯頁，並從手動輸入頁移除 `你的風格 / 你的興趣`。

**Architecture:** Clean Architecture feature folder `lib/features/user_profile/`，加密 Hive box（與 `Partner` / `Conversation` 同一把 AES key）儲存 **per-account** `UserProfile` 紀錄（key = `'profile:$ownerUserId'`），Riverpod `AsyncNotifier` + auth scope StreamProvider 暴露 `UserProfileState`（auth 切換自動 invalidate），UI 走 GoRouter `/profile/about-me`。`UserStyle` (session_context.dart, typeId=7) 不動 — 新建獨立 `InteractionStyle` enum；§13 已明示「不 migrate 舊 SessionContext.userStyle」。

**Tech Stack:** Flutter 3.x · Riverpod (AsyncNotifier) · hive_ce + hive_ce_generator · go_router · flutter_test · build_runner

---

## 0. Pre-Flight Verification

執行任何 Task 前先做這四件事：

1. **typeId free check**（避免撞號）：

```bash
grep -rn "@HiveType\|typeId:" lib/ test/ --include="*.dart" | grep -v ".g.dart" | sort -u
```

預期結果：typeId 已用 0..8，typeId 9, 10, 11, 12 必須**未出現**在輸出裡。若有撞號，停下回報。

2. **AES key 來源確認**：`lib/core/services/storage_service.dart:37-54` 已有 `encryptionCipher: HiveAesCipher(encryptionKey)` 既有 pattern — 新 box 沿用 `encryptionKey` 變數，**禁止**自建第二把 key。

3. **既有 UserStyle 不動確認**：

```bash
grep -n "UserStyle\b" lib/features/conversation/domain/entities/session_context.dart
```

老 enum 須維持 typeId=7 / `humorous, steady, direct, gentle, playful` 不變。

4. **MyReportScreen empty path 確認**：`lib/features/report/presentation/screens/my_report_screen.dart:18-20` 目前在 `report.totalConversations == 0` 時直接 `return _buildEmptyState()`。Task 5 必須改寫此分支讓 About Me card 仍 render。

5. **Record START_SHA for scope guard** (Codex P2)：testing-phase protocol 是 direct-push main，所以執行中 `origin/main` 會被推進，`origin/main..HEAD` 失準。執行第一個 task 之前先 freeze SHA：

```bash
git rev-parse HEAD > /tmp/vibesync-spec1-start-sha
cat /tmp/vibesync-spec1-start-sha   # sanity check, 顯示一個 40-char SHA
```

Task 9 Step 4 會讀這個檔做 diff guard。執行完 plan 後可刪除。

6. **既有 auth scope provider pattern**：`lib/features/conversation/data/providers/conversation_providers.dart:14-19` 已有 `authConversationScopeProvider` (StreamProvider<String?>)。本 plan 在 user_profile feature 內 mirror 同一 pattern（取名 `authUserProfileScopeProvider`），repository 直讀 `SupabaseService.currentUser?.id`，跟 `ConversationRepository._currentUserId` 同 idiom。**不**跨 feature import，**不**把這個 provider lift 到 core（那是 Spec 1 之外的 cleanup）。

---

## Task 1: UserProfile Domain Entity + Enums

**Goal:** 建立純 Dart entity 與三個 enum，先寫 unit test 驗證 normalization / max constraints / equality。Hive 部份留到 Task 2。

**Files:**
- Create: `lib/features/user_profile/domain/entities/user_profile.dart`
- Create: `test/unit/features/user_profile/user_profile_test.dart`

### Step 1: Write failing tests

`test/unit/features/user_profile/user_profile_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  group('UserProfile.create', () {
    test('empty inputs normalize to null / empty list', () {
      final p = UserProfile.create(
        interactionStyle: null,
        practiceGoals: const [],
        topicSeeds: const [],
        customTopics: '   ',
        notes: '',
        updatedAt: DateTime(2026, 4, 30),
      );

      expect(p.interactionStyle, isNull);
      expect(p.practiceGoals, isEmpty);
      expect(p.topicSeeds, isEmpty);
      expect(p.customTopics, isNull);
      expect(p.notes, isNull);
    });

    test('trims whitespace on text fields', () {
      final p = UserProfile.create(
        customTopics: '  咖啡、旅行  ',
        notes: '  慢熟  ',
        updatedAt: DateTime(2026, 4, 30),
      );

      expect(p.customTopics, '咖啡、旅行');
      expect(p.notes, '慢熟');
    });

    test('practiceGoals capped at 3 throws when exceeded', () {
      expect(
        () => UserProfile.create(
          practiceGoals: const [
            PracticeGoal.softInvite,
            PracticeGoal.reduceAnxiety,
            PracticeGoal.humorousReply,
            PracticeGoal.buildCloseness,
          ],
          updatedAt: DateTime(2026, 4, 30),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('topicSeeds capped at 5 throws when exceeded', () {
      expect(
        () => UserProfile.create(
          topicSeeds: const [
            TopicSeed.fitness,
            TopicSeed.travel,
            TopicSeed.coffee,
            TopicSeed.music,
            TopicSeed.movies,
            TopicSeed.photography,
          ],
          updatedAt: DateTime(2026, 4, 30),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('customTopics > 60 chars throws', () {
      expect(
        () => UserProfile.create(
          customTopics: 'x' * 61,
          updatedAt: DateTime(2026, 4, 30),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('notes > 100 chars throws', () {
      expect(
        () => UserProfile.create(
          notes: 'x' * 101,
          updatedAt: DateTime(2026, 4, 30),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('UserProfile.isEmpty', () {
    test('all null / empty returns true', () {
      final p = UserProfile.create(updatedAt: DateTime(2026, 4, 30));
      expect(p.isEmpty, isTrue);
    });

    test('any field present returns false', () {
      final p = UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        updatedAt: DateTime(2026, 4, 30),
      );
      expect(p.isEmpty, isFalse);
    });
  });
}
```

### Step 2: Run test, expect FAIL (file missing)

```bash
flutter test test/unit/features/user_profile/user_profile_test.dart
```

Expected: `Target of URI doesn't exist: '...user_profile.dart'`.

### Step 3: Implement domain entity (no Hive annotations yet)

`lib/features/user_profile/domain/entities/user_profile.dart`：

> **Codex P2 amendment**：dual-constructor pattern — public `const UserProfile(...)` 給 Hive codegen 直接用，`UserProfile.create(...)` factory 集中做 trim / max count / max length validation。**不**用 `_sentinel`，**不**寫 `copyWith`（YAGNI — `AboutMeScreen` 永遠從 form draft 整包重建 `UserProfile`，不需要 partial update）。

```dart
import 'package:flutter/foundation.dart';

/// 互動風格 — single select. Independent from legacy
/// `SessionContext.UserStyle` (typeId=7) on purpose: §13 forbids silent
/// migration from per-conversation data, and labels here drop the `型` suffix.
enum InteractionStyle { steady, direct, humorous, gentle, playful }

/// 練習目標 — multi select, max 3.
enum PracticeGoal {
  softInvite,
  reduceAnxiety,
  humorousReply,
  buildCloseness,
  explainLess,
}

/// 常聊話題 — multi select, max 5.
enum TopicSeed {
  fitness,
  travel,
  coffee,
  music,
  movies,
  photography,
  food,
  pets,
  reading,
  workLife,
}

@immutable
class UserProfile {
  static const int maxPracticeGoals = 3;
  static const int maxTopicSeeds = 5;
  static const int maxCustomTopicsLength = 60;
  static const int maxNotesLength = 100;

  final InteractionStyle? interactionStyle;
  final List<PracticeGoal> practiceGoals;
  final List<TopicSeed> topicSeeds;
  final String? customTopics;
  final String? notes;
  final DateTime updatedAt;

  /// Public raw constructor — used by Hive codegen and trusted call sites.
  /// **Callers from UI / controller MUST use [UserProfile.create] instead**
  /// so trimming + bounds are enforced. This raw form is intentionally
  /// permissive so the generated `UserProfileAdapter.read()` can rebuild
  /// rows without going through the validating factory (which would reject
  /// data that legitimately existed before a future bound was tightened).
  const UserProfile({
    this.interactionStyle,
    this.practiceGoals = const [],
    this.topicSeeds = const [],
    this.customTopics,
    this.notes,
    required this.updatedAt,
  });

  /// Validates + normalizes inputs. **Always** use this from controllers,
  /// repository write-path, or any UI surface that builds a profile from
  /// user input. Throws [ArgumentError] on bound violation.
  factory UserProfile.create({
    InteractionStyle? interactionStyle,
    List<PracticeGoal> practiceGoals = const [],
    List<TopicSeed> topicSeeds = const [],
    String? customTopics,
    String? notes,
    required DateTime updatedAt,
  }) {
    if (practiceGoals.length > maxPracticeGoals) {
      throw ArgumentError('practiceGoals exceeds max $maxPracticeGoals');
    }
    if (topicSeeds.length > maxTopicSeeds) {
      throw ArgumentError('topicSeeds exceeds max $maxTopicSeeds');
    }
    final ct = customTopics?.trim();
    if (ct != null && ct.length > maxCustomTopicsLength) {
      throw ArgumentError('customTopics exceeds $maxCustomTopicsLength chars');
    }
    final n = notes?.trim();
    if (n != null && n.length > maxNotesLength) {
      throw ArgumentError('notes exceeds $maxNotesLength chars');
    }
    return UserProfile(
      interactionStyle: interactionStyle,
      practiceGoals: List.unmodifiable(practiceGoals),
      topicSeeds: List.unmodifiable(topicSeeds),
      customTopics: (ct == null || ct.isEmpty) ? null : ct,
      notes: (n == null || n.isEmpty) ? null : n,
      updatedAt: updatedAt,
    );
  }

  bool get isEmpty =>
      interactionStyle == null &&
      practiceGoals.isEmpty &&
      topicSeeds.isEmpty &&
      customTopics == null &&
      notes == null;
}
```

**Why drop `copyWith`**: `AboutMeScreen` (Task 6) 持有完整 form draft state，按 `儲存` 時直接 `UserProfile.create(interactionStyle: _draftStyle, practiceGoals: List.from(_draftGoals), ...)` 整包重建。沒有 partial update flow → `copyWith` 是 dead code。若未來真有需求（e.g. Spec 2A `userCoachingPreferences` block），到時再加。

**Why public const ctor**: Hive `@HiveType` 生成的 `UserProfileAdapter.read()` 會呼叫 `UserProfile(interactionStyle: ..., practiceGoals: ..., ...)`。private constructor 會強迫 generator 走 reflection workaround 或要求 `UserProfile.fromHive(...)` named factory，徒增 generator 兼容風險。Public const + 兩個 enforcement 入口（UI factory + repository defensive trim）已足夠。

### Step 4: Run test, expect PASS

```bash
flutter test test/unit/features/user_profile/user_profile_test.dart
```

Expected: 8 tests pass.

### Step 5: Commit

```bash
git add lib/features/user_profile/domain/entities/user_profile.dart \
        test/unit/features/user_profile/user_profile_test.dart
git commit -m "[feat] UserProfile domain entity + enums (no Hive yet)"
git push
```

---

## Task 2: Hive Adapters + StorageService Box

**Goal:** 在 `UserProfile` / `InteractionStyle` / `PracticeGoal` / `TopicSeed` 加上 Hive annotations，跑 build_runner，加密開 box，round-trip 測試。

**Files:**
- Modify: `lib/features/user_profile/domain/entities/user_profile.dart` (add `@HiveType` / `@HiveField`)
- Generated: `lib/features/user_profile/domain/entities/user_profile.g.dart`
- Modify: `lib/core/services/storage_service.dart` (register adapters + open box)
- Test: `test/unit/features/user_profile/user_profile_hive_test.dart`

### Step 1: Re-confirm typeId 9–12 free

```bash
grep -rn "typeId: 9\b\|typeId: 10\b\|typeId: 11\b\|typeId: 12\b" lib/ test/ --include="*.dart"
```

Expected: 0 hits. **如有任何 hit 立刻停下回報，不要硬蓋。**

### Step 2: Annotate entity

在 Task 1 entity 上加（only 改動：annotation + `part`）：

```dart
import 'package:hive_ce/hive_ce.dart';

part 'user_profile.g.dart';

@HiveType(typeId: 9) // verified free at 2026-04-30; Partner uses 8
class UserProfile {
  @HiveField(0)
  final InteractionStyle? interactionStyle;
  @HiveField(1)
  final List<PracticeGoal> practiceGoals;
  @HiveField(2)
  final List<TopicSeed> topicSeeds;
  @HiveField(3)
  final String? customTopics;
  @HiveField(4)
  final String? notes;
  @HiveField(5)
  final DateTime updatedAt;
  // ... constructors / methods unchanged
}

@HiveType(typeId: 10)
enum InteractionStyle {
  @HiveField(0) steady,
  @HiveField(1) direct,
  @HiveField(2) humorous,
  @HiveField(3) gentle,
  @HiveField(4) playful,
}

@HiveType(typeId: 11)
enum PracticeGoal {
  @HiveField(0) softInvite,
  @HiveField(1) reduceAnxiety,
  @HiveField(2) humorousReply,
  @HiveField(3) buildCloseness,
  @HiveField(4) explainLess,
}

@HiveType(typeId: 12)
enum TopicSeed {
  @HiveField(0) fitness,
  @HiveField(1) travel,
  @HiveField(2) coffee,
  @HiveField(3) music,
  @HiveField(4) movies,
  @HiveField(5) photography,
  @HiveField(6) food,
  @HiveField(7) pets,
  @HiveField(8) reading,
  @HiveField(9) workLife,
}
```

> **Note:** Task 1 已採 P2 amendment 的 public const constructor，hive_generator 直接認得 — 沒有 `_sentinel` / private ctor 兼容問題。對照 `lib/features/partner/domain/entities/partner.dart` (typeId=8) 也是同一 pattern。

### Step 3: Run codegen

```bash
dart run build_runner build --delete-conflicting-outputs
```

Expected: `lib/features/user_profile/domain/entities/user_profile.g.dart` 被生成；no analyzer error。

### Step 4: Wire StorageService

`lib/core/services/storage_service.dart` — 在 `Hive.registerAdapter(PartnerAdapter())` 後新增：

```dart
Hive.registerAdapter(UserProfileAdapter()); // typeId=9, Spec 1 About Me
Hive.registerAdapter(InteractionStyleAdapter()); // typeId=10
Hive.registerAdapter(PracticeGoalAdapter()); // typeId=11
Hive.registerAdapter(TopicSeedAdapter()); // typeId=12
```

在 `Hive.openBox<Partner>(...)` 後新增：

```dart
await Hive.openBox<UserProfile>(
  'user_profile',
  encryptionCipher: HiveAesCipher(encryptionKey),
);
```

加 `static Box<UserProfile> get userProfileBox => Hive.box<UserProfile>('user_profile');` 跟現有 `partnersBox` getter 並列。

加上 import：`import '../../features/user_profile/domain/entities/user_profile.dart';`

### Step 5: Round-trip test

`test/unit/features/user_profile/user_profile_hive_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import '../../../helpers/fake_path_provider.dart'; // existing helper used by partner tests

void main() {
  setUpAll(() async {
    PathProviderPlatform.instance = FakePathProvider();
    Hive.init('.dart_tool/test/hive_user_profile');
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(UserProfileAdapter());
      Hive.registerAdapter(InteractionStyleAdapter());
      Hive.registerAdapter(PracticeGoalAdapter());
      Hive.registerAdapter(TopicSeedAdapter());
    }
  });

  test('UserProfile survives Hive round-trip', () async {
    final box = await Hive.openBox<UserProfile>('test_user_profile_${DateTime.now().microsecondsSinceEpoch}');
    final original = UserProfile.create(
      interactionStyle: InteractionStyle.gentle,
      practiceGoals: const [PracticeGoal.softInvite, PracticeGoal.reduceAnxiety],
      topicSeeds: const [TopicSeed.coffee, TopicSeed.travel, TopicSeed.movies],
      customTopics: '日劇、週末探店',
      notes: '我慢熟，希望不要太快邀約',
      updatedAt: DateTime.utc(2026, 4, 30, 12, 0),
    );

    await box.put('me', original);
    final restored = box.get('me')!;

    expect(restored.interactionStyle, InteractionStyle.gentle);
    expect(restored.practiceGoals, original.practiceGoals);
    expect(restored.topicSeeds, original.topicSeeds);
    expect(restored.customTopics, '日劇、週末探店');
    expect(restored.notes, '我慢熟，希望不要太快邀約');
    expect(restored.updatedAt, original.updatedAt);
    await box.close();
  });
}
```

> **If `helpers/fake_path_provider.dart` does not exist:** check how `test/widget/features/partner/add_partner_screen_test.dart:47` initializes Hive (it uses `Hive.isAdapterRegistered(PartnerAdapter().typeId)`) and reuse the same setup. Do **not** invent a new pattern.

### Step 6: Verify

```bash
flutter test test/unit/features/user_profile/
flutter analyze --no-fatal-infos lib/features/user_profile lib/core/services/storage_service.dart
```

Expected: all green, 0 analyzer errors.

### Step 7: Commit

```bash
git add lib/features/user_profile/ lib/core/services/storage_service.dart \
        test/unit/features/user_profile/user_profile_hive_test.dart
git commit -m "[feat] UserProfile Hive adapter + encrypted box wiring"
git push
```

---

## Task 3: UserProfileRepository (owner-scoped, Codex P1)

**Goal:** 提供 `load(ownerUserId)` / `save(profile, ownerUserId)` / `clear(ownerUserId)` 三個操作，**owner-scoped key** (`profile:$ownerUserId`)，含明確的帳號隔離測試。

**Files:**
- Create: `lib/features/user_profile/data/repositories/user_profile_repository.dart`
- Test: `test/unit/features/user_profile/user_profile_repository_test.dart`

> **Codex P1 rationale**：固定 key `'me'` 在同 device 多 Supabase 帳號切換時會 leak — 這是 privacy / trust boundary，不是 edge case。Hive box 名稱維持 `'user_profile'`，差別只在 key 改成 owner-scoped；migration 不需要（feature 還沒 ship）。

### Step 1: Write failing repository tests

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

void main() {
  late Box<UserProfile> box;
  late UserProfileRepository repo;

  setUpAll(() async {
    Hive.init('.dart_tool/test/hive_user_profile_repo');
    if (!Hive.isAdapterRegistered(9)) {
      Hive.registerAdapter(UserProfileAdapter());
      Hive.registerAdapter(InteractionStyleAdapter());
      Hive.registerAdapter(PracticeGoalAdapter());
      Hive.registerAdapter(TopicSeedAdapter());
    }
  });

  setUp(() async {
    box = await Hive.openBox<UserProfile>('test_repo_${DateTime.now().microsecondsSinceEpoch}');
    repo = UserProfileRepository(box: box);
  });

  tearDown(() async => box.close());

  const userA = 'user-a-uuid';
  const userB = 'user-b-uuid';

  test('load() returns null when box is empty', () async {
    expect(await repo.load(userA), isNull);
  });

  test('save() then load() returns same profile for same owner', () async {
    final p = UserProfile.create(
      interactionStyle: InteractionStyle.direct,
      updatedAt: DateTime.utc(2026, 4, 30),
    );
    await repo.save(p, userA);
    final loaded = await repo.load(userA);
    expect(loaded?.interactionStyle, InteractionStyle.direct);
  });

  test('save() overwrites previous profile for same owner', () async {
    await repo.save(
      UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        updatedAt: DateTime.utc(2026, 4, 29),
      ),
      userA,
    );
    await repo.save(
      UserProfile.create(
        interactionStyle: InteractionStyle.playful,
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
      userA,
    );
    final loaded = await repo.load(userA);
    expect(loaded?.interactionStyle, InteractionStyle.playful);
  });

  test('clear() removes the profile for that owner', () async {
    await repo.save(
      UserProfile.create(
        interactionStyle: InteractionStyle.steady,
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
      userA,
    );
    await repo.clear(userA);
    expect(await repo.load(userA), isNull);
  });

  test('clear() on empty box is no-op', () async {
    await repo.clear(userA);
    expect(await repo.load(userA), isNull);
  });

  // === Codex P1: privacy / trust boundary ===
  test('save() under owner A is invisible to owner B', () async {
    await repo.save(
      UserProfile.create(
        interactionStyle: InteractionStyle.gentle,
        practiceGoals: const [PracticeGoal.softInvite],
        notes: 'A 的私密 coach memo',
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
      userA,
    );

    expect(await repo.load(userA), isNotNull);
    expect(await repo.load(userB), isNull,
        reason: 'B must NOT see A\'s About Me — privacy boundary');
  });

  test('clear(A) leaves B\'s profile intact', () async {
    await repo.save(
      UserProfile.create(
        interactionStyle: InteractionStyle.direct,
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
      userA,
    );
    await repo.save(
      UserProfile.create(
        interactionStyle: InteractionStyle.humorous,
        updatedAt: DateTime.utc(2026, 4, 30),
      ),
      userB,
    );

    await repo.clear(userA);

    expect(await repo.load(userA), isNull);
    expect(await repo.load(userB)?.interactionStyle, InteractionStyle.humorous);
  });

  test('save rejects empty ownerUserId', () async {
    expect(
      () => repo.save(
        UserProfile.create(
          interactionStyle: InteractionStyle.steady,
          updatedAt: DateTime.utc(2026, 4, 30),
        ),
        '',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });
}
```

### Step 2: Run test, expect FAIL

```bash
flutter test test/unit/features/user_profile/user_profile_repository_test.dart
```

Expected: `UserProfileRepository` undefined.

### Step 3: Implement repository

```dart
import 'package:hive_ce/hive_ce.dart';
import '../../../../core/services/storage_service.dart';
import '../../domain/entities/user_profile.dart';

/// Per-account local store for the global About Me profile.
///
/// Storage key is `profile:<ownerUserId>` — one record per Supabase account.
/// Switching accounts on the same device must not leak About Me across
/// users; see `user_profile_repository_test.dart` privacy tests.
///
/// Box is encrypted by the same AES key used for Conversation / Partner.
class UserProfileRepository {
  UserProfileRepository({Box<UserProfile>? box})
      : _box = box ?? StorageService.userProfileBox;

  final Box<UserProfile> _box;

  static String _keyFor(String ownerUserId) {
    if (ownerUserId.isEmpty) {
      throw ArgumentError('ownerUserId must not be empty');
    }
    return 'profile:$ownerUserId';
  }

  Future<UserProfile?> load(String ownerUserId) async =>
      _box.get(_keyFor(ownerUserId));

  Future<void> save(UserProfile profile, String ownerUserId) async {
    await _box.put(_keyFor(ownerUserId), profile);
  }

  Future<void> clear(String ownerUserId) async {
    await _box.delete(_keyFor(ownerUserId));
  }
}
```

### Step 4: Run test, expect PASS

```bash
flutter test test/unit/features/user_profile/user_profile_repository_test.dart
```

Expected: 5 tests pass.

### Step 5: Commit

```bash
git add lib/features/user_profile/data/repositories/user_profile_repository.dart \
        test/unit/features/user_profile/user_profile_repository_test.dart
git commit -m "[feat] UserProfileRepository load/save/clear"
git push
```

---

## Task 4: Riverpod Providers (auth-scoped, Codex P1)

**Goal:** `authUserProfileScopeProvider` (StreamProvider 鏡射 `authConversationScopeProvider` pattern) + `userProfileRepositoryProvider` + `userProfileControllerProvider` (AsyncNotifier，自動跟著 auth 切換 invalidate)。

**Files:**
- Create: `lib/features/user_profile/data/providers/user_profile_providers.dart`
- Test: `test/unit/features/user_profile/user_profile_controller_test.dart`

### Step 1: Failing provider tests

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';

class _FakeRepo implements UserProfileRepository {
  final Map<String, UserProfile> _byOwner = {};
  int saveCount = 0;
  int clearCount = 0;
  bool throwOnSave = false;

  @override
  Future<UserProfile?> load(String ownerUserId) async => _byOwner[ownerUserId];

  @override
  Future<void> save(UserProfile profile, String ownerUserId) async {
    if (throwOnSave) throw Exception('boom');
    _byOwner[ownerUserId] = profile;
    saveCount++;
  }

  @override
  Future<void> clear(String ownerUserId) async {
    _byOwner.remove(ownerUserId);
    clearCount++;
  }
}

ProviderContainer _container({
  required _FakeRepo repo,
  required String? uid,
}) {
  return ProviderContainer(overrides: [
    userProfileRepositoryProvider.overrideWithValue(repo),
    authUserProfileScopeProvider.overrideWith((ref) => Stream.value(uid)),
  ]);
}

void main() {
  const userA = 'user-a-uuid';
  const userB = 'user-b-uuid';

  test('initial load with empty repo emits null state', () async {
    final repo = _FakeRepo();
    final c = _container(repo: repo, uid: userA);
    addTearDown(c.dispose);

    final state = await c.read(userProfileControllerProvider.future);
    expect(state, isNull);
  });

  test('save() persists per-owner profile and updates state', () async {
    final repo = _FakeRepo();
    final c = _container(repo: repo, uid: userA);
    addTearDown(c.dispose);

    await c.read(userProfileControllerProvider.future);
    await c.read(userProfileControllerProvider.notifier).save(
          UserProfile.create(
            interactionStyle: InteractionStyle.humorous,
            updatedAt: DateTime.utc(2026, 4, 30),
          ),
        );

    expect(repo.saveCount, 1);
    expect(repo._byOwner[userA]?.interactionStyle, InteractionStyle.humorous);
    expect(repo._byOwner[userB], isNull);
    expect(c.read(userProfileControllerProvider).value?.interactionStyle,
        InteractionStyle.humorous);
  });

  test('clear() removes profile for current owner only', () async {
    final repo = _FakeRepo();
    repo._byOwner[userA] = UserProfile.create(
      interactionStyle: InteractionStyle.steady,
      updatedAt: DateTime.utc(2026, 4, 29),
    );
    repo._byOwner[userB] = UserProfile.create(
      interactionStyle: InteractionStyle.playful,
      updatedAt: DateTime.utc(2026, 4, 29),
    );

    final c = _container(repo: repo, uid: userA);
    addTearDown(c.dispose);

    await c.read(userProfileControllerProvider.future);
    await c.read(userProfileControllerProvider.notifier).clear();

    expect(repo._byOwner[userA], isNull);
    expect(repo._byOwner[userB], isNotNull,
        reason: 'clearing A must not touch B');
    expect(c.read(userProfileControllerProvider).value, isNull);
  });

  test('save failure surfaces as exception, state preserved', () async {
    final repo = _FakeRepo()..throwOnSave = true;
    final c = _container(repo: repo, uid: userA);
    addTearDown(c.dispose);

    await c.read(userProfileControllerProvider.future);
    expect(
      () => c.read(userProfileControllerProvider.notifier).save(
            UserProfile.create(
              interactionStyle: InteractionStyle.gentle,
              updatedAt: DateTime.utc(2026, 4, 30),
            ),
          ),
      throwsException,
    );
  });

  test('save() throws StateError when no authenticated user', () async {
    final repo = _FakeRepo();
    final c = _container(repo: repo, uid: null);
    addTearDown(c.dispose);

    await c.read(userProfileControllerProvider.future);
    expect(
      () => c.read(userProfileControllerProvider.notifier).save(
            UserProfile.create(
              interactionStyle: InteractionStyle.gentle,
              updatedAt: DateTime.utc(2026, 4, 30),
            ),
          ),
      throwsA(isA<StateError>()),
    );
  });
}
```

### Step 2: Run, expect FAIL

```bash
flutter test test/unit/features/user_profile/user_profile_controller_test.dart
```

### Step 3: Implement providers

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/services/supabase_service.dart';
import '../../domain/entities/user_profile.dart';
import '../repositories/user_profile_repository.dart';

/// Mirrors `authConversationScopeProvider` (conversation_providers.dart:14)
/// — when the Supabase user changes, downstream providers automatically
/// rebuild against the new scope.
final authUserProfileScopeProvider = StreamProvider<String?>((ref) async* {
  yield SupabaseService.currentUser?.id;
  yield* SupabaseService.authStateChanges
      .map((authState) => authState.session?.user.id);
});

final userProfileRepositoryProvider = Provider<UserProfileRepository>((ref) {
  return UserProfileRepository();
});

final userProfileControllerProvider =
    AsyncNotifierProvider<UserProfileController, UserProfile?>(
  UserProfileController.new,
);

class UserProfileController extends AsyncNotifier<UserProfile?> {
  @override
  Future<UserProfile?> build() async {
    final uid = ref.watch(authUserProfileScopeProvider).valueOrNull;
    if (uid == null) return null;
    final repo = ref.read(userProfileRepositoryProvider);
    return repo.load(uid);
  }

  Future<void> save(UserProfile profile) async {
    final uid = ref.read(authUserProfileScopeProvider).valueOrNull;
    if (uid == null) {
      throw StateError('No authenticated user; cannot save About Me profile');
    }
    final repo = ref.read(userProfileRepositoryProvider);
    await repo.save(profile, uid);
    state = AsyncData(profile);
  }

  Future<void> clear() async {
    final uid = ref.read(authUserProfileScopeProvider).valueOrNull;
    if (uid == null) {
      throw StateError('No authenticated user; cannot clear About Me profile');
    }
    final repo = ref.read(userProfileRepositoryProvider);
    await repo.clear(uid);
    state = const AsyncData(null);
  }
}
```

### Step 4: Run, expect PASS

```bash
flutter test test/unit/features/user_profile/
```

### Step 5: Commit

```bash
git add lib/features/user_profile/data/providers/ \
        test/unit/features/user_profile/user_profile_controller_test.dart
git commit -m "[feat] UserProfileController async notifier + repo provider"
git push
```

---

## Task 5: About Me Card on Report Tab

**Goal:** 在我的報告頂部 render `AboutMeCard`，empty 走 prominent CTA、filled 走 compact summary、即使 `totalConversations == 0` 也要 render（重構 `_buildEmptyState`）。

**Files:**
- Create: `lib/features/user_profile/presentation/widgets/about_me_card.dart`
- Modify: `lib/features/report/presentation/screens/my_report_screen.dart`
- Test: `test/widget/features/user_profile/about_me_card_test.dart`

### Step 1: Failing widget tests

`test/widget/features/user_profile/about_me_card_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vibesync/features/user_profile/data/providers/user_profile_providers.dart';
import 'package:vibesync/features/user_profile/data/repositories/user_profile_repository.dart';
import 'package:vibesync/features/user_profile/domain/entities/user_profile.dart';
import 'package:vibesync/features/user_profile/presentation/widgets/about_me_card.dart';

class _FakeRepo implements UserProfileRepository {
  _FakeRepo(UserProfile? initial) {
    if (initial != null) _byOwner[_testUid] = initial;
  }
  static const _testUid = 'test-user';
  final Map<String, UserProfile> _byOwner = {};

  @override Future<UserProfile?> load(String uid) async => _byOwner[uid];
  @override Future<void> save(UserProfile p, String uid) async => _byOwner[uid] = p;
  @override Future<void> clear(String uid) async => _byOwner.remove(uid);
}

Widget _harness({UserProfile? initial, GoRouter? router}) {
  return ProviderScope(
    overrides: [
      userProfileRepositoryProvider.overrideWithValue(_FakeRepo(initial)),
      authUserProfileScopeProvider
          .overrideWith((ref) => Stream.value(_FakeRepo._testUid)),
    ],
    child: MaterialApp.router(
      routerConfig: router ?? GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const Scaffold(body: AboutMeCard())),
        GoRoute(path: '/profile/about-me', builder: (_, __) => const Scaffold(body: Text('edit-page-stub'))),
      ]),
    ),
  );
}

void main() {
  testWidgets('empty profile shows prominent CTA', (tester) async {
    await tester.pumpWidget(_harness(initial: null));
    await tester.pumpAndSettle();
    expect(find.text('關於我'), findsOneWidget);
    expect(find.text('讓 VibeSync 更像你的教練'), findsOneWidget);
    expect(find.text('開始設定'), findsOneWidget);
  });

  testWidgets('filled profile shows summary lines for filled fields only', (tester) async {
    final profile = UserProfile.create(
      interactionStyle: InteractionStyle.gentle,
      practiceGoals: const [PracticeGoal.softInvite, PracticeGoal.reduceAnxiety],
      topicSeeds: const [TopicSeed.coffee, TopicSeed.travel, TopicSeed.movies],
      updatedAt: DateTime.utc(2026, 4, 30),
    );
    await tester.pumpWidget(_harness(initial: profile));
    await tester.pumpAndSettle();
    expect(find.textContaining('溫柔'), findsOneWidget);
    expect(find.textContaining('自然邀約'), findsOneWidget);
    expect(find.textContaining('降低焦慮'), findsOneWidget);
    expect(find.textContaining('咖啡'), findsOneWidget);
    expect(find.text('編輯'), findsOneWidget);
    expect(find.text('開始設定'), findsNothing);
  });

  testWidgets('partial profile only renders filled fields', (tester) async {
    final profile = UserProfile.create(
      interactionStyle: InteractionStyle.direct,
      updatedAt: DateTime.utc(2026, 4, 30),
    );
    await tester.pumpWidget(_harness(initial: profile));
    await tester.pumpAndSettle();
    expect(find.textContaining('直接'), findsOneWidget);
    expect(find.textContaining('練習目標'), findsNothing);
    expect(find.textContaining('常聊話題'), findsNothing);
  });

  testWidgets('tap 開始設定 navigates to /profile/about-me', (tester) async {
    await tester.pumpWidget(_harness(initial: null));
    await tester.pumpAndSettle();
    await tester.tap(find.text('開始設定'));
    await tester.pumpAndSettle();
    expect(find.text('edit-page-stub'), findsOneWidget);
  });

  testWidgets('tap 編輯 navigates to /profile/about-me', (tester) async {
    final profile = UserProfile.create(
      interactionStyle: InteractionStyle.steady,
      updatedAt: DateTime.utc(2026, 4, 30),
    );
    await tester.pumpWidget(_harness(initial: profile));
    await tester.pumpAndSettle();
    await tester.tap(find.text('編輯'));
    await tester.pumpAndSettle();
    expect(find.text('edit-page-stub'), findsOneWidget);
  });
}
```

### Step 2: Implement `AboutMeCard`

`lib/features/user_profile/presentation/widgets/about_me_card.dart`：

需求：
- 公開 `class AboutMeCard extends ConsumerWidget`，無參數。
- `ref.watch(userProfileControllerProvider)`：
  - `loading` → `SizedBox.shrink()`（不要 spinner，避免報告頁閃爍）
  - `error` → `SizedBox.shrink()`（保護報告主視覺，本卡 best-effort）
  - `data: null` → empty CTA card（標題「關於我」、副標「讓 VibeSync 更像你的教練 / 花 30 秒填一下，之後 AI 會用更像你的節奏給建議」、按鈕「開始設定」→ `context.push('/profile/about-me')`）
  - `data: profile` → compact summary，依 §8.2 規則只 render 有值欄位 + 「編輯」按鈕
- 視覺權重：empty 比 filled 重，但 filled 比 `HeatTrendChart` 輕（不搶主視覺）。
- Label mapping helpers（不寫到 entity 上，UI-only）：

```dart
String _interactionStyleLabel(InteractionStyle s) => switch (s) {
  InteractionStyle.steady => '穩重',
  InteractionStyle.direct => '直接',
  InteractionStyle.humorous => '幽默',
  InteractionStyle.gentle => '溫柔',
  InteractionStyle.playful => '俏皮',
};
// Same pattern for PracticeGoal and TopicSeed (labels per Spec §10).
```

### Step 3: Wire into MyReportScreen

`lib/features/report/presentation/screens/my_report_screen.dart`：

- 把 `_buildEmptyState()` 改成內部 method，回傳 `Widget` 但 caller 端把它包進 `ListView`，並在 ListView 第一格 render `AboutMeCard()`。簡化做法：移除 early-return，改成：

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final report = ref.watch(reportDataProvider);
  return ListView(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
    children: [
      const AboutMeCard(),
      const SizedBox(height: 24),
      if (report.totalConversations == 0)
        ..._emptyStateContents()
      else ...[
        // 既有的標題 / HeatTrendChart / ConversationComparisonChart / ...
      ],
    ],
  );
}
```

`_buildEmptyState` 拆成 `List<Widget> _emptyStateContents()`（不變 copy）。

### Step 4: Run widget tests + report tests

```bash
flutter test test/widget/features/user_profile/about_me_card_test.dart
flutter test test/widget/features/report/  # smoke-check既有 report tests
```

Expected: 5 new tests pass; existing report tests still pass.

### Step 5: Commit

```bash
git add lib/features/user_profile/presentation/widgets/about_me_card.dart \
        lib/features/report/presentation/screens/my_report_screen.dart \
        test/widget/features/user_profile/about_me_card_test.dart
git commit -m "[feat] About Me card on report tab (empty + filled states)"
git push
```

---

## Task 6: About Me Edit Screen

**Goal:** `/profile/about-me` 編輯頁，含 chip groups / text fields / max 限制 / 三段式按鈕（先跳過 / 儲存 / 清除設定）/ 失敗 toast。

**Files:**
- Create: `lib/features/user_profile/presentation/screens/about_me_screen.dart`
- Optional helper: `lib/features/user_profile/presentation/widgets/profile_chip_section.dart` (DRY chip group)
- Test: `test/widget/features/user_profile/about_me_screen_test.dart`

### Step 1: Failing widget tests

每條對應 design §14.4：

```dart
testWidgets('empty new profile primary button = 先跳過', ...);
testWidgets('selecting interaction style flips primary button to 儲存', ...);
testWidgets('cannot select 4th practice goal — shows 最多選 3 個 toast', ...);
testWidgets('cannot select 6th topic seed — shows 最多選 5 個 toast', ...);
testWidgets('customTopics enforces 60-char limit', ...);
testWidgets('notes enforces 100-char limit', ...);
testWidgets('existing profile pre-fills all fields', ...);
testWidgets('clearing all fields on existing profile shows 清除設定', ...);
testWidgets('successful save pops back and shows snackbar 已更新關於我', ...);
testWidgets('successful clear pops back and shows snackbar 已清除關於我設定', ...);
testWidgets('save failure shows 儲存失敗，請再試一次 (no raw exception)', ...);
testWidgets('bottom privacy note 這些設定只用來讓建議更貼近你的語氣 renders', ...);
```

每個 test 用上面 Task 5 的 `_FakeRepo` + `ProviderScope` harness（抽到共用 `test/widget/features/user_profile/_harness.dart`）。

### Step 2: Implement AboutMeScreen

關鍵實作要點：

1. `class AboutMeScreen extends ConsumerStatefulWidget` — local `_draftStyle`, `_draftGoals`, `_draftSeeds`, `_customController`, `_notesController`, `_initialProfile`。`initState` 從 controller 載入 → fill draft state。
2. **Button label 狀態機**（§12）：

```dart
String get _primaryLabel {
  final isDraftEmpty = _draftStyle == null && _draftGoals.isEmpty &&
      _draftSeeds.isEmpty && _customController.text.trim().isEmpty &&
      _notesController.text.trim().isEmpty;
  final hasExistingProfile = _initialProfile != null;
  if (!hasExistingProfile && isDraftEmpty) return '先跳過';
  if (hasExistingProfile && isDraftEmpty) return '清除設定';
  return '儲存';
}
```

3. **Practice goals max 3**：tap 第 4 個時 `ScaffoldMessenger.showSnackBar(SnackBar(content: Text('最多選 3 個')))`，**不**加入 set。同邏輯 topic seeds max 5。
4. **Text limits**：`TextField(maxLength: 60)` / `maxLength: 100` — 同時在 onSave 入口再 trim + revalidate（防黏貼超長）。
5. **Save flow**：
   - `先跳過`：`context.pop()`，**不** persist。
   - `儲存`：`controller.save(UserProfile.create(...))` → `pop()` + `SnackBar('已更新關於我')`。
   - `清除設定`：`controller.clear()` → `pop()` + `SnackBar('已清除關於我設定')`。
   - 任一失敗：`SnackBar('儲存失敗，請再試一次')`，**不**印 exception。
6. AppBar title「關於我」。Body 結構（top to bottom）：
   - subtitle 「花 30 秒設定...」
   - InteractionStyle chip group + helper
   - PracticeGoal chip group (max 3) + helper
   - TopicSeed chip group (max 5) + helper
   - customTopics TextField (60 chars)
   - notes TextField (100 chars) + helper
   - Privacy note 「這些設定只用來讓建議更貼近你的語氣，不會顯示給任何對象，你可以隨時修改或清除。」
   - Primary action button (label 動態)。

### Step 3: Run all widget tests

```bash
flutter test test/widget/features/user_profile/
```

Expected: 12 tests pass.

### Step 4: Commit

```bash
git add lib/features/user_profile/presentation/screens/about_me_screen.dart \
        lib/features/user_profile/presentation/widgets/profile_chip_section.dart \
        test/widget/features/user_profile/about_me_screen_test.dart \
        test/widget/features/user_profile/_harness.dart
git commit -m "[feat] About Me edit screen with skip/save/clear flow"
git push
```

---

## Task 7: Wire Route `/profile/about-me`

**Goal:** GoRoute 註冊 + AboutMeCard tap 真正能跳。

**Files:**
- Modify: `lib/app/routes.dart`

### Step 1: Add route

在 `routes:` 列表中（建議放在 `/settings` 後、`/paywall` 前）：

```dart
GoRoute(
  path: '/profile/about-me',
  builder: (context, state) => const AboutMeScreen(),
),
```

並 import `'../features/user_profile/presentation/screens/about_me_screen.dart';`。

### Step 2: Smoke test (manual + automated)

新增 `test/widget/app/routes_test.dart`（若已存在則 append）：

```dart
testWidgets('/profile/about-me resolves to AboutMeScreen', (tester) async {
  // build full router with logged-in stub, push /profile/about-me, expect AppBar 關於我.
});
```

不需要全 routes regression — 只驗 1 條新路徑。

### Step 3: Run

```bash
flutter test test/widget/app/routes_test.dart
flutter analyze --no-fatal-infos lib/app/routes.dart
```

### Step 4: Commit

```bash
git add lib/app/routes.dart test/widget/app/routes_test.dart
git commit -m "[feat] route /profile/about-me"
git push
```

---

## Task 8: Manual Input Cleanup

**Goal:** 移除 `你的風格 / 你的興趣` UI；保留 `SessionContext.userStyle / userInterests` schema 不動（向後相容舊 Hive 紀錄），新對話寫 null + 顯示輕提示。

**Files:**
- Modify: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`
- Test (new): `test/widget/features/conversation/new_conversation_screen_user_profile_cleanup_test.dart`

### Step 1: Failing tests (per design §14.5)

```dart
testWidgets('Manual input no longer shows 你的風格', (tester) async {
  await tester.pumpWidget(_newConvHarness());
  await tester.pumpAndSettle();
  await tester.tap(find.text('個人化資訊（選填）')); // expand collapsed section
  await tester.pumpAndSettle();
  expect(find.text('你的風格'), findsNothing);
});
testWidgets('Manual input no longer shows 你的興趣', ...);
testWidgets('Manual input still shows 認識情境', ...);
testWidgets('Manual input still shows 認識多久', ...);
testWidgets('Manual input still shows 目前目標', ...);
testWidgets('Manual input still shows 對方特質', ...);
testWidgets('Submitting manual input creates conversation with userStyle=null + userInterests=null', ...);
testWidgets('Optional hint 想讓建議更像你的語氣 renders without blocking submit', (tester) async {
  // assert hint text exists; tap submit still works.
});
```

### Step 2: Edit `new_conversation_screen.dart`

具體刪除（line 數以當前 commit `baf2af4` 為準，執行時 re-grep）：

- **Delete** line 27: `final _userInterestsController = TextEditingController();`
- **Delete** line 38: `UserStyle? _userStyle;`
- **Delete** line 69: `_userInterestsController.dispose();`
- **Modify** line 151-154: pass `userStyle: null, userInterests: null` (or omit since they're optional named params with default null)
- **Delete** line 247-258: `_userStyleLabel` helper
- **Delete** line 363-385: 整段 `'你的風格'` Wrap chip group + `'你的興趣'` GlassmorphicTextField
- **Add** below `對方特質` field（design §7.3）— 一行輕提示：

```dart
const SizedBox(height: 8),
Text(
  '想讓建議更像你的語氣？可到「我的報告 > 關於我」設定一次。',
  style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
),
```

Hint 是純文字、**不**做 CTA / **不**跳 route / **不**擋 submit。

> **`SessionContext.userStyle / userInterests` 欄位不刪**：design §13 明示「不 silent migrate」舊資料；保留欄位讓既有 Hive 紀錄能 round-trip 讀回。新對話的 SessionContext 兩欄都是 null，符合預期。

### Step 3: Run

```bash
flutter test test/widget/features/conversation/
```

Expected: 8 new tests pass; 既有 conversation 測試（若有讀 `_userStyle`）需同步更新或刪除 — 先跑一輪看 break list 再修，**不要**為了綠燈刪 assertion。

### Step 4: Commit

```bash
git add lib/features/conversation/presentation/screens/new_conversation_screen.dart \
        test/widget/features/conversation/
git commit -m "[refactor] Manual input removes user profile fields, adds hint to About Me"
git push
```

---

## Task 9: Final Verification Gate

**Goal:** 跑完整測試套件確認沒踩到無關區域。

### Step 1: Targeted tests

```bash
flutter test test/unit/features/user_profile/ \
             test/widget/features/user_profile/ \
             test/widget/features/report/ \
             test/widget/features/conversation/ \
             test/widget/app/
```

Expected: all green。

### Step 2: Static analysis

```bash
flutter analyze --no-fatal-infos lib test
```

Expected: 0 error；既有 info/warning 數量不變。

### Step 3: Full suite spot-check

```bash
flutter test
```

Expected: 不能讓本 plan 引入新 failure。`docs/bug-log.md` 提到既有 86 stale test rot — 那 86 個若在本 PR 之前就 red，**不要**順手「修綠」（boy-scout 例外應只限 ≤5 行明確 stale，且另開 commit）。

### Step 4: Diff sanity (no scope creep) — Codex P2

testing-phase protocol 是 direct-push main，所以 `origin/main` 在執行中會被推進，**不能**用 `origin/main..HEAD`。改讀 §0 Step 5 凍結的 START_SHA：

```bash
START_SHA=$(cat /tmp/vibesync-spec1-start-sha)
echo "Diff base: $START_SHA"
git diff --stat $START_SHA..HEAD -- lib supabase
git diff --stat $START_SHA..HEAD -- ':(exclude)docs/' ':(exclude).github/'
```

預期 **沒有** `supabase/` 改動、沒有 `lib/features/analysis/` 改動、沒有 `lib/features/partner/` 改動（除 import 新 enum 的零星調整以外）、沒有 `lib/features/opener/` 改動。**有就停下，重新檢查。**

Plan 完成後清掉：

```bash
rm /tmp/vibesync-spec1-start-sha
```

### Step 5: Closing commit (docs)

```bash
git add docs/plans/2026-04-30-two-layer-profile-spec1-about-me-impl.md
git commit -m "[docs] Spec 1 About Me implementation plan"
git push
```

> 本 commit 就是 plan doc 本身；plan 寫完即第一個 commit。後續 7 個 feat / refactor commit 會接著推。

---

## 10. Out-of-Scope Reaffirmation

**任何下列改動發生即停下並回報，不得趁機塞入本 PR：**

- ❌ `supabase/functions/analyze-chat/**` 任何改動
- ❌ OCR / image recognition / `screenshot_recognition_dialog.dart`
- ❌ Prompt template / `userCoachingPreferences` / `UserProfileBlock` 注入（屬 Spec 2A）
- ❌ Partner-level coaching override / PartnerDetail person icon（屬 Spec 2B）
- ❌ Coach Action Card / `actionType` / `LearningRecommendation`（屬 Spec 4）
- ❌ Push notification / proactive nudge（屬 Spec 5）
- ❌ Auto-import 舊 `SessionContext.userStyle / userInterests`（design §13 明示）
- ❌ 動 `UserStyle` enum (typeId=7) / `UserGoal` (typeId=5) / 任何既有 typeId
- ❌ 改 `analyze-chat` JWT verification 設定（會踩 OCR 穩定基線）

---

## 11. Skill References

- TDD discipline: `superpowers:test-driven-development`
- Verification before "done": `superpowers:verification-before-completion`
- Code review on completion: `superpowers:requesting-code-review`
- Bug 5 lesson (test-safe diagnosis): see memory `1013` / `1014` — 改 widget 前先 grep test，不要假設 test 沒在 assert UI 細節

---

## 12. Open Questions / Codex Review Disposition

| # | Question | Codex verdict | Resolution |
|---|---|---|---|
| Q1 | `UserStyle` reuse vs. new `InteractionStyle`？ | ✅ APPROVE new enum | typeId=10 confirmed；語意分離（per-conversation metadata vs. global coach memory）防 prompt 混淆 / migration 歧義 |
| Q2 | Hive key `'me'` 還是 owner-scoped？ | 🟡 P1 PATCH | Plan 已改 `profile:$ownerUserId` + 帳號隔離測試（Task 3）+ auth scope provider（Task 4） |
| Q3 | MyReportScreen 重構深度 | 〰️ 未挑戰 | 維持原 plan：拆 `_emptyStateContents`，不擴成 `CustomScrollView` rewrite |
| Q4 | `profile_chip_section.dart` 抽 helper？ | 〰️ 未挑戰 | 維持原 plan：抽 helper（3 group share 90% 邏輯） |
| Q5 | Task 8 既有測試破壞面 | ✅ Codex grep verified | 既有 test 沒 assert `你的風格 / 你的興趣` chip — 破壞面只在 `new_conversation_screen.dart` 本身。「破了就改、不刪 assertion」原則保留 |
| Q6 | Telemetry / completion counter？ | ❎ DECLINED | 不補 local counter — dogfood 期靠 visual smoke，假訊號比沒訊號糟 |
| Q7 | 9 task / 8 commit 粒度？ | ✅ FINE | testing-phase direct-push main 反而要求每 commit atomic-shippable |
| — | Constructor pattern (`_sentinel` vs public const)？ | 🟡 P2 PATCH | 改 public `const UserProfile(...)` + `UserProfile.create(...)` factory（Task 1 Step 3） |
| — | Scope guard `origin/main..HEAD`？ | 🟡 P2 PATCH | 改 START_SHA file（§0 Step 5 + Task 9 Step 4） |

---

## 13. Estimated Touch Surface

| Layer | Files Created | Files Modified | LoC (rough) |
|---|---|---|---|
| Domain | 1 (entity) | 0 | ~140 |
| Data | 2 (repo + providers) | 1 (StorageService) | ~120 |
| Presentation | 2 (screen + card) + optional 1 (helper) | 2 (my_report_screen, routes) | ~400 |
| Conversation cleanup | 0 | 1 (new_conversation_screen) | ~-40 net |
| Tests | 6 | 0 | ~600 |
| Generated | 1 (.g.dart) | 0 | auto |
| Docs | 1 (this plan) | 0 | n/a |

**Total commits**：8（plan doc + 7 feat/refactor）
**Estimated session time**：3–4 小時 well-paced TDD，含 Codex review 來回。
