# Opener／New Topic 公式回覆實作計畫

> 日期：2026-07-24  
> 狀態：READY FOR CC IMPLEMENTATION  
> 風險：R2（`analyze-chat`、AI prompt/token、New Topic exactly-once ledger、Flutter cache/UI）  
> 實作 owner：Claude Code  
> 規格／整合 owner：Codex  
> 部署：本計畫不授權；實作與雙 review 完成後另等 Eric 明示

## 1. 目標

在既有兩個模式各增加兩則「固定結構、內容依本次素材動態生成」的公式回覆：

- Opener：新增 `formulaOpeners`
- New Topic：新增 `formulaTopics`

每則都同時具備：

1. 鉤子：對方有東西可以回。
2. 開口：對方不必想很久就能接。
3. 具體線索：引用對方可安全對外使用的實際素材，不是空泛稱讚。
4. 一小段「我」：低風險的當下反應、狀態或感受，不虛構人生經歷。
5. 共同點：只有輸入明確證明時才可使用。

本案沿用 Eric 已拍板的三項產品決策：

- 公式回覆併入原本同一次 AI 呼叫，不新增第二次模型請求。
- Free／Starter／Essential 全部可見，不上鎖、不做 tier 投影。
- 每則顯示可直接傳的 `openingLine` 與一句教練註解 `whyItWorks`。

## 2. 「不影響原有」的可驗證定義

本案的硬保證是契約隔離，不是模型文字逐字不變。

在模型回覆是「可解析 JSON object」，且只是 formula 欄位缺席／內容壞掉時，
必須保證：

- Opener 原本五型 `extend / resonate / tease / humor / coldRead` 仍是唯一
  `missingOpenerTypes()` completeness gate。
- New Topic 原本恰好五個 topics、四欄、推薦與 access 驗證全部不變。
- 公式欄位缺席、型別錯、超長、重複或內容不安全時，只丟公式項目。
- 公式欄位壞掉不得觸發 repair、不得造成 4xx/5xx、不得改變扣費。
- 原本 tier 投影、quota、rate limit、推薦、Opener contract v1/v2、
  New Topic exactly-once 與 replay 語意不變。
- 舊 App 忽略未知欄位；新 App 讀舊 response／cache 時得到空清單。

不承諾：

- 同一次 probabilistic AI 呼叫下，原五則文案與改動前逐字相同。
- 公式欄位每次都一定有兩則。模型失常時可以顯示 0 或 1 則，原結果仍成功。
- 模型在 formula string 內吐出未 escape 引號／換行，導致整份 JSON
  syntactically unparseable 時，仍能判斷「只有 formula 壞」。這種情況沿用原本
  malformed base repair；repair 仍失敗就 502、不扣費。
- Server canonicalizer 有 bug、讓非法 formula 進到 DB settlement 時仍回 base
  成功。DB constraint 是最後 fail-closed tripwire，必須讓整個 transaction
  rollback，而不是放寬資料庫。

驗收與對外說法統一使用：

> 公式回覆與原有內容在驗證、tier、扣費、repair、失敗處理及 replay 上完全隔離；公式失敗不會拖垮原結果。

不得宣稱「原五則文字完全不受 prompt 變更影響」。

對外更精確的工程說法是：

> 在模型回覆可解析時，formula 欄位內容失敗不會拖垮原結果；整份 JSON
> syntactically 壞掉仍沿用既有 base repair／不扣費保護。

## 3. 統一資料形狀

兩模式共用同一個 item shape：

```json
{
  "openingLine": "可直接送出的訊息",
  "whyItWorks": "一句教練註解：為什麼好接，必要時補她回後怎麼順著接"
}
```

Opener：

```json
{
  "formulaOpeners": [
    {
      "openingLine": "...",
      "whyItWorks": "..."
    },
    {
      "openingLine": "...",
      "whyItWorks": "..."
    }
  ]
}
```

New Topic：

```json
{
  "formulaTopics": [
    {
      "openingLine": "...",
      "whyItWorks": "..."
    },
    {
      "openingLine": "...",
      "whyItWorks": "..."
    }
  ]
}
```

長度規格：

- `openingLine`
  - prompt soft target：45–80 個繁中字元。
  - server/client/DB hard cap：180 Unicode code points。
- `whyItWorks`
  - prompt soft target：60–100 個繁中字元，一句到短兩句。
  - server/client/DB hard cap：300 Unicode code points。
- 超長一律丟整則，不截斷後顯示。
- 模型 schema 要求恰好兩則；server canonical 結果允許 0–2 則。

## 4. 共用公式 normalizer

新增：

```text
supabase/functions/analyze-chat/formula_reply.ts
supabase/functions/analyze-chat/formula_reply_test.ts
```

建議 API：

```ts
export type FormulaReply = {
  openingLine: string;
  whyItWorks: string;
};

export function normalizeFormulaReplies(
  value: unknown,
  options?: {
    excludeOpeningLines?: readonly string[];
    rejectInternalLabels?: boolean;
  },
): FormulaReply[];
```

規則：

1. 非 array → `[]`。
2. 依原始順序掃描，直到收滿兩個合法項目；不是先 `slice(0, 2)` 再驗證。
3. item 非 object、缺欄、欄位非 string、trim 後空白 → 丟整則。
4. 長度使用 Unicode code points：
   - TypeScript：`[...text].length`
   - Dart：`text.runes.length`
   - PostgreSQL：`char_length(text)`
   `openingLine` >180、`whyItWorks` >300 → 丟整則，不截斷。
5. visible-text markers 在 `trim()` 後檢查；任一欄符合以下即丟整則：
   - 包含 code fence `` ``` ``。
   - 以 `{` 或 `[` 開頭。
   - lowercase 後包含 schema 片段：
     `"formulaopeners"`、`"formulatopics"`、`"openingline"`、
     `"whyitworks"`、`"openers"` 或 `"topics"`。
6. 建立 deterministic dedupe key：
   - 先做 Unicode `NFKC` normalize。
   - 再轉小寫。
   - 移除一般空白與全形空白。
   - 標點保留，不做模糊語意比對，避免誤殺。
   - 兩則公式彼此 openingLine 重複，只留第一則。
   - 與 `excludeOpeningLines` 中任一原 opener/topic 重複，丟公式，不動原內容。
7. normalizer 只輸出兩個白名單 key；模型多吐的 key 不傳到 client/ledger。
8. `rejectInternalLabels=true` 時，任一可見欄位包含下列明顯內部來源標籤即丟：
   - `對象作戰板`
   - `對方作戰板`
   - `最近熱度`
   - `累計對話`
   - `你的備註`
   - `過往備註`
   - `性格分析`
   - `資料顯示`
   - `系統判斷`
9. 不做廣泛禁詞掃描，不誤殺自然語句；安全主責仍是 prompt，這裡只擋明確內部標籤洩漏。
10. Prompt 中的強例 openingLine 必須加入 static
    `FORMULA_PROMPT_EXAMPLE_LINES` exclude set；模型逐字照抄範例時丟 formula，
    不得把與本次素材無關的山頂照送給使用者。
11. 此 helper 不 import Edge server、不碰 DB，可純 unit test。

## 5. Prompt 公式

### 5.1 Opener 公式開場

在 `OPENER_PROMPT` 輸出格式前新增 clearly-scoped 區塊。以下語意是
binding，不得自行改成另一套公式：

```text
## 公式開場（額外兩則，不取代上面的五種風格）

另外產出恰好兩則公式開場。它們是額外選項，不得刪除、合併、改寫或減少
extend / resonate / tease / humor / coldRead 五種開場。

每則都要同時有：
1. 鉤子：抓對方資料裡一個具體、可安全說出口的細節；不是稱讚外貌，也不是
   複述禁忌或內部分析。
2. 一小段「我」：使用者當下的低風險反應、狀態或感受。不得虛構使用者去過
   哪裡、做過什麼、擁有什麼經歷；沒有使用者事實時，可寫看到素材後的自然
   反應。
3. 好接的開口：讓對方可以反駁、補一個細節、做簡單選擇或分享小故事。

只有輸入明確證明共同經歷／共同興趣時，才能寫「我們／我也」；不得把
effectiveStyleContext 與對方素材自行拼成共同點。

可選加入一個具體可填補的資訊缺口，但不要變成查戶口或連環問。
openingLine 可以比五種短句稍長，但仍要像真人可直接傳送。
whyItWorks 用一句教練話說明這句接了哪個細節、為什麼好回；若自然，可補
對方回後怎麼順著接。

弱例（太空泛）：
「妳看起來很有趣，平常喜歡做什麼？」

強例只示範結構，不得照抄：
「妳那張山頂照讓我有點想把週末從沙發救回來。那條是新手也能活著下山的
路線嗎？」
＝具體照片線索＋我的當下反應＋容易補充的資訊缺口。

所有既有 avoidTopics、grounding、安全、可見句不夾技巧名規則同樣適用。
openingLine 目標 45–80 個繁中字元；whyItWorks 目標 60–100 個繁中字元。
```

JSON schema 順序：

1. 原 `profileAnalysis`
2. 原 `openers`
3. 原 `pioneerPlan`
4. 原 `recommendation`
5. 最後才是 `formulaOpeners`

公式欄位放最後，優先讓模型先完成原契約。

### 5.2 New Topic 公式話題

在 `NEW_TOPIC_PROMPT` 輸出格式前新增：

```text
## 公式新話題（額外兩則，不取代五個 topics）

另外產出恰好兩則公式新話題。它們是額外選項，不得刪除、合併、改寫或減少
原本恰好五個 topics，也不參與 recommendation.index。

每則都要同時有：
1. 鉤子：從「對方作戰板」取一個可安全對外使用的具體生活線索。
2. 一小段「我」：從「關於我」取有根據的使用者素材，或使用低風險的當下
   反應；不得虛構使用者經歷。
3. 好接的開口：讓對方容易補充、選擇、反駁或分享一小段故事。

只有素材明確證明共同經歷／共同興趣時才能寫「我們／我也」。不能因為
「關於我」和「對方作戰板」剛好出現相似詞，就自行宣稱共同點。

禁止把作戰板的內部來源與標籤寫進可見文字，包括：
「對象作戰板、對方作戰板、最近熱度、累計對話、你的備註、過往備註、
性格分析、資料顯示、系統判斷」。
不得讓對方知道系統如何記錄或推測她。

went_cold / after_date / stuck / warm_up 的既有節奏規則全部繼續適用。
openingLine 目標 45–80 個繁中字元；whyItWorks 目標 60–100 個繁中字元。
whyItWorks 用一句教練話說明為什麼這句現在好接；若自然，可補她回後怎麼
順著接。
```

JSON schema 順序：

1. 原 `topics`
2. 原 `recommendation`
3. 最後才是 `formulaTopics`

公式不進 `recommendation.index`，不改原五題方向與推薦契約。

## 6. Opener backend

變更：

- `supabase/functions/analyze-chat/index.ts`
- `supabase/functions/analyze-chat/opener_payload.ts`
- `supabase/functions/analyze-chat/opener_prompt_test.ts`
- `supabase/functions/analyze-chat/opener_payload_test.ts`
- `supabase/functions/analyze-chat/index_test.ts`
- 新增共用 `formula_reply.ts` 與測試

### 6.1 Primary 與 repair 資料流

同一個 primary AI response 內必須分成兩條資料路徑；不是第二次 AI call：

```ts
const primaryParsedObject = parseJsonObjectFromText(rawText);
const primaryFormulaRaw = primaryParsedObject?.formulaOpeners;
let parsed = normalizeOpenerPayload(primaryParsedObject);
```

後續原本的 malformed/completeness repair 只處理 base payload。

Base 經可能的 repair 完成、取得最終五句 canonical openers 後，才 normalize
`primaryFormulaRaw`，並以最終五句＋`FORMULA_PROMPT_EXAMPLE_LINES` 做
cross-field dedupe。不得在 repair 前先完成公式去重。

公式選擇固定為：

- Primary 有合法公式：保留 primary canonical 結果。
- Repair 回覆即使意外含 formula，也不得採用；repair 只負責 base。
- Primary 沒有合法公式：`[]`。
- 公式欄位自身壞掉：不得因此呼叫 repair。
- 整份 primary JSON 無法 parse：沿用 base repair；公式固定 `[]`。

### 6.2 Raw 欄位不可穿透

現有 `normalizeOpenerPayload()` 與
`filterOpenerPayloadForAllowedFeatures()` 會 `...parsed`。實作必須保證 raw
`formulaOpeners` 不可能原樣回傳。

可接受兩種做法：

1. base normalizer/filter 明確排除 `formulaOpeners`，最後由 handler 加回 canonical array。
2. handler 最終 response 永遠以
   `formulaOpeners: canonicalFormulaOpeners` 覆蓋 raw 值。

建議兩層都做：normalizer 不保留 raw，response 再明確覆蓋，並用測試鎖住。

### 6.3 Tier 與回應

- `missingOpenerTypes()` 不看公式。
- `filterOpenerPayloadForAllowedFeatures()` 不投影公式。
- Free v1、Free v2、Starter、Essential 都收到同一個 canonical
  `formulaOpeners`。
- 先完成原 tier filter，再將 canonical 公式加到 response。
- 新 Edge 成功 response 一律帶 `formulaOpeners`，即使是 `[]`。
- 不 bump `openerContractVersion`；它只負責原五型的 Free v1/v2 投影。
- 不修改 quota、requestId、opener charge dedup 或 access metadata。
- Opener 沒有 New Topic 那種 DB result ledger；公式只沿用既有本機
  draft/cache JSON。沒有 Opener DB migration。

## 7. New Topic backend 與 exactly-once

變更：

- `supabase/functions/analyze-chat/new_topic_prompt.ts`
- `supabase/functions/analyze-chat/new_topic_payload.ts`
- `supabase/functions/analyze-chat/new_topic_billing.ts`
- `supabase/functions/analyze-chat/index.ts`
- 對應 prompt/payload/billing/source/index tests
- 新 migration：
  `supabase/migrations/20260724180000_new_topic_formula_topics.sql`

### 7.1 Primary 與 repair

同一個 primary AI response parse 一次後分兩條：

- 原 topics/recommendation → 既有 `normalizeNewTopicModelPayload()` strict gate。
- `formulaTopics` → `normalizeFormulaReplies()` best-effort。

原 topics invalid 時：

- 既有 same-model repair 照常執行，只修 topics/recommendation。
- Formula invalid 不觸發 repair。
- Primary 有合法公式時，在 base repair 成功後仍可保留。
- Primary JSON 本身完全無法 parse 時，公式回 `[]`。
- Repair 回覆即使意外含 formula 也不得採用；兩模式規則一致。

base topics 五題 canonicalize 完成後，把其五個 `openingLine` 傳給公式
normalizer，連同 `FORMULA_PROMPT_EXAMPLE_LINES` 做 cross-field dedupe。

### 7.2 Ledger result

`NewTopicLedgerResult` 擴充為：

```ts
type NewTopicLedgerResult = {
  topics: NewTopicLedgerTopic[];
  recommendation: { topicId: string; reason?: string };
  access: NewTopicAccess;
  formulaTopics?: FormulaReply[];
};
```

相容規則：

- 舊 stored row 沒有 `formulaTopics`：合法，replay 時 client 解析成 `[]`。
- 新 Edge 建立的 row：一律有 `formulaTopics`，值為 0–2 則 canonical array。
- Free／Paid topic selection 與 tier projection 只讀原 `topics`，永遠不讀
  `formulaTopics`；canonical `formulaTopics` 原封存入兩種 tier 的 ledger。
- `newTopicSuccessBody()` 仍只在 stored result 外加固定 `usage.cost=3`。
- Fresh 與同 requestId replay 必須回同一份 stored `formulaTopics`。

### 7.3 新 additive migration

已部署的 `20260724120000_new_topic_exactly_once.sql` 不得修改。

新 migration 必須：

1. `DROP CONSTRAINT new_topic_requests_result_state_consistency` 後以向後相容
   版本重建。
2. 舊三-key result 繼續合法。
3. 新四-key result 只允許多一個 `formulaTopics`；其他未知頂層 key 仍拒絕。
4. `formulaTopics` 若存在：
   - 必須是 array。
   - 長度 0–2。
   - 每項必須恰好 `openingLine / whyItWorks` 兩鍵。
   - 兩欄皆為非空 string。
   - PostgreSQL `char_length()` hard cap 分別 180／300 Unicode code points；
     與 TypeScript `[...text].length`、Dart `runes.length` 對齊。
5. `CREATE OR REPLACE FUNCTION validate_new_topic_result(jsonb)` 同步接受
   legacy/new shape，並驗 formula。
6. `new_topic_contract_version()` 更新為
   `new-topic-exactly-once-v2`，只有新 constraint／validator／RPC 俱全時回 v2。
7. 原 RLS、function grants、cron、lease、settlement、quota transaction
   全部不變。
8. migration 在 transaction 內執行，失敗由 PostgreSQL transaction rollback；
   成功套用後採 forward-fix，不提供把 v2 constraint 降回 v1 的 down migration
   （已有四-key row 時降回會失敗）。
9. migration 不得刪現有 row，不新增含原始 Partner 素材的欄位。

### 7.4 Rollout／rollback 相容

Release 時分兩個 Edge 相容點：

1. Compatibility Edge
   - TypeScript validator 已能讀 legacy 三-key與新四-key。
   - 尚未要求模型生成公式。
   - migration-first 後可安全部署。
2. Feature Edge
   - Prompt、normalizer、ledger 寫入與 response 全部啟用。

若 feature Edge 需 rollback，動作是「把 Edge 恢復到 compatibility Edge」；
additive migration 保留，不做 schema rollback。不可回到會拒絕四-key replay
row 的舊 production commit。

本計畫只要求 CC 準備這兩個可辨識 commits／refs；沒有 Eric 明示不得實際
apply migration 或 deploy。

## 8. Token、deadline 與成本

本案初版固定：

- `OPENER_MAX_TOKENS` 維持 3000。
- `NEW_TOPIC_MAX_TOKENS` 維持 3000。
- Opener／New Topic request/generation/settlement deadlines 全部不改。
- quota cost 仍為 3，不因公式成功數量改變。
- 公式 prompt/output 會增加供應商 input/output token 成本；這是需量測的
  business cost，但不改使用者 quota cost、tier、billing classification 或
  `usage.cost=3`。

理由：

- 目前 Opener 已知完整成功輸出約 1566–1597 tokens，3000 尚有空間。
- 公式 prompt 有 45–80／60–100 的 soft targets，不應用 180／300 hard cap
  當正常輸出長度。
- 未取得新 prompt 的 p95 token／stop_reason／latency 前，不可憑猜測提高 cap。

New Topic evidence gate：

- CC 在 Review Packet 中先提供目前可得的 New Topic
  outputTokens／stopReason 分布；沒有證據就標 `NOT MEASURED`，不得捏造。
- Feature Edge 啟用前，需在 Eric 明示允許 paid external calls／deploy 後，
  用新 prompt 做至少 20 次不落帳或測試帳號 black-box sample，確認 base
  completeness、formula count、output tokens、stop reason、latency 與 repair
  rate；此步未過不得啟用 feature Edge。

新增不含內容的 telemetry：

- `formulaOpenersCount`
- `formulaTopicsCount`
- `formulaOpenersDroppedCount`
- `formulaTopicsDroppedCount`
- 既有 input/output tokens、stopReason、repaired 繼續記錄

`DroppedCount` 定義為「本次模型 formula array 中被檢查、但未進 canonical
0–2 結果的項目數」，包含 malformed、over-cap、schema leak、internal label、
duplicate 與超過兩則；只記總數，不記內容。若實作需要細分 reason，只能使用
固定 enum count，仍不得記文字。

不得 log openingLine、whyItWorks、Partner 原文或 formula raw output。

若 dogfood/live evidence 顯示 `max_tokens` 截斷或 p95 接近上限，再另案評估
3000→3600；不得在本案預先上修。

## 9. Flutter data layer

### 9.1 Opener

`lib/features/opener/data/services/opener_service.dart`：

```dart
class OpenerFormulaReply {
  const OpenerFormulaReply({
    required this.openingLine,
    required this.whyItWorks,
  });

  final String openingLine;
  final String whyItWorks;
}
```

`OpenerResult` 新增：

```dart
final List<OpenerFormulaReply> formulaOpeners;
```

規則：

- constructor 預設 `const []`。
- `fromJson` best-effort。Dart 重新檢查兩欄 string/nonblank、
  `runes.length` 180／300、code fence／JSON/schema markers 與明顯內部標籤；
  server canonical 是主防線，client 是 cache／transport defense-in-depth。
- `toJson` 寫入 canonical list，供 opener draft/cache round-trip。
- `visibleForAccess()` 原封傳遞；不得做 Free projection。
- `withRequestId()` 原封傳遞。
- 舊 cache 缺欄 → `[]`。
- response 手動建構 `OpenerResult` 時解析公式；壞公式不影響原 openers。

### 9.2 New Topic

`lib/features/new_topic/domain/entities/new_topic_result.dart` 新增：

```dart
class NewTopicFormulaIdea {
  const NewTopicFormulaIdea({
    required this.openingLine,
    required this.whyItWorks,
  });

  final String openingLine;
  final String whyItWorks;
}
```

`NewTopicResult` 新增：

```dart
final List<NewTopicFormulaIdea> formulaTopics;
```

解析順序：

1. 先完成原 topics/recommendation/access 的 strict parse。
2. 原 result 合法後，才 best-effort 解析 formula。
3. formula 缺席／壞掉回 `[]`，不得讓 `tryParse()` 變 null。

`NewTopicService` 現在已直接把 response 交給 `NewTopicResult.tryParse()`；
若不需其他傳遞，不要為了符合檔案清單做無意義修改。

## 10. Flutter UI

### 10.1 共用顯示語意

使用者可見名稱：

- Opener：`公式開場`
- New Topic：`公式新話題`

區塊副標：

> 具體線索＋你的當下反應＋一個好接的開口

每張卡：

- 顯示完整 `openingLine`。
- 顯示 `whyItWorks`，標籤用 `為什麼好接`。
- 複製只複製 `openingLine`。
- 複製後使用既有 snackbar 語氣。
- formula 空陣列時整區不渲染，不留標題／間距。
- 只有一則時只渲染一張，不補空卡。
- 本案不替公式卡新增 opener outcome/reaction bar，避免混進既有五風格
  adviceType 指標；若未來要量公式成效，另做明確事件 schema。

### 10.2 Opener placement

在既有五風格橫向卡片、對應 outcome bars 與推薦理由之後，`pioneerPlan`
之前插入公式區塊。

不得把公式插在五風格卡與其 outcome bars 中間。

原標題 `・N 種風格` 仍只計原五風格可見卡，公式不計入 N。

公式卡使用垂直、自適應高度，不套現有固定 220 高的 opener style card，
避免 180＋300 hard-cap 內容被 ellipsis。

### 10.3 New Topic placement

順序：

1. 原推薦理由。
2. 原可見 topics。
3. 公式新話題區。
4. Free `還有 4 個` upsell CTA。

這讓 Free 使用者清楚看到公式本來就可用，而 CTA 只鎖原本另外四個 topics。

原 `access.totalCount=5`、Free 1／Paid 5 文案不因公式改成 7。

## 11. Backend tests

### 11.1 Formula helper

- 缺席／null／非 array → `[]`。
- 兩則合法 → 兩則。
- 前兩筆有壞項、第三筆合法 → 繼續掃到兩則合法。
- 缺欄、非 string、空白、超長 → 丟整則。
- code fence／raw JSON／schema key 洩漏 → 丟整則。
- astral emoji 邊界以 Unicode code points 對齊 TS／Dart／SQL。
- 多於兩則 → 最多兩則。
- formula 彼此重複 → 只留第一則。
- 與原 opener/topic openingLine 重複 → 丟 formula。
- 明顯內部作戰板標籤 → 丟 formula。
- 多餘 object key 不出現在 canonical output。

### 11.2 Opener

- Prompt 有公式段、原五型 schema 與 formulaOpeners，且公式 key 在最後。
- `OPENER_MAX_TOKENS=3000` 不變。
- 原五型完整、formula 壞 → 200 path，五型不變、公式 `[]`、不 repair。
- 原五型缺一、formula 完整 → 仍走原 repair／失敗 gate。
- Primary formula 完整、base repair 成功 → 公式仍保留。
- Repair 新增／改寫 opener 後，以最終五句重新 dedupe formula。
- Primary JSON 因 formula string 未 escape 而整份不可 parse → 走既有 base
  repair；repair 成功則 formula `[]`，repair 失敗則 502／不扣。
- Free v1／Free v2／Paid 都收到相同公式。
- raw string／50-item `formulaOpeners` 絕不穿透 response。
- missingOpenerTypes 與 tier filter 的既有測試維持綠。

### 11.3 New Topic

- Prompt 有公式段、原恰好五題與 formulaTopics，且公式 key 在最後。
- `NEW_TOPIC_MAX_TOKENS=3000` 不變。
- 五題完整、formula 壞 → strict base 成功、公式 `[]`、不 repair。
- 五題壞、formula 完整 → base 仍 repair／502，不因 formula 變成功。
- Primary formula 完整、base repair 成功 → 公式可保留。
- Primary JSON 因 formula string 未 escape 而整份不可 parse → 走既有 base
  repair；repair 成功則 formula `[]`，repair 失敗則 502／不扣。
- Free row 原 topics 只存一題，但公式存 0–2 則。
- Paid row topics 五題，公式與 Free 不投影。
- fresh／replay body 的 formulaTopics 完全一致。
- legacy 三-key stored row 仍可 replay，client 公式為 `[]`。

### 11.4 SQL／migration

真 PostgreSQL smoke 至少驗證：

- 現有 legacy 三-key done row migration 後仍符合 constraint。
- 新四-key row 的 0／1／2 formula 均合法。
- 三則 formula、缺欄、超長、多餘 key、非 array 均被拒。
- invalid formula result settle 失敗且 quota/result 同 transaction rollback。
- legacy/new fresh settle、claim replay、late owner stored winner 全部維持。
- Free 1＋formula2 與 Paid 5＋formula2 都合法。
- `new_topic_contract_version()` 回 v2。
- RLS／function privilege／cron 不變。

## 12. Flutter tests

Opener：

- `OpenerResult.fromJson` 解析 0／1／2 則。
- 壞 formula 不拖垮 openers。
- `toJson → fromJson` cache round-trip。
- `visibleForAccess` Free／Paid 都保留 formula。
- `withRequestId` 保留 formula。
- 舊 cache 無欄位 → `[]`。
- widget：0 不渲染、1/2 正確渲染、複製只複製 openingLine。
- 長邊界文字與窄螢幕不 overflow。
- 原 `・N 種風格` 不把公式算進去。

New Topic：

- 原 result strict valid＋formula valid → 成功。
- 原 result strict valid＋formula malformed → 成功且 `[]`。
- 原 result strict invalid＋formula valid → 仍失敗。
- legacy replay 無 formula → 成功且 `[]`。
- widget：公式在 upsell 前；Free／Paid 都顯示。
- 0/1/2 與窄螢幕 overflow。
- 複製只複製 openingLine。

完整驗證：

```text
deno test --allow-read supabase/functions/analyze-chat/formula_reply_test.ts
deno test --allow-read supabase/functions/analyze-chat/opener_*_test.ts
deno test --allow-read supabase/functions/analyze-chat/new_topic_*_test.ts
deno test --allow-read supabase/functions/analyze-chat/
deno check supabase/functions/analyze-chat/index.ts

flutter analyze
flutter test test/unit/features/opener/
flutter test test/unit/features/new_topic/
flutter test test/widget/features/opener/
flutter test test/widget/features/new_topic/
flutter test
```

實際命令依 repo 可執行 glob 調整，但 Review Packet 必須列 exact commands。

## 13. 建議 commits

一 concern 一顆，繁體中文：

1. `擴充新話題重播帳本相容公式欄位`
   - additive migration
   - TS ledger validator compatibility
   - v2 marker
   - SQL／billing／payload tests
   - 此 commit 是 rollback-compatible Edge ref

2. `開場救星與新話題新增公式回覆`
   - shared normalizer
   - prompts
   - primary／repair retention
   - response／ledger wiring
   - Deno tests／telemetry

3. `前端解析並快取公式回覆`
   - Opener／New Topic entities
   - parsing／cache／access pass-through
   - unit tests

4. `開場救星顯示公式開場與公式新話題`
   - UI placement
   - copy UX
   - widget/overflow tests

5. `補公式回覆審查與部署文件`
   - Review Packet
   - migration/rollout/rollback evidence

CC 開工時記錄 `BASE_SHA`。本規格未授權 push 或 deploy；commit 可以完成，
push 依 Eric 當次明示與 repo 規則處理。

## 14. Review gate

這是 material R2：

- Opener／New Topic AI prompt。
- Token/cost/repair deadline。
- New Topic deployed exactly-once schema 與 migration。

完成實作與測試後必須：

1. 準備 exact `BASE_SHA..HEAD_SHA` Review Packet。
2. Active implementer 自查。
3. opposite frontier 做 read-only peer review。
4. GLM 做獨立 falsification pass。
5. 主 integration owner 逐項回查 source evidence，不能用多數決。
6. 最多兩輪；仍有 blocker 就停，不得宣稱 safe。

Review focus：

- legacy 三-key／new 四-key ledger 相容與 rollback。
- fresh/replay formula 一致。
- raw formula 不穿透。
- formula 壞掉不 repair、不扣費、不拖 base。
- grounding／內部作戰板資訊不外露。
- Free／Paid 公式全可見但原 topics/opener counts 不變。
- token cap 維持 3000 的 evidence。

未收到雙 review APPROVED 前：

- 不 apply migration。
- 不部署 analyze-chat。
- 不建立 dogfood-safe／TestFlight-safe 宣稱。

## 15. 部署與 live smoke（另需 Eric 明示）

部署順序：

1. 目標式 apply 新 additive migration，禁止 `db push`。
2. 驗 v2 marker、constraint、validator、RLS、RPC privileges、cron。
3. 部署 compatibility Edge。
4. 跑 legacy 三-key與新四-key PG/replay smoke。
5. 部署 feature Edge：

```text
supabase functions deploy analyze-chat --no-verify-jwt --project-ref fcmwrmwdoqiqdnbisdpg
```

6. 先 smoke 舊 App／Opener v1，再 v2，再 New Topic。
7. 固定 fixture 各跑 Opener／New Topic 至少 10 次，記錄：
   - base success rate
   - formula count 0/1/2
   - repair rate
   - output tokens
   - stop reason
   - latency
8. New Topic fresh 後以同 requestId replay，body 必須相同。
9. Free／Paid 都看到公式；原 Free/Paid counts/access 不變。
10. App build 目檢區塊順序、複製、長文、窄螢幕。

Live smoke 不比較模型文字逐字相同；比較的是契約不變量、成功率與品質 rubric。

## 16. Out of scope

- 不改原五種 opener 文案、名稱、推薦算法或 access 投影。
- 不改 New Topic 原五題 schema、推薦、Free 1／Paid 5、quota 3。
- 不新增第二次 AI request。
- 不把公式加入 recommendation.index。
- 不做公式收藏、歷史、跨頁持久化；Opener 只沿用既有 draft/cache。
- 不新增 formula outcome/reaction analytics。
- 不處理 opener Game 化或 arbitration queue 其他案。
- 不預先提高 token cap。

## 17. 完成回報格式

```text
狀態：
- IMPLEMENTED / BLOCKED

Branch / Worktree：
- ...

Range：
- BASE_SHA..HEAD_SHA

Commits：
- ...

Migration：
- 20260724180000_new_topic_formula_topics.sql
- legacy/new validator smoke：
- DB marker：

Backend：
- Opener base/formula isolation：
- New Topic base/formula isolation：
- fresh/replay：
- Free/Paid：
- raw formula leak guard：
- telemetry：

Frontend：
- Opener cache/access：
- New Topic parser：
- UI placement／copy／overflow：

測試：
- Targeted Deno：
- Full analyze-chat Deno：
- Deno check：
- Targeted Flutter：
- Full Flutter：
- Flutter analyze：
- PostgreSQL smoke：

Cross-model review：
- Claude/Codex peer：
- GLM adversarial：
- Reconciliation：

未執行：
- push / migration / deploy / live smoke / TestFlight

Open concerns：
- none / ...
```
