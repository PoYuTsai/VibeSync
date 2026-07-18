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

### Windows 無 Docker：本機 prompt quality smoke

下面路徑直接跑工作樹內的 `analyze-chat`，只把 run ledger 放在 proxy 記憶體；不部署、不寫 production run table，測試帳號不扣 quota。runner 會印模型文字，所以只接受 `smoke_1_8x_*.json` 合成案例。

```powershell
$runtime = powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  tools/voice-benchmark/start_local_analyze_smoke.ps1 | ConvertFrom-Json

deno run --allow-net --allow-read --allow-env `
  tools/voice-benchmark/run_local_quality_smoke.ts `
  smoke_1_8x_whole_turn_laugh.json stream run-1

powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  tools/voice-benchmark/stop_local_analyze_smoke.ps1 `
  -ProcessId "$($runtime.proxyPid),$($runtime.functionPid)" `
  -RuntimeDir $runtime.runtimeDir
```

三組案例分別鎖：末句「哈哈」不得蓋掉整輪、多句同事件不得逐句拆段、真低投入不得追問施壓。quality runner 另檢查五風格/done contract、測試帳號零扣款，並掃 selected 與所有備選的時間漂移、未提供背景、低投入壓力、規則洩漏、常見簡體與壞字 `�`。

### Coach 1:1 本機 1.8x quality smoke

直接走工作樹內的 `runCoachChat`、Sonnet 5、schema／安全驗證與 retry，不連 DB；固定使用 test-account 模式，若程式嘗試扣額度會立即失敗。案例與輸出皆為合成文字，但會產生 Claude API 成本。

```powershell
deno run --env-file=supabase/.env --allow-env --allow-net `
  tools/voice-benchmark/run_local_coach_1_8x_smoke.ts --runs=2
```

三組案例鎖定：整輪最後只回「哈哈」仍要挑到高價值球、低投入不得追問／索取安撫／貼負面動機、使用者明確要完整訊息時不得硬砍。輸出含每個樣本的 Claude `attempts`，可觀察品質是否靠額外 retry 換來。

## blind/（盲測表，2026-06-12——**作廢留檔**，方向重設後不評）

- `blind_sheet.md`：3 case × 甲/乙（舊/新隨機去識別）＋ChatGPT 欄留白——Eric 拿 `chatgpt_paste/` 同輸入餵 free ChatGPT 貼回後評。
- `answer_key.md`：甲/乙對應，**評完才開**。
- 通過標準：新版 vs ChatGPT「不輸」≥ 2/3，且新版 > 舊版 3/3。
