# VibeSync Part 2 A｜M2–M5 單次 27 秒 Master｜付費送件預檢 v15

時間：2026-08-31T05:35:02+08:00  
狀態：**尚未送件、尚未扣 credits。等待 Eric 在本預檢之後再次明確回覆「跑」。**

## 獨立審查

- Reviewer：Claude Fable，read-only round 1
- 結論：`APPROVE_WITH_RISK`
- 無 P0。
- P1 已由本次即時平台預檢解除：Seedance 2.5 現行 schema 明確支援 4–30 秒；27 秒 exact live quote 成功。
- 剩餘生成風險：27 秒單次動作鏈複雜，可能有長片段角色／物理漂移；不以 reroll 隱藏風險。
- 已知非阻擋差異：首幀男主臉上的霜較少，模型可能弱化提示詞要求的眉毛、睫毛與髮際薄霜。

## 即時模型驗證

- 模型：Seedance 2.5（`seedance_2_5`，Bytedance）
- 模式：Omni Reference（`omni_reference`）
- 現行時長範圍：4–30 秒；本次 27 秒有效
- 比例：16:9；現行 schema 支援
- 解析度：1080p；現行 schema 支援
- Bitrate：High；現行 schema 支援
- 原生音效：ON
- 輸出數：1
- `use_unlim`：false（目前 unlimited 不可用）

## 唯一送件參數

- Duration：27 秒
- Aspect ratio：16:9
- Resolution / bitrate：1080p / High
- Native audio：ON
- Count：1
- Reroll：OFF
- Automatic retry：OFF
- Automatic resubmission：OFF
- 只允許建立 **一個** job

## 全部參考素材

畫面共 3 張、影片共 1 支：

1. START IMAGE：`P2A_M2A_SYDNEY_SUBJECTIVE_GRIP_LOCK_CANDIDATE_v10_1920x1080.png`  
   Higgsfield media：`5f58f7d7-0fe5-4e1a-ad93-47b872f98e3a`
2. IMAGE REFERENCE：`Sydney_V3_WhiteOnepiece`  
   Higgsfield media：`983d3037-86f6-4c8d-9b6c-f9245b54bdb5`
3. IMAGE REFERENCE：`VibeSync_Male_M1`  
   Higgsfield media：`fdb6c55f-24e4-4bab-bbdd-200654e845be`
4. VIDEO REFERENCE：`PART1_ACCEPTED_FAST_PHONE_WELL_FALL_16p00_18p50_2p50s_H264_AAC.mp4`  
   Higgsfield media：`515745fc-f342-4021-806e-26921af99517`

Cost validator 接受以上四個 media ID，無 media error。Canonical `image`／`video` 角色只做預期的 backend schema mapping：`image_references`／`video_references`；沒有時長、比例、解析度或素材替換調整。

## 即時 credits

- 方案：Plus
- 當下 credits：**1140.25**
- Unlimited：不可用
- Exact quote：**243 credits**
- 若送件成功後預估餘額：**897.25 credits**

## 不可變綁定

- Prompt block SHA-256：`9c1d8b2c2e4f2e8589b5ab6900f5a52ccbb2a3ffe8756eb511a9fea065732760`
- Full prompt file SHA-256：`ca92ed80cd35cbbd0372c536684cb76ef0f56c578ebdb2264cdecd9af4765da1`
- Snapshot SHA-256：`9fdcf92cb339af8847b9a15abe2401b2dc0cec2324c7a71692c9317836453cec`
- Prompt：`2026-08-31-vibesync-seedance-part2-a-m2-m5-single-master-27s-v15.txt`
- Director lock：`2026-08-31-vibesync-part2-a-m2-m5-single-master-lock-v15.md`

## 明確排除

- 不使用 M1 男主 POV 尾片作生成參考
- 不使用已淘汰 v13b 首圖
- 不使用私人握手測試照片、Contact Sheet 或 K2–K7
- 不生成可見手機螢幕／UI 文字；手機本體保留後製
- 不包含 Part 2 B 金魚缸
- 不自動 reroll、retry、重送或建立第二個 job

## 付費閘門

只有 Eric 在看到以上完整預檢後再次回覆 **「跑」**，才可立即重讀 balance 與 exact quote，確認固定參數未變後送出唯一一個 job。任何參數或價格發生變化，都必須停止並重新列示。
