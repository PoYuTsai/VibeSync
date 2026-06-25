# AI 實戰練習室 20 則續玩與約出來目標設計

Date: 2026-06-25
Status: Draft for Eric review
Scope: practice-chat Flutter client + Supabase Edge Function prompt/ledger contract

## Context

AI 實戰練習室目前一場扣 1 則額度，最多 10 則 AI 回覆。Dogfood 之後體感是：10 則可以驗證「模擬真人聊天」成立，但常常還不到真正的產品目標：讓使用者練到可以自然約出來。

Eric 與夥伴的新方向：

- 一次扣 1 則額度，給 20 則 AI 回覆。
- 20 則跑完後，可以續玩，再扣 1 則，再給 20 則。
- 續玩預設延續同一位女生、同一難度與同一段互動脈絡，因為目標是練到約出來，不是重開一局。
- 只有使用者在輪與輪之間明確換人或改難度，下一輪才改變對象感。
- 換一位時，除了 persona 變化，也要有女生英文名，增加「真的換對象」的感覺。
- Debrief 要加入「約出來機會」與下一步邀約建議。

## Product Goal

讓使用者在一個低壓但接近實戰的環境，練習從開場、接話、升溫，到自然邀約。系統不保證每場都能約出來；AI 依使用者實際打字品質反應。

高手可能第一輪 20 則內就約出來。中手可能第一輪建立舒適感、第二輪才有機會邀約。新手可能兩輪都還不行，debrief 要指出差在哪裡，而不是硬把女生推向成功。

## Non-Goals

- 不做遊戲化分數條或明確任務樹。
- 不保證 AI 一定接受邀約。
- 不把 debrief 做成長篇課程。
- 不新增 Supabase DB migration，除非 implementation review 證明無法安全延用現有 ledger。
- 不改全站 subscription plan 額度。
- 不讓 client 傳 free-form name/persona/prompt。

## Core Rules

### Practice Round

「一輪」是 billing 單位：

- 每輪扣 1 則額度。
- 每輪最多 20 則 AI 回覆。
- DeepSeek 失敗不扣。
- 一輪內重送或續聊不重複扣。
- 到 20 則後，使用者可以看拆解或續玩下一輪。

### Continue Play

續玩不是新女生，不是清空聊天。

直接點 `續玩 20 則` 的行為：

- 保留同一個 visible practice thread。
- 保留同一個 persona、女生英文名、difficulty。
- 保留全部聊天脈絡，讓 AI 知道前面互動。
- 建立下一輪 billing identity，再扣 1 則額度。
- 新一輪再給 20 則 AI 回覆。

輪與輪之間可以提供明確控制，但不能偷偷改：

- `續玩 20 則`：同一位、同一難度。
- `換一位再玩`：換英文名 + persona，保留難度，建立新的對象感。
- 難度 chip：只改下一輪 difficulty，保留同一位女生。
- 若使用者換人，下一輪仍可保留歷史作為「上一位已結束」的 local record，但 prompt 不應把前一位女生的聊天內容當成新女生自己的記憶。MVP 建議換人時開新的 visible thread，避免身份混線。

安全建議：不要改現有 server ledger 的「一個 session 只扣一次」安全模型。改用 client local thread 對應多個 server billing session ids：

```text
visiblePracticeThreadId = local UI / Hive 顯示用
billingSessionId round 1 = server ledger A, 扣 1, AI 1-20
billingSessionId round 2 = server ledger B, 扣 1, AI 21-40
```

這樣可以避免 prod DB migration，也能保留既有 server-side ledger 的 atomic 扣費與上限保護。

### Session Cap

MVP 不需要無限玩。建議先限制最多 3 輪：

- 最多 60 則 AI 回覆。
- 第 3 輪結束後只顯示「看教練拆解」。
- 如果未來 dogfood 證明需要更長，再調整。

理由：成本可控、UI 可控、debrief 不會被超長逐字稿拖爆。

## UX

### New Room

開場顯示：

```text
本場對象：Ivy · 慢熱上班族 · 一般
```

開聊前顯示：

- `換一位`
- `輕鬆 / 一般 / 挑戰 / 隨機`

`換一位`：

- 換英文名。
- 換 persona。
- 保留目前難度。
- 不要抽到同一個英文名。

難度 chip：

- 只換難度。
- 保留同一位女生。

第一則送出後：

- `換一位` 與難度 chips 鎖定。
- 顯示同一組 `英文名 · persona · difficulty`。

### During A Round

底部額度文案改為：

```text
首次 AI 回覆成功扣 1 則，本輪可聊 20 則
```

扣過後：

```text
本輪已扣 1 則，還能聊 17 則
```

### Round Complete

到 20 則 AI 回覆後，輸入鎖定，底部顯示：

```text
這輪已聊滿 20 則
```

主按鈕：

```text
續玩 20 則
```

副按鈕：

```text
看教練拆解
```

輪與輪之間仍可顯示較輕量的設定列：

- `換一位再玩`
- `輕鬆 / 一般 / 挑戰 / 隨機`

但這些是「下一輪設定」，不是偷偷套用到已完成的上一輪。

若 quota 不足，點 `續玩 20 則` 顯示既有 quota/paywall path，不丟失聊天。

### Debrief

Debrief 可在任一輪後手動進入，也可在最後一輪滿後進入。Debrief 分析整個 visible thread，不只最後一輪。

## English Name Model

新增 server/client 共同 allowlist name catalog。Client 只送 `nameId`，server 用 allowlist 解析 display name。

建議 MVP name pool：

```text
ivy, zoe, mia, chloe, emma, ava, nina, bella, lily, ella, yuna, rina
```

Display names：

```text
Ivy, Zoe, Mia, Chloe, Emma, Ava, Nina, Bella, Lily, Ella, Yuna, Rina
```

Rules：

- `nameId` 是 request metadata，和 `personaId/difficulty` 一樣由 Edge validate。
- 舊 client missing `nameId` fallback `ivy`。
- Prompt 中告訴 AI：如果被問名字，可以自然回答 display name。
- AI 不要主動自介。
- `換一位` 必須避免同 nameId；persona 也盡量避免同 persona，但 nameId 變化優先。

## Date Goal Model

### Chat Prompt Behavior

Prompt 要加入「有機會約出來」的真實反應規則：

- 如果使用者自然、有生活感、接得住情緒、能低壓邀約，AI 可以逐漸變熱，甚至接受或半接受邀約。
- 如果使用者太急、太油、查戶口、硬約、無視女生反應，AI 要冷掉、迴避、吐槽或拒絕。
- AI 不知道自己在被訓練，也不幫使用者達成任務。
- 不把「約出來」當必然終點，而是互動品質自然導出的結果。

### Debrief Evaluation

Debrief 要新增：

```json
{
  "dateChance": "low | medium | high",
  "dateChanceReason": "一句話說明目前為什麼有/沒有機會約出來",
  "nextInviteMove": "下一步可以怎麼約，或如果不適合約，要先補什麼"
}
```

繁中 UI 顯示：

```text
約出來機會：低 / 中 / 高
原因：...
下一步：...
```

判斷原則：

- 高：女生明顯接梗、願意延伸、接受具體場景或釋出時間/興趣訊號。
- 中：聊天有舒適感，但邀約鋪墊不足，或女生還在觀察。
- 低：冷、敷衍、查戶口感、太急、太油、沒有共同場景。

重要：高手第一輪可以高；中手第一輪中、第二輪高；新手可能低。模型必須看逐字稿，不用固定輪數推斷。

## Data Contract

### Flutter Local Thread

`PracticeSession` 建議新增 optional fields：

- `displayName`
- `nameId`
- `roundIndex`
- `roundAiReplyCount`
- `totalAiReplyCount`
- `billingSessionIds`
- `maxRounds`

如果 implementation 想降低 Hive adapter 風險，可先用：

- `sessionId` 保留 visible thread id。
- 新增 `currentBillingSessionId`。
- `messages.length/aiReplyCount` 保留總數。
- `roundAiReplyCount = aiReplyCount % 20` 需小心滿 20 時是 20，不是 0。

推薦仍明確存 `roundAiReplyCount`，避免 modulo 邊界錯誤。

### API Request

Chat / debrief request 加：

```json
{
  "nameId": "ivy",
  "personaId": "slow_worker",
  "difficulty": "normal"
}
```

Chat request 的 `sessionId` 使用 current billing session id，不是 visible thread id。Debrief 若沿用現有 server gate，需要用已扣費且有 AI 的 billing session id；但 debrief prompt 的 transcript 仍傳整個 visible thread。

## Cost And Quota

目前 practice 一輪仍視為 Coach 額度 1 則。

文案必須清楚：

- 開始前：首次 AI 回覆成功才扣 1 則。
- 續玩前：續玩會再扣 1 則，給 20 則。
- quota 不足：不新增 billing session、不清聊天、不改 local state。

Failure invariants：

- DeepSeek 失敗不扣。
- 續玩 quota 429 不清聊天。
- 續玩成功後才進入下一輪可輸入狀態。
- 不能讓使用者用 client 少報 turns 繞過 20 則。
- 不能讓使用者用同一 billing session 重複取得多輪 20 則。

## Implementation Shape

### Edge

- `MAX_AI_REPLIES` 從 10 改 20。
- `validate.ts` accept optional `nameId`。
- 新增/擴充 profile allowlist：name catalog + persona + difficulty。
- Prompt 帶入 display name 與 date-goal behavior。
- Debrief JSON schema 增加 date chance fields。
- Existing old clients fallback `ivy + slow_worker + normal`。

### Flutter

- `kMaxPracticeAiReplies` 從 10 改 20。
- UI copy 改成本輪 20 則。
- `換一位` 同時換 name/persona，難度不變。
- state/Hive 持久化 name 與 round fields。
- 到 20 則後顯示續玩/拆解，而不是直接只剩拆解。
- `continuePracticeRound()`：
  - quota preflight 仍由 Edge 實際決定。
  - client 先建立新 currentBillingSessionId。
  - 第一則下一輪 AI 成功後才持久化新 round charged state。
  - 若失敗，保留原 round complete state。
- `changePersonaForNextRound()`：
  - 只在 round complete 且下一輪尚未開始時可用。
  - 建議開新的 visible thread，避免不同女生共用同一段逐字稿造成 prompt 身份混線。
- `setDifficultyForNextRound()`：
  - 只影響下一輪。
  - 不換英文名、不換 persona。

### Tests

Edge:

- 20 則 cap tests。
- old client fallback name/persona/difficulty。
- invalid nameId rejects.
- prompt contains display name but does not force self-introduction.
- debrief schema parses dateChance/dateChanceReason/nextInviteMove.

Flutter:

- new room shows `Name · persona · difficulty`。
- 換一位 changes name and persona, keeps difficulty.
- 20 replies reaches roundComplete.
- roundComplete shows `續玩 20 則` and `看教練拆解`。
- direct continue starts next billingSessionId, resets round count, keeps same name/persona/difficulty.
- changing difficulty before continue affects only the next round and keeps the same name/persona.
- changing persona before continue starts a new visible thread or otherwise prevents previous girl's transcript from being treated as the new girl's memory.
- quota failure on continue does not clear messages.
- debrief includes full visible transcript.
- old Hive sessions fallback safely.

## Rollout

This is high-risk because it touches quota/cost, Edge schema, AI prompt, and Hive local persistence.

Required closeout before dogfood-safe:

1. Deno practice-chat tests.
2. Flutter practice-chat unit/widget tests.
3. Full `flutter analyze`.
4. Confirm no Supabase migration unless explicitly approved.
5. Codex review on full implementation range.
6. Edge deploy success.
7. iOS/TestFlight rebuild.
8. Real-device smoke:
   - first round 20 cap
   - continue charges again
   - same girl/name continues
   - debrief date chance appears
   - quota failure path does not lose chat
