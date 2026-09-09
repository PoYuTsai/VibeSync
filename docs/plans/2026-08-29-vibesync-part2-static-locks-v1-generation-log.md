# VibeSync Part 2｜六張靜態導演鎖 v1｜生成紀錄

日期：2026-08-29  
模式：Codex 內建 `image_gen`（imagegen skill）；**未送 Higgsfield／Seedance、未扣影片 credits**。  
用途：30–55s 的構圖、身份、手部、落地物理與表演起始幀；不是付費影片送件授權。

## 一次看完

- 六格 16:9 總表：`../handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/PART2_30s_six_keyframes_contact_sheet_v2_16x9.jpg`
- 原始產圖為 3:2；所有採用格另保留無破壞的 `_16x9.png` 中央裁切版。
- 20 位真實女孩身份順序參考：`../handover-screenshots/film-boards-2026-08-29/part2-static-locks-v1/TANK_CAST_20_REFERENCE_10x2.jpg`

## 採用格

| 模組 | 採用檔 | 判定 |
|---|---|---|
| A1 Sydney 揭臉 | `A1_Sydney_reveal_v1_16x9.png` | 身份、左掌、橘屏反射、上揚髮絲成立；鏡頭比原定 75mm 更高更動態，先作候選 |
| A2 掌心迴路 | `A2_palm_circuit_v1_16x9.png` | 男左女右、男右掌接 Sydney 左掌、兩張臉與橘光因果成立 |
| A3 有重量落地 | `A3_weighted_landing_v2_round_atrium_16x9.png` | 兩人屈膝、鞋底接地、圓形井底大廳成立；v1 狹長走廊作廢 |
| P2-B 雙人／缸揭露 | `P2B_duo_tank_reveal_v1_16x9.png` | 垂直井口、寬闊大廳、暖缸與相視成立；成片相視停留要短，避免戀愛誤讀 |
| B10 20 人身份 plate | `B10_cast_plate_exact20_v2_16x9.png` | 正好前排 10＋後排 10；099 在前排第五位，真短髮眼鏡身份與唯一號碼牌成立；尚未合玻璃、後排 80 人與前景背影 |
| B11 Sydney 眨眼起始 | `B11_Sydney_pre_wink_v1_16x9.png` | 兩眼全開、閉嘴微笑、男主肩線與暖金／冷紫光成立；下一格才眨眼 |

淘汰：`B10_layout_diagnostic_22people_v1.png` 多生 22 人且把 099 身份與牌掛錯；只留診斷，不得當母幀。`A3_weighted_landing_v1.png` 人物姿勢可用但背景像狹長走廊，只留歷史。

## 最終 prompt set（重現用）

### A1

- References：B11（Sydney 臉）、B7（白衣／井材質）、COCOON、ENV0、v3c 29.0s 真尾幀。
- Primary：蒸氣藏切後，同一顆冰繭左、Sydney 右；她左掌壓同一道斜裂縫，眼鏡反射三顆橘矩形，嚴肅、喘氣、不笑不眨眼。
- Camera／avoid：電影近景、髮絲向上；禁水平隧道、列車、實驗室、悠哉漂浮、額外手指。

### A2

- References：A1、v3c 男主 12s／14s、COCOON、ENV0。
- Primary：50mm 側面雙人鏡；男主固定畫左，右掌主動破冰；Sydney 固定畫右，左掌在中央與他貼合；橘光只從接觸點向外點亮螢幕。
- Physical lock：兩人各五指、肩膀不交叉、沒有握手或抓腕、仍向下墜、沒有地面。

### A3（v2 背景修正）

- Edit target：A3 v1；architecture reference：P2-B 圓形井底大廳。
- Change only：把狹長平行走廊換成正下方的寬闊圓形落地大廳與頭頂巨大井口。
- Preserve：兩位演員、身份、服裝、男左女右、屈膝接地、手臂帶穩、髮絲／碎冰上飛、橘蒸氣與濕地反射全部不變。

### P2-B

- References：A3、舊 B10 建築概念、A1、v3c 男主。
- Primary：圓形落地大廳；男主左、Sydney 右，剛鬆手後短暫劫後相視；共享眼線引向中央巨型暖金玻璃練習室。
- Avoid：狹長走廊、車廂、月台、約會站位、假 logo／UI。

### B10（採用的 v2 clean plate）

- References：20 人真實身份表、22 人錯版只取燈光／座椅。
- Primary：**總人數正好 20**，前排 10＋後排 10，沒有第三排、背景人群或前景背影。前排依序 `017 023 026 068 099 078 086 088 090 096`；後排依序 `038 024 032 016 051 083 011 019 070 082`。
- Identity lock：保留每人的真實年齡、臉、髮型與膚色；099 是參考表裡短髮、黑框眼鏡的成熟東亞女性，位於前排第五；只有她的牌先寫 `NO.099`，其餘留空後製。
- Avoid：19／21／22 人、同臉、099 換人或摘眼鏡、背景群眾、白色晚禮服、假文字／logo。

### B11

- References：A1 Sydney 身份、舊 B11 構圖、P2-B 大廳光、v3c 男主肩線。
- Primary：85mm 眼高近景；男主只留左前景肩頸；Sydney 右側，兩眼全開、閉嘴極小教練笑，下一格才眨眼。
- Avoid：已經眨眼、露齒廣告笑、咬唇歪頭、曖昧約會、亮白實驗室、清楚女孩群像。

## 下一層製作

1. 先以 A1／A2／A3／P2-B 定鏡頭與短片接點。
2. B10 clean plate 再分層合入玻璃框、景深後排 80 人、男主與 Sydney 背影；不可把 clean plate 重新整張生成。
3. 號碼與真 VibeSync logo 全部後製；除 `NO.099` 概念標記外，不把文字交給影片模型。
4. 任一付費影片仍逐支列參數、當下 credits，停下等 Eric 明確授權。
