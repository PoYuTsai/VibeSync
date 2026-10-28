# 抽卡 V3 卡背素材（已移出 app）

- `practice_draw_card_back_v3_base.webp`：石墨拉絲底＋銀色倒角框＋銀色徽記。v4 卡背的底面煙霧質感取自這張（`tools/practice-card-material/render_card_back.py`）。
- `practice_draw_card_back_v3_emblem_mask.webp`、`practice_draw_card_back_v3_frame_mask.webp`、`practice_draw_card_back_v3_lines_mask.webp`：徽記、外框、線路遮罩。v4 卡背的向量構圖從這三張描出來（`tools/practice-card-material/trace_geometry.py`），構圖鎖定檢查也拿它們比（`test_geometry.py`）。
- `practice_draw_card_back_v3_glow.webp`：預先模糊好的徽記與外框光暈。

都由 `tools/practice-draw-card-back-v3/make_card_back_v3.py` 從 `docs/archive/practice-draw-v2/practice_draw_card_back_base.png` 離線產出（預設輸出到這裡）。2026-10-28 典藏材質起 app 改用 v4 卡背，清理那一刀從 `assets/images/practice/`（整個目錄打包進 app）移到這裡，app 少 273 KiB；來源與授權見 `docs/licenses/practice_draw_reference_assets.md`。
