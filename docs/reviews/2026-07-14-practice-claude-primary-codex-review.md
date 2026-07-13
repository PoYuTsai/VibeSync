# Practice Hint／Debrief Claude-primary Codex Review

Date: 2026-07-14
Scope: `da801fcc..50d91dbc`，最終收斂 commits `1a98cd8f`、`67c6d349`、`21159eeb`、`50d91dbc`
Reviewer: Codex root（未派子代理，依 Eric 的 token 預算要求直接對抗檢查）
Verdict: **APPROVED／DEPLOYED（0 P0 / 0 P1 / 0 P2）**

## Root cause

Production 失敗不是單一模型壞掉。舊同步管線在生成後再串 semantic repair／verifier，後段任何保守拒絕都會把已生成內容變成 503；另一方面，Game FSM 把「咖啡／吃飯」等話題詞誤當邀約，Debrief 又把未出現在逐字稿的隱藏生活情境當事實，造成 Hint 與 Debrief 自相矛盾。

## 最終契約

- 一般角色對話維持 DeepSeek。
- Beginner Hint、Game Hint、Beginner Debrief、Game Debrief 預設由 Claude Sonnet `claude-sonnet-4-6` 直接生成。
- 正常路徑不呼叫同步 semantic reviewer／repair verifier；同一 Sonnet 最多 3 次、每次 24 秒。候選不合法才重產。
- runtime 沒有 Hint／Debrief 罐頭成功路徑。全部失敗只回 retryable 503，不落 snapshot/card、不扣費、不計次。
- 對方最新一句若是問句，新 client 必須先由使用者填真實答案，答案以 evidence-only 方式進 Hint；prefetch 沒答案只回 opaque ack。
- 模型輸出的「我做過／我確認過／親身感受」必須能回指 user-authored evidence；問句、未來計畫不誤判成已發生經歷。
- Game Debrief 只有一個權威下一句：`gameBreakdown.nextFirstLine = suggestedLine`，不允許同一卡內兩句漂移。
- Game FSM 與 pasteable reply 共用 `practiceInviteLevelFor`。只聊咖啡不算邀約，必須有雙方計畫／提議語法才進邀約階。
- 隱藏生活情境只可影響角色生成，不是 Debrief 證據；拆盤只認角色實際說進逐字稿的狀態。
- Hint decision 由 server 依逐字稿、Game ledger 與邀約契約建立；Debrief 沿用該 decision，只有 Hint 後的新證據能改變下一步。

## 對抗檢查 findings 與修復

1. v126 smoke：Beginner Debrief 編出「我也試過硬撐」；Game card 的 `suggestedLine` 安全但 `nextFirstLine` 編出另一段經歷。修成 user-experience provenance gate＋單一權威下一句。
2. 自審發現「這杯喝起來會酸嗎？」會被感受守門誤判。保留句尾問號，問句不進 completed-experience gate。
3. v128 smoke：咖啡開場被標成 `P5_CLOSE`，Debrief 卻說太早。根因是 topic keyword 被當邀約；改共用中央邀約分類器後為 `P1_OPEN／build`。
4. v128 smoke：Debrief 外洩「準備睡／精神快關機」。根因是 hidden scene 與逐字稿衝突仍被當 factual evidence；v129 起 hidden scene 不再進 Debrief prompt/fact evidence。

## 驗證證據

- `deno test --allow-env --allow-read --no-check supabase/functions/practice-chat`：**951/951 passed**。
- changed files `deno fmt --check`、`deno check`、`git diff --check`：通過。
- Flutter API/store/controller/widget contract 在 `1a98cd8f`：**275/275 + 126/126 passed**，`flutter analyze` 0。
- production `practice-chat v129` full generated-only smoke：**PASS**。
  - Beginner Hint／Debrief：第一次成功、provider=`anthropic`、model=`claude-sonnet-4-6`、`fallbackUsed=false`、Hint／Debrief replay stable。
  - Game Hint／Debrief：第一次成功、同上；咖啡開場 decision=`P1_OPEN`、inviteRoute=`build`，Debrief 同樣先累積熟悉感、不邀約。
  - `suggestedLine === gameBreakdown.nextFirstLine`；未再外洩 hidden 睡前情境；測試帳號 costDeducted=0。

## 出貨與 rebuild

- Edge 改動已 live，build 323 也會立即吃到 Claude-primary、無罐頭成功、Game phase 與 Debrief 修正。
- `supportsHintUserFact` 的填答視窗屬 Flutter 新 client contract，必須重新 build／上 TestFlight 才能測到。
- production smoke 證明本輪樣本 4 個生成面都第一次成功，但不是數學上的 99% SLA；後續以 `ai_logs` 的 success/retryable 比率與真機 dogfood 持續觀測。
