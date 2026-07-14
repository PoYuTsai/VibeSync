# Practice Hint／Debrief 語意歸因重構 Codex Review

Date: 2026-07-14
Scope: `practice-chat` 本輪未提交 diff（Claude-primary v129 後續修正）
Reviewer: Codex root（依 Eric 的 token 預算要求，未派子代理）
Verdict: **APPROVED FOR DEPLOY（0 open P0 / 0 open P1 / 0 open P2）**

## Root cause

Production `ai_logs` 證明模型有回覆，但 direct Hint／Debrief 的 lexical typed-facts guard 把自然中文跨字誤判成捏造；同一候選連續重產仍可能命中同一條 regex，最後 503。實例包含一般人名、家鄉、目前位置；這不是 DeepSeek 或 Claude 全線故障。

## 最終契約

- Regex／typed-facts 只作「可疑事實觸發器」，不再是人名、地點、時間、偏好、經歷、關係或行程的最終語意裁判。
- 只有候選命中 unsupported-detail 時，追加一次 `temperature=0` 的 Claude 事實歸因校正；校正器閱讀完整逐字稿與可信事實，可原樣保留安全問句／假設／泛稱，也可最小幅刪除真正捏造。
- 校正後仍完整重跑 JSON/schema、罐頭、L4、安全、internal label、Game FSM、Hint→Debrief lineage 與單一權威下一句等 hard gates。
- 電話、Email、社群帳號等明確 contact identifier 不交給語意模型放行，維持 deterministic fail-closed；校正器若保留捏造號碼，第三次乾淨 writer 仍可恢復。
- 正常路徑仍只有一次 Claude；可疑路徑通常兩次，總上限維持三次 × 24 秒。失敗仍只回 retryable 503，不落罐頭快照、不扣費、不計次。
- Beginner／Game Hint 與 Beginner／Game Debrief 共用同一處理；Game Debrief 的所有可見拆盤欄位也納入可疑事實掃描。
- 舊 build 323 未送 quality capability 時仍回 `typed-facts-v1`，server-only 部署後即可生效。

## Review findings 與修正

1. **P0（已修）**：初版只掃 Debrief 的 `suggestedLine`／`nextFirstLine`，模型仍可在 summary 或 Game 拆盤編造位置。新增 `auditAllVisibleFacts`，direct Debrief 所有分析欄位都能觸發語意校正；補「只在 phaseReached 編出台中」回歸。
2. **P1（已修）**：Game Hint repair prompt 一度誤提 Debrief `suggestedLine`。已依 surface／mode 分支，Game Hint 僅要求 `warmUp`、`steady`、`coaching`，Game Debrief 才要求完整拆盤與單一下一句。
3. **P1（已修）**：校正 timeout 或保留 contact PII 時，後續 writer 可能沿用污染候選。第三次已改回乾淨 base prompt；補 timeout 與電話 hard-gate 回歸。

## 驗證證據

- `deno check supabase/functions/practice-chat/handler.ts`：通過。
- changed files `deno fmt --check`、`git diff --check`：通過。
- `deno test --no-check ...practice-chat/*_test.ts`：**958 passed / 0 failed**。
- 覆蓋：production current-location／hometown failure、一般中文名、泛稱朋友假設、Game breakdown-only 幻覺、contact PII 不可繞過、repair timeout 乾淨重產、build 323 capability omission。
- 整目錄預設 type-check 仍會命中 HEAD 既有 `hint_test.ts` 缺 `PracticeTurn` 匯入；本輪主程式單檔 type-check 已通過，runtime 全套零失敗。

## Deploy gate

只部署 `practice-chat` Edge，無 migration、無 Flutter rebuild。部署後必須以舊 client payload 連跑 Beginner／Game Hint＋Debrief、replay 與輸出目檢；在 production smoke 通過前不得宣稱 dogfood safe。
