# Partner Entity Refactor — A2 Phase 3 Design

**Date**: 2026-04-27
**Phase**: A2 Phase 3 (Tasks 10-13 — flows: enabling ⋮ menu handlers)
**Branches**: 2 sub-PRs from main (`9b2a36c`)
**Master plan reference**: `docs/plans/2026-04-26-partner-entity-A2-impl.md` lines 888-1028
**Design doc 角色**：紀錄 design decisions + master plan deviations 的 *why*。`how` 留在後續兩份 phase impl plan。

---

## 1. Scope confirmation

Phase 3 = **Tasks 10-13**（修正了 `reference_partner_refactor_in_flight.md` 早期版本誤把 Task 14 排在 Phase 3 的內部矛盾）。

| Task | 主題 | 真實 scope |
|---|---|---|
| 10 | New conversation flow partnerId chain | **驗證**（Phase 2 已接通）+ 補 widget tests |
| 11 | Screenshot flow auto-attach Partner | **驗證**（D1-A）+ legacy fallback test |
| 12 | Merge UI | 真實作 — picker + confirm dialog + ⋮ menu enable |
| 13 | Conversation reassign | 真實作 — tile ⋮ menu + reuse Task 12 picker |

Task 14 (same-name banner) 移回 Phase 4，因為其「立即合併」CTA 依賴 Phase 3 落地的 merge picker。

---

## 2. PR slicing decision — 兩個 sub-PR

| 評估項 | 單 PR (4 tasks) | 兩個 sub-PR (10+11 / 12+13) |
|---|---|---|
| Diff 量 | ~1500 / -200 | PR-A ~200，PR-B ~1200 |
| TF QA gate 個數 | 1 大 | 2 個小 + 焦點清楚 |
| Soak 機會 | 0（4 件一次 ship）| PR-A 先 soak 1 天再做 PR-B |
| Codex review 負荷 | 1 大 review，混淆 risk | 2 個小 review，risk surface 清楚 |
| 流程 overhead | 低 | 高 ~30%（兩次 plan / spec review）|

**決定：兩個 sub-PR**。PR-A 是純 validation work（hidden risk surface 小），PR-B 是 destructive UI 真實作（high risk）—— risk profile 反差讓拆 PR 比合 PR 更值得。

**Branch naming**:
- PR-A: `feature/partner-entity-A2-flows-data`
- PR-B: `feature/partner-entity-A2-flows-pickers`

`-data` / `-pickers` 尾綴避免跟 master plan 寫的 `feature/partner-entity-A2-flows`（單一 branch 假設）名稱碰撞。

---

## 3. Design decisions

### D1 reconfirm — 截圖 flow Partner 掛載：採 plan-default A

從 ADR 級設計到 Phase 3 落地，D1 仍採 master plan default A：

> 用戶從 PartnerDetail「+ 新增對話」→ 截圖 → OCR → 完成後 partnerId 已從 args 透傳，**不再 picker**。Legacy entry (partnerId null) 走 A1 `PartnerIdFactory` auto-create。

**決議理由（沿用，非新增）**：
1. Phase 2 已將 Home 改為 PartnerListScreen，用戶主路徑必先建 Partner
2. C 路徑「匿名 `對象 #abc`」會以「未命名對象」形式讓 Bruce 痛點重現
3. B picker 多一步打斷，現有 Phase 2 TF QA 項 3 已驗 A 路徑 working
4. A fallback 直接 reuse A1 已 ship 的 `PartnerIdFactory`，0 新 production code

**Task 11 落地形式**：純驗證 + 補 test，0 行 production code（除非驗證中發現 partnerId 沒 propagate，升級為 fix）。

### Merge confirm dialog — D 版（stats + 紅字警告併存）

Master plan 列了 4 種 union stats（對話數搬遷 / 特質聯集 / 互動累計 / 保留 B avatar），但 confirm dialog 該顯示什麼是用戶心理安全 vs 資訊量的 trade-off。

| 選項 | 內容 | 為何不選 |
|---|---|---|
| A（master plan default 全 4 行）| 4 stats + commit/cancel | 資訊正確但 UI 重，confirm button 視覺權重稀釋 |
| B（精簡兩行）| `N 對話搬遷` + `共 M traits` | 缺「不可逆」警語，destructive 操作心理安全感不足 |
| C（單句紅字版）| 紅字 + commit | `N 對話` 這個關鍵具象 metric 應該明示，不該只有抽象警語 |
| **D**（B+C 混合，**最終選**）| `N 對話` + `M traits` + 紅字「⚠️ 此操作無法復原」 | 兼顧資訊量與心理安全感 |

「保留 B avatar」**不在 dialog 顯**——picker 已選 B，avatar = B 是隱含結果，不是新訊息。

### Task 13 trigger — B 版（trailing ⋮ menu）— **偏離 master plan**

Master plan line 1012 寫死 `long-press cell shows action`（A 版）。本 design 改為 B 版（trailing 改 ⋮ menu），偏離 master plan。

| 選項 | 可發現性 | 視覺 noise | 為何不選 |
|---|---|---|---|
| A long-press（master plan）| 低（隱藏 gesture）| 0 | VibeSync 目標 20-35 非技術 user，Bruce-tier 不會試 long-press |
| **B trailing ⋮**（**最終選**）| 高（icon 可見）| +1 icon per cell（取代 chevron）| — |
| C swipe-to-reveal | 中（iOS native）| 0 | Android 用戶陌生；Flutter 跨平台 portability 略差 |
| D analysis_screen 內 app bar | 中（要進 detail 才看到）| 0 | 要先 tap 進去才能管理 cell，flow 變長 |

**決議理由**：
1. **可發現性是 Phase 3 最重要 UX 屬性**——reassign 是 Bruce 痛點解方，hidden 等於不存在
2. **未來擴張友善**：Phase 4 / 之後若加「刪除對話」secondary action，⋮ menu 直接加 item，bottom sheet (A) 要重排序
3. **與 PartnerDetail ⋮ menu 視覺一致**：Phase 2 已建立 ⋮ icon = 「對這個東西做操作」的 mental model，conversation cell 沿用
4. **取代 chevron 0 視覺成本**：trailing 已是 chevron 視覺權重，換 ⋮ 不增加 cell height，tap 區域不變

**Spec review 義務**：本 deviation 必須在 PR-B impl plan 明寫，並更新對應 widget test（master plan line 1012 寫的 long-press test 改成 ⋮ tap test）。Codex spec review 必須 explicit acknowledge 這個 trade-off。

---

## 4. PR-A 細節（Tasks 10+11）

### Task 10 — NewConversationScreen partnerId chain validation

**現況**：`new_conversation_screen.dart` 已有 `final String? partnerId` arg（line 14, 16, 135）。
**Task 10 真實 scope**：純補 widget tests，0 行 production code（除非驗證中發現 chain 漏接）。

**新 widget tests**（`test/widget/features/conversation/new_conversation_screen_test.dart`）：
1. `partnerId arg passed in: created Conversation has matching partnerId`
2. `partnerId arg null (legacy entry): falls back to PartnerIdFactory.generateForExistingConversation`
3. `default name = "YYYY/MM/DD 新對話" when name field blank`

預估 ~120 行 test code。

### Task 11 — Screenshot flow auto-attach Partner

**現況**：截圖 flow 從 `NewConversationSheet` → `analysis_screen` → save。Phase 2 TF QA 項 3 已驗 partnerId 透傳 working。
**Task 11 真實 scope**：純補 widget tests + legacy fallback。

**新 widget tests**（`test/widget/features/conversation/screenshot_flow_partner_attach_test.dart`）：
1. `screenshot completion: created Conversation has matching partnerId from sheet args`
2. `legacy entry (partnerId null): screenshot completion auto-creates Partner via PartnerIdFactory`

預估 ~80 行 test code。

**若驗證中發現實際路徑沒 propagate partnerId**：升級為 production fix，仍走同 PR-A，plan r2 喊 Codex re-review。

---

## 5. PR-B 細節（Tasks 12+13）

### 共用基礎：`PartnerPickerSheet`

抽出為 `lib/features/partner/presentation/widgets/partner_picker_sheet.dart`：
- Props: `String? excludeId`（排除 self）, `void Function(Partner)? onSelected`, `bool showCreateNewAction = false`
- 內部：owner-scoped Partner list + `TextField` 即時 filter by name + `ListTile` per Partner
- Sort：reuse `partnerListProvider` 既有 sort（最近 active）

Task 12 用 `excludeId: <self>`, `showCreateNewAction: false`。
Task 13 用 `excludeId: <currentPartnerId>`, `showCreateNewAction: true`。

### Task 12 — Merge UI

**新增**：
- `lib/features/partner/presentation/screens/partner_merge_picker_screen.dart`（路由 `/partner/:id/merge`，`PartnerPickerSheet` + selected target → push confirm dialog）
- `lib/features/partner/presentation/dialogs/partner_merge_confirm_dialog.dart`（D 版內容）

**修改**：
- `partner_detail_screen.dart` ⋮ menu 第 1 項 `enabled: false → true`，`onSelected` 路由到 picker
- 同時更新該檔 line 10-12 的 stale comment（Phase 2 寫「Phase 4」現在是 Phase 3）

**Empty state**：當 `partnerListProvider`（exclude self 後）`.isEmpty` → ⋮ menu merge item 動態 disable + tooltip「需至少 2 個對象才能合併」。

**Confirm 後行為**：
1. `PartnerRepository.merge(from: A, to: B)`
2. `context.go('/partner/$toId')`（A detail 從 stack 拔掉）
3. Riverpod aggregate invalidation 由 repo 觸發（A1 已 tested）

### Task 13 — Conversation reassign

**修改**：
- `partner_conversation_tile.dart` trailing：`Icon(chevron_right)` → `PopupMenuButton<String>` items：
  - `[改派到其他對象]` enabled
  - `[刪除對話]` enabled: false（「即將推出」，Phase 4 留位）

**新增**：
- `lib/features/conversation/presentation/dialogs/conversation_reassign_picker.dart`（用 `PartnerPickerSheet` + `showCreateNewAction: true`）

**Reassign 完成行為**：
1. `ConversationRepository.save(updated, previousPartnerId: oldPartnerId)`（Task 3 contract，雙端 invalidate）
2. **不跳轉**——用戶仍在原 PartnerDetail，cell 從 list 消失（自然 visual feedback）

---

## 6. Test 策略

| 層級 | PR-A | PR-B |
|---|---|---|
| Unit | 0（`PartnerRepository.merge` A1 已 tested）| `PartnerPickerSheet` filter logic（pure） |
| Widget | 5 條 | 10+ 條（picker / confirm dialog / ⋮ menu enable / reassign tile / 雙端 invalidate / empty state / merged Partner navigation）|
| Integration | 0 | 0 |
| Manual TF QA | 1 項（partnerId 鏈端到端）| 4 項：merge 流程 / reassign 流程 / 同名 partner merge / merged Partner detail navigation |

**Hermetic widget test pattern**（Phase 2 已建好，繼續沿用）：
- temp Hive box 每 test setUp/tearDown
- `_HomeSentinel` sentinel router 不依賴 main router
- lifted-aggregate provider override（card 純 render，screen 做 per-row watch）

---

## 7. Risk register

| # | Risk | 緩解 |
|---|---|---|
| 1 | 🔴 Merge destructive 不可逆 | confirm dialog 紅字 + 雙重點擊（picker tap → confirm dialog → 確認）|
| 2 | 🟡 `PartnerPickerSheet` reuse 抽象不夠通用 | `excludeId: String?` + `onSelected` callback，不寫死 navigation |
| 3 | 🟡 Task 13 trigger 偏離 master plan | impl plan 明寫 deviation + 此 design doc 引用，Codex spec review 必須 explicit acknowledge |
| 4 | 🟡 Empty state 邊界 | `partnerListProvider.isEmpty(after exclude self)` 算對，detail screen 不寫死 `count > 1` |
| 5 | 🟢 Test infra known limit | `add_partner_screen_test.dart` "successful submit" 仍 skip:true（Windows hang，Phase 3 不戰）|

---

## 8. Rollout sequence

```
T0 ─► PR-A 開工
   ├─ 切 feature/partner-entity-A2-flows-data
   ├─ writing-plans → docs/plans/2026-04-27-partner-entity-A2-phase3-pr-a-impl.md
   ├─ Codex spec review (queue 開新 item — Phase 3-A)
   ├─ executing-plans
   ├─ Codex code review
   ├─ TF QA gate（1 項）
   ├─ PR → merge → branch 雙刪
   └─ Soak 1 天

T0+1 day ─► PR-B 開工
   ├─ pull main（含 PR-A）
   ├─ 切 feature/partner-entity-A2-flows-pickers
   ├─ writing-plans → docs/plans/2026-04-27-partner-entity-A2-phase3-pr-b-impl.md
   ├─ Codex spec review (queue 開新 item — Phase 3-B)
   ├─ executing-plans (PartnerPickerSheet → Task 12 → Task 13)
   ├─ Codex code review
   ├─ TF QA gate（4 項）
   └─ PR → merge → Phase 3 CLOSED

並行：
- PR #4 (CI build-number) 隨時可能 merge → Phase 3 branches 需要 rebase main，YAML vs Dart 0 conflict
- A2 Phase 1/2 TF soak 持續觀察
```

---

## 9. 禁區（Phase 3 期間）

- ❌ 不 reopen Phase 3 design decisions（D1-A / 4-stat dialog / ⋮ trigger）
- ❌ 不動 A1 schema / migration code
- ❌ 不動 A2 Phase 1 ConversationWriteController / PartnerSummaryBuilder
- ❌ 不動 A2 Phase 2 已 merged code 除非 Phase 3 測試發現 regression（regression 路徑：先標出來、再決定動）
- ❌ 不混 OCR 改動（baseline `28c0965`）+ partner UI 改動 commit
- ❌ Phase 3 execution 期間不修 plan（plan APPROVED 後 silently 偏離 = 失約；需要 patch plan 走 r2 喊 Codex re-review）
- ❌ 不嘗試 unskip `add_partner_screen_test.dart` "successful submit"（Windows kernel cache 已 falsified，要動先 migrate to `integration_test/`）

---

## 10. 後續

Phase 3 全 ship 後 → Phase 4（Tasks 14-17 — same-name banner + copy sweep + ship checklist），不在本 design 範圍。
