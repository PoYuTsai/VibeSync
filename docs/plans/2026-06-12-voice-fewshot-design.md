# 主 prompt 全面 few-shot 化（voice few-shot 化）— 設計定稿

> 2026-06-12 brainstorming 定稿，Eric 逐項拍板。
> 目標：analyze-chat 輸出主觀「不輸 free ChatGPT」——人腦肉眼覺得「哦！還不錯蠻高手的、很幽默」。
> 結構不動：segments / 5 風格槽 / 瘦推薦卡 / stream 契約全凍結（Phase 1 資產）。

## 開案依據

Eric 實測（2026-06-12）同一場對話正面對決：

- golden.mp4 = **ChatGPT 免費入口**輸出：點名用戶自造梗（糖糖老師）、分層變體、rationale 是洞察句（「既像開玩笑，又是埋邀約」）、回覆有推拉懸念。
- VibeSync（方案二 Phase 1 後）：結構全對（missed call 接住、逐球引用、複製分段），但 reply 是禮貌模板、零 callback、rationale 是標籤句。
- 差距不是模型能力（同量級），是 prompt 架構抽稅：規則壓抑、範例啟發。活證據：prompt 備用技巧區早有 Callback／良性冒犯／三段式小節，輸出裡一個都沒出現。

## 核心發現

`## 輸出格式 (JSON)`（index.ts ~1868 起，~150 行）**本身就是一個 few-shot**——但範例值全是占位句（「舊版 App fallback：…」），模型每次都在模仿平庸範例。非 stream 舊 build 相容仍需要 schema，所以不是刪，是**換血**。

## 改動（純 server：SYSTEM_PROMPT + stream_prompt）

1. **輸出格式範例值換血**：schema 骨架壓縮保留，範例值全換 golden 級 voice 文字（有推拉、有懸念的真句子）。一刀同時服務 stream / 非 stream。
2. **新增 2 個完整 voice few-shot**（輸入對話 → 完整輸出）：
   - 範例 1 = 糖糖老師場景（ChatGPT golden 轉寫成 segments 格式，**Eric 逐句定稿**）：熱絡多球 + missed call + callback + 幽默。
   - 範例 2 = 冷淡／試探局：示範「這時收斂不耍幽默」——防 few-shot 過擬合，教 voice 也教剎車。
3. **Callback 挖掘**：一條短指令（從對象歷史／對話挖用戶自造梗、暱稱、重複元素；**有梗才 callback，沒梗不硬造**）＋靠範例 1 示範。
4. **Rationale 升級成洞察句**：不加新規則散文，全靠範例示範。

淨 token 目標：砍占位＋壓縮 schema 抵銷新增，**淨增 ≤ +10%**。

## 不做（YAGNI / 另案）

- 高光球分層（穩/幽默/高手多版本）→ Phase 2 item（client schema/UI），混進來會讓盲測歸因失真。
- 全 prompt 重構（B 案）→ 本輪是它的第一步；benchmark 證明有效後，後續每輪再蠶食一塊規則區。

## 量測（先建後改）

**3-case 盲測**：golden case（糖糖老師）＋冷淡局＋試探局（取自真實 dogfood）。每 case 三版輸出：舊 prompt（prod baseline，先跑留檔）／新 prompt／ChatGPT。去識別、隨機排序，Eric 盲選排序。

**通過標準**：新版 vs ChatGPT「不輸」≥ 2/3 case，且新版 > 舊版 3/3。

黑箱 curl 手法沿用 golden_v2_run（/tmp ndjson）。

## 執行順序

1. 轉寫 golden.mp4 → 範例草稿 → Eric 逐句定稿（人工迴圈，品味權在 Eric）。
2. 建 3-case benchmark、跑舊 prompt baseline 留檔。
3. TDD 改 prompt（測試錨：golden 範例存在＋占位句移除；index_test 既有 prompt assertions 同步）。
4. 黑箱復測（segments 契約不退化）＋ benchmark 重跑 → 盲測。
5. Codex 雙審（高風險區：AI 行為）→ land。

## Close Condition

設計拍板（本檔）＋實作 land＋Deno 綠＋黑箱契約不退化＋Codex 雙審 APPROVED＋Eric 盲測「不輸 ChatGPT」＋Bruce 實測有感。
