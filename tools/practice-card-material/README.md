# practice-card-material：抽卡卡背典藏材質管線

規格：`docs/plans/2026-10-28-card-collectible-material-spec.md` §5（離線管線）、§6（執行時）。

卡背的構圖（徽記、星軌、節點、外框）照舊，材質換成三階典藏材質：N 鉑銀霧面、R 電光鈦藍、
SR 香檳金全息。構圖先描成向量，再用高度圖＋打光離線渲染成成品圖；執行時只做轉化擴散、跟著
卡片姿態走的光、SR 全息與額外發光（`lib/features/practice_chat/presentation/widgets/practice_card_material.dart`）。

## 檔案

| 檔案 | 內容 |
|---|---|
| `card_back_geometry.json` | 向量構圖（單一真相）：1200×1800 畫布上的多邊形、折線、圓環、圓弧，各自標圖層 |
| `trace_geometry.py` | 一次性描圖：從 V3 卡背遮罩描出向量構圖（開發工具，平常不用重跑）；收尾的接角修正與描圖碎段（`EMBLEM_JOINTS`、`join_circuits`、`TRACE_FRAGMENTS`）都是逐一列座標的明確修正，描圖結果一變就報錯；清單以外的短線也報錯，不靠長度門檻自動刪線 |
| `geometry.py` | 把 JSON 柵格化成反鋸齒覆蓋率遮罩（4 倍超取樣） |
| `heightfield.py` | 高度圖、材質編號、拉絲方向（飾板 0°、側飾條 90°、四角沿斜邊、暗帶沿卡緣、徽記三面各自的等角軸）、零件編號（拉絲相位）、徽記分面、倒角／斜面、稜面傾斜、高光／全息／發光／刻線遮罩 |
| `render_card_back.py` | 材質與打光（四盞燈＋有限距離相機；每種材質各自的反光寬窄：石墨霧面寬柔、拉絲沿／橫分開、拋光倒角窄；細碎短拉絲、底面細顆粒與霧面），輸出 7 張素材到 `assets/images/practice/` |
| `targets.json`、`concept_match.py` | 示意圖取樣的目標色與區域色差表（CIEDE2000）、紋理指標（底面顆粒／霧面、徽記三面明暗、拉絲連續性）、SR 全息（全息區裡玫瑰到天空藍的像素佔比） |
| `calibrate.py` | 把各材質的坡度起點對目標色二分搜尋，印出建議值（手動寫回 `TIERS`） |
| `test_geometry.py`、`test_render.py` | 構圖鎖定（含徽記沒有描圖短邊、線路端點不差一點點、沒有雙線；描圖碎段只拿掉清單裡的、重描跟提交的 JSON 逐位元相同）、素材尺寸與大小、色差、紋理指標、重跑逐位元相同 |

## 輸出（§5.4）

| 檔案 | 尺寸 | 內容 |
|---|---|---|
| `practice_card_back_v4_{n,r,sr}.webp` | 1200×1800 | 三階成品圖（有損 q94：q90 會壓掉一部分底面顆粒與拉絲細紋；四角留滿、執行時圓角裁切；最外 2 pt 由執行時的拋光外框蓋上） |
| `practice_card_back_v4_light.webp` | 1200×1800 | 無損 RGB：R＝浮雕補光差（0.5＝不變）、G＝全息遮罩、B＝高光遮罩（拉絲平頂乘上拉絲紋，高光帶掃過時帶方向性細紋） |
| `practice_card_back_v4_glowmask.webp` | 600×900 | 無損 RGB：R＝徽記與節點、G＝外框、B＝線路 |
| `practice_card_back_v4_glow.webp` | 600×900 | 預先模糊好的白色泛光（RGBA） |
| `practice_card_noise.webp` | 128×128 | 顆粒雜訊磚（灰階） |

遮罩一律用 RGB 打包、不透明：Flutter 解碼後是預乘 alpha，放在 alpha 的話 RGB 會被清掉。

## 指令（在 repo 根目錄）

```bash
# 重新渲染 7 張素材（同一份 JSON、同一個種子，逐位元相同；約 1 分鐘）
python3 tools/practice-card-material/render_card_back.py [--preview build/card_material]

# 檢查：構圖鎖定（要 scikit-image、scipy；另存疊圖 build/card_material/geometry_overlay.png）、素材、色差、重跑一致
python3 -m unittest discover -s tools/practice-card-material

# app 裡實際畫出來的卡背靜止圖（build/card_back_stills/），再對示意圖目標色
RECORD_CARDBACK=1 flutter test test/tools/card_back_still_recorder_test.dart
python3 tools/practice-card-material/concept_match.py --still build/card_back_stills/back_sr.png \
    [--concept <示意圖單張卡背，本機私有，不入庫>]

# 調材質參數後，重新校準坡度起點（印出建議值，手動寫回 render_card_back.TIERS）。
# 用全解析度（--scale 1.0，約 1.5 分鐘）：半解析度的拉絲與倒角高光跟成品不同，四角飾板會差 1 ΔE 左右
python3 tools/practice-card-material/calibrate.py --scale 1.0

# 只有改構圖時才要：重新描圖（要 scikit-image、scipy），檢查疊圖後提交 JSON
pip install scikit-image scipy
python3 tools/practice-card-material/trace_geometry.py --overlay build/card_material/trace_overlay.png
```

依賴：渲染、量測（`concept_match.py`、`calibrate.py`）與素材檢查（`test_render.py`）只要 numpy＋Pillow（含 WebP）；描圖與構圖鎖定檢查（`trace_geometry.py`、`test_geometry.py`）另外要 scikit-image、scipy（0.25 與 0.26 都可以）。

## 構圖鎖定（§5.1）

新的向量構圖反推回 V3 的 904×1428 跟原遮罩比，門檻寫在 `test_geometry.py`：徽記 IoU ≥ 0.90、
內外環半徑 ±1.5 px、節點中心 ≤ 4.5 px（只比原圖沒黏在一起的）、外框面積 IoU ≥ 0.85、外框細線
中位距離 ≤ 2 px 且覆蓋 ≥ 85%。另外三項回歸檢查（#114 第 3 輪）：徽記最短邊 ≥ 15 px（描圖磨出的
平頭、斜切）、線路端點跟旁邊的線／環／節點要嘛接上（≤ 0.5 px）、要嘛是刻意的間隙（≥ 4 px）、線路／
外框細線／星軌弧不能平行貼在 3 px 內超過 10 px（雙線）。這些只用來擋回歸，不拿來自動刪線。

## 來源與授權

構圖描自 V3 卡背遮罩（V3 由 V2 卡背去色萃取，來源與授權見
`docs/licenses/practice_draw_reference_assets.md`）；底面的煙霧質感取自 V3 底圖。材質、打光、
全息全部由這個資料夾的程式渲染。示意圖只用來取樣目標色（`targets.json` 只有數字），不入庫。
