# 給 Eric／夥伴／CC：公式開場修正版白話 handoff

> 完整施工規格：
> `docs/plans/2026-07-24-opener-formula-replies-implementation-plan.md`  
> 本文件是白話摘要；若兩者有落差，以完整規格為準。

## 一句話

這案可以做，而且維持「同一次 AI 呼叫、多兩則、Free／Paid 都能看」。

但要把它做成真正不拖累舊功能，不能只在 prompt 和畫面多塞一個欄位。
New Topic 有正式的 24 小時重播帳本；公式結果也必須一起安全存進去，否則
第一次看得到、重試卻消失，甚至會被資料庫直接拒絕。

Codex 已把這個缺口與其餘模糊處補成可施工規格，CC 不需要再猜產品決策。

## 我們到底要加什麼

Opener 原本五種開場完全保留，下面額外多一區「公式開場」。

New Topic 原本五個方向、Free 先看一個／Paid 看五個完全保留，下面額外多一區
「公式新話題」。

公式不是固定罐頭文案，而是固定三段結構：

1. 抓她一個具體線索。
2. 放一點我的當下反應或感受。
3. 留一個她很容易接的開口。

有真的共同點才聊「我們」；沒有證據不能硬說「我也」。

每則會顯示：

- 可直接傳出去的訊息。
- 一句「為什麼好接」的教練註解。

兩種方案、所有 tier 都能看到，沒有鎖。

## 「不影響原來回覆」的正確意思

我們能保證的是：

- 原本五種 opener／五個 topics 的數量與完整性 gate 不變。
- 公式壞掉，只是不顯示公式；原結果仍正常成功。
- 不因公式壞掉多打一個 repair call。
- 不改 tier、quota、推薦、access 或扣費。
- 舊 App、舊 cache、舊 replay 都能安全讀。

我們不能說原五則文字會和改 prompt 前逐字一樣。因為它仍是同一次 AI 呼叫，
多一項任務就可能讓模型措辭略有變化。

所以這案的保證是「工程契約完全隔離」，不是「AI 文字逐字凍結」。

更精確地說：如果整份 AI JSON 可以解析，只是 formula 欄位內容壞掉，原結果
一定繼續成功。若模型在公式字串裡吐出沒 escape 的引號／換行，害整份 JSON
都無法解析，server 無法知道是哪個欄位闖禍，會照原本規則 repair；repair
仍失敗就 502、不扣費。

## 為什麼一定有一個 migration

New Topic 現在會把成功結果存 24 小時，確保斷線重試不雙扣，而且 replay 回同
一份內容。

正式資料庫目前只允許：

- topics
- recommendation
- access

三個欄位。

直接加 formulaTopics 會讓結算失敗；如果不存，又會讓 replay 時公式消失。

因此要新增一個向後相容 migration：

- 舊三欄資料繼續合法。
- 新資料可以多 formulaTopics。
- 公式最多兩則，每則只准 openingLine＋whyItWorks。
- 原本 quota、transaction、RLS、cron 全不動。

這不是擴大 scope，而是保持 New Topic 恰一次扣費與 replay 正確的必要工程。

Opener 不走這個 DB ledger；它只沿用目前 App 本機的 draft/cache JSON，所以
Opener 不需要資料庫 migration。

## 公式壞掉時怎麼處理

Server 只收 0–2 則合法公式：

- 少一欄、超長、空字、JSON 洩漏：丟那一則。
- 兩則重複：只留第一則。
- 和原本 opener/topic 完全重複：丟公式，原內容不動。
- 出現「最近熱度、累計對話、你的備註、作戰板」等內部標籤：丟公式。
- 全壞就回空陣列。

公式壞掉絕不觸發 repair，也不能把 raw AI 內容直接傳到 App。

原五則自己不完整時，才照既有規則 repair。

## 作戰板隱私怎麼守

作戰板可以幫 AI 找線索，但訊息不能讓女生知道系統記了什麼。

禁止把這些字眼或意思直接講出去：

- 對象作戰板
- 對方作戰板
- 最近熱度
- 累計對話
- 你的備註／過往備註
- 性格分析
- 系統判斷

能用的是安全的生活線索，例如她確實喜歡咖啡、爬山或某部作品；不能說
「系統判斷妳最近變冷」。

## Token 與成本

初版不提高 3000 token 上限。

公式正常目標是：

- 訊息約 45–80 字。
- 教練註解約 60–100 字。

現有輸出還有空間。先記錄 formula 成功數、output tokens、stop reason、
repair rate 與 latency；真的看到截斷證據，再另案決定要不要升到 3600。

扣費仍是 3 點，不因公式只成功 0／1／2 則而變。

供應商實際 input/output token 成本一定會小幅增加；這會被量測，但不改使用者
看到的 quota、tier 或 3 點扣費。

## App 會長什麼樣子

Opener：

- 原五風格區與「N 種風格」文案完全不動。
- 公式區放在原卡片、回報 bar、推薦理由之後。
- 不把公式算進 N。

New Topic：

- 原 topics 先顯示。
- 接著顯示公式新話題。
- Free 的「還有四個」升級 CTA 放在公式後面，避免看起來像公式被鎖。

公式卡用自適應高度，顯示訊息＋為什麼好接；複製只複製可傳訊息。

## 給 CC 的直接任務

請完整讀：

`docs/plans/2026-07-24-opener-formula-replies-implementation-plan.md`

然後依序做：

1. 記錄 BASE_SHA、檢查 dirty worktree，不碰 Eric 既有變更。
2. 先做 New Topic ledger 相容 migration＋TS validator。
3. 再做共用 formula normalizer、兩個 prompt 與 backend wiring。
4. 再做 Flutter parsing/cache。
5. 最後做兩個 UI 區塊與 widget tests。
6. 跑 targeted＋full Deno／Flutter／analyze。
7. 準備 PostgreSQL legacy/new shape smoke。
8. 逐 concern commit，提供 exact range。
9. 實作完成後跑 opposite-frontier＋GLM 兩路只讀 challenge review並 reconciliation。
10. Review 未 APPROVED 前停下；不得 migration、deploy 或宣稱 dogfood safe。

本 handoff 沒有授權 production deployment，也沒有授權改 quota、tier、原 prompt
五風格內容或 token cap。

## CC 最容易踩的五個坑

1. 不要修改已部署的舊 migration；一定新增 additive migration。
2. 不要把 formulaTopics 只加在 fresh response；它必須進 ledger 才能 replay。
3. 不要讓 opener 的 `...parsed` 把 raw formulaOpeners 漏到 App。
4. 不要因公式壞掉觸發 repair 或讓原五則失敗。
   - 這句只指「整份 JSON 可解析、formula 欄位獨立不合格」。
   - 整份 JSON 語法壞掉仍走既有 base repair。
5. 不要回滾到讀不懂新四-key ledger row 的舊 Edge；要保留 compatibility ref。

## Eric／夥伴現在不需要再決定的事

以下已由 Codex 收斂：

- 公式是固定結構、內容動態生成。
- 使用同一次 AI call。
- 全 tier 可見。
- Formula bad → 空陣列，base 繼續成功。
- Token 先維持 3000。
- New Topic 用 additive migration 擴充 ledger。
- Opener 不 bump contractVersion。
- 公式不加入原推薦與原數量。
- 公式卡暫不接 outcome/reaction bar。

下一個需要 Eric 明示的 consequential action 只有：

- 是否允許 push（若本次交辦沒有明說）。
- 雙 review APPROVED 後，是否允許 migration／Edge deploy／TestFlight。

## 完成的標準

不是「畫面看得到兩張卡」就完成。

真正完成要同時證明：

- Formula 0／1／2 都不拖垮原結果。
- Free／Paid 原 access/counts 完全不變。
- New Topic fresh/replay 同 formula。
- Legacy row／舊 cache／舊 App 相容。
- Raw formula 與作戰板內部標籤不外露。
- 原五則 repair／quota／扣費路徑維持。
- 全測試綠。
- Codex/Claude peer＋GLM challenge 都完成並由 primary reconciliation。

做到這裡，才可以回 Eric「implemented and review-approved」；部署與 dogfood
仍是下一個明示授權階段。
