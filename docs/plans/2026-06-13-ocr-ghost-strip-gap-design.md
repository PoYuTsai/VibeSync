# OCR ③ 鬼訊息 strip-gap 修復設計（2026-06-13）

> 高風險區（OCR / analyze-chat prod code）。本檔為動碼前的 invariants ＋ failure matrix 契約。
> 狀態：**方案 A 作廢（2026-06-13 翻案）**。根因更正為 vision 層雙 bug，strip 層補救對此 case 無效。下一 session 研究 vision 修法。

---

## ⛔ 翻案（2026-06-13，撈 raw 後）——方案 A 作廢

**動碼前撈 `S__5513242_0` 實際 OCR 輸出**（`tools/ocr-golden/results/before/2026-06-13-11-16-22-local.json`），推翻本檔原本對 case 形狀的假設：

- `expectedCount 3 → actualCount 5`（多 2 鬼）。
- 鬼 content = **單行「這小孩也太刺激」**——卡片的「Bruce Chiang」**名字列被 OCR 丟掉** → explicit path（需 ≥2 行）天生接不到。
- 鬼 side = **left（對方 candy）**；但 `sideMismatches` 顯示 candy 的**兩則真回覆**「教小孩真不容易」「等等見」被 OCR **翻到 right（我側）= side-flip bug**。

**致命點：方案 A 在此 case 根本不會觸發。** body-only strip 的前置硬條件 `current.side === next.side`（`index.ts:3300-3304`）——鬼=left、其後真回覆被翻成 right → `left === right` = false、皆非 unknown → **側連續性 guard 直接 fail** → 不論文字判別（≥5 漢字）怎麼改，strip 永不啟動。

**∴ 原 must-strip 假設「鬼與其回覆同側」是事實錯誤；方案 A 修完 S__5513242 仍漏。** 文字層補救是白做工。

### 更正後的根因（兩個糾纏 bug，都在 vision 層）

- (a) **鬼洩漏**：vision 把引用卡當獨立 left 訊息 ＋ 丟掉卡內「Bruce Chiang」名字頭。
- (b) **side-flip**：vision 把 candy 真回覆翻到右側。
- **(b) 讓 (a) 的下游補救（strip / 方案 A）失效。**

### 下一 session 研究方向（不再走 strip 文字啟發式）

1. **先單獨解 side-flip (b)**（candy 真回覆不該翻右），再評估 strip 是否足夠；或
2. **直接修 vision**：別丟卡片名字列 ＋ 正確掛 `quotedReplyPreview`；含「**label 而非 suppress**」構想——叫 vision 對每塊文字標 `blockType: message|quotedPreview|notice`，下游確定性 filter，把易漏的二元抑制決定換成貼標籤。

### 🔒 LOCKED 決策（2026-06-13，Eric 拍板）

- **幾何閘開放迴圈已解**：before-run `11:16:22 UTC` 晚於閘 commit `9f74885`（`07:32:40 UTC`）→ 閘當時 active，side-flip 仍發生。更糟：`isGeometrySideDecisive`（index.ts:3094）只要 vision 帶 `outerColumn` 就 `true`，而 vision **每筆 row 都帶 outerColumn**（prompt 範例 1040-1064）→ **幾乎全部訊息被 geometryDecisive 鎖死** → layout_parser 的 dominant-side 救援（`applyRunSide` line 259 跳過鎖定者）對 vision flip 失效。**幾何閘在暗色引用卡場景淨負面。**
- **strip 文字啟發式徹底丟棄**（方案 A 已作廢，不復活）。
- **Eric 的 goal = vision 最終判斷精準度，怕 per-case whack-a-mole。** ∴ 改用**源頭級 bake-off、數據決定**，不靠論證猜歸因。
- **主修方向 = ②（schema `blockType` 逐塊分類）**——通用 reframe 非 per-case，降低要求 vision 答對的東西，泛化所有引用卡。
- **side-flip (b) = 獨立 track**：修法為「強單側 dominance 時放寬 geometryDecisive 鎖」，獨立 commit ＋ 獨立 Codex（動的是剛上 prod 的幾何閘）。

### Bake-off 計畫（下一 session 執行，產出量化證據）

只在 hard bucket（dark_mode + quoted_card）比較：
1. baseline（現碼，**記 git SHA**）
2. + 暗色預處理（對比正規化/反白/放大）
3. + ② blockType schema
4.（選配）+ Opus vision

判據：`quotedPreviewLeakTotal`、`sideAccuracy`、`quotePreviewAccuracy` 的 before→after delta。
矛盾點待 bake-off 釐清：Eric 稱「四訊號原圖全清楚」→ 若真清楚則**預處理應幫不大**（瓶頸在契約/注意力 → ②）；預處理一上分就跳 → 反證 salience 不足。

**先決條件（均已備）**：bench `CLAUDE_API_KEY` 已寫 `tools/ocr-golden/.env.golden`（gitignored，**用完 rotate**）。執行前需 dump `S__5513242` 逐訊息 output 坐實幾何閘鎖死推論（目前 result JSON 只存 summary）。

**bake-off 不是修 prod**：純本機量測，preprocessing/② 實作完跑分 → Codex 雙審 → Eric 確認 → 才 push。

### 暗色實證（Eric 親驗截圖）

引用卡四訊號（頭像／白粗體名字「Bruce Chiang」／淺灰內文／圓角邊框）在原圖**全部清楚**——非「讀不出」，是 vision 抽取失誤。卡內「對方在一面倒側出現的他方名字頭」近乎確定性訊號，方案 A 卻丟掉它改數內文漢字（最弱訊號）。

---

> ⬇️ 以下為**已作廢**的方案 A 原始設計，保留供溯源，**不得照此實作**。

## 問題（CONFIRMED REAL）

S__5513242 prod raw 親驗：OCR 把兩張引用卡（`這小孩也太刺激`／`北鼻我睏睏想躺一下`）吐成**獨立 live 訊息**，真 owner 訊息 `quotedReplyPreview` 欄空，`stripQuotedReplyPreviewMessages`（`supabase/functions/analyze-chat/index.ts:3267`）完全沒攔（telemetry `quotedPreviewRemovedCount=0`）⟹ analyze-chat 收 5 則含 2 鬼（舊引用脈絡被當她剛丟的新球）＝真 dogfood 污染 bug。

## 根因（精確）

單行純漢字預覽列**兩條 strip 路徑都漏**：

- **Explicit path**（`isLikelyQuotedReplyPreviewContent`, line 3219）：要求 `lines.length >= 2`（名稱列＋內文列卡片結構）。單行鬼只有 1 行 → false。
- **Body-only path**（`isLikelyBodyOnlyQuotedReplyPreviewCandidate`, line 3252-3257）：`這小孩也太刺激` 全漢字無空格 → `isLikelyQuotedReplyPreviewNameLine` 判 true（誤當聯絡人名）→ 提早 return false。

## 修法（A：收緊判別，局部化下刀）

**關鍵精修**：`isLikelyQuotedReplyPreviewNameLine` 被兩條路徑**反向使用**——
- explicit path 要它對名稱回 true（含長暱稱）；
- body-only path 用它當排除條件。

∴ **絕不全域收緊** `isLikelyQuotedReplyPreviewNameLine`（會傷 explicit path 的長暱稱卡辨識）。
改為**只在 body-only 候選裡**把排除條件改成：

```
line[0] 是 name-line 但「看起來是句子不是名字」→ 不排除（視為鬼候選）
```

「看起來是句子」訊號＝**單一連續漢字 run（無空格、無拉丁字）長度 ≥ 5**（N=5，可調參數，靠測試釘死）。
理由：繁中聯絡人名/暱稱在預覽**內文位置**極少 5+ 連續漢字。`這小孩也太刺激`(7)、`北鼻我睏睏想躺一下`(8) 通過；`早安`(2)、`謝謝你`(3) 仍受保護。

## Invariants（strip 永不違反）

1. **首訊息永不被 strip**：body-only 維持 `!!previous`，本修不放寬。
2. **explicit path 行為零改動**：不動共用 `isLikelyQuotedReplyPreviewNameLine`。
3. **strip 只搬不丟**：鬼文字經 `extractQuotedReplyPreviewContent` 掛到 next 的 `quotedReplyPreview` 欄（既有邏輯不改）。
4. **side 連續性 guard 不放寬**：`current.side===next.side || unknown` 維持。

## Failure Matrix

| 案例 | 形狀 | 期望 | 守門機制 |
|------|------|------|---------|
| **must-strip** S__5513242 | 單行純漢字鬼在側翻後、next 是短 reply target | strip→掛 preview | 新 ≥5 Han = 非名 |
| must-NOT ① 真首訊息像名 | 首位短漢字、無 previous | 保留 | `!!previous` |
| must-NOT ② 真連發 | 兩則實質訊息連續同側、next 非短 reply target | 保留 | `isLikelyShortReplyTargetContent(next)` |
| must-NOT ③ 真短名預覽 | line[0] 真是 2-4 字聯絡人名 | 既有行為不變 | <5 Han 仍判名 |
| must-NOT ④ 中段短漢字真訊 | 5+ 漢字真訊但 next 非短 target／無側翻 | 保留 | previous 側翻＋next short target 雙 guard |

**剩餘暴露面（如實揭露）**：must-NOT ④ 若某真訊息剛好 5+ 漢字、前有側翻、next 又是媒體/短續——會被誤 strip。N=5 與 body-only guard 的病態巧合無法 100% 排除；靠負向測試釘典型真連發，Codex 雙審盯此點。

## 實作步驟（下一 session，TDD 紅→綠）

1. **Export for test**：`stripQuotedReplyPreviewMessages`（或 helper）目前未 export、無專測，需先 export。
2. **紅燈先行**：鏡射 S__5513242 must-strip 形狀回歸測試 ＋ must-NOT ①〜④ 負向測試。
   - must-strip 精確 5-message 序列（含 sides）需自 prod raw 確認／或依本檔結構描述重建。
3. **最小修** `isLikelyBodyOnlyQuotedReplyPreviewCandidate`：≥5 連續漢字 run 視為句子非名。
4. `deno test` ＋ `deno check` 綠。本機 only。
5. **重跑測試集**（Eric 要的最終回報）：fix 後對 dark/quoted 多輪跑分，回報 `quotedPreviewLeakTotal`→0、side/recall/exactText/quotePreviewAccuracy before vs after。
6. **Codex 雙審**（高風險 gate）→ APPROVED。
7. **僅在 APPROVED ＋ Eric 確認後** push/deploy（auto-deploy aware；幾何閘 9f74885 已於 2026-06-13 上 prod，本案 push 只帶鬼訊息修法本身）。

## 絕不

- 絕不未經 Codex APPROVED＋Eric 確認就 push（OCR/analyze-chat prod 高風險區，push 即 auto-deploy 進 prod）。
- 絕不放寬 `!!previous`（首訊息保護）。
- 絕不全域改 `isLikelyQuotedReplyPreviewNameLine`（傷 explicit path）。
