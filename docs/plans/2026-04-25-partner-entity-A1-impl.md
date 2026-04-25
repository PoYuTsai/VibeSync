# Partner Entity Refactor — A1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** Introduce the `Partner` Hive entity, add `Conversation.partnerId`, and run a deterministic, idempotent, crash-safe migration that creates one `Partner` per existing `Conversation`. **No UI changes.** A2 is a separate plan that ships after A1 has soaked on TestFlight.

**Architecture:** New `Partner` Hive type (`typeId=8`) stored in a dedicated encrypted Hive box. Migration is driven by a deterministic UUID v5 derived from `Conversation.id` plus a fixed namespace constant; idempotency is guaranteed by `Conversation.partnerId` itself acting as the per-row marker (a `SharedPreferences` flag is only a perf shortcut — never a correctness gate). A backup copy of the conversations box is taken before the migration loop on first run.

**Tech Stack:**
- Flutter 3.x · `hive_ce` / `hive_ce_flutter`
- `uuid: ^4.5.0` (v5 supported natively)
- `shared_preferences: ^2.5.4`
- Tests: `flutter_test` + `hive_ce_test` patterns already in `test/unit/`
- **No new packages.** (Sentry SDK is not wired; A1 logs migration events via `dart:developer` with a grep-able tag — Sentry integration is out of scope.)

---

## Pre-Reading (do this before Task 1)

Read in order. Do **not** skip:

1. `CLAUDE.md` — project conventions + 🚨 OCR baseline
2. `docs/shared-agent-rules.md` — closeout matrix
3. `docs/reviews/ai-arbitration-queue.md` — live item "Partner Entity Refactor — Design Spec Review" (`Status: APPROVED`, `Verdict: PASS`)
4. `docs/plans/2026-04-25-partner-entity-design.md` — full v2 spec (this plan only implements A1 from §6)
5. `docs/decisions.md` ADR-15 — flip status to `Active (A1 shipped)` after Task 13

---

## Codex Review Hot Spots (flag these explicitly at A1 closeout — Eric 2026-04-25)

When handing A1 off to Codex for code review, the queue-item handoff must call out these 2 spec-uncovered judgment calls **by name**. They are the parts of A1 that the v2 spec did **not** rule on, so independent verification matters more here than on the rest of the patch.

| HS | Topic | Where it lives in code | What Codex must judge |
|---|---|---|---|
| **HS1** | **Sentry SDK gap** — `pubspec.yaml` has no `sentry_flutter`. A1 logs migration events via `dart:developer.log` with the grep-able tag `partner_migration` instead. | `lib/features/partner/data/services/partner_migration_service.dart` (search `_kLogTag`) | Is `dart:developer.log` acceptable for TF-soak observability, or should A1 add `sentry_flutter` despite the "minimum blast radius" framing? Trade-off: no remote signal during 1–2 day soak vs. one new SDK in A1. |
| **HS2** | **Redo-backup policy** — the in-app "重做升級" button (Task 11) clears **both** `partner_migration_v1_done` and `partner_migration_v1_backup_done`, so the next run re-takes the backup, **overwriting the prior backup file**. The alternative is "backup is a one-shot, never overwritten." | `partner_migration_service.dart::resetForRedo` + Task 9 second test | If migration v2 ever ships with a regression, the "always re-backup" choice means the only good copy could be overwritten before the user notices. The "one-shot backup" choice keeps a known-good copy at the cost of stale-backup risk. Spec §5 #6 is ambiguous here — Eric / Codex must pick. |

The closeout queue-item update (Task 13 Step 4) **must include an "HS-Review-Asks:" block** quoting the two rows above so Codex does not miss them inside a 1300-line plan.

---

## Codex Implementation Constraints (load-bearing — do not deviate)

These are spec re-review carry-overs from `docs/reviews/ai-arbitration-queue.md`. Each is wired into a specific task below; if you find yourself violating one, stop and arbitrate via the queue file.

| # | Constraint | Where it applies |
|---|---|---|
| C1 | **`conversationsByPartnerProvider(partnerId)` must stay truly partner-scoped** — never reintroduce a global provider fan-out by backing it with `conversationsProvider` and filtering. A1 does **not** ship this provider, but every reference to "Partner aggregate" in this plan must respect the partner-scoped contract so A2 does not have to retrofit it. | Out of A1 scope (A2 builds the providers). Recorded here so the A2 author cannot claim ignorance. |
| C2 | **A1 work is 2–3 dev days + 1–2 day TF soak**, not the original 1.5 days. Do not compress tasks below or skip the TF-soak gate before A2 starts. | Ship cadence — Task 13 (TF soak gate) is mandatory; A2 plan must not start until the soak passes. |
| C3 | **First implementation step is `grep -rn 'typeId:' lib/`** to re-confirm `typeId=8` is unoccupied and `Conversation` HiveField 15 is free, even though the spec already grep-verified. State the grep output verbatim in the Task 1 commit message. | Task 1 — must run before any code is written. |

---

## Bite-Sized Task Granularity Reminder

**Each numbered Step is one action (2–5 minutes).** Don't merge. The task list is long because it's TDD-disciplined; resist the urge to fold steps.

---

## Task 0 — Pre-flight & Branch Setup

**Files:** none (just shell + repo state)

**Step 1: Confirm clean working tree**

Run: `git status`
Expected: `nothing to commit, working tree clean` on `main`

**Step 2: Create A1 working branch**

Run: `git checkout -b feature/partner-entity-A1`
Expected: switched to a new branch

**Step 3: Re-grep typeId (Codex constraint C3)**

Run:
```bash
grep -rn 'typeId:' lib/
grep -n '@HiveField' lib/features/conversation/domain/entities/conversation.dart
```
Expected:
- typeId values **0..7** present, **8 absent**
- `Conversation` HiveField values **0..14** present, **15 absent**

**Step 4: Record grep output**

Save the verbatim grep result to your scratchpad — it goes into the Task 1 commit message body so any reviewer can audit C3 after the fact. Do not commit the scratchpad file.

**Step 5: Verify deps**

Run:
```bash
grep -E '^  (uuid|shared_preferences|hive_ce|hive_ce_flutter):' pubspec.yaml
```
Expected: `uuid: ^4.5.0`, `shared_preferences: ^2.5.4`, `hive_ce`, `hive_ce_flutter` all present.

If any are missing → **stop and arbitrate** via `docs/reviews/ai-arbitration-queue.md` (do not silently add deps).

---

## Task 1 — `Partner` entity (Hive `typeId=8`)

**Files:**
- Create: `lib/features/partner/domain/entities/partner.dart`
- Test: `test/unit/entities/partner_test.dart`

**Step 1: Write the failing entity round-trip test**

Create `test/unit/entities/partner_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_entity');
    Hive.registerAdapter(PartnerAdapter());
  });

  group('Partner Hive round-trip', () {
    test('serializes and deserializes all fields', () async {
      final box = await Hive.openBox<Partner>('partner_rt_test');
      addTearDown(() async => box.deleteFromDisk());

      final now = DateTime(2026, 4, 25, 18, 30);
      final p = Partner(
        id: 'p-abc',
        name: '糖糖',
        avatarPath: '/tmp/avatar.png',
        createdAt: now,
        updatedAt: now,
        ownerUserId: 'user-1',
        customNote: '永春附近',
      );
      await box.put(p.id, p);

      final read = box.get(p.id)!;
      expect(read.id, 'p-abc');
      expect(read.name, '糖糖');
      expect(read.avatarPath, '/tmp/avatar.png');
      expect(read.createdAt, now);
      expect(read.updatedAt, now);
      expect(read.ownerUserId, 'user-1');
      expect(read.customNote, '永春附近');
    });
  });
}
```

**Step 2: Run test to confirm it fails**

Run: `flutter test test/unit/entities/partner_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:vibesync/features/partner/domain/entities/partner.dart'`

**Step 3: Write the entity**

Create `lib/features/partner/domain/entities/partner.dart`:

```dart
// lib/features/partner/domain/entities/partner.dart
import 'package:hive_ce/hive_ce.dart';

part 'partner.g.dart';

/// typeId=8 — verified free at 2026-04-25.
/// Occupied at the time of writing:
///   0 Conversation, 1 Message, 2 ConversationSummary,
///   3 MeetingContext, 4 AcquaintanceDuration, 5 UserGoal,
///   6 SessionContext, 7 UserStyle.
/// (Note: the design doc's earlier comment listed these in a different order;
///  the order above is grep-verified against the codebase at A1 implementation.)
@HiveType(typeId: 8)
class Partner extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  String name;

  @HiveField(2)
  String? avatarPath;

  @HiveField(3)
  final DateTime createdAt;

  @HiveField(4)
  DateTime updatedAt;

  @HiveField(5)
  String? ownerUserId;

  @HiveField(6)
  String? customNote;

  Partner({
    required this.id,
    required this.name,
    this.avatarPath,
    required this.createdAt,
    required this.updatedAt,
    this.ownerUserId,
    this.customNote,
  });
}
```

**Step 4: Run codegen**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `partner.g.dart` generated under `lib/features/partner/domain/entities/`.

**Step 5: Re-run the test**

Run: `flutter test test/unit/entities/partner_test.dart`
Expected: PASS (1 test).

**Step 6: Commit**

```bash
git add lib/features/partner/domain/entities/partner.dart \
        lib/features/partner/domain/entities/partner.g.dart \
        test/unit/entities/partner_test.dart
git commit -m "$(cat <<'EOF'
[feat] 加入 Partner Hive entity（typeId=8）

A1 phase task 1 of Partner Entity Refactor。

re-grep typeId（Codex C3）結果：
  lib/features/conversation/domain/entities/conversation.dart:9:@HiveType(typeId: 0)
  lib/features/conversation/domain/entities/message.dart:6:@HiveType(typeId: 1)
  lib/features/conversation/domain/entities/conversation_summary.dart:8:@HiveType(typeId: 2)
  lib/features/conversation/domain/entities/session_context.dart:7:@HiveType(typeId: 7)
  lib/features/conversation/domain/entities/session_context.dart:37:@HiveType(typeId: 3)
  lib/features/conversation/domain/entities/session_context.dart:63:@HiveType(typeId: 4)
  lib/features/conversation/domain/entities/session_context.dart:89:@HiveType(typeId: 5)
  lib/features/conversation/domain/entities/session_context.dart:111:@HiveType(typeId: 6)
typeId 8 unoccupied → 安全使用。

Reviewer-Hint: 確認 codegen 後 .g.dart 包含 PartnerAdapter，且 typeId=8。
Next-Step: 在 Conversation 加 partnerId（HiveField 15）。
EOF
)"
```

---

## Task 2 — `Conversation.partnerId` (HiveField 15)

**Files:**
- Modify: `lib/features/conversation/domain/entities/conversation.dart`
- Test: `test/unit/entities/conversation_partner_id_test.dart` (new)

**Step 1: Write the failing test**

Create `test/unit/entities/conversation_partner_id_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';

void main() {
  group('Conversation.partnerId', () {
    test('defaults to null and is mutable', () {
      final now = DateTime(2026, 4, 25);
      final c = Conversation(
        id: 'c-1',
        name: 'test',
        messages: const [],
        createdAt: now,
        updatedAt: now,
      );
      expect(c.partnerId, isNull);

      c.partnerId = 'p-abc';
      expect(c.partnerId, 'p-abc');
    });
  });
}
```

**Step 2: Run test to confirm it fails**

Run: `flutter test test/unit/entities/conversation_partner_id_test.dart`
Expected: FAIL — `partnerId` getter undefined.

**Step 3: Add the field**

In `lib/features/conversation/domain/entities/conversation.dart`, after the existing `@HiveField(14) String? ownerUserId;`:

```dart
  /// Partner this conversation belongs to.
  /// Populated by Partner migration (A1) for legacy rows; set on creation
  /// once the Partner-first new-conversation flow lands in A2.
  @HiveField(15)
  String? partnerId;
```

Also add `this.partnerId,` to the constructor parameters (positional after `this.ownerUserId,`).

**Step 4: Regenerate adapter**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: `conversation.g.dart` updated; new field 15 written and read.

**Step 5: Run new + existing entity tests**

Run: `flutter test test/unit/entities/`
Expected: all PASS (round-trip on existing data still works because field 15 is nullable and Hive handles missing fields as `null`).

**Step 6: Commit**

```bash
git add lib/features/conversation/domain/entities/conversation.dart \
        lib/features/conversation/domain/entities/conversation.g.dart \
        test/unit/entities/conversation_partner_id_test.dart
git commit -m "[feat] Conversation 加 partnerId 欄位（HiveField 15）

A1 phase task 2。null 預設保留向後相容；既有 14 欄位序列化不動。
Migration（task 6+）會把它從 null 寫成 deterministic UUID v5。

Next-Step: PARTNER_NAMESPACE_UUID 常數 + UUID v5 helper。"
```

---

## Task 3 — `PARTNER_NAMESPACE_UUID` constant + UUID v5 helper

**Files:**
- Create: `lib/features/partner/data/services/partner_id_factory.dart`
- Test: `test/unit/services/partner_id_factory_test.dart` (new)

**Step 1: Write the failing test (deterministic + namespace regression guard)**

Create `test/unit/services/partner_id_factory_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/data/services/partner_id_factory.dart';

void main() {
  group('PartnerIdFactory.deriveFromConversationId', () {
    test('same input always produces same partnerId (deterministic)', () {
      final a = PartnerIdFactory.deriveFromConversationId('conv-abc');
      final b = PartnerIdFactory.deriveFromConversationId('conv-abc');
      expect(a, b);
    });

    test('different inputs produce different partnerIds', () {
      final a = PartnerIdFactory.deriveFromConversationId('conv-abc');
      final b = PartnerIdFactory.deriveFromConversationId('conv-xyz');
      expect(a, isNot(b));
    });

    test(
        'namespace constant must never change '
        '(regression guard — changing breaks idempotency)',
        () {
      // If this test fails, do NOT update the expected value.
      // Instead, revert the namespace change. Existing user data depends on it.
      expect(
        PartnerIdFactory.namespaceForRegressionGuard,
        '6f6e8b5a-4f8b-4e3a-b1c4-2026042501a1',
      );
    });

    test('returns a well-formed UUID v5 string', () {
      final id = PartnerIdFactory.deriveFromConversationId('conv-abc');
      expect(
        id,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-5[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      );
    });
  });
}
```

**Step 2: Run test to confirm it fails**

Run: `flutter test test/unit/services/partner_id_factory_test.dart`
Expected: FAIL — file does not exist.

**Step 3: Implement the factory**

Create `lib/features/partner/data/services/partner_id_factory.dart`:

```dart
// lib/features/partner/data/services/partner_id_factory.dart
import 'package:uuid/uuid.dart';

/// Compile-time constant. Changing this breaks migration idempotency
/// for every existing user. Treat as immutable.
const _kPartnerNamespaceUuid = '6f6e8b5a-4f8b-4e3a-b1c4-2026042501a1';

class PartnerIdFactory {
  PartnerIdFactory._();

  /// Exposed only for the regression-guard test.
  static const namespaceForRegressionGuard = _kPartnerNamespaceUuid;

  /// Returns a deterministic UUID v5 derived from [conversationId].
  /// Same input → same output, across processes and across reruns.
  static String deriveFromConversationId(String conversationId) {
    return const Uuid().v5(_kPartnerNamespaceUuid, conversationId);
  }
}
```

**Step 4: Re-run the test**

Run: `flutter test test/unit/services/partner_id_factory_test.dart`
Expected: PASS (4 tests).

**Step 5: Commit**

```bash
git add lib/features/partner/data/services/partner_id_factory.dart \
        test/unit/services/partner_id_factory_test.dart
git commit -m "[feat] PartnerIdFactory — deterministic UUID v5 from conversation.id

A1 task 3。常數 NAMESPACE_UUID 鎖死，regression guard test 守住。
Migration 用這個 derive partnerId，重跑同 input 收斂同 output。"
```

---

## Task 4 — Wire `Partner` adapter + box into `StorageService`

**Files:**
- Modify: `lib/core/services/storage_service.dart`
- Modify: `lib/core/constants/app_constants.dart`
- Test: `test/unit/services/storage_service_partner_box_test.dart` (new — opens box via test harness)

**Step 1: Add box name constant**

In `lib/core/constants/app_constants.dart`, near the existing `static const conversationsBox = 'conversations';`:

```dart
  static const partnersBox = 'partners';
```

**Step 2: Register adapter + open box in `StorageService.initialize()`**

In `lib/core/services/storage_service.dart`:

- Add import: `import '../../features/partner/domain/entities/partner.dart';`
- After `Hive.registerAdapter(ConversationSummaryAdapter());`, add:
  ```dart
      Hive.registerAdapter(PartnerAdapter()); // A1: Partner Entity Refactor
  ```
- After the `Hive.openBox<Conversation>(...)` call, add:
  ```dart
      await Hive.openBox<Partner>(
        AppConstants.partnersBox,
        encryptionCipher: HiveAesCipher(encryptionKey),
      );
  ```
- Add accessor below `conversationsBox`:
  ```dart
    static Box<Partner> get partnersBox =>
        Hive.box<Partner>(AppConstants.partnersBox);
  ```
- Update `clearAll` to also call `await partnersBox.clear();`.

**Step 3: Smoke-test that box opens & persists across re-open**

Create `test/unit/services/storage_service_partner_box_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

void main() {
  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_box');
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(PartnerAdapter());
    }
  });

  test('Partner box persists across close+reopen', () async {
    final boxName = 'partners_test_${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime(2026, 4, 25);

    var box = await Hive.openBox<Partner>(boxName);
    await box.put(
      'p-1',
      Partner(id: 'p-1', name: '糖糖', createdAt: now, updatedAt: now),
    );
    await box.close();

    box = await Hive.openBox<Partner>(boxName);
    expect(box.get('p-1')?.name, '糖糖');
    await box.deleteFromDisk();
  });
}
```

**Step 4: Run tests**

Run: `flutter test test/unit/services/`
Expected: all PASS (existing service tests unaffected; new test PASS).

**Step 5: Commit**

```bash
git add lib/core/services/storage_service.dart \
        lib/core/constants/app_constants.dart \
        test/unit/services/storage_service_partner_box_test.dart
git commit -m "[feat] StorageService 註冊 PartnerAdapter + 開 partners box

A1 task 4。box 加密同既有規則；clearAll 一併 wipe。
A1 不在這裡 trigger migration，等 task 10 才 wire（先把 schema 落地）。"
```

---

## Task 5 — `PartnerRepository` (minimum needed for migration writes)

A1 only ships the methods the migration uses. Full CRUD + `merge()` lands in A2.

**Files:**
- Create: `lib/features/partner/data/repositories/partner_repository.dart`
- Test: `test/unit/repositories/partner_repository_test.dart` (new)

**Step 1: Write the failing test**

Create `test/unit/repositories/partner_repository_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';

void main() {
  late Box<Partner> box;
  late PartnerRepository repo;

  setUpAll(() {
    Hive.init('./.dart_tool/test_hive_partner_repo');
    if (!Hive.isAdapterRegistered(8)) {
      Hive.registerAdapter(PartnerAdapter());
    }
  });

  setUp(() async {
    box = await Hive.openBox<Partner>(
      'partners_repo_${DateTime.now().microsecondsSinceEpoch}',
    );
    repo = PartnerRepository(box: box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
  });

  test('upsertIfAbsent inserts new partner', () async {
    final now = DateTime(2026, 4, 25);
    final p = Partner(id: 'p-1', name: '糖糖', createdAt: now, updatedAt: now);

    final wrote = await repo.upsertIfAbsent(p);

    expect(wrote, isTrue);
    expect(box.get('p-1')?.name, '糖糖');
  });

  test('upsertIfAbsent is a no-op when partner already exists', () async {
    final now = DateTime(2026, 4, 25);
    final original = Partner(
        id: 'p-1', name: '糖糖', createdAt: now, updatedAt: now);
    await box.put('p-1', original);

    final wrote = await repo.upsertIfAbsent(
      Partner(id: 'p-1', name: 'OVERWRITE', createdAt: now, updatedAt: now),
    );

    expect(wrote, isFalse);
    expect(box.get('p-1')?.name, '糖糖'); // original preserved
  });

  test('getById returns stored partner', () async {
    final now = DateTime(2026, 4, 25);
    await box.put(
        'p-1', Partner(id: 'p-1', name: 'x', createdAt: now, updatedAt: now));
    expect(repo.getById('p-1')?.name, 'x');
    expect(repo.getById('missing'), isNull);
  });
}
```

**Step 2: Run test to confirm failure**

Run: `flutter test test/unit/repositories/partner_repository_test.dart`
Expected: FAIL — file does not exist.

**Step 3: Implement the repository**

Create `lib/features/partner/data/repositories/partner_repository.dart`:

```dart
// lib/features/partner/data/repositories/partner_repository.dart
import 'package:hive_ce/hive_ce.dart';
import '../../../../core/services/storage_service.dart';
import '../../domain/entities/partner.dart';

class PartnerRepository {
  PartnerRepository({Box<Partner>? box}) : _box = box ?? StorageService.partnersBox;

  final Box<Partner> _box;

  Partner? getById(String id) => _box.get(id);

  /// Inserts [partner] only if no partner with the same id exists.
  /// Returns `true` if inserted, `false` if a row already existed.
  /// This is the migration's idempotency primitive.
  Future<bool> upsertIfAbsent(Partner partner) async {
    if (_box.containsKey(partner.id)) return false;
    await _box.put(partner.id, partner);
    return true;
  }
}
```

**Step 4: Run test**

Run: `flutter test test/unit/repositories/partner_repository_test.dart`
Expected: PASS (3 tests).

**Step 5: Commit**

```bash
git add lib/features/partner/data/repositories/partner_repository.dart \
        test/unit/repositories/partner_repository_test.dart
git commit -m "[feat] PartnerRepository — A1 最小可用版（upsertIfAbsent + getById）

只暴露 migration 需要的 surface。CRUD + merge() 留 A2。
upsertIfAbsent 是 idempotent migration 的 primitive：
同 id 第二次寫入是 no-op，不覆寫既有 row。"
```

---

## Task 6 — `PartnerMigrationService` happy path

**Files:**
- Create: `lib/features/partner/data/services/partner_migration_service.dart`
- Test: `test/unit/services/partner_migration_service_test.dart` (new)

**Step 1: Write the failing happy-path test**

Create `test/unit/services/partner_migration_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation_summary.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';
import 'package:vibesync/features/conversation/domain/entities/session_context.dart';
import 'package:vibesync/features/partner/data/repositories/partner_repository.dart';
import 'package:vibesync/features/partner/data/services/partner_id_factory.dart';
import 'package:vibesync/features/partner/data/services/partner_migration_service.dart';
import 'package:vibesync/features/partner/domain/entities/partner.dart';

late Box<Conversation> convoBox;
late Box<Partner> partnerBox;
late PartnerRepository repo;

Future<void> _setUpBoxes() async {
  Hive.init('./.dart_tool/test_hive_partner_migration');
  if (!Hive.isAdapterRegistered(0)) Hive.registerAdapter(ConversationAdapter());
  if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(MessageAdapter());
  if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(ConversationSummaryAdapter());
  if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(MeetingContextAdapter());
  if (!Hive.isAdapterRegistered(4)) Hive.registerAdapter(AcquaintanceDurationAdapter());
  if (!Hive.isAdapterRegistered(5)) Hive.registerAdapter(UserGoalAdapter());
  if (!Hive.isAdapterRegistered(6)) Hive.registerAdapter(SessionContextAdapter());
  if (!Hive.isAdapterRegistered(7)) Hive.registerAdapter(UserStyleAdapter());
  if (!Hive.isAdapterRegistered(8)) Hive.registerAdapter(PartnerAdapter());

  final ts = DateTime.now().microsecondsSinceEpoch;
  convoBox = await Hive.openBox<Conversation>('conv_mig_$ts');
  partnerBox = await Hive.openBox<Partner>('partner_mig_$ts');
  repo = PartnerRepository(box: partnerBox);
}

Future<void> _tearDownBoxes() async {
  await convoBox.deleteFromDisk();
  await partnerBox.deleteFromDisk();
}

Conversation _legacyConv(String id, String name) {
  final t = DateTime(2026, 4, 25);
  return Conversation(
    id: id,
    name: name,
    messages: const [],
    createdAt: t,
    updatedAt: t,
    ownerUserId: 'user-1',
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _setUpBoxes();
  });

  tearDown(_tearDownBoxes);

  test('happy path — N legacy conversations → N partners with deterministic ids',
      () async {
    await convoBox.put('c-1', _legacyConv('c-1', '糖糖'));
    await convoBox.put('c-2', _legacyConv('c-2', '小白'));
    await convoBox.put('c-3', _legacyConv('c-3', '阿狗'));

    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: await SharedPreferences.getInstance(),
    );
    await svc.runIfNeeded();

    expect(partnerBox.length, 3);
    for (final id in ['c-1', 'c-2', 'c-3']) {
      final expectedPartnerId =
          PartnerIdFactory.deriveFromConversationId(id);
      expect(convoBox.get(id)!.partnerId, expectedPartnerId);
      expect(partnerBox.get(expectedPartnerId)?.name,
          convoBox.get(id)!.name);
    }
  });
}
```

**Step 2: Confirm failure**

Run: `flutter test test/unit/services/partner_migration_service_test.dart`
Expected: FAIL — service does not exist.

**Step 3: Implement happy-path service (no backup, no flag yet — added in next tasks)**

Create `lib/features/partner/data/services/partner_migration_service.dart`:

```dart
// lib/features/partner/data/services/partner_migration_service.dart
import 'dart:developer' as developer;

import 'package:hive_ce/hive_ce.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../conversation/domain/entities/conversation.dart';
import '../../domain/entities/partner.dart';
import '../repositories/partner_repository.dart';
import 'partner_id_factory.dart';

const _kMigrationDoneFlag = 'partner_migration_v1_done';
const _kBackupDoneFlag = 'partner_migration_v1_backup_done';
const _kLogTag = 'partner_migration'; // grep-able for future Sentry hookup

class PartnerMigrationService {
  PartnerMigrationService({
    required Box<Conversation> conversationBox,
    required PartnerRepository partnerRepo,
    required SharedPreferences prefs,
    Future<void> Function()? backupConversationBox,
  })  : _convoBox = conversationBox,
        _partnerRepo = partnerRepo,
        _prefs = prefs,
        _backupConversationBox = backupConversationBox;

  final Box<Conversation> _convoBox;
  final PartnerRepository _partnerRepo;
  final SharedPreferences _prefs;
  final Future<void> Function()? _backupConversationBox;

  Future<void> runIfNeeded() async {
    if (_prefs.getBool(_kMigrationDoneFlag) == true) {
      // Perf shortcut — correctness already enforced row-by-row below,
      // so skipping the loop is safe when this flag was set on a prior run.
      return;
    }

    await _ensureBackup();
    await _migrateLoop();

    await _prefs.setBool(_kMigrationDoneFlag, true);
    developer.log('completed', name: _kLogTag);
  }

  Future<void> _ensureBackup() async {
    if (_prefs.getBool(_kBackupDoneFlag) == true) return;
    final hook = _backupConversationBox;
    if (hook != null) {
      await hook(); // throws → flag stays false → next run retries backup
    }
    await _prefs.setBool(_kBackupDoneFlag, true);
    developer.log('backup_completed', name: _kLogTag);
  }

  Future<void> _migrateLoop() async {
    for (final convo in _convoBox.values.toList()) {
      if (convo.partnerId != null) continue;
      try {
        final partnerId =
            PartnerIdFactory.deriveFromConversationId(convo.id);
        await _partnerRepo.upsertIfAbsent(Partner(
          id: partnerId,
          name: convo.name,
          avatarPath: convo.avatarPath,
          createdAt: convo.createdAt,
          updatedAt: convo.updatedAt,
          ownerUserId: convo.ownerUserId,
        ));
        convo.partnerId = partnerId;
        await convo.save();
      } catch (e, st) {
        // Per-convo isolation — failure here must not block other convos.
        developer.log(
          'per_convo_failed',
          name: _kLogTag,
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  /// Test/dev-only entry point. Clears both flags so the next call to
  /// [runIfNeeded] re-runs the entire flow. Exposed for the in-app
  /// "重做升級" button (Task 11).
  Future<void> resetForRedo() async {
    await _prefs.remove(_kMigrationDoneFlag);
    await _prefs.remove(_kBackupDoneFlag);
  }
}
```

**Step 4: Run happy-path test**

Run: `flutter test test/unit/services/partner_migration_service_test.dart`
Expected: PASS (1 test).

**Step 5: Commit**

```bash
git add lib/features/partner/data/services/partner_migration_service.dart \
        test/unit/services/partner_migration_service_test.dart
git commit -m "[feat] PartnerMigrationService — happy path

A1 task 6。每筆 convo derive deterministic partnerId、upsertIfAbsent、
寫回 convo.partnerId、save 落盤。per-convo failure 隔離。
log 用 dart:developer + tag 'partner_migration'，未來接 Sentry 不破 API。

Reviewer-Hint: 這版尚無 idempotent / crash-safe / 改派場景測試 — task 7-8 補。
Next-Step: 加 idempotent rerun test。"
```

---

## Task 7 — Migration idempotency contract test

**Files:**
- Modify: `test/unit/services/partner_migration_service_test.dart` (add test, no source change)

**Step 1: Add test under the same `main()`**

Append inside `main()`:

```dart
  test(
      'idempotent — running twice yields identical state '
      '(partner box size + every convo.partnerId)',
      () async {
    await convoBox.put('c-1', _legacyConv('c-1', '糖糖'));
    await convoBox.put('c-2', _legacyConv('c-2', '小白'));

    final prefs = await SharedPreferences.getInstance();
    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
    );

    await svc.runIfNeeded();
    final firstPartnerIds = partnerBox.keys.toSet();
    final firstConvoMap = {
      for (final c in convoBox.values) c.id: c.partnerId
    };

    // Force a real second pass (clear the perf-shortcut flag).
    await svc.resetForRedo();
    await svc.runIfNeeded();

    expect(partnerBox.keys.toSet(), firstPartnerIds);
    expect(
      {for (final c in convoBox.values) c.id: c.partnerId},
      firstConvoMap,
    );
    expect(partnerBox.length, 2); // no duplicate partners
  });
```

**Step 2: Run**

Run: `flutter test test/unit/services/partner_migration_service_test.dart`
Expected: PASS (2 tests).

**Step 3: Commit**

```bash
git add test/unit/services/partner_migration_service_test.dart
git commit -m "[test] Partner migration idempotent contract — 跑兩次無 diff

A1 task 7。回應 Codex P1：正確性 = deterministic UUID v5 + per-convo marker，
與 SharedPreferences flag 解耦。"
```

---

## Task 8 — Migration crash-safe contract test

**Files:**
- Modify: `lib/features/partner/data/services/partner_migration_service.dart` (expose seam)
- Modify: `test/unit/services/partner_migration_service_test.dart`

**Step 1: Add a per-convo write hook seam (test-only injection)**

In the service constructor, add an optional callback:

```dart
    void Function(Conversation convo)? onBeforeSavePerConvo,
```

Store as `_onBeforeSavePerConvo` and call it inside `_migrateLoop` right before `await convo.save();`. In production no callback is passed → behaviour unchanged.

```dart
        _onBeforeSavePerConvo?.call(convo);
        await convo.save();
```

**Step 2: Add the crash-safe rerun test**

```dart
  test(
      'crash-safe — interrupted mid-loop then rerun = same final state '
      'as a single uninterrupted run',
      () async {
    for (var i = 1; i <= 5; i++) {
      await convoBox.put('c-$i', _legacyConv('c-$i', 'p-$i'));
    }
    final prefs = await SharedPreferences.getInstance();

    // Round 1 — boom on the 3rd convo.
    var calls = 0;
    final svc1 = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
      onBeforeSavePerConvo: (_) {
        calls++;
        if (calls == 3) throw StateError('simulated crash');
      },
    );
    await svc1.runIfNeeded();

    // Crash means the done-flag was NOT written. Backup flag was, though,
    // because backup happens once before any per-convo save.
    expect(prefs.getBool(_kMigrationDoneFlagForTest), isNot(true));
    final partial = convoBox.values
        .where((c) => c.partnerId != null)
        .length;
    expect(partial, lessThan(5));

    // Round 2 — fresh service, no crash. Should converge.
    final svc2 = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
    );
    await svc2.runIfNeeded();

    // Every convo has a partnerId, partnerBox holds exactly 5 partners,
    // and every partnerId equals the deterministic derive.
    for (var i = 1; i <= 5; i++) {
      final c = convoBox.get('c-$i')!;
      expect(c.partnerId,
          PartnerIdFactory.deriveFromConversationId('c-$i'));
    }
    expect(partnerBox.length, 5);
  });
```

> The test references `_kMigrationDoneFlagForTest`. Expose the flag string from the service file (or just inline the literal `'partner_migration_v1_done'` in the test — pick one and stay consistent. Inlining is acceptable for a regression-guard test.)

**Step 3: Run**

Run: `flutter test test/unit/services/partner_migration_service_test.dart`
Expected: PASS (3 tests).

**Step 4: Commit**

```bash
git add lib/features/partner/data/services/partner_migration_service.dart \
        test/unit/services/partner_migration_service_test.dart
git commit -m "[test] Partner migration crash-safe — 中斷後重跑收斂

A1 task 8。inject 第 3 筆 throw → 重跑用 PartnerRepository.upsertIfAbsent
+ 既寫 partnerId 的 convo skip → final state 與一次跑完位元級相同。
回應 Codex P1：crash 容錯不靠 SharedPreferences flag。"
```

---

## Task 9 — Backup hook + backup-fail-blocks-loop test

**Files:**
- Modify: `test/unit/services/partner_migration_service_test.dart`

**Step 1: Add the test**

```dart
  test('backup throw → done flag stays false → loop did NOT run',
      () async {
    await convoBox.put('c-1', _legacyConv('c-1', '糖糖'));
    final prefs = await SharedPreferences.getInstance();
    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
      backupConversationBox: () async {
        throw StateError('simulated disk full during backup');
      },
    );

    await expectLater(svc.runIfNeeded(), throwsA(isA<StateError>()));

    expect(prefs.getBool('partner_migration_v1_done'), isNot(true));
    expect(prefs.getBool('partner_migration_v1_backup_done'), isNot(true));
    expect(convoBox.get('c-1')!.partnerId, isNull); // loop never ran
    expect(partnerBox.length, 0);
  });

  test('backup runs only once across reruns', () async {
    await convoBox.put('c-1', _legacyConv('c-1', '糖糖'));
    final prefs = await SharedPreferences.getInstance();
    var backupCalls = 0;

    final svc = PartnerMigrationService(
      conversationBox: convoBox,
      partnerRepo: repo,
      prefs: prefs,
      backupConversationBox: () async => backupCalls++,
    );
    await svc.runIfNeeded();
    await svc.resetForRedo();
    await svc.runIfNeeded();

    expect(backupCalls, 1);
    // Reset clears both flags by design (see service comment); however
    // backup is gated on _kBackupDoneFlag specifically. resetForRedo
    // is documented to also wipe the backup flag → backup runs again.
    // If product wants "backup once forever", swap resetForRedo to
    // only clear the migration flag. For A1 we accept the redo-rebackup.
  });
```

> If the product call is "redo should also re-backup" (current spec implies yes — the redo flow is for repair after suspected corruption), the second test will need `expect(backupCalls, 2)` and the comment block updated. Leave a `// TODO[A2]:` line if Eric wants to revisit. **Do not silently change product behaviour.** If unsure, **stop and arbitrate** via the queue.

**Step 2: Run**

Run: `flutter test test/unit/services/partner_migration_service_test.dart`
Expected: PASS (5 tests; adjust the second test's expected count to match the chosen redo policy).

**Step 3: Commit**

```bash
git add test/unit/services/partner_migration_service_test.dart
git commit -m "[test] Partner migration backup gate — fail blocks loop

A1 task 9。備份 throw → migration loop 不啟動，下次重跑會重備份。
redo 政策測試先以「redo 重備份」為準（spec §5 第 6 點隱含此語意）。"
```

---

## Task 10 — Wire `runIfNeeded()` into `StorageService.initialize()`

**Files:**
- Modify: `lib/core/services/storage_service.dart`
- Test: `test/unit/services/storage_service_partner_migration_wire_test.dart` (light wiring sanity test)

**Step 1: Add the wiring after both boxes are open**

In `StorageService.initialize()`, after the `partnersBox` is opened:

```dart
    final prefs = await SharedPreferences.getInstance();
    final migration = PartnerMigrationService(
      conversationBox: conversationsBox,
      partnerRepo: PartnerRepository(box: partnersBox),
      prefs: prefs,
      backupConversationBox: _backupConversationBox,
    );
    await migration.runIfNeeded();
```

Add a private `_backupConversationBox()` that copies the conversations Hive file alongside as `<filename>.partner_migration_backup`. (Implementation: read the underlying Hive file path via `box.path`, copy with `dart:io`. If the platform doesn't expose `box.path` — Web — short-circuit to `Future.value()`; A1 ships mobile-only, but Web must not crash on init.)

**Step 2: Sanity test**

Skip a deep integration test here — the integration test in Task 12 covers end-to-end. Just assert `StorageService.initialize()` is callable twice without throwing on the test harness.

**Step 3: Run all tests**

Run: `flutter test`
Expected: ALL PASS.

**Step 4: Commit**

```bash
git add lib/core/services/storage_service.dart \
        test/unit/services/storage_service_partner_migration_wire_test.dart
git commit -m "[feat] StorageService.initialize 串入 PartnerMigrationService

A1 task 10。app 啟動時自動跑 migration（done flag 已寫 → 跳過 loop）。
Web 平台 backup short-circuit（A1 mobile 先；Web 不 crash）。"
```

---

## Task 11 — In-app 「重做升級」 entry (Settings → Advanced)

**Files:**
- Modify: existing settings screen (locate via `grep -rn "設定" lib/features/settings/` — pick the screen that already hosts advanced options; do **not** create a new screen)
- Test: widget test asserting the button calls `resetForRedo` then `runIfNeeded`

**Step 1: Locate the host screen**

Run:
```bash
grep -rln "Settings\|設定" lib/features/settings/ 2>/dev/null
```
Use the most senior settings screen file that already holds debug/advanced toggles. If none exists, **stop and arbitrate** — Eric needs to decide where the entry lives.

**Step 2: Write a widget test for the button**

Skeleton (adapt to the chosen screen):

```dart
testWidgets('重做升級 button clears flags then re-runs migration', (tester) async {
  // pump the screen with mocked PartnerMigrationService that records calls
  // tap the button, verify resetForRedo + runIfNeeded called in that order
});
```

**Step 3: Confirm failure → implement → confirm pass → commit**

```bash
git add <chosen settings screen> test/widget/screens/settings_redo_upgrade_test.dart
git commit -m "[feat] 設定 → 進階 → 重做升級 入口

A1 task 11。清掉兩個 flag 強制重跑 migration（仍 idempotent，不會 corrupt）。
測試帳號 / Bruce 真機萬一 box 異常時的急救工具。"
```

> **If unsure where the button belongs in current settings IA, write only the service plumbing in this task and defer the actual Settings UI hookup to A2.** Mark as `[chore]` instead of `[feat]` and update Task 13's checklist accordingly. Do not invent a new settings screen for A1.

---

## Task 12 — Integration test: Bruce-shaped legacy data

**Files:**
- Create: `test/integration/partner_migration_integration_test.dart`

**Step 1: Write the failing test**

```dart
// Mirror the Bruce scenario: 5 owner-scoped legacy conversations, 2 with
// duplicate names ("糖糖"). After migration:
//  - 5 distinct Partner rows, deterministic ids
//  - every conversation.partnerId set
//  - duplicate-name conversations remain SEPARATE Partners (Migration B,
//    per ADR-15 + design doc Brainstorm decision)
//  - rerun is a no-op
//  - simulated mid-loop crash followed by rerun converges to the same state
```

(Use the same harness as the unit test but realistic conversation payloads — messages, summaries, `lastEnthusiasmScore`, `ownerUserId`, etc. The point is to prove Hive serialization round-trips through migration without data loss.)

**Step 2: Run**

Run: `flutter test test/integration/`
Expected: PASS.

**Step 3: Commit**

```bash
git add test/integration/partner_migration_integration_test.dart
git commit -m "[test] Partner migration integration — Bruce 場景 + crash 變體

A1 task 12。5 段對話含 2 段同名 → migration 後 5 個獨立 Partner（Migration B 行為）。
crash 變體驗證 deterministic + idempotent 收斂。"
```

---

## Task 13 — TF soak gate + closeout

This is **NOT** "code complete = ship A2". Codex constraint **C2** says A1 needs **1–2 days of TF soak** before A2 starts.

**Step 1: Run the full test suite**

Run: `flutter test`
Expected: ALL PASS, no skipped tests in the partner area.

**Step 2: Manual verification on physical device (you, Eric, or Bruce)**

Checklist (paste into the queue item update, not into a new doc):
- [ ] Fresh install — no existing conversations → no migration log spam, app boots
- [ ] Upgrade install on a build that has 4–5 legacy conversations → app boots, every legacy conversation now has a `partnerId` (verify via debug logs)
- [ ] Force-kill app mid-migration (devmode entry to throw on convo #3) → relaunch → migration converges, no duplicate Partner rows
- [ ] 重做升級 button clears flags and re-migrates without data loss
- [ ] Account switch — Partner rows from user A do not leak into user B's view (A1 just asserts `partnerBox` size; UI verification lands in A2)

**Step 3: Update `docs/decisions.md` ADR-15**

Flip the status line:
```
**狀態**: 🟢 Active (A1 shipped — TF soak in progress YYYY-MM-DD .. YYYY-MM-DD)
```
Add a one-line "A1 ship" entry. **Do not** rewrite the decision body.

**Step 4: Open a NEW queue item for A1 code review (do not reopen the closed spec-review item)**

The spec-review item (`Status: CLOSED` since the plan was written) is a different decision. Add a fresh item at the top of `docs/reviews/ai-arbitration-queue.md`:

```
## [YYYY-MM-DD] Partner Entity Refactor — A1 Implementation Code Review
Status: OPEN
Request-Type: review
Raised-By: Claude
Owner: Codex
Scope: review
Branch/Commit: feature/partner-entity-A1 @ <sha>

HS-Review-Asks (Eric 2026-04-25):
- HS1 Sentry SDK gap: A1 uses dart:developer.log + tag 'partner_migration'.
  Acceptable for TF soak, or should sentry_flutter be added? See plan §"Codex
  Review Hot Spots" HS1.
- HS2 Redo-backup policy: 重做升級 currently re-takes the backup on every
  redo (overwrites prior). Alternative is one-shot backup. See plan HS2.

Context: <one paragraph: scope, A1 vs A2 split, migration B>
Changed: <files, test counts>
Evidence: <commit shas, test run output, manual TF observations>
Open-Risks: <e.g. Web platform untested, settings UI hookup deferred>
Claude-Position: <faithful-to-spec summary; explicit calls on HS1 + HS2>
Codex-Position: Pending
Verdict: Pending
Action-Items:
- [ ] Codex reviews diff against design doc v2
- [ ] Codex rules on HS1 + HS2
- [ ] If HS1/HS2 fail → rebuttal in docs/reviews/ + spec or plan amendment
Close-Condition: A1 lands on main with HS1 + HS2 resolved.
```

**Step 5: Closeout per shared matrix**

The **only** docs that should be touched in this session:
1. ✅ `docs/decisions.md` — ADR-15 status flip (matrix item #5)
2. ✅ `docs/reviews/ai-arbitration-queue.md` — handoff to Codex (matrix item #7)
3. ❌ **NOT** `docs/snapshot.md` — A1 alone is not a stage change; A2 ship is
4. ❌ **NOT** `docs/bug-log.md` — no bug fixed
5. ❌ **NOT** `README.md` — onboarding flow unchanged
6. ❌ **NOT** `CLAUDE.md` / `AGENTS.md` — no new shared rule
7. ❌ **NOT** a fresh `docs/reviews/2026-04-XX_*.md` file — the queue item carries the handoff

**Step 6: Push**

```bash
git push -u origin feature/partner-entity-A1
```

Open PR with the design doc + ADR-15 linked in the body. **Do NOT merge to main until TF soak is signed off.**

**Step 7: TF soak — start a 1–2 day timer (Codex C2)**

A2 plan-writing must not start until either:
- 1–2 calendar days of TF use without crash / Hive corruption / Sentry-equivalent log spike, OR
- Eric explicitly acknowledges he wants to skip the soak and accept the risk in writing in the queue.

---

## Out of A1 Scope (do NOT touch in this branch)

- Partner list UI on the home screen
- Partner detail screen + radar summary card
- AI prompt Partner-summary assembly + truncation
- Merge UI / 改派 UI
- Routing changes (`/partner/:partnerId`)
- `partnerAggregateProvider` / `conversationsByPartnerProvider` — see **Codex C1** above; the partner-scoped provider is an A2 responsibility. If A1 accidentally introduces a global fan-out provider here, it locks A2 into either a breaking change or a hidden perf regression. Resist.
- Sentry SDK integration (not currently wired; the migration logs to `dart:developer` with the tag `partner_migration` so a future Sentry hookup is a one-line search-and-replace)

---

## Estimated Effort (per Codex C2 re-review)

- Code + unit tests: **2 dev days**
- Integration test + manual TF: **0.5–1 dev day**
- TF soak before A2 starts: **1–2 calendar days**

Total wall-clock before A2 plan: **3.5–5 days**, not the original 1.5.

---

## Risk Register

| Risk | Mitigation |
|---|---|
| Codegen drift between `Partner` and `Conversation` adapters across machines | `build_runner` is hermetic per-pubspec.lock; tests catch any drift |
| Hive box opens before adapter registered | Task 4 ordering enforces register-before-open; integration test pins this |
| Backup file fills disk on low-storage devices | Backup is only the conversations Hive box (typically <1MB for VibeSync data); add size guard only if soak surfaces a crash |
| User switches account mid-migration | Migration is owner-agnostic on the partnerId derive (UUID v5 from `convo.id`), so cross-owner migrations stay isolated by virtue of Conversation's existing `ownerUserId` filtering at read time |
| Web platform crashes on backup hook | Task 10 short-circuits backup on Web; A1 ships mobile-only so Web is "must not crash on init" only |
| `_onBeforeSavePerConvo` test seam ships to production | It is a constructor-injected null-defaulted callback; production callers don't pass it. Code review must catch any prod call site that does. |

---

## Glossary (for the executing engineer who has zero context)

- **Migration B** — Eric's brainstorm-locked decision: every existing Conversation becomes its **own** Partner. No name-based auto-merge in A1. Bruce's "two 糖糖 cards" stay two Partners; merge UI in A2 lets him collapse them by hand.
- **A1 vs A2** — A1 is "schema + migration, no UI". A2 is "Partner-first home screen + AI prompt summary + merge UI". They ship sequentially with TF soak between.
- **Closeout matrix** — `docs/shared-agent-rules.md` §"Closeout Matrix". Default is **write nothing**; every doc edit must point to a numbered matrix trigger.
- **Queue item** — the single live entry per task in `docs/reviews/ai-arbitration-queue.md`. Update in place, don't append a new one.
