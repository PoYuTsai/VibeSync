# 使用者可見 AI 串流遷移計畫

> 狀態：APPROVED／分批實作中；Eric 於 2026-07-16 拍板採用 progress-only
> 目前進度：Coach 1:1 已完成可信進度串流；Opener 已完成誠實的本地分階段等待，但不是 server streaming；「我幫你修」已完成固定扣 1 與安全重播。其他流程仍依風險分批處理。

## 決策摘要

不採用「Flash 先產生看似思考的 stream，再由高級模型產生 final」的雙模型架構。`analyze-chat` 的正式文字路徑已是單一選定 Claude 模型做 full streaming；舊 quick/full 僅保留 rollback。新增流程應讓原本負責答案的模型直接工作，進度由系統事件表達，避免多一次模型呼叫造成更慢、更貴、前後建議衝突與扣額度語意不清。

本計畫先解決「等很久但不知道發生什麼事」。任何提早顯示實質建議的改動，必須先有可重播的 run/result ledger、原子扣額度及內容可見前驗證，不與單純進度 UX 綁在同一批。

Eric 本輪選擇 **progress-only**：只顯示伺服器確實走到的階段，完整答案通過驗證後才一次顯示。**Early usable content 未被選用**，因此不會提前顯示模型候選文字或模擬思考。

## Scope

- In：Coach 1:1、Opener、Coach follow-up、OCR／圖片分析／「我幫你修」、Practice 的使用者可見進度與必要的安全重播設計。
- In：確認既有純文字 `analyze-chat` 在正式環境確實走 full stream，作為共用事件協議的參考實作。
- Out：復活 quick/full、用第二個快速模型製造思考文案、串流未通過 schema／安全／事實審查的 raw token、一次橫跨所有流程的大型改版。

## 現況盤點

| 流程 | 現況與模型 | 使用者現在看到什麼 | 遷移風險 |
|---|---|---|---|
| 分析對話（純文字） | 單一 Claude full stream；Free 與付費主模型皆為 Sonnet 5，失敗依序降級 Sonnet 4.6 → Haiku | 固定進度事件後逐段結果；不是 Flash 生成的思考 | 已完成；只需驗證 live flag、遞增到達與 rollback |
| 分析對話（圖片／OCR） | 非串流；圖片強制 Sonnet，timeout 最長 120 秒 | 本地等待文案後一次回傳 | 高：vision schema、OCR、成本及長 timeout |
| 「我幫你修」／`optimize_message` | 非串流，現有 analyze stream gate 明確排除 | 等待後一次回傳 | 中高：付費 entitlement、短內容安全與扣額度 |
| Coach 1:1／`coach-chat` | 非串流；Free Haiku、付費 Sonnet；每次最長 60 秒，驗證不過最多 3 次 | spinner「教練正在接這句」後一次回傳 | 高：多次生成、clarification 不扣額度、目前無 result replay ledger |
| Coach follow-up | 非串流；Free Haiku、付費 Sonnet；單次最長 60 秒 | 「正在產生跟進建議」後一次回傳 | 中高：內容短，提早吐內容收益有限 |
| Opener | 非串流；Free 純文字 Haiku，付費或圖片 Sonnet；可 fallback／format repair | staged 本地文案後整張卡片 | 高：五種結果、recommended pick、一次扣 3、現有 ledger 只去重扣費而不存結果 |
| Practice chat | DeepSeek `v4-flash` 非串流；失敗時依流程可能由 Claude 補位 | spinner 後一次回傳 | 高：回傳前仍有標籤及安全檢查 |
| Practice hint／debrief | DeepSeek Flash 生成，Claude 是 failover／審查者；成功路徑仍有語意與事實審查 | 「教練拆解中」後一次回傳 | 非常高：候選內容可能被拒絕或修正，只能顯示已完成的審查階段 |

「問教練：我現在該怎麼做？」會捲到 Coach 1:1 並在送出後呼叫 `coach-chat`，因此 Fable 回報的長等待不應先被歸因成「分析對話」。

## 兩種使用者承諾

### A. 進度串流（預設、先做）

- 只送出伺服器知道已發生的階段，例如 `request_started`、`generating`、`validating`、`retrying`、`finalizing`。
- 模型 payload 仍完整緩衝；通過 schema、安全與 quota 規則後，才一次送出既有 final card。
- 改善可感知等待與除錯能力，不宣稱縮短完成時間，也不顯示模型「思考過程」。
- 若 final 與進度共用 NDJSON 連線，仍需 request idempotency；否則斷線後不得自動重送並再次扣額度。

### B. 已驗證內容串流（需 Eric 明確核准）

- 只提早顯示可獨立使用、已通過完整驗證的內容單位，例如一張正式 Coach 建議卡或 Opener 的 recommended opener；禁止 raw token streaming。
- 第一個官方內容事件送出前，必須在同一交易中完成 `validate -> persist result -> charge`，再以 event ordinal 發送。
- 同一 `requestId/runId` 必須能在重連時 replay 已扣費內容且不重扣；其餘區段可續跑或以明確 partial terminal 結束。
- 一旦送出官方內容，不得再以另一模型靜默替換；後續 fallback 必須發生在扣費與內容可見之前。

## 不可破壞的高風險 invariants

1. Free 使用者在 quota 真正耗盡前保有核心存取；只有伺服器確認 quota exhausted 才回 429／升級 UX。
2. malformed、unsafe、schema 不合格或僅有 deterministic fallback 的內容不得扣額度，也不得把 raw JSON／候選文字顯示給使用者。
3. 第一個官方可用內容必須 charge-before-emit；扣費與可重播內容必須原子保存，`requestId`、owner、flow、input hash 均需核對。
4. clarification question 維持不扣 Coach quota；任何 retry／repair 次數與模型 fallback 不得造成多扣。
5. 圖片輸入維持 Sonnet，不可因 provider fallback 靜默降級到 Haiku；若 Sonnet 不可用，回可重試錯誤。
6. Practice 不顯示尚未通過語意、事實與安全審查的 candidate；只能串流系統已完成的階段及最終 validated card。
7. 事件需單調 ordinal、可去重且只有一個 terminal；client 不自行推定「已扣費」或「已完成」。
8. 每個 endpoint 保留 feature flag、穩定 buffered rollback 與既有 response schema；只能在第一個官方內容事件之前切回 legacy path。

## 失敗矩陣

| 情境 | quota／run 狀態 | 使用者行為 | 重試／fallback 規則 |
|---|---|---|---|
| 連線在扣費前中斷 | `pending` 或無 run；不扣費 | 顯示可安全重試 | 同一 request 可重跑；不得留下 usage |
| validation／安全檢查失敗 | 不扣費；不保存為 official result | 不顯示候選內容；依既有規則 repair、clarify 或錯誤 | 可在預算內重試／fallback；全部失敗則 terminal error |
| quota charge 回 429 | 交易 rollback；無 official content | 顯示 quota exhausted／正確 paywall | 不得送出建議後才 429；不得自動重試 |
| 扣費並保存後、第一個內容事件前斷線 | `charged`，official result 已保存 | 重連後恢復同一內容 | 以同一 `requestId/runId` replay；絕不重扣 |
| 已收到第一個內容、final 前斷線 | `charged`，記錄最後 ordinal／可重播內容 | 保留已顯示內容並提供「繼續載入」 | replay 去重後續跑；無法續跑時發 partial terminal，不換答案 |
| provider/model 在扣費前失敗 | 不扣費 | 顯示 retrying 進度或可重試錯誤 | 可依 flow policy fallback；圖片不得降級模型 |
| provider/model 在扣費後失敗 | 已扣費；已保存的 official content 不變 | 保留正式內容，清楚標示其餘未完成 | 只能續跑同一 run 或 partial terminal；不得另產生衝突答案 |
| client 重送相同 request | 查到 owner/input hash 相同的既有 run | replay pending progress、official content 或 final | owner/hash 不符拒絕；相同 run 不再次呼叫 charge |
| 事件重複、亂序或 terminal 後又到達 | server ledger 為準 | client 依 ordinal 去重；terminal 後忽略 | 記 telemetry；不得改寫已顯示官方內容 |
| streaming transport 不可用 | 第一個 official event 前才可 rollback | 使用既有 buffered UX | 已 charge／emit 後禁止切換成新 legacy request |

## Reviewable batches

### 前置確認：既有 Analyze baseline

- 驗證正式環境 `STREAM_ANALYZE_ENABLED`、真機是否逐段到達、quota/replay 與 legacy rollback；不得把現有固定 progress 誤記成 Flash 輸出。
- 抽出最小共用 NDJSON envelope（`runId`、`ordinal`、`type`、`stage`、`payload`、`terminal`），但不為了共用而一次重構所有 endpoint。

### Batch 1：Coach 1:1 進度

**狀態：已完成並部署（`b09b6dd1`；`coach-chat` v52）。** 2026-07-16 live smoke 依序收到 `request → generating → validating → finalizing → done`，最後事件含完整 validated card。

- 在 `coach-chat` 加 gated progress response，僅傳真實生成／驗證／retry 階段，final 仍使用完整 validated Coach card。
- Flutter 改用可逐行解析的 transport 與明確 loading stages，保留 429、clarification、deterministic fallback 及現有卡片 schema。
- 若 progress 與 final 共用連線，先補最低限度 request idempotency；沒有可重播 final 前，不提供斷線後自動重送。

### Batch 2：Coach 已驗證內容 ledger（只有 Eric 選 early usable content 才做）

**狀態：本輪不做。** Eric 未選 early usable content；Coach 目前沒有 final result replay ledger，App 也不會在斷線後自動重送並冒著重複扣費風險。

- 新增 owner-scoped Coach run/result ledger 與原子 `persist + charge` RPC；定義 pending／charged／done／partial／failed lifecycle。
- 僅在一張完整 Coach card 通過安全與 schema 後送出，不逐 token 顯示；實作 replay、續傳與 ordinal 去重。
- clarification 與 deterministic fallback 保持不扣費；模型 retry 必須發生在 official emit 前。

### Batch 3：Opener

**狀態：等待體驗已完成（`971b7214`、`8f6b5f8e`），server streaming 尚未實作。** 本輪讓使用者可一次選三張截圖，並以誠實的本地階段文案說明正在處理；不宣稱答案正在逐段從伺服器傳回。

- 先做 progress-only；保留五種 opener、recommended pick、profile/pioneer plan、format repair 與一次扣 3 的既有契約。
- 若核准 early content，將現有「只去重扣費」ledger 升級為可保存／replay 結果；先送 recommended opener 也必須是完整驗證並已原子扣費的官方內容。
- 稽核圖片 Sonnet invariant，移除任何圖片路徑降級 Haiku 的可能性後才開 flag。

### Batch 4：Coach follow-up

- 套用已驗證的 Coach progress envelope；final 仍一次回傳。
- 只有數據證明等待痛點與 early-content 收益，才複用 Coach run ledger；不另造第二套 quota protocol。

### Batch 5：OCR／圖片分析／「我幫你修」

**狀態：「我幫你修」固定扣 1 與 result replay 已完成並部署（`4b624617`；migration `20260716170000`；Edge v269）；fresh／replay／mismatch live smoke 通過。OCR／圖片分析的可信進度尚未實作。**

- 分別處理 vision/OCR 與 `optimize_message`，不得與文字 Analyze 或 Coach 同 commit。
- 先送 OCR/upload/model/validation 的可信進度；任何辨識文字、改寫句或分析內容仍需通過該 mode 的 schema、安全與 Sonnet 規則後才可見。
- `analyze-chat` 部署沿用專案既定 `--no-verify-jwt` 規則，並保留 text full-stream rollback。

### Batch 6：Practice 僅 validated-stage progress

- 只送 `generating -> semantic_review -> fact_verification -> finalizing` 等完成階段；不送 DeepSeek／Claude candidate、review rationale 或 hidden assessment。
- 保留既有 requestId/result replay、typed-facts、generated-only 與 failover budget；final card 維持完整驗證後一次回傳。
- 明確排除 Practice raw/early content streaming，除非另立安全設計與產品核准。

## 每批測試、部署與 review gates

- Contract tests：事件順序、重複／亂序、單一 terminal、partial line、UTF-8、heartbeat、429 與 legacy JSON fallback。
- Backend tests：validation fail 不扣費、clarification 不扣費、charge idempotency、owner/hash mismatch、斷線前後 replay、provider retry/fallback、圖片不降級、terminal 後不再生成。
- Flutter tests：首個進度狀態、final card 相容、重連 replay 去重、partial terminal、retry 文案、背景／前景切換、timeout 與 429/paywall mapping。
- 執行該 flow 的 Deno tests、`flutter analyze` 與 targeted Flutter tests；若有 migration，再跑 DB lint／RPC 並行與 rollback 驗證。
- 每批一個 concern、一個 feature flag、一個可回退 deploy；記錄 time-to-first-progress、time-to-first-usable、completion、validation failure、disconnect-before/after-charge、replay hit 與 duplicate-charge telemetry。
- 任何 quota、Edge schema、AI prompt/token 或可見內容改動，在宣稱可 dogfood 前必須有 Codex read-only review 證據；有 migration 時先 DB、再 Edge、最後 client。
- Edge smoke 後才切 whitelist；需要 client 改動的批次送 TestFlight，使用真 iPhone 確認 chunk 真的逐步到達而非結尾一次吐出。未通過時關 flag，不提交 App Review。
- 完成一批並觀察 dogfood telemetry 後才開始下一批；不得把 Coach、Opener、OCR 與 Practice 合成同一次 rollout。

## 產品選擇已結案

Eric 於 2026-07-16 選擇 **Progress-only**：使用者看到的只能是可信系統階段，答案仍在完整驗證後一次出現。**Early usable content 不採用**；若未來要提前顯示正式內容，必須另案核准 run/result ledger、原子扣費、replay 與 partial failure 設計，不能直接打開 `stream: true`。
