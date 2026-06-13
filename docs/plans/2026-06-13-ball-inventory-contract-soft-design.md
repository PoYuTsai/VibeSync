# 球數案修法二：盤點逼進輸出契約（軟版）設計

> 日期：2026-06-13 · 狀態：設計拍定，待新 session TDD 實作 · 前置：commit `ddce074`（few-shot 範例3，黑箱 FAILED）

## 為什麼要這個（根因 + 機制）

黑箱重打 golden（`tools/voice-benchmark/cases/golden_anchor_recon.json`）3 次共 15 個 style 輸出：只 1/15 達 ≥3 段，選中風格 coldRead 每次 2 段（srcIdx 6,5＝未接視訊+到家）。finalRecommendation.reason 證據：「她主動打視訊是這輪最高價值的球…」——**模型根本沒做盤點，直接抓單一最熱球，靜默吞掉比賽(2,3)、晚餐照(4)、msg1**。

few-shot 正例（範例3）與三件套散文同命：被當散文略過。

**機制診斷**：現在「盤點」寫在 reason（決策後才填的事後辯解欄），模型先選球再補理由。**修法＝把盤點做成「最先 emit、列全 N 球」的必填事件，強迫 autoregressive 生成上「先逐項分類完才准選球」——分類在選擇之前，吞不掉。順序是關鍵。**

## 軟版範圍（Eric 拍板：軟先、只動 stream、中文標籤）

### 1. 新事件 `analysis.inventory`，最先 emit（在 `analysis.decision` 之前）
```json
{"type":"analysis.inventory","balls":[
  {"sourceIndex":1,"sourceMessage":"…","disposition":"接","reason":"…"},
  {"sourceIndex":2,"sourceMessage":"…","disposition":"併","reason":"…"}
]}
```
- 全 N 球逐項列（連發幾句就幾項，[Photo]/[Missed call] 等媒體標記也各算一項）。
- disposition 中文 enum：`接` / `併` / `略`（與既有 prompt 散文一致；模型對中文標籤服從度在本案已驗）。

### 2. 一次全域，非每風格
盤點對「她的訊息」分類、與風格無關 → emit 一次。五風格 segments 都從標「接/併」的球取材。

### 3. Prompt（`stream_prompt.ts` + SYSTEM_PROMPT）
- `buildStreamSystemPrompt` 事件順序加 step 0 = `analysis.inventory`，附 1 行 example line（仿現有 recommendation/reply_option 的 example）。
- SYSTEM_PROMPT 已有「盤點先行」散文＋範例3 已示範 接/併/略 格式，複用即可，補一句「盤點要先 emit 成 inventory 事件，不是只寫進 reason」。

### 4. Server＝純放行（軟版本質）
收到 inventory 事件就 log/丟棄。**不驗證、不 reject、完全不碰 `sanitizeReplySegments` 丟段路徑**（守住上輪 handoff 紅線）。

### 5. reframer 容忍（TDD 第一個紅燈）
唯一真風險：現有 stream 組裝器遇未知事件型別會不會炸？必須在 `stream_events.ts` 把 `analysis.inventory` 註冊成 **known-optional**：reframer 認得、不報錯、不阻斷後續事件；App 端可忽略不渲染但不得 crash。

### 6. Legacy 路徑
**本輪不做**（YAGNI，dogfood 走 stream）。未來若要：SYSTEM_PROMPT 輸出 JSON 加 `ballInventory` 為 finalRecommendation 第一欄位。

## TDD 順序（新 session）
1. 🔴 reframer/stream_events 容忍 `analysis.inventory`（unknown→known-optional，不炸、不阻斷）。
2. 🔴 `stream_prompt.ts` 事件順序含 inventory step 0 + example line（anchor 測試）。
3. 🔴 server 收 inventory 純放行、不碰 segments（contract 測試：丟段路徑零改動）。
4. 🟢 實作至全綠 + `deno check`。
5. **真驗收 gate＝黑箱重打 golden**：選中風格須 ≥3 段含 msg1+msg4、reply 有素材。單元測試只是護欄。
6. Codex 雙審（高風險：stream contract + AI prompt）→ 才可宣稱 dogfood-safe。

## 風險 / 回退
- 軟版不改丟段路徑、不 reject，回退＝移除 inventory step + 事件註冊即可。
- 若軟版黑箱仍不達標 → 升級硬驗證（server 驗 segments 只來自接/併球、接數達下限），但那會碰丟段路徑、需重評風險。

---

## ✅ 硬版 SHIPPED（2026-06-13）

實作完成並通過全部 gate，dogfood-safe（WAITING Eric/Bruce 體感）。commits：
`0a571ae`（reframer disposition 閘＋新 `ball_inventory.ts`）、`ef9c601`（compliance
floor (b)＋callback 原則 (c) prompt）、`7cee711`（b2 選中風格別寫得比其他短）、
`7380a29`（Codex adversarial P2 修：下限數 distinct 接/併球）。黑箱重打 golden
（b2 ×3＋P2 confirm）：選中風格穩定 ≥3 真接球、零 INCOMPLETE、msg1 callback 會
被撩回。Codex 雙審：review APPROVED 0；adversarial r1 P2→修→r2 APPROVED 0。
**實作偏離原設計（更安全）**：閘設在 reframer `forwardReplyOption` 轉發上游＝
直接丟棄不誠實 option 走既有 INCOMPLETE，**完全沒碰 `sanitizeReplySegments`／
丟段路徑**（INV-H5 trivially 守住，比下方原設計步驟 4 預期更安全）。(c) 不寫死
golden、改通則 prompt 原則，黑箱證實生效（msg1 每跑都接）。詳見 queue item。

P3 follow-up（非阻斷）：`catchableCount` 按 row 累加而非 distinct sourceIndex，
僅模型 emit 重複列時才偏差，正常流量零影響。

---

## 硬版升級設計（2026-06-13，soft 黑箱 FAILED 後，Eric 拍板升級）

> soft 版 `c782e98` 已 land＋deploy。黑箱重打 golden ×3 完全一致：inventory 機制成功（模型顯式列全 6 球 `1略 2併 3接 4接 5接 6接`），但選中風格仍 2 段（srcIdx 6,5）。下面是硬版 TDD 開工前必備的 invariants＋failure matrix。**新 session 執行，先讀三檔。**

### 根因二分（黑箱實證）
- **(b) inventory→reply 斷層**：模型標 4 顆接（idx 3,4,5,6）卻只寫 2 段（5,6），公然違反自己的盤點＋「segments 只來自接/併球」指令。← **硬版 server 驗證可治**。
- **(c) msg1（只喜歡江果先）誤判略**：模型 reason「語境不明…無可接球點」。**經查 golden `partnerSummary` 只寫「糖糖老師」自造梗、完全沒有「江果先」字串**——模型沒有任何脈絡能把「只喜歡江果先」連到對象歷史，標略**可能是正確行為不是 bug**。← **硬版 server 驗證治不了**（server 無法叫模型去接一顆它自己標略的球）。

### ⚠️ 關鍵結論：硬版單獨無法滿足 gate「≥3 含 msg1+msg4」
- server 硬驗證（接數下限＋segments⊆接/併）能逼出 **≥3 段＋msg4**（從接集 {3,4,5,6} 挑 3 顆必含 4），治 (b)。
- 但 **msg1 永遠進不來**，因為模型標它略、server 不能強接略球。
- **(c) 不是改資料、不是改 gate——那兩個都是寫死/搬球門的補丁（Eric 2026-06-13 駁回）**。真正的通則解是一條 **prompt 原則**：
  - golden `partnerSummary` 其實已寫「用戶自造梗，她會接梗」——模型本來就有「內部梗在流動」的信號，只是沒把「只喜歡江果先」連上去。
  - 原則：**當 partnerSummary 顯示有自造梗/內部梗，或某句讀起來像個人 callback 但缺完整背景時，當它是可接的高價值球，用「順著玩／俏皮反問」接住，不判略**。略只留給真的沒內容（純貼圖無字等），不留給「我沒有背景故事」。
  - 優點：① 通用到其他對象/對話，非 overfit 這張 golden ② 不碰丟段路徑 ③ 正是好教練/好調情真實行為（GPT 版即把江果先 callback 撩回）。
  - 風險/未知：模型已兩次不聽散文（few-shot＋inventory），這條原則能不能被遵守是經驗問題，要黑箱驗；可能需 worked-example 等級而非一句散文。
- **(c) 與硬版 (b) 正交**：(b) 是 server 強制段數（碰丟段路徑、必雙審）；(c) 是 prompt 分類原則（不碰丟段路徑）。可分兩案、也可同 prompt 輪一起上黑箱。
- **在 (c) 落地前，硬版只能宣稱治 (b)；不要假裝黑箱會過含-msg1 的 gate。**

### 硬版 invariants（碰丟段路徑＝上輪紅線，逐條守）
- **INV-H1 扣費時機不變**：驗證**絕不**移動/重複扣費。charge 仍在 decision/recommendation 觸發，早於 reply_option 的 segment 驗證。
- **INV-H2 不製造已扣費無輸出**：選中風格 reply 若驗證不過，走既有 `STREAM_INCOMPLETE_REPLY_OPTIONS`／error 路徑（emitDone 已守「已扣費無輸出」紅線），**不**新增靜默 done。
- **INV-H3 per-style 失敗隔離**：非選中風格未達下限**不得**阻斷選中風格或 done 事件。
- **INV-H4 inventory 狀態保留**：硬版需在 reframer 保留 inventory 的 disposition map（sourceIndex→接/併/略）直到 reply_option 到貨比對。**現在 inventory 只 ride pre-charge buffer 被 emit、未存 state**——這是硬版第一個新增 state，須 TDD 覆蓋（含 inventory 缺席時的 fallback：無 map＝退回 soft 行為不驗證，絕不誤殺）。
- **INV-H5 合法段 sanitize 不變**：只「加」一道下限/涵蓋率閘，**絕不**改既有合法 segment 怎麼被 `sanitizeReplySegments` 處理。
- **INV-H6 略球誤判出範圍**：server 只能驗「segments⊆接/併」＋「count≥下限」；catching 略球＝模型分類問題，見 (c)。

### Failure matrix（她連發 ≥4 句，下限 = min(3, 接+併 數)）
| inventory 接/併 數 | reply 段數/來源 | server 動作 |
|---|---|---|
| 4 接 | 2 段（皆接球） | **REJECT 選中風格** → INCOMPLETE/retry（未達下限）|
| 4 接 | 3 段（皆接球） | PASS |
| 4 接 | 3 段，1 段來自略球 | REJECT or 丟該段（丟後可能跌破下限→連帶 REJECT）|
| 2 接（真的球少） | 2 段 | PASS（下限例外：接數<3，不能要求超過真球數）|
| 0 接/inventory 缺席 | — | 退回 soft 不驗證（INV-H4 fallback），絕不誤殺 |

### TDD 順序（新 session）
1. 🔴 reframer 保留 inventory disposition map（含缺席 fallback）。
2. 🔴 選中風格 segments 全來自接/併、count≥min(3,接併數) → PASS；否則 → 既有 INCOMPLETE/error（不新增 code，重用）。
3. 🔴 非選中風格失敗隔離、不阻斷 done（INV-H3）。
4. 🔴 段來自略球 → 丟段或 REJECT 的明確契約（碰 `sanitizeReplySegments`，最高風險，先寫 invariant 再改）。
5. 🟢 全綠＋deno check → 黑箱重打 golden（驗治 (b)：≥3＋msg4）→ Codex 雙審（必，碰丟段路徑＋扣費語意）。
6. (c) 依 Eric 拍板另案處理（改 golden payload 或改 gate 定義）。
