# A2 Phase 3 PR-A — partnerId Chain Validation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task.

**Goal:** 用 4 個 hermetic widget tests 驗證 Phase 2 已接通的 partnerId chain（manual + 截圖兩條 path），確保 PartnerDetail 的 `+ 新增對話` 進來的 conversation 一律帶上正確 partnerId。

**Architecture:** 純 widget test（0 production code）。Pattern：`ProviderScope` override `conversationWriteControllerProvider` 改用 recording fake notifier，捕 `controller.create(partnerId:)` 的 args，斷言透傳正確。Sheet 路徑用 minimal `GoRouter` 提供 `context.go` / `router.push` 必要 plumbing，Phase 2 hermetic pattern (`partner_detail_screen_test.dart`) 為主要參考。

**Tech Stack:** Flutter, Riverpod NotifierProvider override, `flutter_test`, GoRouter (test harness only).

---

## ⚠️ Reality Check — Plan Scope Deviates From Design Doc

讀 code 後發現 design doc §4 有兩個 aspirational 假設與現行 code 不符，PR-A 不寫對應 test：

| 原假設（design doc） | 現行 code 行為 | PR-A 處理 |
|---|---|---|
| legacy null partnerId 在 create 時走 `PartnerIdFactory` 自動建 Partner | `ConversationRepository.createConversation` 直接存 `partnerId=null`，無 fallback。Partner 由 A1 migration 在 app 啟動時補建 | **不測** auto-derive。改測「null 透傳到 controller.create 是 null」（行為文件化）|
| name 空白時 default 到「YYYY/MM/DD 新對話」 | 空白時跳 snackbar `請先輸入對方名稱` 錯誤，無 default | **不測** default name |

**這個 deviation 不擋 PR-A merge**，但 PR-B / Phase 4 之前要決定：
1. Auto-derive on create 是否要做？（UX：legacy null 立即可見 vs 等 migration backfill）
2. Default name 是否要加？（screenshot path 已 hardcode `'新對話'`，manual entry 需用戶填）

→ 暫記入 `reference_partner_refactor_in_flight.md` 「Phase 4 待決議」段，PR-A 收尾時補。

---

## 🔁 r2 Patch — 修正 helper + CTA finder（2026-04-27）

Codex spec review r1（`docs/reviews/2026-04-27_partner-entity-A2-phase3-pr-a-plan_codex-review.md`，HEAD `539950e`）抓到兩個 P1，皆是「test 看似驗 chain 但其實永遠 short-circuit 在 production 早 return / 找不到真實 widget」：

| # | 問題 | r2 修法 |
|---|---|---|
| P1-A | `_fillNameAndOneMessage()` 只填名字，沒輸入 / tap 加號 → `_messages` 空 → `_createConversation()` 在 `if (_messages.isEmpty)` (line 116-121) snackbar return，永遠跑不到 `controller.create()` | helper 補：`enterText` 第二個 TextField + tap `Icons.add` first |
| P1-B | CTA finder 用 `find.widgetWithText(ElevatedButton, RegExp('儲存\|建立').toString())`，問題雙殺：(1) production 是 `GradientButton` (line 481)，不是 `ElevatedButton`；(2) `RegExp.toString()` 產 `"RegExp: pattern=儲存\|建立 flags="` literal string，不是 regex matcher | 改 `find.byType(GradientButton)` + 額外 assert `find.text('建立對話')`（`_hasIncomingMessage=true` 後固定，line 46）|

R1/R3/R4 Codex 全部 accept（不需 ADR-16 / Reality Check 維持原樣 / 加 Key 可接受但獨立 commit）。

---

## Pre-flight（Task 0）

執行：

```bash
git status
git log -1 --format=oneline
ls test/widget/features/partner/
```

預期：
- `On branch feature/partner-entity-A2-flows-data`，working tree clean
- HEAD = `bc1017d [docs] plan: Phase 3 design 收斂 — 兩 sub-PR + 4 design decisions`
- `partner_detail_screen_test.dart` 存在（Phase 2 hermetic test 參考）

跑 baseline test 確保 Phase 2 沒被打壞（用 cmd.exe 因 WSL flutter binary 壞）：

```bash
cmd.exe /c "flutter.bat test test\widget\features\partner --reporter expanded"
```

預期：all green（Phase 2 留下的 partner widget tests 全過）。

若有 fail → STOP，先 root-cause，不要繼續 Phase 3。

---

## Task 1 — 建立 RecordingConversationWriteController fake

**Files:**
- Create: `test/widget/features/conversation/_fakes/recording_conversation_write_controller.dart`

**Step 1：寫 fake 檔**

```dart
// test/widget/features/conversation/_fakes/recording_conversation_write_controller.dart
//
// Hermetic test double for ConversationWriteController. Captures partnerId
// passed to create() so PR-A widget tests can assert Phase 2's chain
// without Hive/Supabase. save() is no-op since downstream state is not
// under test in PR-A.
import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/domain/entities/conversation.dart';
import 'package:vibesync/features/conversation/domain/entities/message.dart';

class RecordingConversationWriteController extends ConversationWriteController {
  bool createCalled = false;
  String? capturedPartnerId;
  String? capturedName;
  int capturedMessageCount = 0;

  @override
  Future<Conversation> create({
    required String name,
    required List<Message> messages,
    String? partnerId,
  }) async {
    createCalled = true;
    capturedPartnerId = partnerId;
    capturedName = name;
    capturedMessageCount = messages.length;
    return Conversation(
      id: 'fake-conv-id',
      name: name,
      messages: messages,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      partnerId: partnerId,
    );
  }

  @override
  Future<void> save(Conversation c, {String? previousPartnerId}) async {
    // no-op for hermetic widget test
  }
}
```

**Step 2：跑 analyze 確認 fake 可編**

```bash
cmd.exe /c "flutter.bat analyze test\widget\features\conversation\_fakes\recording_conversation_write_controller.dart"
```

預期：`No issues found!`

**Step 3：Commit（不 push，在最後 Task 6 一起 push）**

```bash
git add test/widget/features/conversation/_fakes/recording_conversation_write_controller.dart
git commit -m "[test] 加 RecordingConversationWriteController fake (PR-A Task 1)

Phase 3 PR-A 4 個 widget test 共用，捕 controller.create 的 partnerId arg。
subclass 既有 ConversationWriteController，覆寫 create + save，0 Hive、
0 Supabase 依賴。Phase 2 hermetic pattern 延續。"
```

---

## Task 2 — Test：NewConversationScreen 透傳 partnerId arg

**Files:**
- Create: `test/widget/features/conversation/new_conversation_screen_partner_id_test.dart`

**Step 1：寫第一個 failing test**（先確認 harness 可跑）

```dart
// test/widget/features/conversation/new_conversation_screen_partner_id_test.dart
//
// Hermetic widget tests for NewConversationScreen partnerId chain.
// Verifies that the partnerId arg passed to the screen is propagated all
// the way to ConversationWriteController.create(partnerId:). Phase 2
// already wired this; PR-A locks it in as a contract test.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/presentation/screens/new_conversation_screen.dart';
import 'package:vibesync/shared/widgets/warm_theme_widgets.dart'; // GradientButton

import '_fakes/recording_conversation_write_controller.dart';

GoRouter _routerWith(String? partnerId) => GoRouter(
      initialLocation: '/new',
      routes: [
        GoRoute(
          path: '/new',
          builder: (_, __) => NewConversationScreen(partnerId: partnerId),
        ),
        GoRoute(
          path: '/conversation/:id',
          builder: (_, __) => const Scaffold(body: Text('post-create stub')),
        ),
      ],
    );

Future<void> _fillNameAndOneMessage(WidgetTester t) async {
  // Production reality (`new_conversation_screen.dart`)：
  //   - default state（personalization 未展開）TextField 順序：
  //     [0] 對話對象 name (_nameController, line 270)
  //     [1] 她的訊息 (_herMessageController, line 429)
  //     [2] 我的訊息 (_myMessageController, line 448)
  //   - 加號按鈕 = `_buildAddButton(_addHerMessage)` (line 435)，
  //     內含 `Icons.add` (line 188)。第二顆相同 icon 是 _addMyMessage。
  //   - 必須真的 _messages.add 一則，否則 _createConversation()
  //     line 116-121 snackbar early return，controller.create 永遠不會被叫。
  //   - 一條 her message 入列 → _hasIncomingMessage=true → CTA 文字固定「建立對話」(line 46)。
  await t.enterText(find.byType(TextField).at(0), 'Alice');
  await t.enterText(find.byType(TextField).at(1), '嗨');
  await t.tap(find.byIcon(Icons.add).first);
  await t.pumpAndSettle();

  // FALLBACK（only if Icons.add finder 不準）：在 production 加 `Key('her_message_add')`
  // 等 stable Key，**獨立 commit** `[refactor] 補 widget test key`，不混 test commit。
  // Codex r2 review acknowledge 此 minimal hook OK（review doc 539950e Findings§Patch）。
}

void main() {
  testWidgets('partnerId arg "p-test" propagates to controller.create', (t) async {
    final fake = RecordingConversationWriteController();

    await t.pumpWidget(ProviderScope(
      overrides: [
        conversationWriteControllerProvider.overrideWith(() => fake),
      ],
      child: MaterialApp.router(routerConfig: _routerWith('p-test')),
    ));
    await t.pumpAndSettle();

    await _fillNameAndOneMessage(t);

    // CTA = GradientButton (production line 481-485, NOT ElevatedButton).
    // _hasIncomingMessage=true 後 text 固定「建立對話」(line 46)。
    final cta = find.byType(GradientButton);
    expect(cta, findsOneWidget,
        reason: 'GradientButton CTA renders after a「her message」 is added');
    expect(find.text('建立對話'), findsOneWidget,
        reason: '_hasIncomingMessage=true 應 render 文字「建立對話」(line 46)');

    await t.tap(cta);
    await t.pumpAndSettle();

    expect(fake.createCalled, isTrue);
    expect(fake.capturedPartnerId, 'p-test');
    expect(fake.capturedName, 'Alice');
    expect(fake.capturedMessageCount, greaterThanOrEqualTo(1));
  });
}
```

**Step 2：跑 test 看是否能完成 finder/CTA chain**

```bash
cmd.exe /c "flutter.bat test test\widget\features\conversation\new_conversation_screen_partner_id_test.dart --reporter expanded"
```

可能結果：
- ✅ PASS → Phase 2 chain 確實 working，繼續 Task 3
- ❌ FAIL on finder（找不到「她的訊息」add button）→ 讀 `lib/features/conversation/presentation/screens/new_conversation_screen.dart` 找對應 widget tree，調整 finder。**最後手段**：在 production 加 `Key('her_message_add_button')` 等 test hook，commit 前獨立成 `[refactor] 補 widget test key for partnerId chain test` commit
- ❌ FAIL on `controller.create` 沒被叫 → 表示 Phase 2 chain 斷了（regression），STOP 並 escalate 為 production fix（這場 PR-A scope expand）

**Step 3：若 PASS，commit；若 FAIL，先修 Step 2 finder 再 commit**

```bash
git add test/widget/features/conversation/new_conversation_screen_partner_id_test.dart
# 若有改 production code 加 keys：
# git add lib/features/conversation/presentation/screens/new_conversation_screen.dart
git commit -m "[test] new_conversation_screen 補 partnerId 透傳 widget test (Task 2)

驗 Phase 2 已接通的 chain：partnerId arg → controller.create(partnerId:)。
Hermetic：Riverpod override RecordingConversationWriteController，無 Hive。
GoRouter test harness 提供 context.go 必要 plumbing。"
```

---

## Task 3 — Test：NewConversationScreen partnerId=null 透傳 null

**Files:**
- Modify: `test/widget/features/conversation/new_conversation_screen_partner_id_test.dart`（同檔加 test）

**Step 1：在同檔 main() block 內加第二個 test**

```dart
testWidgets('partnerId arg null (legacy entry) propagates as null', (t) async {
  final fake = RecordingConversationWriteController();

  await t.pumpWidget(ProviderScope(
    overrides: [
      conversationWriteControllerProvider.overrideWith(() => fake),
    ],
    child: MaterialApp.router(routerConfig: _routerWith(null)),
  ));
  await t.pumpAndSettle();

  await _fillNameAndOneMessage(t);

  // 同 Task 2：GradientButton + 文字「建立對話」（一條 her message 已入列）。
  final cta = find.byType(GradientButton);
  await t.tap(cta);
  await t.pumpAndSettle();

  expect(fake.createCalled, isTrue);
  expect(fake.capturedPartnerId, isNull,
      reason: 'Legacy entry without partnerId arg should pass null to controller.create. '
              'Auto-derive on create is NOT implemented in current architecture; '
              'A1 migration backfills Partners on app start. Phase 4+ may revisit.');
});
```

**注意 reason 字串**：明寫「auto-derive on create 不存在於現行 architecture」當做合約 doc，未來若有人要加 auto-derive，這個 test 會強制他改 assertion 從 `isNull` → `isNotNull` 並更新 reason，避免 silent behavior drift。

**Step 2：跑兩個 test 都過**

```bash
cmd.exe /c "flutter.bat test test\widget\features\conversation\new_conversation_screen_partner_id_test.dart --reporter expanded"
```

預期：2/2 PASS。

**Step 3：Commit**

```bash
git add test/widget/features/conversation/new_conversation_screen_partner_id_test.dart
git commit -m "[test] new_conversation_screen 補 partnerId=null 透傳合約 (Task 3)

文件化「legacy entry (partnerId null) 透傳 null 到 controller.create，
不 auto-derive」是現行行為。auto-derive on create 是 Phase 4+ 待議
題目，這個 assertion 將強制未來 contributor 在改架構時 explicit revisit。"
```

---

## Task 4 — Test：NewConversationSheet 截圖 path 透傳 partnerId arg

**Files:**
- Create: `test/widget/features/conversation/new_conversation_sheet_screenshot_test.dart`

**Step 1：寫 test**

```dart
// test/widget/features/conversation/new_conversation_sheet_screenshot_test.dart
//
// Hermetic widget tests for NewConversationSheet's screenshot ListTile.
// Verifies that the partnerId passed to the sheet is propagated to
// controller.create(partnerId:) when the user taps「截圖開始」. Pairs
// with new_conversation_screen_partner_id_test.dart to cover both
// manual + screenshot conversation creation paths.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:vibesync/features/conversation/data/providers/conversation_write_controller.dart';
import 'package:vibesync/features/conversation/presentation/widgets/new_conversation_sheet.dart';

import '_fakes/recording_conversation_write_controller.dart';

GoRouter _sheetTestRouter(String? partnerId) {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => Scaffold(
          body: Builder(
            builder: (ctx) => Center(
              child: ElevatedButton(
                onPressed: () => showModalBottomSheet(
                  context: ctx,
                  builder: (_) => NewConversationSheet(partnerId: partnerId),
                ),
                child: const Text('open sheet'),
              ),
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/conversation/:id',
        builder: (_, __) => const Scaffold(body: Text('post-create stub')),
      ),
      GoRoute(
        path: '/new',
        builder: (_, __) => const Scaffold(body: Text('manual entry stub')),
      ),
    ],
  );
}

void main() {
  testWidgets('sheet partnerId="p-test" + 截圖開始 → controller.create(partnerId: "p-test")',
      (t) async {
    // Phase 2 已驗 sheet bottom sheet 在 800x600 default 有 1.5px overflow。
    // 用 partner_detail_screen_test.dart 的 setSurfaceSize pattern 避開。
    await t.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));

    final fake = RecordingConversationWriteController();

    await t.pumpWidget(ProviderScope(
      overrides: [
        conversationWriteControllerProvider.overrideWith(() => fake),
      ],
      child: MaterialApp.router(routerConfig: _sheetTestRouter('p-test')),
    ));
    await t.pumpAndSettle();

    await t.tap(find.text('open sheet'));
    await t.pumpAndSettle();

    expect(find.text('截圖開始'), findsOneWidget);
    await t.tap(find.text('截圖開始'));
    await t.pumpAndSettle();

    expect(fake.createCalled, isTrue);
    expect(fake.capturedPartnerId, 'p-test');
    expect(fake.capturedName, '新對話',
        reason: '截圖 path hardcodes 名稱「新對話」(NewConversationSheet line 96)');
    expect(fake.capturedMessageCount, 0,
        reason: '截圖 path 在 sheet 階段不傳 messages — OCR 完才補');
  });
}
```

**Step 2：跑 test**

```bash
cmd.exe /c "flutter.bat test test\widget\features\conversation\new_conversation_sheet_screenshot_test.dart --reporter expanded"
```

預期：PASS。
若 FAIL：
- finder「截圖開始」找不到 → 檢查 NewConversationSheet line 81，確認 ListTile title 文字
- `surfaceSize` overflow → Phase 2 已測過 400x900 OK，理論上不該再現

**Step 3：Commit**

```bash
git add test/widget/features/conversation/new_conversation_sheet_screenshot_test.dart
git commit -m "[test] new_conversation_sheet 補 截圖 partnerId 透傳合約 (Task 4)

驗 Phase 2 已接通：sheet partnerId arg → ListTile「截圖開始」onTap →
controller.create(partnerId:)。setSurfaceSize 400x900 沿用 Phase 2 pattern。
hardcoded name「新對話」/ messages=[] 同時當合約寫入 reason 字串。"
```

---

## Task 5 — Test：NewConversationSheet 截圖 path partnerId=null 透傳 null

**Files:**
- Modify: `test/widget/features/conversation/new_conversation_sheet_screenshot_test.dart`（同檔加 test）

**Step 1：在同檔 main() 加第二個 test**

```dart
testWidgets('sheet partnerId=null + 截圖開始 → controller.create(partnerId: null)',
    (t) async {
  await t.binding.setSurfaceSize(const Size(400, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));

  final fake = RecordingConversationWriteController();

  await t.pumpWidget(ProviderScope(
    overrides: [
      conversationWriteControllerProvider.overrideWith(() => fake),
    ],
    child: MaterialApp.router(routerConfig: _sheetTestRouter(null)),
  ));
  await t.pumpAndSettle();

  await t.tap(find.text('open sheet'));
  await t.pumpAndSettle();

  await t.tap(find.text('截圖開始'));
  await t.pumpAndSettle();

  expect(fake.createCalled, isTrue);
  expect(fake.capturedPartnerId, isNull,
      reason: 'Legacy entry: 從非 PartnerDetail 進入截圖 flow（例如未來新加的 home FAB '
              '快捷），sheet 不帶 partnerId → controller.create(partnerId: null)。'
              '與 manual entry path 一致：auto-derive on create 不在現行架構。');
});
```

**Step 2：跑兩個 sheet test**

```bash
cmd.exe /c "flutter.bat test test\widget\features\conversation\new_conversation_sheet_screenshot_test.dart --reporter expanded"
```

預期：2/2 PASS。

**Step 3：Commit**

```bash
git add test/widget/features/conversation/new_conversation_sheet_screenshot_test.dart
git commit -m "[test] new_conversation_sheet 補 截圖 partnerId=null 透傳合約 (Task 5)

兩條 sheet path 對稱於 manual：partnerId 透傳到 controller.create，null 也透傳。
PR-A 4 個 widget test 收齊。"
```

---

## Task 6 — Full sweep + push

**Step 1：跑全 PR-A 測試 + Phase 2 baseline 一起，確認沒打壞任何既有 test**

```bash
cmd.exe /c "flutter.bat test test\widget\features --reporter expanded"
```

預期：
- 4 個 PR-A 新 test 全 PASS
- Phase 2 留下的 partner widget tests 全 PASS
- 無新 warning / overflow

**Step 2：跑 analyze**

```bash
cmd.exe /c "flutter.bat analyze --no-fatal-infos"
```

預期：`No issues found!`

**Step 3：push branch（不開 PR，等 Codex spec review APPROVED 才開）**

```bash
git push -u origin feature/partner-entity-A2-flows-data
```

預期：branch 上 remote，4-5 個 commit 全推上。

---

## Task 7 — 喊 Codex code review + queue 開新 item

**Step 1：在 `docs/reviews/ai-arbitration-queue.md` 頂部加 PR-A live item**

```markdown
## [LIVE] A2 Phase 3 PR-A — partnerId Chain Validation Tests

**Status**: AWAITING_CODEX_REVIEW
**Branch**: `feature/partner-entity-A2-flows-data`
**Plan**: `docs/plans/2026-04-27-partner-entity-A2-phase3-pr-a-impl.md`
**Design**: `docs/plans/2026-04-27-partner-entity-A2-phase3-design.md`

### Round 1 — YYYY-MM-DD HH:MM

Diff scope（4-5 commits）：
- 1 fake notifier (test/.../_fakes/...)
- 4 widget tests（manual + 截圖 path × partnerId arg + null）
- 0 production code（除非 Task 2/Step 2 為了 finder 加 widget Key，這場視結果決定）

Reviewer-Hint: 主要看 4 個 test 是否真的在驗「Phase 2 已接通」(green path) +
「null 不 auto-derive」(documented behavior contract). Auto-derive on create
是 design doc §11 點名的 Phase 4+ 待議題，PR-A 故意不測。

預期 Verdict：APPROVED 或 REVISE（小調整）。1 輪結束機率高。
```

**Step 2：開 review request 給 Codex（user-side action — Eric 跑 codex CLI / Discord）**

跑（user 自己決定哪個入口）：
- `codex review feature/partner-entity-A2-flows-data` 或
- Discord 喊 Codex 審 branch

**Step 3：等 Codex review 結果**

- ✅ APPROVED → 開 PR + 等 TF QA gate（見 Task 8）
- 🔴 REVISE → 依 verdict 直接修，commit 推 branch，update queue item Round 2，重審

---

## Task 8 — 開 PR + 喊 TF QA gate

**Step 1：開 PR**

```bash
gh pr create --title "[A2 Phase 3 PR-A] partnerId chain validation tests" \
  --body "$(cat <<'EOF'
## Summary

Phase 3 第一個 sub-PR — 純 hermetic widget test work，驗證 Phase 2 已接通的
partnerId chain（manual + 截圖兩條 path）。0 行 production code。

### Scope
- `test/widget/features/conversation/_fakes/recording_conversation_write_controller.dart` — 共用 fake notifier
- `test/widget/features/conversation/new_conversation_screen_partner_id_test.dart` — manual path × 2 tests
- `test/widget/features/conversation/new_conversation_sheet_screenshot_test.dart` — 截圖 path × 2 tests

### Reality check（plan §⚠️ Reality Check 補充）
- legacy null partnerId **不 auto-derive on create**（A1 migration 補 Partner），
  PR-A 把這條當作 documented contract 寫進 test reason，未來改架構強制 explicit revisit
- default name `YYYY/MM/DD 新對話` 不存在於現行 code，PR-A 不測

### Test plan
- [ ] PR-A 4 個 widget test 全 PASS（CI Flutter test job）
- [ ] Phase 2 既有 partner widget tests 不 regression
- [ ] TF QA gate 1 項：v141+ build 從 PartnerDetail「+ 新增對話」→ 手動 / 截圖
      建出的對話的 partnerId 正確 propagate（已在 Phase 2 TF QA 項 3 驗過，PR-A
      不重複 manual 步驟，純 ship 後監測 1 天）

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)" --base main
```

**Step 2：等 CI**（pubspec.yaml 已 pin 的 Flutter version）

預期：CI 全綠（test job + analyze job）。

**Step 3：TF QA gate（1 項）**

PR-A 是 test-only PR，**TF QA 行為與 Phase 2 相同**——Phase 2 TF QA 項 3 已驗手動 + 截圖跨 partner。PR-A 加的 test 是 regression guard，TF gate 簡化為：

> 在 v142+ TF build 上跑一次 PartnerDetail「+ 新增對話」→ 手動 / 截圖 各一條對話，檢查 partnerId 正確掛載。

預估 5 分鐘。Eric 跑完回報「綠」即可進入 merge gate。

**Step 4：Merge → branch 雙刪 → soak 1 天**

```bash
gh pr merge --squash --delete-branch  # 或 user UI 上 Create a merge commit
git checkout main
git pull --ff-only
git branch -d feature/partner-entity-A2-flows-data 2>/dev/null || true
```

**Step 5：Update queue item → CLOSED + 寫 closeout commit**

```bash
# edit docs/reviews/ai-arbitration-queue.md PR-A item: Status: CLOSED + 加 result section
git add docs/reviews/ai-arbitration-queue.md
git commit -m "[docs] queue: A2 Phase 3 PR-A CLOSED — partnerId chain tests 入庫"
git push
```

---

## Failure Protocols

### Test 在 Task 2/3/4/5 任一 step FAIL（非 finder 問題，是真實 chain regression）

PR-A scope expand 為 production fix。流程：
1. STOP，先標出哪一條 chain 斷了（debug print / 讀 code）
2. 寫 1 個 commit 修 production，commit msg 開頭 `[fix]` 而非 `[test]`
3. 在 plan 末尾加 Round 2 entry 描述 fix
4. queue item Status 改 `IN_PROGRESS_PRODUCTION_FIX`
5. 重跑 Task 6 全 sweep
6. Codex code review 必須看 fix（不只是看 test）

### Plan 與 master plan 已記載的 deviation 衝突

`design.md` § Reality Check 已點名兩個 master plan 假設與 code 不符（auto-derive / default name）。若 Codex spec review r1 抓到「為什麼不照 master plan 測？」，回應就是這個 deviation 的 reasoning（指 design doc + plan §⚠️）。Plan 不再為了配合 master plan 寫 aspirational test。

### Windows flutter.bat hang

`add_partner_screen_test.dart` 「successful submit」test 已知會 hang（skip:true）。PR-A 4 個新 test **不要碰 pushReplacement / Hive write future**——所有 navigation 用 GoRouter stub route，Storage write 用 fake controller no-op。若仍 hang，可疑點優先級：
1. `pumpAndSettle` timeout：縮短 await 或改用 `pump(Duration(milliseconds: 100))`
2. Provider 還沒 dispose：每 test 結束加 `addTearDown(() => container?.dispose())`
3. 環境性 Windows kernel cache（已 falsified）：**不再戰**，標 skip + 寫 reason，不 block PR-A

---

## DoD（Definition of Done）

PR-A 真正完成的條件：

- [ ] 5-6 commits 推到 `feature/partner-entity-A2-flows-data`
- [ ] CI 全綠（test + analyze）
- [ ] Codex code review APPROVED
- [ ] PR merge 進 main，feature branch 雙刪
- [ ] queue item Status: CLOSED
- [ ] `reference_partner_refactor_in_flight.md` Phase 3 PR-A 段更新為 ✅
- [ ] memory 補一筆「Phase 4 待議：auto-derive on create + default name」issue tracker entry

---

## 後續

PR-A merge + soak 1 天後 → 切 `feature/partner-entity-A2-flows-pickers`，啟動 PR-B impl plan 寫作（writing-plans 第二輪）。PR-B scope（Tasks 12+13 — merge picker + reassign ⋮ menu）詳見 design doc §5。
