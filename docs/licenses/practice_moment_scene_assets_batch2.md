# Practice Moment Scene Assets — Batch 2

Date: 2026-08-25

Scope:
- `assets/images/practice_moments/*.webp`（第二批 20 張備用情境圖）

Source:
- 由 OpenAI gpt-image 2.0（ChatGPT 內建 imagegen）生成，非取自第三方圖庫或影片。
- 實際生成輸入永久收錄於
  `docs/plans/2026-08-24-practice-moments-scene-image-prompts-batch2.md`：每張候選皆逐字使用
  共用 STYLE、對應 id 的場景 prompt 與該條指定的 NEGATIVE-A 或 NEGATIVE-B，未改寫或合併。
- 上述規格書的 Git blob 為 `3c50140f541e0f482619f49b5f6e8045d092ff0d`，與來源分支
  `claude/practice-moments-image-prompts-n2lllm` 的原檔一致。

Generation record:
- 生成日期：2026-08-25。
- 每個 id 先生成 2–3 張 PNG 候選；原始候選僅供人工挑選，存放於 repo 外，未納入版本控制。
- 入選圖置中裁切為 1365×1024、縮放至 960×720，再輸出為 sRGB WebP（quality 80、metadata stripped）。
- 第二批 20 張合計 793,348 B；第一、二批共 40 張合計 1,662,962 B；每張皆低於 130,000 B。

| id | 候選數 | 入選候選 |
| --- | ---: | :---: |
| `moment_iced_latte` | 2 | a |
| `moment_breakfast_shop_table` | 2 | b |
| `moment_bento_lunch` | 2 | b |
| `moment_street_food_stall` | 2 | b |
| `moment_bubble_tea_cup` | 2 | a |
| `moment_baking_tray` | 2 | a |
| `moment_friends_cheers` | 3 | b |
| `moment_hotpot_table` | 2 | b |
| `moment_ktv_room` | 2 | a |
| `moment_cafe_two_cups` | 2 | b |
| `moment_viewpoint_drinks` | 2 | b |
| `moment_rainy_alley` | 2 | a |
| `moment_bus_window_rain` | 2 | a |
| `moment_scooter_helmet` | 2 | b |
| `moment_open_book_blanket` | 2 | a |
| `moment_headphones_lamp` | 2 | b |
| `moment_harbor_boats` | 3 | c |
| `moment_temple_incense` | 2 | b |
| `moment_riverside_track` | 2 | a |
| `moment_sketchbook_desk` | 2 | b |

Human review:
- 逐張以原尺寸與手機約 240 px 顯示尺寸檢查；可辨識人臉未發現，發文者本人及其倒影未入鏡。
- `moment_breakfast_shop_table`：店內 2 名遠景、背對鏡頭且重度失焦的顧客。
- `moment_street_food_stall`：畫面上緣僅見遠景、失焦的路人小腿與鞋部，無臉部或可辨識身分。
- `moment_friends_cheers`：4 組手臂／手掌僅由畫面邊緣入鏡並帶動態模糊；背景用餐者皆為不可辨識色塊。
  入選候選已逐手檢查手指數量與關節，未發現多指、缺指或畸形。
- `moment_cafe_two_cups`：遠景顧客僅為重度失焦背影，未見手部或臉部細節。
- 其餘 16 張未見人物、人體部位或倒影；全批未發現可辨識文字、logo、第三方作品或品牌標識。
- 40 張縮至 240 px 後主題仍可辨識，整體色調一致；置於深紫底 `#1F1330` 時無刺眼大面積純白。

Usage:
- 僅用於練習室動態貼文的備用配圖。
- 生成時未刻意模仿任何既有作品；人工檢查未發現可辨識的第三方作品或品牌標識。
  生成結果不保證唯一。參見 [OpenAI Terms of Use](https://openai.com/policies/terms-of-use/)。
