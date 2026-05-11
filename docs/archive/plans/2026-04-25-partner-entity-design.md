# Partner Entity Refactor — Design Doc

> **Date**: 2026-04-25（Revised 2026-04-25 18:05）
> **Status**: REVISED — Codex P1/P2 addressed, awaiting re-review
> **Owner**: Claude (design + revision) → Codex (spec re-review) → next session (implementation plan) → Claude (A1 ship) → Codex (A2 final code review)
> **Related ADR**: ADR-15 in `docs/decisions.md`
> **Live tracking**: `docs/reviews/ai-arbitration-queue.md`
> **Codex review v1**: `docs/reviews/2026-04-25_partner-entity-design_codex-review.md`

---

## Spec Revision Log

### v2 — 2026-04-25 18:05（response to Codex 🔴 critical review）

| # | Codex finding | 處置 | Sections |
|---|---|---|---|
| P1 | `Partner @HiveType(typeId: 5)` 衝突 `UserGoal` | 改 `typeId=8`（grep 驗證 0-7 全占用） | §1 |
| P1 | Migration 不 rerun-safe（fresh UUID + terminal flag） | 改 deterministic UUID v5 + per-convo marker（`partnerId` 欄位本身），SharedPreferences flag 降為 perf 優化 | §1, §5 |
| P2 | `200-400 token` 無硬 cap / ranking | 加 hard char cap 1500、ranking by `lastInteraction` desc、取 last N=8 | §3 |
| P2 | `auto invalidate on any Conversation change` 過粗 | 收窄到 `partnerAggregateProvider(partnerId)` only，寫 conversation 時只 invalidate 對應 partner | §3 |
| P2 | A1 1.5 天估算偏低 | 標 `TBD pending Codex re-review`，待重估 | §6 |

**未動**：brainstorm 五項決策（IA 2 層 / Migration B / Union / Hybrid / 報告 D）—— 屬已鎖定產品決策，不在本輪 spec 改動範圍。

---

## Background

VibeSync 目前 `Conversation` entity 只有 `name`（字串），**沒有 `partnerId`**。同一個對方（例：糖糖）若分兩次新對話建立 = 兩個獨立 Conversation，AI 抽出的興趣 / 性格 / 備註不會跨對話聚合。

Bruce 2026-04-25 測試期發現他的首頁有兩張「糖糖」卡（一張 95、一張 85），這正是現況的真實顯化：**同人不同段對話的特質碎裂**。

Eric 拍板 Phase A — 全面重構：架構應該以**對象**為單位，不是每次都開新對話。

---

## Brainstorm 決策（已鎖定，不要 reopen）

| 議題 | 決策 | 拍板者 / 時間 |
|---|---|---|
| 資訊架構 | 2 層（Home = Partner list → Partner detail with Conversation list + traits + add new）| Bruce 2026-04-25 09:07 |
| 既有資料 migration | **B**：每 Conversation = 獨立 Partner + 手動合併 UI | Bruce 2026-04-25 09:08 |
| 跨對話聚合 | **A Union**：traits 聯集去重 / heat=latest / counts=sum / last=max | Bruce 2026-04-25 09:10 |
| AI context | **C Hybrid**：當前對話完整訊息 + Partner 摘要塞 prompt | Bruce 2026-04-25 09:12 |
| 我的報告 tab | **D**：tab 不動；Partner 詳情頁加最新對話 5 維雷達摘要小卡 | Bruce 2026-04-25 09:17 |
| 排程 | **Phase A 完整 Big Bang**（內切 A1 schema 1.5 天 + A2 UI 7-8 天）| Eric 2026-04-25 09:35 |

---

## Section 1 — Data Model

新增 `Partner` Hive entity：

```dart
@HiveType(typeId: 8) // grep verified 2026-04-25: typeId 0-7 全占用
                    // (Conversation=0 / Message=1 / ConversationSummary=2 /
                    //  SessionContext=3 / MeetingContext=4 / UserGoal=5 /
                    //  AcquaintanceDuration=6 / UserStyle=7)
                    // 實作前必須再 grep 一次確認無新增佔用
class Partner extends HiveObject {
  @HiveField(0) final String id;        // deterministic UUID v5（migration） or random UUID（用戶手建新對象）
  @HiveField(1) String name;             // 用戶可改
  @HiveField(2) String? avatarPath;
  @HiveField(3) final DateTime createdAt;
  @HiveField(4) DateTime updatedAt;
  @HiveField(5) String? ownerUserId;     // 帳戶隔離
  @HiveField(6) String? customNote;      // 用戶 Partner-level 備註（新功能）
}
```

`Conversation` 加一個欄位（最小入侵）：
- `@HiveField(15) String? partnerId`（grep verified 2026-04-25：`Conversation` 既有欄位 0..14，adapter 寫 15 個 fields 結束於 14；field 15 free）
- 其餘欄位**全保留**（messages, summaries, lastEnthusiasmScore, sessionContext 等不動）

**Repository**:
- 新增 `PartnerRepository`：CRUD + `listByOwner(ownerUserId)` + `merge(a, b)`
- `ConversationRepository`：加 `byPartner(partnerId)` query
- 既有 ConversationRepository methods **全部保留**（漸進遷移期需要）

**Migration（idempotent + crash-safe）**:

設計核心：**marker 用 `conversation.partnerId` 欄位本身，正確性不依賴 SharedPreferences flag 的寫入時序**。Partner 用 deterministic UUID v5 derive from `conversation.id`，重跑同 conversation 收斂同 `partnerId`，不會重建。

```dart
// compile-time constant，永不更換（更換 = 破壞冪等保證）
const PARTNER_NAMESPACE_UUID =
    '6f6e8b5a-4f8b-4e3a-b1c4-2026042501a1';

Future<void> migrateConversationsToPartners() async {
  // 1. 首次備份（SharedPreferences 標記是否已備份；備份本身只做一次）
  if (!_prefs.getBool('partner_migration_v1_backup_done')) {
    await _backupConversationBox();
    await _prefs.setBool('partner_migration_v1_backup_done', true);
    _sentryEvent('partner_migration_backup_completed');
  }

  // 2. 逐筆 idempotent migration（per-convo marker = partnerId 欄位）
  for (final convo in conversationBox.values) {
    if (convo.partnerId != null) continue; // 已 migrate

    final partnerId = uuidV5(
      namespace: PARTNER_NAMESPACE_UUID,
      name: convo.id,
    ); // 同一 convo.id 每次都產生同一 partnerId

    if (!partnerBox.containsKey(partnerId)) {
      // 前次 partial run 未寫過 → 建立
      await partnerBox.put(partnerId, Partner(
        id: partnerId,
        name: convo.name,
        avatarPath: convo.avatarPath,
        createdAt: convo.createdAt,
        updatedAt: convo.updatedAt,
        ownerUserId: convo.ownerUserId,
      ));
    }
    // else：前次已寫，直接複用（idempotent）

    convo.partnerId = partnerId;
    try {
      await convo.save(); // sync 寫盤；crash 後 partnerId 已落地或全沒落地，不存在中間態
    } catch (e, st) {
      _sentryError('partner_migration_per_convo_failed',
          {'convoId': convo.id}, e, st);
      // 個別 convo 失敗不阻塞其他 convo（continue）
    }
  }

  // 3. 全跑完才寫 done flag（perf 優化：下次啟動跳過整個 loop）
  //    正確性已由 step 2 的 per-convo marker + deterministic UUID 保證
  await _prefs.setBool('partner_migration_v1_done', true);
  _sentryEvent('partner_migration_completed');
}
```

**Crash 場景（已驗證涵蓋）**:
| 場景 | 行為 |
|---|---|
| Migration loop 中途死掉 | 已寫 partnerId 的 convo 下次 skip；partial 寫入的 Partner 用 deterministic ID 不重複；未寫的 convo 下次 pick up |
| 切帳戶 | migration owner-scoped，每帳戶獨立 partnerId 命名空間（同一 namespace + 同一 convo.id 產出同一 partnerId，不論 ownerUserId） |
| OOM / force kill | Hive `convo.save()` sync 寫盤，partial state 限定在「已寫 partnerId vs 未寫」，無 in-memory 中間態 |
| 備份失敗 | `_backupConversationBox()` throw → flag 不寫 → 下次重跑備份；migration loop 不啟動（先確保備份） |

**啟動觸發**:
- `StorageService.initialize()` 開 `Partner` box 後，若 `_prefs.getBool('partner_migration_v1_done') != true` → call `migrateConversationsToPartners()`
- flag = true 時直接跳過 loop（perf 優化）
- 急救入口（設定 → 進階 → 重做升級）會清掉兩個 flag 強制重跑（仍 idempotent，不會 corrupt 資料）

**Sentry events**:
- `partner_migration_backup_completed` / `partner_migration_completed`
- `partner_migration_per_convo_failed`（含 convoId、error type）
- 觀察 TF 7 天 success rate（成功率 = `completed / (completed + per_convo_failed)`）

---

## Section 2 — UI Flow + 路由

**首頁（Partner list）**
- 三個 tab 不動（首頁 / 我的報告 / 學習專區）
- 主體：Conversation cards 改為 **Partner cards**（avatar / name / 「N 段對話」 / 最新熱度 badge / 最後活動時間）
- 排序 by `max(conversation.updatedAt)` across the partner's conversations
- Empty state：「還沒有對象，加一個開始」
- 底部 FAB「+ 新增對象」

**Partner 詳情頁**（新 screen，路徑 `/partner/:partnerId`）
- Header：avatar + name + ⋮ 選單（**合併到其他對象** / 編輯對象 / 刪除對象）
- 對方檔案卡（traits / 互動趨勢 — 走 Section 3 union 邏輯）
- 最新對話 5 維雷達摘要卡（從最新 Conversation 的 `lastAnalysisSnapshotJson` 解）
- 「對話 (N 段)」list（最新在上，每張卡：對話 name / 訊息數 / 最新熱度 / 最後活動）
- 底部「+ 新增對話」按鈕

**Conversation 內部（基本不變）**
- 既有 `analysis_screen` 不動（雷達 / 熱度 / 五種回覆 / 繼續對話 全保留）
- 唯一加：頂部 navbar 顯示「← 對象名 / 對話標題」讓用戶知道層級
- 「繼續對話」語意不變（同一段對話往下加訊息）

**新增對話 flow（從 Partner 詳情）**
- 點「+ 新增對話」→ 既有 `new_conversation_screen`，**partnerId 預先帶入**
- 對話 name 預設「2026/04/25 新對話」可改
- 手動輸入 / 截圖開始 / 開場救星 = 既有三選項不變

**新增對象 flow（從首頁）**
- FAB → 簡單表單：name + 可選 avatar
- 建立後直接跳 Partner 詳情頁，引導點「新增對話」
- 不一次塞兩步（避免 UX 過長）

**Routing 變動**
- 加 `/partner/:partnerId`
- 既有 `/conversation/:id` 保留向後相容（deep link / 分享連結仍可用，內部跳 Partner 詳情）

**邊界**
- 對話內按「← 返回」→ 跳 Partner 詳情（不是首頁）
- iOS swipe back 同上
- **開場救星 / 截圖 OCR 入口和邏輯完全不動（避開禁區）**

---

## Section 3 — 聚合邏輯 + Partner 摘要 spec

**Partner aggregates 全 derived**（不存在 entity 上以避免 stale）：

```dart
extension PartnerAggregates on Partner {
  List<String> get unionInterests   // 所有對話 interests 聯集去重
  List<String> get unionTraits      // 性格聯集
  String? get unionNotes            // 備註以換行串接保留時序
  int get latestHeat                // 最新對話 lastEnthusiasmScore
  int get totalRounds               // currentRound 加總
  int get totalMessages             // messages.length 加總
  DateTime get lastInteraction     // max(updatedAt)
}
```

**Riverpod invalidation 收窄**（response to Codex P2）:

不採「any conversation change → invalidate all partners」的 fan-out，改 narrow boundary：

- `partnerAggregateProvider(partnerId)` 只訂閱 `conversationsByPartnerProvider(partnerId)`（不訂閱全 conversation list）
- 寫 `Conversation` 時的 invalidation：先讀 `conversation.partnerId`，**只 invalidate 該 Partner 的 aggregate provider**，其他 Partner 不動
- 既有 home / analysis 等 widely-used invalidate path（見 Codex review L96-99 引用的 `analysis_screen.dart:495-514` 等）行為保留，但 Partner aggregate **不掛在它們的 fan-out 範圍內**
- 邊界：Conversation 改派 partner 時（Section 4 的反向操作），**舊 partnerId 與新 partnerId 兩邊都 invalidate**

**邊界**:
- 空 Partner（沒對話 / 剛建好 / 內部對話刪光）→ 全欄位 default（空 list / 0 / null）
- 特質超過 ~20 條 → 取最新 N 段對話的特質（避免 UI 過長，詳細 ranking 規則見下）

**Partner 摘要 for AI prompt — hard-bounded**

格式（純文字，client 即時組裝、不快取、不額外打 API）：

```
[對象背景：糖糖]
- 累計對話：5 段，68 則訊息，最後互動 3 天前
- 最近熱度：95
- 興趣：可愛貼圖、日韓料理、貓
- 性格：撒嬌、表達直接、晚上易累
- 你的備註：叫你北鼻、住永春附近
- 注意：以上是整體背景，當前對話內容仍以本次訊息為主
```

**生成時機**：每次「繼續對話」或「新對話首次分析」前，從 Hive 拼接資料塞進 prompt（即時，不快取）。

**Token 預算 + Truncation（hard-enforced，response to Codex P2）**:

| 規則 | 值 | 理由 |
|---|---|---|
| Summary 整體 char 上限 | **1500 chars (~400 tok)** | 對齊 `analyze-chat` 5000 char `CONTEXT_TOO_LONG` 守線，Partner summary 占比 ≤ 30% |
| `unionInterests` 取 | 最近 **N=8** 條 | 按 `lastInteraction` desc，從各 conversation extracted interests 抓最新 |
| `unionTraits` 取 | 最近 **N=8** 條 | 同上 |
| `unionNotes` 取 | 最近 **5** 條換行串接 | 早期備註壓進 `[older] ...` 摘要，避免無限長 |
| 對話數摘要 | 取 last **10** 段做 `totalRounds` / `totalMessages` 統計 | 30+ 段對話的 Partner，older 不進 prompt |
| 拼裝來源 | `Conversation.lastAnalysisSnapshotJson` 解出的精簡 fields（traits / interests / notes / heat） | **不灌 raw JSON**，避免 5000 char 守線一觸即發 |

**Pre-assembly safety check（client 端，組好 prompt 送出前）**:
1. `assert(summary.length <= 1500)`，超過時尾端硬截斷加 `... [truncated]`
2. 拼裝前驗證 `partner.ownerUserId == conversation.ownerUserId`，不一致回傳 empty summary（防呆）
3. 任何 `lastAnalysisSnapshotJson` parse 失敗（單筆）→ skip 該 conversation 不阻斷整體拼裝

**Worst-case（30 段對話 Partner）**:
- 取 last 10 段、每段最多吐 8 traits / 8 interests → 拼裝後 deduped union 仍受 N=8 上限約束
- 即使 user 手改 `customNote` 灌 1000 字，最後 hard truncate 到 1500
- Free Haiku tier：summary 占用 ~400 tok，剩 prompt budget 仍夠承載當前對話 messages

**邊界**:
- 第一段對話（Partner 只有這一段）→ 摘要僅一行「這是你跟此對象的第一次對話」（避免 AI 對空 trait 強解讀）
- Partner 沒名字 → 用「對象 #abc」placeholder（id 末 4 碼）
- 所有 conversation 都沒 analysis snapshot → 摘要回「這是你跟此對象的第一次分析，過去對話尚未產生分析摘要」

---

## Section 4 — 合併 UI + 邊界 case

**合併流程**

入口：Partner 詳情頁 ⋮ 選單「**合併到其他對象**」

1. Picker 列出該帳戶所有其他 Partner（搜尋 by name）
2. 選目標 → 確認對話框：
   ```
   合併「糖糖 (A)」→「糖糖 (B)」
   - A 的 8 段對話搬到 B
   - 特質聯集 → B 共 12 條
   - 互動累計 73 則
   - 保留 B 的 avatar / name
   ⚠ 合併後不可復原（但對話本身保留，可拆出來）
   ```
3. 執行：A 所有 Conversation 改 partnerId=B.id；customNote 串接進 B（"[from A] ..."）；刪 Partner A；Riverpod 自動重算 B aggregates

**反向操作**：對話卡長按 →「改派到其他對象」→ 選目標 Partner（或新建）。用於合併後悔 / 一開始誤合。

**邊界**:
1. **空 Partner**：預設留著（檔案備未來用）；用戶可從 ⋮「刪除對象」手動移除
2. **Migration 後同名一堆**（Bruce 兩張糖糖）：首頁一次性 banner「偵測到 N 組同名對象，要合併嗎？」用戶可關掉 banner 永久不再提
3. **帳戶切換**：Partner 跟 ownerUserId 隔離（沿用 Conversation 機制）
4. **未命名 Partner**：UI 顯示「未命名對象 #abc」（id 末 4 碼）；詳情頁 prompt「點此命名」
5. **雷達摘要卡資料源**：從最新 Conversation 的 `lastAnalysisSnapshotJson` 解 5 維；沒 snapshot → 顯示「最新對話尚未分析」
6. **Conversation 改派的特質一致性**：Conversation extracted traits 跟著走，兩邊 Partner 的 union 自動 invalidate 重算
7. **Partner 名字衝突**：不強制唯一（保留彈性），UI 用 last interaction date 區分

---

## Section 5 — 測試策略 + Migration 風險防護

**Unit tests（必補）**
- `Partner` Hive 序列化 round-trip
- `PartnerAggregates`：union 去重 / heat latest / sum / max date
- Migration logic：N Conversation → N Partner，partnerId 掛回正確
- Migration **idempotent + crash-safe**（response to Codex P1）:
  - 跑兩次：第二次 0 修改、partnerBox 規模不變、`conversation.partnerId` 不變
  - 中途中斷模擬：跑到一半 throw → 重跑能完成全部、最終結果與「一次跑完」位元級相同（compare partner box state + conversation.partnerId map）
  - 同一 `conversation.id` 兩次跑出的 `partnerId` 必相同（deterministic UUID v5 contract）
  - PARTNER_NAMESPACE_UUID 寫死：assert constant 不變（regression guard）
- Partner summary truncation（response to Codex P2）:
  - 30 段對話的 Partner → assemble 後 `summary.length <= 1500`
  - ranking 取最新 N=8 的順序穩定（時間 desc）
  - `partner.ownerUserId != conversation.ownerUserId` → empty summary
  - 單筆 `lastAnalysisSnapshotJson` parse fail → 該筆 skip 不影響整體
- Riverpod narrow invalidation:
  - 寫 conversation A（屬 Partner X）→ 只 `partnerAggregateProvider(X)` invalidate；其他 Partner provider 不動
  - 改派 conversation A 從 X 到 Y → X 與 Y 兩 provider 都 invalidate
- `PartnerRepository.merge(a, b)`：對話搬遷 + A 刪除 + aggregate 重算

**Widget tests**
- 首頁 Partner list：empty / 多 Partner / 排序
- Partner 詳情：有對話 / 空對話 / 同名 banner
- Merge UI：picker / confirm / success

**Integration test（最關鍵）**
- 模擬 Bruce 場景：4-5 既有 Conversation → migration → 4-5 個獨立 Partner
- **Crash-safe rerun**: 灌 10 個 Conversation → migration 跑到第 5 個 throw → 重啟跑完 → assert partnerBox 共 10 筆、無重複、所有 conversation.partnerId 正確且 deterministic
- **Backup 完整**: migration 完成後 backup box 內容 == migration 前的 conversation box（位元級比對）
- Partner with N conversations → aggregates 正確（含 N=30 worst case）
- Merge 流程：conversations 全 reassigned + 兩邊 aggregates 重算
- 帳戶切換隔離（多 owner migration 不互相污染）

**Manual TF regression**（更新 `docs/testflight-regression-checklist.md`）
- 升級既有資料無 crash
- Bruce 兩張糖糖看到合併 banner
- 跨對話分析 Partner summary 出現在 prompt（log 抽查）
- 帳戶切換不洩漏

**Migration 風險防護**:
1. **備份**：Migration 啟動前先備份 Conversation Hive box 為 `.partner_migration_backup`，保留 30 天；備份成功才啟動 loop（用獨立 SharedPreferences flag `partner_migration_v1_backup_done` 標記是否已備份）
2. **Idempotent core**：正確性由 deterministic UUID v5 + per-convo `partnerId` marker 保證；`partner_migration_v1_done` flag 只是 perf 優化（跳過 loop），**不是正確性 gate**
3. **Per-convo failure isolation**：個別 conversation 寫入失敗 → log Sentry + continue，不阻塞其他 convo（多次重啟仍能補完）
4. **typeId 防呆**：implementation 前再跑一次 `grep -rn 'typeId:' lib/` 驗證 Partner typeId=8 沒衝突、`Conversation.partnerId` 用 HiveField(15) 沒被新增佔用
5. **Sentry 監控**：events `partner_migration_backup_completed` / `partner_migration_completed` / `partner_migration_per_convo_failed`；觀察 TF 7 天 success rate
6. **急救機制**：用戶手動觸發「重做升級」入口（設定 → 進階）→ 清掉兩個 flag 強制重跑（idempotent，不會 corrupt 資料）

---

## Section 6 — 排程 / Phasing

> **2026-04-25 v2 修訂**：A1 工期 `1.5 天` 估算偏低（Codex P2 finding），暫標 `TBD`，待 Codex re-review 後重估。整體 9-10 天上限保留，但 A1/A2 內部分配以 re-review 後為準。

| 模組 | 天 |
|---|---|
| Schema + Migration（含 backup / Sentry / deterministic UUID + idempotent rerun + crash-safe tests）| **TBD** ⏳ |
| Repository + Provider + Aggregates（含 narrow invalidation） | 1.0 |
| 首頁 Partner list + 新增對象 form | 1.0 |
| Partner 詳情頁 + 編輯 + 雷達摘要卡 | 1.0 |
| AI prompt Partner 摘要整合（含 ranking + truncation + ownerUserId 防呆）| 0.5-0.8 |
| Merge UI | 0.5 |
| Conversation 改派 UI | 0.3 |
| Routing 變動 | 0.3 |
| Unit + Widget + Integration tests（idempotent rerun + crash-safe + narrow invalidation + summary truncation） | **TBD** ⏳（原 1.5 天偏低） |
| Manual TF regression + ADR + TF checklist | 0.5 |
| Buffer for 未知 | 1.5 |
| **合計** | **9-10 天上限保留，內部分配等 A1 重估** |

切兩個 sub-phase 限縮 blast radius：

### A1 — Schema + Migration（**工期 TBD pending Codex re-review**）

**範圍**（v2 擴充）：
- Partner Hive entity（typeId=8）+ .g.dart codegen
- Conversation 加 partnerId 欄位（HiveField(15)）
- Migration code:
  - PARTNER_NAMESPACE_UUID compile-time 常數
  - deterministic UUID v5 derive from `conversation.id`
  - per-convo `partnerId` marker 為 idempotency 來源
  - 備份 + Sentry events (`backup_completed` / `completed` / `per_convo_failed`)
  - perf flag（`partner_migration_v1_done`）只跳 loop，不擔正確性
- typeId 衝突 assert（implementation 前 re-grep）
- 急救入口（設定 → 進階 → 重做升級）清 flag 流程
- Migration 相關 unit tests:
  - 跑兩次無 diff（idempotent contract）
  - 中途 throw + 重跑 = 全跑（crash-safe contract）
  - PARTNER_NAMESPACE_UUID 常數 regression guard
  - deterministic UUID v5 同 input 同 output
- 1 個 integration test（Bruce 4-5 個 Conversation → migration → 4-5 個獨立 Partner，含 crash-safe 變體）

**A1 不動 UI**——首頁仍走舊 Conversation list flow。Partner UI 在 A2 才打開。

**A1 ship 後**：TF build 給 Bruce + Eric + 測試帳號跑，**驗證 1-2 天**，確認 migration 成功、無 crash、Hive box 完整、Sentry success rate > 99%、急救入口可正常重跑。

### A2 — UI + AI summary + Merge UI（~7-8 天，A1 穩定後做）

**範圍**：
- 首頁改 Partner list
- Partner 詳情頁
- AI prompt Partner 摘要注入
- Merge UI + Conversation 改派
- Routing 變動
- 完整 widget + integration tests
- TF regression checklist 更新

**A2 結束** → Codex code review + 邊界補強（按昨晚 closeout matrix 規則）

### 送審影響

**現況**：CLAUDE.md「送審前最後穩定化，不做大功能擴張」。Path B = 大功能擴張，**直接 ship 會延 ~2 週送審**。

反面：上線後修 data model = 真實用戶資料受影響、修補成本 10×。Bruce 此刻測試抓出來 = 最佳修補時機。

**Eric 拍板**：值得延。

---

## Codex Spec Review Request

> **v1 review 結果**：🔴 Critical flaw（`docs/reviews/2026-04-25_partner-entity-design_codex-review.md`）。
>
> **v2 修訂處置**：見頂部「Spec Revision Log」。本段保留 v1 七項盲區並標註 v2 處置狀態，方便 re-review 對照。

| # | v1 盲區 | v1 verdict | v2 處置 |
|---|---|---|---|
| 1 | Hive `typeId=5` 是否衝突 | 🔴 P1 collision with `UserGoal` | ✅ 改 `typeId=8`（grep verified）+ implementation 前再 grep |
| 2 | `Conversation @HiveField(15)` 是否被佔用 | 🟢 free | ✅ unchanged |
| 3 | Migration race / crash-safe | 🔴 P1 not rerun-safe | ✅ deterministic UUID v5 + per-convo marker，正確性與 flag 解耦 |
| 4 | Riverpod auto-invalidate fan-out | 🟠 P2 too coarse | ✅ 收窄到 `partnerAggregateProvider(partnerId)` only |
| 5 | Partner summary token worst-case | 🟠 P2 no hard cap | ✅ char cap 1500 + ranking N=8 + assembly source 規則 |
| 6 | 9-10 天估算 sanity check | 🟠 P2 A1 1.5 天偏低 | ⏳ A1 estimate 標 `TBD`，待 re-review 重估 |
| 7 | Test coverage gap | 🟠 implicit | ✅ 加 idempotent rerun / crash-safe / narrow invalidation / summary truncation 測試 |

**v2 re-review 範圍**:
- 上表 v2 處置是否真正 close 各項 finding
- §1 deterministic UUID v5 + per-convo marker 演算法 crash 場景表是否還有漏網
- §3 truncation 規則（N=8 / cap=1500）是否合理且能涵蓋 Free Haiku tier worst case
- §5 新增測試是否足以證明 idempotent + crash-safe contract
- §6 A1 工期 TBD 之外，是否有其他子項估算需要調整

**Verdict 寫法（按昨晚協作協議）**:
- 🟢 **PASS** → queue item Status: APPROVED → 開新 Claude session 寫 A1 implementation plan
- 🟠 **architectural alternative** → 只寫不動，標 `Verdict: Daisy-Decision-Needed`
- 🔴 **Critical flaw** → 在既有 `docs/reviews/2026-04-25_partner-entity-design_codex-review.md` 補 v2 段（不開新檔），spec 再修完才 ship

---

## 後續 Session 開場語

### 新 Claude session 寫 A1 implementation plan

> 先讀 `CLAUDE.md` → `docs/shared-agent-rules.md` → `docs/reviews/ai-arbitration-queue.md` 的 live item「Partner Entity Refactor — Design Spec Review」→ 該 item 指向的 `docs/plans/2026-04-25-partner-entity-design.md` 與 ADR-15。讀完後使用 `superpowers:writing-plans` skill 寫 **A1 phase only** 的 implementation plan（不要寫 A2，A1 ship 穩定後才開新 session 寫 A2）。

### Codex spec review session

> 先讀 `AGENTS.md` → `docs/shared-agent-rules.md` → `docs/reviews/ai-arbitration-queue.md` 的 live item → `docs/plans/2026-04-25-partner-entity-design.md`。執行 spec review，重點盲區見 design doc 末尾「Codex Spec Review Request」段。Verdict 寫進 queue item Codex-Position 欄；若有 🔴 issue 則開 `docs/reviews/2026-04-25_partner-entity-design_codex-review.md`。

---

## 影響 / 取代既有計畫

- **取代** `memory/reference_testing_phase_feature_queue.md` Item #2「分析頁 escape hatch button」——Partner 架構直接解決 Bruce 原本痛點，escape hatch 不需要額外做
- **生效** Phase A 期間 VibeSync 不再「送審前最後穩定化」階段，CLAUDE.md 的「送審前不做大功能擴張」**暫時 paused**（Phase A 結束後恢復）
