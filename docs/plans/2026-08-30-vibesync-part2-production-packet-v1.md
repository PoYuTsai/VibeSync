# VibeSync Part 2｜30–60 秒製作包 v1

日期：2026-08-30  
狀態：**本機備妥、尚未送件、沒有任何付費授權。**  
上位導演鎖：`2026-08-30-vibesync-part2-30s-director-lock-v3.md`

## 1. 製作結論

Part 2 不採「一支 30 秒讓模型同時完成救援、百人、20 張臉、20 個號碼與 Sydney 表演」。正式路徑是五支獨立動態素材加後製；每支只承擔一條主因果，失敗時只修該模組，不重跑整個後 30 秒。

| 成片時間 | 模組 | 主因果 | 生成素材長度 | 狀態 |
|---:|---|---|---:|---|
| 30.0–45.0 | A 救援 | 男主回應 Sydney → 橘色迴路 → 蒸氣減速 → 有重量落地 | 15s | prompt 與接縫素材已備妥，可列參數等授權 |
| 45.0–50.0 | B 揭露 | Sydney 示意觀看 → 兩人轉身 → 五區百人空間亮起 | 5s | prompt 已備妥；需 A 通過尾幀 |
| 50.0–53.0 | C 中央 20 人 | 男主主觀鏡；20 位真人都看中央鏡頭，以不同微笑／眨眼／小手勢回應；Stella 最後完成辨識 | 5s 取 3s | prompt 已備妥；**需先完成 exact 4K clean master** |
| 53.0–55.0 | D1 Stella | 開場瑜伽老師認出男主 | 5s 取 2s | blank badge 首幀與 prompt 已備妥 |
| 55.0–57.5 | D2 Sydney | 男主認出 Stella → Sydney 觀察、笑、單次眨眼 | 5s 取 2.5s | prompt 已備妥；需 B/C 通過後的暖光首幀 |
| 57.5–60.0 | FINAL | 回到 B 的英雄大全景 → 真 logo 留亮 → 收黑 | 不另生成 | 後製完成 |

## 2. 為什麼這樣比一次 30 秒穩

- A 只有男主、Sydney、冰繭與同一井道；百人素材完全不進 prompt，避免角色互相污染。
- B 只建立相視、轉身、五區空間與光線；百張精確臉不由這支負責。
- C 從 exact 20 人 clean master 做 3 秒克制微動；鏡頭就是男主眼位，20 道視線都落在中央鏡頭，號碼仍留給後製。
- D1 只鎖 Stella；D2 只鎖男主與 Sydney。兩種微表情不要求同一支模型跨景維持三張臉。
- FINAL 直接重用已通過的 B 大全景，不讓模型在最後兩秒重新發明空間或角色。

## 3. 送件檔案

1. `2026-08-30-vibesync-seedance-part2-a-rescue-15s-v2.txt`（v2：承認 Part 1 已完成 Sydney 露臉與破冰；從 29.50s 蒸氣白後直接接男主伸手）
2. `2026-08-30-vibesync-seedance-part2-b-wide-reveal-5s-v1.txt`
3. `2026-08-30-vibesync-seedance-part2-c-center20-5s-v1.txt`
4. `2026-08-30-vibesync-seedance-part2-d1-stella-5s-v1.txt`
5. `2026-08-30-vibesync-seedance-part2-d2-sydney-reaction-5s-v1.txt`

每份都使用 `START STATE → CAMERA → ONE CAUSAL ACTION → END STATE → CUT MATCH → AUDIO`，並把不可混入的內容寫在 `HARD AVOID`。

## 4. 接縫控制素材

資料夾：`../handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/production-prep-v1/`

- `PART1_v5_tail_27p50_30p08_H264_AAC.mp4`：唯一允許餵給 A 的 video reference；1920×1080、24fps、H.264、AAC 48kHz stereo、2.58s。
- `PART1_v5_t29p50.png`：A v2 的唯一 start image；用已發生破冰後的蒸氣白藏接縫，避免模型重新介紹 Sydney 或重演出招。
- `PART1_v5_t29p00.png`：只作「上一幕已完成 Sydney 露臉與破冰」的連續性核對，不作 A 的起始圖。
- `PART1_v5_t29p50.png`：蒸氣滿版的剪接遮罩；只供後製判斷切點，不當空白首幀。
- 禁止把完整 Part 1 餵成 video reference，避免 8–14s 曾出現的橫向飛行語法滲入 A。

## 5. 中央 20 人身份閘門

- 單一真相：`../handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/TANK100_center20_element_manifest_v1.json`。
- 20 位全部建立描述式 Element；Element 只鎖身份，不能鎖座位與表演。
- 四組固定為 C1 後左五、C2 後右五、C3 前左五、C4 前右五；一支局部修補最多五個 Element。
- `TANK100_center20_identity_lock_v2_4K.png` 是身份／座位控制板，不是電影首幀。
- `TANK100_center20_cinematic_concept_v1_COMPOSITION_ONLY_16x9.png` 是構圖／表演控制，不是身份母幀。
- 只有兩者合成並肉眼通過的 `TANK100_center20_clean_master_v1_4K.png` 才能送 C；此檔目前尚未成立。
- 本輪內建 imagegen 曾測試同時替四人換臉，但它連未指定的 16 人、構圖與服裝也一起重畫，因此已判定不適合作正式身份母幀，沒有放入專案採用鏈。

## 6. 五展區百人做法

- 空間 clean plate：`TANK100_fishbowl_empty_plate_v1_16x9.png`。
- 大全景語法：`TANK100_fishbowl_wide_concept_v3_research_locked_16x9.png`。
- 100 人精確分配：`TANK100_five_bay_manifest_v2.json`。
- 中央第 3 區放 exact 20 人；其餘 80 張真 App 素材分成四個側區 crowd plates。
- 側區 80 人只要求每個都是不同真人且都有實體牌；大全景不要求數字可讀。
- Hero 20 的真 `NO.xxx` 使用 20 個獨立平面追蹤圖層；模型只生成空白、可追蹤的實體牌。

## 7. 送件順序與停止點

1. 第一筆只能是 A；A 未通過「不重播破冰、正確手、男主主動伸手、蒸氣減速、有重量落地」前，不送 B。
2. A 通過後，以其真尾幀建立 B start image，再列 B 當下參數與 credits 等授權。
3. C 先停在 exact 4K clean master 閘門。沒有 20 個正確身份母幀，不得用 composition-only 圖冒充正式片。
4. D1 可獨立準備，但是否先送仍由 Eric 當下決定；D2 必須等 B/C 的實際暖光方向成立。
5. 所有 reroll、edit、局部五人補片都是新付費動作；沒有當下授權不得自動重送。

## 8. 每次付費前必列

- 平台／模型／模式
- 秒數、16:9、解析度、High、原生聲音開關
- start image、image references、唯一 video reference
- 一次輸出數量
- live confirmation screen 顯示的 credits 與扣款後預估餘額
- `只送 1 次／不 reroll／不自動重送`

有效授權必須指向該次完整參數；「可以繼續」、「試試看」或前一支的授權都不視為下一筆付費授權。

## 9. 全片驗收

1. Part 1 蒸氣白到 A 是否像同一個動作的延續，而不是硬切投影片？
2. A 是否從 Part 1 已完成的破冰蒸氣白直接接續，沒有再次介紹 Sydney 或再次出招？
3. 男主是否從既有裂口主動伸手，既有散亂橘光是否在接觸後整流向下，並一路清楚導致蒸氣？
4. 是否一路下降到有重量落地，沒有懸停、超人飛行、火車或牆面地板？
5. 五個展區是否連成一個真實超大空間，並清楚讀成一百位真人？
6. 中央 20 位是否全是指定 App 身份、座位不換，且全部眼神落在代表男主／觀眾的中央鏡頭，同時微動不整齊同步？
7. Stella 是否明確是開場瑜伽老師，`NO.038` 是否與臉同時清楚？
8. 男主認出 Stella 後，Sydney 的眨眼是否讀成教練鼓勵而非兩人談戀愛？
9. 最後是否回到百人高潮與真 logo，沒有翻牌、假 UI、標語或第二個 CTA？
