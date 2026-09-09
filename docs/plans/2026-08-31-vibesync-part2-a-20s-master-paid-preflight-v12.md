# VibeSync Part 2 A v12｜Higgsfield 付費送件前檢查

檢查時間：2026-08-31T04:12:31+08:00  
狀態：**歷史送件紀錄。Eric 明確回覆「跑」後已建立唯一 Job `ea8d04b0-5da3-447a-a544-55e2cb8ffd5c`，扣除 144 credits；成片已由導演拒絕，未 reroll、未 retry、未自動重送。**

## 送件設定

- 模型：Seedance 2.5（`seedance_2_5`）
- 模式：Omni Reference（`omni_reference`），不是 Video Extension
- 本次生成：16 秒
- 最終剪輯：已通過的 M1 v8（97 格）＋本次預期 384 格，僅移除一格穩定尾格，目標 480 格／20.000 秒（仍以成品 `ffprobe` 為準）
- 比例：16:9
- 解析度：1080p
- Bitrate：High（`high`）
- 原生音效：開啟（`generate_audio: true`）
- 輸出數：1
- `use_unlim`：`false`；目前 unlimited generations 不可用
- Elements：0；Seedance 2.5 本次使用普通 Omni 圖片／影片參考

## 直接參考素材

直接圖片 3 張：

1. Sydney 主觀鏡頭與精確三手抓握拓樸：`P2A_M2A_SYDNEY_SUBJECTIVE_GRIP_LOCK_CANDIDATE_v10_1920x1080.png`  
   Higgsfield media：`5f58f7d7-0fe5-4e1a-ad93-47b872f98e3a`
2. Sydney 身分、眼鏡、髮型、白色短袖連身服與黑靴：`Sydney_V3_WhiteOnepiece_ELEMENT.png`  
   Higgsfield media：`983d3037-86f6-4c8d-9b6c-f9245b54bdb5`
3. 男主身分、炭黑長袖、深色長褲與赤腳：`VibeSync_Male_M1_ELEMENT.png`  
   Higgsfield media：`fdb6c55f-24e4-4bab-bbdd-200654e845be`

直接影片 1 段：

1. 密集手機井材質、向上視差與高速垂直下墜速度：`PART1_ACCEPTED_FAST_PHONE_WELL_FALL_16p00_18p50_2p50s_H264_AAC.mp4`  
   Higgsfield media：`515745fc-f342-4021-806e-26921af99517`

不附加：已通過的 M1 v8、K2–K7、Contact Sheet、私人夫妻解剖照片。Hero phone 保留後製，不由模型生成。

## Prompt 與快照

- Prompt 貼入區塊：10,371 字元／10,455 UTF-8 bytes（不含檔尾換行）
- Prompt 區塊 SHA-256：`7195860d89af47901a6a2bb56ba9583fc5ebe302d829c5d6c1a908ffd67d8449`
- Prompt 整檔 SHA-256：`3cc2f9f4e9c9e3612583a3e9e29deda6fe9079e01982aa3a8933d05248bb1f3f`
- v12 快照 SHA-256：`d83c8849ea1e625a7c38baa472b110bd1d324cd93db856f7996b7feac63c06a1`
- 獨立第二輪複核：`APPROVED`

## Credits

- 當下帳戶：Plus
- 當下餘額：1,284.25 credits
- 唯讀成本估算：144 credits（exact 144）
- 預期扣款後：1,140.25 credits
- 成本工具僅把三個 `image` role 正規化為 `image_references`、一個 `video` role 正規化為 `video_references`；未調整秒數、解析度或其他送件設定

## 重送規則

- Reroll：關閉／未授權
- Retry：關閉／未授權
- 自動重送：關閉／未授權
- 本檢查不構成送件授權；只有 Eric 在看到本清單後，新一輪明確回覆「跑」，才可建立唯一一筆 Job。

## 實際結果

- Job：`ea8d04b0-5da3-447a-a544-55e2cb8ffd5c`
- 成品：16.064 秒、1920×1080；原始 HEVC Main 10／AAC，已另存 H.264／AAC 分享版。
- 實際送件後餘額：1,140.25 credits。
- 導演結論：不通過。第一人稱腿部構圖、冰繭、拔出因果、高速墜落、手機井、人物受力、落地與冰／手機威脅均未達標。
- 後續：由 `2026-08-31-vibesync-part2-a-modular-action-lock-v13.md` 取代。
