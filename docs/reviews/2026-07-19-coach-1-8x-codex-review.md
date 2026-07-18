# Coach 1.8x 投入對等改寫 — Codex Review

日期：2026-07-19

範圍：`coach-chat` suggestedLine prompt、生成後 grounding guard、local Sonnet quality smoke
結論：**APPROVE FOR COMMIT；未部署，不能據此宣稱 production 已更新。**

## Review findings

1. 原 prompt 的「字數不要超過對方最後一句約 1.8 倍」同時把 1.8x 寫成上限、把錨點縮成末句，與投入對等的原意相反。已改成看整輪、1.8x 只作參考，高手感由選球準、自然、有畫面、有張力與低壓決定。
2. 真實 Sonnet smoke 證實只改字串仍不夠：模型曾把「這週」寫成「這陣子」、把「還好啦哈哈」轉成索取解釋的問句，或腦補「很會裝」。這些句子可能短且順，仍不準。
3. 可客觀判定的三類錯誤已接進既有最多三次的 validation retry：來源沒有的時間範圍、來源沒有的負面動機標籤、以及使用者明確要求不要追問時仍輸出問句。guard 只拒絕卡片，不改寫內容；合法卡才會扣額度。
4. 額外 retry 會增加模型成本與延遲。範圍已刻意限窄；若三次都不通過，沿用保守 no-charge fallback。單元測試鎖定 `costDeducted=0` 且不呼叫扣費。

## Evidence

- `coach-chat` 完整 Deno suite：87 passed／0 failed。
- 修改檔 `deno fmt --check`、`generation.ts` 與 local smoke runner 的 `deno check` 通過。
- 調整期共 39 個本機真實 Sonnet 5 合成樣本，皆為 test-account 模式、不連 DB、不扣 quota。
- 最終固定 corpus 9/9：整輪末句 ack、低投入、明確長訊息各 3 次。
  - 整輪：都有接到提案／陶藝高價值球，沒有只跟最後的「哈哈」。
  - 低投入：4–12 字，無追問、安撫索取或負面動機標籤。
  - 明確長訊息：65–70 字，沒有因 1.8x 被硬砍，時間詞維持來源的「這週」或省略。
- 最新帶 attempts 的 3 樣本為 `1／2／1`；低投入首抽違反明確 no-question 要求後，第二抽通過。這證明 guard 有效，也保留額外模型呼叫的成本證據。
- 終掃不再含「1.8x 黃金法則」「最後一句約 1.8 倍」「字數不要超過對方」等舊公式；正向與負向斷言均已加入。

## Boundary

- 沒有部署 `coach-chat`，也沒有修改 quota、訂閱、模型路由或 DB。
- 沒有引入關係溫度／冷熱／升溫放寬概念。
- lexical grounding guard 只覆蓋 smoke 實際抓到、可明確判定的窄詞組；它不是完整事實驗證器，其他模型變異仍需持續用評測觀察。
- `analyze-chat` 已由前一個獨立 commit 處理；client `_userOverextendedReply` 與 Practice 1.8 評分係數未修改。
