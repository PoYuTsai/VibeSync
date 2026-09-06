# Sydney 素材與提示詞檢閱

檢閱日期：2026-09-06。範圍：Eric 提供的 3 張 JPG、10 秒 MP4、2 份文字附件、8 張 App 截圖，以及 Bruce 指定分支的完整文件。附件中的任務清單是被檢閱內容，沒有據此自動執行素材生成。新附件只在本機檢閱，本文件不嵌入它們。

## 圖片：先解決形象一致性

| 素材 | 可確認內容 | 本次判斷 |
| --- | --- | --- |
| 綠幕白洋裝圖 | 848×1264，RGB JPG，約 2:3；眼睛半閉 | 衣服較接近，但眼鏡、髮型、畫風已有差異；不能直接作為睜眼待機母版 |
| 棋盤格托腮圖 | 1029×1024，RGB JPG | 棋盤格已烙在像素內，沒有 alpha。無袖上衣、黑褲、腰帶不符合這次維持既有洋裝形象的要求 |
| 紫底托腮圖 | 1029×1024，RGB JPG；右下角星形標記 | 同一套新服裝，且背景已合成。可保留為探索，不能因構圖完成就當作正式原形象素材 |

既有 repo 原圖的尺寸也不同：greeting／tip 1023×1537、thinking 941×1672、encouragement 1122×1402。不可假設全部能套用同一個裁切命令。

原形象的眼鏡偏較大的圓角矩形、上緣較明顯，髮頂有束起的層次。文字提示直接指定「細圓框、全直順披髮」可能和參考圖互相競爭。**以選定原圖為視覺權威，文字只描述需要改的姿態／動作。**

Bruce 的 Nano 文件確有可選換装探索，可解釋托腮造型的來源；本次選用仍應遵守 Eric 的「維持既有形象」範圍。

## 影片：能參考動作，不能直接放入 App 循環

- MP4，1280×720，16:9 橫式，10.000 秒，24 fps，240 幀，H.264，約 1.76 MB。
- 有 AAC 音軌且不是全靜音；未依音軌內容做語意判斷。
- 精確首幀仍有先前 UI／文字殘留；0.05 秒已出現人物，不能只看預覽縮圖忽略閃幀。
- 逐秒抽樣及首尾檢查可見：思考／側看、歪頭、放下手、抬手、眨眼比讚、微笑收尾。動作跨好幾種狀態。
- 最末幀沒有回到起始姿勢，直接 loop 會跳接。
- 紫底、角落星形標記都已進入畫面；人物偏左、右方大量留白，構圖更像橫向卡片。
- 因此問題不限於模型能力：來源首幀、形象、構圖、單段動作範圍與循環接點都還未固定。

## 提示詞：值得保留與需要修正

值得保留：同一主參考、固定鏡頭、小幅動態、去背後測深色背景、先小批驗證、保留原始輸出。

需統一：
1. 兩份附件混有 9:16／2:3、眼睛位於 20%／22% 等基準；先定義同一畫布、人物大小及安全範圍。2:3 同高裁成 9:16 只會移除左右約 15.6% 寬度，不會自動變成理想半身構圖，也可能切手肘。
2. 不能對任意比例輸入直接 scale 成 540×960，否則形體變形。先確認裁切／留白，再縮放。
3. 接點必須取自實際播放的截點。若某段實際只播到 2.5 或 3 秒，下段參考卻用原片第 8 秒，姿勢仍會跳。
4. 全程閉口、輕微張嘴與露齒笑在不同段落互相衝突；每段只留一套要求。
5. 「完全像素一致」「第 2.5 秒眨眼」「移動 1%」是驗收意圖，不是生成模型必然精確遵守的控制器。
6. 去背重點在髮絲、白衣、眼鏡；應在 App 實際深紫背景看綠邊、破洞與閃爍。先測一段，再決定透明格式、幀率、尺寸與品質。
7. 不先把 15 段全做完。Bruce 完整文件其實已有分批六段思路；本次因閱讀區不需影片，進一步縮成一段待機，通過後加一段思考。

**完整性澄清：**Eric 貼上的「完整版」附件在 C08a 中途截斷，但 [Bruce 分支的 Veo 原檔](https://github.com/PoYuTsai/VibeSync/blob/2b41872da58cf98637f744768ce84a5b4dcb7624/docs/ideas/sydney-interaction/veo-video-prompts.md) 含 C08a–C13、後製、預算與接線摘要。不能稱他的原檔不完整；也不能把附件提及的章節名稱或裁切命令當作已核對的原檔內容。

## Seedance 2.5：先做能看出成敗的一段

9:16 可以作為直式人物的來源畫布；它不是 UI 必須全屏或佔半屏的理由。來源應留足臉、髮頂、肩膀、手肘安全區，再用 App 容器選取需要的部分。[Higgsfield 官方 Seedance 2.5 說明](https://higgsfield.ai/seedance/2.5)

工具只查詢模型、點數及估價，未上傳或生成。2026-09-06 的估價：
- `seedance_2_5 / omni_reference / 6 秒 / 720p / 9:16 / generate_audio=false / count=1`：39 credits。
- 同條件 8 秒：52 credits。
- 若每段 8 秒、15 段各跑一次，即 780 credits，尚未包含任何重試。

這是當次估價，不是固定報價；生成前重新確認。已知 video_edit 路徑依原影片時長計價並忽略輸出時長／比例參數，不宜把那支橫式多動作片當作本次直式小循環的起點。

### 待機試片提示詞草案

先選定／確認睜眼、原服裝、構圖對齊的母圖，再交給模型。不要混入三張不同衣服或不同畫風的參考。

> Animate only the provided, approved Sydney reference. Preserve her identity, illustration style, facial proportions, glasses, hairstyle, original white dress, lighting, framing and colors exactly as shown in that reference. Fixed camera, 9:16 canvas. Keep the full head, shoulders and visible hands within the agreed safe area.
>
> A calm six-second idle moment: extremely subtle breathing and one gentle, natural blink. Her eyes return to the same relaxed open state. Keep her mouth closed, hands and arms in the reference pose, and body position stable. No wave, thumbs-up, speaking, lip sync, head turn, camera movement, zoom or scene transition. Start and finish as close as possible to the reference pose so the result can be evaluated for a seamless loop.
>
> Keep the supplied plain background stable. No UI, text, added objects or new accessories. Silent output.

模型若有實際的 start/end frame 控制再使用；不能僅依 prompt 承諾首尾完全一致。平台是否產出標記、透明背景，應檢查輸出本身，不能假設文字提示能關掉平台標記或產生 alpha。

一次試片只判斷五件事：還是不是同一個 Sydney、臉與眼鏡會不會漂、動作是否安靜、頭尾有沒有跳、縮到實際容器後邊緣是否乾淨。先過這關，再決定思考素材及交付格式。
