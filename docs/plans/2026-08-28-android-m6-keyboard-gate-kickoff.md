# Android M6 Keyboard Gate K Kickoff（Frozen Phase A）

> 日期：2026-08-28（Asia/Taipei）
> Base：`828d6cded8329407f649d05738d0cf0f08cf1a95`
> Branch：`codex/android-m6-keyboard-gate-20260828`
> 角色：Luna Max＝coding owner；Codex＝coordinator／主 reviewer；Claude＝privacy-risk independent reviewer
> Delivery：只在 Android M6 隔離分支完成 KEY-00 prototype 與證據；不合 `main`、不操作 production 或商店後台

## 來源與本輪目標

本輪落實 Frozen Spec v1 的 `KEY-00`，並遵守以下文件順序：

1. `docs/plans/2026-08-21-android-public-release-roundtable-spec.md`
2. `docs/plans/2026-08-21-android-public-release-implementation-plan.md`
3. 本文件

目標是建立一個獨立於正式主 App 流程的最小 Android IME screenshot feasibility prototype，以及可重複量測的 Gate K 證據工具。這不是正式 Android AI 鍵盤；`KEY-01`～`KEY-05` 在 Codex 對完整 Gate K 證據判定 `pass` 前一律封鎖。

## 凍結的公開測試邊界

測試只允許落在以下 public seams，不得綁死 private helper 或內部呼叫順序：

1. **IME session lifecycle seam**：公開的開始／結束 session 事件可產生單調 session floor；只有本次 IME 顯示後的候選能被接受。
2. **Screenshot observation seam**：輸入一組具時間、來源與尺寸 metadata 的公開候選事件，可得到接受、忽略或拒絕的明確結果。
3. **Candidate identity seam**：公開內容 hash／identity 能處理 observer 抖動與重送，同張圖在同一 session 只接受一次。
4. **Permission／policy invariant seam**：公開 manifest／prototype contract 可被自動檢查，權限白名單明確，且完全沒有 `AccessibilityService`。
5. **Evidence aggregation seam**：公開 trial record 可產生原始成功／失敗數、成功率、p50／p95 latency 與門檻判定；不得用人工改寫 summary 取代原始紀錄。

## Phase A frozen behavior

- prototype 必須能在最小 `InputMethodService` 顯示期間觀察其他 App 產生的 screenshot 候選。
- 只允許候選 Android API／MediaStore 路徑；每項 Android permission 都要列入白名單並能對映 Play 政策。
- 禁止 `AccessibilityService`，也不得以廣泛檔案權限、背景爬圖或其他方式繞過 screenshot／圖片存取限制。
- 只接受本次 IME session floor 之後的新 screenshot；舊圖、非預期圖片、錯 session 與 observer 重送都必須 fail closed。
- 同一張圖只能產生一次接受事件；prototype 不得呼叫 AI、上傳圖片、扣 quota 或記錄聊天內容。
- 若每次或反覆要求使用者重選「部分照片存取」，即屬 manual fallback，不算 exact flow。

## TDD 垂直切片

1. session floor：一個 failing public test → 最小 lifecycle contract → focused test 綠。
2. candidate filtering：逐一加入舊圖、錯來源、錯時間與錯 session failing test → 最小 fail-closed 實作。
3. hash／dedupe：observer 重送與同圖重建 failing test → 最小 identity／dedupe 實作。
4. permission／privacy：先寫會抓出 AccessibilityService／未白名單權限的 contract test，再補最小 prototype manifest。
5. evidence aggregation：先寫 trial threshold／latency failing test，再補 deterministic summary；最後才接 emulator instrumentation。
6. 迭代中只跑 focused tests；候選完成後才跑完整 Flutter／Android gate、`flutter analyze`、`git diff --check` 與 exact-SHA CI。

## Gate K 證據矩陣

- emulator：API 34、35、36。
- physical：至少一台 stock Android 14+、一台 Samsung One UI 6+。
- 每一類至少 40 次。
- IME 顯示後跨 App screenshot 在 3 秒內成功率至少 95%。
- 證據要保留裝置／OS、每次成功或失敗、latency、p50／p95、session／dedupe 結果、權限畫面、政策連結與可重現失敗步驟。
- emulator 單獨全綠不能宣告 Gate K `pass`；兩類實機證據與政策對照仍是硬前置。

## Codex 三選一裁決

- `pass`：量化門檻、session／dedupe、permission path 與 policy path 全部通過，才開放 `KEY-01`～`KEY-05` 正式實作。
- `proven fail`：有可重現的技術或政策阻擋，才開放既已核可的 `KEY-FB` manual Photo Picker／Sharesheet 路徑。
- `inconclusive`：停止探索並回 Eric 決定；不得自行視為失敗、不得偷換 fallback。

## Stop conditions 與排除項目

- 最多投入 3 個實際工作日；等待裝置、帳號或外部回覆不計入。任何延長最多 1 日，且必須另得 Eric 明確同意。
- 任一敏感資料、廣泛權限或 Play 政策風險未釐清，不得判定 `pass`。
- 若實作開始觸及正式 `KEY-01`～`KEY-05`、AI 上傳、quota、Supabase／Edge、RevenueCat／Play、credential、production、store release 或 `main` 合併，立即停止。
- prototype 與證據可以留在本隔離分支供審查，但 Gate K 未通過前不合入正式發行線。

## Phase A exit

- public-seam tests 與 prototype instrumentation 綠。
- API 34／35／36 emulator 原始試驗證據齊全，且沒有 AccessibilityService／未核可權限。
- Codex 完成 exact-SHA 主審，Claude 完成隱私風險唯讀獨立審查，無未解 P0／P1／P2。
- 只稱 **M6 Gate K emulator candidate**；未取得兩類實機各 ≥40 次與政策證據前，不稱 M6 完成，也不開始正式鍵盤。
