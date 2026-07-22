# 練習室 Hint 延遲優化 Phase 1（2026-07-22）

## 背景

Eric 反映點「提示/攻略」等待過長。根因＝全串行非串流多階段管線（DeepSeek 生成 → 跨供應商語意複核 ≥2 呼叫 → repair/failover 線性疊加），詳見原始根因分析（2026-07-22 session）。

## Phase 0 實測（production，近 14 天）

- `PRACTICE_HINT_PREFETCH_ENABLED` **已是開啟狀態**（secret digest == sha256("true")）→ 原計畫 1.1「開 flag」作廢。
- `practice_hint_requests` ledger：prefetch 消費 196 / 冷路徑 97 / prefetch 未消費 6 → **命中率 ~67%，痛點在 33% 冷路徑**（p50 23s、p90 67s）。
- ai_logs：practice_hint attempts 447 筆、failed 156（**35%**），每次失敗燒 20-73s 才 failover。最大宗 `schema_invalid` 107 筆，但該桶混入 `semantic_adjudication_*` 機制失敗，且 **ai_logs.error_message 全 null**，離線無法分解 → 新增任務 1.5。
- 07-21 修復（2938c1f0）後樣本僅 4 筆，無法評估；semanticProviderCalls 直方圖只在 edge logs（保留期短），待下次 dogfood 流量。

## Phase 1 任務（拍板順序：1.2 → 1.5 → 1.3 → 1.4）

### 1.2 Client prefetch 暫時性失敗重試一次（升為第一優先）
`lib/features/practice_chat/data/providers/practice_chat_providers.dart`（`_runHintPrefetchAfterPersist` ~885-953）：
- 失敗分類：可重試（網路、timeout、503 retryable）vs 終止（429、403、disabled、409 stale）。
- 可重試者延遲 3-5s 用**同一 requestId** 重試恰一次，受 `stillCurrent()` 保護；正式點擊進行中即取消。
- 伺服器失敗已釋放 latch（handler.ts:3306），同 id 重 claim 是設計冪等路徑；若首次其實已 settle，preflight 回 opaqueAck，不重複生成不扣費。
- 不變量測試（practice_chat_controller_test.dart）：同 requestId 絕不並發兩個 prefetch、正式派發後不重試。

### 1.5 失敗明細落 DB（新增）
practice-chat 的 ai_logs 寫入點：failed attempt 把內部 failure 訊息（如 `hint_missing_*`、`semantic_adjudication_*`）寫進 `ai_logs.error_message`（截斷合理長度、**絕不含使用者逐字稿**）。目的＝分解 schema_invalid 混桶（35% 失敗率的主線索）。Deno 測試斷言 error_message 有值且不含 transcript。

### 1.3 分段進度 UX
`practice_chat_screen.dart`（提示按鈕 spinner ~1754＋提示面板）：套 analysis_screen.dart ~6795-6895 既有 stage label 模式：0-8s「教練正在讀你們最後幾句…」→ 8-25s「正在想兩種回法…」→ 25s+「正在做品質雙重複核，確保建議可靠…」＋經過秒數。純時間分段，不假造伺服器進度。widget 測試放 test/widget/features/practice_chat/；**動畫/timer 零無限 repeat，pumpAndSettle 必收斂**。

### 1.4 Claude 呼叫加 prompt caching
`supabase/functions/practice-chat/claude.ts`：system 改 content-block 陣列＋`cache_control: {type:"ephemeral"}`（**零 prompt 文字變更**）。claude_test.ts 斷言 request body 形狀。

## 明確不做（Phase 1）
- 成功 envelope 的 Hive await 移位（動搖 durable 不變量）；pending-id 落盤攸關計費必留。
- 串流生成、prefetch 回傳內容、調降 token 上限、瘦身 rubric、裁 reviewer transcript、並行 DB RPC、雙供應商對衝（原計畫已證偽/否決）。
- semantic_quality.ts 狀態機（Phase 3 才議，需 Eric 拍板＋設計文件）。

## 驗證與回滾
- Deno 全套維持 934/934；Flutter targeted 測試綠＋`flutter analyze` 0 issue。
- 1.2/1.5 碰高風險區（AI token/cost/telemetry）→ Codex review 證據後才宣稱 dogfood safe。
- 回滾：1.4/1.5 純 server 行為，revert commit 即回現狀；kill switch `PRACTICE_HINT_PREFETCH_ENABLED=false` 不受影響。

## Phase 1 執行結果（2026-07-22 SHIPPED）

- 1.4 `c0335f86`（claude.ts prompt caching）＋ 1.5 `b28e34c1`（ai_logs.error_message 失敗明細）：Deno 1145/1145 綠（934 是舊基準）。
- 1.2 `62210a9c`＋`b0a1c12b`（prefetch 同 requestId 重試恰一次、正式點擊即取消、dispose 清 timer）＋ 1.3 `1a788e42`（分段進度文案＋秒數）：flutter analyze 0 issue、controller 179/179＋practice widget 合跑 360/360 綠。
- **Codex 單審 APPROVED（0026ba30..main 五 commit，零 P0/P1/P2）**：查證同 id 冪等重試、timer 清理、system byte-for-byte 單一 cached block、error_message 僅 sanitized 機器碼無逐字稿。Codex sandbox 無法跑 Flutter 測試，以 client agent 本機 360/360 補證。
- 待辦：Eric 真機 dogfood 體感（冷路徑應變少、等待有分段文案）；下次有流量後用 ai_logs.error_message 分解 schema_invalid 混桶，再決定 Phase 2。

## Phase 2/3（未開工，等遙測）
2.1 DeepSeek prefix-cache 稽核、2.2 consume 加入進行中 prefetch（等「點擊撞 generating」頻率數據）、3.1 並行複核（最後手段，Eric 拍板）。
