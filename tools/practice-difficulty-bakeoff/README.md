# 練習室難度 bakeoff

難度重設計案（`docs/plans/` 下的 practice-difficulty-redesign 計畫）Task 7：上線前量化
gate 工具。直接重用 `supabase/functions/practice-chat/` 的真管線模組（`resolvePracticeProfile`
／`buildChatMessages`／`buildDebriefMessages`／`buildTurnClassifierMessages`／
`parseTurnClassification`／`applyLearningClassification`／`difficultyTuningFor`／
`parseDebriefCard`／`callDeepSeek`），跑「難度(easy/normal/challenge) × 腳本
(bad_interrogator/average/high_quality) × runs」全組合，量測 AI 回覆長度、句點/敷衍
占比、溫度軌跡、debrief `dateChance` 分佈，讓難度調參／prompt 改動有數字可對比，
不用每次靠肉眼聊天判斷。

## 模型供應商（Eric 2026-07-06 拍板）

- **預設 provider = DeepSeek（prod 同款，正式 gate 依據）**：重用
  `supabase/functions/practice-chat/deepseek.ts` 的 `callDeepSeek`＋`DEEPSEEK_MODEL`
  （`deepseek-v4-flash`），呼叫形狀（`jsonMode`／maxTokens／temperature／timeout）與
  `handler.ts` 一模一樣。key 讀 env `DEEPSEEK_API_KEY`。
- **`--provider=claude` 為參考路徑**（`CLAUDE_API_KEY` + `claude-sonnet-4-6`）：只供
  交叉參考難度規格在不同 LLM 下的相對行為。**正式 gate 只認 DeepSeek 結果，Claude
  報告不得作為上線依據**（report.md 會自動印警告標頭）。

## 跑法

```bash
DEEPSEEK_API_KEY=... deno run \
  --allow-net --allow-env --allow-read --allow-write \
  tools/practice-difficulty-bakeoff/bakeoff.ts
```

預設跑滿三難度 × 三腳本 × 2 runs（共 18 場、每場 6 輪 + 1 次 debrief）。

### CLI flags（縮小規模用，例如 smoke test）

| flag | 預設 | 說明 |
|---|---|---|
| `--provider=P` | `deepseek` | `deepseek`（prod 同款，正式 gate）或 `claude`（參考用，讀 `CLAUDE_API_KEY`） |
| `--runs=N` | `2` | 每個(難度×腳本)組合跑幾場 |
| `--scripts=a,b,c` | 三組全跑 | 合法值：`bad_interrogator`、`average`、`high_quality` |
| `--difficulties=a,b,c` | 三難度全跑 | 合法值：`easy`、`normal`、`challenge`（`random` 不進 bakeoff） |
| `--out=DIR` | 腳本目錄下的 `out/` | 輸出目錄。預設落在 `tools/practice-difficulty-bakeoff/out/`，與 cwd 無關；顯式帶 `--out=DIR` 時才相對執行時的 cwd 解析 |
| `--profileId=ID` | `practice_girl_001`（`DEFAULT_PROFILE_ID`） | 固定 persona，排除人設差異干擾 |

Smoke test（只跑 1 場、6 輪 + debrief）：

```bash
DEEPSEEK_API_KEY=... deno run \
  --allow-net --allow-env --allow-read --allow-write \
  tools/practice-difficulty-bakeoff/bakeoff.ts \
  --runs=1 --scripts=bad_interrogator --difficulties=challenge
```

Claude 參考路徑（非 gate；2026-07-06 已用此路徑 smoke 過端到端）：

```bash
CLAUDE_API_KEY=sk-ant-... deno run \
  --allow-net --allow-env --allow-read --allow-write \
  tools/practice-difficulty-bakeoff/bakeoff.ts \
  --provider=claude --runs=1 --scripts=bad_interrogator --difficulties=challenge
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
