# Partner Entity Refactor — Design Doc

> **Date**: 2026-04-25
> **Status**: PROPOSED — pending Codex spec review
> **Owner**: Claude (design) → Codex (spec review) → next session (implementation plan) → Claude (A1 ship) → Codex (A2 final code review)
> **Related ADR**: ADR-15 in `docs/decisions.md`
> **Live tracking**: `docs/reviews/ai-arbitration-queue.md`

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
@HiveType(typeId: 5) // 跑前 grep -rn 'typeId:' 確認無衝突
class Partner extends HiveObject {
  @HiveField(0) final String id;        // UUID
  @HiveField(1) String name;             // 用戶可改
  @HiveField(2) String? avatarPath;
  @HiveField(3) final DateTime createdAt;
  @HiveField(4) DateTime updatedAt;
  @HiveField(5) String? ownerUserId;     // 帳戶隔離
  @HiveField(6) String? customNote;      // 用戶 Partner-level 備註（新功能）
}
```

`Conversation` 加一個欄位（最小入侵）：
- `@HiveField(15) String? partnerId`（跑前 grep `@HiveField(15)` 確認無舊版佔用）
- 其餘欄位**全保留**（messages, summaries, lastEnthusiasmScore, sessionContext 等不動）

**Repository**:
- 新增 `PartnerRepository`：CRUD + `listByOwner(ownerUserId)` + `merge(a, b)`
- `ConversationRepository`：加 `byPartner(partnerId)` query
- 既有 ConversationRepository methods **全部保留**（漸進遷移期需要）

**Migration（一次性）**:
1. App 啟動偵測 SharedPreferences flag `partner_migration_v1_done` 未設
2. **備份**：複製 Conversation Hive box 為 `<box>.partner_migration_backup`（保留 30 天）
3. 開 Conversation box 逐筆建立對應 Partner（id=uuid, name=convo.name, avatarPath=convo.avatarPath, ownerUserId=convo.ownerUserId）
4. 寫回 `conversation.partnerId`
5. Flag 寫進 SharedPreferences 防重跑
6. 失敗 → 不寫 flag、log Sentry、跳一次性 toast「升級遇到問題」、Repository 維持讀舊 flow（**App 仍可用**）

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

由 Riverpod `Provider.family<Partner, String>` 包裝，任何 Conversation 改動自動 invalidate。

**邊界**:
- 空 Partner（沒對話 / 剛建好 / 內部對話刪光）→ 全欄位 default（空 list / 0 / null）
- 特質超過 ~20 條 → 取最新 N 段對話的特質（避免 UI 過長）

**Partner 摘要 for AI prompt（~200-400 token）**

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

**Token 預算**：摘要 200-400 token；現有 prompt 加這個增量對 Sonnet/Haiku 都可忽略。**Codex 待驗證 worst-case（30 段對話的 Partner）**。

**邊界**:
- 第一段對話（Partner 只有這一段）→ 摘要僅一行「這是你跟此對象的第一次對話」（避免 AI 對空 trait 強解讀）
- Partner 沒名字 → 用「對象 #abc」placeholder（id 末 4 碼）
- 組裝前檢查 partner / conversation 的 ownerUserId 一致（防呆）

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
- Migration **idempotent**：跑兩次不重複建（flag 守住）
- `PartnerRepository.merge(a, b)`：對話搬遷 + A 刪除 + aggregate 重算

**Widget tests**
- 首頁 Partner list：empty / 多 Partner / 排序
- Partner 詳情：有對話 / 空對話 / 同名 banner
- Merge UI：picker / confirm / success

**Integration test（最關鍵）**
- 模擬 Bruce 場景：4-5 既有 Conversation → migration → 4-5 個獨立 Partner
- Partner with N conversations → aggregates 正確
- Merge 流程：conversations 全 reassigned + 兩邊 aggregates 重算
- 帳戶切換隔離

**Manual TF regression**（更新 `docs/testflight-regression-checklist.md`）
- 升級既有資料無 crash
- Bruce 兩張糖糖看到合併 banner
- 跨對話分析 Partner summary 出現在 prompt（log 抽查）
- 帳戶切換不洩漏

**Migration 風險防護**:
1. **備份**：Migration 前複製 Hive box 為 `.partner_migration_backup`，保留 30 天
2. **Flag 守住**：SharedPreferences `partner_migration_v1_done` 防重跑；try/catch 失敗不寫 flag → 下次重試
3. **Graceful fallback**：失敗不寫 flag、不破壞資料、Sentry log error、App 啟動跳 toast「升級遇到問題」、Repository 維持讀舊 Conversation flow → **App 仍可用**
4. **typeId 防呆**：跑前 assert Partner typeId 沒衝突、`Conversation.partnerId` 用 HiveField(15) 沒被舊版佔用
5. **Sentry 監控**：新增 events `partner_migration_started/completed/failed`；觀察 TF 7 天 success rate
6. **急救機制**：用戶手動觸發「重做升級」入口（設定 → 進階）讓 support team 引導用

---

## Section 6 — 排程 / Phasing

**完整工程量：~9-10 工作天**（含 buffer）

| 模組 | 天 |
|---|---|
| Schema + Migration（含 backup / Sentry / typeId 驗證）| 1.5 |
| Repository + Provider + Aggregates | 1.0 |
| 首頁 Partner list + 新增對象 form | 1.0 |
| Partner 詳情頁 + 編輯 + 雷達摘要卡 | 1.0 |
| AI prompt Partner 摘要整合 | 0.5 |
| Merge UI | 0.5 |
| Conversation 改派 UI | 0.3 |
| Routing 變動 | 0.3 |
| Unit + Widget + Integration tests | 1.5 |
| Manual TF regression + ADR + TF checklist | 0.5 |
| Buffer for 未知 | 1.5 |
| **合計** | **9-10 天** |

切兩個 sub-phase 限縮 blast radius：

### A1 — Schema + Migration（~1.5 天，先 ship、最小 blast radius）

**範圍**：
- Partner Hive entity + .g.dart codegen
- Conversation 加 partnerId 欄位
- Migration code（含 backup + flag + Sentry events）
- typeId 衝突 assert
- Migration 相關 unit tests + 1 個 integration test（Bruce 4-5 個 Conversation → Partner）

**A1 不動 UI**——首頁仍走舊 Conversation list flow。Partner UI 在 A2 才打開。

**A1 ship 後**：TF build 給 Bruce + Eric + 測試帳號跑，**驗證 1-2 天**，確認 migration 成功、無 crash、Hive box 完整、Sentry success rate > 99%。

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

**範圍**：本檔完整 design（特別 Section 1 / Section 3 / Section 5 / Section 6）

**重點盲區（請優先掃）**:
1. Hive `typeId=5` 全 repo 真沒衝突？(`grep -rn 'typeId:' lib/`)
2. Conversation `@HiveField(15)` 真沒被舊版佔用？
3. Migration race conditions（強關 App / 切帳戶 / OOM）graceful 是否真 graceful
4. Riverpod auto-invalidate 鏈會不會 thrash UI（每次 Conversation 改動 N 個 Partner provider invalidate？）
5. Partner summary token worst-case（30 段對話的對象）會不會爆 prompt（**Free Haiku tier 特別注意**）
6. 9-10 天估算 sanity check（哪些子任務低估 / 高估？）
7. 測試 coverage gap（特別 integration test 範圍夠嗎？）

**Verdict 寫法（按昨晚協作協議）**:
- 🟢 **PASS** → queue item Status: APPROVED → 開新 Claude session 寫 A1 implementation plan
- 🟠 **architectural alternative** → 只寫不動，標 `Verdict: Daisy-Decision-Needed`
- 🔴 **Critical flaw** → 寫 `docs/reviews/2026-04-25_partner-entity-design_codex-review.md` 列出問題，spec 修完再 review

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
