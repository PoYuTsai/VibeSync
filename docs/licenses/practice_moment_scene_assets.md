# Practice Moment Scene Assets

Date: 2026-08-24

Scope:
- `assets/images/practice_moments/*.webp`（20 張情境圖）

Source:
- 由 OpenAI gpt-image 2.0（ChatGPT 內建 imagegen）生成，非取自第三方圖庫或影片。
- 實際生成輸入永久收錄於
  `docs/plans/2026-08-24-practice-moments-scene-image-prompts.md`：每張候選皆逐字使用
  共用 STYLE、對應 id 的場景 prompt 與共用 NEGATIVE，未改寫或合併。

Generation record:
- 生成日期：2026-08-24。
- 每個 id 先生成 2–3 張 1536×1024 PNG 候選；原始候選僅供人工挑選，未納入 repo。
- 入選圖置中裁切為 1365×1024、縮放至 960×720，再輸出為 sRGB WebP。
- 最終 20 張合計 869,614 B；每張皆低於 130,000 B。

| id | 候選數 | 入選候選 |
| --- | ---: | :---: |
| `moment_coffee_cup` | 2 | a |
| `moment_cafe_corner` | 3 | b |
| `moment_dessert_plate` | 3 | c |
| `moment_home_cooking` | 2 | a |
| `moment_late_night_snack` | 2 | b |
| `moment_street_night` | 2 | b |
| `moment_sunset_sky` | 2 | a |
| `moment_sea_view` | 2 | b |
| `moment_mountain_trail` | 2 | a |
| `moment_gym_corner` | 2 | b |
| `moment_yoga_mat` | 2 | a |
| `moment_cat_nap` | 2 | a |
| `moment_dog_walk` | 2 | a |
| `moment_bookshelf` | 3 | b |
| `moment_desk_work` | 3 | c |
| `moment_exhibition_wall` | 2 | b |
| `moment_live_stage` | 2 | a |
| `moment_flower_bunch` | 2 | a |
| `moment_rainy_window` | 2 | a |
| `moment_train_window` | 2 | a |

Usage:
- 僅用於練習室動態貼文的配圖。
- 除規格允許的不可辨識觀眾黑色頭部剪影外，全部不含人物；人工檢查未發現可辨識
  文字、第三方作品或品牌標識。
- 生成時未刻意模仿任何既有作品；生成結果不保證唯一。參見
  [OpenAI Terms of Use](https://openai.com/policies/terms-of-use/)。
