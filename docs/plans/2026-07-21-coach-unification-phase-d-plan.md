# 教練統一 Phase D — 本機紀錄合成一套 實作計畫

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans（或 subagent-driven-development）逐 Task 執行本計畫。

**Goal:** 新增 `UnifiedCoachResult`（Hive typeId 26）統一本機教練紀錄；新寫入只進 unified box，legacy typeId-16/17 box 唯讀、讀取時即時合併（不搬不刪）；repository 泛化為 scope-keyed 並保留 keep=10 trim/rollup；`clearAll` 與 per-scope 刪除必清 unified box（防跨用戶外洩）。

**Architecture:** read-bridge 三 model 並存（D-5 拍板）。`CoachChatRepositoryImpl` 泛化為 scope-keyed unified 儲存核心＋合併讀取：conversation scope＝unified ⊕ typeId-17 by conversationId；partner scope＝unified ⊕ typeId-16 `get(partnerId)`（observation→userState/answer、task→nextStep、phase→lifecyclePhase）；依 id 去重（unified 優先）、generatedAt 降序。既有 `CoachChatRepository` 介面保留，內部改走 unified，Phase E 前 UI 零改動。

**Tech Stack:** Flutter/Hive（AES cipher）、Riverpod、`flutter test --concurrency=1`。

**設計檔真相源:** `docs/plans/2026-07-21-coach-unification-design.md` §Phase D（line 86-90）、Invariant #7/#8（line 53-54）、F11（line 67）、D-5/D-6 拍板（line 107-108）。

**鐵律（動碼前重申）:**
- Invariant #7：read-bridge 永不刪改 legacy typeId-16/17 內容；但 `clearAll()` 與刪對話/刪對象**必須**清對應 unified rows。
- Invariant #8：unified 儲存只存卡片欄位形狀，不新增任何來源訊息/prompt 欄位。
- D-6：legacy follow-up 卡映射進 unified 視圖時 `costDeducted` 用中性 sentinel `0`。
- 絕不 `git add pubspec.lock`。一 commit 一 concern、繁中 message、完成即 push。
- Phase D 屬高風險（Hive／換用戶清庫）→ Codex APPROVED 才可稱 dogfood safe。

**既有程式碼地標（2026-07-21 盤點）:**
- `CoachChatResult` typeId 17，HiveField 0-24：`lib/features/coach_chat/domain/entities/coach_chat_result.dart:11`
- `CoachFollowUpResult` typeId 16，HiveField 0-8（partnerId/phase/headline/observation/task/suggestedLine/boundaryReminder/generatedAt/modelUsed；**無 id、無 costDeducted**）：`lib/features/coach_follow_up/domain/entities/coach_follow_up_result.dart:25`
- adapter 註冊與開 box 全在 `lib/core/services/storage_service.dart:33-121`；typeId 24/25 已被 AnalysisHistory 佔用，**26 空閒**；`clearAll()` 在 line 211-222
- `CoachChatRepositoryImpl`（key=result.id、keep=10 trim `_trimConversation` line 50-57、rollup `_rollupStaleResults` line 59-87、carry-forward line 35-48）：`lib/features/coach_chat/data/repositories/coach_chat_repository_impl.dart`
- `CoachFollowUpRepositoryImpl`（key=partnerId latest-only）：`lib/features/coach_follow_up/data/repositories/coach_follow_up_repository_impl.dart`
- 刪對話清 coach_chat rows：`lib/features/conversation/data/repositories/conversation_repository.dart:191-198`
- 刪對象/合併清 follow-up：`lib/features/partner/data/repositories/partner_repository.dart:138-141, 177-182`
- providers：`lib/features/coach_chat/data/providers/coach_chat_providers.dart:17`、`lib/features/coach_follow_up/data/providers/coach_follow_up_providers.dart:41`
- 既有測試：`test/unit/features/coach_chat/data/repositories/coach_chat_repository_impl_test.dart`、`test/unit/features/coach_follow_up/data/repositories/coach_follow_up_repository_impl_test.dart`、`test/unit/services/storage_service_clear_all_test.dart`

---

### Task 1: `UnifiedCoachResult` entity（typeId 26）＋adapter

**Files:**
- Create: `lib/features/coach_chat/domain/entities/unified_coach_result.dart`
- Generate: `lib/features/coach_chat/domain/entities/unified_coach_result.g.dart`
- Test: `test/unit/features/coach_chat/domain/entities/unified_coach_result_test.dart`

**Step 1: 寫 entity。** 鏡像 `CoachChatResult` 全部 25 欄（**同名同 HiveField 編號 0-24**，唯 `conversationId` 改 `String?`——partner scope 無對話），新增：

```dart
@HiveField(25)
final String scopeType; // 'conversation' | 'partner'

@HiveField(26)
final String scopeId;

@HiveField(27)
final String? lifecyclePhase;
```

class 註解標明：typeId 26；scopeType/scopeId 必填；`scopeType=='conversation'` 時 `scopeId==conversationId`、`=='partner'` 時 `scopeId==partnerId`。加 `isClarifyingQuestion`/`isCoachAnswer` getter 與 `copyWith`（至少涵蓋 `earlierSummary`/`earlierResultCount`，與 CoachChatResult 對齊）。預設值照舊：`responseType='coachAnswer'`、`costDeducted=1`、`frictionType='unclearIntent'`、`earlierResultCount=0`。

**Step 2: 產 adapter**

Run: `flutter pub run build_runner build --delete-conflicting-outputs`
Expected: `unified_coach_result.g.dart` 生成、typeId 26。

**Step 3: 寫 round-trip 測試**（Hive.init temp dir → registerAdapter → 開 box 寫讀一筆全欄位、含 null 欄位）。

Run: `flutter test --no-pub test/unit/features/coach_chat/domain/entities/unified_coach_result_test.dart`
Expected: PASS

**Step 4: Commit**：`教練統一 Phase D：UnifiedCoachResult typeId 26 entity＋adapter`（**勿加 pubspec.lock**）

### Task 2: legacy→unified 映射 helpers

**Files:**
- Modify: `lib/features/coach_chat/domain/entities/unified_coach_result.dart`（加 factory）
- Test: 同 Task 1 測試檔追加 group

**Step 1: 寫失敗測試**：
- `fromCoachChatResult` 保留全欄位、`scopeType='conversation'`、`scopeId=conversationId`、`lifecyclePhase=null`
- `fromFollowUpResult` 映射：`observation→userState` **且** `→answer`、`task→nextStep`、`phase→lifecyclePhase`、`headline/suggestedLine/boundaryReminder/generatedAt/modelUsed` 直傳、`scopeType='partner'`、`scopeId=partnerId`、`id='legacy-followup-<partnerId>'`（latest-only，穩定合成鍵）、`costDeducted=0`（D-6 sentinel）、`question=''`、`mode='partnerFollowUp'`、`provider='legacy'`、`needsReflection=false`

**Step 2: Run 確認 FAIL（factory 未定義）→ Step 3: 實作兩個 factory → Step 4: Run PASS → Step 5: Commit**：`教練統一 Phase D：legacy 16/17→unified 映射（D-6 costDeducted sentinel 0）`

### Task 3: StorageService 接線（註冊、開 box、clearAll）

**Files:**
- Modify: `lib/core/services/storage_service.dart`（`initialize()` line 33-121、`clearAll()` line 211-222）
- Test: `test/unit/services/storage_service_clear_all_test.dart` 追加 spec

**Step 1: 寫失敗測試**：`clearAll() purges unified_coach_results box`（比照既有 Spec 5/6A 寫法）。
**Step 2: 實作**：
- `initialize()`：`Hive.registerAdapter(UnifiedCoachResultAdapter())`（照周邊 idiom）；開 box `'unified_coach_results'` 用**同一** `HiveAesCipher(encryptionKey)`（與 line 89-96 兩個 coach box 相同寫法）
- 加 static getter `unifiedCoachResultsBox`
- `clearAll()` 加 `await unifiedCoachResultsBox.clear();`（**F11——防跨用戶外洩的最高後果一行**，放 coach 兩行旁 line 216-217 之後）

**Step 3: Run PASS → Step 4: Commit**：`教練統一 Phase D：unified box 開箱＋clearAll 清庫（F11 防跨用戶外洩）`

### Task 4: repository 泛化——scope-keyed unified 儲存核心

**Files:**
- Modify: `lib/features/coach_chat/domain/repositories/coach_chat_repository.dart`（加 scope-keyed 介面）
- Modify: `lib/features/coach_chat/data/repositories/coach_chat_repository_impl.dart`
- Test: `test/unit/features/coach_chat/data/repositories/coach_chat_repository_impl_test.dart`

**Step 1: 介面**。`CoachChatRepository` 追加（或並列新 abstract）：

```dart
List<UnifiedCoachResult> listByScope(String scopeType, String scopeId);
UnifiedCoachResult? latestForScope(String scopeType, String scopeId);
Future<void> putUnified(UnifiedCoachResult result);
Future<void> deleteScope(String scopeType, String scopeId);
```

**Step 2: 建構子改** `CoachChatRepositoryImpl(this._unifiedBox, this._legacyChatBox, this._legacyFollowUpBox, {this.keepPerScope = 10})`。

**Step 3: TDD 泛化 trim/rollup**（先寫失敗測試再實作，逐條 Run）：
- `putUnified` 寫 unified box（key=`result.id`）、**legacy 兩 box 零寫入**（測試斷言 legacy box `isEmpty` 不變）
- 同 scope 超過 10 筆 → trim 至 10（只動 unified box）
- trim 前 rollup：stale 摘要進該 scope 最新一筆 `earlierSummary`（`_summarizeResult`/`_truncateSummary` 900 字/`_dedupeLines` 邏輯直接搬用，改吃 `UnifiedCoachResult`）
- carry-forward：新最新筆接手前筆 summary（沿 `_carryForwardRollup` 邏輯）
- `deleteScope` 只刪 unified box 該 scope rows；**不觸 legacy**
- partner scope 走同一套 trim/rollup（keep=10；legacy follow-up latest-only 不在此列）

**Step 4: 全檔 Run PASS → Step 5: Commit**：`教練統一 Phase D：repository 泛化 scope-keyed＋trim/rollup 搬 unified box`

### Task 5: read-bridge 合併讀取（唯讀、去重、排序）

**Files:**
- Modify: `lib/features/coach_chat/data/repositories/coach_chat_repository_impl.dart`
- Test: 同 Task 4 測試檔追加 group

**Step 1: 寫失敗測試**：
- conversation scope：unified 2 筆＋legacy-17 同 conversationId 2 筆 → `listByScope` 回 4 筆合併、generatedAt 降序
- id 撞號（同 id 同存兩 box）→ 只回 unified 那筆（unified 優先）
- partner scope：unified 1 筆＋legacy-16 `get(partnerId)` 1 筆 → 2 筆，legacy 筆映射欄位正確（userState==answer==observation、nextStep==task、lifecyclePhase==phase、costDeducted==0）
- 其他 conversation/partner 的 rows 不滲漏
- 合併讀取後 legacy 兩 box 內容 byte 不變（Invariant #7）

**Step 2: 實作** `listByScope`：unified filter by scope ⊕ legacy 來源（conversation→legacy-17 filter `conversationId`；partner→legacy-16 `get(partnerId)` 經 `fromFollowUpResult`）→ Map by id（unified 後蓋 legacy）→ sort desc。`latestForScope`=first。

**Step 3: Run PASS → Step 4: Commit**：`教練統一 Phase D：read-bridge 合併 legacy 16/17（唯讀、id 去重 unified 優先）`

### Task 6: 舊介面走 unified（Phase E 前 UI 零改動）

**Files:**
- Modify: `lib/features/coach_chat/data/repositories/coach_chat_repository_impl.dart`
- Modify: `lib/features/coach_chat/data/providers/coach_chat_providers.dart:17`
- Test: 既有測試檔改造

**Step 1: 舊方法改導**：
- `put(CoachChatResult r)` → `putUnified(UnifiedCoachResult.fromCoachChatResult(r))`（**新寫入只進 unified box**）
- `listByConversation(id)` → `listByScope('conversation', id)` 映回 `CoachChatResult` 視圖（欄位 1:1 反映射；unified 專屬欄位丟棄）
- `latestForConversation`、`deleteConversation`（=`deleteScope('conversation', id)`）、`clearAll`（清 unified box；**不清 legacy**——legacy 清理只歸 StorageService.clearAll 與既有刪除路徑管）同理
**Step 2: providers.dart:17 改建構**：`CoachChatRepositoryImpl(StorageService.unifiedCoachResultsBox, StorageService.coachChatResultsBox, StorageService.coachFollowUpResultsBox)`
**Step 3: 既有 6 條測試改造**：建構子改三 box；`put` 系列斷言改「寫進 unified、legacy 不動」；行為語意（trim 10/rollup/carry-forward/deleteConversation 只刪該對話/clearAll 全清）**全數保留**＝「rollup 與今日對等」驗收
**Step 4: Run 全檔 PASS → Step 5: Commit**：`教練統一 Phase D：舊 CoachChatRepository 介面導入 unified 寫讀`

### Task 7: 刪對話清 unified rows

**Files:**
- Modify: `lib/features/conversation/data/repositories/conversation_repository.dart:191-198`
- Test: 該 repo 既有測試檔追加 case（無則建 `test/unit/features/conversation/.../conversation_repository_coach_cleanup_test.dart`）

**Step 1: 失敗測試**：deleteConversation 後 unified box 中該 conversation scope rows 清空、其他 conversation 與 partner scope rows 保留、legacy-17 既有清理行為不變。
**Step 2: 實作**：比照 line 191-198 `Hive.isBoxOpen` 守門寫法，追加 `unified_coach_results` 清理（filter `scopeType=='conversation' && scopeId==id`）。
**Step 3: Run PASS → Step 4: Commit**：`教練統一 Phase D：刪對話同步清 unified conversation rows`

### Task 8: 刪對象／合併對象清 unified rows

**Files:**
- Modify: `lib/features/partner/data/repositories/partner_repository.dart:138-141, 177-182`
- Test: partner_repository 既有測試檔追加 case

**Step 1: 失敗測試**：`deletePartner` 後 unified partner-scope rows 清空；merge 路徑 `fromId` 的 partner-scope rows 也清（比照 follow-up `delete(fromId)`）；legacy-16 行為不變。
**Step 2: 實作**：兩處呼叫點旁加 unified 清理（`Hive.isBoxOpen` 守門，同 Task 7 pattern）。
**Step 3: Run PASS → Step 4: Commit**：`教練統一 Phase D：刪對象/合併同步清 unified partner rows`

### Task 9: 換用戶零殘留（F11）＋全套驗證

**Files:**
- Test: `test/unit/services/storage_service_clear_all_test.dart` 追加整合 spec

**Step 1: 失敗測試**：模擬用戶 A 寫入 unified（雙 scope）＋legacy 兩 box → `clearAll()` → 三 box 全空（含 unified）＝新用戶零殘留。
**Step 2: Run PASS。**
**Step 3: 全套驗證**：

```bash
flutter analyze          # Expected: 0 issues
flutter test --concurrency=1   # Expected: 全綠
```

**Step 4: Commit**：`教練統一 Phase D：F11 換用戶零殘留整合測試`＋push 全部 commits。

### Task 10: Codex 對抗式審查（高風險 gate）

- base ref：Phase D 起點 commit（本計畫 commit）。
- 檔案清單：Task 1-9 全部改檔。
- 高風險焦點（設計檔 §7）：**clearAll 跨用戶外洩、read-bridge 去重映射**；另請 Codex 核 trim/rollup 對等性與 legacy 唯讀不變式。
- 佐證：`flutter analyze` 0 issue＋`flutter test --concurrency=1` 全綠輸出隨包附。
- 直呼 `codex:rescue`（拍板 2026-07-02：CC 直呼不出 packet）；**拿到 APPROVED verdict 前絕不宣稱 dogfood safe**；有 finding 照 High-Risk Patch Stop Rule 最多兩輪修。

---

**驗收總表（對照設計檔 line 90）：**
- [ ] 合併/去重/排序 unit 測（Task 5）
- [ ] rollup 與今日對等（Task 4/6）
- [ ] clearAll 清 unified（Task 3）
- [ ] 換用戶零殘留（Task 9）
- [ ] 刪對象/刪對話清對應 unified rows（Task 7/8）
- [ ] Codex APPROVED（Task 10）
