# AI 實戰練習室每日翻牌機制設計
Date: 2026-06-26
Status: Draft for Eric / Bruce review
Scope: practice-chat Flutter client, Supabase Edge `practice-chat`, paywall copy, quota ledger

## 背景

AI 實戰練習室已經有 60 位陪練女孩、照片、基本資料、20 則一輪、最多續玩 3 輪。下一個產品問題不是「缺女生」，而是「一次全部隨機換，使用者很快就失去新鮮感」。

這次要加「每日翻牌」入口，讓使用者每天回來都有一個新女孩可抽，並把它接到付費方案。夥伴提供的方向是：

- 每日可以翻一個新人物卡，避免很快膩。
- Free 每日 1 次，Starter 每日 3 次，Essential 每日 5 次。
- 每日中午 12:00 重置。
- 免費次數用完後，Starter / Essential 額外翻一次扣 5 則。
- Free 不開放額外扣 5 則翻牌，改引導升級。
- 首屏可以出現模糊小縮圖牆，文案「每日登入就送新女孩」。
- 翻牌動畫希望高度還原參考影片：背面出現、翻轉、光圈、正面人物卡、資料展開。

## 產品判斷

### 為什麼不是完全免費無限換

60 位女孩如果一開始無限換，用戶會快速刷完，對「每天回來」沒有拉力。每日翻牌把女生變成輕量收集感，但不把主產品變成抽卡遊戲。

### 為什麼 Free 不扣 5 則額外翻牌

Free 每日只有 15 則。如果用 5 則換一次人，等於花掉三分之一聊天額度，容易讓使用者覺得被懲罰，也會降低真正練習聊天的機會。Free 的限制應該是升級誘因，不是消耗陷阱。

### 為什麼 Starter / Essential 可以扣 5 則

Starter 每日 50 則、Essential 每日 120 則。5 則作為額外翻牌成本足夠有感，但不至於太痛。它讓重度用戶能多探索，也讓方案價值更清楚。

### 為什麼目前不把難度綁死在角色上

夥伴提到「不同角色有不同難度，不要給選，像抽卡收集」。這是後續方向，但 MVP 先保留現有難度 chips，原因：

- 現有練習室已經有難度切換，突然移除會讓控制感下降。
- 角色收集和難度抽取是另一層遊戲化，會牽涉稀有度、保底、付費感知，現在不適合一次做太重。
- MVP 先驗證「每日翻牌 + 高質感揭卡動畫 + 付費限制」是否提高回訪和升級意願。

後續可以在每張卡顯示「個性傾向 / 互動難度傾向」，但不在本版強制難度。

## 核心規則

### 每日翻牌額度

以 Asia/Taipei 時區中午 12:00 為每日重置點。

```text
如果現在時間 >= 今日 12:00，windowStart = 今日 12:00
如果現在時間 < 今日 12:00，windowStart = 昨日 12:00
nextResetAt = windowStart + 24 小時
```

方案額度：

```text
Free: 每日免費 1 次
Starter: 每日免費 3 次
Essential: 每日免費 5 次
```

額外翻牌：

```text
Free: 不開放，顯示升級
Starter: 免費次數用完後，每次扣 5 則
Essential: 免費次數用完後，每次扣 5 則
```

額外翻牌扣的是一般訊息 quota，必須同時檢查每日與每月剩餘額度。扣費必須 server-side atomic，不可靠 client 計數。

### 翻牌和聊天扣費分離

翻牌只決定「今天遇見誰」，不等於開始一輪練習。

```text
翻牌成功：可能免費，也可能扣 5 則，回傳 profileId
第一次 AI 成功回覆：再扣 1 則，開啟 20 則 AI 回覆的一輪練習
續玩同一位：另開 billing session，再扣 1 則，給下一輪 20 則
```

### 同一位和換一位

- 續玩同一位不翻牌，不消耗每日翻牌次數，不改 profileId。
- 換一位才走翻牌流程。
- 切換難度不翻牌，不消耗每日翻牌次數，不改 profileId。
- 第一次進入 AI 實戰練習室，如果沒有今日已揭示的 draft card，要顯示翻牌入口，不直接把女生完整露出。
- 如果使用者翻牌後還沒開始聊天就離開，回來應保留這張已揭示卡，不重扣。
- 如果 draft card 跨過下一個中午 12:00 且仍未開始聊天，回來可以重新顯示翻牌入口，讓使用者拿今天的新卡。

### 今日重複

同一個使用者在同一個 reset window 內，盡量不要抽到同一張 profile。若 60 張都已用完，可允許重複，但 MVP 正常情況不會到這個量。

### 測試帳號

`vibesync.test@gmail.com` 延續既有測試帳號策略：可用來驗證 flow。建議 server 仍記錄 draw event，但 quota 扣費可沿用既有測試帳號免扣邏輯，避免測試成本污染真 quota。

## 主要 UX

### 1. 未揭牌狀態

在 AI 實戰練習室首屏，取代目前直接露出女生 hero。

視覺：

- 深色背景沿用練習室。
- 中央一塊模糊縮圖牆，使用 8 到 12 張女孩照片拼成小格。
- 縮圖牆上方或中央覆蓋大字：「每日登入就送新女孩」。
- 下方顯示剩餘翻牌次數，例如：

```text
今日免費翻牌 1/1
中午 12:00 重置
```

或：

```text
今日免費翻牌已用完
額外翻牌 5 則 / 次
```

按鈕：

```text
翻開今日女孩
```

若 Free 免費次數已用完：

```text
升級解鎖更多女孩
```

### 2. 翻牌動畫

目標是高度還原參考影片，不只是淡入一張照片。

動畫階段：

1. 模糊縮圖牆微暗，按鈕消失。
2. 卡背在中央浮出，帶微光邊框。
3. 卡片做 3D Y 軸翻轉，帶 perspective。
4. 翻到 90 度時切換卡面。
5. 金色光圈繞卡片一圈，伴隨少量 sparkle。
6. 正面卡靜止，顯示照片、姓名、年齡、城市。
7. 卡面展開成既有 profile hero，顯示完整資料與輸入框。

建議總時長約 2.6 到 3.0 秒：

```text
teaser dim: 250ms
card back enter: 350ms
flip: 1000ms
front settle: 450ms
profile expand: 650ms
```

需要尊重 iOS reduce motion。若 `MediaQuery.disableAnimations` 或 accessibility reduce motion 開啟，跳過翻轉與光圈，直接顯示揭示後的 profile hero。

### 3. 揭牌後首屏

揭牌後顯示目前既有 profile hero，但第一眼要更像「我真的遇到這位女生」：

- 大照片仍是首屏重點。
- 姓名、年齡、職業、城市保持可見。
- 顯示興趣 / 個性 / 生活 tags。
- 顯示自我介紹。
- 難度 chips 可以留在上方或 hero 外，文案避免蓋過照片。
- 保留「點擊圖片看全圖」提示和已完成的全圖 viewer。

### 4. 已開始聊天

聊天後用 compact header：

```text
小圓照片 + Name · profession · age · city · difficulty
```

點 header 或照片打開 profile bottom sheet。

### 5. 換一位

在沒有訊息前：

- 「換一位」改成「再翻一張」或「換一位」都可以，但必須走 server draw，不再 client-side random。
- 免費次數未用完：免費翻。
- 免費次數用完且 Starter/Essential：顯示「再翻一張 · 5 則」。
- Free 用完：進 paywall。

在一輪結束後：

- 「換一位」同樣走翻牌流程。
- 這會開新 visible thread，不保留前一位 transcript。

## Paywall 規格

在方案比較表加入：

```text
每日免費翻牌 | 1 次 | 3 次 | 5 次
額外翻牌 | 升級解鎖 | 5 則 / 次 | 5 則 / 次
AI 陪練女孩 | 限量 | 開放 | 開放
```

AI 模型文案延續已修規格：

```text
AI 模型 | 經濟型 | 高階型 | 高階型
```

從翻牌限制進入 paywall 時，頂部文案要和情境連動：

```text
想每天遇見更多陪練女孩？
Starter 每天 3 次，Essential 每天 5 次，還能用 5 則額外翻牌。
```

## Server Contract

在 `practice-chat` Edge Function 增加新 mode：

```json
{
  "mode": "draw_profile",
  "requestId": "uuid",
  "currentProfileId": "practice_girl_006",
  "visiblePracticeThreadId": "optional-local-thread-id"
}
```

成功回應：

```json
{
  "profile": {
    "profileId": "practice_girl_043",
    "nameId": "vicky",
    "professionId": "dental_assistant",
    "photoId": "practice_girl_043",
    "personaId": "playful_direct"
  },
  "draw": {
    "costMessages": 0,
    "freeAllowance": 3,
    "freeUsed": 2,
    "freeRemaining": 1,
    "extraCostMessages": 5,
    "nextResetAt": "2026-06-27T04:00:00.000Z"
  },
  "usage": {
    "monthlyUsed": 123,
    "monthlyLimit": 300,
    "dailyUsed": 12,
    "dailyLimit": 50
  }
}
```

Free 用完：

```json
{
  "error": "practice_draw_upgrade_required",
  "message": "升級後每天可以翻更多陪練女孩。",
  "draw": {
    "freeAllowance": 1,
    "freeUsed": 1,
    "freeRemaining": 0,
    "extraCostMessages": 5,
    "nextResetAt": "2026-06-27T04:00:00.000Z"
  }
}
```

Starter/Essential 額外翻牌但 quota 不足：

沿用現有 429 quota payload，不回傳新 profile，不寫 draw event，不扣費。

## DB / Ledger

新增 draw ledger，因為它會影響 quota。不能只存在 client。

建議表：

```sql
create table practice_profile_draw_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  request_id text not null,
  profile_id text not null,
  tier_at_draw text not null,
  reset_window_start_at timestamptz not null,
  cost_messages integer not null check (cost_messages in (0, 5)),
  created_at timestamptz not null default now(),
  unique (user_id, request_id),
  unique (user_id, reset_window_start_at, profile_id)
);
```

需要 SECURITY DEFINER RPC，讓「檢查免費次數 / 檢查 quota / 扣 quota / 寫 event」在同一個 transaction 完成。

RPC 最低要求：

- 同一個 `requestId` 重試不重複扣費。
- 免費次數用完且 Free 時不寫 event、不回 profile。
- Starter/Essential 額外翻牌要 atomic 扣 5 則。
- quota 不足時不寫 event、不回 profile。
- 回傳最新 usage，讓 client 同步 quota 顯示。

## 非目標

本版不做：

- 稀有度、星等、保底、收藏冊。
- 強制不同角色綁不同難度。
- 把 profile 全部存 server DB 動態管理。
- 遠端圖片下載或線上圖片生成。
- 完整 poker 遊戲機制。
- 無限翻牌。
- 用真實品牌、真實公司制服、真實航空公司 logo。

## 風險

- 這是 quota/paywall/Edge schema 高風險區，push 前必須 Codex review。
- 新 migration 必須用 Supabase MCP `apply_migration` 套 prod，不要用 `supabase db push`，因為目前本機 migration 版本號與遠端已有已知分歧。
- 翻牌動畫若做太重，容易拖慢首屏或造成 iPhone 低階機卡頓。動畫必須可跳過且減少 layout thrash。
- 如果 draw mode 放在 `practice-chat` function，必須確保 draw 不需要 `DEEPSEEK_API_KEY`，否則圖片翻牌會被 AI key 設定誤擋。
- 不能讓舊 client 壞掉。`chat` 和 `debrief` mode 必須保持現有 schema 向下相容。

## 驗收標準

### 產品

- Free 每天第一次能翻牌，第二次引導升級。
- Starter 每天前三次免費，第四次扣 5 則。
- Essential 每天前五次免費，第六次扣 5 則。
- 中午 12:00 後免費次數重置。
- 翻牌後離開再回來，不重扣，仍看到同一位。
- 換一位會換照片 / 姓名 / 職業 / profileId。
- 續聊同一位不換照片 / 姓名 / profileId。
- 切難度不換人。
- Chatbot prompt 收到的 profile ids 與 UI 顯示的女孩一致。
- Paywall 顯示每日免費翻牌和額外翻牌 rows。

### 視覺

- 未揭牌首屏能清楚看到模糊縮圖牆和「每日登入就送新女孩」。
- 翻牌動畫包含卡背、3D 翻轉、金色光圈、正面人物卡、展開資料。
- 圖片不嚴重裁切，點擊可看全圖。
- reduce motion 時不會卡住或空白。

### 技術

- Deno tests 全綠。
- Flutter practice_chat targeted tests 全綠。
- Paywall widget tests 全綠。
- `flutter analyze lib` 無 issue。
- Codex review 無 P0/P1；P2 必須修或明確取得 Eric 接受。
