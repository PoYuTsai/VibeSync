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
