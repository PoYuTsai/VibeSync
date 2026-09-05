# 練習室 Phase 5「上線前補洞」實作計畫

- 日期：2026-09-05
- 程式基線：`main` `74f14c76`（含 4.5a～4.5i、4.6 三把小刀、4.7 空白守門。原稿對 `22c9ef90` 寫，2026-09-05 已兩次 rebase 並逐條重核行號）
- Phase 4.6（gameDebrief／聊天端 gameSnapshot 補 `inviteStage`、`check_out` 結構後檢查改注入改寫指令＋telemetry `checkOutRewriteInjected`）與 4.7（空白回覆守門）**已上 main**（`336e27b1`／`74f14c76`）；相關行號已重核：check_out 段 `conversation_agency.ts:1659-1745`、`partnerStatus` `handler.ts:5324-5336`。
- 本文狀態：**Eric 2026-09-05 晚上定案**。Phase 5 ＝ **五包**（WP1 週報、WP2 成本保險絲、WP3 續聊敘事記憶、WP4 UI/UX 檢視、WP5 收尾導向檢討），彼此獨立、無依賴。其餘原案（計費第二次扣費、方案深度分層、提示換 Haiku、LINE 式互動整套、玩家傳圖、她傳圖照片庫、對抗式評測、分類器三刀）**全部進附錄凍結區**，上線後看四週週報再議。**PR #71 在五包做好、驗證好之後關閉。**
- 產出性質：實作計畫；本文件本身零程式改動、零模型呼叫
- 讀者：Bruce（前端 client）與 Eric-AI（server／工具）
- 前一階段：`docs/plans/2026-09-03-practice-conversation-agency-plan.md`（Phase 0–4.5i）

---

## 1. 目標／非目標／黃金法則

### 1.1 這一階段要做完的事：上線前補洞

Phase 0–4.5i 把「她像不像真人」做到了模型服從率的天花板；練習室的核心（她像真人、模式／提示／檢討／計費）已經完整。現階段的目標是**上線**，Phase 5 只補上線前少了會出事的洞：

1. **看得見**：每週一支唯讀腳本，上線後四週的真實分佈是所有後續決定的依據（WP1）。
2. **燒不穿**：當日 Anthropic 花費超標自動退回 DeepSeek，沒有保險絲的東西不上 production（WP2）。
3. **她記得**：續聊時她記得上一場聊過什麼——欄位、prompt 路徑、守門都已存在，只差寫入（WP3）。
4. **看起來熟**：手機端對標 LINE 做一輪檢視與小優化，不動行為（WP4）。
5. **收得了尾**：她已讀不回或走人時，App 導向檢討而不是只多一行字（WP5）。

### 1.2 黃金法則（三條，衝突時照這個順序）

1. **像真人**：任何改動都不能讓她變回「有功能感的機器人」。收尾訊號是她走了，不是系統彈窗。
2. **免費玩得到、而且玩得到檢討**：免費使用者要能完整走完一次「聊 → 卡住 → 提示 → 檢討」，這是獲客動作，不是試用殘缺版。
3. **成本封頂**：每一個模型呼叫都要有旗標，而且要有一道當日花費保險絲。

### 1.3 非目標（這一階段明確不做；2026-09-05 定案凍結，細節見附錄）

- **LINE 式互動整套**：長按選單、引用回覆、收回、「這句不像真人」回報鈕。
- **玩家傳圖**（含聊天截圖當一般照片）：UGC 會把整張 App Review 表（審核、檢舉、刪除、隱私聲明）拉進來，現階段不做。
- **她傳圖／預生照片庫**（GPT Image 2 image-to-image、500 張資產、驗臉 gate）。
- **方案深度分層**（`limitsForTier`、tier 查表、第 11 回合第二次扣費、Free 10 回合）。
- **提示換 Haiku**（維持 Sonnet 5，退路 Haiku）。
- **對抗式評測**與**分類器三刀**（承認不改口／性暗示是非題／指令注入）。
- 影片、語音（傳與收都不做）。
- 重寫 `game_fsm.ts`／`game_state.ts` 的責任邊界。
- ~~「一般」模式（standard）的分類器與狀態補齊~~ → 4.5b 已補齊（`PRACTICE_STANDARD_AGENCY_CLASSIFIER`，production 已開），standard 走同一套，見 §3-D。

凍結理由（Eric 2026-09-05）：Phase 5 原案有一半的決定沒有真實使用者數據可依；先上線、拿四週週報，再決定要不要復活。

---

## 2. 已定決策（Eric 2026-09-05 拍板，不重新討論）

> D1–D6、D10、D11 已於 2026-09-05 晚上凍結，原文搬到附錄凍結區。以下只留與五包相關的決策。

### D7　UI/UX 全面檢視

三個面向，產出**檢查清單與 before／after 截圖要求**，不寫死設計稿：

1. **LINE 熟悉度**：泡泡間距、時間戳、已讀／輸入中指示、深色模式。
2. **功能可發現性**：首次使用提示、空狀態、提示鈕剩餘顆數。
3. **美感**：字級、行高、色彩對比。

（原案的「圖片泡泡」「長按回饋」「她看得到照片的 affordance」隨傳圖與長按選單一起凍結，2026-09-05。）

### D8　成本保險絲

Anthropic 當日花費超過設定值（Edge 端以 telemetry 累加或 KV 計數）→ **強制退回 DeepSeek**；旗標可手動覆蓋；告警一行 log。（原案的「關閉圖片輪」隨傳圖凍結，2026-09-05。）

### D9　可觀測：每週一支唯讀腳本

Management API 拉練習室 telemetry：場次、回合分佈、介入率、`chatModel` 分佈、fallback 比率、每場成本估算、`check_out` 結構後檢查比率。輸出 markdown 進 `docs/reports/`（目前這個目錄不存在，本包建立）。（原案的「圖片張數」「回報鈕數量」隨傳圖與回報鈕凍結，2026-09-05。）

### D12　修帳

- **已在 4.5c 完成，Phase 5 無事可做**：單價唯一來源改成 `tools/practice-agency-eval/pricing.ts`——`HAIKU_4_5_PRICING`（`:59`，官方 `$1／$5`）與 `SONNET_5_PRICING`（`:73`，官方 `$2／$10`），cache 兩格用官方乘數推（`:32-33`）。`run_agency.ts` 自己抄的那份 `$0.8／$4` 已刪。

### D13　Game check_out 進檢討需要 client 訊號

server Response 要有一個訊號讓 client 導向檢討。
- 現況（4.5a／4.5c 之後）：`check_out`／`read_only` 已是 policy 的 forced act（`conversation_agency.ts:93-94`），Response 已有選填 `partnerStatus: "checked_out" | "read_only"`（`handler.ts:5324-5336`，**只在 Game** 時給），client 已解析（`practice_chat_api_service.dart:1396`）但只多顯示一行、不導向。WP5 要做的是放寬條件與導向，見 WP5（§9 C6 已過時）。

### D14　成本表（每場，USD；匯率取 1 USD ≈ NT$32）——保留當參考

> **2026-09-05 凍結後的讀法**：分層與傳圖都凍結了，目前 production 實際只有「**聊天（mixed）＋提示 Sonnet＋檢討 Sonnet**」這一列成立；下表的 Free 10 回合、提示 Haiku、玩家圖、她傳圖、第二次扣費都是原案的假設，留著當復活時的參考，**不是現行成本**。

單價來源：Haiku 4.5 官方 `$1／$5` per MTok（D12 修帳後）、**Sonnet 5 官方 `$2／$10`**（claude.com/pricing，2026-09-05 核對；程式內 `pricing.ts:73` `SONNET_5_PRICING` 已有，4.5c）、cache read 0.1×、cache write 1.25×；DeepSeek 聊天 `$0.0000294`／次、分類器 `$0.0002027`／次（`tools/practice-agency-eval/README.md` §4.3 實測）；mixed 聊天每場 `$0.0436`（4.3 基準 68.5% Haiku）～`$0.0648`（4.4 刻意堆疊上限 74.0%）。

單次呼叫外推（輸入 9k token，其中 8.1k 命中 cache）：

| | 輸出 tokens | Haiku 4.5 | Sonnet 5 |
|---|--:|--:|--:|
| 提示 | ~400 | **$0.0037** | $0.0074 |
| 檢討 | ~1,200 | $0.0060 | **$0.0154** |

| 項目 | Free（10 回合） | Starter（20 回合） | Essential（20 回合） |
|---|--:|--:|--:|
| 聊天（含分類器） | $0.0023（純 DeepSeek） | $0.0436 ～ $0.0648 | $0.0436 ～ $0.0648 |
| 提示（Haiku，原 D3 後） | 1 × $0.0037 | 3 × $0.0037 = $0.0111 | 5 × $0.0037 = $0.0185 |
| 檢討（Sonnet 5） | 1 × $0.0154 | 1 × $0.0154 | 1 × $0.0154 |
| 玩家圖（審核 $0.001 ＋ 視覺 $0.0016） | — | 3 × $0.0026 = $0.0078 | 5 × $0.0026 = $0.0130 |
| 她傳圖 | — | — | ≈ $0（預生，攤提見附錄 D5） |
| **典型（4.3 基準）** | **$0.0214** | **$0.0779** | **$0.0905** |
| **最壞（4.4 上限 ＋ 額度全用滿）** | **$0.0214** | **$0.0991** | **$0.1117** |
| 折台幣（典型／最壞） | NT$0.7 | NT$2.49 ／ NT$3.17 | NT$2.90 ／ NT$3.57 |

每則收入（月繳價 ÷ 月額度）：Starter `590 ÷ 300 = NT$1.97`、Essential `1290 ÷ 800 = NT$1.61`。原案一場練習扣 1–2 則：

| | 一場收入（扣 2 則） | 典型成本 | 最壞成本 | 典型毛利率 | **最壞毛利率** |
|---|--:|--:|--:|--:|--:|
| Free | NT$0（獲客） | NT$0.7 | NT$0.7 | — | **−100%（NT$0.7／場獲客成本）** |
| Starter | NT$3.94 | NT$2.49 | NT$3.17 | +37% | **+20%** |
| Essential | NT$3.22 | NT$2.90 | NT$3.57 | +10% | **−11%** |

原案的結論（保留）：Sonnet 5 從 `$3／$15` 的外推改成官方 `$2／$10` 之後，三個方案都往上抬了一格——Starter 最壞從 +14% 變 +20%，Essential 最壞從 −18% 變 **−11%**，但號誌沒有變綠。凍結之後這張表的用途變成：WP1 週報的每場成本估算要能對回這裡的單價，WP2 保險絲的預算值要從這裡推。

檢討是所有方案的最大單一模型支出：佔 Free 一場成本的 **72%**、Starter 的 16–20%、Essential 的 14–17%。檢討留 Sonnet 5，這筆帳要在 WP1 週報看得見。

---

## 3. 待決事項——2026-09-05 定案

- [x] **D.「一般」模式（standard）→ 納入這套。**（事實陳述）
  4.5b 已補齊 standard 的每輪分類器與持久化狀態（`PRACTICE_STANDARD_AGENCY_CLASSIFIER`，production 9/5 下午已開），`chatModelFor` 第 6 參數 `standardAgencyClassifier` 開著時 standard 也走 mixed（`conversation_agency.ts:1543-1563`）。五包對三種模式一體適用，沒有 standard 例外。

- [x] **E. 已讀不回的更強版本（伺服器真的不回）→ 定案：不做，先用「（已讀）」文字。**
  真的不回是唯一會讓使用者以為 App 壞了的功能；先在 WP4 把「（已讀）」這個視覺語言立起來、看使用者讀不讀得懂，再談要不要讓她真的沉默。

- [x] **F. 連續越界計入「已讀」允許 → 定案：`userOverEscalated` 計入，`gameGreasy` 不計入。**
  兩者在 `turn_response_plan.ts:237` 目前被當同一件事（都併進 cautious），但語意不同：`userOverEscalated` 是玩家往界線推，已讀是合理反應；`gameGreasy` 是玩家講話油膩（Game FSM 的失敗狀態），那是**該被教練指出來的技術問題**，用沉默處理等於把教學機會丟掉。

（A 免費額度、B 她傳圖門檻、C 驗臉 gate、G Starter 沒臉兩張：隨對應功能凍結，原文在附錄。）

---

## 4. 工作包 WP1–WP5

規則（照 `AGENTS.md`）：**一包＝一個 PR＝一個一句話講得完的目的**，可獨立測試、合併、還原。沒有行數上限。合併一律 Squash Merge。每次交接換一個 next-owner label。

**分工（定案）**：伺服器全歸 Eric-AI，手機端全歸 Bruce，體感驗收由 Eric。Bruce **現在就能開 WP4**。

### 依賴表：五包彼此獨立

| 包 | owner | 依賴 | migration | 旗標 |
|---|---|---|---|---|
| WP1 週報腳本 | Eric-AI | 無 | 無（唯讀） | 無 |
| WP2 成本保險絲 | Eric-AI | 無 | **有**（`practice_chat_daily_cost`，五包裡唯一一個） | `PRACTICE_COST_FUSE_DAILY_USD` |
| WP3 續聊敘事記憶 | Eric-AI | 無 | 無 | `PRACTICE_MEMORY_SUMMARY_WRITE` |
| WP4 UI/UX 檢視 | **Bruce** | **無** | 無 | 無 |
| WP5 收尾導向檢討 | Eric-AI（server）＋ Bruce（client） | 無 | 無 | `PRACTICE_SESSION_END_SIGNAL` |

任何一包可以先開、先合、先關，不用等別包。唯一的排程限制是 §7 第 4 條：**一次只開一個旗標**。

---

### WP1　週報腳本（tools）

**目的**：每週一支唯讀腳本，把練習室 telemetry 拉成 markdown。上線後四週的週報是附錄凍結區要不要復活的唯一依據。

| | |
|---|---|
| owner | Eric-AI |
| PR | 獨立，直接對 `main` |
| label | `next:eric-ai` |
| 依賴 | 無 |

**改哪些檔**：新檔 `tools/practice-weekly-report/report.ts`（Deno，`--allow-net=api.supabase.com`，**唯讀 Management API**）；新目錄 `docs/reports/`。

**輸出欄位（全部用既有 telemetry 欄位，不依賴任何新欄位）**：
- 場次（`practice_chat_succeeded` 事件數，按 `practiceMode`）。
- 回合分佈（直方圖 1–20，`MAX_AI_REPLIES = 20` 是現行上限）。
- 介入率（agency 決策非 `none` 的比率）。
- `chatModel` 分佈（`deepseek`／`haiku`）與 `chatModelFallback` 比率（`handler.ts:5123`）。
- 每場成本估算：用 `chatModelUsage` 四格 × `tools/practice-agency-eval/pricing.ts` 的單價（`estimateCostUsd`／`HAIKU_4_5_PRICING`／`SONNET_5_PRICING`），提示與檢討各自一列。
- `check_out` 結構後檢查：`checkOutStructuralFail` 比率（4.5g，main 已有）；`checkOutRewriteInjected` × `checkOutStructuralFail` 交叉比率（`checkOutRewriteInjected` 是 4.6 欄位，main 已有）。
- 提示與檢討使用率（`hintUsedCount`、`practice_chat_debrief_succeeded` 事件數）。

**損益表**：每個方案的付費人數、平均每人每月練習場數、練習室成本佔該方案收入的比例（成本＝場數 × 每場成本估算，收入＝該方案月費 × 付費人數）。**付費人數在 RevenueCat，不在 Supabase telemetry，第一版由 Eric 手填**（腳本留 `--paid-starter=N --paid-essential=N` 兩個參數，缺就只印成本欄）。

**驗收**：手跑一次產出 `docs/reports/2026-09-XX-practice-weekly.md`，成本欄能跟 Anthropic console 當週總帳對得起來（誤差 < 10%）。

**成本**：零。不 commit 報告本身以外的任何東西；腳本絕不寫 DB。

**旗標**：無。

---

### WP2　成本保險絲（server）

**目的**：Anthropic 當日花費超標時自動強制 `deepseek`。（原稿的「修帳」半包已在 4.5c 做完，見 D12。）

| | |
|---|---|
| owner | Eric-AI |
| PR | 獨立，直接對 `main` |
| label | `next:eric-ai` |
| 依賴 | 無 |

**改哪些檔**
- 新檔 `supabase/functions/practice-chat/cost_fuse.ts`：純函式 `shouldDegrade(spentUsdToday, budgetUsd)` ＋ 一個以 `practice_chat_daily_cost` 表（`day date primary key, spent_usd numeric`）累加的 client。累加來源＝既有的 `chatModelUsage` 四格（`callClaude` 的 `onUsage` 已經在記）。
- `handler.ts`：`chatModelFor` 之前先問保險絲，燒斷就強制回 `deepseek`。
- 單價直接 import `tools/practice-agency-eval/pricing.ts` 的 `estimateCostUsd`／`HAIKU_4_5_PRICING`／`SONNET_5_PRICING`（4.5c 建好的唯一來源），不要在 Edge 端再抄一份。
- **新 migration**：`practice_chat_daily_cost` 表。**這是五包裡唯一有 migration 的包**：migration 必須先在 production 驗證完成，才准把 Edge code 推 `main`（`AGENTS.md` 硬規則）；**絕不 `supabase db push`**，走 `docs/shared-agent-rules.md` 的定向 migration 程序。表是純加法，關旗標後沒人讀，資料留著不影響。

**資料契約**：telemetry 新增事件 `practice_chat_cost_fuse_blown`，payload `{ day, spentUsd, budgetUsd }`，一天最多一筆（用 `spent_usd` 跨過門檻的那一次寫）。告警＝一行 `console.warn`。

**驗收**
- 設 `PRACTICE_COST_FUSE_DAILY_USD=0.0001` 打一場 → 第二輪起 `chatModel` 全是 `deepseek`，事件恰好一筆。
- 旗標留空 ＝ 保險絲完全不啟動，零 DB 讀寫。
- **保險絲燒斷不能讓對話失敗**：退回 DeepSeek 是降級不是報錯。
- 提示與檢討不受保險絲影響（它們沒有 DeepSeek 退路；燒斷後仍走 Sonnet→Haiku，但成本會被記進當日累加，第二天自然重算）。

**成本**：每輪多一次極小的 DB upsert；不新增模型呼叫。

**旗標**：`PRACTICE_COST_FUSE_DAILY_USD`（數值；空／未設 ＝ 關）。手動覆蓋＝把它設成很大的數或拿掉。

---

### WP3　續聊敘事記憶（server）

**目的**：讓她記得上一場聊過什麼。用檢討那支 Sonnet 呼叫順手吐一段「她記得的事」寫進既有的 `memory_summary`，下一場開頭餵回去。

| | |
|---|---|
| owner | Eric-AI |
| PR | 獨立，直接對 `main` |
| label | `next:eric-ai` |
| 依賴 | 無 |

**現況（2026-09-05 實查 main）**
- 手機端 Hive 存整場，每次請求只送最近 `kPracticePromptRecentTurns = 80` 則（`practice_chat_providers.dart:43`）；超過 80 則的部分手機端自己剪成殘片——`_memorySummaryForPrompt`（`:2639-2656`）取最舊 8 則＋最近 16 則（`_memorySummarySample`，`:2658-2666`）、每則截 48 字、總長 800 字，放進 request 的 `memorySummary`。
- **伺服器根本沒把那段殘片餵進 prompt**：`request.memorySummary` 只用在續聊判定（`handler.ts:1024`）與 telemetry（`:4397`）。prompt 吃的是 `promptMemorySummary = relationshipThreadState?.memorySummary`（`:2544`），來源是 `practice_relationship_threads.memory_summary`（讀取在 `:1043-1051`）。
- 那個欄位**從未寫入**：migration `20260708130000_practice_game_state_relationship_threads.sql:87-88` 建了 `memory_summary TEXT`（≤ 1000 字）、`:128` 的 RPC `upsert_practice_relationship_thread` 收 `p_memory_summary`（`:200` 用 COALESCE 保留舊值），但 `handler.ts` 呼叫它（`:1339`）時**沒有帶 `p_memory_summary`**，所以永遠 NULL。
- 餵入路徑已經存在且有守門：聊天 prompt 的 `memorySummaryPrompt`（`prompt.ts:132-138`，untrusted hidden evidence，Reality Anchoring 規則在 `:120`）、檢討的 `debriefMemorySummaryPrompt`（`:168-175`）。**零 migration、零新 prompt 路徑。**

**做法**
- debrief 那支 Sonnet 呼叫（`handler.ts:3998-4157`）已經讀整場逐字稿；在輸出 schema 多一個欄位 `memorySummary`（≤ 1000 字，第三人稱、以她的視角寫「她記得的事」：聊過的話題、他透露的事、她對他的印象、未完的約定），寫進檢討結果後用 `upsert_practice_relationship_thread` 帶 `p_memory_summary` 存回。
- 下一場 `fetchRelationshipThreadState` 讀出來就自動走既有 `memorySummary` prompt 路徑，一行都不用加。
- 手機端那段 8＋16 殘片維持原樣（反正伺服器不讀），**Bruce 零改動**。

**資料契約**：Response（debrief）加 `memorySummary`（僅供 telemetry／除錯，client 不用讀）；`practice_relationship_threads.memory_summary` 從此有值。telemetry `practice_chat_debrief_succeeded` 加 `memorySummaryChars`。

**驗收**
- 同一位連玩兩場：第二場她的開頭能接住第一場的話題（10 場人工抽查 ≥ 7 場），且**不會**因此捏造第一場沒發生的事（Reality Anchoring 守門既有，`prompt.ts:120`）。
- 檢討輸出多一個欄位不影響檢討本文；欄位缺失／超長 → 只跳過寫入，不讓檢討失敗。
- 旗標 `off` ＝ 不寫 `p_memory_summary`、不加 schema 欄位，四面等價 golden。

**成本**：零新呼叫；檢討輸出多 ≤ 1000 字 ≈ 每場多 `$0.005`（Sonnet 5 輸出價）。**每輪聊天不多花錢**（讀 memory_summary 走既有 prompt 位置，已在 cache 前綴之外的尾巴）。

**旗標**：`PRACTICE_MEMORY_SUMMARY_WRITE`（`off`／`true`，預設 `off`）。

---

### WP4　UI/UX 檢視與小優化（client）

**目的**：對標 LINE，把練習室從「能用」做到「熟悉」。純視覺，不改行為、不改契約。

| | |
|---|---|
| owner | **Bruce** |
| PR | 獨立，直接對 `main` |
| label | `next:bruce` |
| 依賴 | **無**（現在就能開） |

**改哪些檔**：`lib/features/practice_chat/presentation/screens/practice_chat_screen.dart`（3,380 行，目前泡泡、提示鈕、扣費文案、`sessionComplete` 都在這一支）與同目錄 `widgets/`。**這一包是唯一准許重構那支檔案的機會**——如果泡泡與輸入列要拆出 widget，在這裡做（§7 第 3 條：拆兩個 commit）。

**檢查清單（驗收就照這張表逐項打勾，附 before／after 截圖）**

LINE 熟悉度：
- [ ] 泡泡間距：同一人連續泡泡 4dp、換人 12dp
- [ ] 時間戳：只在換分鐘或換人時顯示，靠泡泡外側
- [ ] 「輸入中」指示：她生成期間顯示三點動畫，不是全螢幕轉圈
- [ ] 「已讀」指示：玩家訊息送達後顯示（§3-E 定案先用文字；4.5a 的 `read_only` 回覆已存在，這是它的視覺語言）
- [ ] 深色模式：全部新元件逐項對照

功能可發現性：
- [ ] 首次進入練習室的一次性提示（三句話以內）
- [ ] 空狀態：還沒有訊息時說得出「這裡可以做什麼」
- [ ] 提示鈕顯示**剩餘顆數**，不是只顯示「提示」。**用既有欄位，零 server 改動**：Response 已回 `hintUsedCount`（`handler.ts:5329`，prefetch 路徑 `:3544`），client 已有 `kMaxPracticeHintsPerRound = 5`（`practice_chat_providers.dart:35`）與 `hintLimitReached`（`:213`），剩餘＝`kMaxPracticeHintsPerRound - hintUsedCount`。（原稿指的 `handler.ts:2604-2605`／`:3250` 是 server 內部的 `maxHints`／`hintsRemaining`，不回 client，2026-09-05 grep 修正。）
- [ ] 扣費文案統一成單純「**本場已扣 1 則**」語意（沒有第二次扣費），`practice_chat_screen.dart:1713-1714`（已是「本場已扣 1 則，還能聊 N 則」）與 `:1281`、`:2711` 三處對齊，不要出現「超過 N 則會再扣」

美感：
- [ ] 字級／行高：泡泡內文 15/22，時間戳 11
- [ ] 色彩對比：全部文字對背景 ≥ 4.5:1（深色模式也要量）

（原案的「圖片泡泡」「長按回饋 haptic」「她看得到照片的 affordance」隨傳圖與長按選單凍結，2026-09-05 刪。）

**驗收**：上表全打勾 ＋ 每個大項一組 before／after 截圖進 PR。**不寫死設計稿**，Bruce 有實作自由。

**成本**：零。

**旗標**：無（純視覺）。

---

### WP5　收尾訊號進檢討（server ＋ client）——2026-09-05 定案

**目的**：policy 打出 `check_out` 或 `read_only` 時，回一個訊號讓 App 導向檢討。**不綁 Game 的 P5**，挑戰難度也適用；Bruce 端只需接一個欄位。

| | |
|---|---|
| owner | Eric-AI（server）＋ **Bruce**（client 導向） |
| PR | 一個（改動小），Eric-AI 開，client 那半 Bruce 接 commit |
| label | server 完成後 `next:bruce` |
| 依賴 | 無 |

**現況（main `8d15cc57`）**
- `check_out`／`read_only` 已是 policy 的 forced act（`conversation_agency.ts:93-94`；4.5a 刀 3）。強制結束**只給挑戰難度或 Game**（`:1057`，`allowsCheckOut` `:944`），policy 打出來的當輪 `forcedAct` 就是訊號來源，不必再看 FSM phase。
- Response 已有選填 `partnerStatus: "checked_out" | "read_only"`（`handler.ts:5324-5336`，4.5c 刀 3），但條件多綁了 `practiceMode === "game"`；client 已解析（`practice_chat_api_service.dart:1396`），目前只多顯示一行、不自動結束、不鎖輸入。
- forced `check_out` 結構後檢查（4.5g）與 4.6 的改寫指令注入在 `conversation_agency.ts:1659-1745`（main 已有）。

**改哪些檔**
- `handler.ts:5324-5336`：把 `partnerStatus` 的 Game-only 條件放掉——凡 agency `on` 且當輪 `forcedAct` 是 `check_out`／`read_only` 就給（挑戰難度自然納入，因為 `allowsCheckOut` 只在那兩種情形為真）。**不新開 `sessionEndedBy` 欄位**，沿用既有 `partnerStatus`，Bruce 端零新 parsing。
- client：收到 `partnerStatus` 非 null → 顯示收尾提示並提供「看教練拆解」入口（導向檢討），而不是只多一行字。

**資料契約**（既有，不改形狀）
```jsonc
{
  "partnerStatus": "checked_out" | "read_only"   // 選填；只在 forced 那一輪出現，其他情形連 key 都沒有
}
```
既有的 `sessionComplete` boolean **保留不動**（達回合上限；client 舊版相容）。

**驗收**：挑戰難度或 Game 打到 policy forced `check_out`／`read_only` → Response 帶 `partnerStatus`，App 顯示並導向檢討；beginner／standard 永遠沒有這個 key（`allowsCheckOut` 為 false）；旗標 `off` ＝ 維持 4.5c 的 Game-only 行為，逐位元組不變。

**成本**：零。

**旗標**：`PRACTICE_SESSION_END_SIGNAL`（`off`／`true`，預設 `off`）。

---

## 5. 旗標與回滾

| 旗標 | WP | 值域 | 預設 | 開啟順序 |
|---|---|---|---|---|
| `PRACTICE_COST_FUSE_DAILY_USD` | WP2 | 數值／空 | 空（關） | 先設很大的值觀察累加正確 → 調到真實預算 |
| `PRACTICE_MEMORY_SUMMARY_WRITE` | WP3 | `off`／`true` | `off` | 直接 true（只寫欄位；讀取路徑本來就在） |
| `PRACTICE_SESSION_END_SIGNAL` | WP5 | `off`／`true` | `off` | 直接 true（只管「挑戰難度也給訊號」這一步；Game 的 `partnerStatus` 是 4.5c 既有行為，無旗標） |

WP1（唯讀腳本）與 WP4（純視覺）無旗標。

**回滾鐵則（沿用 Phase 0–4.4）**：每個旗標的 `off` 路徑必須逐位元組等於舊行為，由 `agency_flag_off_equivalence_test.ts` 的四面（`messages`／`response`／`rpc`／`telemetry`）等價 harness 釘住。`shadow` 的契約是「只多記 telemetry」，三面等價 ＋ telemetry 必須不同。

**唯一不能靠關旗標回滾的是 migration**：WP2 的 `practice_chat_daily_cost` 表是純加法，關旗標後沒人讀，資料留著不影響。**絕不 `supabase db push`**，走 `docs/shared-agent-rules.md` 的定向 migration 程序。

---

## 6. App Review／隱私／資料

傳圖凍結後五包沒有 UGC、沒有新的資料型別送給 Anthropic（WP3 的 `memory_summary` 是既有欄位、既有 prompt 路徑，Anthropic 早就收到整場對話）。原案那張 UGC 前置表整段搬到附錄凍結區，玩家傳圖復活時再拿出來。

---

## 7. 風險與停損

1. **保險絲燒斷必須是降級不是報錯（WP2）。**
   停損：`shouldDegrade` 為真只改 `chatModelFor` 的結果，不進任何 throw 路徑；DB 讀寫失敗一律 fail-open（當成沒燒斷、記一行 warn），因為保險絲壞掉的代價是多花錢，不是對話失敗。

2. **記憶摘要不得捏造（WP3）。**
   停損：寫入的是「她記得的事」，讀取走既有 untrusted hidden evidence 位置，Reality Anchoring 規則（`prompt.ts:120`）既有；10 場人工抽查裡任何一場出現第一場沒發生的事就關旗標，改 debrief 那段 schema 說明再驗。

3. **WP4 要動 3,380 行的 `practice_chat_screen.dart`。**
   停損：這一包是唯一准許重構它的機會，但重構與 UI 改動要分成同一個 PR 裡的兩個 commit（先純搬移零行為改動、再改行為），Review 才看得懂。

4. **同時開太多旗標會讓 telemetry 歸因不到。**
   停損：一次只開一個旗標，開完看滿 48 小時的 `chatModel` 分佈與 fallback 比率，再開下一個。這是 Phase 4.4 的既有紀律，Phase 5 不放寬。

---

## 8. 給 Bruce 的三句話摘要

1. **你只有 WP4（UI/UX 檢視與小優化，現在就能開，不依賴任何 server 改動）和 WP5 的手機端半包**（收到 `partnerStatus` 非 null 就顯示收尾提示並導向檢討，沿用你已經解析的欄位，等 Eric-AI 的 server 半包合併後接 commit）。
2. **LINE 式互動整套（長按選單、引用回覆、收回、回報鈕）與雙向傳圖都不做了**，Eric 2026-09-05 定案凍結；WP4 檢查清單裡沒有圖片泡泡、沒有長按，提示鈕剩餘顆數用既有的 `hintUsedCount` 算。
3. **驗收怎麼看**：WP4 是 §4 那張檢查清單逐項打勾 ＋ 每個大項一組 before／after 截圖進 PR；WP5 是在真機上打到她已讀不回或走人時，App 顯示收尾提示並能一鍵進檢討。

---

## 9. 查證結果：與拍板決策衝突或需要修正的地方

寫這份計畫時逐檔查證了 `main@22c9ef90` 的現況，2026-09-05 rebase 到 `8d15cc57` 後逐條重核。C1–C4 都是傳圖相關，隨傳圖凍結搬到附錄；C5（`MAX_DEBRIEFS` 3 → 1）隨分層凍結，不再需要，已刪。C6、C7 已因 4.5a／4.5c 過時，保留為紀錄。

**C6　~~`check_out` 不是程式裡存在的識別字~~ → 已過時（對 `22c9ef90` 成立，`8d15cc57` 不成立）。**
4.5a 刀 3 已把 `check_out`／`read_only` 加進 policy 的 act 集合（`conversation_agency.ts:93-94`），4.5c 刀 3 已在 Game 的 Response 回 `partnerStatus`（`handler.ts:5324-5336`），4.5g 又補了 forced `check_out` 的結構後檢查（`:1659-1745`，4.6 已改）。所以 D13 不需要再「定義 check_out」，WP5 改成「放寬到挑戰難度＋App 導向檢討」。

**C7（非衝突，補充）　~~Sonnet 5 有官方價，但程式內沒有常數~~ → 4.5c 已解。**
`tools/practice-agency-eval/pricing.ts` 現在是單價唯一來源：`HAIKU_4_5_PRICING`（`:59`，`$1／$5`）、`SONNET_5_PRICING`（`:73`，`$2／$10`）、cache 乘數（`:32-33`）、`DEEPSEEK_CLASSIFIER_USD_PER_CALL`（`:108`）。§2 D14 的成本表用的就是這組價。WP1／WP2 直接 import，不要再抄。

---

## 附錄：凍結區（2026-09-05，上線後看四週週報再議）

以下是 Eric 2026-09-05 晚上凍結的原案內容，**原文保留、不刪細節**，之後可能復活。每段開頭標「凍結（2026-09-05）」。

⚠️ **編號注意**：本區的 WP 編號是**原編號**（原 WP1 配額、原 WP2 提示 Haiku、原 WP3 保險絲、原 WP4 週報、原 WP5 LINE、原 WP6 UI、原 WP7 玩家傳圖、原 WP8 照片庫、原 WP9 對抗式、原 WP10 分類器、原 WP11 收尾、原 WP12 記憶），與正文五包的 WP1–WP5 **不是同一套**。本區內部互相引用時沿用原編號；對照正文用這張表：原 WP4 → 正文 WP1、原 WP3 → 正文 WP2、原 WP12 → 正文 WP3、原 WP6 → 正文 WP4、原 WP11 → 正文 WP5。

### 凍結（2026-09-05）　已定決策 D1–D6、D10、D11

#### D1　計費：一場 1 則，第 11 個 AI 回合再扣 1 則

- 維持「一場練習扣 1 則 Coach 額度」。
- **第 11 個 AI 回合成功時再扣 1 則**，一場最多 2 則。
- Free 每場回合上限 10，構造上永遠觸發不到第 2 則。
- App 文案：**「本場已扣 1 則（超過 10 則會再扣 1）」**。
- 現況：`quota_decision.ts` 的 `decideChatGate` 只有 `!ledger.charged` 一個扣費條件；`MAX_AI_REPLIES = 20` 由 handler 以 `p_max_replies` 傳進 RPC，所以上限改常數即生效（RPC 不用重佈）。第二次扣費是**新的扣費點**，要在 RPC 內同一交易處理（見原 WP1）。

#### D2　方案深度（伺服器常數，依 tier 讀取）

| | Free | Starter | Essential |
|---|---|---|---|
| 回合上限／場 | 10 | 20 | 20 |
| 提示／場 | 1 | 3 | 5 |
| 檢討／場 | 1 | 1 | 1 |
| 玩家傳圖／場 | 0 | 3 | 5 |
| 她傳圖／場 | 0 | 0（§3-G 傾向：暫不給） | 1（熱度門檻到才觸發） |
| 混合模型（介入輪＋越界輪＋圖片輪走 Haiku） | 否 | 是 | 是 |

- 檢討上限從程式現況的 `MAX_DEBRIEFS = 3` 改成 **1**（三個 tier 都是 1）。
- 三個常數（`MAX_AI_REPLIES`／`MAX_HINTS_PER_ROUND`／`MAX_DEBRIEFS`）現在都已經是「handler 傳進 RPC 的參數」，改成 tier 查表不需要新 RPC 簽章，只要把單一常數換成 `limitsForTier(tier)`。
- 訂閱方案本身不變：Starter NT$590／月（月 300 則、日 50），Essential NT$1,290／月（月 800 則、日 120），Free 月 30／日 15。

#### D3　提示改用 Haiku 4.5，檢討留 Sonnet 5

- 前置條件：**20 則抽查對比 Sonnet，品質不退才切**。抽查工具沿用 `tools/practice-agency-eval/hint_debrief_spotcheck.ts` 的作法（真呼叫、逐則人工讀）。
- 現況：`handler.ts` 的 hint 與 debrief 都是 `runSingleShot({ models: [CLAUDE_SONNET_MODEL, CLAUDE_HAIKU_MODEL] })`（Sonnet 失敗退 Haiku）。提示改成 `[HAIKU, HAIKU]`？不：改成 `[CLAUDE_HAIKU_MODEL, CLAUDE_SONNET_MODEL]`（Haiku 失敗退 Sonnet），退路方向反過來，維持「絕不回罐頭」的既有鐵則。

#### D4　玩家傳圖

流程：相簿／相機上傳 → **審核**（色情／暴力；模型或第三方，每張約 US$0.001）→ Supabase Storage（**30 天自動刪**）→ 該輪路由 **Haiku 4.5 視覺**（DeepSeek 看不了圖）→ 她看得到並能回應。

- 聊天截圖當一般照片處理，**不走 OCR**。
- 不做影片、不做語音。
- 審核不過：不上傳、不進對話、不扣圖片配額，client 顯示「這張不能傳」。

#### D5　她傳圖＝預生照片庫，不即時生

**第一版資產規格（Eric 2026-09-05 定，原 WP8a 照這個燒）**

- **數量**：每位 **5 張**，100 位 ＝ **500 張**。原案 Eric 與 Bruce **各 250 張**；原 WP8a 有「全交 Bruce 一條線」的建議，**待 Eric 拍板**。
- **生成方式**：**GPT Image 2，image-to-image**；參考圖 ＝ 既有的 `assets/images/practice_girls/practice_girl_NNN.jpg`（100 位都有）。
  - ⚠️ 這條路**不是**既有的 Fal.ai moments 流程，見本區查證衝突 C3。
- **五個標籤，每位各一張**：

| 標籤 | 內容 | 有臉？ |
|---|---|---|
| `selfie_home` | 居家自拍、淡妝、自然光 | **有臉** |
| `out` | 外出／旅遊，半身或全身，有場景 | **有臉** |
| `work` | 符合她職業的工作場景 | **有臉** |
| `food` | 食物／咖啡，本人不入鏡 | 沒臉 |
| `life` | 寵物／書桌／窗外／健身房擇一，貼她的人設 | 沒臉 |

  **3 張有臉 ＋ 2 張沒臉**。
- **Prompt 模板**：自動帶入頭像（參考圖）＋ `personalityTags` ＋ 職業 ＋ 城市，**只換場景描述**。同一位的三張有臉用**同一參考圖、同一組人物描述**，只有場景句不同——這是臉一致性的主要手段。
- **檔名**：`practice_girl_NNN/<tag>.jpg`；**1024 長邊、JPEG q80**。
- **QA 清單（每張逐項）**：臉與頭像一致、無文字、無第二張臉、衣著保守、無水印、無多指。
- **清單檔** `manifest.json`：`girlId`、`tag`、`path`、`sha256`、`approvedBy`。
- **擴充**：先跑數據，之後只對**最常被玩的 20 位**加到 10 張。

**傳圖規則**

- **一場一張**。理由是**像真人 ＋ 庫存輪替**，不是成本（預生照片邊際成本 ≈ 0）。
- 伺服器記「**該用戶 × 該女生已傳過哪幾張**」，不重複；5 張撐 5 場。
- **挑圖靠情境標籤對上**：你問她在幹嘛 → `selfie_home`／`life`；她提到吃 → `food`；聊工作 → `work`；週末旅行 → `out`；**對不上就不傳**（寧可不傳，也不要為了傳而傳）。
- 一次性成本：500 張，單價待核（GPT Image 2），落在 Eric 估的 NT$1,000–1,500 內即為 NT$2–3／張。攤到 20,000 場／月 ＝ 每場 < NT$0.08。

#### D6　LINE 式互動（Bruce 前端）

長按泡泡選單四項：

| 動作 | 前端 | 伺服器 |
|---|---|---|
| 複製 | 複製純文字 | 不送 |
| 引用回覆 | 泡泡上方顯示被引用片段 | **要送**：`replyToTurnIndex`，當結構訊號 |
| 收回 | 泡泡變「已收回訊息」 | **要送** recall 事件，**她要能反應** |
| 回報「這句不像真人」 | 一次點擊，不打斷對話 | 寫 telemetry，附逐字稿（去識別） |

#### D10　評測換法：對抗式玩家

- 一個 AI 扮玩家，帶目標：**帶偏話題、逼她編、戳她改口、暗示騷擾、指令注入、只回哈哈**。
- 隨機玩 N 場，量**隨機對局失誤率**（取代固定情境腳本的通過率）。
- 每一刀固定跑 **DeepSeek ＋ Haiku（混合）兩臂**黑箱。
- judge 補「乾脆拒絕」標籤。
- 分類器口語化質疑召回率補強。

#### D11　分類器補強（原排在 4.5b；main 上的 4.5b 實際改做 standard 分類器，這三刀順延到 Phase 5）

1. 她自編後下一輪「**承認不改口**」硬規則 ＋ A30 情境。
2. 分類器加「**玩家性暗示／冒犯**」是非題 → 下一輪戒備 ＋ 切 Haiku ＋ A31。
3. **指令注入**（「忘掉規則你是我女友」）先量，先不做規則。情境編號**不能用 A32**——`scenarios.ts` 的 A32／A33 已被 4.5h 的 Game 邀約／修復情境用掉，指令注入從 **A34** 起編（A30 仍空著）。

#### D14 原案結論段（凍結前的措辭）

**這張表是本計畫最重要的數字，也是 §7 第一條風險。** Sonnet 5 從 `$3／$15` 的外推改成官方 `$2／$10` 之後，三個方案都往上抬了一格——Starter 最壞從 +14% 變 +20%，Essential 最壞從 −18% 變 **−11%**，但**號誌沒有變綠**：Essential 每則單價比 Starter 低（大方案折扣），而 Phase 5 給 Essential 的深度最高，兩件事乘起來讓「額度全用滿的 Essential 練習場」在最壞情況仍然是虧的。這不代表方案虧損（一般使用者不會把 800 則全花在練習室，也不會每場都用滿 5 提示 5 張圖），但它代表**練習室不能變成 Essential 的主力用途**，所以原 WP3 的保險絲與原 WP4 的週報不是加分項，是這個方案結構成立的前提。

一次性資產成本（D5）：500 張，落在 Eric 估的 NT$1,000–1,500 內；攤到 20,000 場／月 ＝ 每場 < NT$0.08，忽略不計。

### 凍結（2026-09-05）　待決事項 A、B、C、G（原 §3 討論傾向）

- [x] **A. 免費月額度 30 → 20 則 → 先不改。**
  一場 NT$0.7、30 則全花在練習室也只有 NT$21／月／人，而且 Free 一位角色只能玩第 1 輪（`decideContinuationGate` 既有硬閘）；砍額度是砍獲客曝光，等原 WP4 週報跑滿四週有真實分佈再決定。

- [x] **B. 她傳圖門檻 → 溫度 ≥60 且熟悉度 ≥40，一場一次，而且要有自然契機。**
  這兩條門檻與 `relationshipStageFor` 的 `personal_allowed` 邊界同區，不用新開值域；「自然契機」＝ D5 的標籤要對得上，對不上就不傳——沒有契機的照片是功能感，不是真人感。

- [x] **C. Bruce 先驗 5 位角色的臉一致性 → 要，而且是原 WP8a 的硬 gate。**
  臉部一致性在這條管線上沒有任何既有證據（本區 C3）；先生 5 位 × 5 張驗完才准燒剩下 95 位，最貴的錯誤是燒完 500 張才發現不一致。

- [x] **G. Starter 要不要給沒臉的兩張（`food`／`life`）當甜頭？→ 暫不給。**（傾向）
  先讓 Essential 獨享，等原 WP4 週報看到「照片觸發率」的真實數字再決定要不要下放。反對下放的理由仍成立：她傳的第一張如果永遠是食物，「她傳照片」這個驚喜的第一印象就被用掉了。
  實作上兩種都是 D2 表格改一個數字（原 WP1 的 `limitsForTier` 加 `partnerPhotoFaceAllowed`），翻案不影響任何一包的排程。

### 凍結（2026-09-05）　原依賴順序總表與分工原則

**分工原則（原稿討論傾向）**：**伺服器全歸 Eric-AI，手機端全歸 Bruce，付費黑箱與體感驗收由 Eric**。Bruce **現在就能開原 WP6**（UI/UX），不用等任何伺服器改動。資產（原 WP8a）的分工另有建議，見原 WP8。

```
WP1 ──┬── WP2 ── WP12 ── WP3 ── WP4
      │
      ├── WP5 ── WP6
      │
      └── WP7 ── WP8b ── WP8c

WP8a（照片資產）  ← 零 server 依賴，可與 WP5 並行開燒
WP9 ── WP10        （獨立，可與上面任何一包並行）
WP11               （獨立小包）
```

原 WP1 是所有 tier 相關工作的地基（`limitsForTier`），原 WP2/WP5/WP7 都要讀它。原 WP9/WP10/WP11 不碰 tier，可任意插隊。原 WP12 排在原 WP2 之後，因為兩包都動同一支 debrief 呼叫。

### 凍結（2026-09-05）　原 WP1　配額與方案深度（server）

**目的**：把三個寫死的上限常數換成依 tier 查表，並加上第 11 回合的第二次扣費。

| | |
|---|---|
| owner | Eric-AI |
| PR | 獨立，直接對 `main` |
| label | `next:eric-ai` |
| 依賴 | 無（其他包的 parent） |

**改哪些檔**
- `supabase/functions/practice-chat/quota_decision.ts`：新增 `PRACTICE_TIER_LIMITS`（見 D2 表）與 `limitsForTier(tier)`；`MAX_AI_REPLIES`／`MAX_HINTS_PER_ROUND`／`MAX_DEBRIEFS` 保留為 Starter/Essential 的預設值以免動到既有 import，但 handler 全部改讀 `limitsForTier`。`decideChatGate` 回傳加 `shouldChargeSecondPreview`。
- `supabase/functions/practice-chat/handler.ts`：`p_max_replies`／`p_max_hints`／`p_max_debriefs` 八個呼叫點（2677/2678/3018/3568/3574/3578/3854/4827）全部改成 tier 值；另外 `:249`（`rows.length > MAX_DEBRIEFS`）、`:2604-2605`（`maxHints`／`maxReplies` 回 client）、`:3250`（剩餘提示數）三處也讀同一組常數，一起換。
- 新 migration：`commit_practice_chat_turn` RPC 加 `p_second_charge_at`（預設 `NULL` ＝ 舊行為），在 `FOR UPDATE` 同一交易內判斷「`ai_count + 1 = p_second_charge_at` 且 `second_charged = FALSE`」才扣第二則並把 `second_charged` 設 `TRUE`。`practice_chat_sessions` 加 `second_charged boolean NOT NULL DEFAULT FALSE`。
- `MAX_DEBRIEFS` 3 → 1（全 tier）。

**資料契約**

Response（`practice_chat_succeeded` 路徑）新增：
```jsonc
{
  "quotaCharged": 1,              // 這一次呼叫實際扣了幾則（0/1）
  "sessionChargedTotal": 2,       // 這一場累計扣了幾則
  "maxReplies": 20,               // 這個 tier 的回合上限（client 顯示剩餘用）
  "remainingHints": 3
}
```
telemetry `practice_chat_succeeded` 新增：`tier`、`sessionChargedTotal`、`secondChargeFired`（boolean）。

**驗收條件**
- Free 帳號第 10 個 AI 回合後 `sessionComplete = true`，且 `sessionChargedTotal` 永遠是 1。
- Starter/Essential 第 11 個 AI 回合成功時且僅此一次 `quotaCharged = 1`；重試、守門重生、fallback 都不重複扣。
- 第 11 回合的模型呼叫失敗 → 不扣（沿用「失敗一律不扣」鐵則）。
- 已經有 2 次檢討的既有 session：第 3 次 claim 被 RPC 拒絕，回既有的 `PRACTICE_DEBRIEF_LIMIT`，不 500。

**測試與 gate**
- `quota_decision_test.ts` 補 tier 矩陣（3 tier × 4 個上限）。
- migration 契約測試沿用 `debrief_idempotency_migration_test.ts` 的 postgres + source 雙檔慣例。
- 等價 harness：旗標 `off` 時 `messages`／`response`／`rpc`／`telemetry` 四面全等於既有 golden。
- **這是 migration-dependent 的 Edge 改動**：migration 必須先在 production 驗證完成，才准把 Edge code 推 `main`（`AGENTS.md` 硬規則）。

**成本**：零新增模型呼叫。Free 從 20 回合砍到 10 回合，Free 每場成本直接減半。

**旗標**：`PRACTICE_TIER_DEPTH`（`off`／`shadow`／`true`，預設 `off`）。`off` 時 `limitsForTier` 一律回舊常數，逐位元組舊行為。

### 凍結（2026-09-05）　原 WP2　提示改 Haiku（server）

**目的**：提示的主模型從 Sonnet 5 換成 Haiku 4.5，退路方向反轉。

| | |
|---|---|
| owner | Eric-AI |
| PR | Draft parent ＝ 原 WP1（要讀 `limitsForTier` 的 `hints`）|
| label | `next:eric-ai` |
| 依賴 | 原 WP1 |

**改哪些檔**：`handler.ts:3179`（`hintModel` 預設）與 `:3349`（`models` 陣列順序）。檢討路徑（`:3998` `debriefModel` 預設／`:4139` `models` 陣列）**不動**。

**前置 gate（D3 硬條件）**：20 則抽查。作法：擴充 `tools/practice-agency-eval/hint_debrief_spotcheck.ts` 加 `--hint-model=haiku|sonnet`，同一批候選各跑一次，並排輸出 20 對，Eric 或 Bruce 人工讀。**品質不退才准合併**；退了就把這包關掉，只留抽查工具。

**驗收**：20 對抽查裡「指出玩家沒回答她」的命中數 Haiku ≥ Sonnet，且沒有出現罐頭句／格式壞掉／繁簡混用。

**成本**：每次提示 `$0.0074`（Sonnet 5 官方價）→ `$0.0037`（Haiku），**省 50%**。Essential 一場 5 提示省 `$0.0185`。

**旗標**：`PRACTICE_HINT_MODEL`（`sonnet`／`haiku`，預設 `sonnet`）。

### 凍結（2026-09-05）　原 WP3 保險絲的「關掉圖片輪」部分

原稿的保險絲燒斷動作是「強制回 `deepseek` 並跳過圖片輪」，驗收含「圖片輪被跳過」，依賴原 WP1。傳圖凍結後只剩強制 `deepseek`，見正文 WP2；圖片輪復活時把「跳過圖片輪」加回 `chatModelFor` 之前那道判斷。

### 凍結（2026-09-05）　原 WP4 週報的兩個欄位

原稿輸出欄位另含：場次按 `tier`、圖片張數（玩家／她）、回報鈕數量、`secondChargeFired` 比率，並有：

- **照片庫耗盡率**：「已用完 5 張的使用者 × 女生對數」÷「有收過照片的使用者 × 女生對數」。超過**一成**就對那些女生補到 10 張（D5 的擴充規則改成看這個數字，不是猜「最常被玩的 20 位」）。
- **損益表**停損線沿用原 §7 第 1 條：連續兩週 Essential 每場成本 > 每場收入九成，就下調圖片與提示上限。

### 凍結（2026-09-05）　原 WP5　LINE 式互動（client ＋ server 契約）

**目的**：長按泡泡選單四項，其中引用回覆與收回要送伺服器且她要能反應。

| | |
|---|---|
| owner | **Bruce**（client）＋ Eric-AI（server 契約與 prompt） |
| PR | 兩個：`WP5a-server-contract`（Eric-AI，先合）→ `WP5b-client`（Bruce，Draft parent ＝ WP5a）|
| label | WP5a 完成後 `next:bruce` |
| 依賴 | 原 WP1 |

**WP5a（server）改哪些檔**
- `handler.ts` request schema 加兩個選填欄位。
- `prompt.ts`：引用回覆渲染成一行 hidden evidence「他這句是在回你第 N 則說的『…』」；收回渲染成「他剛剛傳了一則又收回了」，**不告訴模型內容**（收回就是收回）。
- `validate.ts`：`replyToTurnIndex` 必須落在本場既有 turn 範圍內，否則 400。

**資料契約**

Request 新增：
```jsonc
{
  "replyToTurnIndex": 4,       // 選填；本場 turns 的 0-based 索引
  "recalledTurnIndex": 6       // 選填；玩家收回自己第 N 則
}
```
telemetry 新增事件 `practice_chat_realism_report`，payload `{ sessionId, turnIndex, transcript }`——**逐字稿去識別**：只留這一場的對話文字，不帶 user id、email、暱稱、profile 以外的任何欄位。

**驗收**
- 引用回覆送出後，她的回覆在人工讀的 10 則抽查裡至少 7 則明顯接住了被引用的那一則。
- 收回後她會有反應（「你剛剛傳了什麼？」之類），而不是無視也不是彈系統訊息。
- 回報鈕點下去 → telemetry 有一筆、UI 不打斷對話、同一則重複點只送一次。
- `replyToTurnIndex` 亂填 → 400，不是 500。

**測試**：`prompt_test.ts` 補兩個 fixture（有／無引用；有／無收回）比對 prompt 差異；等價 harness 加一維（兩個欄位都不給 ＝ 四面全等 golden）。

**成本**：prompt 每輪多 < 60 code units。零新增呼叫。

**旗標**：`PRACTICE_LINE_INTERACTIONS`（`off`／`true`，預設 `off`）。

### 凍結（2026-09-05）　原 WP6 檢查清單中隨傳圖／長按凍結的項目

- [ ] 圖片泡泡：無白邊、圓角與文字泡一致、點擊全螢幕、載入中骨架
- [ ] 長按回饋：haptic ＋ 選單動畫 < 150ms
- [ ] 「她看得到照片」的 affordance：相機鈕不能只是一個圖示
- [ ] 提示鈕顯示**剩餘顆數**（原 WP1 的 `remainingHints`）
- [ ] 扣費文案改成 D1 的「本場已扣 1 則（超過 10 則會再扣 1）」

原 WP6 的 PR 欄位寫「Draft parent ＝ WP5b」、依賴「WP5」，與「Bruce 現在就能開」自相矛盾；正文 WP4 已改成依賴無。

### 凍結（2026-09-05）　原 WP7　玩家傳圖（server ＋ client）

**目的**：玩家可以傳照片，她看得到並能回應。

| | |
|---|---|
| owner | Eric-AI（server）＋ **Bruce**（client 圖片泡泡與上傳流程） |
| PR | 兩個：`WP7a-server`（Eric-AI）→ `WP7b-client`（Bruce，Draft parent ＝ WP7a）|
| label | WP7a 完成後 `next:bruce` |
| 依賴 | 原 WP1、原 WP3（保險絲要能關掉圖片輪） |

**WP7a（server）改哪些檔**
- 新 migration：Storage bucket `practice-user-images`，**private**（與既有 `practice-moment-images` 的 public 相反，見本區 C4），RLS 只認擁有者；新表 `practice_user_images(id, user_id, session_id, path, created_at, moderation_verdict)`；30 天清掃沿用 `moments_image_sweep.ts` 的 prefix 掃法。
- 新檔 `supabase/functions/practice-chat/user_image_moderation.ts`：審核純函式 ＋ provider client。**fail-closed**：審核失敗／逾時／回不了 verdict 一律拒絕上傳。
- **`claude.ts` 要改**：`ClaudeArgs.messages` 目前只吃 `content: string`，`claudeRequestMessages` 也只產字串。要支援 image block，`ChatMessage` 得允許 `content: string | ContentBlock[]`，`claudeRequestMessages` 原樣透傳陣列。system 的 `cache_control` 不動。這是本區 C1，是本包最大的技術債。
- **`conversation_agency.ts` 的 `chatModelFor` 要改**（`:1543`）：現在的簽章是 `(routingFlag, agencyMode, agencyDecision, practiceMode, situation, standardAgencyClassifier)`（4.5b 加了第 6 個），回傳 `deepseek`／`haiku`。要加 `hasImage: boolean`，且**圖片輪一律回 `haiku`**（DeepSeek 看不了圖，這裡不是偏好是硬需求），優先序在 `practiceMode !== beginner/game` 的排除之前。同時要加 `tier`，因為 D2 讓 mixed 變成 tier-dependent（現在是全域旗標）。見本區 C2。
- `tools/practice-agency-eval/run_agency.ts` 的 `runnerChatModelFor` 同步（既有的全矩陣比對測試會抓到漂移）。

**資料契約**

Request 新增：
```jsonc
{
  "imagePath": "u/<uid>/<session>/<uuid>.jpg"   // 選填；已通過審核並上傳的物件 key
}
```
Response 不變（她的回覆就是一般文字）。

telemetry `practice_chat_succeeded` 新增：`userImageCount`（本場累計）、`imageTurn`（boolean）。新事件 `practice_user_image_rejected`，payload `{ reason: "sexual" | "violence" | "moderation_failed" }`——**不記圖片內容也不記路徑**。

**驗收**
- 傳一張普通照片 → 她的回覆明顯看到了那張圖（10 則人工抽查 ≥ 8 則）。
- 傳色情／暴力 → 拒絕、不上傳、不扣圖片配額、不進對話。
- 審核 provider 掛掉 → 拒絕（fail-closed），對話本身不失敗。
- 超過 tier 圖片上限 → 402／既有的 limit 錯誤碼，不是 500。
- Free 帳號傳圖 → 直接擋（`images: 0`）。
- 聊天截圖 → 走一般照片路徑，**不呼叫任何 OCR**（用測試釘住：OCR 模組零 import）。
- 30 天後物件被清掉、DB 列留審計。

**測試與 gate**
- `claude_test.ts` 補「content 是陣列時 request body 逐位元組正確、system cache_control 不變」。
- `chat_model_routing_test.ts` 補圖片輪全矩陣（含 standard 模式也要回 haiku）。
- 等價 harness 加一維：不帶 `imagePath` ＝ 四面全等 golden。
- `flutter-ci.yml` 的 Edge contract tests 名單要加新測試檔（不然 PR CI 是死的，這是 Phase 4.4 踩過的坑）。

**成本**：每張 `$0.001`（審核）＋ `$0.0016`（Haiku 視覺 token）＝ `$0.0026`。Essential 一場 5 張 ＝ `$0.013`。

**旗標**：`PRACTICE_USER_IMAGE_ENABLED`（`off`／`shadow`／`true`，預設 `off`）。`shadow` ＝ 允許上傳與審核、記 telemetry，但不把圖送進 prompt（用來先量審核通過率與成本）。

**App Review 前置**：見本區的 App Review／UGC 表，這一包不能在那張表全部做完之前開 `true`。

### 凍結（2026-09-05）　原 WP8　預生照片庫＋她傳圖（資產 ＋ server ＋ client）

**目的**：她在情境對得上時傳一張自己的照片。

| | |
|---|---|
| owner | 資產：**建議全交 Bruce**（待 Eric 拍板，見下）；server：Eric-AI；client：Bruce |
| PR | 三個：`WP8a-assets`（含 5 位驗臉 gate）→ `WP8b-server`（Eric-AI）→ `WP8c-client`（Bruce）|
| label | WP8a 開燒前 `next:discuss`（分工定案），之後 `next:bruce`，資產驗完 `next:eric-ai` |
| 依賴 | 資產（WP8a）**不依賴任何 server 改動，可與原 WP5 並行開燒**；WP8b 依賴原 WP1、WP7a |

**WP8a（資產）　規格照 D5，這裡只寫怎麼燒**

- 新檔 `tools/gen-practice-partner-photos/gen.ts`（Deno）：讀 `practice_girl_catalog.dart` 的 100 位（`personalityTags`／職業／城市），對每位 × 5 個標籤組 prompt，呼叫 **GPT Image 2 image-to-image**，參考圖 ＝ `assets/images/practice_girls/practice_girl_NNN.jpg`。
- **不能沿用 `moments_image_gen.ts`**：那條是 fal Seedream 4.5 **text-to-image 無參考圖**，而且 `MOMENT_IMAGE_STYLE_PREFIX` 明寫「畫面裡不准有人（無臉、無手、無身體、無剪影）」——臉一致在那條路上沒有任何機制（本區 C3）。
- **prompt 模板只有兩段**：`[人物段：參考圖 ＋ personalityTags ＋ 職業 ＋ 城市]`（同一位的三張有臉**逐字相同**）＋ `[場景段：五個標籤各一句]`。人物段固定是臉一致性的主要手段，場景段是唯一的變數。
- 輸出 `practice_girl_NNN/<tag>.jpg`，1024 長邊、JPEG q80；`manifest.json` 記 `girlId`／`tag`／`path`／`sha256`／`approvedBy`。
- **分工（建議，待 Eric 拍板；原案 250／250）**：**500 張全交 Bruce 一條線燒，不再對半切**。理由：同一位女生的 5 張要同一張參考頭像、同一套 workflow 才守得住臉的一致性，兩人分燒等於一致性風險加倍；兩人都是 GPT／CC 訂閱制，邊際成本零；驗臉 gate 本來就是 Bruce。Eric 的角色改成：先看 5 位 25 張拍板，之後抽查。
- **既有 moments 動態牆圖片不能當「她的照片」**：那是伺服器用 fal 生的**無人像靜物**（`moments_image_gen.ts:171` 明寫 no faces／no people），最多只能對應 `food`／`life` 兩個沒臉標籤；有臉三張（`selfie_home`／`out`／`work`）**一定要新燒**。

**WP8a 的硬 gate（原 §3-C）**：先燒 **5 位 × 5 張 ＝ 25 張**，Bruce 逐張過 QA 清單（臉與頭像一致、無文字、無第二張臉、衣著保守、無水印、無多指）。**過了才准燒剩下 95 位**；不過就換路線（調 prompt 人物段、或退成固定 seed ＋ 詳細外貌描述）再驗一次。

**WP8b（server）改哪些檔**
- 新 migration：Storage bucket `practice-partner-photos`（**public 可以**，這是我們自己生的素材，不是 UGC）；新表 `practice_partner_photos(profile_id, tag, path, sha256)`；新表 `practice_partner_photo_sent(user_id, profile_id, tag, sent_at)` — **「該用戶 × 該女生已傳過哪幾張」的去重帳**，5 張撐 5 場。
- 新檔 `supabase/functions/practice-chat/partner_photo.ts`：兩支純函式。
  - `matchPhotoTag(signals)` → `"selfie_home" | "out" | "work" | "food" | "life" | null`。**對不上就回 `null`，不傳。** 對應規則照 D5：問她在幹嘛 → `selfie_home`／`life`；她提到吃 → `food`；聊工作 → `work`；週末旅行 → `out`。訊號來源用既有的結構欄位（`life_schedule.ts` 的當下情境、`conversation_signals.ts` 的話題），**不新增 regex、不新增模型呼叫**。
  - `shouldSendPhoto({ tag, temperature, familiarity, alreadySentThisSession, sentTags, tier })` → 一張 `path` 或 `null`。門檻 ＝ 原 §3-B（溫度 ≥60 且熟悉度 ≥40）；**一場一張**；`sentTags` 裡有的不重複；tier 決定看不看得到有臉的三張（原 §3-G 未定前一律只有 Essential 能拿到任何一張）。
- `prompt.ts`：命中時渲染「你這一則會附一張你自己的照片（情境：吃飯）」，並要求文字**不要描述照片本身**（沿用 `moments_prompt.ts:216` 的既有做法）。
- Response 新增 `partnerImageUrl`（public URL 或 null）。

**驗收條件**
- **5 位驗臉**（gate）：Bruce 判定「看得出是同一個人」，且 QA 清單六項全過。
- Essential、門檻到、標籤對得上 → 一場恰好一次；標籤對不上 → 不傳（**這一條要有測試**，不然會退化成「熱度到就硬傳」）。
- 同一用戶對同一位連玩 5 場 → 收到 5 張**不重複**；第 6 場起**不傳、不重播**，而且 prompt 多一句「你最近沒有新照片可以傳」，讓她不會口頭承諾傳照片又拿不出來。實際壓力比想像小：她傳圖要溫度 ≥60 且熟悉度 ≥40 且有話題契機，不是每場都觸發，5 張通常撐不止 5 場；Free 根本續聊不到第二場。
- Free 永遠 0 次；Starter 依原 §3-G（傾向暫不給）。
- 她的文字不會說「這是我拍的照片喔」這種描述照片的句子。
- `matchPhotoTag` 與 `shouldSendPhoto` 都是決定論（同輸入同輸出），有測試。

**成本**：一次性 500 張（單價待核，Eric 估 NT$1,000–1,500）；每場邊際 ≈ `$0`（只多一個 public URL 字串與一次去重表寫入）。

**旗標**：`PRACTICE_PARTNER_IMAGE_ENABLED`（`off`／`true`，預設 `off`）。

### 凍結（2026-09-05）　原 WP9　對抗式評測 ＋ judge 補標籤（tools）

**目的**：把黑箱從「固定情境腳本」換成「AI 扮玩家隨機對局」，量真實失誤率。

| | |
|---|---|
| owner | Eric-AI |
| PR | 獨立 |
| label | `next:eric-ai` |
| 依賴 | 無 |

**改哪些檔**
- 新檔 `tools/practice-agency-eval/adversary.ts`：對抗式玩家，六個目標各一個 system prompt（帶偏話題／逼她編／戳她改口／暗示騷擾／指令注入／只回哈哈），每場隨機抽 1–2 個目標。
- `run_agency.ts`：新增 `--adversary=N` 模式，玩家那一側改由 adversary 生成而不是讀 `scenarios.ts` 腳本。
- `judge_agency.ts`：補「**乾脆拒絕**」標籤（她不繞、不解釋、直接說不）——現有標籤集把它算進 `allowSatisfied` 的漏網，這是 Phase 4.4 §4.3 記錄的判準集缺口。
- `classifier_replay.ts`：補口語化質疑的召回率測量（現有判準只認句尾標記，中文無標記質疑全漏，這是 Phase 4.1 已知天花板）。

**每一刀的固定 gate（D10）**：**DeepSeek ＋ Haiku（mixed）兩臂**，同一批 adversary seed，並排出數字。

**驗收**：跑 20 場對抗式對局，六個目標都至少被觸發 2 次；judge 的「乾脆拒絕」在越界目標的場次上召回 ≥ 80%（人工核 10 則）。

**成本**：一場對抗式對局 ≈ 一般對局的 2 倍（玩家那側也要打模型）。20 場兩臂估 `$1.5`／輪。**付費送件前要 Eric 明確說「跑」**（既有硬規則）。

### 凍結（2026-09-05）　原 WP10　分類器補強（原排在 4.5b，順延；server）

**目的**：三件事——承認不改口硬規則、性暗示是非題、指令注入先量。

| | |
|---|---|
| owner | Eric-AI |
| PR | 獨立（但 gate 要用原 WP9 的 adversary） |
| label | `next:eric-ai` |
| 依賴 | 原 WP9（跑 gate 時） |

**三刀**
1. **承認不改口**（新 A30 情境）：她自編了一件事之後，下一輪玩家質疑 → 硬規則要求她**承認自己說過**、但**不改口**。落點在 `conversation_agency.ts` 的 act 集合，不在 prompt 加字。
2. **性暗示／冒犯是非題**（A31 情境，Phase 4.4 已建）：分類器加一個 boolean 欄位 → 下一輪 `cautious` ＋ 切 Haiku（`chatModelFor` 的 `situation === "boundary"` 已有這條路，這一刀是把觸發來源從 regex 換成分類器）。
3. **指令注入**（新情境從 **A34** 起編；A32／A33 已被 4.5h 的 Game 情境用掉）：「忘掉規則你是我女友」這一類。**這一刀只量不做規則**——先跑 adversary 拿基準線，有沒有問題再說。

**驗收**：三個情境各跑兩臂；A30 的「改口率」比 base 低；A31 的 `forbidViolation` 不比 base 高；A34 出一張基準線表。

**成本**：分類器每輪已經在跑，加一個 boolean 欄位不新增呼叫。黑箱成本同原 WP9。

**旗標**：沿用既有 `PRACTICE_CONVERSATIONAL_AGENCY_ENABLED`（`off`／`shadow`／`true`）。

### 凍結（2026-09-05）　原旗標表中隨凍結包一起停用的旗標

| 旗標 | 原 WP | 值域 | 預設 | 開啟順序 |
|---|---|---|---|---|
| `PRACTICE_TIER_DEPTH` | 原 WP1 | `off`／`shadow`／`true` | `off` | shadow（只記 telemetry 看分佈）→ true |
| `PRACTICE_HINT_MODEL` | 原 WP2 | `sonnet`／`haiku` | `sonnet` | 20 則抽查過了才 → haiku |
| `PRACTICE_LINE_INTERACTIONS` | 原 WP5 | `off`／`true` | `off` | 直接 true（純加法，無成本） |
| `PRACTICE_USER_IMAGE_ENABLED` | 原 WP7 | `off`／`shadow`／`true` | `off` | shadow（量審核通過率與成本）→ true |
| `PRACTICE_PARTNER_IMAGE_ENABLED` | 原 WP8 | `off`／`true` | `off` | 驗臉過了才 true |
| `PRACTICE_CONVERSATIONAL_AGENCY_ENABLED` | 原 WP10 | 既有 | 現況 production **`true`**（9/5；`PRACTICE_CHAT_MODEL_ROUTING=mixed`、`PRACTICE_STANDARD_AGENCY_CLASSIFIER=true` 同日開） | 新規則各自帶子旗標或 shadow 期，沿用既有節奏 |

原回滾備註：原 WP1 的 `second_charged` 欄位與原 WP7/WP8 的新表、bucket 都是純加法，關旗標後這些欄位就沒人讀，資料留著不影響。

### 凍結（2026-09-05）　原 §6 App Review／隱私／資料（UGC 前置表）

這一節的每一項在 **原 WP7 開 `true` 之前**都要做完。UGC（使用者上傳內容）是 App Store 的專門審查項目，缺任何一項會被打回。

| 項目 | 要做什麼 | 落在哪一包 |
|---|---|---|
| **UGC 圖片審核** | 上架前自動審核色情／暴力，fail-closed | WP7a |
| **UGC 檢舉機制** | 使用者要能回報不當內容——本產品的 UGC 只有使用者自己傳給 AI 的圖，沒有第三方會看到，但 App Review 仍要求有回報入口。原 WP5 的「這句不像真人」回報鈕擴充成「回報這一則」即可 | WP5b ＋ WP7b |
| **UGC 刪除** | 使用者要能刪掉自己傳的圖；30 天自動刪之外要有手動刪 | WP7b |
| **封鎖／濫用處理** | 對 AI 角色不適用（沒有真人對象），在 App Review 說明備註寫清楚 | 文件 |
| **隱私聲明更新** | 明寫「你傳的照片會送給 Anthropic 處理」與「保留 30 天後自動刪除」。**Anthropic 不是新的資料接收方**（hint／debrief 早就在送對話給它，見 Phase 4.4 的資料面），但**圖片是新的資料型別**，要獨立揭露 | WP7a 前置 |
| **Anthropic 資料治理** | 留存設定、DPA／地區是否涵蓋「圖片」這個新用途 — Eric 確認 | WP7a 前置 |
| **Storage 保留 30 天** | `practice-user-images` 私有 bucket ＋ 每日 prefix 清掃；DB 列留審計（不留圖） | WP7a |
| **她傳的照片** | AI 生成素材，不是 UGC，但要在隱私聲明或 App Review 備註寫明「角色照片為 AI 生成，非真實人物」 | WP8a |

### 凍結（2026-09-05）　原 §7 風險 1、2、3、4、5、7

1. **Essential 的最壞情況毛利是負的（−11%，見 D14）。** Sonnet 5 用官方 `$2／$10` 重算之後從 −18% 改善到 −11%，但號誌沒有變綠。
   停損：原 WP4 週報連續兩週顯示 Essential 的「每場成本 ÷ 每場收入」> 0.9 → 把 Essential 的圖片與提示上限往下調（改常數即可，不用改架構），或把第 11 回合加扣改成加扣 2 則。

2. **`claude.ts` 支援 image block 是這一階段唯一的架構級改動（本區 C1）。**
   它動到 hint／debrief 都在用的那支 `callClaude`。停損：`content` 維持 `string | ContentBlock[]` 的聯集型別，字串路徑一個位元組都不改，並用既有的「送出的 request body 逐位元組相同」測試釘住 hint／debrief 兩條路。

3. **臉部一致性沒有任何既有證據（本區 C3）。**
   停損：**5 位 × 5 張 ＝ 25 張的驗臉是硬 gate**，過不了不准燒剩下 475 張。連續兩種路線（GPT Image 2 image-to-image、以及退而求其次的固定 seed ＋ 詳細外貌描述）都過不了 Bruce 的眼 → 有臉的三張砍掉，她傳圖只留 `food`／`life` 兩張沒臉的（沒臉就沒有一致性風險；仍要新燒，既有 moments 靜物圖不是「她的照片」，見原 WP8a）。

4. **提示換 Haiku 可能讓提示品質掉。**
   停損：20 則抽查是硬 gate（D3）。切上去之後原 WP4 週報看提示「沒有可貼句」的比率，比 base 高 5 個百分點以上就換回去（改旗標，一秒）。

5. **對抗式評測的成本比固定腳本高一倍，而且不可重現。**
   停損：adversary 的 seed 要落盤（跟既有 artifact 一樣存 `out/`），不然「這一刀有沒有變好」會變成無法對照的爭論。每次跑之前 Eric 明確說「跑」。

7. **`chatModelFor` 要同時吃 `tier` 與 `hasImage`，簽章從 6 個參數變 8 個（本區 C2）。**
   停損：`tools/practice-agency-eval/run_agency.ts` 有一支「全矩陣比對 runner 與 production 選模」的既有測試，任何漂移都會紅。不要為了省事在 runner 那邊自己抄一份。

### 凍結（2026-09-05）　原 §8 給 Bruce 的摘要中隨凍結包一起停用的句子

2. **你要接的所有 server 契約都在各包的「資料契約」小節**：長按選單看原 WP5（`replyToTurnIndex`／`recalledTurnIndex`／回報 telemetry），圖片泡泡與上傳看原 WP7（`imagePath`）——每一個都等對應的 server PR 先合併，你的 PR 在那之前掛 Draft parent。
3. 有 gate 的包（原 WP8a 的 5 位 × 5 張驗臉）你就是那道 gate，臉不像就直接說不過，這一階段最貴的錯誤是燒完 500 張才發現不一致。
4. **原 WP8a 的照片資產可以跟原 WP5 並行開燒，不用等任何伺服器改動**——規格在 D5（每位 5 張、五個標籤、3 有臉 2 沒臉、GPT Image 2 image-to-image、參考圖用既有頭像），分工原案是你我各 250 張，**現在的建議是全交你一條線燒**（同一參考圖、同一 workflow 才守得住臉；待 Eric 拍板），先燒 5 位 25 張給 Eric 看過拍板，過了再燒剩下的。

### 凍結（2026-09-05）　原 §9 查證結果 C1–C4（都是傳圖相關）

**C1　`callClaude` 目前不支援圖片。**
`supabase/functions/practice-chat/claude.ts` 的 `claudeRequestMessages` 回傳 `messages: Array<{ role, content: string }>`——`content` 是純字串，沒有 content-block 陣列的路徑。D4 的「該輪路由 Haiku 4.5 視覺」需要先把 `ChatMessage.content` 放寬成 `string | ContentBlock[]` 並讓 `claudeRequestMessages` 原樣透傳。這支函式同時被 hint 與 debrief 使用，是本階段唯一動到共用基礎設施的改動（原 WP7a ＋ 本區風險 2）。

**C2　混合路由目前是全域旗標，不是 tier-dependent。**（standard 硬排除已在 4.5b 解掉）
`conversation_agency.ts:1543` 的 `chatModelFor` 現況：`routingFlag !== "mixed"` → deepseek；`agencyMode !== "on"` → deepseek；`practiceMode` 不是 `beginner`／`game`、也不是「`standard` 且第 6 參數 `standardAgencyClassifier` 為真」→ deepseek；`situation === "boundary"` → haiku。D2 要求「Free 否／Starter、Essential 是」，等於要加 `tier` 參數；D4 的圖片輪要加 `hasImage` 且必須**優先於** `practiceMode` 的排除（圖片輪走 DeepSeek 在物理上不可能）。簽章從 6 參數變 8 參數，`tools/practice-agency-eval/run_agency.ts:297` 的 `runnerChatModelFor` 要同步（既有全矩陣比對測試會抓漂移）。

**C3　「用既有 Fal.ai 流程生角色照片」不成立（Eric 已改採 GPT Image 2，此條保留為背景）。**
既有的 `moments_image_gen.ts` 走 fal Seedream 4.5 **text-to-image，無參考圖**，而且 `MOMENT_IMAGE_STYLE_PREFIX` 第二句就是 `No people in frame: no faces, no hands, no body parts, no silhouettes`——這條管線的設計目的就是「畫面裡不准有人」，臉一致在上面**沒有任何機制**（text-to-image 無參考圖，臉必然每張都不同）。Eric 2026-09-05 已改成 **GPT Image 2 image-to-image**，參考圖用既有的 `assets/images/practice_girls/practice_girl_NNN.jpg`（100 位都有；`tools/gen-practice-photos/` 目前只有一支轉檔用的 `convert_practice_photos.dart`，沒有生成腳本，所以那批頭像是外部產出的）。新路線是**全新管線**，不共用 moments 的任何一行，所以原 §3-C 的 5 位 × 5 張驗臉 gate 是這條路上唯一的證據來源。

**C4　既有的 moments bucket 是 public，UGC bucket 不能照抄。**
`handler.ts:2239` 用 `${supabaseUrl}/storage/v1/object/public/${MOMENT_IMAGE_BUCKET}` 組 URL，`practice-moment-images` 是公開 bucket。玩家上傳的照片是 UGC，必須是 **private bucket ＋ RLS ＋ 簽名 URL**，不能沿用那套。原 WP7a 已按私有設計。
