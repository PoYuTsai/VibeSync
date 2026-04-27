# Partner Entity Refactor — A2 Phase 4 Design（Polish + Ship）

> Author: Claude (brainstorm validated with Eric 2026-04-28)
> Status: SPEC_DRAFT — pending Codex spec review
> Predecessors: A1 `919e034` → A2 Phase 1 `f053a9c` → Phase 2 `004388e` → Phase 3 PR-A `f2ab222` → Phase 3 PR-B `a38d46e`
> Branch (impl): `feature/partner-entity-A2-polish`
> Tracking plan: `docs/plans/2026-04-26-partner-entity-A2-impl.md` Tasks 14-18
> Master design: `docs/plans/2026-04-25-partner-entity-design.md` (ADR-15)

---

## 1. Goal

Ship A2 — 收齊所有 polish + 視覺還原 + ship gate，讓 A2 全集進入 TF soak，準備送審。

**Definition of done：**
- PR `feature/partner-entity-A2-polish` merged to main
- A2 5 件 user-visible 改動全到位（partner list 視覺 / dedupe banner / 文案 / partner delete / @Deprecated cleanup）
- TF regression checklist 含 A2 必測項
- ADR-15 v2 ship 段落寫好

## 2. Scope

| Task | 主題 | Layer |
|---|---|---|
| 18 | PartnerListCard 視覺還原 + Partner delete API（hidden scope） | data + UI |
| 14 | Same-name dedupe banner（per-account） | data + UI |
| 15 | Copy sweep — 「對象」/「對話」雙層詞彙 | UI |
| 16 | 砍 `@Deprecated HomeContent` + doc closeout | refactor + docs |
| 17 | Pre-PR sanity + ship gate + Codex code review handoff | gate |

**Hidden scope 揭露**：Task 18 內含 Partner delete API。PR-B handoff 列為 Phase 4 territory「delete handler」，但 Tasks 14-17 master plan 沒單列；Bruce 的 5 件套裡的「刪除 icon」需要 controller / repo 新工，故拆 18a (data) + 18b (UI)。

## 3. Non-goals

- ❌ 不 reopen ADR-15 brainstorm 6 個 D 決策
- ❌ 不動 A1 schema / migration / A2 Phase 1-3 已 ship code
- ❌ 不混 OCR 改動（baseline `28c0965` 保護）
- ❌ 不加新功能（只 polish + ship）
- ❌ 不 rename domain `Conversation` class（D2 plan-default A）

## 4. Daisy-Decisions（locked 2026-04-28）

| ID | 決策 | Locked Choice | Why |
|---|---|---|---|
| **D-P4-1** | Partner delete cascade 語意 | **A — block when conversations exist** | 資料安全 + 有 path（merge / reassign）替代 + 教育用戶走正確 flow |
| **D-P4-2** | Banner pre-fill source/target | **A — newer-by-createdAt = source, older = target** | 心智模型：先建的是正本；對齊 Task 12 customNote `[from A]` tag |
| **D-P4-3** | PartnerListCard preview 資料源 | **B — interests+traits 前 3 tag** | 產品定位（AI 拆解輪廓）+ 隱私（不曝對話原文）+ 0 行 aggregate 改動 |
| **D-P4-4** | Heat indicator fallback (latestHeat == null) | **B — 🌡️ 待分析 灰字** | 5 件套完整性 + 教學暗示 + 語意正確（null ≠ 0） |
| **D-P4-5** | Banner dismissed flag scope | **A — per-account, key = `partner_dedupe_banner_dismissed_$uid`** | 多帳戶隔離一致性（A2 invariant） + Eric 自己會踩到 |

## 5. Sequencing

```
Task 18 (visual + delete API)
  ├─ 18a: data — PartnerWriteController.delete() + repo guard + tests
  └─ 18b: UI — PartnerListCard 5 件套 + delete dialog two-mode
       │
       ▼ (visual donor @Deprecated HomeContent 仍存活，Task 18 期間可參考)
Task 14 (dedupe banner)
  ├─ 14a: PartnerBannerService (per-uid SharedPreferences) + 3 unit tests
  └─ 14b: SameNameDedupeBanner widget + merge picker route 加 ?target query param
       │
       ▼
Task 15 (copy sweep, 1 commit)
       │
       ▼
Task 16
  ├─ 16a: 砍 @Deprecated HomeContent (1 commit, full test gate)
  └─ 16b: TF regression + ADR-15 v2 + snapshot + 1 pitfall (1 commit)
       │
       ▼
Task 17 (ship gate)
  ├─ flutter test + analyze 全綠
  ├─ Manual smoke 5 項
  ├─ gh pr create
  └─ Queue item 喊 Codex code review
```

**為什麼這個順序**：
1. Task 18 第一：Bruce 視覺反饋最 user-visible，先看到 PR diff（halfway WIP push 也能 mock）
2. Task 18 在 Task 16 之前：visual donor `@Deprecated HomeContent` 必須還活著，Task 16 才砍
3. Task 15 在 14、18 之後：avoid 兩次掃（含 banner 文案 + 新 PartnerListCard 文案）
4. Task 16 砍 deprecated 排倒數第二，緊接 Task 17 ship gate → 砍完跑全測試驗證沒洩漏 reference

## 6. Task 18 — PartnerListCard 視覺還原 + Partner delete API

### 6.1 Task 18a — Partner delete API（data layer）

**Files:**
- Modify `lib/features/partner/data/repositories/partner_repository.dart`（+`delete()` with conversation guard）
- Modify `lib/features/partner/data/providers/partner_write_controller.dart`（+`delete()` + invalidation, try/finally）
- New `test/unit/features/partner/partner_repository_delete_test.dart`
- Modify `test/unit/features/partner/partner_write_controller_test.dart`（+ delete cases）

**API contract:**

```dart
class PartnerHasConversationsException implements Exception {
  final int conversationCount;
  PartnerHasConversationsException(this.conversationCount);
}

// PartnerRepository
Future<void> delete(String partnerId) async {
  final conversations = await listByPartner(partnerId);
  if (conversations.isNotEmpty) {
    throw PartnerHasConversationsException(conversations.length);
  }
  await _box.delete(partnerId);
}

// PartnerWriteController
Future<void> delete(Partner partner) async {
  try {
    await _repo.delete(partner.id);
  } finally {
    _ref.invalidate(partnerListProvider(partner.ownerUserId));
    _ref.invalidate(partnerAggregateProvider(partner.id));
  }
}
```

**TDD 三條 RED → GREEN：**
1. `delete throws PartnerHasConversationsException when conversations exist`
2. `delete removes partner from box when conversations is empty`
3. `controller delete invalidates partnerListProvider + partnerAggregateProvider after success`

`try/finally` 對齊 PR-B Codex r1 patch（`0187685`）partial-fail invalidation 紀律。

### 6.2 Task 18b — PartnerListCard 視覺還原（UI layer）

**Files:**
- Modify `lib/features/partner/presentation/widgets/partner_list_card.dart`
- Modify `lib/features/partner/presentation/screens/partner_list_screen.dart`（接 onDelete callback）
- New `test/widget/features/partner/partner_list_card_test.dart`

**5 件套 mapping（Bruce spec → 實作）：**

| Bruce 件 | 實作 | 資料源 |
|---|---|---|
| 圓角玻璃感卡 | `GlassmorphicContainer` 包 `ListTile` | — |
| 黃字頭 avatar | `LinearGradient(avatarHerStart→avatarHerEnd)` + `partner.name[0]` | `Partner` |
| 名稱+時間 header | `Row` 內 `partner.name` + `_formatDate(aggregate.lastInteraction)` | `Partner` + `aggregate.lastInteraction` |
| 熱度 indicator | `latestHeat != null` → emoji+數字+顏色；null → `🌡️ 待分析` 灰字 | `aggregate.latestHeat` |
| Preview + 刪除 | `(unionInterests + unionTraits).take(3).join(' · ')`；trailing `Icon(Icons.delete_outline)` | `aggregate.unionInterests` + `aggregate.unionTraits` |

**Architecture invariant 不破**：
- `PartnerListCard` 收 `(Partner partner, PartnerAggregateView aggregate, VoidCallback onTap, VoidCallback? onDelete)`
- **不 ref.watch**，視覺從已傳入 aggregate derive，符合 Phase 2 lifted-aggregate API
- `_formatDate` 直接 inline 進 card（與 ConversationTile 相同邏輯：今日 HH:mm / 昨天 / N天前 / MM/dd）

**Delete dialog two-mode:**

```dart
Future<void> _onDelete(BuildContext context, WidgetRef ref) async {
  final aggregate = ...; // 從 PartnerListScreen 傳入
  if (aggregate.totalRounds == 0) {
    // Confirm mode
    final confirmed = await showDialog<bool>(...AlertDialog with confirm action);
    if (confirmed == true) {
      try {
        await controller.delete(partner);
        // SnackBar success
      } on PartnerHasConversationsException catch (e) {
        // 防衛性 catch（race condition: dialog 開啟期間用戶建了對話）
        // 提示「請重試」
      }
    }
  } else {
    // Informational mode (no destructive action)
    await showDialog(...AlertDialog with single「我知道了」button,
      content: '此對象有 ${aggregate.totalRounds} 段對話，請先合併或改派');
  }
}
```

**Widget tests（5 條）：**
1. `renders 5 visual pieces given Partner + non-empty aggregate`
2. `falls back to 🌡️ 待分析 when latestHeat is null`
3. `shows interests+traits joined by ' · ' as preview, capped at 3`
4. `tapping delete with empty aggregate (totalRounds==0) shows confirm dialog`
5. `tapping delete with totalRounds>0 shows informational dialog (no destructive action)`

## 7. Task 14 — Same-name dedupe banner

### 7.1 Files

- New `lib/features/partner/data/services/partner_banner_service.dart`
- New `lib/features/partner/presentation/widgets/same_name_dedupe_banner.dart`
- Modify `lib/features/partner/presentation/screens/partner_list_screen.dart`（list 頂部 conditionally render banner）
- Modify `lib/app/routes.dart`（merge picker route 接收 `?target=` query param）
- Modify `lib/features/partner/presentation/screens/partner_merge_picker_screen.dart`（讀 `target` param 並 pre-select）
- New `test/widget/features/partner/same_name_banner_test.dart`
- New `test/unit/features/partner/partner_banner_service_test.dart`

### 7.2 Service

```dart
class PartnerBannerService {
  static String _key(String uid) => 'partner_dedupe_banner_dismissed_$uid';

  static Future<bool> isDismissed(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key(uid)) ?? false;
  }

  static Future<void> markDismissed(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(uid), true);
  }
}
```

抄 `OnboardingService` pattern 加 uid 參數。

### 7.3 Dedupe detection（presentation-layer derive）

```dart
({Partner older, Partner newer})? _findFirstDupPair(List<Partner> partners) {
  final byName = <String, List<Partner>>{};
  for (final p in partners) {
    byName.putIfAbsent(p.name.trim(), () => []).add(p);
  }
  final firstDup = byName.values.firstWhere(
    (group) => group.length >= 2,
    orElse: () => const <Partner>[],
  );
  if (firstDup.length < 2) return null;
  final sorted = [...firstDup]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return (older: sorted.first, newer: sorted.last);
}
```

放在 `partner_list_screen.dart` 內 private helper。

### 7.4 Banner widget

```dart
class SameNameDedupeBanner extends StatelessWidget {
  final String partnerName;
  final VoidCallback onMergeTap;     // 帶到 merge picker pre-fill
  final VoidCallback onDismissTap;   // markDismissed + 收起 banner
}
```

**Placement**：放在 `PartnerListScreen` body 頂部（list 上方），**非 sticky**——隨 scroll 推走。

### 7.5 CTA flow

「立即合併」tap → `context.push('/partner/${newer.id}/merge?target=${older.id}')`
→ `PartnerMergePickerScreen` 從 query param 讀 `target` 並 pre-select 該 row（user 可手動切）

**route 小改：**
```dart
GoRoute(
  path: '/partner/:partnerId/merge',
  builder: (context, state) => PartnerMergePickerScreen(
    sourceId: state.pathParameters['partnerId']!,
    initialTargetId: state.uri.queryParameters['target'], // ← new
  ),
),
```

### 7.6 Tests

**Widget tests（5 條）：**
1. `shows when ≥2 partners share same name and not dismissed`
2. `does not show when all unique`
3. `does not show when service.isDismissed returns true`
4. `tap "以後再說" calls service.markDismissed(uid) and hides banner`
5. `tap "立即合併" pushes /partner/{newer.id}/merge?target={older.id}`

**Service unit tests（3 條）：**
1. `isDismissed returns false when key absent for uid`
2. `markDismissed then isDismissed returns true for same uid`
3. `markDismissed for uid A does not affect uid B (per-account isolation)`

## 8. Task 15 — Copy sweep

### 8.1 Pre-flight grep

```bash
grep -rn "新增對話\|新對話\|建立對話\|對話列表\|你的對話\|還沒有對話\|加一個開始" lib/ \
  | grep -v "_test.dart\|.g.dart\|migration_service\|_repository.dart\|_controller.dart\|@Deprecated"
```

### 8.2 處理規則

| 命中位 | 處理 |
|---|---|
| `lib/app/main_shell.dart` FAB / popup | 改「**+ 新增對象**」 |
| `partner_list_screen.dart` 空狀態 | 改「**還沒有對象，加一個開始**」 |
| `new_conversation_sheet.dart` / `partner_detail_screen.dart` 「+ 新增對話」 | **保留**（partner-scoped 語意正確） |
| domain `Conversation` class | **保留**（D2-A） |
| `@Deprecated HomeContent` 內字串 | **不改**（Task 16 即將砍） |

### 8.3 Snapshot tests（防漂移，3 條）

```dart
testWidgets('home FAB label = "+ 新增對象"', (tester) async { /* ... */ });
testWidgets('partner detail "+ 新增對話" label remains', (tester) async { /* ... */ });
testWidgets('home empty state copy = "還沒有對象，加一個開始"', (tester) async { /* ... */ });
```

### 8.4 邊界陷阱

- `MainShell` popup `key` 別動到（既有 test reference）
- Empty state grep 確認位置（Task 16 會砍 HomeContent，掃要掃對位置）
- `new_conversation_sheet.dart` 是 single source of truth — 改一處全域生效

## 9. Task 16 — 砍 @Deprecated HomeContent + doc closeout

### 9.1 Step 1 — 砍 HomeContent（first commit）

**動作：**
- Delete `lib/features/conversation/presentation/screens/home_screen.dart`（整檔）
- `grep -rn "HomeContent\|home_screen" lib/ test/` 清所有 import / route reference
- 預期殘留位（最少）：`lib/app/routes.dart`（若還有 `/home` fallback）

**驗證：**
```bash
flutter analyze --fatal-infos       # 0 issues
flutter test                        # 全綠
grep -rn "HomeContent" lib/ test/   # 0 hit
```

### 9.2 Step 2 — TF regression checklist 補項

Modify `docs/testflight-regression-checklist.md`，加 A2 ship 段落（含 13 項 critical path，見 §11）。

### 9.3 Step 3 — ADR-15 v2 ship section

Modify `docs/decisions.md`：

```markdown
## ADR #15 — v2 ship（2026-04-XX）

A2 已 ship — Partner list / detail / merge / reassign / dedupe banner / AI summary / 視覺還原 / delete API 全上。

主要決策落地：
- D1 plan-default A（Partner detail 內 +新增對話 線性）
- D2 plan-default A（domain Conversation 命名保留）
- D3 plan-default A（conversation cell tap → analysis）
- D4 plan-default A（dedupe banner 一次性，可永久關，per-account）

Phase 4 新增決策（D-P4-1 ~ D-P4-5）：
- D-P4-1 Partner delete = block-when-non-empty
- D-P4-2 Banner pre-fill = older-as-target / newer-as-source（依 createdAt）
- D-P4-3 PartnerListCard preview = 興趣+特質前 3 tag
- D-P4-4 Heat fallback = 🌡️ 待分析 灰字
- D-P4-5 Banner dismissed = per-account uid-scoped key

A2 後續 follow-up:
- HS1 Sentry SDK 整合（A2 ship 後再裝）
- HS2 重做升級覆蓋舊備份（接受 trade-off）
- 2 週後人工評估是否退役 `conversationsProvider` legacy global invalidation
```

### 9.4 Step 4 — snapshot.md 月度刷新

A2 全 ship 後重寫「當前階段」一句話 + Phase 4 ship date。

### 9.5 Step 5 — Common Pitfalls 補 1 條

CLAUDE.md 加：

> Partner delete 必須先驗 conversation 數，非空時 throw `PartnerHasConversationsException`；UI 需相應切 informational vs confirm dialog（不可省略 guard）

## 10. Task 17 — Pre-PR sanity + ship gate

### 10.1 Step 1 — 全測試 + lint

```bash
~/flutter/bin/flutter test 2>&1 | tee /tmp/phase4_test_output.log
~/flutter/bin/flutter analyze 2>&1 | tee /tmp/phase4_analyze_output.log
```

**Acceptance gates：**
- 0 failing tests
- 0 lint warnings on new files
- 既有 main test count ≤ Phase 4 branch test count
- Skip count 不增（Phase 2 那個 `add_partner_screen` skip 維持 1）

### 10.2 Step 2 — Manual smoke

5 項 critical path：
1. 升級舊資料 → Partner list 顯示 + 新 visual card 5 件套
2. 兩個同名 Partner → banner 顯示 → 「立即合併」帶到 merge picker（target 預選舊 partner）
3. Partner 有對話 → 刪除 icon 跳 informational dialog
4. Partner 無對話 → 刪除 icon 跳 confirm → 確認後 Partner 從 list 消失
5. 切帳戶 → A 關 banner，B 仍看到 banner（per-account 隔離）

### 10.3 Step 3 — 開 PR

```bash
gh pr create --title "Partner Entity Refactor A2 — Phase 4 polish + ship (Tasks 14-18)" --body "..."
```

PR body 含：Summary / Test plan / Phase 4 design decisions（D-P4-1 ~ D-P4-5 引用本 design doc）。

### 10.4 Step 4 — Codex code review handoff

開 `docs/reviews/ai-arbitration-queue.md` 頂部新 item「A2 Phase 4 Code Review」，Status: IN_REVIEW，喊 Codex 審 diff。

## 11. TF Regression Checklist 補項

A2 ship 段落應含 13 項：

1. 升級已有資料 → Partner list 顯示，原 N 個對話 → N 個 Partner cards
2. Partner detail 顯示對應 conversations
3. 「+ 新增對象」FAB 可建 Partner，建完跳 detail
4. 「+ 新增對話」從 Partner detail 進，建完掛在該 Partner
5. 同名 Partner（migration 後）顯示 banner，「以後再說」永久關閉，**且只該帳戶生效**
6. 「合併到其他對象」實際搬遷對話 + customNote 加 [from A] tag
7. 長按 conversation cell 改派 → 兩端 aggregates 都更新
8. **Banner CTA「立即合併」帶到 merge picker，較舊 partner 預選為 target**
9. **Partner 有對話時刪除按鈕跳 informational dialog，無對話時跳 confirm dialog**
10. **PartnerListCard 5 件套全顯示**（avatar / 名稱+時間 / 熱度 or 🌡️待分析 / 興趣 traits 預覽 / 刪除 icon）
11. 跨對話分析 prompt 含 partner summary（log 抽查 < 1500 char）
12. 多帳戶切換不洩漏（A 帳戶 Partners 不入 B 帳戶 list；A 關 banner 不影響 B）
13. 舊 `/conversation/:id` deep-link 仍可開（A1 兩天 soak 已驗，Phase 4 不應破）

## 12. 預估 Commit 結構

| # | Commit | Task | Layer |
|---|---|---|---|
| 1 | `[feat] PartnerWriteController/Repository.delete() + cascade guard` | 18a | data |
| 2 | `[feat] PartnerListCard 視覺還原 5 件套 + delete dialog two-mode` | 18b | UI |
| 3 | `[feat] PartnerBannerService (per-uid SharedPreferences) + 3 unit tests` | 14a | data |
| 4 | `[feat] SameNameDedupeBanner widget + merge picker pre-fill route param` | 14b | UI |
| 5 | `[refactor] copy sweep — UI 「對象」/「對話」雙層詞彙 + snapshot tests` | 15 | UI |
| 6 | `[refactor] 砍 @Deprecated HomeContent — Phase 4 cleanup` | 16a | refactor |
| 7 | `[docs] A2 ship — TF regression + ADR-15 v2 + snapshot + 1 pitfall` | 16b | docs |

7 commits / 0 hotfix 預期。Codex code review 若 verdict REVISED_AND_APPROVED，預期會多 1 個 patch commit。

## 13. Codex Spec Review Hot Spots

請 Codex 特別看這幾個地方：

### HS-P4-1 — `PartnerHasConversationsException` 是否需要 cascade enum 而非單 exception？
- 現設計：單 exception 攜 conversationCount
- Alternative：enum `PartnerDeleteFailureReason { hasConversations, ... }` + 多 case
- 評估：Phase 4 只有一種 failure reason，YAGNI

### HS-P4-2 — `try/finally` invalidation 在 delete 是否 over-applied？
- 對齊 PR-B Codex r1 patch pattern
- 但 delete 失敗時 partner 沒被刪，invalidate `partnerListProvider` 真的有意義嗎？
- 評估：保險。即使 box.delete 沒跑到，invalidate 不會錯顯（會 re-read 同一筆 partner），代價低

### HS-P4-3 — Banner detection 在 presentation 層 derive 是否該抽 domain extension？
- 現設計：`_findFirstDupPair` 放在 `partner_list_screen.dart` private helper
- Alternative：放 `partner_aggregates.dart` 旁邊作 collection-level extension
- 評估：detection 邏輯純 presentation（只 banner 用），不污染 domain

### HS-P4-4 — Merge picker route 加 `?target=` query param 是否破壞既有 URL 慣例？
- 現有：`/partner/:partnerId/merge` (path param only)
- 改後：`/partner/:partnerId/merge?target=...` (path + query)
- Phase 3 PR-B 已 ship 既有 route，要驗 query param 不會破壞既有 init flow
- 評估：query param 是 optional，沒帶就維持原本「user 自選」行為，向後相容

### HS-P4-5 — Tag preview「興趣+特質前 3」串接順序敏感嗎？
- 現設計：`(interests + traits).take(3)` — interests 優先吃進 3 名額
- 邊界：partner 有 5 個 interests + 5 traits → 顯示 3 個 interests，0 個 traits
- 用戶可能更想看「至少 1 個 trait」（因為 trait 比 interest 更具描述性）
- Alternative：interleave - `[i0, t0, i1, t1, i2]`.take(3)
- 評估：值得 Codex 提意見

## 14. Risks & Mitigations

| Risk | 影響 | Mitigation |
|---|---|---|
| 砍 `@Deprecated HomeContent` 漏清 reference | 編譯失敗 / route fall-through | Task 16 step 1 先 grep 全 codebase，flutter analyze + flutter test 雙 gate；commit 前手動再 grep 一次 |
| Banner CTA route 帶錯 source/target id | 用戶在 picker 看到「自己合併自己」之類錯誤狀態 | Widget test #5 明確驗 push URL；merge picker 內部 guard `sourceId != targetId` 已存在（Task 12 已 ship） |
| `PartnerHasConversationsException` race（dialog 開啟時用戶建對話） | 點 confirm 後 throw | Task 18b 防衛性 catch + 「請重試」SnackBar；不 panic |
| Per-account banner key 換帳戶後沒 dismiss state 遺漏 | A 關了 banner，A 重登後仍看到 | uid 取自 `Supabase auth.currentUser?.id`，登出登入 uid 不變 → 應該 OK；service unit test #3 已驗隔離 |
| 文案掃漏（D2-A 例外位） | TF 看到字串不一致 | snapshot tests 覆蓋 3 條 critical path；Codex spec review 也會 grep 一輪 |

## 15. Branch / Commit / Push protocol

- Branch: `feature/partner-entity-A2-polish`，從 main `1794371` 切
- 每 commit 後立即 push（CLAUDE.md 全域硬規則）
- Commit message 繁中、`[類型] 簡短描述` 格式
- 一個 commit 一件事；7 commits 預期；Codex patch 若有額外多 1
- 不 amend / 不 force push / 不 --no-verify

## 16. 喊 Codex spec review handoff

執行完本 design doc commit + push 後，於 `docs/reviews/ai-arbitration-queue.md` 開 item：

- Status: IN_REVIEW
- Request-Type: review
- Raised-By: Claude
- Owner: Codex
- Question: spec review the Phase 4 design covering Tasks 14-18 + hidden delete API
- Verdict 期望：APPROVED / REVISED_AND_APPROVED (with patches) / REVISE
- Round budget: 1-3 輪（PR-A 1 輪、PR-B 2 輪先例）

Codex APPROVED 後再開實作 plan 並切 branch；若 REVISED 則 patch 同 queue item 走 r2。
