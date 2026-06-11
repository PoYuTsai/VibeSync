# Smoke 修復計畫：quota 429 retry 誤映射 + 實扣顯示常駐（2026-06-11）

> 來源：Bruce TestFlight smoke feedback（ADR #19 計費新制上線後）。
> 兩案皆碰 quota/paywall 高風險區 → 修完走 Codex 實作雙審，APPROVED 前不得回報 Bruce「可再試」。

## 問題 1（P1）：Free 用戶額度不足，retry 路徑顯示「無法再重試」

**現象**：Free 用戶額度不足做分析，看到「無法再重試，請重新分析。」+ disabled 按鈕。應顯示「目前剩 N 則，請升級至 Starter or Essential」。

**根因鏈**（已定位）：

1. Server 429 回應帶完整資訊：`supabase/functions/_shared/quota.ts:200-231`（`monthlyRemaining` / `dailyRemaining` / `quotaNeeded` / `used` / `limit`）。
2. 正常路徑正確：429 → `Daily/MonthlyLimitExceededException`（`analysis_service.dart:1538-1556` 轉換、`:2291-2317` 定義，`suggestedAction: wait/upgrade`）→ analysis_screen 捕獲 → snackbar + `_showPaywall`。✅
3. **Bug**：streaming full 分析路徑 `streaming_analyze_notifier.dart:604-621` 的 generic `on Exception catch` 把 quota 異常混進普通失敗，硬設 `retriesRemaining: 0`；`_streamRetriesRemaining`（:483-500）也沒處理 `upgrade` action。
4. UI 看到 `retriesRemaining == 0` → `kRetryExhaustedMessage`「無法再重試，請重新分析。」（`streaming_analysis_loading_widgets.dart:37`、`FullAnalysisRetryCard` :214-232）。

**修法**：

- `streaming_analyze_notifier.dart`：在 generic catch 之前特別捕獲 `DailyLimitExceededException` / `MonthlyLimitExceededException`，存入新 state（quota 不足旗標 + remaining + needed + daily/monthly 區分）。
- `FullAnalysisRetryCard` 分流：quota 狀態渲染獨立卡片——「目前剩 N 則，本次分析需 M 則。升級至 Starter 或 Essential 繼續分析」+「查看方案」鈕（接既有 `_showPaywall`）。不再出現「無法再重試」。
- Server 不用改（429 payload 已齊）。
- 測試：notifier 單測——429 quota 異常 → state 為 quota 不足而非 retriesRemaining=0；widget 測——quota 卡片文案 + 升級鈕。

## 問題 2：實扣顯示「只看過一次，後來都沒出現」

**現象**：分析完「扣幾則」提示不明顯，只見過一次。

**根因**（設計選型，非壞掉）：

- 實扣顯示是 floating SnackBar（`analysis_screen.dart:2577`「本次分析使用 N 則」），僅分析完成現場彈一次（`_syncSubscriptionUsageFromResult` :2561-2579，`showChargeToast: true` 只在 streaming done :3573-3623 與 optimize :3738）；hydration 回看路徑刻意不彈（:826）。
- 放大因素：後續分析撞 429 失敗 → 無 usage → 無 toast（與問題 1 同源）；`recognizeOnly` 模式 `messagesUsed = 0` 不顯示（server index.ts :6070/:6587）。

**修法**：

- 結果區（正常化摘要附近）加常駐一行「本次分析使用 N 則・剩餘 M 則」，隨 `lastAnalysisSnapshotJson` 持久化，回看也顯示。
- SnackBar 保留（即時感知），不再是唯一載體。
- 「剩餘 M 則」：先確認成功路徑 `usage` 物件是否已帶 remaining；沒有則 server 補欄位（小改，欄位新增向後相容）。

## 順序

1. 修問題 1（P1，直接傷 Free→付費轉換漏斗）。
2. 修問題 2。
3. 兩案一起開 queue item 丟 Codex 實作雙審 → APPROVED → 回 Bruce。
