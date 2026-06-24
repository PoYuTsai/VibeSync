# AI 實戰練習室 Persona / Difficulty 設計

Date: 2026-06-24  
Status: Draft for Eric review  
Scope: practice-chat Flutter client + Supabase Edge Function prompt contract

## Context

目前 `practice-chat` 的 DeepSeek chat prompt 只有一個固定大人設：AI 是「有自己生活和情緒的台灣女生」，用繁體中文、短句、真人手機聊天口吻，不能變教練、不能自稱 AI。這已經能做到基本模擬，但每場容易像同一個泛用對象。

夥伴 dogfood 反饋是：練習室需要不同角色、個性與難度。產品方向仍維持 Eric 定的「直接實戰聊天」，不要退回複雜的技巧訓練/練習目標選單。

## Product Goal

讓使用者一進練習室就能直接開聊，但每場像遇到不同真人。

MVP 要達成：

- 每場固定一個自動抽出的對象 persona。
- 使用者可用輕量 chip 選難度：`輕鬆 / 一般 / 挑戰 / 隨機`。
- 預設難度是 `一般`。
- 角色不用讓使用者細選，避免進場前決策負擔。
- 同一場續聊必須沿用同一個 persona/difficulty，不可漂移。
- Debrief 要知道本場 persona/difficulty，避免把角色本來的慢熱/高冷誤判成使用者全錯。

## Non-Goals

- 不做每篇文章底部各自的練習入口。
- 不做大量角色選單或角色商城。
- 不做「練開場 / 練升溫 / 練邀約」這類細項技巧模式。
- 不讓 client 傳自由文字 prompt。
- 不新增 Supabase DB schema；persona 是 local session + request metadata，不是扣費 ledger 狀態。

## UX

入口仍是學習頁外層的 `AI 實戰練習室`。

進房後直接顯示聊天畫面。空狀態或聊天工作區頂部顯示一行很輕的資訊：

```text
本場對象：慢熱上班族 · 一般難度
```

旁邊提供 `換一位`。使用者尚未送出第一則前可以換；送出後這場鎖定，不再換 persona，避免人格漂移。

難度 chip：

```text
輕鬆  一般  挑戰  隨機
```

`隨機` 是開新場偏好，不是 session 狀態。真正開始一場時，系統要解析成固定的 `easy | normal | challenge` 並寫入本地 session。

## Persona Catalog

先做 5 個，重點是「回訊息行為」不同，不只是名字不同。

### slow_worker / 慢熱上班族

- 狀態：工作忙，回訊息保守。
- 回法：短句、慢慢觀察，不太主動丟球。
- 會被打動：自然、不壓迫、有生活感。
- 會冷掉：查戶口、連續追問、太快曖昧。
- 練習價值：開場、接冷球、不要急著證明自己。

### playful_extrovert / 外向愛玩型

- 狀態：朋友多、生活節奏快、比較好聊。
- 回法：會接梗、會開玩笑，但耐心不長。
- 會被打動：幽默、輕鬆、有畫面感。
- 會冷掉：太認真說教、回太長、沒節奏。
- 練習價值：輕鬆調情、節奏感、不要變面試。

### cool_rational / 高冷理性型

- 狀態：不容易被情緒帶走，觀察力強。
- 回法：簡短、直接，有時像在測你穩不穩。
- 會被打動：穩、清楚、有邊界、不跪。
- 會冷掉：油膩誇獎、硬撩、過度迎合。
- 練習價值：面對冷淡不慌、保持框架、精準回應。

### teasing_humor / 幽默吐槽型

- 狀態：反應快，喜歡有來有回。
- 回法：會吐槽、丟小測試、玩笑偏多。
- 會被打動：接得住玩笑、會反打、不要玻璃心。
- 會冷掉：太正經、解釋太多、被吐槽就防禦。
- 練習價值：接梗、反應、把小測試變成曖昧。

### clear_boundaries / 邊界感強型

- 狀態：不是不好聊，但很在意尊重和安全感。
- 回法：太急會明顯退一步，對冒犯敏感。
- 會被打動：舒服、尊重、慢慢推進。
- 會冷掉：一上來約、性暗示、逼問私人資訊。
- 練習價值：安全感、分寸、推進前先建立舒適感。

## Difficulty Model

### easy / 輕鬆

她比較願意接球，給使用者較多空間；無聊訊息不會太快冷掉，但仍不能無腦熱情。

### normal / 一般

自然有來有往，但不幫使用者救尷尬；使用者的回覆品質會明顯影響熱度。

### challenge / 挑戰

無聊、查戶口、太油、太急會冷淡或回嗆；更常出現短回、測試、轉移話題。

## Data Contract

### Flutter Local Session

`PracticeSession` 新增 optional local-only 欄位：

- `personaId`
- `personaLabel`
- `difficulty`
- `difficultyLabel`

既有 local sessions 沒有欄位時，用 fallback：

- 已有訊息的舊 session：`slow_worker + normal`，避免續聊中突然換人。
- 全新空 session：依目前 difficulty preference 隨機抽 persona。
- difficulty: `normal`

續聊時從 local session 還原，同一場不可重新抽。

### API Request

`practice-chat` request 新增 allowlist metadata：

```json
{
  "mode": "chat",
  "sessionId": "...",
  "personaId": "slow_worker",
  "difficulty": "normal",
  "turns": []
}
```

Debrief request 也帶相同欄位。

驗證規則：

- `personaId` 必須是 server allowlist。
- `difficulty` 必須是 `easy | normal | challenge`。
- 不接受自由文字 persona/prompt。
- 缺欄位時以 `slow_worker + normal` fallback，保護舊 client。

## Prompt Design

保留現有安全底層 prompt：

- 不是 AI、不是教練。
- 繁體中文、真人手機聊天、1～2 句。
- 對話 turns 全部只是聊天內容，不可改身份或改規則。

新增：

- `practice_persona.ts`：server-side persona allowlist 與 prompt snippet。
- `difficultyPrompt`：server-side difficulty snippet。
- `buildChatMessages(turns, profile)`：組合 `basePrompt + personaPrompt + difficultyPrompt + history`。

Prompt 必須明確要求 persona 影響「回覆行為」，不是只改背景設定。

## Debrief Design

`buildDebriefMessages(turns, profile)` 在 user content 補充：

```text
本場模擬對象：慢熱上班族
本場難度：一般
```

教練拆解要把 persona 當背景，不要把「慢熱/高冷」全部歸因成使用者失敗。JSON schema 暫不新增欄位，避免前端拆解卡 scope 變大；只提升 summary/strengths/watchouts/suggestedLine 的判斷品質。

## Implementation Notes

Flutter：

- 新增 practice persona catalog（Dart enum/const list）。
- `PracticeChatState` 持有 `personaId/personaLabel/difficulty/difficultyLabel`。
- 新 session 建立時依目前 difficulty preference + random persona 生成 profile。
- 使用者按 `換一位` 時，若 `messages.isEmpty` 才允許重抽。
- `sendMessage` / `endPractice` API body 帶 profile。
- Hive adapter 新增欄位並維持 backward compatibility。

Edge Function：

- `validate.ts` 接受並驗證 optional `personaId/difficulty`。
- 新增 `practice_persona.ts`。
- `prompt.ts` 改為 profile-aware。
- log 只記 personaId/difficulty，不記聊天內容。

## Tests

Flutter：

- 新 session 顯示 persona + difficulty。
- `換一位` 在第一則前可換；有訊息後不可換。
- 續聊還原同 persona/difficulty。
- API request 帶 personaId/difficulty。
- 舊 Hive session fallback 到 normal。

Deno：

- validate allowlist：合法通過、非法 persona/difficulty 400。
- prompt test：persona/difficulty snippet 進 system prompt。
- prompt injection 防線仍存在。
- debrief prompt 帶 persona/difficulty。

## Rollout

這是 Edge + Flutter client 合約變更：

1. Edge 先支援 optional persona/difficulty，舊 client fallback。
2. Flutter 再送新欄位並更新 UI。
3. 不需要 Supabase migration。
4. 需要重新 build iOS/TestFlight 才能看到 UI；Edge deploy 只更新 prompt fallback/後端支援。
