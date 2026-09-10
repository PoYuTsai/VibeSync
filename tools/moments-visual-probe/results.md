# Step 0 探針結果（2026-09-10）

真呼叫 fal Seedream 4.5，24/24 成功（第一趟 24 張因 Deno `--allow-net` 漏列 `v3b.fal.media` 子網域，生成已計費但下載失敗，已修）。
腳本 `run.ts`；prompt 全文 `out/prompts.md`；圖與對照表在 `out/`（未進 git）。

設計：4 個手寫場景（coffee／street／desk／dinner）× 3 位角色 × {V1 現行 prompt, V2 場景＋角色拍法一句＋硬限制}。
同一對 V1/V2 共用同一個 production seed；場景固定不走 DeepSeek，唯一變因是風格段。
對照表每列一位角色（Mia／Chloe／Ivy），每欄依序 coffee V1,V2｜street V1,V2｜desk V1,V2｜dinner V1,V2。
`contact_sheet.png` 是 App 縮圖尺寸（260×180 cover）。

## 判讀（人眼，縮圖尺寸）

| 問題 | 結果 |
| --- | --- |
| 同一內容，不同人拍法看得出不同？ | **是**。coffee 與 dinner 兩欄最明顯：Mia 斜側近拍質地、Chloe 主體推到一側用桌緣當線條留白、Ivy 平視帶環境。street／desk 差異較小但仍可辨。 |
| 同一人四篇像同一人？ | **是**。Mia 四張都是近拍局部；Chloe 四張都有「一條邊＋留白」；Ivy 四張都保留環境。 |
| V1 三人有沒有像同一個攝影師？ | **有**。coffee／dinner 的 V1 三張幾乎同構圖（杯／碗置中、暖色、桌面）。 |
| 硬限制違規 | V1：`16_Ivy_coffee_v1` 出現**手**、`04_Mia_desk_v1` 筆記本有**可讀中文**、`02_Mia_street_v1` 有招牌字。V2：縮圖未見人物或可讀文字（原圖待逐張確認）。 |
| 副作用 | 拿掉 Taipei 後 street 三張 V2 全部像歐洲街景；但 V1 的 Chloe／Ivy street 帶著 Taipei 前綴也一樣像歐洲，只有 Mia V1 像台灣。地點線索不可靠，但完全拿掉會系統性偏歐洲。 |

## 對報告的結論

1. 報告核心假設成立：同模型下只改 prompt 組成就能看出「不同的人在拍」，不用換模型。
2. 每人一句拍法（取景習慣＋處理習慣）已足夠，主／次配方 70/30、tidiness、processingStrength 第一輪不需要。
3. 「Taiwan」要留，但放在**場景事實層**（如 `in Taiwan`），不放風格層；街景類題材才需要。
4. V1 前綴的 no hands／no text 明文禁止卻仍出現違規，代表禁令句本身不可靠；V2 把硬限制放最後一段，24 張未見違規，但樣本太小，不能當結論。
