# 練習室難度 bakeoff

難度重設計案（`docs/plans/` 下的 practice-difficulty-redesign 計畫）Task 7：上線前量化
gate 工具。直接重用 `supabase/functions/practice-chat/` 的真管線模組（`resolvePracticeProfile`
／`buildChatMessages`／`buildDebriefMessages`／`buildTurnClassifierMessages`／
`parseTurnClassification`／`applyLearningClassification`／`difficultyTuningFor`／
`parseDebriefCard`），跑「難度(easy/normal/challenge) × 腳本(bad_interrogator/average/
high_quality) × runs」全組合，量測 AI 回覆長度、句點/敷衍占比、溫度軌跡、debrief
`dateChance` 分佈，讓難度調參／prompt 改動有數字可對比，不用每次靠肉眼聊天判斷。

## ⚠️ 模型供應商差異（務必先讀）

`practice-chat` 正式環境的 chat／debrief／分類器三個呼叫全部打 **DeepSeek**
（`handler.ts` 的 `DEEPSEEK_MODEL`、`deps.callDeepSeek`、env `DEEPSEEK_API_KEY`）。
但本機 repo（`supabase/.env`）只有 `CLAUDE_API_KEY`，完全沒有 `DEEPSEEK_API_KEY`，
無法離線打 DeepSeek；本 task 規格文字也明講「讀 env `CLAUDE_API_KEY`」。

因此這支工具改打 **Anthropic Messages API**（`CLAUDE_API_KEY` + `claude-sonnet-4-6`，
與 `coach-chat/generation.ts`、`analyze-chat` 現用的 Sonnet 常數一致）。重用的是
**同一組 prompt 內容（ChatMessage[]）與同一套分類/溫度數學**，不是同一個模型供應商。

這代表 bakeoff 量到的長度/敷衍/溫度數字是「同一套難度規格＋同一套溫度管線，換一個
LLM 執行」的結果，可以用來比較難度 A vs 難度 B 的相對差異，但**不能**當成「上線後
DeepSeek 真實表現」的絕對數字。若要交叉驗證正式模型，把 `bakeoff.ts` 裡的
`callClaude()` 換成 `supabase/functions/practice-chat/deepseek.ts` 的
`callDeepSeek()`，並改讀 `DEEPSEEK_API_KEY` 即可——`buildChatMessages` 等 prompt
組裝函式完全不用動。

## 跑法

```bash
CLAUDE_API_KEY=sk-ant-... deno run \
  --allow-net --allow-env --allow-read --allow-write \
  tools/practice-difficulty-bakeoff/bakeoff.ts
```

預設跑滿三難度 × 三腳本 × 2 runs（共 18 場、每場 6 輪 + 1 次 debrief）。

### CLI flags（縮小規模用，例如 smoke test）

| flag | 預設 | 說明 |
|---|---|---|
| `--runs=N` | `2` | 每個(難度×腳本)組合跑幾場 |
| `--scripts=a,b,c` | 三組全跑 | 合法值：`bad_interrogator`、`average`、`high_quality` |
| `--difficulties=a,b,c` | 三難度全跑 | 合法值：`easy`、`normal`、`challenge`（`random` 不進 bakeoff） |
| `--out=DIR` | `out` | 輸出目錄（相對於執行時的 cwd） |
| `--profileId=ID` | `practice_girl_001`（`DEFAULT_PROFILE_ID`） | 固定 persona，排除人設差異干擾 |

Smoke test（只跑 1 場、6 輪 + debrief）：

```bash
CLAUDE_API_KEY=sk-ant-... deno run \
  --allow-net --allow-env --allow-read --allow-write \
  tools/practice-difficulty-bakeoff/bakeoff.ts \
  --runs=1 --scripts=bad_interrogator --difficulties=challenge
```

## 產物

- `out/report.md`：人看的彙總表（每個難度×腳本一列：場次成功/失敗數、平均回覆長度、
  敷衍輪占比、平均終值溫度／熟悉度、`dateChance` 分佈）＋逐場溫度軌跡。
- `out/raw.json`：完整原始紀錄（每輪的 user 訊息、AI 回覆、分類器輸出、溫度/熟悉度
  前後值、debrief 卡片），供進一步分析或除錯用。

兩個檔案都在 `out/`，已 gitignore，絕不進 commit。

## 指標定義

- **平均回覆長度**：AI 回覆去除所有空白字元後的字元數，取所有成功場次、所有輪次的平均。
- **句點/敷衍輪占比**：符合以下任一條件即算一輪敷衍：
  - 去空白後字元數 ≤ 10
  - 全文（trim 後）完整匹配 `^(喔+|嗯+|還好|哈哈+|是喔|喔喔)[。.!?～~]?$`
- **溫度終值＋軌跡**：`applyLearningClassification` 每輪回傳的 `score`（升溫指數），
  起始值取 `difficultyTuningFor(difficulty).startTemperature`，熟悉度起始值固定 0，
  同 `practice-chat` handler 對 beginner 模式的 session 起始邏輯。
- **`dateChance` 分佈**：debrief 卡片的 `dateChance` 欄位（`low`/`medium`/`high`），
  per 難度 × 腳本統計次數；若該場 debrief 解析失敗，計入 `error` 桶。

## 已知限制

- 溫度／熟悉度更新只呼叫純函式 `applyLearningClassification` 在記憶體內累加，**不**
  寫 Supabase `update_practice_learning_state` RPC，因為 bakeoff 目的是量測 prompt/
  溫度管線的行為，不是驗證 DB 併發語意（DB 併發語意已有 `learning_state_test.ts` 等
  既有 deno test 覆蓋）。
- 三組腳本固定寫死在 `scripts.ts`，不隨機生成——bakeoff 的目的是「同一組輸入下比較
  難度設定差異」，不是模擬使用者分佈。
- persona 固定用同一個 `profileId`（預設 `practice_girl_001`），排除人設差異干擾。
- 任一輪 chat 生成或分類器呼叫失敗，會讓整場（run）標記 `sessionError` 並跳過，不會
  讓其他場次連坐失敗；debrief 失敗則單獨記錄 `debriefError`，不影響該場的逐輪數據。
