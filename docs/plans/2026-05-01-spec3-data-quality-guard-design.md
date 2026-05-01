# Spec 3: Partner Data Quality Guard — Design

> **狀態**：BRAINSTORM 完成，等 Eric / Codex 對齊後才進 `superpowers:writing-plans`。
> **不含 implementation plan**。
> **前置依賴**：Spec 1 About Me（已 ship）、Spec 2 Partner Style Override（已 ship @ 7bef1d1）。

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
| AI 行為 | L1 即時回覆照常 / L2 不寫進主卡 + 呈現層提醒 / L3 照常顯示 + 低壓提示 / L4 N/A |
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

### 3.3 偵測來源優先順序（嚴格遵守）

1. **Conversation-level 名稱訊號**：`Conversation.name` / OCR header / 分析後對話名稱欄位
2. **保守 message regex**：「我叫 X」「Hi I'm X」這類明確自報訊號（中英文 only）
3. **絕不**：全文大量抓人名 — 避免朋友、女兒、寵物、店名誤判成對象

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
| **L2 對方特質卡 / 長期記憶** | trait 抽取、跨輪摘要 | ⏸ **不再把疑似混入後新內容併進主卡**；既有資料保留顯示，卡底加：「這張卡可能混到不同人的聊天，整理後分析會更準。」 |
| **L3 熱度趨勢 / 長期報告** | 多 round aggregate 數值與曲線 | 照常顯示 + 同一個低壓提示；**不標紅、不降分** |
| **L4 教練建議** | Spec 4，未做 | （Spec 4 接時要避免引用 flagged 卡的長期人格結論） |

### 5.1 v1 不重算

拆卡後新對象從拆出去那刻起累積；舊卡保留拆出去之前的 trait（不重算）。完整重算放 v2。

### 5.2 「標記為同一人」恢復寫入

使用者標記後，這組 names 衝突不再提醒、L2 寫入恢復可信。**範圍限這組 names**：之後若出現第三個新名字，仍會再提醒。

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

### 7.3 偵測流程（high-level）

```
PartnerDetail open
  ↓
讀取該 partner 底下所有 conversation
  ↓
per-conversation 抽 name candidate（按 §3.3 優先順序）
  ↓
跨 conversation 比對：
  - 候選名字集合 size ≥ 2 且名字明顯不同
  - 且該 (nameA, nameB) pair 不在 confirmedSamePersonPairs
  ↓
true → 顯示 PartnerDataQualityBanner
false → 不顯示
```

### 7.4 持久化（新 entity）

```dart
@HiveType(typeId: <next>)
class PartnerDataQualityState {
  @HiveField(0) String partnerId;
  @HiveField(1) List<NamePair> confirmedSamePersonPairs;  // 使用者標記過的同一人組合
  @HiveField(2) List<NamePair> dismissedNamePairs;        // （保留欄位，v1 暫不用，因為「忽略一次」拿掉）
  @HiveField(3) DateTime updatedAt;
}
```

- 獨立 box（例：`partner_data_quality_states`），AES-256 加密（同 Spec 1 / Spec 2 pattern）
- **只持久化使用者確認過的 pair**
- flag 本身 read-time 算，不持久化
- **不塞 Partner entity**（與 Spec 2 PartnerStyleOverride 同 pattern）
- 不雲端同步（本地優先，與其他 Hive 資料一致）

### 7.5 UI 元件

**新建** `PartnerDataQualityBanner`（sibling of `SameNameDedupeBanner`）：
- 重用 visual lineage：glassmorphic surface tokens、雙 action button layout、padding rhythm
- **不共用元件名稱、不共用 copy**
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
- ❌ 把疑似混入後新內容寫進 trait 主卡

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

1. **Conversation.name 與 OCR header 欄位現況**：implementation plan 需先 grep 現 codebase 確認 conversation-level 名稱訊號的 schema，看是否需要先補欄位
2. **「明顯不同」的判斷算法**：兩個名字長得多不同才算 flag？例：Anna vs Anne？Anna vs 安娜？需 implementation 階段定 normalize 規則
3. **Banner 顯示時機 race condition**：conversation 儲存中 → save callback invalidate → detail 重新 read 之間，是否會閃爍？需 implementation 階段定 loading state
4. **拆卡後 conversation 搬移的 atomic 保證**：Hive 操作是否保 atomic？失敗時如何 rollback？
5. **Hive typeId 序號**：next available（Spec 2 用到 13）

---

## 12. 下一步

1. **本 design doc commit + push**
2. **Eric / Codex 對齊**（若 Codex 有 spec review 意見走 `docs/reviews/ai-arbitration-queue.md`）
3. 對齊後啟用 `superpowers:writing-plans` 寫 implementation plan
4. 待寫的 implementation plan **不在本 spec 範圍**
