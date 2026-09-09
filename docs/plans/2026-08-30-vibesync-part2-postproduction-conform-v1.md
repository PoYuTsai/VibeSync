# VibeSync Part 2｜後製 Conform v1

日期：2026-08-30  
狀態：本機後製規格；不是付費生成授權。

## 1. 主時間軸

- Master：1920×1080、16:9、24fps、Rec.709、逐行掃描。
- Audio：48kHz、stereo；最終輸出 AAC 192kbps 以上。
- 交付：H.264 High Profile、`yuv420p`、`+faststart`；另保留高品質 mezzanine 中間檔。
- Part 1 母片固定為 `PART1_v3c_HYBRID_v5_HAND_TEXT_LOCK_H264_AAC.mp4`，不得重編前 30 秒畫面內容。

| 時間 | Video | Audio | 接法 |
|---:|---|---|---|
| 29.50–30.35 | Part 1 蒸氣白與 A 開頭重疊 | Part 1 爆裂尾音跨縫；A 近距離冰滴淡入 | 8–12 幀 additive／screen 蒸氣疊化；不能普通黑場 dissolve |
| 30.00–45.00 | A 救援母片 | A native Foley 為主 | 只在冰片、蒸氣與近牆面板遮滿時藏切 |
| 45.00–50.00 | B 雙人轉身＋百人揭露 | 呼吸→玻璃低頻→左右展開的 room tone | 男主黑肩遮擋切入大全景 |
| 50.00–53.00 | C 中央 20 人 | 玻璃空間、布料、座椅與極低人聲嗡嗡 | 男主肩線 wipe；鏡頭鎖定，不做 AI 橫移 |
| 53.00–55.00 | D1 Stella | 近距離呼吸與衣料 | 眼線 match cut，不用發光傳送 |
| 55.00–57.50 | D2 男主＋Sydney | wink 前抽掉 room tone 3–4 幀 | 眼線回玻璃，接 B 大全景 |
| 57.50–59.35 | B 最後英雄大全景重用＋精確 crowd／badge 合成 | 音樂到最高和弦，百人 room tone 展開 | 不再生成新人物或新鏡頭 |
| 59.35–60.00 | 同鏡自然壓暗，真等角立方體 logo 留亮後全黑 | 低頻尾韻＋一聲克制品牌音 | 不出 UI、翻牌、標語或 CTA |

## 2. 影像軌建議

- V1：Part 1 鎖定母片。
- V2：A rescue master。
- V3：B duo／wide master。
- V4：五展區 empty architecture plate。
- V5–V8：四個側區各 20 人 crowd plates。
- V9：中央 20 人 exact clean master／C 動態。
- V10：D1 Stella。
- V11：D2 Sydney／male。
- V12–V31：Hero 20 獨立 badge／`NO.xxx` 平面追蹤。
- V32：玻璃反射、薄霧、體積光與最終 true-logo layer。

## 3. 號碼與身份

- 20 個 Hero badge layer 直接用 `Name_NOxxx` 命名，例如 `Stella_NO038`、`Audrey_NO099`。
- 每張牌獨立四點追蹤；禁止用一張 20 人大圖整體變形。
- 任何局部角色補片只重追該角色牌；其餘 19 張沿用已通過追蹤。
- 1080p 中 Stella／Audrey 三位數字至少 30px 高；其餘前層至少 28px、後層至少 24px。
- 玻璃反射在臉與牌面區做局部壓低，白字不能被暖橘高光洗掉。

## 4. 百人合成

- 五區不是五張卡：所有人物 plate 共用同一片連續弧形玻璃、地板反射與天花光帶。
- 中央區照度 100%；內側兩區約 72–82%；外側兩區約 52–65%。外側仍須看到膚色、髮型、晚禮服與不同人物輪廓。
- 側區 80 位只做稀疏微動；每區同時明顯動作不超過四人，禁止整區同步眨眼或招手。
- 女孩都在玻璃內亮側，男主與 Sydney 在玻璃外暗側；不加入價錢、服務等級、叫號燈或情色姿勢。
- C 鏡與 D1 的鏡頭中心固定為男主眼位。Hero 20 的瞳孔都必須落在中央鏡頭；可以錯開眨眼、微笑與手勢，但不能把視線分散到 Sydney、彼此或畫外。若單一角色視線飄移，只修該 5 人分區，不重跑整段。

## 5. 聲音

- A1：Part 1 native mix；只跨到 30.35s。
- A2：A rescue native Foley；保留掌心接觸、橘光序列、蒸氣與兩次落地。
- A3：B/D close Foley；呼吸、衣料、腳步，不保留任何生成式語音。
- A4：glass-room tone；中央亮起時由中間向左右展開。
- A5：crowd micro Foley；布料、座椅與極低無字人聲，不可像酒吧吵雜。
- A6：score／low-frequency design。
- A7：final brand tone。
- 任何 native audio 出現可辨識台詞、名字、尖叫、歡呼或性感喘息，直接靜音該段並改用乾淨 Foley，不嘗試保留。

## 6. 不可用修法

- 不用 frame interpolation 補救錯臉、錯手或消失人物。
- 不用普通 cross-dissolve 跨兩張完全不同構圖；只在蒸氣、冰片、肩線或眼線 match 中藏切。
- 不把橫向金魚缸 morph 成直式 App 卡片。
- 不讓 AI 重寫 VibeSync logo、號碼、App UI 或字幕。
- 不用 slow motion 假裝下墜加速度；速度感必須來自牆面視差、碎片方向、衣襬與聲音。

## 7. 最終 QC

逐幀確認：兩人身份、Sydney 眼鏡／白衣、左右手、男主存在、下降方向、地板連續性、100 位總量、中央 20 位身份與座位、Hero 20 全部中央鏡頭眼神、20 張真號碼、Stella `NO.038` 直視同一眼線、Sydney 只眨一次、真 logo、無假 UI。Windows 交付檔另用 `ffprobe` 驗證 H.264／AAC／1920×1080／24fps／48kHz stereo。
