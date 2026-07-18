# Analyze 1.8x 投入對等改寫 — Codex Review

日期：2026-07-19

範圍：`analyze-chat` quick／full／stream prompt、ball inventory、local quality smoke
結論：**APPROVE FOR COMMIT WITH KNOWN MODEL-VARIANCE RISK；未部署，不能據此宣稱 production 已更新或五風格 dogfood 品質全面安全。**

## Review findings

1. 原提案把 1.8x 從硬上限改為整輪參考是正確方向，但漏了 active stream adapter。它把 `接` 與 `併` 都算進 `min(3, ...)` segment floor，還要求 selected style 不得比其他風格短；因此「併」名義上合併，實際上會強迫多一段。這是阻擋高手感的 P1 行為根因。
2. full prompt 另以「連發 4 句」推定「通常 ≥3 段」，仍是訊息數公式。已改成先做語意分群，段數只跟彼此獨立、略過會像沒聽到的 `接` 球走。
3. 現行 Flutter 路徑的 `_shouldUseStreamingFull => true`，所以 active UX 直接走 stream；quick／full 分支只為 rollback 相容保留。quick 的 1–2 顆選球修正是防 rollback 回退，不是現行首屏證據。沒有引入關係冷熱／升溫放寬概念。
4. 多輪 live smoke 另抓到合併時補故事、時間線漂移、低投入 tease 索取安撫、偶發簡體等高手感缺口。已把可泛化規則與 strict runner 補上；但非 selected 備選仍有模型變異，prompt-only 不能保證每輪五個選項全 clean。

## Evidence

- `analyze-chat` Deno full suite：645 passed／0 failed。
- `deno check`：`index.ts`、quick／stream prompt、ball inventory、local smoke runner／proxy 全過。
- 調整期 local Sonnet 5 真實呼叫覆蓋 quick rollback 與 active stream；quick 不列入現行 UX 安全證據。
- 最終固定 active-stream corpus 6 輪：整輪／同事件／低投入各 2 輪。
  - 1.8x／整輪選球／段數／低壓形狀：6/6。
  - 依最終自動 gate 回溯：5/6；一個非 selected 選項捏造「我家那隻」。
  - 人工高手感 clean：4/6；另有一個非 selected 選項把工作專案誤寫成「課業」。
- 每輪皆為測試帳號、`messagesUsed=0`、五風格與 `analysis.done` 完整。runner 會掃 selected 與所有備選的規則洩漏、乾巴巴附和、壓力語氣、時間漂移、未提供背景、常見簡體與 `�` 壞字。
- 終掃已移除 analyze runtime 裡的「上限／限制內／最後一則 1.8 倍」措辭；reason 禁止洩漏公式的既有規則保留。

## Boundary

- 沒有部署 Edge Function；部署仍需另行確認，且 `analyze-chat` 必須使用 `--no-verify-jwt`。
- `coach-chat` 同型措辭由第二個獨立 commit 處理。
- client `_userOverextendedReply` 單訊息數值檢查、Practice 評分係數、OCR 路徑均未修改。
- 非 selected 備選的偶發誤詞／補故事需要獨立品質策略（評測、重排或正規化），本次不以繼續堆 1.8x prompt 掩蓋。
