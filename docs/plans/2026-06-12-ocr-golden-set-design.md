# OCR Golden Set 量測案設計（2026-06-12）

> 來源：`docs/reviews/2026-06-12-ocr-readonly-audit.md` 建議 #1（Eric 拍板開案）。
> 硬約束：零風險、不動 OCR code path。本案唯一目的：把「左右判斷 ≥98%」從願望變實測數字，並為未來任何 OCR 改動建立 land 前回歸跑分。
> 拍板紀錄：截圖來源 / 標注流程 / telemetry 範圍均經 Eric 確認（本檔即紀錄）。

## 架構：黑箱 HTTP 跑分

腳本把圖打到 `analyze-chat` 的 `recognizeOnly` 端點（`quotaBypassed`，不扣 quota），收 `recognizedConversation` 與 ground truth 比對。不 import、不複製任何 OCR 程式碼——量到的是用戶真實吃到的全鏈（vision → normalize → layout repair → 分類 → dedup），零漂移。

端點雙模式：

- **prod**（預設）：線上 Edge Function + 測試帳號 token → 量 prod baseline。
- **local**：`supabase functions serve analyze-chat --no-verify-jwt` + 本機 `CLAUDE_API_KEY` → 未來 OCR 改動 land 前先跑分，分數不退步才准上。

```
tools/ocr-golden/
  README.md
  manifest.json          # 每張圖：id、source(real|synthetic)、scenarios[]、檔名、group(重疊組)
  labels/<id>.json       # ground truth：contactName、classification、messages[{side,text}]
  run_benchmark.ts       # Deno 跑分腳本
  generate_synthetic.py  # 合成圖 generator（PIL + 系統中文字型）
  generate_overlap.py    # 長圖裁切重疊變體（讀真實圖，輸出至 gitignored 目錄）
  synthetic/             # 合成圖（無隱私，入 git）
  results/               # 跑分輸出（gitignored）
```

## 圖源與隱私

- **真實圖 12 張與其 labels 一律不入 git**：圖存於 Eric 本機 OneDrive 目錄，跑分時以 `OCR_GOLDEN_IMAGES_DIR` 環境變數指向；labels 在 `labels/real/`（gitignored——labels 內容即對話逐字稿，圖不入 git 但逐字稿入 git 等於白防）。manifest 只記檔名。兩個系列：LINE 日常對話（含 700×2339 長圖）、交友軟體對話（11 張連號）。
- **重疊組（實況更新 2026-06-12）**：標注後發現連號截圖天然帶逐字重疊（246 首 1 則重複 245 尾、252 前 8 則重複 251 尾，均已逐字驗證），直接以「兩張一組同請求」manifest unit 測 dedup，毋需裁切長圖。
- **合成圖（範圍縮小，實況更新 2026-06-12）**：標注後確認真實圖已原生覆蓋 dark_mode、quoted_card、typo（pattya/健深房/裡拜三/好哒）、sticker、long_screenshot、only_left pattern——合成只需補**中線氣泡**（水平位置精準壓 42-58% 含糊區，唯一真實圖保證不了的情境）×2-3 張，PIL 畫 LINE 風格入 git。
- 標注：左=對方、右=我（Eric 確認本批圖全為標準 layout）。AI 看圖產草稿 labels，Eric 逐張快速校對。

## 跑分指標

先 LCS 序列對齊（文字 normalize 後相似度 ≥0.8 視為同一則），再打分：

| 指標 | 定義 | 對應 audit 風險 |
|---|---|---|
| Side accuracy | 對齊訊息 left/right 判對比率（主指標） | #1 #2 |
| Message recall / precision | 漏抓率 / 幻覺率 | #2 |
| Final unknown rate | 最終 `side: unknown` 比率 + `uncertainSideCount` | #1 |
| Text fidelity (CER) | 字元錯誤率；錯字保留檢查（「在→再」原樣才算對，被修正 = fail） | #3 |
| Dedup correctness | 重疊組合併後訊息數與去重 expected 一致、無無聲丟失 | #4 |
| Classification | `classification` / `importPolicy` 符合預期 | 非聊天圖防護 |

報告分層：真實圖為主指標、合成圖獨立列參考；每情境標籤（midline / dark_mode / quoted_card / overlap / typo）各自小計。輸出 `results/<日期>.json`（機器可 diff）+ markdown 摘要。

實況更新（2026-06-12 讀碼確認）：`recognizeOnly` 成功回應即帶 `normalizationTelemetry`（`index.ts:3847-3858`，layout 修復數/系統列移除數/重疊去除數等 7 計數）——黑箱**拿得到修復次數分佈**，原樣存入 results JSON。黑箱量不到的只剩「修復前的原始 unknown 訊息清單」（非計數），由 telemetry 案補。`importPolicy: reject` 走 400 `RECOGNITION_UNSUPPORTED`，跑分視為合法結果（對 reject label 算正確）。

## Telemetry 設計（本輪文件 only，實作另開案 + Codex 雙審）

核心發現：pipeline 計數已存在（`normalizationTelemetry` 修復數/系統列移除數、`uncertainSideCount`、`sideConfidence`），僅未持久化。設計方向：

- `logAiCall()` 加結構化 `ocr_metrics`（jsonb）：`imageCount`、`finalUnknownCount`、`uncertainSideCount`、`adjustedCount`（layout repair 修復次數）、`systemRowsRemoved`、`classification`、`importPolicy`、`sideConfidence`。
- 零訊息內容、零新表（掛 `ai_logs`），附每週 SQL 分佈查詢範本。
- 時程：golden set baseline 數字出來後，另開 scoped task 實作，OCR 高風險區須 Codex 雙審。

## 執行順序（一次一變數）

1. 本設計文件 commit。
2. 跑分腳本 + manifest 骨架。
3. AI 草稿 labels → Eric 校對（唯一需 Eric 的步驟）。
4. 合成 generator + 合成圖 + labels。
5. 打 prod 跑 baseline → 第一份實測報告。
6. 更新 `docs/ocr-analysis-maturity-benchmark.md`：98% 從期望改實測。

閉環標準：audit 風險 #1-#4 全部有數字；未來 OCR 改動有 land 前跑分可用。

## 成本

每次完整跑分 ~20 張 × Sonnet vision ≈ US$0.15。
