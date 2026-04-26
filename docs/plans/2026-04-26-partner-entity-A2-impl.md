# Partner Entity Refactor A2 — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.
>
> **For Codex (spec review)**: see `## Codex Review Hot Spots` near the end. Plan-level Daisy-Decision-Needed markers are listed under `## Daisy-Decision-Needed` and must be resolved before execution starts.

**Goal**: Ship the Partner-first UI/UX layer + AI-prompt Partner summary on top of the A1 schema/migration baseline (`919e034`), so the user-facing app reflects ADR-15's information architecture without changing data semantics.

**Architecture**:
- Riverpod **partner-scoped narrow invalidation** (`partnerAggregateProvider(partnerId)` only listens to `conversationsByPartnerProvider(partnerId)`, not the global conversation list — locks Codex C1 constraint).
- Partner summary built **client-side, on demand, no caching** — assembled at prompt time from `Conversation.lastAnalysisSnapshotJson` parsed fields under a hard `1500`-char cap (Codex P2 envelope).
- UI extends existing Clean Architecture: `lib/features/partner/presentation/` is new; `conversation/` keeps existing screens with minimal reroute / breadcrumb changes.
- Routing: add `/partner/:partnerId`; keep `/conversation/:id` for back-compat (deep link + share survival).

**Tech Stack**: Flutter 3.x · Riverpod · Hive (read-only — no schema change in A2) · `fl_chart` (existing radar) · go_router (existing).

**Locked decisions** (do not reopen — ADR-15):
- IA: 2-tier Home(Partner list) → Partner detail
- Migration B: per-Conversation = independent Partner + manual merge UI
- Aggregation A Union: traits 聯集去重 / heat=latest / counts=sum / last=max
- AI context C Hybrid: current-conversation full messages + Partner summary
- 我的報告 tab D: tab unchanged + Partner detail radar mini-card
- Phase A Big Bang: A2 = ~7-8 dev days

---

## Daisy-Decision-Needed

These are A2-specific UX gaps the design doc did **not** lock. Codex review will mark anything ambiguous with `Verdict: Daisy-Decision-Needed`. Eric should resolve before Task execution starts; defaults below (marked **Plan-default**) apply if no decision.

### D1 — 第一次截圖建對話時，Partner 怎麼掛？

當用戶從首頁 FAB **「+ 新增對象」** → 進到空 Partner detail → 點 **「+ 新增對話」** → 既有 3 選項 popup（手動 / 截圖 / 開場救星）→ 選截圖 → 進 OCR → 第一張截圖完成 OCR 之後：

| 選項 | 行為 | UX 感受 | 風險 |
|---|---|---|---|
| **A**（**Plan-default**） | 用戶**已先**透過「+ 新增對象」建好 Partner，截圖 flow 直接掛在那個 Partner 下，不再多問 | 線性、最少步驟 | 用戶若從別處進入截圖 flow（例如首頁尚未 partner-list 化前的舊路徑）需要 fallback |
| B | 截圖完成後彈 picker：「這是你跟誰的對話？」可選既有 partner 或建新 | 多一步、但較精準 | 流程變長、Bruce 抱怨可能再現 |
| C | 自動建匿名 Partner（命名 `對象 #abc` 用 id 末 4 碼），用戶後續可在 Partner detail 改名 | 最少打斷、自動化 | 同名情境下 Bruce 痛點會以「未命名對象」形式重現 |

**Plan-default**: A — 已有 Partner detail 「+ 新增對話」入口承擔，無需再彈 picker。

**Why this matters**: Bruce 原本痛點就是「同人不同段對話 → 兩張獨立卡」。如果走 C，Free-tier 用戶大量產生「對象 #abc」匿名 entries，首頁會更亂，問題沒解。

---

### D2 — Copy sweep 範圍 / domain 是否 rename

design doc §2 寫死 UI 用「對象」/「對話」雙層詞彙（Home FAB =「+ 新增對象」、Partner detail 的「+ 新增對話」），但 **`Conversation` Hive entity / repository / class names** 是否同步改？

| 選項 | 行為 | 估時 | 風險 |
|---|---|---|---|
| **A**（**Plan-default**） | UI 文案 only，domain 層 `Conversation` 不動 | +0.0 day | UI 與 code 詞彙不同（reader confusion） |
| B | UI + domain 層 rename `Conversation` → `ChatSession`，引入 `Partner` + `ChatSession` 雙層命名 | +1.5-2.0 day（高 churn：Hive type adapters / repository / Riverpod providers / 全部 import / 測試） | 高 blast radius；A1 schema 才剛穩定 |
| C | UI + domain 層 rename `Conversation` 內部變數但保留 typeId / Hive 序列化 schema | +0.8 day | 介於 A 與 B 之間，但雙層 mental model 仍混 |

**Plan-default**: A — domain 層保留 `Conversation` 名稱不動，UI 才用「對話 / 對象」。理由：A1 schema baseline 才穩，同期再大規模 rename 撞測試 + Codex review 時間。如 A2 ship 後仍覺名稱礙眼可走 post-A2 cleanup PR。

---

### D3 — Partner detail 的 conversation cell tap 行為

| 選項 | 行為 |
|---|---|
| **A**（**Plan-default**） | tap → 進 `analysis_screen`（既有對話分析頁，雷達 + 五回覆 + 繼續對話），與舊版 home tap 行為一致 |
| B | tap → 進 conversation overview（messages 列表 + 中繼資料），再多一步才到 analysis |

**Plan-default**: A — 與舊版心智模型一致、最少破壞。

---

### D4 — Same-name banner 顯示時機與門檻

design doc §4「Migration 後同名一堆」說一次性 banner「偵測到 N 組同名對象，要合併嗎？」。觸發時機沒寫死。

| 選項 | 行為 |
|---|---|
| **A**（**Plan-default**） | 進到 Partner list 首頁時偵測，detected ≥1 同名組則顯示；用戶按「合併」走 merge UI / 按「以後再說」**永久關閉**（寫 SharedPreferences flag `partner_dedupe_banner_dismissed`） |
| B | 每次 cold start 都偵測；只要還有同名組就顯示 |
| C | 只在 migration 完成後第一次進首頁顯示，之後不再 |

**Plan-default**: A — 夠彈性又不糾纏。

---

## Pre-flight（執行任何 Task 前必跑）

```bash
# 確認 main 在 919e034 之後且沒有 unmerged soak hotfix
git log --oneline -10
git status

# typeId / HiveField 衝突再 grep（A1 plan 已 grep，但 A2 期間若有 hotfix 改過任何 Hive entity 必須重驗）
grep -rn 'typeId:' lib/ | sort
grep -rn '@HiveField(15)' lib/

# 既有 home / new_conversation / analysis 三 screen 行為當前狀態（A2 改動 baseline）
flutter test --reporter expanded test/widget/home_screen_test.dart 2>&1 | tail -20 || true
```

預期：
- typeId 0..8 全占用，無新衝突
- `Conversation.partnerId @HiveField(15)` 已在 A1 ship
- Home screen test baseline 跑得過或已被標 skip（A1 沒動 home flow）

---

## Branch / Commit Strategy

- **新 branch**: `feature/partner-entity-A2`（從最新 `main` 切）
- **絕對不 rebase 進 A1 branch** `feature/partner-entity-A1`（保留 fallback）
- 每 Task 一個（或多個）原子 commit；commit trailer 必含：
  - `Reviewer-Hint: ...`（若有不確定）
  - `Next-Step: ...`（若有銜接）
- **每 commit 後立即 push**（全域 CLAUDE.md 規則）
- 全部 Task 完成且 `flutter test` + `flutter analyze` 全綠 → 開 PR 喊 Codex code review

---

## Task 1 — PartnerAggregates extension（聚合邏輯，pure dart）

**Files:**
- Create: `lib/features/partner/domain/extensions/partner_aggregates.dart`
- Test: `test/unit/features/partner/partner_aggregates_test.dart`

**Why first**: 純函數、無 I/O、無 UI 依賴，給後續 provider / summary builder / detail screen 共用。

**Step 1: Write failing tests**

```dart
// test/unit/features/partner/partner_aggregates_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:vibesync/features/partner/domain/extensions/partner_aggregates.dart';
// ... import Partner / Conversation

void main() {
  group('PartnerAggregates', () {
    test('unionInterests dedupes across conversations', () {
      // Arrange: 3 conversations with overlapping interests
      // Act: partner.unionInterests(conversations)
      // Assert: deduped, ordered by lastInteraction desc, top N=8
    });

    test('unionTraits dedupes + ranks by recency', () { /* ... */ });

    test('latestHeat = max-recency conversation lastEnthusiasmScore', () { /* ... */ });

    test('totalRounds sums currentRound across all conversations', () { /* ... */ });

    test('totalMessages sums messages.length across all conversations', () { /* ... */ });

    test('lastInteraction = max(updatedAt) across all conversations', () { /* ... */ });

    test('empty conversation list returns safe defaults (0, [], null)', () { /* ... */ });

    test('unionNotes preserves chronological order, joined with newline', () { /* ... */ });
  });
}
```

**Step 2: Run, expect FAIL**

```bash
flutter test test/unit/features/partner/partner_aggregates_test.dart
# Expected: compilation error (extension does not exist)
```

**Step 3: Minimal implementation**

```dart
// lib/features/partner/domain/extensions/partner_aggregates.dart
import 'package:vibesync/features/partner/domain/entities/partner.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';

class PartnerAggregateView {
  final List<String> unionInterests;
  final List<String> unionTraits;
  final String? unionNotes;
  final int latestHeat;
  final int totalRounds;
  final int totalMessages;
  final DateTime? lastInteraction;

  const PartnerAggregateView({
    required this.unionInterests,
    required this.unionTraits,
    required this.unionNotes,
    required this.latestHeat,
    required this.totalRounds,
    required this.totalMessages,
    required this.lastInteraction,
  });

  factory PartnerAggregateView.empty() => const PartnerAggregateView(
        unionInterests: [],
        unionTraits: [],
        unionNotes: null,
        latestHeat: 0,
        totalRounds: 0,
        totalMessages: 0,
        lastInteraction: null,
      );
}

extension PartnerAggregates on Partner {
  PartnerAggregateView aggregateOver(List<Conversation> conversations) {
    if (conversations.isEmpty) return PartnerAggregateView.empty();
    // sort by updatedAt desc, take top-recency for ranking
    final sorted = [...conversations]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    // (impl: extract from lastAnalysisSnapshotJson; dedupe; cap N=8)
    // return assembled PartnerAggregateView
    // ...
  }
}
```

(Full implementation: parse `lastAnalysisSnapshotJson` per-conversation for `interests` / `traits` / `notes` lists; dedupe across all; rank by `updatedAt` desc; cap interests/traits at N=8; notes joined newline-separated; latestHeat = sorted[0].lastEnthusiasmScore; totalRounds / totalMessages = sum; lastInteraction = sorted[0].updatedAt.)

**Step 4: Run, expect PASS**

```bash
flutter test test/unit/features/partner/partner_aggregates_test.dart
```

**Step 5: Commit**

```bash
git add lib/features/partner/domain/extensions/ test/unit/features/partner/partner_aggregates_test.dart
git commit -m "$(cat <<'EOF'
[feat] PartnerAggregates extension — union/latest/sum 規則

Reviewer-Hint: 取 N=8 ranking 由 updatedAt desc，注意空 list / null notes 邊界
Next-Step: T2 Repository.listByOwner / T3 Riverpod narrow invalidation
EOF
)"
git push
```

---

## Task 2 — PartnerRepository extension：listByOwner + merge

**Files:**
- Modify: `lib/features/partner/data/repositories/partner_repository.dart`
- Test: `test/unit/features/partner/partner_repository_test.dart`（已存在 — A1）

**Step 1: Add failing tests**

```dart
test('listByOwner returns only partners with matching ownerUserId', () { /* ... */ });
test('listByOwner returns empty list for unknown owner', () { /* ... */ });

test('merge moves all conversations from A to B partnerId=B.id', () { /* ... */ });
test('merge appends A.customNote into B.customNote with [from A] prefix', () { /* ... */ });
test('merge deletes Partner A after re-pointing', () { /* ... */ });
test('merge is idempotent if B does not exist (throws ArgumentError, no partial state)', () { /* ... */ });
test('merge of A=B is no-op (same id)', () { /* ... */ });
```

**Step 2: Run, expect FAIL**

**Step 3: Implement**

```dart
// in PartnerRepository
List<Partner> listByOwner(String ownerUserId) =>
    box.values.where((p) => p.ownerUserId == ownerUserId).toList();

Future<void> merge({required String fromId, required String toId}) async {
  if (fromId == toId) return;
  final from = box.get(fromId);
  final to = box.get(toId);
  if (from == null || to == null) {
    throw ArgumentError('merge source or target not found');
  }
  // Step 1: re-point conversations
  for (final convo in conversationBox.values
      .where((c) => c.partnerId == fromId)) {
    convo.partnerId = toId;
    await convo.save();
  }
  // Step 2: append note (preserve history)
  if ((from.customNote ?? '').isNotEmpty) {
    final tag = '[from ${from.name}]';
    to.customNote = (to.customNote ?? '').isEmpty
        ? '$tag ${from.customNote}'
        : '${to.customNote}\n$tag ${from.customNote}';
  }
  to.updatedAt = DateTime.now();
  await to.save();
  // Step 3: delete source partner
  await box.delete(fromId);
}
```

**Step 4: Run, expect PASS**

**Step 5: Commit**

```bash
git commit -m "[feat] PartnerRepository.listByOwner + merge"
git push
```

---

## Task 3 — Riverpod providers + ConversationWriteController（narrow invalidation contract）

**Files:**
- Create: `lib/features/partner/presentation/providers/partner_providers.dart`
- Create: `lib/features/conversation/data/providers/conversation_write_controller.dart`（**new — invalidation owner**）
- Modify: `lib/features/conversation/data/repositories/conversation_repository.dart`（**新增** `listByPartner(partnerId)`，read-only filter；**不**注入 `Ref`）
- Modify (UI migration, 9 sites): `new_conversation_screen.dart` / `home_screen.dart` / `main_shell.dart` / `analysis_screen.dart`
- Test: `test/unit/features/partner/partner_providers_test.dart`
- Test: `test/unit/features/conversation/conversation_write_controller_test.dart`

**Architecture decision (locked 2026-04-26 by Eric, post Codex P1)**:
- Invalidation owner = `ConversationWriteController extends Notifier<void>`（Riverpod 2.x），集中持有所有 conversation 寫入（create / save / delete / reassign），由 controller 統一 `ref.invalidate(...)` partner-scoped providers。
- `ConversationRepository` **保持** A1 plain storage wrapper、**不**注入 Riverpod `Ref`（A1 stable baseline 不 poke）。
- 9 個既有 UI invalidate 呼叫點（grep 2026-04-26 確認）全部改走 controller，由 controller 端做 narrow invalidate。

**Codex C1 constraint**: `partnerAggregateProvider(partnerId)` 必須只訂閱 `conversationsByPartnerProvider(partnerId)`，**不**訂閱全 `conversationsProvider`。寫 conversation A → controller 只 invalidate `conversationsByPartnerProvider(A.partnerId)` + `partnerAggregateProvider(A.partnerId)`，其他 partner provider 不受影響。

**Step 1: Failing tests**

```dart
// partner_providers_test.dart
test('conversationsByPartnerProvider returns only conversations with matching partnerId', () { /* ... */ });
test('conversationsByPartnerProvider does not depend on global conversationsProvider', () {
  // Critical: assert provider.dependencies does NOT include conversationsProvider
  // (use ProviderContainer + ref.read introspection or static analysis comment hint)
});

test('partnerAggregateProvider invalidates ONLY when controller writes affect this partner', () {
  // Arrange: 2 partners X, Y; subscribe to both aggregates
  // Act: ref.read(conversationWriteControllerProvider.notifier).save(c) where c.partnerId == X
  // Assert: aggregateProvider(X) rebuilt; aggregateProvider(Y) unchanged
});

test('reassigning conversation from X to Y invalidates BOTH X and Y', () {
  // Act: controller.save(c, previousPartnerId: X) where c.partnerId == Y
  // Assert: aggregateProvider(X) AND aggregateProvider(Y) both rebuilt
});

test('partnerListProvider sorts by max(conv.updatedAt) across each partner conversations', () { /* ... */ });

// conversation_write_controller_test.dart
test('save() persists via repository then invalidates partnerAggregateProvider for current partnerId', () {
  // mock repo; assert repo.updateConversation called once; assert invalidate logged once
});
test('save() with previousPartnerId different from new partnerId invalidates BOTH partners', () { /* ... */ });
test('create() invalidates the new partnerAggregateProvider', () { /* ... */ });
test('delete() invalidates partnerAggregateProvider for the conversation\'s partnerId', () { /* ... */ });
test('controller does NOT invalidate global conversationsProvider', () {
  // narrow contract: assert no invalidate on conversationsProvider
});
test('controller no-ops invalidate when partnerId is null (legacy / unmigrated conversations)', () { /* ... */ });
```

**Step 2: Run, expect FAIL**

**Step 3: Implement**

```dart
// lib/features/partner/presentation/providers/partner_providers.dart
final partnerListProvider = Provider<List<Partner>>((ref) {
  final userId = ref.watch(authConversationScopeProvider).valueOrNull;
  if (userId == null) return const <Partner>[];
  final repo = ref.watch(partnerRepositoryProvider);
  final partners = repo.listByOwner(userId);
  partners.sort((a, b) {
    final aLast = ref.watch(_partnerLastInteractionProvider(a.id));
    final bLast = ref.watch(_partnerLastInteractionProvider(b.id));
    return (bLast ?? a.createdAt).compareTo(aLast ?? a.createdAt);
  });
  return partners;
});

// CRITICAL: scoped to partnerId — NOT subscribed to global conversationsProvider
final conversationsByPartnerProvider =
    Provider.family<List<Conversation>, String>((ref, partnerId) {
  ref.watch(authConversationScopeProvider); // bind to auth scope, not global conversation list
  final repo = ref.watch(conversationRepositoryProvider);
  return repo.listByPartner(partnerId);
});

final partnerAggregateProvider =
    Provider.family<PartnerAggregateView, String>((ref, partnerId) {
  final partner = ref.watch(partnerByIdProvider(partnerId));
  final conversations = ref.watch(conversationsByPartnerProvider(partnerId));
  return partner?.aggregateOver(conversations) ?? PartnerAggregateView.empty();
});
```

```dart
// lib/features/conversation/data/providers/conversation_write_controller.dart
class ConversationWriteController extends Notifier<void> {
  @override
  void build() {} // stateless write coordinator

  Future<Conversation> create({
    required String name,
    required List<Message> messages,
    required String partnerId,
  }) async {
    final repo = ref.read(conversationRepositoryProvider);
    final c = await repo.createConversation(name: name, messages: messages);
    c.partnerId = partnerId;
    await c.save();
    _invalidatePartnerScope(partnerId);
    return c;
  }

  Future<void> save(Conversation c, {String? previousPartnerId}) async {
    final repo = ref.read(conversationRepositoryProvider);
    await repo.updateConversation(c);
    _invalidatePartnerScope(c.partnerId);
    if (previousPartnerId != null && previousPartnerId != c.partnerId) {
      _invalidatePartnerScope(previousPartnerId);
    }
  }

  Future<void> delete(Conversation c) async {
    final repo = ref.read(conversationRepositoryProvider);
    await repo.deleteConversation(c.id);
    _invalidatePartnerScope(c.partnerId);
  }

  void _invalidatePartnerScope(String? partnerId) {
    if (partnerId == null) return; // legacy / unmigrated conversation: no narrow scope to invalidate
    ref.invalidate(conversationsByPartnerProvider(partnerId));
    ref.invalidate(partnerAggregateProvider(partnerId));
  }
}

final conversationWriteControllerProvider =
    NotifierProvider<ConversationWriteController, void>(
  ConversationWriteController.new,
);
```

Plus: `ConversationRepository.listByPartner(String partnerId)` — pure storage wrapper, owner-scoped, **no `Ref`**.

**Step 4: Run, expect PASS** — partner provider + write controller tests 全綠

**Step 5: Migrate 9 UI invalidate 呼叫點**

Grep verified 2026-04-26:

| File | Line | Migration |
|---|---|---|
| `new_conversation_screen.dart` | 146 | new conversation flow → `controller.create(...)` (controller 內部已 invalidate；移除原行) |
| `home_screen.dart` | 91 | conversation 刪除/操作 → `controller.delete(c)` 或 `controller.save(c)` |
| `main_shell.dart` | 245 | 同上 |
| `analysis_screen.dart` | 495 | analyze 完成存檔 → `controller.save(c)` |
| `analysis_screen.dart` | 514 | 同上 |
| `analysis_screen.dart` | 935 | message 編輯後 → `controller.save(c)` |
| `analysis_screen.dart` | 1000 | 同上 |
| `analysis_screen.dart` | 1113 | analyze 完成存檔 → `controller.save(c)` |

**Verification gate**:
- `grep -rn "ref.invalidate(conversationsProvider)" lib/` → 期望 0 hits
- 跑 `flutter analyze` → 0 warnings
- 手測 home → partner detail → analyze → back flow，UI 即時更新

**Step 6: Commit (split 2 commits)**

```bash
git commit -m "[feat] Partner narrow-invalidation providers + ConversationWriteController"
git commit -m "[refactor] 9 UI invalidate 呼叫點改走 ConversationWriteController"
git push
```

---

## Task 4 — Partner summary builder（AI prompt 用）

**Files:**
- Create: `lib/features/partner/domain/services/partner_summary_builder.dart`
- Test: `test/unit/features/partner/partner_summary_builder_test.dart`

**Spec source**: design doc §3 token budget 表 + worst-case 段落。

**Step 1: Failing tests**

```dart
test('30-conversation partner: assembled summary <= 1500 chars', () { /* ... */ });
test('takes top N=8 interests / traits ranked by lastInteraction desc', () { /* ... */ });
test('takes top 5 notes joined newline-separated', () { /* ... */ });
test('partner.ownerUserId != conversation.ownerUserId returns empty summary', () {
  // Anti-bleed safeguard
});
test('single conversation lastAnalysisSnapshotJson parse failure: skip that conversation, summary still assembled', () { /* ... */ });
test('first-conversation partner: summary returns single-line marker', () {
  // "[對象背景：糖糖]\n這是你跟此對象的第一次對話"
});
test('all conversations no analysis snapshot: summary returns analysis-pending marker', () { /* ... */ });
test('unnamed partner: uses fallback "對象 #abc" with id last 4 chars', () { /* ... */ });
test('user-set customNote 1000 chars: final summary still <= 1500 (truncation works)', () { /* ... */ });
test('truncation preserves "[truncated]" suffix marker', () { /* ... */ });
test('truncation does NOT split a non-ASCII character (boundary safety, Codex P2)', () {
  // Build inputs so the truncation point lands exactly on a multi-codeunit char.
  // Construct partner.customNote padded so the assembled buffer length is e.g. kHardCharCap+1
  //   AND the codepoint at index (kHardCharCap - markerLen - 1) is a Chinese char or emoji
  //   that occupies >1 UTF-16 code unit.
  // Assert: result.length <= kHardCharCap.
  // Assert: result is valid UTF-16 (no orphan surrogate; round-trip through `String.fromCharCodes(result.codeUnits)` equals result).
  // Assert: result ends with the truncation marker.
});
```

**Step 2: Run, expect FAIL**

**Step 3: Implement**

```dart
// lib/features/partner/domain/services/partner_summary_builder.dart
class PartnerSummaryBuilder {
  static const int kHardCharCap = 1500;
  static const int kTopN = 8;
  static const int kTopNotes = 5;
  static const int kTopConversationsForStats = 10;

  String build({
    required Partner partner,
    required List<Conversation> conversations,
  }) {
    // 0. ownerUserId mismatch defense
    final mismatch = conversations.any(
      (c) => c.ownerUserId != null && c.ownerUserId != partner.ownerUserId,
    );
    if (mismatch) return '';

    // 1. parse lastAnalysisSnapshotJson per conversation; skip on failure
    final extracted = <_ExtractedSnapshot>[];
    for (final c in conversations) {
      try {
        final snap = _parseSnapshot(c.lastAnalysisSnapshotJson);
        extracted.add(_ExtractedSnapshot(c.updatedAt, snap));
      } catch (_) { /* skip per-snap parse fail */ }
    }

    // 2. first-conversation / all-no-snapshot edge cases
    if (extracted.isEmpty) {
      if (conversations.isEmpty) {
        return _emptyPartnerHeader(partner);
      }
      return _firstAnalysisPendingHeader(partner);
    }

    // 3. rank
    extracted.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final topConvos = extracted.take(kTopConversationsForStats).toList();

    final unionInterests = _unionDedupe(
      topConvos.expand((s) => s.snap.interests),
      cap: kTopN,
    );
    final unionTraits = _unionDedupe(
      topConvos.expand((s) => s.snap.traits),
      cap: kTopN,
    );
    final notes = _topNNotes(extracted, n: kTopNotes);

    // 4. assemble
    final buffer = StringBuffer()
      ..writeln('[對象背景：${_partnerName(partner)}]')
      ..writeln('- 累計對話：${conversations.length} 段，'
          '${_sumMessages(topConvos)} 則訊息，'
          '最後互動 ${_relativeTime(extracted.first.updatedAt)}')
      ..writeln('- 最近熱度：${extracted.first.snap.heat}');
    if (unionInterests.isNotEmpty) {
      buffer.writeln('- 興趣：${unionInterests.join('、')}');
    }
    if (unionTraits.isNotEmpty) {
      buffer.writeln('- 性格：${unionTraits.join('、')}');
    }
    if ((partner.customNote ?? '').isNotEmpty) {
      buffer.writeln('- 你的備註：${partner.customNote}');
    } else if (notes.isNotEmpty) {
      buffer.writeln('- 過往備註：${notes.join('；')}');
    }
    buffer.writeln('- 注意：以上是整體背景，當前對話內容仍以本次訊息為主');

    var s = buffer.toString();
    // 5. hard cap — char-safe truncation (Codex P2 fix 2026-04-26)
    // Use `characters` (grapheme clusters) — never raw substring on UTF-16 code units,
    // which can split a Chinese char's surrogate pair or an emoji ZWJ sequence.
    const marker = '... [truncated]';
    final cs = s.characters;
    if (cs.length > kHardCharCap) {
      final keep = kHardCharCap - marker.length;
      s = '${cs.take(keep).toString()}$marker';
    }
    return s;
  }

  // ... helpers
}
```

**Step 4: Run, expect PASS** — 所有 10 個 test 必須綠

**Step 5: Commit**

```bash
git commit -m "[feat] PartnerSummaryBuilder — hard 1500 cap + N=8 ranking + ownerUserId 防呆"
git push
```

---

## Task 5 — AI prompt integration（client-side wiring）

**Files:**
- Modify: `lib/features/analysis/data/services/analysis_service.dart`（live caller, verified 2026-04-26）
- Test: `test/unit/features/analysis/analysis_service_partner_summary_test.dart`

**Goal**: 「繼續對話」 / 「新對話首次分析」呼叫 `analyze-chat` Edge Function 前，由 client 組好 partner summary 塞進 request payload。

**Step 1: Failing tests**

```dart
test('analyze-chat request includes partnerSummary field when conversation has partnerId', () { /* ... */ });
test('analyze-chat request omits partnerSummary when conversation.partnerId is null (legacy / unmigrated)', () { /* ... */ });
test('partnerSummary is rebuilt on every call (no caching)', () { /* ... */ });
test('partnerSummary omitted when builder returns empty (ownerUserId mismatch fallback)', () { /* ... */ });
```

**Step 2: Run, expect FAIL**

**Step 3: Implement**

```dart
// in AnalysisService (lib/features/analysis/data/services/analysis_service.dart)
Future<AnalysisResult> analyze(Conversation c) async {
  String? partnerSummary;
  if (c.partnerId != null) {
    final partner = partnerRepository.getById(c.partnerId!);
    if (partner != null) {
      final convos = conversationRepository.listByPartner(c.partnerId!);
      final s = summaryBuilder.build(
        partner: partner,
        conversations: convos,
      );
      if (s.isNotEmpty) partnerSummary = s;
    }
  }
  return _callEdgeFunction(
    conversation: c,
    partnerSummary: partnerSummary,
  );
}
```

Plus: Edge Function side — `supabase/functions/analyze-chat/index.ts` reads `partnerSummary` from request and prepends to system / user prompt（見 design doc §3 摘要範本）。

**Step 4: Run, expect PASS**

**Step 5: Commit (split: Flutter side + Edge Function side 兩 commits)**

```bash
git commit -m "[feat] analyze-chat client 注入 partnerSummary"
git commit -m "[feat] analyze-chat edge function 接收並前置 partnerSummary"
git push
```

---

## Task 6 — Routing（/partner/:partnerId）

**Files:**
- Modify: `lib/app/routes.dart`（live router, verified 2026-04-26）
- Test: `test/widget/router_test.dart`

**Step 1: Failing tests**

```dart
test('/partner/:partnerId routes to PartnerDetailScreen', () { /* ... */ });
test('/conversation/:id retains backward compat (still routes to AnalysisScreen)', () { /* ... */ });
test('Back from in-conversation navigates to Partner detail (not Home)', () {
  // iOS swipe-back parity check
});
```

**Step 2: Run, expect FAIL**

**Step 3: Implement** — go_router add new route + back stack tweak

**Step 4: Run, expect PASS**

**Step 5: Commit**

```bash
git commit -m "[feat] router 新增 /partner/:id + 保留 /conversation/:id 向後相容"
git push
```

---

## Task 7 — Partner list home screen（首頁主體）

**Files:**
- Modify: `lib/features/conversation/presentation/screens/home_screen.dart`（現有）→ 換內容；或更精準 create new + 在 main_shell 把 home tab 換掉
- Create (preferred): `lib/features/partner/presentation/screens/partner_list_screen.dart`
- Modify: `lib/app/main_shell.dart`（home tab body）
- Test: `test/widget/features/partner/partner_list_screen_test.dart`

**Step 1: Failing widget tests**

```dart
testWidgets('empty state shows "還沒有對象，加一個開始" + FAB', (tester) async { /* ... */ });
testWidgets('multiple partners listed, sorted by lastInteraction desc', (tester) async { /* ... */ });
testWidgets('partner card shows name / N段對話 / latest heat / lastInteraction', (tester) async { /* ... */ });
testWidgets('FAB tap navigates to "+ 新增對象" form', (tester) async { /* ... */ });
testWidgets('partner card tap navigates to /partner/:partnerId', (tester) async { /* ... */ });
```

**Step 2: Run, expect FAIL**

**Step 3: Implement**

```dart
// PartnerListScreen
class PartnerListScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final partners = ref.watch(partnerListProvider);
    if (partners.isEmpty) return _EmptyState();
    return ListView.builder(/* PartnerCard per item */);
  }
}
```

PartnerCard widget showing avatar + name + 「N 段對話」 + heat badge + 最後活動時間。

**Step 4: Run, expect PASS**

**Step 5: Commit**

```bash
git commit -m "[feat] Home tab 改 PartnerListScreen + 空狀態 + FAB 入口"
git push
```

---

## Task 8 — Add Partner form（從 FAB 進）

**Files:**
- Create: `lib/features/partner/presentation/screens/add_partner_screen.dart`
- Test: `test/widget/features/partner/add_partner_screen_test.dart`

**Step 1: Failing tests**

```dart
testWidgets('form requires name; submit disabled while empty', (tester) async { /* ... */ });
testWidgets('avatar 可選 — submit 時不選也能建', (tester) async { /* ... */ });
testWidgets('successful submit creates Partner + navigates to /partner/:newId', (tester) async { /* ... */ });
testWidgets('newly-created Partner has ownerUserId set to current user', (tester) async { /* ... */ });
```

**Step 2: Run, expect FAIL**

**Step 3: Implement** — simple form: TextFormField(name), optional avatar picker, submit → `partnerRepository.put(new Partner(...))` → `context.go('/partner/${id}')`.

**Step 4: Run, expect PASS**

**Step 5: Commit**

```bash
git commit -m "[feat] 新增對象表單 — name + 可選 avatar"
git push
```

---

## Task 9 — Partner detail screen（含雷達摘要小卡）

**Files:**
- Create: `lib/features/partner/presentation/screens/partner_detail_screen.dart`
- Create: `lib/features/partner/presentation/widgets/partner_radar_summary_card.dart`
- Create: `lib/features/partner/presentation/widgets/partner_traits_card.dart`
- Test: `test/widget/features/partner/partner_detail_screen_test.dart`

**Step 1: Failing tests**

```dart
testWidgets('shows partner name, ⋮ menu, traits card, radar summary card, conversation list', (tester) async { /* ... */ });
testWidgets('conversation cell tap → navigates to /conversation/:id (D3 plan-default A)', (tester) async { /* ... */ });
testWidgets('+ 新增對話 button passes partnerId to NewConversationScreen', (tester) async { /* ... */ });
testWidgets('empty conversation list shows "尚未有對話，從下方加一段開始"', (tester) async { /* ... */ });
testWidgets('latest analysis snapshot null → radar card shows "最新對話尚未分析"', (tester) async { /* ... */ });
testWidgets('⋮ menu shows 合併到其他對象 / 編輯對象 / 刪除對象', (tester) async { /* ... */ });
```

**Step 2: Run, expect FAIL**

**Step 3: Implement** — full screen with header (avatar + name + ⋮) / `PartnerTraitsCard` (uses `partnerAggregateProvider`) / `PartnerRadarSummaryCard` (parses latest conv `lastAnalysisSnapshotJson` for 5-dim) / conversation list (uses `conversationsByPartnerProvider`) / sticky `+ 新增對話` button.

**Step 4: Run, expect PASS**

**Step 5: Commit**

```bash
git commit -m "[feat] Partner 詳情頁 — traits / radar 小卡 / conversation 列 / + 新增對話"
git push
```

---

## Task 10 — New conversation flow（從 Partner detail 帶 partnerId）

**Files:**
- Modify: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`
- Test: `test/widget/features/conversation/new_conversation_screen_test.dart`

**Step 1: Failing tests**

```dart
testWidgets('partnerId arg passed in: created conversation has matching partnerId', (tester) async { /* ... */ });
testWidgets('partnerId arg passed in: default conversation name = "YYYY/MM/DD 新對話"', (tester) async { /* ... */ });
testWidgets('partnerId arg null (legacy entry): falls back to legacy create flow (creates Partner with conv.id-derived UUID)', (tester) async {
  // safety net for any code path that calls into NewConversationScreen pre-A2 wiring
});
```

**Step 2: Run, expect FAIL**

**Step 3: Implement**

```dart
class NewConversationScreen extends ConsumerWidget {
  final String? partnerId; // new optional arg
  // ...
  Future<void> _create() async {
    final partnerIdResolved = partnerId ?? await _autoCreatePartner();
    final convo = Conversation(
      id: const Uuid().v4(),
      name: _name ?? _defaultDateName(),
      partnerId: partnerIdResolved,
      ownerUserId: currentUserId,
      // ... existing fields
    );
    await conversationRepository.save(convo);
    context.go('/conversation/${convo.id}');
  }
}
```

**Step 4: Run, expect PASS**

**Step 5: Commit**

```bash
git commit -m "[feat] new_conversation_screen 接 partnerId — Partner detail 來源 path 接通"
git push
```

---

## Task 11 — Screenshot flow auto-attach Partner（**D1 影響**）

**Files:**
- Modify: 截圖 OCR 入口處（pre-flight 確認當前實作 — 多半在 `new_conversation_screen.dart` 或獨立 `screenshot_upload_widget`）
- Test: 對應 widget test

**依 D1 plan-default A**: 用戶從 Partner detail「+ 新增對話」進來時，partnerId 已從 Task 10 帶下來，截圖完成後直接掛在該 Partner 上 — 此 Task 主要是**驗證**這條 path 不需要額外 picker。

**若 Eric 改 D1 為 B / C**: 此 Task 範圍會擴張（picker UI / 自動命名邏輯），請執行前再讀一次 D1 決議。

**Step 1: Failing test (defensive)**

```dart
testWidgets('screenshot 完成後 conversation.partnerId 等於進入時的 partnerId arg', (tester) async { /* ... */ });
testWidgets('legacy entry (partnerId null): 截圖完成後仍能建立 conversation + 自動建 Partner（migration 邏輯複用）', (tester) async { /* ... */ });
```

**Step 2: Run, expect FAIL**（若現行行為仍是 partnerless conversation create）

**Step 3: Implement** — 補上 partnerId 傳遞鏈條 + null fallback 走 `PartnerIdFactory` 自動建（A1 已存在）

**Step 4: Run, expect PASS**

**Step 5: Commit**

```bash
git commit -m "[feat] 截圖 flow 接 partnerId — Partner detail 進入維持線性，legacy fallback 自動建"
git push
```

---

## Task 12 — Merge UI（合併到其他對象）

**Files:**
- Create: `lib/features/partner/presentation/screens/partner_merge_picker_screen.dart`
- Create: `lib/features/partner/presentation/dialogs/partner_merge_confirm_dialog.dart`
- Test: `test/widget/features/partner/partner_merge_test.dart`

**Step 1: Failing tests**

```dart
testWidgets('picker shows all other partners except self, supports search by name', (tester) async { /* ... */ });
testWidgets('confirm dialog shows from/to summary: 對話數搬遷 / 特質聯集數 / 互動累計 / 保留 B avatar', (tester) async { /* ... */ });
testWidgets('confirm tap calls PartnerRepository.merge(from: A, to: B) and navigates to /partner/B', (tester) async { /* ... */ });
testWidgets('merge invalidates both A and B aggregates (B rebuilt with union)', (tester) async { /* ... */ });
testWidgets('post-merge navigation: target partner detail shows merged customNote with [from A] tag', (tester) async { /* ... */ });
```

**Step 2: Run, expect FAIL**

**Step 3: Implement** — picker (search + ListTile per Partner) / confirm dialog (uses aggregateOver to preview union counts) / wire to ⋮ menu in Partner detail.

**Step 4: Run, expect PASS**

**Step 5: Commit**

```bash
git commit -m "[feat] Partner 手動合併 UI — picker + confirm + invalidate 雙 partner"
git push
```

---

## Task 13 — Conversation reassign（改派到其他對象）

**Files:**
- Modify: Partner detail conversation list cell（加 long-press handler）
- Create: `lib/features/conversation/presentation/dialogs/conversation_reassign_picker.dart`
- Test: `test/widget/features/conversation/conversation_reassign_test.dart`

**Step 1: Failing tests**

```dart
testWidgets('long-press on conversation cell shows "改派到其他對象" action', (tester) async { /* ... */ });
testWidgets('reassign picker shows other partners + "+ 新建對象"', (tester) async { /* ... */ });
testWidgets('selecting target partner: conversation.partnerId switched + both source/target aggregates invalidated', (tester) async { /* ... */ });
```

**Step 2: Run, expect FAIL**

**Step 3: Implement** — uses save flow with `previousPartnerId` for narrow invalidation (Task 3 contract).

**Step 4: Run, expect PASS**

**Step 5: Commit**

```bash
git commit -m "[feat] conversation 改派 UI — 長按進 picker，雙端 invalidate"
git push
```

---

## Task 14 — Same-name banner（D4 plan-default A）

**Files:**
- Create: `lib/features/partner/presentation/widgets/same_name_dedupe_banner.dart`
- Test: `test/widget/features/partner/same_name_banner_test.dart`

**Step 1: Failing tests**

```dart
testWidgets('shows when partner names have duplicates (≥2 with same name)', (tester) async { /* ... */ });
testWidgets('does not show when all unique', (tester) async { /* ... */ });
testWidgets('"以後再說" tap writes partner_dedupe_banner_dismissed=true; banner hidden permanently', (tester) async { /* ... */ });
testWidgets('"立即合併" tap navigates to merge picker pre-filled with first dup pair', (tester) async { /* ... */ });
testWidgets('after partner_dedupe_banner_dismissed=true, banner stays hidden even if new dup appears (per D4-A)', (tester) async { /* ... */ });
```

**Step 2: Run, expect FAIL**

**Step 3: Implement** — banner widget on Partner list home; dedupe detection runs on `partnerListProvider` rebuild.

**Step 4: Run, expect PASS**

**Step 5: Commit**

```bash
git commit -m "[feat] 同名 Partner 偵測 banner — 一次性提示，可永久關閉 (D4-A)"
git push
```

---

## Task 15 — Copy sweep（「對話」/「對象」用詞）

**Files:**
- Modify: `lib/app/main_shell.dart`（Bruce 截圖紅框 popup 的所在）
- Modify: `lib/features/conversation/presentation/screens/new_conversation_screen.dart`
- Modify: 其他 grep 出來的命中位（pre-flight grep 全 codebase）

**Step 0: Run sweep**

```bash
grep -rn "新增對話\|新對話\|建立對話\|對話列表\|你的對話" lib/ \
  | grep -v "_test.dart\|.g.dart\|migration_service\|_repository.dart"
```

逐筆判斷：
- 屬於「Partner detail 內」/ 「截圖 OCR 標題」 → 保留「對話」（語意正確：仍是建一段 conversation）
- 屬於「首頁 / 全域導覽」/ 「空狀態 / 教學提示」 → 改成「對象」
- 屬於 domain 層（class / variable / comment） → 保留 `Conversation`（D2 plan-default A）

**Step 1: Snapshot tests**（避免 copy 漂移）

```dart
testWidgets('home FAB label = "+ 新增對象"', (tester) async { /* ... */ });
testWidgets('partner detail "+ 新增對話" label remains', (tester) async { /* ... */ });
testWidgets('home empty state copy = "還沒有對象，加一個開始"', (tester) async { /* ... */ });
```

**Step 2: Run, expect FAIL（at least one current copy mismatch）**

**Step 3: Edit copy**

**Step 4: Run, expect PASS**

**Step 5: Commit**

```bash
git commit -m "[refactor] copy sweep — UI 雙層詞彙「對象 / 對話」對齊 ADR-15"
git push
```

---

## Task 16 — Documentation closeout（TF regression / ADR ship section / snapshot）

**Files:**
- Modify: `docs/testflight-regression-checklist.md`
- Modify: `docs/decisions.md`（ADR-15 加 v2 ship 段落）
- Modify: `docs/snapshot.md`
- Modify: `CLAUDE.md` Common Pitfalls 段（若新增 pitfall）

**Step 1: TF regression checklist 加 A2 必測項**

- 升級後第一次開 app — Partner list 顯示，原 N 個對話 → N 個 Partner cards
- Partner detail 顯示對應 conversations
- 「+ 新增對象」FAB 可建 Partner，建完跳 detail
- 「+ 新增對話」從 Partner detail 進，建完掛在該 Partner
- 同名 Partner（migration 後）顯示 banner，「以後再說」永久關閉
- 「合併到其他對象」實際搬遷對話 + customNote 加 [from A] tag
- 長按 conversation cell 改派 → 兩端 aggregates 都更新
- 跨對話分析 prompt 含 partner summary（log 抽查 < 1500 char）
- 多帳戶切換不洩漏（A 帳戶 Partners 不入 B 帳戶 list）

**Step 2: ADR-15 v2 ship 段落**

```markdown
## ADR #15 — v2 ship（2026-XX-XX）

A2 已 ship — Partner list / detail / merge / AI summary 全上。

主要決策落地：
- D1 採用 plan-default A（Partner detail 內 +新增對話 線性）
- D2 採用 plan-default A（domain Conversation 命名保留）
- D3 採用 plan-default A（conversation cell tap → analysis）
- D4 採用 plan-default A（dedupe banner 一次性，可永久關）
（如有 Eric 覆蓋預設值，列在此處）

A2 後續 follow-up:
- HS1 Sentry SDK 整合（A1 + A2 完成後再裝）
- HS2 重做升級覆蓋舊備份（接受 trade-off）
```

**Step 3: snapshot.md 月度刷新（若跨月）**

**Step 4: Commit**

```bash
git commit -m "[docs] A2 ship — TF regression 補項 + ADR-15 v2 段落 + snapshot 刷新"
git push
```

---

## Task 17 — Pre-PR sanity（最終驗收）

**Step 1: 全測試 + lint**

```bash
flutter test 2>&1 | tee /tmp/a2_test_output.log
flutter analyze 2>&1 | tee /tmp/a2_analyze_output.log
```

**Acceptance gates**:
- 0 failing tests
- 0 lint warnings on new files
- Existing `main` test count ≤ A2 branch test count（無回歸刪除）

**Step 2: Manual smoke**（自家 build / TF 候選 build）

- 升級已有資料 → Partner list 出現
- 新增 Partner → 建 conversation → AI 分析含 partner summary（log 抽）
- 兩個同名 Partner → banner 出現 → 合併 → 對話搬遷
- 切帳戶 → 隔離

**Step 3: 開 PR**

```bash
gh pr create --title "Partner Entity Refactor A2 — UI / Merge / AI Summary" --body "$(cat <<'EOF'
## Summary
- Implements Partner-first IA per ADR-15
- Adds Partner list / detail / merge UI / Conversation reassign / same-name banner
- AI prompt now includes Partner summary (≤1500 char, N=8 ranking, ownerUserId guard)
- Riverpod narrow invalidation (Codex C1 contract honored)

## Test plan
- [ ] flutter test — all green
- [ ] flutter analyze — no new warnings
- [ ] Manual: upgrade flow / Partner CRUD / merge / reassign / multi-account isolation
- [ ] Codex code review pass

## Daisy-Decision resolutions
- D1: plan-default A | overridden to ___ (TBD)
- D2: plan-default A | overridden to ___ (TBD)
- D3: plan-default A | overridden to ___ (TBD)
- D4: plan-default A | overridden to ___ (TBD)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

**Step 4: 開 queue item「Partner Entity Refactor — A2 Implementation Code Review」喊 Codex**

---

## Codex Review Hot Spots

> 給 Codex spec review 預先標的可疑面向。Codex 可在這些角度產出 verdict 而不必通讀 17 個 task。

### HS-A2-1 — Riverpod narrow invalidation 真的 narrow 嗎？

**Concern**: Task 3 contract 寫 `conversationsByPartnerProvider(partnerId)` 不訂閱全 `conversationsProvider`。但 Repository 層若是 Hive box listener，**所有 conversation 寫入仍會觸發 box listener** → provider 重算就算只 read 不 watch global。

**Verify path**:
- `lib/features/partner/presentation/providers/partner_providers.dart`
- 看 `conversationsByPartnerProvider` 是 `Provider.family` 還是 `StreamProvider.family`
- 若用 box stream，必須做 `where((c) => c.partnerId == partnerId)` 並且每筆寫入都過篩，才能稱為 narrow
- 否則 narrow invalidation 是 facade，全 partner aggregate 仍 fan-out

**Test signal**: T3 narrow-invalidation test 是否真檢測 fan-out（subscribe both X and Y, write under X, assert Y not rebuilt）。

### HS-A2-2 — Partner summary < 1500 在「30 段對話 + 用戶 customNote 1500 字」極端情境

**Concern**: Builder hard cap 切 1500 但 customNote 是用戶寫的、上限沒 enforce。若 customNote = 1500 字，`buffer.writeln('- 你的備註：...')` 直接超 1500 才被 truncate。truncate 點若落在中文 utf-16 surrogate 中會壞字。

**Verify path**:
- `lib/features/partner/domain/services/partner_summary_builder.dart` truncate 實作
- truncate 必須 char-safe（`String.runes` 或 `characters` package）

**Test signal**: T4 user-customNote 1000-char test 是否 assert no broken chars at truncate boundary。

### HS-A2-3 — D1 plan-default A 是否真的不引入 picker？

**Concern**: 若用戶從**首頁的舊「+ 新增對話」popup**（migration 期 / legacy state）進來，partnerId 為 null。Plan 預設 fallback 走 PartnerIdFactory 自建 — 但 fallback path 是否仍會**觸發 Bruce 痛點**（同人不同段對話 → 兩個獨立 Partner）？

**Verify path**:
- Task 11 / Task 10 的 fallback impl
- 是否在 fallback time deduplicate by name（風險：跨人撞名 false positive）
- 或者 Plan 預設**不 dedupe**，只在 Partner list 時靠 same-name banner（D4-A）兜底

**Verdict needed**: Codex 認為是否 acceptable 將 same-name dedupe 全部交給 banner / 手動 merge，還是 ingest path 需做主動 dedupe？

### HS-A2-4 — A2 工期 7-8 dev days 是否仍合理？

**Concern**: Codex spec re-review 對 A1 給 `2-3 dev days + 1-2 day TF soak`（C2）。A2 比 A1 寬：17 tasks vs A1 13 tasks，新增 6 個 widget / screen + 1 個 builder + 完整 widget tests。樂觀估 6-7 day，悲觀 9-10 day。

**Verdict needed**: Codex sanity-check 哪些 task 估時偏低 / 哪些有 hidden 撞 Hive 寫入競態風險。

### HS-A2-5 — Routing back-stack 真的不會跳到 Home？

**Concern**: design doc §2 寫「對話內按返回 → Partner detail（不是首頁）」。go_router 預設 back stack 是 navigation 歷史，從 Partner detail push /conversation/:id 沒問題；但若用戶從 deep link / 通知 / 分享連結 直接落地 /conversation/:id，**back stack 為空**，按返回會出 app 而非進 Partner detail。

**Verify path**:
- Task 6 router config 是否有 fallback parent route（go_router 的 `parentNavigatorKey` / `initialLocation` 機制）
- T6 test 是否覆蓋 deep-link entry case

**Verdict needed**: 是否需要在 `/conversation/:id` 載入時，若該 conversation 有 partnerId，自動把 `/partner/:partnerId` 推進 back stack？

---

## Closeout（PR 開出後）

依昨晚 closeout matrix：
- **Default**：commit history + 本 plan 即足，**不另寫 review doc**
- 若 Codex review 出 🔴 / 🟠 → 既有 `docs/reviews/` 開新 doc（不在本 plan 補）
- 若 A2 ship 改變了 ADR — 在 ADR-15 補 v2 段落（Task 16 已含）
- 若新增 recurring trap → CLAUDE.md Common Pitfalls 補一條
- 全部 OK → memory `reference_partner_refactor_in_flight.md` 翻 status: `A2 SHIPPED, awaiting code review`

---

## 後續 Session 開場語

### Codex spec review session

> 先讀 `AGENTS.md` → `docs/shared-agent-rules.md` → `docs/reviews/ai-arbitration-queue.md` 的 live item「Partner Entity Refactor — A2 Implementation Plan Review」→ 本 plan。執行 spec review，重點盲區見上方「Codex Review Hot Spots」。Verdict 寫進 queue item Codex-Position 欄；🔴 issue 開 `docs/reviews/2026-04-26_partner-entity-A2-plan_codex-review.md`。

### 新 Claude session 執行 A2

> 先讀 `CLAUDE.md` → `docs/shared-agent-rules.md` → 本 plan → 確認 Daisy-Decision-Needed 4 項都已決議（PR description 會列）。使用 `superpowers:executing-plans` skill 從 Task 1 開始 TDD 推進；每 Task 完成 commit + push（trailer 含 Reviewer-Hint / Next-Step）。
