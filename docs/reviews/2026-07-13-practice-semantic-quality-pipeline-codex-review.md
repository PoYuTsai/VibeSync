# Practice Hint／Debrief 語意品質管線 Codex Review

Date: 2026-07-13
Scope: `f02c1245..ad0fdae9`
Verdict: **APPROVED（0 P0 / 0 P1 / 0 P2）**

## 驗收不變量

- Beginner／Game Hint 只回模型生成且通過 schema、grounding、高手品質與獨立事實核驗的內容；任一環失敗只回 retryable error，絕不把罐頭當成功、落快照、扣費或計次。
- 模型只負責可見 `warmUp`、`steady`、`coaching`。Hidden decision、phase、target、invite route 與 rationale 全由 server 依逐字稿、角色資料及 Game ledger 產生，reviewer 回傳的 `strategies` 一律沒有 production 介面可進入 Debrief。
- Hint 可貼句中的第一人稱事實必須有 user turn 證據；對方、第三人、地點與共同經歷必須受逐字稿或已知角色資料支持。語意 reviewer 後仍有獨立 fact-only verifier，且 verifier 不能改稿。
- Debrief 收到 applied Hint 時，除非 Hint 後的新回覆出現明確反證，必須承認 Hint 被採用，只評執行與下一步；所有 Game 拆盤欄位、`suggestedLine`、`nextFirstLine` 與 action owner 必須彼此一致。
- Hint 最多四次 provider 呼叫；DeepSeek generation 24 秒、Claude failover 18 秒、semantic call 24 秒。Flutter Hint fence 115 秒，低於 DB owner 120 秒；不更動 Debrief 90 秒／owner 105 秒契約。

## 審查與修正紀錄

1. 前輪對抗審曾抓到 P0：以正向「強人名」allowlist 判 HIGH，會讓嘉玲、雅婷等一般中文名降成 LOW，打開自然人名幻覺通道。已改回反向排除哲學並補常見名回歸；P1 asksPlace over-kill 與 P2 telemetry 前綴也一併收斂。
2. 第一輪 production smoke 顯示 Beginner Hint 可成功，但 hidden model strategy 曾把「精神快關機」帶進 Debrief；同時 Game Hint 三次皆 503，live `ai_logs` 分別是 `semantic_adjudication_invalid_strategy`、repair 無法驗證、Claude timeout／pure-questions。
3. 最終重構移除 Hint semantic result 的整個 `strategies` 型別、parser、required key 與 test fake。Server 對每個選項重新建立 authoritative decision；legacy reviewer 即使多吐捏造或 stale strategies 也只會被忽略，不能進 response 或 Debrief lineage。
4. Hint reviewer 改成只修三個可見欄位，token cap 4,000→1,800；提示明訂被直接問時先回答／表態，兩案不可只丟問題。Game 高手 rubric、邀約階梯、一次一招、低能量退壓與 deterministic hard guard 保留。
5. 自審另修正 server rationale：不能窄寫「只依據最新一句」，因高手 callback 可合法使用本場前文；最終契約為「本場逐字稿與已知角色資料」，不封死合法技巧也不接受模型自編狀態。

## 驗證證據

- `deno test --reporter=dot --allow-env --allow-read --allow-net=127.0.0.1 --no-check .`：**914/914 passed**。
- Hint／semantic／handler targeted：**355/355 passed**；prompt budget targeted：**197/197 passed**。
- `deno check index.ts`、`deno fmt --check` 六檔、`git diff --check`：通過。
- `flutter test --no-pub test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart`：**174/174 passed**。
- `dart format --output=none --set-exit-if-changed` 兩個 Flutter 檔：0 changed。
- 最長 20 輪 SR Hint prompt 仍守住既有 4,800 字上限；沒有為新增規則放寬 token/cost gate。

## Production smoke

- Edge `practice-chat` 已部署，bundle 992.5 kB；本輪另有 owner-window function migration `20260713120000_practice_debrief_semantic_owner_window.sql`，將 Debrief single-flight owner fence 對齊為 105 秒。
- 2026-07-16 landing 前以 `supabase migration list --linked` 直接核對 production ledger：local／remote 均存在 `20260713120000`。這更正原先「無 DB migration」的文件誤載；migration 實際已於 2026-07-13 套用。
- Beginner：prefetch fail-closed 503 且未落壞快照；正式 Hint 第一次成功（DeepSeek、13.9 秒）、replay stable、`fallbackUsed=false`。Debrief 承認「你有照提示做」並正確保留她後續自揭內容。
- Game：prefetch 200；正式 Hint 第一次成功，DeepSeek 24 秒 timeout 後 Claude failover，整體 62.7 秒、replay stable、`fallbackUsed=false`。輸出誠實承認被反問、接住打哈欠的低能量而不捏造咖啡店或共同經歷。
- Game Debrief 第一次因 fact verifier 拒絕修正版而 503 fail-closed；同 requestId 重試 39.9 秒成功。最終卡明確寫「你照提示收尾」，`hintContinuityGuardPassed=true`。這是已披露的保守拒絕，不是罐頭成功，也不是本輪 Hint 點擊三連敗復發。
- 腳本結論：`production_smoke PASS`，Beginner＋Game 皆通過。

## 出貨結論

Server 修法已在 production 生效。新 build／TestFlight 仍必須包含 `ad0fdae9`，才會把 app 的 Hint 等待上限由 90 秒帶到 115 秒；舊 build 在慢速 failover 情境仍可能先於 server 成功而 timeout。
