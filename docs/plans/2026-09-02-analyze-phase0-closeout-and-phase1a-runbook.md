# Analyze Chat：Phase 0 收尾與 Phase 1a（DB／扣費契約）runbook

> 日期：2026-09-02
> 基準：`origin/main` @ `c05c8110`（Phase 0 觀測已部署，Edge deploy 2026-09-01T15:14Z）
> 規格：`2026-09-01` 兩份 Analyze 優化規格（工程版 §9.4／§10／§21，白話版 §7／§9）

## 1. Phase 0 現況（正式流量）

- 觀測管線在 production 已上線，但 **部署後尚無任何 Analyze run**：`analysis_stream_runs` 最近兩筆是 2026-09-01 00:23Z 與 03:05Z，都早於部署時間；Edge log 中 `stream_phase0_observability` 事件數為 0。
- 所以「矛盾率基線」目前 **無法從正式流量算出**，不是管線壞掉。需要 dogfood 流量（建議至少 20 次分析）再算。
- 兩個查詢坑（已寫進 `scripts/analyze_phase0_baseline.py`）：
  - Management API `analytics/endpoints/logs.all` 時間窗一寬（實測 3 天）就 **靜默回 0 筆**，24 小時內才有資料；腳本固定切 6 小時查。
  - `event_message` 是 Deno `console.log` 的 inspect 格式（key 不加引號），不是 JSON；腳本會轉回 JSON 再彙整。

### 怎麼算基線（有流量後）

```bash
# WSL；PAT 讀 ~/.supabase/access-token
python3 scripts/analyze_phase0_baseline.py --project-ref fcmwrmwdoqiqdnbisdpg --days 7
```

輸出是一份 markdown：各欄位 observed／unknown 數、各矛盾率、問句密度、決策與 flag 分布。把結果貼進本檔「基線紀錄」小節並註明統計期間，Phase 0 即可標 Done。

### unknown 欄位分類（本輪已釐清）

| 欄位 | v1 現在觀測得到？ | 說明 |
|---|---|---|
| `legacyGiveUpBanner`／`legacyGiveUpConflict`／`candidateCount`／`coachActionType` | **是（本輪補上）** | 伺服器端鏡射 App 的放棄橫幅規則（`enthusiasm.level == cold` 且 warnings 含「建議放棄／開新對話」）。`legacyGiveUpConflict` 就是白話規格「橫幅說別追、下面還有回覆卡」的 v1 矛盾率。 |
| `selectedStyle`、`questionCounts`、`meaningfulBallCoverage`、`fiveCardSourceDivergence` | 是 | 來自 v1 已有的 `analysis.inventory`、replyOptions 與 evidence linkage。 |
| `decisionSchema`、`action`、`messageDecision`、`replyMode`、`selectedBallCount`、`betaRiskFlags`、`solutionModeAllowed`、`actionMismatch`、`ballMismatch`、`noSendConflict` | **否，要等 Phase 1b** | v1 prompt 凍結，模型不會 emit `analysisDecisionV2`；這批只有 v2 決策契約上線後才有值。 |
| `topicJump`、`semanticDistance`、`solutionMode` | **否，要等 Phase 2** | 需要發散層的 per-variant 欄位。 |

## 2. Phase 1a：migration 與 v2 扣費 RPC

檔案：`supabase/migrations/20260902120000_analysis_stream_runs_decision_kind.sql`（單一交易、additive）

1. `analysis_stream_runs.decision_kind TEXT`，CHECK 為 NULL 或四種決策；NULL＝舊 v1 send run，不回填。
2. 新約束 `no_send_has_no_style`：三種 no-send 不得帶 `selected_style`。
3. 改寫 `charged_has_recommendation`：已扣費 ⇒ recommendation 為物件 且（有風格 或 decision_kind 為 no-send）。舊列全部相容。
4. 新 RPC `charge_stream_analysis_run_v2(p_run_id, p_user_id, p_conversation_hash, p_recommendation_json, p_decision_kind, p_selected_style, p_message_count, p_charge_quota)`：send 沿用五風格檢查；no-send 要求 style 為 NULL，且 JSON 內 `decisionKind` 相符、`action`／`reason`／`stopCondition` 非空才准扣費（防空殼決策提早扣費）。已扣費一律回放，不重扣。舊 `charge_stream_analysis_run` 一字未動。
5. `reserve_stream_analysis_retry` 同簽名重建：放行已扣費的 no-send run。
6. 授權：v2 RPC 僅 `service_role`。

驗證：`supabase/functions/analyze-chat/stream_runs_decision_kind_migration_postgres_test.ts`（PGlite 真 Postgres，9 案例：舊列相容、NULL 邏輯、v1 RPC 不變、v2 驗證矩陣、exactly-once、lease、cleanup、grants），已加入 `flutter-ci.yml` 的 Postgres 契約步驟。

### 部署順序（依 `docs/shared-agent-rules.md`）

1. 先在 production 用 targeted migration 上這一檔（MCP `apply_migration`，或 `migration list --linked` 證明它是唯一 pending 後 `migration up --linked --yes`；MCP OAuth 壞掉時參考踩坑筆記「暫移他檔讓目標成唯一 pending」）。**禁止 `supabase db push`。**
2. 驗三件：ledger 版本＝檔名、`pg_proc` 有 `charge_stream_analysis_run_v2` 且 anon／authenticated 無 EXECUTE、既有 run 仍可 `reserve_stream_analysis_retry`。
3. 之後 Phase 1b 的 Edge v2 code 才可推 `main`。Edge v1 全程不呼叫 v2 RPC，rollback 只需不開 v2 capability，migration 可留存。

## 3. Phase 1b 後端（決策權威，capability gated）

請求多一個欄位 `analysisContractVersion`（整數；缺省＝1；2＝支援不回決策；其他值 400）。只有送 2 的 client 會拿到下面的行為，v1 client 的 prompt、事件、扣費一字不變（`baseline_contract_test` hash 鎖仍綠）。

- **Prompt**：v1 之後插入「1a. Message decision gate」，要求每個 `analysis.decision` 帶 `messageDecision`（`send`／`do_not_send`／`acknowledge_and_stop`／`need_context`）。三種不回：不帶 `selectedStyle`，帶 `action`／`reason`／`stopCondition`（`acknowledge_and_stop` 另帶 `closingMessage`），跳過 recommendation 與 reply_option，直接接 metrics／report／done。
- **扣費錨點**：不回決策經 `validateNoSendDecisionEvent` 驗證（空殼不扣費、安全掃描）後，走 `charge_stream_analysis_run_v2`，`decision_kind` 落 DB、`selected_style` NULL；`send` 仍走 v1 RPC。
- **串流**：不回模式下 reply_option／recommendation 事件一律丟棄、後續 decision 不能改判；done 跳過五風格完整性檢查；`finalResult.replies`／`replyOptions` 強制空、無 `finalRecommendation`、帶 `analysisDecisionV2`（`schemaVersion 2`、`messageDecision`、`replyMode` none／single、`action`、`reason`、`stopCondition`、`closingMessage?`）。
- **後處理**：`ensureNonEmptyAnalysisOutput` 對不回結果不補罐頭句。
- **重試／續看**：`recommendation_json.decisionKind` 存在即還原不回錨點，不再回 `STREAM_RUN_NOT_RETRYABLE`；重試不重扣、決策凍結。
- **App 端（Phase 1c，未做）**：收到 `messageDecision` 非 send 時零回覆卡、零升級推銷；`shouldGiveUp` 降為離線備援。在 1c 上線前，App 不送 `analysisContractVersion: 2`，此路徑在 production 為休眠。

測試：`no_send_decision_test.ts`（驗證矩陣、round-trip、prompt 閘、後處理、store RPC 分流）＋`no_send_stream_test.ts`（reframer 七案例＋handler 三案例），皆已進 CI 契約清單。

## 4. Phase 1c App（三態畫面）

- 請求送 `analysisContractVersion: 2`（`AnalyzeStreamClient.analysisContractVersion`），**這一步一上線，dogfood 使用者就會真的收到不回決策**。
- `AnalysisDecisionV2`（domain，`analysis_models.dart`）從 `finalResult.analysisDecisionV2` 解析；只認 schemaVersion 2＋合法 messageDecision，其餘 null 退回 v1。`shouldGiveUp` 在決策存在時以決策為準（do_not_send＝true，其餘 false），本地 cold＋警語只當 v1 備援；歷史快照走 rawResponse round-trip，不需 migration。
- 畫面：`AnalysisDecisionCard`（sections）在 messageDecision 非 send 時是唯一主卡（不回／資料不夠／先收尾三種文案；acknowledge_and_stop 顯示收尾句＋複製）；`ReplyZoneSection` 與升級推銷在 replyMode none／single 隱藏；`GiveUpAdviceBanner`／`CoachActionPolicy` 只在 v1 或 send 出現。歷史紀錄詳情同樣顯示決策卡。串流中 `analysis.decision` 的不回事件由 display mapper 轉成「本輪判斷」內容卡。
- 測試：`analysis_decision_v2_test`、`analysis_stream_content_display_test`、`analysis_decision_card_test`、characterization 三案例、records UI 一案例、body test 合約版本斷言。
- 未做：詳細分析區的發散地圖（Phase 2）；決策型回饋分類（規格 §18）。

## 5. 基線紀錄

（待 dogfood 流量；填入統計期間與腳本輸出）
