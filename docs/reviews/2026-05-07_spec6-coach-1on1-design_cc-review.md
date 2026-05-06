# CC Spec Review — Spec 6 Coach 1:1 / Coach-first Product Architecture

**Date:** 2026-05-07
**Reviewed doc:** `docs/plans/2026-05-07-spec6-coach-1on1-design.md` @ main `51746f6`
**Reviewer:** Claude Code（CC）— independent review, brief titled "Codex / CC Spec Review Brief"
**Verdict:** **APPROVED-WITH-AMENDMENTS**（含 3 項 Daisy-Decision-Needed）

> Filename note：brief 建議 `_codex-review.md`，但本檔由 CC 撰寫。為保留作者透明度改用 `_cc-review.md`。Codex 若另起一份獨立 review，仍走 `_codex-review.md`。

---

## Summary

整體方向**通過**：把 VibeSync 從「報表工具」推向「有上下文記憶的教練系統」是合理的下一步，且 Spec 1–5 的累積資產（記憶、樣式、品質守門、教練行動、跟進）正好構成 Spec 6 真正的護城河。

但設計文件在以下三個面向**還沒有把 Spec 5 已經建立的紀律寫死**，必須在動手之前補回，否則新 provider（OpenAI）會用一張白紙重新長出 Spec 5 已經學過的痛：

1. **Output safety 紅線詞契約**（A1）—— Spec 5 有 7 詞 `assertCardSafe`，Spec 6 §9.4 只用「不要操弄」一句話帶過。
2. **欄位字數上限**（A4）—— Spec 5 有 `FIELD_CAPS`（headline 30 / observation 80 / suggestedLine 80 / boundaryReminder 60）。Spec 6 §4.5 schema 只示範樣本，沒寫硬規。
3. **dataQualityFlagged × partnerHint 行為**（A7）—— §4.4 說「flagged 時避免 long-term partner memory」，但 §4.3 範例 payload 在 flagged 也照樣帶 `partnerHint.traits`。

這三項都是直接套 Spec 5 的紀律即可，屬於必要 amendment。

另有三項屬於 **Daisy-Decision-Needed**，CC 不仲裁，列項供 Eric / Bruce 拍板：

- **A2**：OpenAI 第三方 provider 的隱私揭露 vs ADR #1。
- **A5**：Healthy Sexual Tension Level 2 範例的 App Store / 17+ 評級風險。
- **A10**：Free tier × Coach 1:1 × Level 1/2 內容的合計風險。

---

## 對 brief 10 項問題的逐項判斷

| # | Brief 問題 | 判斷 | 備註 |
|---|---|---|---|
| 1 | Coach-first UI architecture 方向 | **APPROVED** | §1.2 的 "Every screen answers one question" 是好的設計濾鏡。Demote（不 delete）熱度/雷達是對的，避免破壞既有付費價值。 |
| 2 | Phase 6A scope 是否夠小 | **APPROVED** | 單回合、不寫長記憶、最近 3 筆 local、不收追問——和 Spec 5 同一套「先驗證生死點」紀律。 |
| 3 | OpenAI coach-chat Edge Function 隔離 | **APPROVED** | 同 Spec 5 的 `coach-follow-up` 隔離邏輯，是 OCR baseline 真正該守的線。Codex 在 Spec 5 review 已經立過原則，這裡延用合理。 |
| 4 | Input context contract 是否充足 | **APPROVED-WITH-AMENDMENTS** | Must-include / must-not-include 清單明確，但 dataQualityFlagged 行為要補（A7）。 |
| 5 | Response schema 是不是教練而非報告 | **APPROVED-WITH-AMENDMENTS** | mode + headline + answer + userState + nextStep + suggestedLine? 結構好；但 schema 沒寫 field caps（A4），且 mode 由模型決定，dogfood 沒 mode-correctness 的評分項（A8）。 |
| 6 | Healthy Sexual Tension policy | **APPROVED 框架，但 A5/A10 需 Daisy 拍板執行範圍** | 「不是消毒成安全提醒」的產品立場我贊成，這是 VibeSync 對比 ChatGPT 的真差異。但 Level 2 露骨範例、Free tier 普及、App Store 17+ 評級——這三件事的交集需要 Eric 決定。 |
| 7 | Coach reflection 是否進 v1 | **APPROVED** | 「先給判斷再可選追問」是對的（§11.2）。完整二問二答留 v1.1 也對。schema `needsReflection=true ⇒ reflectionQuestion required` 寫得乾淨。 |
| 8 | 6B/6C/6D/6E 拆分 | **APPROVED-WITH-AMENDMENTS** | 拆分本身合理。但 6A 在 6B 之前——Coach 卡放進「還沒重排序」的分析頁——dogfood 訊號會夾雜「卡片本身沒用」vs「卡片位置不對」。建議 6A 帶一個最小排序 tweak（A6）。 |
| 9 | Credit / privacy contract | **APPROVED-WITH-AMENDMENTS** | 計費規則 §4.10 的 invariant 「沒成功扣額度，不返回成功卡片」精準對應 Spec 5 P1 的 deductCredit silent-failure 教訓，這條必守。但 §12.5 隱私 copy 與 ADR #1 的關係要補（A2）。 |
| 10 | Dogfood 評分（"比 ChatGPT 更像 VibeSync"） | **APPROVED with caveat** | 20 題與 8 個維度好。但 "70% feel more VibeSync-specific" 的判斷標準是主觀的——建議 Eric 親自打分對照組（同樣 20 題餵 ChatGPT），不要只靠模型自評。 |

---

## Required Amendments（動 impl plan 前必補）

### A1. 紅線詞契約缺失（HIGH，consistency with Spec 5）

**問題：** §9.4「Do not encourage manipulation」是 prompt 級提醒，沒有 output 級 token blocklist。Spec 5 在 `coach-follow-up/validate.ts` 有 `assertCardSafe`，硬擋 7 詞：`PUA / 收割 / 控住 / 攻略 / 壞女人 / 高分妹 / 玩咖`。OpenAI ≠ Claude，prompt-only guardrail 在新 provider 上強度未知。

**為何必補：**

- VibeSync 的產品紅線詞是**跨 provider 的契約**，不是 Claude-specific。
- Spec 5 走過的 defense-in-depth 教訓（prompts.ts 教 AI 規則 + validate.ts 不信任 AI）必須延用。
- 如果 OpenAI 偶爾洩漏 PUA 詞彙到 suggestedLine，等於整個 Spec 6 信任壓力測試掉到 0。

**建議寫死：**

> Spec 6 Coach 1:1 必須繼承 Spec 5 的 banned-token blocklist（7 詞，未來可擴充）+ post-generation `assertCardSafe`-equivalent。觸發紅線詞 → 不返回卡片、不扣額度、telemetry 標 `errorClass=banned_token`，與 Spec 5 對齊。
>
> 紅線詞清單應抽到 shared module（例如 `supabase/functions/_shared/banned_tokens.ts`），讓 `coach-follow-up` 與 `coach-chat` 共用，避免兩處 drift。

寫進 §4.8（Edge Function structure）+ §9.4（What Not To Do）。

### A4. Response field caps 未訂死（MED，consistency with Spec 5）

**問題：** §4.5 範例給了 schema，但沒寫 byte cap。Spec 5 在 `validate.ts` 有：

```ts
const FIELD_CAPS = {
  headline: 30,
  observation: 80,
  task: 30,
  suggestedLine: 80,
  boundaryReminder: 60,
};
```

OpenAI Structured Outputs 不會主動 cap 字數，會吐長尾。沒有 `truncateCard` → UI 排版炸裂 / 卡片變成小作文 / dogfood 「太囉嗦」訊號汙染。

**建議寫死：** Spec 6 §4.5 補一張 caps 表，建議起點：

```ts
{
  headline: 30,
  answer: 200,
  userState: 100,
  nextStep: 100,
  suggestedLine: 100,
  boundaryReminder: 60,
  reflectionQuestion: 80,
}
```

實作時走 `truncateCard` 而不是 schema reject，避免一個多餘字就 5xx 用戶。

### A7. dataQualityFlagged × partnerHint 行為矛盾（LOW-MED）

**問題：** §4.4 說「flagged = true 時 only rely on current conversation, avoid long-term partner memory」，但 §4.3 範例 payload 在示意 `dataQualityFlagged: false` 的情境，沒有展示 flagged=true 時 `partnerHint` 應如何處理。Spec 3 contract 的精神是「flagged 時 partner traits 不可信」，因此 flagged 應至少 strip `partnerHint.traits`。

**建議寫死：** §4.4 加一條：

> 當 `dataQualityFlagged = true`：
> - `partnerHint.traits` 必須 omit（保留 `partnerHint.name` 給 UI display 即可）。
> - prompt 系統訊息插入「partner 長期資料目前不可信」一句話，避免模型用 name 自己推斷個性。
> - mode 偏向 `clarifyIntent` / `stateCalibration`，避免 `moveForward`。

---

## Daisy-Decision-Needed（產品判斷，CC 不仲裁）

### A2. OpenAI 第三方 provider × ADR #1 隱私揭露（MED-HIGH）

**現況：**

- ADR #1：「對話資料不上雲」——指 VibeSync server / Hive 不存對話。沒禁止呼叫第三方 AI。
- Spec 5 已經把對話 context 送 Claude API，這條紅線早就被解釋為「VibeSync 不長存，但會送 AI 一次性使用」。
- §12.5 對 OpenAI 走同一句話：「只用於本次生成，不會被 VibeSync 後端長期保存」。

**問題：**

- Spec 5 = Anthropic（一個 provider）；Spec 6 = 加入 OpenAI（第二個 provider）。
- 對用戶來說，「資料給誰用」從一個變兩個，揭露語氣需要更新。
- App Store privacy disclosure / 隱私權政策需要新增 OpenAI 為 data processor。
- 7-day retention default（OpenAI Responses API 預設）vs Anthropic 的 retention 政策**不同**——這條 Eric 應該拉合約 / API ZDR 設定確認。

**建議拍板項：**

1. 是否要在 Coach 1:1 首次使用前彈一次性同意 sheet？
2. 隱私權政策 / App Store privacy nutrition label 是否需 v1 上線同步更新？
3. OpenAI ZDR / Zero Data Retention 是否要開（會貴一點，但對「不長存」的口碑承諾更乾淨）？

→ 推薦在 Open Question Q1 / Q8 把這三個拆出獨立子題。

### A5. Sexual Tension Level 2 範例 × App Store 風險（MED）

**現況：** §10.3 Level 2 範例的 partner 訊息直接出現性器官提及（露骨）；reply 候選詞 calibrated 得不錯。

**為何要 Daisy 拍板：**

- VibeSync 的 App Store 評級（17+？）目前我沒查到實際資料；這直接影響 Level 2 是否合適出現在產品行為中。
- 即使 reply 是 calibrated 的，Apple 審核員看到「AI 接得住露骨性暗示」的 demo 可能拒審或要求拉高評級。
- §10.5 prompt line「不要把所有性暗示都消毒成安全提醒」這句話的內部意圖我贊成，但**寫進 prompt 後會不會被外洩**（prompt injection / debug logs）也是風險。

**建議拍板項：**

1. v1 是否限定 Coach 1:1 只回應到 Level 1？Level 2 由產品策略性「策略性 calibrate」（例如「先讓對方再開一次，我教你怎麼接」）而不直接吐 reply？
2. Healthy Sexual Tension policy 的「真張力範例」是否該移出 design doc（變內部訓練資料）而不公開存 repo？避免將來外洩或誤用。
3. App Store 評級當前是什麼？Spec 6 是否需要往上拉？

CC 立場：產品哲學我支持（「成熟是接得住張力，也知道何時退一步」這句寫得好）；落地範圍是 Eric 的判斷。

### A10. Free tier × Coach 1:1 × Level 1/2 的交集風險（MED）

**現況：** §12.2 開放 Coach 1:1 給所有 tier（含 Free）。§10 sexual tension 的 Level 1/2 觸發條件是「partner 主動開」。

**潛在問題：**

- Free tier 用戶含試用、含未驗證年齡的青少年帳號（如有）。
- 「partner 主動開性暗示」這個觸發條件**完全由用戶側截圖控制**——也就是說，用戶可以自編 partner message 來解鎖性張力 mode。
- A2 + A5 + A10 是同一條鏈：第三方 provider 看到的內容、產品上線評級、tier × content 交集。

**建議拍板項：**

1. 是否需要年齡 gating（即使 17+ 也要二次確認）？
2. Free tier 是否限制只到 Level 0（清水）→ 想看 Level 1/2 才付費 upgrade？這個切法既能驗證需求又能規避未付費青少年觸發風險。
3. 是否在 Coach 1:1 的 telemetry 中記錄 sexual_tension_level（不記內容，只記 level）以便產品事後 audit？

CC 立場：產品 vs 風險的取捨是 Eric 的判斷。但**至少**：sexual_tension_level 應進 telemetry（不記文字）。

---

## Recommendations（非 blocking，建議走進 impl plan）

### A3. `gpt-5.5` 模型名驗證（LOW）

§4.9 直接寫 `COACH_CHAT_MODEL=gpt-5.5`。impl 時用 OpenAI 官方文件 / Model API 列表確認當下是否存在；Open Question Q1 已經 flag 這件事，保留 placeholder 即可。

### A6. 6A 卡片位置 vs 6B 重排序的 sequencing（MED）

§4.2 把「問教練一句」card 放進當前**還沒重排序**的分析頁。dogfood 訊號可能是「卡片有用嗎？」與「卡片位置好嗎？」的混合。

**建議：** 6A ship 時帶一個最小排序 tweak——把 Coach 1:1 card 放到「推薦回覆」下方，而非頁尾——讓 dogfood 訊號更乾淨。完整 6B 重排序仍走 Phase 2。

### A8. Mode-correctness dogfood 評分項（LOW）

§4.6 列了 6 個 mode（clarifyIntent / stateCalibration / boundaryRisk / moveForward / replyCraft / stopSignal），但 §13.2 評分維度沒寫「mode 是否選得對」。20 題裡至少 5 題的「正確 mode」是可預判的，例如：

- "她有男友還約我" → 期待 `boundaryRisk`
- "我覺得自己配不上她" → 期待 `stateCalibration`
- "她已讀不回兩天" → 期待 `stopSignal` 或 `clarifyIntent`
- "我想告白但怕嚇到她" → 期待 `stateCalibration`

**建議：** dogfood 表單加一欄「expected_mode」，事前 Eric 自己填，事後對照模型輸出。如果 mode 偏差率 > 30%，prompt 要重 calibrate。

### A9. 成本最佳化文件需更新（LOW）

`docs/cost-optimization.md` 目前以 Claude 為主。impl 時更新並把 OpenAI Coach 1:1 的單次成本放進整體月度估算（Free 30 / Starter 300 / Essential 800）×（假設 30% 用戶會用 Coach 1:1 至少一次）×（input ~1.5k token + output ~600 token）。

### A11. 「OpenAI by default」這個產品決策（NOTE）

§4.9 的「Spec 6A uses OpenAI API by default」其實是 Open Question Q1 的延伸——這是個產品實驗（不同 provider 的 reasoning quality / 中文 dating context 表現）。CC 立場：

- **Pros 寫進 doc：** isolation from Claude / 不同 reasoning trace / cost diversification。
- **Risk 寫進 doc：** Spec 5 prompt-tuning 的累積優勢無法直接遷移；OpenAI Structured Outputs ≠ Anthropic JSON mode 的行為。
- **建議：** impl plan 第一步是**Anthropic vs OpenAI 同 prompt 同 dogfood 對照組**——用實證資料拍板，不要先押 OpenAI。如果 Claude 表現一樣好，留在 Claude（既有的紅線詞、prompt 紀律、Edge Function 模式都能直接複用）。

這條我不擋，但建議 Eric 把「provider 選擇」從 §4.9 的 default 改成 §4.9 的 hypothesis，並在 impl plan 第一步做對照。

---

## 紅線守護一覽（impl plan 不可退讓）

下表是 Spec 6 進 impl plan 後**不可退讓**的紅線，等同 Spec 5 review 中 Codex 立的「Hard boundaries」：

| 項 | 必守 | 來源 |
|---|---|---|
| OCR baseline 隔離 | 不 import `analyze-chat` 任何 helper（OCR / parser / `buildAnalysisPrompt` / `PartnerContextResolver`） | CLAUDE.md OCR Stable Baseline |
| 圖片拒絕 | `images` field → `400 invalid_input_for_mode` | Spec 5 §4.4 |
| Cost invariant | 沒成功 deductCredit 不返回成功 card；deductCredit 必檢查 Supabase `{ error }` | Spec 5 P1 patch（commit `0ba500d`） |
| Banned tokens | 7 詞 blocklist + post-gen `assertCardSafe`；觸發 → 不扣額度 | A1 amendment |
| Field caps | `truncateCard` 在 `assertCardSafe` 之前跑 | A4 amendment |
| Telemetry no-content | 不 log `userQuestion` / prompt / raw response / partner messages / `suggestedLine` | §12.4（已寫對） |
| Local-only persistence | Coach 1:1 結果只存 Hive，不寫 partner traits / About Me / long-term memory | §4.11（已寫對） |
| dataQualityFlagged | flagged=true 時 strip `partnerHint.traits` + prompt 注入「partner 長期資料不可信」 | A7 amendment |
| Edge Function 部署 | `coach-chat` 走 JWT 驗證；不混進 `analyze-chat` 的 `--no-verify-jwt` workflow | Spec 5 review precedent |

---

## Overall Verdict

**APPROVED-WITH-AMENDMENTS**

**前置必補（在 impl plan 之前更新 design doc）：**

1. A1 — Banned-token contract（§4.8 + §9.4）
2. A4 — Response field caps（§4.5）
3. A7 — dataQualityFlagged × partnerHint 行為（§4.4）

**Daisy-Decision-Needed（產品 / 風險拍板，CC 不仲裁）：**

- A2 — OpenAI 第三方 provider 隱私揭露 / 同意流程 / ZDR 取捨
- A5 — Sexual Tension Level 2 範例 × App Store 評級
- A10 — Free tier × Coach 1:1 × sexual content 交集

**Recommendations（impl plan 進去處理）：**

- A3 / A6 / A8 / A9 / A11

**不擋但要 Eric 自驗：** §13 dogfood 是否親自跑「同 20 題餵 ChatGPT」對照組——這直接決定「比 ChatGPT 更像 VibeSync」這句話有沒有被驗證，而不只是模型自我感覺良好。

**下一步建議：**

1. Eric 拍板 A2 / A5 / A10 三項。
2. 用 amendment 更新 design doc（A1 / A4 / A7 必補）。
3. 找 Codex 做 plan-level 獨立 review（與 Claude 並行 / cross-check echo chamber 的關鍵環節）。
4. impl plan 第一步：Claude vs OpenAI 同 prompt dogfood 對照——用實證資料拍板 provider。
5. 不寫 production code，直到 Eric 與 Bruce 同意 design 方向。

---

**Reviewer-Hint:** A2 / A5 / A10 三項屬產品方向題，CC 立場已寫，但用戶直覺優先。其餘 A1 / A4 / A7 屬於從 Spec 5 學到的紀律延用，不應放掉。

**Next-Step:** 等 Eric 在 design doc 直接 commit amendment，或回 brief 討論 Daisy-Decision-Needed 三題。CC 不另寫 impl plan，不改 production code。
