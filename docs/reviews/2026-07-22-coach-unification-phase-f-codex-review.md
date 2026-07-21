# 教練統一 Phase F 收尾包 — Codex 審查紀錄（2026-07-22）

## 範圍

Commit range `213f8f82..22b9a2cc`（共 5 commit）：

- `cc02261f` partnerId 切換重置 auto-focus 閂鎖（Task7 記債 1）
- `76b0b96a` `openCoachInputOnFirstBuild` 改名 `openCoachInputRequested`（Task7 記債 3）
- `995e2cfa` deep-link 意圖事件改名 `CoachOpenCoachIntentEvent`＋刪零 emit 舊事件（Task7 記債 2）
- `91f4c215` 刪除舊 coach_follow_up engine 死叢集（7 lib＋7 test 檔＋LEGACY helper，−3996 行）
- `22b9a2cc` snapshot＋Phase E 計畫檔記債清償註記

風險級別：中風險（coach 區死碼刪除＋rename，不碰 billing/wire）→ 依計畫走單審。

## Verdict：APPROVED（零 P0/P1/P2）

Codex 審查重點與結論：

- 死叢集刪除：`lib`/`test` 對已刪 providers/api/widgets/helpers 零殘留引用。
- Deep-link focus 路徑：`openCoachInputRequested` 經 `PartnerDetailScreen` → `CoachFollowUpSection` → `CoachSurface` 流通，無 legacy sheet/generate 路徑。
- Quota/429：統一 `coach-chat` 路徑仍區分 `MODEL_RATE_LIMITED` 與真 quota 耗盡，不會誤開 paywall。
- 閂鎖修復：parent/orchestrator/section 三層 reset 行為一致。
- `git diff --check` 乾淨。

## Nit 處置

Codex 提一條非阻斷 nit：`coach_follow_up_phase.dart:12` 註解仍提 `coach_follow_up_invoked.phase`。**查證後判定假陽性不改**——該註解描述的是 server 端 telemetry，`coach-follow-up` Edge function 至今仍發 `coach_follow_up_invoked` 事件（`supabase/functions/coach-follow-up/generation.ts:113`）；Phase F 改名的是 client 端 analytics 事件類（`CoachOpenCoachIntentEvent`），兩者不同層。

## CC 側驗證證據（Codex sandbox 唯讀無法跑 Flutter，由 CC 補）

- `flutter analyze`：No issues found（580.3s）。
- `flutter test --concurrency=1`：All tests passed（2206 passed／4 skipped；基準 2332 扣除刪除的 7 個測試檔屬預期）。
- 死叢集 9 關鍵字＋`openCoachInputOnFirstBuild` grep 歸零；`hive_registrar.g.dart` 無變動；`pubspec.lock` 未入任何 commit。
