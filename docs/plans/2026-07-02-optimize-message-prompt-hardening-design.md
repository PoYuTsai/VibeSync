# 草稿潤飾器 prompt 補強設計（2026-07-02）

## 背景

2026-06-05 `9928dd63` 因「草稿潤飾跑不出結果」bug，把 optimize_message 從完整 `SYSTEM_PROMPT` 切到瘦版 `OPTIMIZE_MESSAGE_PROMPT`（窄 JSON＋700 token budget）。可靠性修復正確，必須保留；但長版累積的品質規則未同步蒸餾過去。

調研結論（詳見 2026-07-02 調研）：契約塊 `User Draft To Optimize`（index.ts）已涵蓋大半精華（light edit、不換人設、emoji 0-1、慾望降壓），且為純文字與帶圖兩條路徑共用。真正缺口四項：

1. 1.8x 長度法則——瘦版無長度指引，且 style context 收尾句引用「the 1.8x rule」但瘦版從未定義（現存自相矛盾）
2. reason 欄位規則（禁提字數公式）——補 1.8x 的必要配套
3. 自貶改自嘲
4. Partner context 使用指引——長版也只被動塞 `## Partner Context` 段，兩路徑都沒教模型怎麼用

## 拍板（Eric 2026-07-02）

- 開工，範圍＝優化點 1+2 合併小案
- 落點＝方案 C 混合
- 瘦版架構不動、路由不動（quota_usage.ts `deriveRequestType` 不碰）
- AI prompt 高風險區：commit 留 local，Codex 雙審 APPROVED 後才 push（push 即 auto-deploy prod）

## 變更設計

### 1. 共用契約塊（index.ts `User Draft To Optimize`）

加一條 partner context 使用指引（英文，跟隨既有契約塊語言），兩路徑同吃：

- 用 Partner Context / User Voice 挑選她可能有反應的用詞與話題角度
- 絕不捏造 context 沒有的她或使用者的事實

### 2. 瘦版 `OPTIMIZE_MESSAGE_PROMPT`（index.ts）

補四條（繁中，跟隨既有瘦版語言）：

- 1.8x 簡版：以對方最近訊息長度為基準，優化後約不超過 1.8 倍；寧短勿長
- 自貶改自嘲
- reason 欄位禁提 1.8x／字數計算／公式，用自然描述
- 潛水 few-shot 一組（「感覺你潛水很厲害」→ 加互動性版本；不可只輸出同義短句）

### 3. 測試（index_test.ts）

跟隨既有 source-includes 字串鎖慣例（見 `draft polish uses a narrow prompt and token budget`）：

- 新增測試鎖新規則關鍵字串（1.8x、自嘲、reason 禁令、few-shot、partner 指引）
- 既有兩顆潤飾守門測試必須續綠

## 不做（YAGNI）

- 不動路由／不合併兩條路徑（瘦版是可靠性修復）
- 優化點 3（userStyle 雙軌冗餘）、4（telemetry）另案
- 不加串流、不入 analysis_stream_runs

## 驗證與門控

1. TDD：先紅後綠，`deno test` index_test.ts＋`deno fmt --check`
2. commit local 不 push
3. 出 Codex review packet（AI prompt 高風險），Eric 路由雙審
4. APPROVED 後 push（auto-deploy）→ dogfood A/B 體感驗證
