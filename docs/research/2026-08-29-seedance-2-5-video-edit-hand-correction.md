# Seedance 2.5 Video Edit：手機握持手左右修正研究

日期：2026-08-29  
範圍：只查 Higgsfield、ByteDance Seed、BytePlus／Dreamina 第一方資料與產品介面；未上傳素材、未估價、未生成、未重試。

## 結論先講

目前這個鏡頭若再次只用「原影片＋文字說把右手換成左手」，官方證據不足以認為成功率會明顯提高。前一次模型保留了錯手，代表純文字的左右手語意沒有壓過來源影片的既有像素與動作慣性。

成功率最高、同時最能保住右手點擊、VibeSync UI、冰霜、鏡頭與光線的工作流是：

1. 保留目前約 5.7 秒的單一動作來源片；若還能裁短，也只能裁到仍完整包含「持機 → 右手點擊 → 結冰」的 4–6 秒，不要把因果拆斷。
2. 先做一張同一畫面、同一角度、同一光線的正確握法參考圖。參考圖中只能把持機手改成左手：左手拇指位於畫面左側、其餘四指從畫面右側包住手機；由畫面右側進場點擊的右手保持原樣。
3. 若 Higgsfield 當下的 Seedance 2.5 編輯頁真的出現可畫區域／point／brush 工具，遮罩只圈持機左手與手腕，加極窄的融合邊界；不要圈手機畫面、點擊右手、冰霜或背景。
4. 使用 `video_edit`，來源影片作唯一動作／時間控制；正確握法圖只作解剖與握姿參考。先用一張主參考，只有在點擊前後握姿明顯不同時才加第二張，不要堆一批互相衝突的圖。
5. 指令用「時間範圍＋畫面位置＋唯一因果動作＋保留項」寫法，並把左右手改寫成可目視驗收的畫面幾何，不只寫 `left hand`。
6. 視覺編輯時不生成新聲音；通過後把原片音軌原封不動 remux 回去。這是為降低音訊漂移的製作流程建議，不是模型保證。

若 Higgsfield 頁面沒有區域選取，而且 `video_edit` 也不能同時加入匹配角度的握法參考圖，就不建議再送同類 generic edit。官方已證實 Seedance 2.5 的複雜動作物理與多主體互動仍非完全穩定，而「兩隻手＋手機接觸」正是高風險情境。

## 第一方能力核對

| 控制項 | 第一方證據 | 目前可確定的 Higgsfield 狀態 | 對本鏡頭的意思 |
|---|---|---|---|
| 局部區域編輯 | Higgsfield Seedance 2.5 頁宣稱可做 region-level edit，只重繪指定區域。Dreamina 官方 localized edit 流程明確要求在清楚影格上選 exact region。 | 行銷／教學頁確認「局部修正」概念；但 Higgsfield 公開的 Seedance 2.5 Video Edit schema 沒有 mask、brush、座標或 bounding box 欄位，公開說明也沒有證實一般 Video Edit 面板一定能畫遮罩。 | 若 UI 實際出現 brush／point，優先使用；若沒有，不能把文字區域描述當成真正 mask。 |
| 參考圖 | Seedance 2.5 支援 image reference；BytePlus Enhanced Video Edit 可放 1–9 張圖，並明說角度、距離相近可顯著提高替換成功率。Seed 官方一般多模態上限為 30 圖。 | Higgsfield 模型層有 `image_references`；但公開文件未證實每個 Video Edit 入口都能與來源影片同時使用多張圖。 | 必須在送出前看介面是否真的能加圖；本鏡頭以 1 張同角度的正確握法主圖為優先，必要時最多 2 張。 |
| 首幀／尾幀 | BytePlus 明確支援 first-frame I2V 與 first-and-last-frame I2V。 | Higgsfield 平台有 start／end image 角色，但公開資料未證實它們可在 Seedance 2.5 `video_edit` 內作局部約束。 | 不拿首尾幀 I2V 取代 Video Edit；那會重新生成整段，UI、冰霜和點擊動作更容易漂。參考圖應走普通 image reference。 |
| 來源／參考影片 | Seedance 2.5 支援 reference video、特定時間段修改與參考構圖／電影語言；Higgsfield `video_edit` 使用一支來源影片。 | 目前可確定來源影片是 edit 的主要時間、構圖與動作控制。Higgsfield live model catalog 顯示 edit 的 duration 與 aspect ratio 由來源片決定。 | 用現在的短來源作唯一 control video，不再塞第二支動作影片。 |
| 時間裁切／duration | 一般 Seedance 2.5 可做 4–30 秒；BytePlus Enhanced Video Edit 的來源為 2–15 秒、輸出 4–15 秒，並建議主體清楚、鏡頭相對穩定。Higgsfield V2V 官方工作流也建議先切成目標 clip。 | Higgsfield `video_edit` 沒有獨立 crop 控制；duration 在 edit 模式由來源片繼承。 | 先在外部裁成單一 4–6 秒動作，或沿用目前 5.7 秒片；不要要求模型在長片裡自行找手。 |
| 空間 crop | 查到的 Higgsfield／BytePlus Seedance 2.5 公開 schema 沒有 spatial crop 參數。 | 未證實。 | 不把裁一小塊手再讓模型補整畫面當第一選擇；這會增加邊緣、手機與 UI 合成接縫。 |
| 音訊 | Seedance 2.5 支援音訊參考與原生同步音訊；BytePlus 有 `generate_audio` 開關。Higgsfield current catalog 也有 `generate_audio`。 | 官方未保證 Video Edit 會逐位元保留原聲，也未說 edit 時完全不重混。 | 對這次外觀手術，建議關閉新音訊，再後製接回來源音軌；不要讓模型多解一個不必要任務。 |
| 解析度／bitrate | BytePlus 精確的 Seedance 2.5 generation API 列 480p／720p、24 fps；其 Enhanced Video Edit 通用欄位列到 1080p。Higgsfield current catalog 提供 480p／720p／1080p 與 standard／high bitrate。Higgsfield 行銷頁對 native 解析度的說法高於 BytePlus API。 | 平台封裝、升頻與底層模型規格之間有差異，不能把「native 1080p／4K」當成每次 Video Edit 的保證。 | 若介面可選，維持 1080p High 以貼近母片；驗收仍看輸出實際細節，不用行銷標籤判定。 |
| prompt guidance／CFG／seed | 官方共同建議是時間碼、空間位置、明確唯一修改與 Preserve／Avoid；Seed 官方示例也用「只改 camera，其餘不變」。 | 公開 Higgsfield Video Edit schema 沒有獨立 CFG、guidance scale、seed 或 negative-prompt 欄位。 | 能控制的是提示詞結構與視覺參考，不存在可宣稱能鎖死結果的數值旋鈕。 |
| 自動評估／重試 | BytePlus Enhanced Video Edit 有可選自動評估和重試，官方明說會增加時間與成本。 | 未證實 Higgsfield Seedance 2.5 Video Edit 有相同開關。 | 本案不啟用；每一次重試都是新的付費行為，必須另得 Eric 明確授權。 |

## 為什麼上一輪容易失敗

1. **來源影片的像素慣性比文字強**：原片清楚顯示右手持機，提示詞卻要求同一接觸動作改成左手；沒有正確視覺錨點時，模型最省力的結果就是保留原手。
2. **`left/right` 對鏡頭視角有歧義**：人物左右、觀眾畫面左右、手掌朝向和手機正反面可能互相衝突。應以「畫面左側拇指／畫面右側其餘手指」加一張實際正確圖消除歧義。
3. **同時接觸的主體太多**：持機手、點擊手、手機、按鈕發光、冰霜擴散都在狹小區域互相遮擋。Seed 官方也承認複雜動作物理合理性與多主體互動仍有改善空間。
4. **只寫保留、不代表真的鎖像素**：沒有 mask 的文字式 Video Edit，即使寫「其他完全不動」，模型仍可能重繪 UI、手指、手機邊緣或冰霜。

## 最高成功率的未送件工作流

### A. 先做可驗收的視覺錨點

- 從原片選持機手最清楚、右手點擊尚未完全遮住手機的影格。
- 在同一張完整畫面上只修正持機手，不換手機、不鏡像整張、不重畫 UI。
- 合格幾何：左手拇指沿手機的**畫面左緣**；其餘手指從**畫面右側**包住手機背面／右緣；右手食指仍由畫面右側進入並點擊。
- 手腕角度、膚色、焦距、景深、暖光、陰影與動態模糊要貼近來源片。
- 若點擊後握姿幾乎沒變，只用一張主參考。若冰霜階段明顯改變遮擋，再補第二張同角度的結冰狀態圖。

### B. 先確認 Higgsfield 介面，沒有就停

送件前只做介面確認，不先生成：

- 是否有 Seedance 2.5 `Video Edit`；
- 是否能同時放來源影片與 image reference；
- 是否真的能在影格上 point／brush／選 region；
- 是否能選 1080p、High bitrate、關閉生成音訊；
- edit 是否明示沿用來源 duration／aspect ratio。

若前兩項缺任一項，這條 Higgsfield 工作流就不是目前官方證據支持的高成功率方案。若有 image reference 但沒有 mask，仍可做一次「參考圖＋時間／空間文字鎖定」的次佳方案；風險會高於真正局部遮罩。

### C. 區域選取原則

- 選區只涵蓋持機手、手腕，以及一圈極窄的光影／動態模糊融合邊界。
- 不選手機螢幕中央、不選 VibeSync 字與按鈕、不選右側點擊食指、不選冰霜大面積、不選背景。
- 若持機手指與手機邊緣重疊，遮罩只能吃進修正接觸陰影所需的最小手機邊緣，避免整支手機被重畫。

### D. 建議提示詞草稿（僅備稿，不送件）

```text
TARGETED VIDEO EDIT OF @Video 1.

Use @Image 1 only as the anatomy, grip, camera-angle, and lighting reference for the supporting hand. Do not copy any UI or unrelated pixels from the reference image.

During 00:00.00–00:05.70, replace only the hand that supports and grips the phone with one anatomically correct human LEFT hand matching @Image 1. In screen coordinates, the left thumb runs along the SCREEN-LEFT edge of the phone, while the other fingers wrap naturally around the back and SCREEN-RIGHT edge. Keep one stable wrist, five natural fingers, physically correct contact, and continuous motion through the whole shot.

The separate RIGHT hand entering from SCREEN-RIGHT and tapping the orange button remains exactly unchanged.

Preserve the source video's timing, camera, crop, phone geometry, real VibeSync UI and all readable text, orange tap glow, frost growth, ice texture, lighting, shadows, background, and every untargeted area. Do not add or remove any hand, finger, object, icon, dialog, text, or effect. No camera change, no UI redesign, no mirroring, no new action.
```

若介面支援時間碼標記，應把 `00:00.00–00:05.70` 改成持機手實際出現的精確範圍；若全片都出現就維持全段。不要在同一輪再要求改鏡頭、冰霜、UI 或聲音。

### E. 驗收與聲音

一次生成後只驗四件事：

1. 左手幾何是否正確且全程沒有翻回右手；
2. 右側進場點擊的右手是否沒被換掉、沒多指；
3. 手與手機接觸是否自然，手機邊緣、UI、文字和冰霜是否保持；
4. 是否能無縫替換回 Part 1 母片。

視覺通過後，把來源片的原音軌 remux 回成片；這比要求模型重新生成同一段聲音可控。若失敗，不自動 reroll，也不讓平台自動評估後重試；先停下判斷失敗類型，再由 Eric 決定是否授權下一次付費操作。

## 不建議的路徑

- 原封不動重送上一輪「只用文字把右手換左手」的 generic Video Edit。
- 用 first／last-frame I2V 重新生成整個 5.7 秒片段；它能控頭尾，不能保證中間 UI、點擊和冰霜逐格不漂。
- 鏡像整張畫面；會把 UI、文字、點擊方向與光線一起反轉。
- 只裁手部小方塊生成，再直接硬貼回去；除非轉入人工 VFX／roto 流程，否則接觸陰影、手機邊緣與動態模糊很容易露餡。
- 啟用 BytePlus 自動 retry；每次重試都可能增加成本，且不符合本案「只送一次、不 reroll」限制。

## 仍未知的限制

- Higgsfield 現行網頁版 Seedance 2.5 `Video Edit` 是否真的提供可畫的 mask／brush／point；官方行銷頁有 region edit，但公開 schema 沒有 mask 欄位。
- Higgsfield `video_edit` 是否在每個入口都允許一支來源影片再加多張 image reference，及參考圖能否綁定特定時間段。
- Higgsfield 編輯後是否逐位元保留來源音軌；「支援原生音訊」不等於「原音完全不動」。
- Higgsfield 顯示的 1080p／更高解析度究竟是模型原生、平台封裝或升頻；第一方不同頁面與 BytePlus API 規格並不一致。
- 手部左右交換沒有任何第一方公布成功率；即使有 mask 和正確參考圖，也不能保證一次成功。
- BytePlus Enhanced Video Edit 的 `object_replace`／`person_replace` 並沒有明確把「只換一隻手」列為獨立類型，不能假設它會比局部遮罩更穩。

## 第一方來源

- [ByteDance Seed：Introducing Seedance 2.5](https://seed.bytedance.com/en/blog/one-take-creation-flexible-referencing-introducing-seedance-2-5)
- [ByteDance Seed：Seedance 2.5 model page](https://seed.bytedance.com/en/seedance2_5)
- [BytePlus：Seedance 2.5 enhanced video generation API](https://docs.byteplus.com/en/docs/byteplus_las/video_gen_enhanced)
- [BytePlus：Enhanced video editing](https://docs.byteplus.com/en/docs/Byteplus_LAS/Enhanced_video_editing)
- [BytePlus：Seedance 2.5 prompt guide](https://docs.byteplus.com/api/docs/ModelArk/2222480)
- [Higgsfield：Seedance 2.5](https://higgsfield.ai/seedance/2.5)
- [Higgsfield：Seedance 2.5 prompting guide](https://higgsfield.ai/blog/seedance-2-5-prompting-guide)
- [Higgsfield：AI vs VFX workflow](https://higgsfield.ai/blog/ai-vs-vfx)
- [Higgsfield：What is Higgsfield MCP?](https://higgsfield.ai/creator-hub/help-center/integrations/what-is-higgsfield-mcp)
- [Higgsfield：DaVinci Resolve plugin／Draw to Edit](https://higgsfield.ai/plugins/davinci)
- [Higgsfield：External integrations](https://higgsfield.ai/creator-hub/help-center/integrations/external-integrations-higgsfield)
- [Dreamina／CapCut：How to edit a specific part of a video with AI](https://dreamina.capcut.com/ai-video/how-to-edit-a-specific-part-of-a-video-with-ai)
- [Dreamina／CapCut：How to maintain continuity in AI video editing](https://dreamina.capcut.com/ai-video/how-to-maintain-continuity-in-ai-video-editing)
- [Dreamina／CapCut：Seedance 2.5 prompt guide](https://dreamina.capcut.com/seedance/seedance-2-5-prompt)

## 證據邊界

上述「最高成功率」是依第一方功能與限制推導的製作決策，不是官方成功率承諾。Higgsfield live model catalog 的模式／參數是在 2026-08-29 以第一方只讀介面核對；沒有公開 permalink 的欄位，已避免把它寫成外部 API 保證。任何真正送件前，仍要在當下產品介面重新核對可用欄位、成本與一次生成設定，並重新取得 Eric 的明確授權。
