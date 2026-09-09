# VibeSync Part 2 A｜M2A 付費送件前清單 v10

日期：2026-08-31  
狀態：**Eric 已明確回覆「跑」並完成唯一一次付費送件；Job 已完成、已扣 36 credits。未 reroll、未 retry、未重送。成片本地初審因中段違反單鏡位鎖而暫列 BLOCK，等待 Eric 最終裁決。**

## 送件設定

- 模型：Seedance 2.5（model id：seedance_2_5）
- 模式：Omni Reference（mode：omni_reference）
- 生成秒數：4 秒
- 成片預計取用：約末段 1.2083 秒／29 格；實際入出點待成片驗收
- 比例：16:9
- 解析度：1080p
- Bitrate：high
- 原生音效：ON（generate_audio：true）
- 輸出數：1
- Unlimited：不可用；use_unlim：false，使用 credits
- Reroll：OFF
- 自動 retry／自動重送：OFF
- Multi-shot：不啟用；M2A 本身固定單鏡位

## 全部參考素材

1. 唯一影片參考
   - PART2A_M1_v8_ACCEPTED_TAIL_2p064_4p064_2p000s_H264_AAC.mp4
   - Higgsfield media：c22f6809-c52e-4ea2-a5d3-e7fb732a337c
   - 角色、黑長袖、既有兩點抓握與動態連續權威；不負責 M2A 反打鏡位
2. 唯一直接圖片參考／Start image
   - P2A_M2A_SYDNEY_SUBJECTIVE_GRIP_LOCK_CANDIDATE_v10_1920x1080.png
   - Higgsfield media：5f58f7d7-0fe5-4e1a-ad93-47b872f98e3a
   - Eric 已核准；只負責 Sydney 側主觀鏡位、三隻手拓撲與手臂進畫方向
3. Sydney Element
   - Sydney_V3_WhiteOnepiece
   - Element：db109a5a-f9a4-4999-905f-7809d5e1d69a
   - 狀態：completed
   - Prompt placeholder：<<<db109a5a-f9a4-4999-905f-7809d5e1d69a>>>
4. 男主 Element
   - VibeSync_Male_M1
   - Element：247e5e3c-5b28-4650-be9f-4a043943f0f3
   - 狀態：completed
   - Prompt placeholder：<<<247e5e3c-5b28-4650-be9f-4a043943f0f3>>>

畫面張數口徑：直接上傳的圖片參考 1 張；另外注入 2 個角色 Elements，每個 Element 各有 1 張身份底圖。因此 payload 顯式媒體為 1 影片＋1 start image，另有 2 個 Element。

不得上傳：真人夫妻握手照、v9 純冰拓撲圖、任何舊錯手人物圖、Contact Sheet、K2／K4／K5／K6、Hero phone。

## Prompt 鎖

- Prompt 來源：2026-08-31-vibesync-seedance-part2-a-m2a-sydney-subjective-charge-4s-v10.txt 中 COPY ONLY 區塊。
- 送件前將兩個 @Element 名稱機械替換成上述 <<<Element UUID>>>；刪除末端純 @tag 行，不改其他文字。
- 送件 prompt：4267 characters／4285 UTF-8 bytes。
- SHA-256：c174e93de974d14d03f2476f3104bb1c22cfdbf329bbe56fb24ca6ec666a36ba

## 即時 credits 與成本

- 唯讀查詢時間：2026-08-31，本次送件準備回合
- 當下餘額：1419.25 credits
- Free-trial unlimited：不可用
- 完整 payload 唯讀估算：36 credits（exact 36）
- 若成功扣款後的預期餘額：1383.25 credits
- Cost estimate 回傳調整：影片 canonical role video 會由後端映射為 video_references；其他欄位沒有回傳調整
- 估算工具確認：No job submitted

## 硬停止線

本清單授權的唯一一次 generate_video 已執行完畢。結果不合格時一律停下報告；任何 retry、reroll 或重送都需要 Eric 新一輪明確回覆「跑」。

## 實際送件與結果

- 送件時間：2026-08-31
- Job：96787c40-94e2-4492-8089-6f0853eec6a2
- 狀態：completed
- 實際扣款：36 credits
- 扣款後餘額：1383.25 credits
- 後端唯一調整：canonical `video` 映射為 `video_references`
- 原檔：`docs/handover-screenshots/film-boards-2026-08-29/video-tests/PART2A_M2A_v10_LOAD_TEST_SEEDANCE25_4S_JOB_96787c40_RAW.mp4`
- H.264／AAC 分享版：`docs/handover-screenshots/film-boards-2026-08-29/video-tests/PART2A_M2A_v10_LOAD_TEST_SEEDANCE25_4S_JOB_96787c40_H264_AAC.mp4`
- 八格檢查圖：`docs/handover-screenshots/film-boards-2026-08-29/part2-rescue-physical-lock-v1/production-prep-v10/PART2A_M2A_v10_JOB_96787c40_CONTACT_SHEET_8F.png`
- 分享版驗證：1920×1080、24 fps、97 格、4.064 秒、H.264 High／AAC stereo
- 本地初審：前半維持 Sydney 側主觀鏡位且兩點抓握大致成立；約中段模型自行 180° 反打為男主看 Sydney，違反「do not cut again」與固定 Sydney 主觀鏡位硬鎖。預定取用的末段約 1.2083 秒落在錯誤反打鏡位，因此暫列 BLOCK。
- 自動重送：無
