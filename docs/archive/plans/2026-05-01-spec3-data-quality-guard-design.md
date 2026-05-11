# Spec 3: Partner Data Quality Guard — Design

> **狀態**：BRAINSTORM + Codex spec review 完成，已收 amendments；待 Eric 點頭即進 `superpowers:writing-plans`。
> **不含 implementation plan**。
> **前置依賴**：Spec 1 About Me（已 ship）、Spec 2 Partner Style Override（已 ship @ 7bef1d1）。
> **Codex review**：`docs/reviews/2026-05-01_spec3-data-quality-guard_codex-review.md`（c7cfee5），verdict 🟡 APPROVED-WITH-AMENDMENTS。本檔已 amend 5 點 — §3.3（P3 placeholder rules）、§5 表 + 新 §5.3（P1 PartnerContextResolver 降級）、§7.3（P5 scan cap）、§7.4（P4 移除 dismissedNamePairs）、新 §7.6（P2 cascade contract）。

---

## 1. 目標與動機

VibeSync 不是單次回覆產生器，而是「會記得我和每個對象的約會教練」。記憶可信度是 Layer 2（對方特質）/ 3（長期記憶）/ 4（教練建議）的基礎。

當使用者把不同人的聊天放進同一張對象卡時，AI 會把對方特質、熱度趨勢、長期記憶、後續教練建議混在一起，導致輸出失準。Spec 3 的目標是**提供低打擾的資料品質提醒 + 最小整理工具**，讓使用者主動處理疑似混入，而不是讓 AI 自動責備或自動搬資料。

**核心定位**：資料整理建議（assistive），不是錯誤警告（accusatory）。

---

## 2. 拍板總覽

| 主題 | 拍板 |
|---|---|
| 偵測訊號 | MVP 主訊號 = 名字不一致；其餘訊號 v2 候選 |
| 偵測來源 | conversation-level 名稱訊號優先，message regex 保守 fallback；不全文抓人名 |
| UX placement | Partner detail 頂部 banner only |
| UX tone | 白話 + 給「同一人就忽略」退路；禁用「異常 / 警告 / ⚠️ / 紅色 / 強制彈窗」 |
| AI 行為 | L1 即時回覆照常 / L2 `PartnerContextResolver` 注入降級（minimal header，no aggregate）+ 呈現層提醒 / L3 照常顯示 + 低壓提示 / L4 N/A |
| 整理工具 | 拆成新對象（auto by name，conversation 為單位）+ 標記同一人 |
| 偵測引擎 | 純本地 heuristic，不動 prompt / OCR / Edge Function |
| 持久化 | 新獨立 entity `PartnerDataQualityState`，只存使用者確認過的 pair；flag 本身 read-time 算 |
| Banner 元件 | sibling component `PartnerDataQualityBanner`，reuse `SameNameDedupeBanner` 視覺 lineage 但**不共用名稱與 copy** |

---

## 3. 偵測訊號（Q1）

### 3.1 MVP 主訊號

**名字不一致**：同一張 partner 卡底下，多段 conversation 各自抽出的「對方主要名字」若有 ≥ 2 個明顯不同 → flag。

### 3.2 不做的訊號（v2 候選或永久排除）

- 對方稱呼用戶的方式衝突（哥/弟/老師）— 中文情境切換太常見，最多作 secondary / debug，不進 banner trigger
- 平台跳轉（IG → Line）— 正常產品情境
- 語氣差異 — 心情、時間、關係階段都會影響
- 特質互相矛盾 — v2 候選，需 TF 樣本評估
- 時間線異常 — v2 候選

### 3.3 偵測來源優先順序（嚴格遵守 — amended P3）

1. **Conversation-level 名稱訊號（priority 1）**：`Conversation.name`，但**不無條件採信**：
   - **拒絕 placeholder**：`新對話`、`新的對話`、`互動紀錄`、`第 X 段`、純日期型 title、空字串
   - **舊資料**只在通過保守「looks-like-person-name / nickname」filter 時採用（implementation 階段定 filter 規則）
   - **未來 OCR 進來的 `contactName`** 信心較高，但 Codex 確認目前 codebase **沒有 provenance 欄位**標記「此 name 來自 OCR header」 → §11.6 列為 implementation 階段需處理的 open question
2. **保守 message regex（priority 2，極窄）**：「我叫 X」「Hi I'm X」「Call me X」這類明確自報訊號，中英文 only
3. **scan cap**：見 §7.3
4. **絕不**：全文抓人名 / NER — 避免朋友、女兒、寵物、店名誤判成對象

### 3.4 接受的權衡

- 接受 **low recall**（中文沒空格、暱稱多，會漏抓）
- 不接受 **high false positive**（誤觸提醒會讓使用者覺得 AI 多事 → 直接關掉所有資料品質功能）

---

## 4. UX 提醒（Q2）

### 4.1 Placement

**Partner detail 頂部 banner only**。
- 首頁不放警示 icon
- 新增 conversation 完成當下不跳提示
- 不用強制彈窗

### 4.2 Banner 結構

```
┌─────────────────────────────────────────────────┐
│ 這張卡裡出現了兩個名字：「Anna」「May」。           │
│ 如果她們是同一個人，可以先不用管；                  │
│ 如果不是，建議拆成不同對象卡，分析會比較準。         │
│                                                 │
│         [這是同一人]    [拆成新對象]              │
└─────────────────────────────────────────────────┘
```

### 4.3 Tone 規則

- ✅ 白話、低壓、給退路
- ✅ 動作詞：分開 / 拆 / 整理 / 兩個名字
- ❌ 禁用詞：異常 / 警告 / ⚠️ / 錯誤 / 混入
- ❌ 視覺：紅色、警告色 icon
- ❌ 互動：強制彈窗、首頁徽章

### 4.4 顯示規則

Banner 永久顯示直到使用者執行「拆成新對象」或「這是同一人」。N 天後不會自動隱藏（與 Q3 邊界對齊：整理才能恢復 L2 寫入）。

### 4.5 跨 Spec UI 排序（R4 directive）

Partner detail 同時可能出現 hero card、PartnerStyle card、traits card、Quality banner。**Quality banner 放在 traits / summary 附近，不壓過 hero**。具體像素級排序在 implementation 階段定。

---

## 5. AI 行為分層（Q3）

| 層 | 內容 | flagged 時的處置 |
|---|---|---|
| **L1 即時回覆** | 五種回覆、熱度 0-100、進度五階段 | ✅ 照常 — 只看當下 round 文本 |
| **L2 對方特質卡 / 長期記憶** | partner aggregate（`partner.aggregateOver(conversations)` → `partner_summary_builder` → `PartnerContextResolver` 注入 `analyze-chat`） | ⏸ flagged-unresolved 時 **`PartnerContextResolver` 注入降級**：回傳 minimal partner header（name/id），不注入 aggregate traits / interests / notes（見 §5.3）。UI 既有 trait / notes 卡照樣顯示但加提示：「這張卡可能混到不同人的聊天，整理後分析會更準。」 |
| **L3 熱度趨勢 / 長期報告** | 多 round aggregate 數值與曲線 | 照常顯示 + 同一個低壓提示；**不標紅、不降分** |
| **L4 教練建議** | Spec 4，未做 | （Spec 4 接時要避免引用 flagged 卡的長期人格結論） |

### 5.1 v1 不重算

拆卡後新對象從拆出去那刻起累積；舊卡保留拆出去之前的 trait（不重算）。完整重算放 v2。

### 5.2 「標記為同一人」恢復寫入

使用者標記後，這組 names 衝突不再提醒、L2 注入恢復完整。**範圍限這組 names**：之後若出現第三個新名字，仍會再提醒。

### 5.3 PartnerContextResolver 注入降級規格（amendment P1）

**Codex 校準**：partner memory 不是寫在「主卡」，而是每次從 conversations aggregate 後由 `PartnerContextResolver` 注入 `analyze-chat`。若只顯示 banner 而 resolver 照常注入，污染 context 仍會進 AI，違反 spec 核心動機。

**Required behavior**（implementation plan 必須實作）：

| 注入內容 | flagged-unresolved | flagged-resolved（confirmed same person）/ 未 flagged |
|---|---|---|
| Partner header（name / id） | ✅ | ✅ |
| Aggregate traits | ❌ | ✅ |
| Interests | ❌ | ✅ |
| Notes | ❌ | ✅ |
| 當下 conversation 即時內容 | ✅ | ✅ |

**邊界**：
- 這是 **client-side context gating** — 不改 prompt / Edge Function / OCR，符合 §7.1
- L1 即時回覆**照常**（當下 conversation 文本仍注入）
- 使用者執行「拆成新對象」或「這是同一人」後 resolver 自動恢復完整注入（read-time 算 + invalidate）

**Implementation 測試需求**：
- flagged 時 resolver 確實只回 minimal header
- resolved / 未 flagged 時 resolver 行為不變
- flag 切換後立即生效

**Affected files**（implementation 參考）：
- `lib/features/analysis/data/services/partner_context_resolver.dart`（resolver 介面變更）
- `lib/features/partner/domain/extensions/partner_aggregates.dart`（aggregate 跳過邏輯，視 implementation 選擇分層在哪一層）
- `lib/features/partner/domain/services/partner_summary_builder.dart`

---

## 6. 整理工具（Q4）

### 6.1 MVP 兩個動作

**① 拆成新對象（auto-split by name，conversation 為單位）**
- 系統提示：「Anna 留在原卡 / May 移到新卡 → 確認」
- 拆分單位 = conversation / 互動紀錄，**不是 round / message**
- 原卡：保留原名 + 原 PartnerStyleOverride
- 新卡：用偵測到的另一個名字建立、空 override（走 global About Me fallback）
- 被移出的 conversation 整段搬到新卡
- v1 不重算 trait

**② 標記「這是同一人」**
- banner 收掉
- 恢復 L2 寫入
- 記住這組 names 確認過
- 第三個新名字才會再提醒

### 6.2 不做（v2 或拿掉）

- ❌ 移到既有對象（v2 — 需要 partner picker + 多選 round UI）
- ❌ 手動勾 round 拆分（v2 — 心智負擔大）
- ❌ 忽略一次（拿掉 — 跟「這是同一人」重疊）

### 6.3 邊界

- 同一段 conversation 內**同時命中兩個名字** → v1 留在原卡不動。AI 信心不足，寧可不動也不要誤搬。
- 所有拆卡**必須使用者確認**，不做 AI 自動判定後直接搬移。

---

## 7. 技術方案（Q5）

### 7.1 偵測引擎

**純本地 heuristic（Dart 端）**。
- ❌ 不動 `analyze-chat` Edge Function
- ❌ 不混 prompt
- ❌ 不碰 OCR baseline
- ❌ 不加 backend `partnerNameCandidates` field（v1.5 候選，看 TF recall 數據再評估）

### 7.2 偵測時機

| 時機 | 責任 |
|---|---|
| Conversation 儲存後 | 更新 / invalidate guard 狀態（讓下次 detail 開啟能看到最新） |
| Partner detail 開啟時 | read-time 重新計算 — 主入口 |

**不需要 background job**。以 detail read-time 為主，save 後僅 invalidate。

### 7.3 偵測流程 + scan cap（amended P5）

```
PartnerDetail open
  ↓
讀取該 partner 底下所有 conversation
  ↓
per-conversation 抽 name candidate：
  1. Conversation.name 通過 §3.3 placeholder filter → 採用，stop
  2. 否則 message regex fallback：只掃**前 N 則 + 後 N 則 incoming messages**
     （v1 N = 5；不掃中段、不掃 outgoing user messages）
  ↓
跨 conversation 比對：
  - 候選名字集合 size ≥ 2 且名字明顯不同（normalize 規則 §11.2 open question）
  - 且該 (nameA, nameB) pair 不在 confirmedSamePersonPairs
  ↓
true → 顯示 PartnerDataQualityBanner
false → 不顯示
```

**v1 perf contract**：
- N 段 conversation × 最多 10 則 message scan（前 5 + 後 5 incoming）
- 不全文掃描、不做 NER
- 不在 v1 加 in-memory cache（先驗證 N×10 成本足夠便宜；若 partner detail 開啟有可感延遲再升級到 cache + invalidate）

### 7.4 持久化（新 entity，amended P4）

```dart
@HiveType(typeId: 14)
class PartnerDataQualityState {
  @HiveField(0) String partnerId;
  @HiveField(1) List<NamePair> confirmedSamePersonPairs;
  @HiveField(2) DateTime updatedAt;
}
```

- 獨立 box `partner_data_quality_states`，AES-256 加密（同 Spec 1 / Spec 2 pattern）
- **只持久化使用者確認過的 same-person pair**
- flag 本身 read-time 算，不持久化
- **不塞 Partner entity**（與 Spec 2 `PartnerStyleOverride` 同 pattern）
- 不雲端同步（本地優先，per G4）
- **`dismissedNamePairs` 不留欄位**（amendment P4：v1 沒有「忽略一次」action，留欄位變死 schema migration baggage；v2 若重新引入再加新 field）
- typeId = 14（Spec 2 用到 13，Codex 已確認下一個是 14）

### 7.5 UI 元件

**新建** `PartnerDataQualityBanner`（sibling of `SameNameDedupeBanner`）：
- 重用 visual lineage：glassmorphic surface tokens、雙 action button layout、padding rhythm
- **不共用元件名稱、不共用 copy**

### 7.6 Privacy / Cascade Contract（amendment P2）

新 box `partner_data_quality_states` 必須對齊 Spec 1 / 2 既有 cascade pattern：

| 觸發 | 行為 | Implementation 測試需求 |
|---|---|---|
| `StorageService.clearAll()` | 清整個 box | unit test on `StorageService` |
| Partner delete | 刪該 `partnerId` 的 state | 擴張 `partner_repository_cascade_test` |
| Partner merge（A → B） | 刪 source A 的 state；B 的 state 不動（B 自己的 confirmed pairs 保留） | 擴張 `partner_repository_merge_test` |
| Partner split（拆成新對象） | source 的 state **保留**（confirmed pairs 仍對源卡有意義）；new partner 的 state = empty | 新測 `partner_repository_split_test` |
| 雲端同步 | **不同步**（per G4） | N/A |

**Cascade pattern 來源 reference**：
- Codex `7bef1d1` — `PartnerStyleOverride` 的 partner merge cascade
- `8bb410b` — `clearAll()` 同步清 `partner_style_overrides`
- 本 spec **split path 是新 cascade 路徑**（merge 反向），需獨立測試覆蓋（不能類比 merge）

**Affected files**（implementation 參考）：
- `lib/core/services/storage_service.dart` — clearAll 增清新 box
- `lib/features/partner/data/repositories/partner_repository.dart` — delete / merge cascade
- `lib/features/partner/data/providers/partner_write_controller.dart` — write controller 對 state invalidation
- 兩者語意相反：
  - `SameNameDedupeBanner`：兩張同名卡 → 合併
  - `PartnerDataQualityBanner`：一張卡內兩個名字 → 拆分

---

## 8. Scope / Non-goals（Q6）

### 8.1 灰色地帶拍板（G1–G5）

- **G1 多語言**：zh + en only。
- **G2 升版 backfill**：不做。read-time 自然觸發。
- **G3 拆卡後 PartnerStyleOverride**：留原卡。新卡空 override 走 global About Me。
- **G4 雲端同步 confirmed pairs**：本地不同步。
- **G5 banner 不點 action**：永久顯示直到動作為止。

### 8.2 全量 Non-goals

**訊號層**
- ❌ 平台跳轉、語氣差異作為 trigger
- ❌ 特質矛盾、時間線異常（v2 候選）
- ❌「對方稱呼用戶方式」當 banner trigger
- ❌ 全文大量抓人名

**UX 層**
- ❌ 首頁警示 icon、新增完成跳提示、強制彈窗
- ❌「異常」「警告」「⚠️」「紅色」嚇人元素
- ❌「忽略一次」action

**AI 行為層**
- ❌ v1 trait 重算
- ❌ 暫停 L1 即時回覆 / 五種回覆 / 熱度
- ❌ flagged-unresolved 時 `PartnerContextResolver` 注入 aggregate traits / interests / notes（per §5.3）

**整理工具層**
- ❌「移到既有對象」（v2）
- ❌ 手動勾 round 拆分（v2）
- ❌ 跨名混名 conversation 自動 split（v1 留原卡）
- ❌ AI 自動判定後直接搬移 — 所有拆卡必須使用者確認

**技術層**
- ❌ 動 analyze-chat / prompt / OCR baseline
- ❌ Backend `partnerNameCandidates` field（v1.5 候選）
- ❌ Background job
- ❌ flag 本身持久化
- ❌ 直接塞 Partner entity
- ❌ 雲端同步 confirmed pairs

**跨 Spec 邊界**
- ❌ Spec 4 Coach Action Card
- ❌ Spec 5 proactive follow-up

---

## 9. 風險

| ID | 風險 | 對策 |
|---|---|---|
| **R1** | 中文名字 recall 偏低 | Q1 已接受 low recall。TF soak ≥ 2 週後看 missed-detection 數據評估升 backend signal |
| **R2** | 假陽性傷害大於假陰性 | 偵測來源優先順序 + 「這是同一人」一鍵 dismiss + 不再次提醒同組 names |
| **R3** | 拆卡破壞 Spec 2 cascade 邏輯 | 7bef1d1 修了 merge 的 override cascade；split 是反向 cascade，**需新測試覆蓋**（不能只靠類比） |
| **R4** | 跨 Spec UI 心智負擔 | design 階段定 Partner detail 元件排序：Quality banner 在 traits/summary 附近、不壓 hero |
| **R5** | OCR / Conversation.name 缺失時靜默 | 沒有 conversation-level 名稱訊號的 partner 會 silent；可接受，已寫明 |

---

## 10. 跨 Spec 互動

### Spec 1（UserProfile / About Me）
- 不直接互動（user-scoped vs partner-scoped）
- 拆出新卡走 global About Me fallback（Spec 1 兜底）

### Spec 2（PartnerStyleOverride）
- **拆卡 cascade**：override 留原卡（G3 拍板）
- **新卡 override** = empty → effectiveStyle 走 global About Me
- **新測試覆蓋**：split path 的 cascade 行為 — 不能只類比 merge 的 7bef1d1
- **Partner merge** 已有 cascade（7bef1d1）；split 是新 cascade 路徑

### Spec 4 / Spec 5（未做）
- Spec 4 Coach 接時要 query `PartnerDataQualityState` 判斷是否 flagged，flagged 時避免引用長期人格結論
- Spec 5 proactive follow-up 不在本 spec 範圍

---

## 11. 開放問題（implementation 階段需解決）

1. ✅ **RESOLVED — Conversation.name 與 OCR header 欄位現況**：Codex 已 grep（review doc §findings P3 + Pre-Plan Grep Notes）。`Conversation.name` 存在但是 mutable display field；`RecognizedConversation.contactName` 存在於 OCR 流程；`Message` 沒有 sender label。**Implication**：§3.3 priority 1 必須加 placeholder filter（已 amended）；OCR provenance marker 列為 §11.6。
2. **「明顯不同」的判斷算法**：兩個名字長得多不同才算 flag？例：Anna vs Anne？Anna vs 安娜？全形半形 / 大小寫 / 簡繁？需 implementation 階段定 normalize 規則。
3. **Banner 顯示時機 race condition**：conversation 儲存中 → save callback invalidate → detail 重新 read 之間，是否會閃爍？需 implementation 階段定 loading state。
4. **拆卡後 conversation 搬移的 atomic 保證**：Hive 操作是否保 atomic？失敗時如何 rollback？
5. ✅ **RESOLVED — Hive typeId 序號**：Codex 確認 next available = `14`（Spec 2 用到 13）。已寫進 §7.4。
6. **NEW (P3 amendment) — OCR provenance marker**：當 OCR 流程把 `RecognizedConversation.contactName` 寫進 `Conversation.name` 時，是否需要新欄位 / metadata 標記「此 name 來自 OCR header」，讓 §3.3 priority 1 可以高信心使用？或維持「所有 Conversation.name 皆走相同 placeholder filter」？implementation 階段拍板。
7. **NEW (P5 amendment) — in-memory cache trigger**：v1 不做 cache，但若 partner detail 開啟有可感延遲（partner 底下 conversation 多時），何時升級到 in-memory cache + invalidate-on-save？需要 perf benchmark 數據後判斷。

---

## 12. 下一步

1. ✅ design doc commit + push（`cd36a05`）
2. ✅ Codex spec review（verdict 🟡 APPROVED-WITH-AMENDMENTS @ `c7cfee5`）
3. ✅ 本檔 amend 5 點（P1–P5）並 commit + push
4. **Eric 點頭** → 啟用 `superpowers:writing-plans` 寫 implementation plan
5. 待寫的 implementation plan **不在本 spec 範圍**

---

## Appendix A: Codex Amendments Changelog

| Item | Codex finding | 處置 | 寫進章節 |
|---|---|---|---|
| **P1** | flagged 卡未 gate `PartnerContextResolver`，banner 變裝飾 | Accept — added §5.3 注入降級規格 | §2 / §5 / §5.3 / §8.2 / §11.1 |
| **P2** | 新 box 缺 cascade contract | Accept — added §7.6 | §7.6 / §10 |
| **P3** | `Conversation.name` 不安全當 high-confidence；need placeholder rejection + 保守 filter | Accept — amended §3.3 + §11.6 open question | §3.3 / §11.1 / §11.6 |
| **P4** | `dismissedNamePairs` 死 schema | Accept — removed from §7.4 entity | §7.4 |
| **P5** | read-time scan cap | Accept — added §7.3 perf contract + §11.7 | §7.3 / §11.7 |

無 push back / 無 Daisy-Decision-Needed。
