# Practice Hint／Debrief Claude-primary Codex Review

Date: 2026-07-14  
Scope: `da801fcc..working tree`  
Verdict: **APPROVED FOR DEPLOY SMOKE（0 P0 / 0 P1 / 0 P2）**

## 問題與根因

Production v113 的 Hint 正式結果約半數失敗。命中帳號的 Game Hint 兩次分別耗時 19.1 秒與 32.9 秒，最後都以 `semantic_adjudication_repair_unverified:semantic_fact_verification_rejected` 結束。根因不是單一 regex 或 DeepSeek 掛掉，而是同步 `生成 → 語意改稿 → 事實再核驗` 管線把一次請求拆成多個相依模型階段；任一後段保守拒絕都會把前面已生成的內容變成 503。

## 驗收不變量

- 一般角色對話維持 DeepSeek，不受本次改動影響。
- Beginner Hint、Game Hint、Beginner Debrief、Game Debrief 在正式預設路徑都由 Claude Sonnet 直接生成；第一次通過守門即回傳，最多只允許一次同模型重產。
- 正式路徑不呼叫同步 semantic reviewer／repair verifier；不是「換另一個模型再審一次」。
- 每次候選仍須通過既有 schema、逐欄 grounding、typed facts、角色主詞、已知罐頭、內部標籤、安全與 Game FSM／邀約階梯守門。
- Hint decision 仍由 server 依逐字稿、角色與 Game ledger 建立，模型不能擁有 hidden strategy lineage。
- Debrief 沿用 server resolve 的 Hint decision；無 Hint 後新反證時不得批評或反轉 exact Hint。
- 正式 Debrief 不使用 deterministic visible-copy repair。怪句、捏造或 Hint 矛盾一律拒絕該候選，帶具體原因請 Sonnet 重寫。
- 兩次都失敗時只回 retryable 503，釋放 generation owner；不落 Hint snapshot／Debrief card、不扣費、不計次、不回罐頭成功。

## 失敗矩陣

| 情境 | 模型呼叫 | 結果 |
|---|---:|---|
| 第一次合法 | 1 次 Sonnet | 直接成功、正常落檔 |
| 第一次格式／品質／事實不合法，第二次合法 | 2 次 Sonnet | 附拒絕理由重產後成功 |
| 第一次 timeout，第二次合法 | 2 次 Sonnet | 原 prompt 重試，不偽稱 JSON 被拒絕 |
| 兩次都不合法或 timeout | 2 次 Sonnet | retryable 503、無成功內容／扣費／計次 |
| Debrief 打臉 preserved exact Hint | 2 次內 | 拒絕並重產，不由 server 套固定句 |
| `PRACTICE_CLAUDE_PRIMARY=false` | 舊管線 | 僅供 production 緊急回滾 |

## 成本與等待時間審查

- 正式路徑通常 1 次 provider call，最差 2 次；舊路徑可能串接 generation、repair、alternate reviewer 與 verifier，共 3–5 次。
- Hint 每次上限 1,600 output tokens，Debrief 每次 1,200；最差 output 上限分別為 3,200／2,400，但不再疊 semantic reviewer token。
- 每次 Sonnet timeout 24 秒，兩次最差約 48 秒，加 DB 開銷仍低於 build 323 的 90 秒 client timeout，也低於 Debrief 105 秒 owner fence。
- Free／Starter／Essential 的 Hint 與 Debrief 統一用 Sonnet，這是 Eric 為高手品質明確接受的單次成本上升；整體 provider call 數則下降。

## 審查結果

- 未發現 P0／P1／P2。
- 正式 direct branch 與 rollback branch 明確互斥；direct branch 不會在第二次失敗後落回 DeepSeek 或 semantic pipeline。
- `failoverUsed` 在同模型重產時保持 `false`，telemetry 的 attempt/retry/failureCodes 仍可區分第一次失敗。
- record／release／prefetch settle／quota 邏輯位於生成分支之外且未更動；新增失敗測試確認兩次拒絕後 record=0、release=1。

## 驗證證據

- `deno check supabase/functions/practice-chat/handler.ts`：通過。
- `deno fmt --check` changed files：通過。
- `git diff --check`：通過。
- direct-path targeted：7/7 passed，覆蓋 Beginner＋Game Hint、Game Debrief、事實捏造、transient timeout、Hint→Debrief 一致性、雙失敗不落檔。
- `deno test --allow-env --allow-read --no-check supabase/functions/practice-chat`：**920/920 passed**。

## 出貨門檻

本 verdict 核准部署 smoke，不等於已證明 production 99%。部署後必須以 production Test 帳號跑 Beginner Hint、Game Hint、Game Debrief、replay，並從 `ai_logs` 確認 provider=`anthropic`、model=`claude-sonnet-4-6`、`semanticProviderCalls=0`、`fallbackUsed=false`，再更新本文件結論。
