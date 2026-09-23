# 開場兩段式評測

原有 `run.ts` 的舊單段控制模式保留。新增 `--compare-naturalness`：在**同一工程 HEAD**、同一模型與 token 設定下，比較現行兩段式與自然度候選。未執行真模型前，這是候選工程實作，不能聲稱品質提升。

## 控制來源與比較邊界

- `baseline-prompts.json` 從 P2 修復提交 `aee655a82658a8ea28b83e841a7759bc908a4987` 正式模組匯出；版本 `opener-two-stage-prompt-v1`。檔內保存來源及兩段 prompt 的 SHA-256，runner 會驗證 Git 來源及祖先關係。
- 候選直接匯入目前產品模組，版本 `opener-two-stage-topic-first-v1`（2026-09-24 教練定位；此前為 `opener-two-stage-natural-v1`）。所有原料整理、use/omit、來源檢查、投影與最終推薦共用目前工程實作；不把舊的漏擋帶回控制組。
- `naturalness_cases.json` 原樣保留準備包的 12 組人工資料；其中 `NOT_RUN` 是來源目錄的歷史狀態，真正結果與執行狀態只在 `out/<tag>/manifest.json`。適配器 `naturalness.ts` 透過正式請求驗證及 snapshot builder 接入 36 個輸入。
- `generate-only`：兩版本共用完全相同的合成合法快照、當前補充、正式初稿 fingerprint。快照來源明記 `synthetic_production_builder_shared_by_both_variants`，不冒稱模型分析。N10 三臂都與原初稿不同，正式失效邏輯均為 false。
- `full-two-stage`：相同原始資料，各版本獨立分析，再把自己的結果送入生成；結果另列，不能混為純第二段比較。N09 沒有實際圖片，六個版本／arm 組合均記為 `NOT_RUN_REQUIRES_ACTUAL_IMAGE`。
- 這是 prompt＋正式純函式評測，**不經 Edge、DB 或真正修正呼叫**。每筆明記 `repairPathExercised=false`、零次格式／內容修正及 `repairedOutput=null`。真正 handler 的修正、計費與重播另由 scripted-model＋PGlite 正式 SQL 回歸驗證。

## 無模型 dry-run

在專案 WSL 根目錄執行；需要既有 Deno、Git。無網路／環境變數權限，不讀模型金鑰：

```sh
deno run --cached-only --no-prompt --allow-read \
  --allow-write=tools/opener-two-stage-eval/out --allow-run=git \
  tools/opener-two-stage-eval/run.ts --compare-naturalness \
  --mode=both --repeat=1 --tag=phase1-dry --budget-usd=5
```

同名輸出目錄存在會拒絕覆寫。完整一輪：generate-only 72 次生成；full-two-stage 22 次分析＋66 次生成，共 160 次規劃呼叫。dry-run 實際呼叫一律 0，沒有假造輸出或品質分數。每筆保留工程 HEAD、prompt 版本、snapshot 來源、原初稿、目前補充及失效結果；尚未分析的 full-flow 輸入保持 null。

## 未授權的真模型比較提案

先做 N01／N03／N05／N10 的 generate-only，每臂一次，兩版本共 **24 次生成，費用上限 US$5**。若要完整兩模式則 **160 次，提案上限 US$20**，須另經 Eric 授權且先核實模型可用性與當日價格。本輪沒有執行任何付費呼叫。

真跑必須同時指定 `--run --confirm-paid --max-calls=<上限> --budget-usd=<上限> --input-usd-per-million=<已核實單價> --output-usd-per-million=<已核實單價> --price-source=<官方來源網址>`，並使用乾淨 HEAD。這些參數是技術守門，不能取代使用者授權。工具不自行核實價格；未提供價格時 dry-run 保持未知，真跑拒絕啟動。

每次送出前用 UTF-8 位元組數＋固定額外預留及 max_tokens 做保守費用預留；回傳 usage 後以指定單價計算。成本未知的失敗保留預留並停止後續呼叫，不能當成免費；`requests.jsonl` 留下送出前後紀錄。這是指定單價下的執行預算，非供應商帳单保證。API 費用、可用性及真實 transport 路徑本輪未驗證。

## 判讀

- 記錄原始輸出、正規化／硬檢查、原始模型排序、Free 三卡／付費五卡各自的最後推薦。硬錯的原始输出不投影成可交付結果，也不假造修復成品。
- `records.json` 保留失敗、未執行及各類別。正常正向想法、N03/N04 衝突或不適用目標、N05 單独身體觀察、N12 純限制及略過分開；不能把失敗從分母悄悄刪除。採用指標只是既有內容證據，不能當成語意正確率。
- 真跑後的 `blind_free.md`／`blind_paid.md` 只有資料、原初稿、目前補充、可見句子與最後推薦。隱藏版本、模式、case/arm ID、招式名稱、AI 理由與自評；seed 決定可重現的洗牌。對照在獨立 `reveal-map.json`，不要一起交给盲審者。
- 人工六維：想法忠實、容易回答、近的下一步、自然精簡、平等低壓、相關性。「近的下一步」指她容易接的下一句，不是邀約。15–45 字只作觀察，不新增硬門檻；產品原有 180 字防護不變。所有分數預設 null。

## 已知邊界／待主審

N03 已用正式 handler 證明：有來源地 omit 衝突的邀約部分、保留羽球活動可以交付。2026-09-24 教練定位後，想約目標（N01-A、N02-B、N03-A）不再要求採用，整段誤判 use 也不再觸發 material_unused、不會被修正逼出邀約；推薦有沒有真的碰到話題只剩字面指標與盲審，沒有程式檢查。修正提示補回對方資料與限制，但不能由 scripted fixture 推論真模型一定遵守。

候選 11 處替換已與實際來源唯一匹配，另補適用性語意界線及修正階段的來源上下文；準備包提到的原始 47,824-byte 規格未附在 ZIP，沒有獨立核實它的全文章節。沒有新增 continuations、UI、SQL、新話題或對話分析策略。

原 Work `w-dc8aabe2-c476-4a44-b85d-a76b68f9526f` 的主審歷史與阻擋保留。兩輪加一次特許補審已用完；建立本機證據不等於已送 ChatGPT 或已通過。沒有 push、deploy、付費測試或殘餘風險接受。
