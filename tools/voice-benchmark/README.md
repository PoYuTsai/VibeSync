# voice-benchmark

voice few-shot 化案（`docs/plans/2026-06-12-voice-fewshot-design.md`）的 3-case 盲測素材。

## baselines/

- `golden_v2_run1.ndjson`、`golden_v2_run2.ndjson`：golden case（糖糖老師，熟絡局）**舊 prompt（Phase 1 後、few-shot 化前）prod 黑箱輸出**，2026-06-12 留檔。run2 為完整五槽 + finalRecommendation，是盲測「舊版」一欄的素材。
- 黑箱 curl 手法：直打 prod `analyze-chat` stream 端點收 ndjson（同 Phase 1 復測手法）。

## 待建

- 陌生早期局、陌生冷淡局兩個 case 的對話素材（取自真實 dogfood）＋各自舊 prompt baseline。
- 去識別、隨機排序的盲測表產出腳本（規模小，可手工）。
