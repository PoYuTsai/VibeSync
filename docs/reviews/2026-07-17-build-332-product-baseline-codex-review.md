# 2026-07-17 Build 332 產品基線 Codex Review

狀態：`CODE_REVIEW_APPROVED_WITH_EXTERNAL_GATES`

## Scope

- Base：`a80ac2e0`（本 branch 上一個已提交版本）
- Branch：`codex/launch-hardening-20260717`
- Intent：把 1.0.1 Build 332 收斂成可直接產生新 build 的產品基線：既有 Sonnet 主路徑升級 Sonnet 5、Free 分析提供延展＋調情、投入度顯示分數九折，以及恢復 OCR 滑動教學與長等待狀態切換。
- Scope check：`CLEAN`。程式變更只涉及上述產品行為、對應測試、版本號與 current-truth 文件；前一段 launch-hardening commits 沿用 `docs/reviews/2026-07-17-launch-hardening-codex-review.md` 的審查證據。
- Review 方式：同一 Codex thread 在完成實作後重新載入完整 diff 與高風險 checklist 做 adversarial review；不是獨立 reviewer。

## 高風險不變條件

1. Sonnet 5 是 production 主模型；`analyze-chat` 的 4.6 只保留為 `sonnet-5 → sonnet-4-6 → haiku` 降級鏈、強制測試相容與未知模型保守成本基準。
2. Free `analyze-chat` 的 server entitlement 固定為 `extend`＋`tease`；Free Opener 另外使用 `extend` allowlist，沒有跟著擴權。
3. 已升級使用者仍可辨識並刷新舊的單一 `extend` 與新的 Free 雙風格封存結果；Free 結果固定保留完整五風格升級入口。
4. 投入度校準只在共用完成後處理的最後一步執行一次；先完成 fallback、風格選擇與安全檢查，再把 client score 設為 `ceil(clamp(raw, 0, 100) × 0.9)`。Prompt、AI 推理、quota 與回覆選擇不變。
5. App 的投入度等級與 hero 文案由校準後分數重新計算，因此 82 → 74 時會同步從「高度投入」變成「投入明顯」，不會數字與文字矛盾。
6. OCR 仍只有一個 `recognizeOnly` request，不串流中間文字或分析結果；client 只在 0.7／4／9／15 秒切換等待文案，response、exception 與 dispose 都會取消後續 timer。
7. OCR 滑動教學每次 dialog 開啟只播放一次，不會循環；真實操作、全設為對方、reduce-motion 與關閉 dialog 都有取消或靜態替代路徑。
8. 這輪沒有修改 DB schema、Edge response schema、OCR prompt、quota、扣費、timeout、RevenueCat 或本地歷史資料；舊分數不做不可逆回寫。

## Review findings

正式審讀前已自動修正三個一致性問題：

1. 把仍描述付費 Sonnet 4.6／Free 單一回覆的 current-truth、定價與 App Review 文件同步成 Build 332 現況。
2. 把投入度輸入先限制在 0–100 再九折，避免異常 AI 值造成負分或超過 90；補上 120、-10、null 與空字串測試。
3. 確認畫面等級由校準後 score 推導；server 原始 `level` 只保留既有策略判斷，不用來渲染 score hero。

最終 adversarial review 沒有發現剩餘 P0／P1／P2 程式碼問題。

## Verification

- `flutter analyze`：No issues found。
- `flutter test --concurrency=1`：2,251 passed、0 failed、4 skipped。
- `deno test --allow-read --allow-env supabase/functions/analyze-chat/`：614 passed、0 failed。
- Coach／Follow-up Edge tests：221 passed、0 failed。
- Practice Edge tests：914 passed、0 failed。
- Free 雙風格＋投入度 targeted Edge tests：112 passed、0 failed。
- Paywall＋付費刷新 targeted Flutter tests：51 passed、0 failed。
- OCR targeted Flutter tests：30 passed、0 failed。
- `deno check`：`analyze-chat`、`coach-chat`、`coach-follow-up`、`practice-chat` production entrypoints 全部通過。
- Deno／Dart format、`git diff --check`：通過。
- `AGENTS.md`／`CLAUDE.md` SHA-256：一致。

## 尚未完成的外部硬閘門

以下不影響 repo 產生 Build 332，但完成前不能宣稱本輪已可正式送審：

1. 必須在 macOS 產 signed iOS Build 332，並確認 archive 含 `VibeSyncKeyboard.appex`。
2. 必須用 iPhone 真機驗證 Free 雙風格、付費 Sonnet 路由的實際結果、82 → 74 校準、OCR 每次開啟動畫、4／9／15 秒等待狀態、訂閱升降級與鍵盤非測試 quota／HTTP 並行／lost-response／Full Access。

Production keyboard gate 已於 2026-07-17 依 DB → Secret → JWT-verified Edge v5 → live contract 完成；DB transaction 與測試帳號 fresh／replay／mismatch smoke 通過。證據見 `docs/reviews/2026-07-17-keyboard-production-deployment.md`。

## Verdict

`APPROVED FOR BUILD 332`，但 `NOT YET APP REVIEW READY`。Repo 層與 production keyboard backend gate 已收斂；signed iOS、非測試 quota／HTTP 並行與 lost-response、隱私揭露及 iPhone 真機證據仍是送審前硬條件。
