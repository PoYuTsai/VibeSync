# voice-benchmark

voice 案測試素材。現行方向＝Game 體系化（`docs/plans/2026-06-12-voice-game-system-design.md`）；盲測已退役（round1 結算不過、round2 作廢留檔），本目錄轉為 anchor／smoke 復測資產庫。

## 現役資產（2026-06-12 刀 2 範例對調後）

few-shot 範例現為 golden 糖糖（熟絡檔）＋承瑋 Wen 局（冷開→升溫完整弧線檔）。範例輸入不得當 held-out 測試（開卷背誦失真）：

| 角色 | 素材 | payload |
|------|------|---------|
| golden anchor（非盲） | 糖糖（熟絡局，重建版輸入） | `cases/golden_anchor_recon.json` |
| 冷局 smoke（held-out，驗不 pushy、不裝熟） | 小雲首晚（刀 2 退出 prompt 接手） | `cases/case2_min_first_night.json` |
| held-out 預備 | 承瑋 R 局／肉伊／Ashley | `cases/case1_chengwei_r.json`、`cases/case2_rouyi.json`、`cases/case3_ashley_probe.json` |

- `cases/wen_cold_smoke.json` 已刪（刀 2）：Wen 局進 prompt 後其冷啟動段＝開卷，smoke 失效；冷局 smoke 由小雲 payload 接手。
- 驗收走新 gate 四關（設計檔 §3）：契約測試＋anchor 復測＋Eric/Bruce 體系感雙向目檢＋Codex 雙審。盲測通過標準作廢。

## 轉寫稿

- `case3-bruce-transcript-draft.md`：Bruce 4 年前 21 張（肉伊 5 張＋Ashley 16 張），已抽查目檢（S__42246191/177 吻合）。
- `chengwei-transcript-draft.md`：承瑋 22 張 3 對象，含 18 處戰術標籤＋紅筆步驟編號（高手筆記，輸出可參考）。⚠️ S__42246217 含真實手機號碼，素材化前必匿名。

## baselines/（舊 prompt prod 黑箱輸出，2026-06-12）

- `golden_v2_run1/2.ndjson`：golden case（糖糖，熟絡局）。run2 五槽完整。
- `case2_min_run1/2.ndjson`：小雲首晚切點（anchor 用）。
- `case1_chengwei_run1/2.ndjson`、`case2_rouyi_run1/2.ndjson`、`case3_ashley_run1/2.ndjson`：盲測三題，各兩輪皆五槽完整零 error。
- `new_*.ndjson`：**新 prompt**（c64bbed few-shot 第一刀＋128d00e audit 砍 A+B）prod 黑箱輸出，2026-06-12 砍完部署後跑。9/9 過 `check_contract.sh`（五槽零 error、source contract 乾淨）。
  - `new_case{1,2_rouyi,3}_run1/2`：盲測三題新版＝盲測素材。
  - `new_golden_anchor_run1`：golden anchor（非盲）。⚠️ payload 是 `cases/golden_anchor_recon.json` **重建版**（原 payload 未留檔、hash 對不上舊 baseline），輸入非逐字同源但場景同。voice 重現定稿：懸念鉤 finalRecommendation（pick=coldRead 同 Eric 拍板）＋糖糖老師 callback；舊 run 的「夜市」範例汙染歸零。
  - `new_min_anchor_run1`：小雲 anchor（byte-identical payload）。重現定稿「等等，妳是泰國人？…」pick=coldRead。
  - `new_wen_smoke_run1`：Wen 冷局 smoke（`cases/wen_cold_smoke.json`，嗨→冷回嗨；**case 檔已刪**，baseline 留檔）。不 pushy：humor 低壓破冰、明示「不是推進邀約」。

## 跑法

```
./run_baseline.sh cases/<case>.json <output_name>   # 黑箱打 prod 收 ndjson
deno run --allow-net --allow-read live_contract_smoke.ts cases/case3_ashley_probe.json 5  # 跨平台長對話契約 smoke（只印 metadata）
./check_contract.sh <name1> [name2 ...]             # 契約檢查（五槽/零error/source contract）
./gen_blind_sheet.sh                                # 產 blind/blind_sheet.md＋answer_key.md
```

憑證：測試帳號在 `tools/ocr-golden/.env.golden`、anon key 在 repo root `.env.local`。直打 prod `analyze-chat` stream 收 ndjson（同 Phase 1 黑箱手法）。

## blind/（盲測表，2026-06-12——**作廢留檔**，方向重設後不評）

- `blind_sheet.md`：3 case × 甲/乙（舊/新隨機去識別）＋ChatGPT 欄留白——Eric 拿 `chatgpt_paste/` 同輸入餵 free ChatGPT 貼回後評。
- `answer_key.md`：甲/乙對應，**評完才開**。
- 通過標準：新版 vs ChatGPT「不輸」≥ 2/3，且新版 > 舊版 3/3。
