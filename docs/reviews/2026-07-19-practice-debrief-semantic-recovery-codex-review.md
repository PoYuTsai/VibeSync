# Practice Debrief 語意複核失敗根治 Codex Review

Date: 2026-07-19

Scope: `practice-chat` Debrief generation／semantic adjudication／Claude structured output／telemetry／provider-call ledger

Verdict: **CODEX APPROVED（0 P0 / 0 P1 / 0 P2）；最終 Edge deploy 與 live smoke 待完成**

## Production evidence

- Production v200 在 2026-07-18 22:43 UTC 對同一 Essential 使用者連續兩次失敗。DeepSeek 候選已生成，Claude semantic reviewer 分別落在 malformed schema 與 repair-unverified；每次皆耗盡三個 semantic call。
- 第一階段修正部署後，新的 Standard Debrief 可一次成功且 replay stable；但 Beginner live smoke 又揭露兩次 `semantic_fact_verification_rejected`，client 第三次重送才成功。這證明 provider schema 已解掉 envelope 失敗，但 fact-rejection recovery 仍有獨立 root cause。
- 所有失敗都由 DB owner fence 正確 release；未 record Debrief、未增加 `debrief_count`、未扣月額度。

## Root cause

1. Claude reviewer 原本只靠 prompt 要求 JSON，API request 沒有 provider-level JSON schema；模型偶發缺欄或 envelope 變形時，strict parser 會正確 fail closed。
2. Fact verifier 只要求 verdict，`reject + issues=[]`、缺 issue metadata 或 generic issue 都被當成真實事實拒絕；同時 `pendingVerification` 保持 sticky，下一票可對未修改候選重投。結果不是連續 503，就是後一票 accept 抹掉前一票安全拒絕。
3. Debrief semantic cap 只有 3。DeepSeek timeout＋Claude generation 後雖仍在總上限 6 內，卻少一個 call，無法完成「full review → fact reject → repair → fresh fact verify」。
4. Prompt、schema、parser 的 fact field 契約沒有共用來源：DeepSeek prompt 未列 enum，Hint／Debrief 欄位混用，甚至 Hint JSON example 指向 Debrief `suggestedLine`，會製造可避免的 invalid schema／503。
5. Model repair 原本可加入任意 top-level／nested key；除了把「只改無關欄位」偽裝成 repair，還可能讓 untrusted property name 進入下一輪 Anthropic dynamic schema cache。
6. Telemetry 把 substantive semantic rejection 與 deadline 都歸成 `schema_invalid`，Claude regeneration 也把一般品質／策略／安全 reject 誤診成事實 grounding 問題。

## Final design invariants

- Claude Debrief reviewers 使用 `output_config.format=json_schema`；Hint 維持 prompt-only，避免把 Debrief schema 變更擴散到既有 Hint 路徑。
- Fact reject 必須含固定、privacy-safe 的 `kind + field + reasonCode`；accept 必須 `issues=[]`。缺欄、空 reject、錯 surface field、accept-with-issues 一律 fail closed。
- Prompt、Claude schema、parser 共用 surface-specific field helper：Hint 只允許三個可見欄位；Standard Debrief 不含 `gameBreakdown`；Game Debrief 才開該欄位。
- Substantive fact reject 後禁止再對原候選重投。唯一恢復路徑是：完整 repair → reviewer 點名的每個欄位都實際變更 → fresh fact verification。沒有最後驗證不得成功。
- Repair 的 object／array container shape 遞迴鎖定原候選 key 集合；model 不得增加 top-level、`gameBreakdown` 或 `hintAssessment` nested key，因此 untrusted key 不會進入後續 dynamic schema。
- Debrief semantic 最多 4 call、整個 request 最多 6 provider call；DeepSeek 初輪若 Claude recovery 可用仍只分 2 call，預留 Claude generation＋兩個 reviewer。任何異常 call count 保守扣完整 allocation，不能出現第七次。
- 所有 Debrief generation／reviewer 共用 request-entry 85 秒 deadline；每個 provider timeout 依剩餘時間 clamp。修復後若來不及 fresh verifier，也必須 fail closed、release owner、record 0。
- Telemetry 將事實／一般 semantic reject 分到 `semantic_rejected`，deadline 分到 `timeout`；failure code 只含固定 enum token，不落候選、逐字稿或自由文字。

## Independent review record

- State-machine review 找到並關閉：只改無關欄位即可繞過 changed-repair、一般 semantic reject 使用錯誤 retry diagnosis。
- Schema／privacy review 找到並關閉：DeepSeek prompt 未列 enum、cross-surface field、Hint 錯誤 example、top-level／nested key 注入、deadline telemetry 誤分類。
- Budget／ledger review確認：總上限 6、semantic 上限 4、85／90／105 秒 fences、失敗 release／零 record、成功 first-writer authoritative replay 均成立。
- 三路 final verdict 均為 **0 P0 / 0 P1 / 0 P2**。

## Validation before final deployment

- `deno test --no-check --allow-env --allow-read supabase/functions/practice-chat`：**934/934 passed**。
- 真 handler integration 實際走滿 DeepSeek 3＋Claude 3＝6 calls，完成 fact reject → changed repair → fresh verify；成功 record 1、release 0。
- Deadline regression 覆蓋：regeneration 前到期、full review 後到期、repair 後但 fresh verifier 前到期；全部不放行未驗證 candidate。
- 對抗 regression 覆蓋：第二票抹除 reject、只改 `vibe`、錯 surface field、空 reject、top-level／nested key injection、Hint／Debrief prompt-schema-parser enum drift。
- Changed files `deno fmt --check`、`deno lint`、`deno check semantic_quality.ts`、smoke tool check、`git diff --check` 全綠。
- `deno check index.ts` 仍命中既有 `handler.ts:484` 的 Deno 2.9 `setTimeout` handle 型別問題（來源 commit `bfbebd703`），非本 diff 引入；本輪不混入無關修正。

## Deployment gate

最終修正尚未部署。完成 `practice-chat` 目標式 Edge deploy、fresh Standard 單次 Debrief＋replay smoke、至少一條 Beginner assisted flow 與 production telemetry 抽查前，不宣稱 production safe。
