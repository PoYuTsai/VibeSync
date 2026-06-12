# 方案二 Phase 1 設計定稿 — 分析輸出 Golden 形狀重構

> 2026-06-12 Eric 拍板。實作 session 以本檔為錨點，搭配 queue OPEN item。
> 高風險區：AI prompt + Edge schema + 扣費路徑。完成後必送 Codex 雙審。

## 背景

#12 調查結論：stream 事件協議從未實作分段——`stream_prompt.ts:31,34` 只定義 flat
`message`，分段規格只在 finalResult 一句話帶過且與 compact 指令打架。golden 影片
（ChatGPT 同截圖輸出）品質勝過產品現狀，Eric 定位 P0。

Prompt 價值重定義：**管格式是稅；教判斷 + 餵專有 context 才是資產**。
核心 goal：回覆品質至少不輸裸 ChatGPT/Claude，再加上 domain knowledge 的護城河。

## 已拍板決策

| # | 決策 | 內容 |
|---|------|------|
| D1 | 球判準 | 預設每顆有內容的球都接；純貼圖/單 emoji/純時間戳不算獨立球、併鄰球；上限 **5 段**（原 3） |
| D2 | Bind 形狀 | 「瘦推薦卡」案：字只寫一次在 selected style 的 reply_option；reframer 扣卡回填（見下） |
| D3 | 相容策略 | server→client 契約凍結：事件順序與形狀對 App 不變，build 256 零影響；Phase 1 純 server 出貨 |
| D4 | flat message | 模型不再寫；server 以 segments join 合成相容欄位 |

## 五件套設計

### 1. 球判準重寫（`index.ts` 選球規則區，~:1411-1441 + :1135）

「通常只選 1-2 顆、最多 3 顆」→「每顆有內容的球都接，上限 5；貼圖/單 emoji/純時間戳
併進鄰球不佔額度」。同步更新 Multi-Message Reply Reminder 的 cap。

### 2. Marker 語意進 prompt

A/B 實證：裸 marker `[Missed video call]` 被模型判「別提」；同語意自然語言則正確優先接。
加教學小節，用人話解釋每個 OCR marker 的語意：

- `[Missed video call]` = 她主動打來、高價值升溫訊號，必須接
- `[Photo]` = 分享慾、想被回應的訊號
- （實作時盤點 layout_parser 全部 marker 種類，逐一給語意）

### 3. Stream 協議 v2（`stream_prompt.ts`）

- `reply_option` 規格改以 `segments[]` 為一等公民：每段 `sourceIndex` / `sourceMessage` /
  `reply` / `reason`。模型不寫 flat `message`（D4）。
- 加 few-shot：一行多球 reply_option 的 JSONL 範例。
- `recommendation` 瘦身：`selectedStyle` + `reason` + 「她可能怎麼回」，不再帶回覆全文。
- 模型端事件順序：decision → 瘦 recommendation → reply_option[selected] → 其餘 ×4 → …

**主 prompt 負資產→正資產全掃**（Eric 追加）：
- 砍格式稅：JSON 形狀指令、互相打架的 compact 要求、stream contract 已管的事不重複管
- 保判斷資產：選球規則、中文問句功能判讀、長度分寸——只強化不刪
- 加餵料：marker 語意、對象歷史 context
- 範圍控制：全面 few-shot 化是另案（已拍板分開），本輪只做砍稅 + 加料

### 4. Bind 執行細節（`reframer.ts`）

reframer「扣卡回填」：
1. 收到瘦 recommendation → 驗 selectedStyle / reason → **buffer 住不轉發**
2. 收到 reply_option[selected]（含 segments）→ 把 join 後全文 + segments 塞回推薦卡
3. 按舊順序轉發：enriched recommendation → reply_option[selected] → …
4. App 收到的事件順序與形狀 = 今天（D3）

扣費：safety 檢查（guardrail patterns）改在回填後跑，檢查對象是 join 後全文——
驗的內容跟今天相同，只是時機後移。decision 仍是第一扣費錨點（不變）。
selected reply_option 始終沒到 → 走既有 INCOMPLETE 錯誤路徑；**buffer 中的瘦卡
不得造成「已扣費但無輸出」**（測試重點）。

assembler：finalRecommendation 的 pick/content/replySegments 一律從 selected
reply_option 回填，廢除雙軌。

### 5. Contract 堵漏（`post_process.ts:216-227`）

模糊匹配修復加「唯一性」：一段 sourceMessage 經 containment 同時匹配 ≥2 顆不同的球
（「球A / 球B」併球指紋）→ 不放行，回填正典單球原文或丟段。
`matchBallIndex` 改回傳全部匹配，>1 視為 ambiguous。

## 成本 / 延遲

- output token：原估 +60~100%，bind 砍掉雙軌後修正為 **+40~70%**（≈ +$0.015/次）
- 大卡（核心動線）到貨時間 ≈ 不變；整份分析完成 46-52s → ~60s，增量集中在
  摺疊區與底部報告，stream 逐卡片 UX 吸收
- 模型呼叫次數不變

## 測試與把關

- 每件先紅燈測試再實作（TDD）；reframer 扣卡回填鏡射 prod 事件序列測
- contract ambiguous match 紅燈測試（用 #12 調查的實際併球輸出當 fixture）
- analyze-chat Deno 全測綠
- prod 黑箱復測（手法：memory `p0-stream-reply-option-fix-2026-06-12`，測試帳號 + curl stream）
- Codex 雙審 APPROVED 前不得宣稱 dogfood safe
- 動 prompt 必雙審（球判準 / marker / 砍稅全在內）

## Close Condition（同 queue item）

Phase 1 land + Deno 測試綠 + Codex 雙審 APPROVED + Bruce 實測有感。
Phase 2（5 風格槽 → 策略意圖選項 client UI）另立 item、需 brainstorming + Eric 拍板。
