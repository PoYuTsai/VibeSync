# AI 實戰練習室新手學習模式：升溫指數與提示教學設計

Date: 2026-06-28
Status: Approved for implementation planning
Owner: Eric product decision / implementation owner assigned during planning

## Context

本案新增 AI 實戰練習室的「新手學習模式」，參考夥伴 repo
`chiang53610-droid/temperature-chatbot-` 與桌面影片 `新手練習.mp4` 的互動模型：

- 對話中有 0-100 的好感溫度，使用者回覆後即時升降。
- 使用者卡住時可點提示，得到兩種可送出的回覆與一段不可送出的心法教學。
- 溫度不只是 UI 裝飾，而是會影響下一回合女生回覆態度。

現有 AI 實戰練習室的實戰模式必須保留。新手模式是同一練習室裡的另一種教學模式，不取代原模式。

## Goals

- 讓新手在練習中即時知道「這句讓互動升溫還是降溫」。
- 在不知道怎麼接時，用提示提供一個升溫方向、一個穩住方向，以及一句心法。
- 保留原本實戰模式的乾淨體驗，不讓溫度計或提示污染既有玩法。
- 扣費規則清楚：溫度自動更新不扣，提示成功產出才扣 1 則。

## Non-Goals

- 不取代開場救星 opener。
- 不把溫度解讀成約會成功率。
- 不讓使用者中途把既有實戰 session 切成新手 session。
- 不在第一版做深度劇情遊戲或路線分支。
- 不把提示內容寫入聊天 transcript；只有真正送出的文字才進 messages。

## Locked Product Decisions

| Topic | Decision |
| --- | --- |
| 入口 | 同一個 AI 實戰練習室內切換 `實戰` / `新手` |
| 模式鎖定 | 送出第一句前可切換；第一句送出後鎖住 |
| 舊 session | 沒有 mode 欄位時一律視為 `實戰` |
| 新手起始溫度 | 固定 30/100 |
| 溫度語意 | 好感溫度：對方是否舒服、是否願意繼續互動 |
| UI 呈現 | 可包裝成 `升溫指數` |
| 溫度扣費 | 每回合自動更新，不額外扣額 |
| 溫度影響 | 採 3-lite：用大區間影響下一回合女生語氣 |
| 提示可用時機 | 只在女生已回覆、輪到使用者接話時可按 |
| 提示扣費 | 成功產出才扣 1 則 |
| 提示選項名稱 | `升溫回覆` / `穩住回覆` |
| 提示選項行為 | 點選只填入輸入框，不自動送出 |
| Hint 上限 | 每輪最多 5 次 |

## UX

AI 實戰練習室在開始聊天前顯示模式切換：

```text
實戰 | 新手
```

`實戰` 為預設。切到 `新手` 後，在聊天區顯示 `升溫指數 30/100`。送出第一句後，模式切換鎖住，只顯示目前模式。

### 實戰模式

- 維持現況。
- 不顯示升溫指數。
- 不顯示提示燈泡。
- 不使用溫度影響女生回覆。
- 不新增任何提示扣費。

### 新手模式

- 顯示升溫指數。
- 女生回覆成功後更新分數，短暫顯示 `+3` / `-2` 這類變化。
- 女生下一回合回覆會讀取溫度區間。
- 輸入列旁顯示提示按鈕，文案可用：`不知道怎麼接？看提示`。
- 提示按鈕附近提示：`提示成功產生才扣 1 則`。

提示面板包含：

- `升溫回覆` chip：較有機會讓互動更有趣或更推進。
- `穩住回覆` chip：低風險、不扣分，讓新手先保住互動。
- `心法教學`：1-3 句繁中說明，不可點、不可送出。

點 chip 只填入輸入框，使用者可改；真正送出後才進聊天 transcript。

## Temperature Model

新手模式 session 起始 `temperatureScore = 30`。每次 chat 成功後：

1. 使用者送出訊息。
2. 女生 AI 依目前溫度區間回覆。
3. 回覆成功後，server 使用 judge 產生 `temperatureDelta`。
4. 新分數為 `clamp(old + delta, 0, 100)`。
5. Flutter 顯示新分數。
6. 下回合 prompt 使用新溫度區間。

Delta 建議：

- 每回合限制在 `-8..+8`。
- 普通回覆多落在 `-2..+3`。
- 壓迫、冒犯、強需求感才給 `-6..-8`。
- 有承接、鬆、有具體接球點才給 `+4..+8`。

溫度區間：

| Score | Band | Behavior |
| --- | --- | --- |
| 0-20 | 冰點 | 防備、短回、明顯不想被推進 |
| 21-40 | 冷淡 | 願意回，但不主動，回覆偏短 |
| 41-60 | 可聊 | 正常互動，會給一些接球點 |
| 61-80 | 升溫 | 更願意延伸，可能丟小窗口 |
| 81-100 | 熱絡 | 主動性提高，但仍保持人設與邊界 |

重要限制：

- 溫度不是約會成功率。
- 高溫不保證邀約成功。
- 低溫仍可透過穩住、降壓、接球慢慢修復。

### Temperature Failure Rules

- 女生回覆失敗：不新增 AI 訊息、不扣額、不更新溫度。
- judge 失敗：聊天仍成功，保留原溫度。
- judge 格式錯：丟棄 delta，保留原溫度。
- 不信任 client 提供的 delta；server 才是權威。

## Hint Model

Hint 只存在於新手模式。

可按條件：

- `practiceMode == beginner`
- 已至少有一則女生 AI 回覆。
- 最後一則有效訊息是女生 AI。
- 目前不是 sending / debriefing / sessionComplete。
- 本輪 hint 使用次數未達 5。

Hint 回傳：

```json
{
  "replies": [
    {
      "type": "warm_up",
      "label": "升溫回覆",
      "text": "..."
    },
    {
      "type": "steady",
      "label": "穩住回覆",
      "text": "..."
    }
  ],
  "coaching": "這邊她其實有給你一個可接的點...",
  "costDeducted": 1,
  "hintUsedCount": 2,
  "monthlyRemaining": 123,
  "dailyRemaining": 12
}
```

提示內容規則：

- 兩個 replies 都必須是使用者第一人稱、可直接傳給女生。
- `升溫回覆` 可以更有趣、更推進，但不能油、不能壓迫。
- `穩住回覆` 必須低風險、不扣分，適合新手卡住時使用。
- 心法教學只能教使用者，不可被當成一句要傳給女生的話。
- 不給第三個以上選項，避免選擇疲勞。
- 禁止操控、PUA、貶低、逼迫、性暗示硬推進。

失敗規則：

- hint 失敗、timeout、格式錯：不扣額。
- quota 不足：不產出 hint，不扣額，回 quota/paywall payload。
- 第 6 次 hint：不產出 hint，不扣額，提示本輪已用完。

## API Contract

現有 `practice-chat` 保留 `chat` / `debrief` / `draw_profile`，新增 `hint`。

`chat` request 新增：

```json
{
  "mode": "chat",
  "practiceMode": "beginner",
  "temperatureScore": 30
}
```

`practiceMode`:

- `standard`
- `beginner`

缺欄位 fallback 為 `standard`，保護舊 client / 舊 session。

`chat` response 在 beginner 才回：

```json
{
  "reply": "...",
  "aiTurnCount": 3,
  "sessionComplete": false,
  "costDeducted": 0,
  "temperature": {
    "score": 33,
    "delta": 3,
    "band": "cold",
    "reason": "使用者承接了對方話題，壓力不高"
  }
}
```

`standard` response 不含 `temperature`。

新增 `hint` request：

```json
{
  "mode": "hint",
  "sessionId": "...",
  "practiceMode": "beginner",
  "temperatureScore": 33,
  "turns": []
}
```

## Billing And Server Safety

現有規則保留：

- 一輪練習首次女生 AI 回覆成功，扣 1 則。
- 同一輪最多 20 則女生 AI 回覆。
- DeepSeek / format 失敗不扣。
- debrief 不另扣，但受 server ledger 限制。
- `draw_profile` 不受新手模式影響。

新增規則：

- 溫度自動更新不扣額。
- hint 成功產出扣 1 則。
- hint 不增加 `practice_chat_sessions.ai_count`，不影響 20 則女生回覆上限。
- hint 每輪最多 5 次，server-side gate 為準。
- hint quota preflight 必須在 provider call 前。
- hint 扣費必須在成功產出後，且不能被 client 偽造。

Implementation note:

- 第一版可以避免新增 Postgres migration 的話，不要為 hint ledger 急著加新表。
- 但「每輪最多 5 次」是 server-side 成本界線；若現有 ledger 無法可靠承載，實作時應設計一個最小 migration 或 RPC，而不是退回 client-only gate。

## Flutter Local Data

`PracticeSession` 需新增 nullable / fallback-safe 欄位：

- `practiceMode`: `standard | beginner`
- `temperatureScore`: nullable int，beginner 起始 30
- `hintUsedCount`: 本輪 hint 次數，client 顯示用；server 仍是權威

舊 Hive session：

- `practiceMode == null` -> `standard`
- `temperatureScore == null` -> 不顯示溫度
- 不得因 adapter 舊欄位 crash

Hint 面板不寫入 Hive。真正送出的文字才會成為 `PracticeMessage(role: user)`。

## Testing

### Edge Tests

- `validate.ts` 接受 `practiceMode: beginner | standard`。
- invalid `practiceMode` rejected。
- old client missing `practiceMode` fallback standard。
- standard chat response 不含 temperature。
- beginner chat response 含 temperature。
- temperature judge 失敗時 chat 成功但溫度不變。
- temperature delta clamp 在 `-8..+8`。
- hint 只能 beginner。
- hint 要求最後一則有效狀態是女生回覆。
- hint 成功才扣 1。
- hint 失敗不扣。
- hint quota 不足不扣。
- hint 每輪最多 5 次。
- hint 不增加 `ai_count`，不影響 20 則上限。
- standard mode prompt 不受 beginner temperature band 影響。

### Flutter Tests

- 送第一句前可切模式，送出後鎖住。
- 舊 session fallback standard。
- beginner 顯示 `升溫指數 30/100`。
- standard 不顯示溫度與提示。
- chat response temperature 更新 state 並 persist。
- judge missing temperature 時保留舊分數。
- hint loading / success / error / quota exceeded。
- 點 `升溫回覆` 填入輸入框但不送出。
- 心法不可點、不進 transcript。
- 每輪第 6 次 hint 被擋。
- restore recent session 後 mode + temperature 保留。

## Rollout And Review

本案高風險，因為會碰：

- quota / 扣費
- `practice-chat` Edge schema
- AI prompt 行為
- Hive local persistence
- 新手模式 UI state

Implementation closeout before dogfood-safe:

1. Deno practice-chat tests.
2. Flutter targeted practice-chat tests.
3. `flutter analyze`.
4. 明確列出是否需要 Supabase migration / RPC。
5. Codex review on full implementation range.
6. Edge deploy success if Edge changed.
7. TestFlight rebuild if Flutter changed.
8. Real-device smoke:
   - 實戰模式沒有溫度/提示。
   - 新手模式 30 開場。
   - 女生回覆後溫度變。
   - 高低溫會影響下一回合語氣。
   - hint 成功扣 1。
   - hint quota 不足不清聊天。
   - 每輪第 6 次 hint 被擋。
   - 最近練習恢復時 mode 不亂跳。

Codex review focus:

- quota 是否可能多扣/少扣。
- hint 是否能繞過 5 次上限。
- standard 模式是否被新 prompt 影響。
- Hive adapter 是否舊資料安全。
- Edge response schema 是否不會讓舊 client crash。
