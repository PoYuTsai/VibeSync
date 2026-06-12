# Gate 3 體系感雙向目檢表（刀4，2026-06-12）

> 給 Eric＋Bruce。不盲、不比 GPT。兩題各看兩個問題：
> **①看得到體系嗎**——出招局技巧名自然出現、標注內行不尬
> **②會不會硬出招**——平聊局讀起來像正常聊天、不硬貼標籤、不為體系感每句套技巧
>
> 來源：刀3 新 prompt（`057568f`）prod 實跑，原始檔 `baselines/gate4_golden_anchor_run1.ndjson`、`baselines/gate4_min_smoke_run1.ndjson`。

---

## Case A：golden anchor（糖糖，熟絡局＝出招局，重點看①）

**主推薦 pick=coldRead**（與定稿一致）
> msg：到家就好🫶／不過剛那通電話，害我有點好奇到底想跟我說什麼。
> reason：她主動打視訊是最高價值的升溫訊號，**懸念鉤**接住這顆球比流水帳回覆更有吸引力

| 槽 | message（用戶可見句） | reason 標注 |
|----|----|----|
| coldRead | 到家就好🫶／不過剛那通電話，害我有點好奇到底想跟我說什麼。 | **懸念鉤**：半開放的好奇讓她主動投入 |
| extend | 那家茄汁牛肉飯下次直接帶我去，不要只傳照片來折磨我。 | **合作框架**＋**模糊邀約**不綁時間，她不用答應任何事 |
| tease | 今天還特地打給我，是不是糖糖老師的待遇升級了？ | **callback 糖糖老師梗＋輕推拉** |
| resonate | 今天從比賽一路衝到晚上，這電量我真的佩服🫶… | （無標注＝接情緒平聊，與範例 1 設計一致） |
| humor | 妳今天這行程根本熱血女主角，我最大的運動是走去倒垃圾… | 自嘲反差＋**懸念鉤** |

機檢已過：messages 零夾技巧名、黑名單 18 詞零出現、失格零觸發（熱局本不該觸發）、糖糖 callback 重現、五槽契約 PASS。

**目檢問題 A**：reason 欄的技巧名標注讀起來「內行」還是「尬」？tease 的「輕推拉」標注 OK 嗎（見披露點②）？

## Case B：小雲首晚（陌生冷局 held-out smoke＝平聊局，重點看②）

**主推薦 pick=extend**
> msg：對啊那張在清邁，你們那邊最有名的就是老虎園哈哈／那妳現在在台灣哪個城市？來多久了？
> reason：她問老虎照是主動投入訊號，接住這顆球再順勢問她在台灣的狀況（無技巧名標注）

| 槽 | message | reason 標注 |
|----|----|----|
| extend | …那妳現在在台灣哪個城市？來多久了？ | 無標注（順勢延伸） |
| resonate | 被妳發現了哈哈，對就是清邁… | 無標注（接驚喜感） |
| tease | 妳眼睛很尖欸…泰國人跑來台灣，台灣人跑去泰國哈哈 | **輕鬆推拉** |
| humor | 對！結果妳才是正港泰國人，我只是觀光客… | 自嘲式幽默（非表內詞） |
| coldRead | 我猜妳來台灣不只是純觀光，是有在唸書或工作？ | 溫和猜測（非表內詞） |

機檢已過：不 pushy（零邀約推進）、不裝熟、黑名單/失格零、五槽契約 PASS。冷局 5 槽僅 1 處表內標注＝技巧密度原則（時機性不密度性）有守住。

**⚠️ 一處內部張力（如實披露）**：coach_hint 教「一個問題，不要連問」，但 extend 主推薦自己連問兩題（哪個城市？＋來多久？）。輕微、單次取樣，目檢判要不要管。

**目檢問題 B**：冷局讀起來像正常聊天嗎？有沒有為了體系感硬出招的痕跡？

---

## 三個披露點（✅ Eric 2026-06-12「照你建議」裁決：①維持不補回 ②推拉解禁維持 ③範圍明示 analyze-chat SYSTEM_PROMPT only＋opener 案加全 prompt 常數 blocking 掃描——零 code 變更）

1. **§6 反例出處括號未抄進 prompt**：設計檔 §6 有 8/9 反例帶內部出處（round1 case2 教訓等），進 prompt 時去掉了——對模型是噪音。維持現狀 or 要補回？（建議維持）
2. **「推拉」從黑名單解禁**：舊禁詞表有「推拉」，但 §5 定稿 tease 槽明寫「角色反轉式輕推拉」可見標注，衝突→刀3 把它從黑名單拿掉。本輪兩條 anchor 的 tease reason 都real出現「輕推拉／輕鬆推拉」標注。接受解禁 or 要改回（改回則 §5 定稿 tease 標注要重寫）？

3. **Codex adversarial 1 high＝OPENER_PROMPT 殘留**（job review-mqb5avrp-zu3vsw，session 019ebcae-5161-7040-b872-47f5dc462cee）：同檔 `index.ts:2148-2358` 的 `OPENER_PROMPT` 仍含「玩咖」「PUA」等第 2-3 層詞，刀3 測試刻意只切 SYSTEM_PROMPT。**與既有拍板一致**（opener Game 化＝下一案，設計檔 §4 不碰 opener），Codex 不知情故報 high。處置選項：(a) 照原拍板＝本案範圍明示「analyze-chat SYSTEM_PROMPT only」，opener 案開工時加「掃全部 production prompt 常數」的 blocking 測試（Codex 建議 B，推薦）；(b) 改判提前清 OPENER_PROMPT（擴刀，需重跑四關）。

---

## 四關狀態（2026-06-12 終局）

1. 契約測試：✅ Deno 636 綠 / 0 failed
2. anchor 復測：✅ 兩條 PASS（五槽零 error、黑名單/失格零、messages 零夾名、糖糖 callback 重現、冷局不 pushy 不裝熟）
3. 體系感雙向目檢：⏳ 本表，等 Eric＋Bruce
4. Codex 雙審：review ✅ 0 findings；adversarial ⚠️ needs-attention 1 high＝披露點 3（已拍板範圍切割，非新缺陷）

**現狀＝未 dogfood safe**：等關 3 目檢＋Eric 對三披露點裁決。
