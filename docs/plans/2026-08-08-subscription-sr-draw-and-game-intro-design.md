# 訂閱送 SR 限定翻牌＋Game 教學卡觸發改版（設計）

2026-08-08 與 Eric 對話拍板。背景：真機（build 411）發現 Game 教學卡實質上「抽到 SR 才看得到」——
教學卡只在首次真正進入 Game 模式時彈出，而進 Game 被 `rarity == SR` 硬擋；非 SR 點 Game 分頁只閃
鎖定字幕。Free 終身只有起步清單 1 抽、SR 機率 10%，九成 Free 用戶永遠不認識 Game 玩法。

## 現況事實（真相源）

- 每日免費翻牌：Free 0 / Starter 3 / Essential 5，台北中午 12:00 重置（`draw_decision.ts`）。
- 起步清單完成＝一次性 +1 贈抽，全 tier（`practice_draw_bonuses`，user_id PK 一人一列）。
- SR 權重 10%（R 30%、N 60%，`practice_persona.ts`）。
- 教學卡已內建 Free 訂閱鈎子（`showUpgradeHook` → 查看方案 → paywall）。
- 推論：Starter 每日 3 抽，一週累積 SR 機率約 89%——訂閱用戶遲早有 SR。「訂閱送 SR」真實成本低，
  價值在「立即解鎖 Game」的儀式感與轉換鈎子。

## 拍板決定

### 1. 教學卡觸發改版：點 Game 分頁就開，不分 N/R/SR

- 點鎖定的 Game 分頁 → 直接開教學卡（取代只閃鎖定字幕）。首次進 Game 自動彈的既有邏輯照舊。
- 教學卡 CTA 分流：
  - Free：鈎子文案升級為明講「訂閱送一次 SR 限定翻牌，馬上解鎖 Game」→ paywall。
  - 已訂閱但當前角色非 SR：CTA 改「去圖鑑翻牌」（他有每日額度，不該看到升級話術）。
  - SR 局（現況）：照舊，重看教學。

### 2. 訂閱享有一次 SR 限定翻牌

- 權益：Starter 與 Essential 相同，終身一次，保底 SR 的翻牌（復用抽卡儀式，不做直接發卡）。
- 抽選：沿用現有抽選/去重邏輯，僅 rarity 鎖 `sr`。
- 帳本：沿 `practice_draw_bonuses` 先例新增 source（如 `subscription_sr`）。**注意現表 PK 是
  `user_id` 一人一列，須改 PK 為 `(user_id, source)` 或另開一表**（migration 時定，走
  shared-agent-rules 目標式 migration，禁 `supabase db push`）。
- Grant：client 偵測有效訂閱且未領 → best-effort 呼叫；**server 端以 RevenueCat 驗證後的 tier
  把關**（比清單訊號強，不信 client 宣稱）。INSERT ON CONFLICT DO NOTHING 冪等。
- 回溯：既有有效訂閱者首次跑到新版同一條檢查路徑自然補發（dogfood 友好，Eric sandbox 可驗）。
- 消耗：顯式 claim（點券才抽），不用懶標記——這張券強制 rarity，抽卡請求必須知道自己是 SR 券。
  走 `claim_draw_bonus_atomic` 式 RPC：DB 交易 row lock＋idempotent＋consumed 與抽卡結果原子
  （quota 高風險區鐵律：訂閱鎖後二次 replay 檢查）。
- 重裝/restore 不重複送：一人一列天然擋。

### 3. 儀式感：兩層，不打斷原任務

- 訂閱成功當下：輕慶祝——成功回饋多一張小卡「🎴 已解鎖：SR 限定翻牌 ×1」，點了才去圖鑑。
- 持久入口：圖鑑抽卡區一張限定樣式金券（與每日翻牌明顯區隔），未用掉就一直在——本身就是
  「有好東西等你」的提醒，不另做推播/紅點。高級感發生在他自己翻開那一刻（保底 SR 抽卡動畫）。

### 4. Free 鉤子：三處講同一句話「訂閱送 SR 限定翻牌，立即解鎖 Game」

1. Game 教學卡（意圖最強時刻，見決定 1）。
2. 圖鑑抽卡區：Free 看到同一張券的上鎖狀態（灰階＋鎖頭），點開 paywall。訂閱前後視覺連續。
3. Paywall 方案卡：Starter 與 Essential benefit 各加一行（順帶回答「哪檔才有」——兩檔都有）。

### 刻意不做

- 抽到 N/R 的結果瞬間插「訂閱直接拿 SR」——失落時刻推銷傷產品感。
- 直接發卡進圖鑑的新儀式動畫——復用抽卡儀式即可。

## 驗證要點

- Edge：`draw_decision`/handler deno test 補 SR 券路徑（rarity 鎖定、冪等、consumed 原子性）；
  ledger 併發可用 WSL PG16 跑真併發 smoke。
- Client：教學卡觸發矩陣 widget test（Free 鎖定點擊/已訂閱非 SR/SR 局）；券的三態
  （鎖定/可用/已用）。
- 高風險區（訂閱/quota/paywall）：實作批走 Codex 雙審。
