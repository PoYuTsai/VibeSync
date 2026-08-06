# Hint 守門嚴重度分級設計(2026-08-06,Eric 逐段拍板)

> Debrief 守門嚴重度分級(6e2e7466..6e5e92bb)的同型另案。目標三合一:
> 低延遲(偏好門不再燒補發)+輸出好建議(模型卡優於重試殘局)+穩定不 503
> (出口縮到紅線/結構雙發全滅)。

## 背景與差異

Debrief 當時的病是「好卡被殺→端出更爛的修補模板」;hint 已吃過兩輪止血
(2938c1f0 通用解、2026-08-05 salvage),病型不同:**好卡被殺→燒 5-15 秒
補發,最後 salvage 多半端回同一張卡**。歷史數據 35% attempt 失敗率,每次
失敗燒一發模型呼叫。同型分級套上來,收益主體是延遲與兩管線模型統一,
salvage 複雜度整條拆除是自然結果。

## 一、逐門嚴重度判定表(Eric 拍板)

### 維持否決權(打回→補發;重生成真的有救)

| 門 | 理由 |
|---|---|
| 紅線四類(罐頭/洩漏/L4/溫度) | 不變,使用者絕不能看到 |
| 壞 JSON/缺欄/型別錯/超長 | 結構失敗,salvage 本來也救不了 |
| `hint_quality_invalid_duplicate_replies` | 模型空轉,同 debrief Game 拆盤欄位互抄拍板照擋;**最後一發沿用 degrade 剪成一句端出+finding,不 503** |
| Game 契約 slug(game心法/速約任務) | client 渲染依賴的 deterministic 契約 |
| `hint_no_pasteable_conflict` | 既說沒句子又給句子=自相矛盾,不猜 |

### 降級為 finding(第一發即收卡,碼記 telemetry)

| 門 | 理由 |
|---|---|
| `hint_quality_invalid_not_grounded` | 短對話結構性不可能過,debrief 21 天實證同型;salvage 現在也已原諒它 |
| `unsupported_detail`(fact ledger) | Eric 已在 debrief 拍板非紅線,同一條 |
| `hint_bossy_pasteable_reply` | 措辭偏好,卡仍可用 |
| 雙欄純問句(`HintPureQuestionError`) | 查戶口是品味問題不是壞卡;**專用重試回饋機制一併退役** |

### 靜默跳過→記 finding(不改放行行為,補觀測迴路)

`relaxSubjectiveQualityRubrics` 目前把三道門整個跳過:路線矛盾
(`invite_coaching_conflict`)、實質行動(`substantive_move`)、Game coaching
實質度。比照 debrief「hint 路線矛盾復活為 finding」——照放行,但記 finding,
telemetry 才看得見 finding 率。

## 二、salvage/重試鏈拆除與 prefetch 統一

- **`salvageHintCandidate` 整條刪除**:偏好門不殺卡後,雙發全滅只剩紅線/
  結構/API 錯,全是 salvage 救不了或不准救的。
- 連帶退役:`hintParseCandidate` 的 override 旗標(`skipLexicalGrounding`/
  `degradeStructuralDefects`/`salvagePass`)、`buildHintDecision` 的
  `salvagePass` 參數(邀約階梯讓路)、handler 的 `hintSalvageUsed` 與
  `practice_chat_generation_salvaged` 事件。
- `degradeStructuralDefects`(duplicate 剪一句)**不是刪,是移進正式路徑
  最後一發**。
- `SingleShotExhaustedError.raw` 保留機制:debrief salvage 還在用就不動,
  只剩 hint 用才評估。
- **重試鏈不動**:Sonnet→Haiku、timeout、deadline 全維持;只是觸發補發的
  敗因集合縮到「紅線+結構+API 錯」。
- **Prefetch 吃同一套分級**:消費路徑同一個 `parseHintResult`;預產 finding
  照記、帶 `prefetch: true` 分冷熱。「預產失敗絕不落 fallback 快照」鐵則
  不變——它管紅線/結構失敗不端罐頭,與 finding 卡照收不衝突。

## 三、telemetry、契約與驗證

- 事件名 `practice_chat_hint_quality_finding`,形狀鏡射 debrief 那顆
  (handler.ts `practice_chat_debrief_quality_finding`,鍵名是 **`codes`**):
  `codes`(一發可多類,同碼去重)、`model`、`practiceMode`、`prefetch`。
- **對比基準警告**:`practice_chat_generation_attempt` 敗因碼分佈會改變
  (偏好門碼從 failure 消失、改出現在 finding)。日後撈 ai_logs 別誤判
  「失敗率驟降」。
- **契約凍結**:`qualitySchemaVersion` 不 bump(client 相等比對,bump=
  舊 build 拒收,同 debrief 拍板)。`HINT_TOOL_SCHEMA`、client hint 渲染、
  `acceptsNoPasteableHint` 全不動——wire 形狀零改動。
- **測試**:每道降級門要有「踩門→卡照端+finding 碼被記」正反例;duplicate
  最後一發 degrade 專測;salvage 測試批次轉刪或改寫成「結構失敗雙發→503」
  窄出口測試。Deno 該檔+`deno check`。
- **上線觀測**:隔幾天撈 ai_logs 看 hint finding 率分佈;長期偏高=回頭修
  prompt 或門本身,**絕不加回否決權**。真機 dogfood:Game/新手各按一次
  hint,體感延遲+內容不空話。

## 刻意不動

debrief 管線(剛 ship 別回頭碰)、coach/opener 守門、OCR、
`visible_text_guard` 詞表本身。
