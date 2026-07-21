# 教練統一 Phase F：舊 engine 退場＋三小債收尾 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans（或 subagent-driven-development）task-by-task 執行。

**Goal:** 清償 Phase E Task 7 記下的三筆小債（latch 重置、telemetry 意圖事件改名、`openCoachInputOnFirstBuild` 改名），並刪除已零外部引用的舊 coach_follow_up engine 死叢集（7 檔＋LEGACY helper＋7 個對應測試檔）。

**Architecture:** 純客戶端收尾，不動 Edge/wire。`CoachFollowUpPhase` enum 值是 wire format（Hive 存檔字串 `CoachFollowUpResult.phase`＋server telemetry），**絕不改 enum 值**——改名債落在 telemetry 事件類別層。保留不刪：`coach_follow_up_result.dart`（＋.g.dart，Hive 模型，storage_service/coach_chat/hive_registrar 引用）、`coach_follow_up_repository.dart`＋`_impl.dart`（Phase D read-bridge，partner_repository 引用）、`coach_follow_up_phase.dart`（wire 解析）、`coach_follow_up_section.dart`（薄 wrapper，掛 CoachSurface）。

**Tech Stack:** Flutter/Riverpod；`flutter analyze`＋`flutter test`（WSL 下 dart format 壞，不跑 format）。

**明確不做（out of scope）：**
- durable requestId 持久化（Phase E Task 8 Codex R1 P2）＝獨立設計案，billing 相鄰，本包絕不碰。
- `CoachFollowUpPhase` enum 值改名（wire/Hive 相容性）。
- pubspec.lock 本地漂移絕不收進任何 commit。

---

### Task 1: latch 重置債 — `_didAutoFocusCoachInput` 在 partnerId 切換時重置

**Files:**
- Modify: `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart:78-85`（`didUpdateWidget`）
- Test: `test/widget/features/coach_follow_up/coach_follow_up_section_test.dart`

**背景**：閂鎖 `_didAutoFocusCoachInput`（section.dart:70）保證 auto-focus 只發一次，但 partnerId 原地切換時未重置——parent/orchestrator 兩層守衛已擋、真實 deep-link 走 push 新 route 打不到，此為第三層防禦一致性補強（Phase E Task 7 雙審記債第 1 項）。

**Step 1: 寫失敗測試**（加入 section_test.dart 既有 group；`_pump` helper 已支援 `openCoachInputOnFirstBuild` 參數，需擴充支援自訂 partnerId 與 rebuild）：

情境：`pump(partnerId: 'p1', openCoachInputOnFirstBuild: true)` → 首幀 auto-focus 發過（token=1，latch 鎖上）→ rebuild `(partnerId: 'p2', openCoachInputOnFirstBuild: false)` → rebuild `(partnerId: 'p2', openCoachInputOnFirstBuild: true)`（false→true transition）→ 斷言 focus token 再次遞增（=2）。未修時 latch 仍鎖 → token 不動 → FAIL。

斷言方式沿用該測試檔既有讀 token 的手法（找 CoachSurface widget 的 `focusRequestToken`）。

**Step 2: 跑測確認 FAIL**

Run: `flutter test test/widget/features/coach_follow_up/coach_follow_up_section_test.dart --concurrency=1`
Expected: 新測試 FAIL（token 未遞增），其餘綠。

**Step 3: 最小實作**——`didUpdateWidget` 開頭補：

```dart
if (widget.partnerId != oldWidget.partnerId) {
  _didAutoFocusCoachInput = false;
}
```

**Step 4: 跑測確認 PASS**（同 Step 2 指令，全綠）

**Step 5: Commit＋push**

```
教練統一 Phase F：partnerId 切換重置 auto-focus 閂鎖（Task7 記債1）
```

---

### Task 2: 改名債 — `openCoachInputOnFirstBuild` → `openCoachInputRequested`

**Files:**
- Modify: `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart`（:48 欄位、:57 建構子、:81-82、:90、相關註解 :87-88）
- Modify: `lib/features/partner/presentation/screens/partner_detail_screen.dart`（:284、:578 傳入點；:100-105、:915 註解同步改）
- Modify: `test/widget/features/coach_follow_up/coach_follow_up_section_test.dart`（:90、:121、:236、:238＋Task 1 新增的測試）

**背景**：參數名「OnFirstBuild」名不符實——主要路徑是中途 false→true transition（deep-link orchestrator 定位後才翻 flag）。改為 `openCoachInputRequested`，與 parent 欄位 `_openCoachInputRequested`（partner_detail_screen.dart:106）對齊（Phase E Task 7 雙審記債第 3 項）。

**Step 1: 全案 rename**（純機械，含註解裡的舊名）。`grep -rn "openCoachInputOnFirstBuild" lib test` 必須歸零。

**Step 2: 驗證**

Run: `flutter analyze lib/features/coach_follow_up lib/features/partner`（0 issues）
Run: `flutter test test/widget/features/coach_follow_up/ test/widget/features/partner/ --concurrency=1`（全綠）

**Step 3: Commit＋push**

```
教練統一 Phase F：openCoachInputOnFirstBuild 改名 openCoachInputRequested（Task7 記債3）
```

---

### Task 3: 改名債 — deep-link 意圖事件改為 `CoachOpenCoachIntentEvent`

**Files:**
- Modify: `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart:282-325`（telemetry sealed 家族）
- Modify: `lib/features/partner/presentation/screens/partner_detail_screen.dart`（:1027 emit 點、:1824-1840 一帶 stub sink switch）
- Test: `test/widget/features/partner/partner_detail_coach_focus_test.dart`（若有斷言舊事件/log 字串則同步改；先 grep 確認）

**背景**：`CoachFollowUpInvokedEvent(phase: openCoach)` 語意已從「實際觸發生成」前移為「deep-link 意圖」，接真 analytics（Phase X25）前應改名（Phase E Task 7 雙審記債第 2 項）。同時 `CoachFollowUpRegeneratedEvent`／`CoachFollowUpPhaseSwitchedEvent` 全 repo 零 emit 點（唯一 emit 是 partner_detail_screen.dart:1027 的 Invoked）＝舊 engine 殘骸，一併退場。

**Step 1: 改 sealed 家族**（section.dart 檔尾）：
- 新增 `class CoachOpenCoachIntentEvent extends CoachFollowUpTelemetryEvent`（無欄位——phase 恆 openCoach、hasOptionalText 恆 false，皆無資訊量；doc comment 註明「deep-link focusAction=openCoachInput 意圖時點記錄」）。
- 刪除 `CoachFollowUpInvokedEvent`、`CoachFollowUpRegeneratedEvent`、`CoachFollowUpPhaseSwitchedEvent` 三類。
- `CoachFollowUpTelemetryEvent` sealed base 與 section 的 `onTelemetry` 參數保留。

**Step 2: 改 emit 點＋stub sink**（partner_detail_screen.dart）：
- :1027 一帶改為 `_logCoachFollowUpTelemetry(const CoachOpenCoachIntentEvent());`，前方註解同步改。
- `_logCoachFollowUpTelemetry` 的 switch 收斂為單一 case，debugPrint 改 `'coach_open_coach_intent'`（stub 尚未接真 analytics，字串可改——這正是記債要求的「接真 analytics 前改名」）。

**Step 3: 驗證**

Run: `grep -rn "CoachFollowUpInvokedEvent\|CoachFollowUpRegeneratedEvent\|CoachFollowUpPhaseSwitchedEvent" lib test` → 歸零
Run: `flutter analyze lib/features/coach_follow_up lib/features/partner`（0 issues）
Run: `flutter test test/widget/features/coach_follow_up/ test/widget/features/partner/ --concurrency=1`（全綠）

**Step 4: Commit＋push**

```
教練統一 Phase F：deep-link 意圖事件改名 CoachOpenCoachIntentEvent＋刪零 emit 舊事件（Task7 記債2）
```

---

### Task 4: 舊 engine 死叢集刪除

**Files（Delete，lib 7 檔）：**
- `lib/features/coach_follow_up/data/providers/coach_follow_up_providers.dart`（死叢集 hub）
- `lib/features/coach_follow_up/data/services/coach_follow_up_api_service.dart`
- `lib/features/coach_follow_up/domain/services/coach_follow_up_hint_resolver.dart`
- `lib/features/coach_follow_up/domain/services/coach_follow_up_partner_hint_builder.dart`
- `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_input_sheet.dart`
- `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_chip_row.dart`
- `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_result_card.dart`

**Files（Delete，test 7 檔）：**
- `test/unit/features/coach_follow_up/data/providers/coach_follow_up_providers_test.dart`
- `test/unit/features/coach_follow_up/data/services/coach_follow_up_api_service_test.dart`
- `test/unit/features/coach_follow_up/domain/services/coach_follow_up_hint_resolver_test.dart`
- `test/unit/features/coach_follow_up/domain/services/coach_follow_up_partner_hint_builder_test.dart`
- `test/widget/features/coach_follow_up/coach_follow_up_input_sheet_test.dart`
- `test/widget/features/coach_follow_up/coach_follow_up_chip_row_test.dart`
- `test/widget/features/coach_follow_up/coach_follow_up_result_card_test.dart`

**Files（Modify）：**
- `lib/features/coach_follow_up/presentation/widgets/coach_follow_up_section.dart`：刪檔尾 LEGACY `showCoachFollowUpInputSheet`（:255-280）＋刪 `coach_follow_up_api_service.dart`／`coach_follow_up_input_sheet.dart` 兩個 import（:23、:25）；檔頭註解拿掉「凍結不刪（Phase F 退場）」敘述改為已退場事實。
- `test/widget/features/copy_sweep_snapshot_test.dart`：grep 到它引用死叢集檔名——先讀該引用段，移除對已刪 widget 的 import/字串條目後確認 snapshot 測試綠。

**依賴查證（已做，2026-07-22）**：repository_impl／repository 介面只 import result entity（不碰 api_service）；死叢集 7 檔互相引用、lib 其餘處零 import；`CoachFollowUpAnswers` 只剩 LEGACY helper 用（同刪）。保留 `coach_follow_up_phase.dart`（wire 解析＋section telemetry doc）、`coach_follow_up_result.dart`＋`.g.dart`、repository 兩檔、section。

**Step 1: 刪檔**（`git rm` 上列 14 檔）＋section.dart 兩處修改＋copy_sweep 修引用。

**Step 2: 驗證**

Run: `grep -rn "coach_follow_up_providers\|coach_follow_up_api_service\|hint_resolver\|partner_hint_builder\|coach_follow_up_chip_row\|coach_follow_up_result_card\|coach_follow_up_input_sheet\|showCoachFollowUpInputSheet\|CoachFollowUpAnswers" lib test` → 歸零
Run: `flutter analyze`（全 repo，0 issues）
Run: `flutter test --concurrency=1`（全套，基準 2332 綠，刪 7 測試檔後總數下降屬預期；`hive_registrar.g.dart` 不得因此重生變動）

**Step 3: Commit＋push**

```
教練統一 Phase F：刪除舊 coach_follow_up engine 死叢集（7 lib＋7 test 檔＋LEGACY helper）
```

---

### Task 5: docs 收尾＋Codex 審查

**Files:**
- Modify: `docs/snapshot.md`：教練統一段落補「Phase F 收尾包 SHIPPED（三小債清償＋舊 engine 死叢集刪除）；durable requestId 持久化仍為獨立案未做」；:43 既有已知債條目維持不動。
- Modify: `docs/plans/2026-07-22-coach-unification-phase-e-plan.md`：Task 7 記債區塊補一行「1–3 已於 Phase F 清償（見本計畫檔），4 維持獨立案」。

**Step 1: 改 docs＋commit＋push**

```
教練統一 Phase F：snapshot＋Phase E 計畫檔記債清償註記
```

**Step 2: Codex 審查**（中風險：coach 區死碼刪除＋rename，不碰 billing/wire——單審即可）：走 `codex:rescue` 送 Phase F 全部 commit range diff 審查，拿到 verdict 才宣稱 dogfood safe。有 P finding 依 receiving-code-review 紀律處理。

---

## 驗收總標準

1. `grep -rn "openCoachInputOnFirstBuild" lib test` 歸零；舊三 telemetry 事件類名歸零；死叢集檔名引用歸零。
2. `flutter analyze` 全 repo 0 issues；`flutter test --concurrency=1` 全綠。
3. `CoachFollowUpPhase` enum 值與 `coach_follow_up_result.dart` byte 未動（wire/Hive 相容）。
4. pubspec.lock 未進任何 commit。
5. Codex 審查 verdict 落檔 `docs/reviews/`。
