# Practice Debrief 語意複核失敗根治 Codex Review

Date: 2026-07-19

Scope: `practice-chat` Debrief generation／semantic adjudication／Claude structured output、相關 client contract 註解與 durable docs

Verdict: **APPROVED（0 P0 / 0 P1 / 0 P2）**

## Production evidence

- Production `practice-chat` v200 在 2026-07-18 22:43:48、22:44:19 UTC 對同一 Essential 使用者連續失敗。
- DeepSeek Debrief 候選已生成；失敗發生在 Claude semantic reviewer。`ai_logs` 皆為 `schema_invalid`，`semanticProviderCalls=3`，failure code 分別落在 `semantic_adjudication_invalid_schema` 與 repair-unverified。
- 同版本稍後有其他 Standard Debrief 成功，排除全站 provider outage。Hosted v200 與 main handler／semantic／Claude caller SHA 相同，排除部署分支漂移。
- Claim 失敗後有 release exact owner；沒有 Debrief record、卡片或 quota charge。

## Root cause

1. Claude reviewer 只被 prompt 要求 JSON，API request 沒有 provider-level JSON schema；模型偶發缺欄或 envelope 變形時，嚴格 parser 正確 fail closed。
2. Handler 一旦開始 semantic adjudication 就封死 generation failover；直接移除此 sticky 也不夠，因 production adjudicator 會先耗完整三次 reviewer budget，剩餘額度不足以做「Claude regeneration＋full review＋fact verifier」。原先以人工 `providerCalls=1` 注入的 recovery test 是 production-unreachable false positive。
3. 若只擴大 call budget，最壞獨立 timeout 會穿透 mobile 90 秒與 DB owner 105 秒，造成 client 已放棄但 server 仍持有 owner。

## Final design invariants

- Claude reviewer 使用 `output_config.format=json_schema`；strict parser、hard guard、refusal／`max_tokens` fail-closed 仍是最後權威。
- Debrief budget 最多六次：初始 generation 1；若 Claude recovery 可用，初輪 semantic 最多 2，預留 Claude generation 1＋full reviewer 1＋fact verifier 1。任何異常 call count 都保守扣完整 allocation，不能出現第七次。
- 所有 Debrief generation／reviewer 共用從 handler entry 起算的 85 秒 absolute deadline；每個 provider timeout 依剩餘時間 clamp。到期回 retryable 503、release owner、record 0。
- Hint 維持既有 sticky fail-closed 行為與最多五次 call；本案不開 Hint post-semantic regeneration。
- 無 applied Hint 的 Debrief 不把 model-authored `hintAssessment` 帶入動態 schema；assisted path 只接受 server canonical shape。
- Reviewer verdict／issue metadata 大小寫正規化後再走 allowlist；產品候選 schema 與 visible content 不放寬。

## Independent review record

- Initial high-risk review：抓到兩個 P1——recovery path 不可達、缺 shared absolute deadline；另有成本契約 P2。
- Timeout／test re-review：PASS，0 P0/P1/P2。確認 85 秒 deadline、六次 ledger、Hint sticky、失敗 release／零 record。
- Structured schema re-review：APPROVED，0 P0/P1/P2。確認 Sonnet 5／Haiku 4.5 schema 相容、雙向 `revisedEvidenceQuote` union、metadata casing 與 unassisted schema boundary。
- Final high-risk review：APPROVED，0 P0/P1/P2。Bootstrap queue、client comments、design／review durable contract 均已同步 Hint 5、Debrief 6 與 85／90／105 秒 fences。

## Validation before deployment

- `practice-chat` full Deno suite：**923/923 passed**。
- Handler：**212/212 passed**；semantic＋Claude caller：**34/34 passed**。
- 真 adjudicator integration 實際走滿六次 provider call，並驗證後段 timeout 依共同 deadline clamp 為 20s／15s；不是人工注入短路。
- Deadline failure tests：regeneration 前到期不呼叫 Claude；full review 後到期不啟動 fact verifier；兩者皆 503、release exact owner、record 0。
- `deno fmt --check`、Dart format、`git diff --check` 通過。
- `deno check index.ts` 仍命中既有 `handler.ts` `setTimeout` handle 型別問題（來源 commit `bfbebd703`），非本 diff 引入；本輪不混入無關修正。

## Deployment gate

Edge deploy 與 test-account Standard／Beginner／Game live smoke 尚未執行；完成前不得宣稱 production safe。
