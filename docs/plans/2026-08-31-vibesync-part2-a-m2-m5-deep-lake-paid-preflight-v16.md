# VibeSync Part 2 A｜M2–M5 深湖版 27 秒｜付費送件預檢 v16

時間：2026-08-31T11:30:35+08:00  
狀態：**尚未送件、尚未扣 credits。等待 Eric 在看完本預檢後再次明確回覆「跑」。**

## 獨立審查

- Reviewer：Claude Fable，read-only round 1。
- 結論：`APPROVED_WITH_RISK`；無 P0／P1。
- 已確認一致：右手對右手掌握＋左手托前臂、單一腰下橢圓冰繭、Sydney POV→第三人稱遮切、全身拔出、至少 5.1 秒純重力急墜、男主早約 0.20 秒入水、兩人各自游泳上岸、全段 0.00–27.00 秒無缺口或重疊。
- 主要生成風險：
  1. 27 秒內仍有 POV、外部側 3/4、遠景急墜、水下、水線與岸邊六種鏡頭語法；單次長生成可能漂移。
  2. 提示詞要求碎冰在約 16 秒後才砸入水，但其延遲機制未明確畫出；模型可能讓碎冰提早入水或改寫近失節奏。
  3. 次要風險：5.1 秒急墜剛好填滿 5.10 秒時槽；上岸短扶上臂可能被硬性 `no re-grip` 誤抑制；黑屏手機來源未明寫。
- 若 Eric 在本預檢後回覆「跑」，視為接受上述固定快照的生成風險，並授權只建立一個付費 Job；不代表授權 reroll、retry 或第二次送件。

## 即時模型與送件參數

- 模型：Seedance 2.5（`seedance_2_5`，Bytedance）
- 模式：Omni Reference（`omni_reference`）
- 秒數：27 秒
- 比例：16:9
- 解析度／bitrate：1080p／High
- 原生音效：ON
- 輸出數：1
- `use_unlim`：false；目前 Unlimited 不可用
- Reroll：OFF
- Automatic retry：OFF
- Automatic resubmission：OFF
- 只允許建立 **一個** Job

平台即時 schema 顯示 Seedance 2.5 支援 4–30 秒、16:9、1080p、High bitrate 與原生音效；本次參數沒有被調整。

## 全部參考素材

畫面共 **3 張**、影片共 **1 支**：

1. START IMAGE：`P2A_M2A_SYDNEY_SUBJECTIVE_GRIP_LOCK_CANDIDATE_v10_1920x1080.png`  
   本地：`/home/eric1/work/VibeSync/docs/handover-screenshots/film-boards-2026-08-29/part2-rescue-physical-lock-v1/production-prep-v10/P2A_M2A_SYDNEY_SUBJECTIVE_GRIP_LOCK_CANDIDATE_v10_1920x1080.png`  
   Higgsfield media：`5f58f7d7-0fe5-4e1a-ad93-47b872f98e3a`
2. IMAGE REFERENCE：Sydney identity，`Sydney_V3_WhiteOnepiece`  
   Higgsfield media：`983d3037-86f6-4c8d-9b6c-f9245b54bdb5`
3. IMAGE REFERENCE：Male identity，`VibeSync_Male_M1`  
   Higgsfield media：`fdb6c55f-24e4-4bab-bbdd-200654e845be`
4. VIDEO REFERENCE：`PART1_ACCEPTED_FAST_PHONE_WELL_FALL_16p00_18p50_2p50s_H264_AAC.mp4`  
   本地：`/home/eric1/work/VibeSync/docs/handover-screenshots/film-boards-2026-08-29/part2-rescue-physical-lock-v1/production-prep-v12/PART1_ACCEPTED_FAST_PHONE_WELL_FALL_16p00_18p50_2p50s_H264_AAC.mp4`  
   Higgsfield media：`515745fc-f342-4021-806e-26921af99517`

平台只做預期的 canonical role mapping：兩張 `image` → `image_references`、一支 `video` → `video_references`；沒有替換素材。

## 明確不使用

- 不使用已淘汰岸邊六格示意圖、Contact Sheet 或 K2–K7。
- 不使用私人握手測試照片、舊 v13b 或前次失敗生成影片。
- 不使用 M1 男主 POV 尾片作影片參考。
- 不生成可讀手機 UI、文字或 logo。
- 不包含 Part 2 B 女孩／金魚缸。

## 即時 credits

- 方案：Plus
- 當下顯示 credits：**897.25**
- Exact quote：**243 credits**
- 若唯一一次送件成功，預估餘額：**654.25 credits**

## 固定快照與可重算證據

- Prompt block SHA-256：`af822d808682cfcba48632bc2cfd1094683192081b031f89212fce37cdbc21ef`（11,534 bytes）
- Prompt file SHA-256：`69ea9a13085a0068dc38dd4d265091dac43474d76071cf2b09d181f71bab9183`（13,029 bytes）
- Director lock SHA-256：`ea3ba74d8ce7aeea96a7f1f3939795fef95d7322c08b34383f0f069c8cfa5abf`（5,424 bytes）
- Snapshot SHA-256：`ca143cbebb50ad209979c0b9db4796ca96c2e59f0290278e64e607e9971566e8`（1,905 bytes）
- PowerShell `Get-FileHash` 與 WSL `sha256sum`／Node 各自重算結果一致。

固定檔案：

- Prompt：`docs/plans/2026-08-31-vibesync-seedance-part2-a-m2-m5-deep-lake-27s-v16.txt`
- Director lock：`docs/plans/2026-08-31-vibesync-part2-a-m2-m5-deep-lake-lock-v16.md`
- Snapshot：`docs/plans/2026-08-31-vibesync-part2-a-m2-m5-deep-lake-snapshot-v16.json`

## 付費閘門

只有 Eric 在看到以上完整預檢後再次回覆 **「跑」**，才可立即重讀 balance 與 exact quote，確認固定快照與參數未變，然後送出唯一一個 Job。任何參數、素材、prompt hash 或價格發生變化，都必須停止並重新列示。
