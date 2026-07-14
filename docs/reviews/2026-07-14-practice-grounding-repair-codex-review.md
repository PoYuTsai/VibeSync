# Practice Hint／Debrief 語意歸因重構 Codex Review

Date: 2026-07-14
Scope: `practice-chat` 本輪未提交 diff（Claude-primary v129 後續修正）
Reviewer: Codex root（依 Eric 的 token 預算要求，未派子代理）
Verdict: **APPROVED FOR DEPLOY（0 open P0 / 0 open P1 / 0 open P2）**

## Root cause

Production `ai_logs` 證明模型有回覆，但 direct Hint／Debrief 的 lexical typed-facts guard 一方面把自然中文跨字誤判成捏造、另一方面也漏掉真捏造。前者讓一般人名、家鄉、目前位置候選連續被拒成 503；第一次 deploy smoke 又發現「昨晚看什麼這麼入迷」未命中 regex，Hint 直接替使用者編出《黑白大廚》與《淚之女王》。這不是 provider 全線故障，而是 regex 同時有 false positive 與 false negative，不能擁有是否審查的決策權。

## 最終契約

- 每個 direct Hint／Debrief 候選正常固定經過兩次 `temperature=0` Claude：第一道做事實歸因修復，第二道以獨立對抗角度假設前審漏掉自然的第一人稱幻覺再複核；regex 不再決定是否審查，也不再是人名、地點、時間、偏好、經歷、關係或行程的最終語意裁判。
- 審查器閱讀完整逐字稿與可信事實，明訂「對方的問題不是使用者答案、上一版候選也不是證據」；可原樣保留安全問句／假設／泛稱，也可最小幅刪除真正捏造。
- 校正後仍完整重跑 JSON/schema、罐頭、L4、安全、internal label、Game FSM、Hint→Debrief 明確反轉與單一權威下一句等 hard gates。Direct Debrief 不再用「只問／只回／重複片段」猜測是否打臉 Hint；只有直接寫出「提示錯／不該／偏保守」等明確反轉才 fail-closed。
- 電話、Email、社群帳號等明確 contact identifier 不交給語意模型放行，維持 deterministic fail-closed；任一審查若仍保留捏造號碼，後續結果仍不能通過 final hard gate。
- 正常路徑固定 writer＋repair review＋independent verification 三次 Claude。只要 writer 已回候選，即使撞格式／安全／Hint 連動契約，下一 call 就在同一次 review 修正該契約並完成全部事實歸因，不再浪費一格盲寫；只有 provider 未回候選才重叫 writer。若獨立複核本身 timeout／格式失敗，回退前一道已通過語意審查與全部 final hard gates 的候選，不回 503。總上限仍為三次 × 24 秒；若連第一道 review 都未完成則 fail-closed，不落罐頭快照、不扣費、不計次。
- Beginner／Game Hint 與 Beginner／Game Debrief 共用同一處理；Game Debrief 的所有可見拆盤欄位也納入可疑事實掃描。
- 舊 build 323 未送 quality capability 時仍回 `typed-facts-v1`，server-only 部署後即可生效。

## Review findings 與修正

1. **P0（已修）**：初版只掃 Debrief 的 `suggestedLine`／`nextFirstLine`，模型仍可在 summary 或 Game 拆盤編造位置。新增 `auditAllVisibleFacts`，direct Debrief 所有分析欄位都能觸發語意校正；補「只在 phaseReached 編出台中」回歸。
2. **P1（已修）**：Game Hint repair prompt 一度誤提 Debrief `suggestedLine`。已依 surface／mode 分支，Game Hint 僅要求 `warmUp`、`steady`、`coaching`，Game Debrief 才要求完整拆盤與單一下一句。
3. **P1（已修）**：初版在 review timeout 或保留 contact PII 後會用第三次乾淨 writer 恢復，但該 writer 沒有剩餘 review 預算。最終改成只要已有候選，後續 slot 都是可同時修契約的 review；只有 provider 完全沒回候選才可再叫 writer，因此未審 writer 絕不成功。已補 timeout 與電話 hard-gate 回歸。
4. **P0（已修）**：第一次 deploy smoke 雖機器腳本回 PASS，內容目檢發現 Beginner Hint 在完全未命中 regex 時編出兩個劇名，Debrief 又把該錯誤 Hint 當成使用者事實繼續肯定。最終改為 always-on grounding review，並以該 build 323 逐字情境新增零 lexical failureCodes 的回歸測試。
5. **P1（已修）**：always-on 第一版 production smoke 的 Beginner Debrief 第一次 503；`ai_logs` 顯示兩個 writer 都有回覆，但都把 exact Hint 寫成問題而命中 `debrief_hint_assessment_revision_required`，第三格因必須保留 review 而不能再盲寫。狀態機改為「有候選就直接契約修正＋事實審查」，同一類回歸現在由第二個 call 修好，仍保留全部 final hard gates。
6. **P0（已修）**：後續 production smoke 同一個 Beginner Debrief 連續三個 request、每個三個 Claude 回覆都被 `debrief_hint_assessment_revision_required` 拒絕。根因不是模型仍在明講提示錯，而是 direct regex 把「只問／只回」與 Hint 片段重複當成策略反轉；合理的下一步改善也被誤殺。已移除這段模糊 direct 裁決，只保留明確「提示錯／偏保守」紅線；legacy reviewer path 不變。
7. **P0（已修）**：單一語意 editor 雖已明文禁止，production Game 仍把無證據寫成「我沒記清楚店名／堅果味」。最終狀態機改為正常雙審，第二道 fresh pass 明確假設前審漏掉自然第一人稱幻覺；補 Hint 記憶與 Debrief 感官兩個實際漏網回歸，以及第二審 outage 回退第一審成功結果的穩定性回歸。

## 驗證證據

- `deno check supabase/functions/practice-chat/index.ts`：通過。
- changed files `deno fmt --check`、`git diff --check`：通過。
- `deno test --no-check --allow-read --allow-env ...practice-chat/*_test.ts`：**963 passed / 0 failed**。
- 覆蓋：production current-location／hometown failure、一般中文名、泛稱朋友假設、Game breakdown-only 幻覺、contact PII 不可繞過、review timeout、雙 review timeout 不落未審快照、獨立複核 outage 回退、build 323 capability omission、regex 零告警的實際劇名幻覺、店名記憶與香氣感官幻覺。
- 整目錄預設 type-check 仍會命中 HEAD 既有 `hint_test.ts` 缺 `PracticeTurn` 匯入；本輪主程式單檔 type-check 已通過，runtime 全套零失敗。

## Deploy gate

只部署 `practice-chat` Edge，無 migration、無 Flutter rebuild。部署後必須以舊 client payload 連跑 Beginner／Game Hint＋Debrief、replay 與輸出目檢；在 production smoke 通過前不得宣稱 dogfood safe。
