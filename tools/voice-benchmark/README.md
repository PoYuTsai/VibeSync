# voice-benchmark

voice few-shot 化案（`docs/plans/2026-06-12-voice-fewshot-design.md`）的盲測素材。

## 盲測組成（2026-06-12 Eric 拍板：全 held-out）

few-shot 範例（golden 糖糖、小雲首晚）的輸入**不進盲測**——同輸入會變開卷背誦、新版必贏，盲測失真。盲測三題全部用不在 prompt 裡的素材：

| Case | 素材 | 關係階段 | payload |
|------|------|----------|---------|
| 1' | 承瑋 R 局（聖誕夜學妹四連發） | 升溫/熱絡 | `cases/case1_chengwei_r.json` |
| 2' | 肉伊（被虧像Gay+誇溫柔感混合球） | 陌生早期 | `cases/case2_rouyi.json` |
| 3 | Ashley（「你有約過別人不是去那邊的嗎」試探球） | 見面後試探 | `cases/case3_ashley_probe.json` |

- golden＋小雲切點（`cases/case2_min_first_night.json`）降級為**非盲 anchor 檢查**：改完 prompt 後驗服務鏈能重現定稿 voice，不佔盲測眼力、不計入通過標準。
- 冷局 smoke test：用承瑋 Wen 局罐頭冷啟動段（轉寫見 `chengwei-transcript-draft.md`），驗新 prompt 遇冷不變 pushy。不進盲測。
- 通過標準不變：新版 vs ChatGPT「不輸」≥ 2/3，且新版 > 舊版 3/3。

## 轉寫稿

- `case3-bruce-transcript-draft.md`：Bruce 4 年前 21 張（肉伊 5 張＋Ashley 16 張），已抽查目檢（S__42246191/177 吻合）。
- `chengwei-transcript-draft.md`：承瑋 22 張 3 對象，含 18 處戰術標籤＋紅筆步驟編號（高手筆記，輸出可參考）。⚠️ S__42246217 含真實手機號碼，素材化前必匿名。

## baselines/（舊 prompt prod 黑箱輸出，2026-06-12）

- `golden_v2_run1/2.ndjson`：golden case（糖糖，熟絡局）。run2 五槽完整。
- `case2_min_run1/2.ndjson`：小雲首晚切點（anchor 用）。
- `case1_chengwei_run1/2.ndjson`、`case2_rouyi_run1/2.ndjson`、`case3_ashley_run1/2.ndjson`：盲測三題，各兩輪皆五槽完整零 error。

## 跑法

```
./run_baseline.sh cases/<case>.json <output_name>
```

憑證：測試帳號在 `tools/ocr-golden/.env.golden`、anon key 在 repo root `.env.local`。直打 prod `analyze-chat` stream 收 ndjson（同 Phase 1 黑箱手法）。

## 待建

- 盲測表（3 case × 舊/新/ChatGPT 去識別隨機排序；ChatGPT 欄需 Eric 拿同輸入餵 free ChatGPT 截取）。規模小，可手工。
