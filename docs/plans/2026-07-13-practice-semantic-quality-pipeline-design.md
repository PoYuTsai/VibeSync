# Practice Hint／Debrief 語意品質管線設計

> 日期：2026-07-13
> 狀態：Eric 已授權整體重構；本檔鎖定實作不變量與驗收標準。
> 範圍：Beginner Hint、Game Hint、兩型 Debrief、Prefetch 與 client 等待契約。

## 1. 使用者結果

1. Hint／Game Hint 點擊後只會出現通過模型生成與事實驗證的內容；沒有罐頭成功回覆。
2. 預產成功時點擊快速 replay；預產仍在途時可以多等，但不能因 client 提早 timeout 變成假失敗。
3. Game Hint 每個選項都要有本輪訊號、實際招式、目標與邀約階梯，不以固定口號冒充高手感。
4. Debrief 沿用被採用 Hint 的真實策略；除非 Hint 送出後她的新回覆提供反證，不能事後打臉。
5. 人名、地點、店名、偏好、行程、共同經歷等幻覺用通用語意驗證處理，不再靠持續增加中文 regex。

## 2. 2026-07-13 production 證據

- Game Hint 三次連續失敗時，DeepSeek 與 Claude 都在約 8–10 秒內回覆；六份候選被同一套 runtime guard 拒絕。失敗碼包含：
  - `hint_quality_invalid_not_grounded`
  - `hint_quality_invalid_unsupported_detail:third_party:name:is_named`
  - `hint_quality_invalid_unsupported_detail:world:venue:located_at`
  - `hint_quality_invalid_game_coaching_substance`
- 最新 `practice-chat v100` production smoke：Beginner Hint 成功，但 Debrief 連續三次 503；兩次為 `debrief_quality_invalid_suggested_line_not_grounded`，一次為 `debrief_l4_unsafe`。
- 同一版 targeted Deno baseline 為 403/403 綠。結論：現有測試鎖住 regex 行為，沒有鎖 live 可用率。
- `hint_fact_ledger.ts` 約 2,600 行，嘗試用 lexical rules 推斷中文自然語言的人名、地點、偏好、所有權、否定與共指。近期同一路徑連續出現店名、路名、地點、人名、echo、截斷與 Debrief repair 補丁，已構成架構性 whack-a-mole。

## 3. 根因

現況把三種不同責任塞進同一個同步 fail-closed parser：

1. **結構與安全**：JSON、欄位、長度、內部詞、L4、邀約越級。這些適合 deterministic hard guard。
2. **事實正確性**：有沒有編造人物、地點、行程或共同歷史。這需要讀懂語意與說話者，regex 不是可靠工具。
3. **教練品質**：是否具體、是否只問問題、Game coaching 是否夠高手。這是生成品質問題，不應用 lexical pattern 直接讓整個 request 503。

Failover 目前只是把第二個模型輸出送進同一套 guard；Prefetch 也只是提早撞同一面牆。增加 timeout 或 max tokens 只能改善 timeout／截斷，不能改善 acceptance rate。

另一個根因是 Hint lineage 太薄。`PracticeHintDecision.move` 目前主要只記 `build_connection / soft_invite / direct_invite / repair_safety`，沒有保存 callback、生活樣本、合作畫面、輕鬆張力等實際招式。Debrief 因此拿不到自己先前真正教了什麼，只能重新猜。

## 4. 新架構

### 4.1 三層責任

#### A. Deterministic hard guard

保留 fail-closed：

- JSON／schema／必填欄位／完整句與絕對長度。
- 可見內部標籤、L4、操控／羞辱／性壓力等安全紅線。
- Server FSM 算出的邀約上限；模型回覆不得越級。
- 策略 evidence reference 必須指向存在的 turn，quote 必須是該 turn 的 exact substring，owner 必須相符。
- Prefetch、requestId、quota、hint count、replay exactly-once 等既有計費不變量。

#### B. Semantic adjudicator

不再用 lexical hard reject 判斷以下項目：

- 人名／地點／店名／偏好／行程／共同歷史是否為未支持事實。
- 回覆是否真的接住最新一句，而非只碰到一個共同字。
- 是否空泛、只追問、只有稱讚、Game coaching 是否有具體任務。
- Debrief 可見欄位是否忠於逐字稿與被採用 Hint。

Adjudicator 只讀：完整候選、帶 turn id 的逐字稿、profile／scene 的可信證據、server FSM 邀約上限與 applied Hint decision。輸出固定 JSON：

```json
{
  "verdict": "accept | repair | reject",
  "issues": [
    {
      "field": "warmUp | steady | coaching | debrief.<field>",
      "kind": "unsupported_fact | generic | strategy_mismatch | unsafe",
      "span": "候選中的短片段",
      "reason": "簡短原因"
    }
  ],
  "repairedResult": null
}
```

- `accept`：採原候選。
- `repair`：`repairedResult` 必須是完整新候選，重新跑 hard guard。若 issue 是 `unsupported_fact` 或 `unsafe`，還必須由另一 provider 對修復後候選做獨立 semantic accept；budget 不足就 fail-closed。
- `reject` 或 repairedResult 仍不合格：最多再做一次定向修復；仍失敗才回 retryable 503，絕不回罐頭。
- Adjudicator 本身壞 JSON／timeout 時，改由另一 provider 做同一份 adjudication；不因裁判失效直接放行可能幻覺的內容。

#### C. Offline quality gate

「高手感」不再靠 production regex 判斷。用多情境 eval、golden anchors 與 Eric/Bruce 真機體感驗收：

- 是否抓到最新訊號。
- 是否一次一招、投入匹配。
- 是否包含 callback／生活樣本／合作畫面／輕鬆張力／邀約窗口等合時機戰術。
- 是否像可直接送出的真人句，而非教科書或罐頭。

Production runtime 只負責安全、事實與策略一致；風格品質透過 prompt、few-shot、semantic repair 與離線基準提升。

### 4.2 Hint 結構化策略

生成模型仍只產 `warmUp／steady／coaching`。獨立 semantic adjudicator 在審核時另外產生：

```json
{
  "warmUp": "可貼句",
  "steady": "可貼句",
  "coaching": "可見心法",
  "strategies": {
    "warmUp": {
      "move": "callback | self_disclosure | shared_scene | playful_reframe | answer_then_question | soft_invite | direct_invite | repair | hold",
      "evidenceTurnId": "turn-12",
      "evidenceQuote": "她最新一句中的逐字片段",
      "rationale": "本輪訊號、目標與原因"
    },
    "steady": {
      "move": "同上",
      "evidenceTurnId": "turn-12",
      "evidenceQuote": "逐字片段",
      "rationale": "原因"
    }
  }
}
```

Edge 對外仍回既有 `replies + coaching`，不把原始 strategy object 暴露成新 UI。現有 `decision.move` 改存真實招式，`decision.rationale` 存精簡策略理由；phase、targetVariable、inviteRoute 仍由 server FSM 權威決定。這讓既有 client JSON 契約可相容，又讓 Debrief 真的拿到 Hint 戰術。

### 4.3 Provider 管線

常態：

1. DeepSeek 生成候選。
2. Claude semantic adjudication；可在同一次回覆中修復候選。
3. hard guard 通過後才 record／prefetch snapshot。

例外：

- DeepSeek timeout／格式失敗：Claude 直接生成，之後仍需 adjudication。
- adjudicator timeout／壞 JSON：另一 provider 接手 adjudication。
- `unsupported_fact／unsafe` repair：另一 provider 必須覆核修復後全文；不能自證成功。
- repaired candidate hard guard 失敗：改由另一 reviewer 重判；budget 用完即 retryable 503。

現行 bounded budget（2026-07-19 修正）：Hint 最多五次 provider call；Debrief 常態為一次 generation＋full reviewer＋fact verifier，初輪 reviewer envelope 失敗時會預留 Claude regeneration＋同樣兩個 reviewer，最多六次。若 Claude candidate 的 fact verifier substantive reject，剩餘兩個 semantic call 只能走「完整且點名欄位實際變更的 repair → fresh fact verifier」；不可用第二票覆蓋未修改候選。Debrief semantic cap 為四，所有 generation／reviewer call 共用從 request entry 起算的 85 秒 deadline；client 90 秒、in-flight stale owner 105 秒。Hint client 維持 115 秒。Fact prompt、provider schema 與 parser 必須共用 surface-specific field enum，repair 的 nested key shape 必須保持 server canonical，避免 untrusted key 進入 dynamic schema。

### 4.4 Prefetch 與計費

- 只有通過 hard guard＋semantic adjudication 的 Hint 才能寫 `charged=false` prefetch snapshot。
- 使用者點擊仍由既有 settle RPC 原子扣 quota、計 hint count、標記 consumed；同 requestId exactly-once 不變。
- 點擊時 prefetch 在途：client await；同 session／aiCount／generation 仍有效才 dispatch formal request。
- Prefetch 全敗：release owner、不落 snapshot。Formal request 跑完整語意管線；仍失敗才顯示可重試錯誤。
- 不重建 `buildFallbackHintResult` 或任何罐頭 success path。

### 4.5 Debrief 連動

- Debrief prompt 讀取 latest applied Hint 的 phase、targetVariable、真實 move、inviteRoute、rationale 與原句。
- `hintAssessment` 保持 hidden，但升級為 typed continuity contract：
  - `preserved`：沿用 Hint 策略，只評執行與她的新反應。
  - `revised`：必須提供 Hint 送出後的 assistant turn id＋exact quote；server 驗證後才允許改判。
- Debrief candidate 也走 semantic adjudication。裁判必須檢查：
  - visible summary／strengths 有承認使用者採用 Hint。
  - watchouts 是下一步或執行差異，不把系統自己的 Hint 說成錯誤。
  - `suggestedLine` 與 Game `nextFirstLine` 都沿同一策略，除非 revised evidence 合法。
  - 所有新事實有來源；沒有就改成詢問、假設或不提。
- 移除逐題新增 `unansweredQuestionRepairLine` 類 deterministic 文案修補；修復由 semantic adjudicator 依當輪證據生成。

## 5. 不變量

1. **Generated only**：任何成功 Hint／Debrief 都必須來自模型候選，不能由罐頭 fallback 產生。
2. **No unreviewed claims**：含可見自然語言的成功結果必須通過 semantic adjudication；裁判失效不直接放行。
3. **Hard safety stays hard**：L4、操控、越界、JSON/schema、邀約越級與 evidence ref mismatch 仍 deterministic fail-closed。
4. **Consume-only billing**：Prefetch 不扣、不計次；formal settle 才扣／計，requestId exactly-once。
5. **No failed snapshot**：Prefetch 失敗、adjudication 失敗或 repair 失敗都不 record。
6. **Authoritative strategy**：phase／targetVariable／inviteRoute 由 server 決定；模型只能在允許 tactical enum 中選 move。
7. **Debrief continuity**：沒有合法 post-Hint assistant evidence 就不得 revised。
8. **No transcript telemetry**：只記 outcome、issue kind、provider、attempt、latency、token／prompt size，不記逐字稿、候選或 evidence quote。
9. **Bounded cost**：Hint 每 request 最多五次 provider call；Debrief 最多六次，且 85 秒 absolute deadline 會 clamp 每次 generation／reviewer timeout；不得無限自我修復。
10. **Old client compatibility**：server 內部與 snapshot 永遠保存 `semantic-quality-v2`；新 client 用 capability 宣告接受 v2，未宣告的 build 322 只在 HTTP envelope 收到 `typed-facts-v1` 相容標記，內容仍是 v2 管線產物。

## 6. Failure matrix

| 情境 | 結果 |
|---|---|
| DeepSeek 候選正確、Claude accept | record generated result |
| 候選有未支持店名／人名 | adjudicator repair；另一 provider accept＋hard guard 後才 record |
| 候選空泛／純問句／Game 任務不具體 | adjudicator repair，不因 lexical pattern 直接 503 |
| 候選 L4／操控／邀約越級 | hard reject；定向 repair，絕不先顯示 |
| evidence quote 不在 turn | hard reject；定向 repair |
| primary timeout | secondary generate＋adjudicate |
| adjudicator timeout／壞 JSON | alternate adjudicator；不得直接放行 |
| surface provider budget（Hint 5／Debrief 6）用完仍不合格 | retryable 503；不 record、不扣、不計、不回罐頭 |
| Prefetch success | opaque ack；snapshot 未 consumed |
| Prefetch failure | release；formal 點擊重新跑完整管線 |
| Formal 命中 prefetch | 原子 settle；零模型 call |
| Debrief preserved | 明確歸功 Hint，分析執行與後續反應 |
| Debrief 想 revised 但無 post-Hint quote | repair 成 preserved，不能打臉 Hint |
| Debrief revised evidence 合法 | 可調整策略並顯示引用後的理由 |
| Debrief request-entry 85 秒 deadline 到期 | 停止啟動 provider、release owner、retryable 503；不 record、不扣、不計 |

## 7. 驗收

### 自動測試

- hard guard 正負測：schema、L4、invite route、evidence reference、requestId／billing invariants。
- semantic adjudicator parser、provider failover、repair、Hint 5／Debrief 6 total budget exhaustion 與 85 秒 deadline。
- 既有 Game/Beginner prefetch、settle、replay、quota/count 全回歸。
- Debrief preserved/revised lineage 與 post-Hint evidence。
- 既有 regex false-positive fixtures 改驗「進 semantic repair」，不再驗「整份 reject」。

### Live eval

- Beginner 5 情境＋Game 5 情境，每情境至少 2 次，合計 20 組。
- Gate：20/20 有 generated Hint；0 未支持具體事實；0 known canned；20/20 strategy/evidence 可追溯。
- 套用其中至少 6 組 Hint 跑 Debrief：6/6 不打臉，除非有合法 post-Hint反證。
- 回報 P50/P95 latency、常態／最差 provider call count、prefetch hit/miss/fail；不只報單元測試。

## 8. Rollout

1. 先以測試鎖定 semantic schema、hard guard、Hint 5／Debrief 6 call budget、計費與 Debrief lineage。
2. Edge-first 部署；build 322 走 HTTP marker compatibility，新 client capability 才收 v2 marker。
3. Prefetch 只存 adjudicated v2 result；用測試帳號驗 quota／settle／replay 與舊 client response。
4. client Hint timeout 115 秒；Debrief server deadline／client timeout／stale owner 依序為 85／90／105 秒。
5. production live eval 與獨立 Codex review皆過，才通知 Eric 真機測試。

若新版 Edge 有 regression，先停發新 client 並 forward-fix；不得回退到會讓新 client schema mismatch、或重新放行 regex 罐頭／未審核候選的版本。計費 ledger、prefetch-aware compatibility floor 與 stored v2 certification 不回退。
