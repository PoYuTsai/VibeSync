# Sydney nano banana 提示詞包

> 搭配 `README.md` 的狀態表使用。提示詞用英文（Gemini 對敘述式英文最穩），每段前面有中文說明用途。nano banana＝Gemini 2.5 Flash Image；若用 Nano Banana Pro（Gemini 3 Pro Image），可附更多參考圖、輸出更高解析度，提示詞相同。

## 0. 使用原則（先讀）

1. **每次都附參考圖**：`assets/images/coach/sydney_greeting.png`、`sydney_thinking.png`，加一張從 greeting 裁出的頭部特寫（`CoachHeadAvatar` 的裁切框：左 269、上 154、邊長 492）。提示詞裡明講「the attached reference images」。
2. **先產主幀 S01，其餘全部用編輯模式從 S01 改**：上傳 S01，寫「change only X, keep everything else identical」。這是幀能疊在一起的關鍵；不要每張都重新生成。
3. **一次只改一件事**：不滿意就重抽同一張，不要在錯的結果上疊加修改，會越改越漂。
4. **背景固定純綠、無陰影**：目前 Gemini 圖像輸出沒有透明通道，綠幕最好去背。
5. **每張過三點檢查**：圓細黑框眼鏡、齊眉直瀏海、尖領＋前排扣＋腰結；任一不對直接丟。
6. **比例**：提示詞寫 portrait 2:3；用 AI Studio 或 API 時另外把 aspect ratio 設 2:3，避免被裁。

## 1. 共用角色描述（Character Bible）

貼在「生成」類提示詞（S00、S01）最前面。編輯類提示詞不用重貼，只需保留第 4 節的 KEEP 段。

```text
CHARACTER: "Sydney", the VibeSync dating coach.
Use the attached reference images as the single source of truth for her identity and art style, and reproduce her exactly.
- A young East Asian woman in her mid-20s. Kind, attentive, calm: like a warm senior colleague who listens before she speaks.
- Art style: semi-realistic anime illustration. Clean digital painting, soft cel shading blended with subtle realistic skin rendering, delicate linework without heavy black outlines, crisp individual hair strands. Not photorealistic, not chibi, not a 3D render.
- Hair: long, straight, very dark brown hair falling past her shoulders, with a straight blunt fringe cut just above the eyebrows.
- Glasses: thin, round, black wire-frame glasses.
- Face: warm brown eyes with natural lashes, a soft closed-lip smile with light natural pink lip color, fair skin with a faint blush on the cheeks.
- Outfit: a white short-sleeved button-up shirt dress with a pointed collar, a front button placket, and a soft white self-tie bow belt at the waist.
- Lighting: soft, even studio key light from the upper front-left, plus a faint cool violet rim light on her hair and shoulders from behind, because she will be placed on a dark purple app background. No hard shadows on her face.
- Background: a flat, uniform, pure chroma-key green (#00FF00). No gradient, no vignette, no floor, no cast shadow, so she can be cut out cleanly.
- Camera: fixed, eye level, 85mm portrait lens look, no perspective distortion. Portrait orientation, 2:3 aspect ratio.
- No text, no logo, no watermark, no props.
```

## 2. 探索用：表情表 S00（可選）

用途：正式產幀前，先用一張圖看九個表情是否穩定；不進 App。

```text
[貼上 Character Bible]
TASK: Create one character expression sheet of Sydney: a clean 3 by 3 grid of head-and-shoulders portraits, same framing and scale in every cell, all on the same flat chroma-key green background. Cells, left to right, top to bottom: (1) calm closed-lip smile looking at the camera, (2) eyes fully closed in a relaxed blink, (3) gaze down toward the lower-left as if reading a message, (4) attentive listening with a slight head tilt, (5) thinking with the index finger under the chin and eyes up to her left, (6) pleased "an idea just landed" smile with eyes closed, (7) speaking mid-sentence with lips slightly parted and bright eyes, (8) sheepish apologetic smile with brows slightly raised, (9) playful wink with a wide happy smile. Identical face, hair, glasses and collar in all nine cells. Thin white gutters between cells, no labels.
```

## 3. 主幀 S01（所有幀的基準）

```text
[貼上 Character Bible]
FRAME S01, "idle, eyes open". This is the master frame; every other frame will be edited from it, so keep the composition simple and centered.
Medium shot, waist-up: the bottom edge of the canvas cuts through her skirt a little below the bow belt. Her body faces the camera squarely with a relaxed, upright posture, shoulders level and soft. Her head is centered horizontally, and her eyes sit at about 22% from the top of the canvas, leaving comfortable headroom above her hair. Her left hand loosely holds her right wrist in front of her, just below the bow. She looks straight into the camera with a calm closed-lip smile, present and listening, not performing. Her hair falls naturally over both shoulders.
```

## 4. 編輯類提示詞（每張都上傳 S01 當底圖）

共用開頭與結尾，中間換 CHANGE 段：

```text
Using the attached image (Sydney, frame S01) as the base, make a minimal edit.
CHANGE: <貼上下方對應幀的 CHANGE 內容>
KEEP everything else pixel-identical: same framing and canvas, same camera, same body position, same lighting, same white shirt dress with the bow belt, same hair and fringe, same round black glasses, same flat chroma-key green background. Do not move her head or shoulders unless the CHANGE says so.
```

### 待機組

S02 半眨眼

```text
CHANGE: only her eyelids. Both eyes are half-closed in the middle of a blink, lids relaxed, lashes visible; gaze direction, eyebrows and smile unchanged.
```

S03 閉眼

```text
CHANGE: only her eyes. Both eyes are fully closed in a soft, relaxed blink: smooth upper lids, gentle lashes, eyebrows unchanged, smile unchanged. Relaxed, not squinting, not sleepy.
```

S04 瞄輸入列

```text
CHANGE: only her eyes. Shift her gaze down and to her right, toward the lower-left corner of the frame where a chat input box sits, as if she just noticed a new message. Her head does not turn. Same calm smile.
```

### 聆聽組

S10 側頭聆聽（前傾由程式 `Transform` 做，圖片只改頭與視線）

```text
CHANGE: only her head and eyes. Tilt her head about 5 degrees to her left and lower her gaze toward the lower-left of the frame, with a soft, attentive closed-lip smile, as if listening to someone typing. Shoulders and hands unchanged.
```

S11 托腮聆聽

```text
CHANGE: her arms and head. Raise her right hand so the fingertips rest lightly against her right cheek near the jaw, with her left arm folded across her waist supporting the right elbow. Tilt her head about 5 degrees to her right, eyes on the camera, warm closed-lip smile: an "I'm all ears" pose.
```

S12 點頭

```text
CHANGE: only her head. Tip her chin down about 8 degrees in a small acknowledging nod, eyes still open and looking at the camera from under the fringe, warm closed-lip smile. Shoulders and hands unchanged.
```

### 思考組

S20 托下巴思考

```text
CHANGE: her arms and gaze. Bring her right hand up so the bent index finger rests under her chin in a thinking gesture, and fold her left arm across her waist to support the right elbow, matching the gesture in the attached "thinking" reference. Her eyes look up and to her left, toward the upper-right of the frame; lips softly pressed together; eyebrows raised a touch in concentration.
```

S21 想到了（這張改用 S20 當底圖）

```text
CHANGE: keep the hand under the chin, close her eyes gently and let a small pleased smile form, the moment an idea lands. Tilt her head about 3 degrees to her right.
```

### 講解組

S30 提示手勢

```text
CHANGE: her right arm and face. Raise her right hand beside her shoulder with the index finger pointing up, a friendly "here is the tip" gesture matching the attached "tip" reference; her left hand rests at her waist. She looks at the camera with lips slightly parted as if mid-sentence, eyes bright.
```

S31 攤手呈現

```text
CHANGE: her right arm and expression. Extend her right hand forward and slightly down with the palm open and facing up, toward the lower-left of the frame, as if presenting the message that sits below her. Warm open smile with a hint of teeth. Left hand rests at her waist.
```

S32 陪讀（退讓檔位 B 的主幀）

```text
CHANGE: only her eyes and head. Her eyes look straight down toward the bottom-center of the frame and her head tips down about 6 degrees, calm closed-lip smile: she is reading along with the user. Hands unchanged.
```

### 收尾與錯誤

S40 抱歉歪頭

```text
CHANGE: her right arm and expression. Raise her right hand behind her head with the fingers in her hair near the nape, tilt her head about 10 degrees to her left, eyebrows slightly raised and drawn together, sheepish closed-lip smile: a gentle "sorry, that did not go through" look. Left hand rests at her waist.
```

### 彩蛋組（點擊回饋）

S50 揮手

```text
CHANGE: her right arm and face. Raise her right hand to shoulder height with the palm facing the camera in a small friendly wave, fingers together and relaxed. Bright open smile showing a little teeth, eyes crinkled happily. Left hand rests at her waist.
```

S51 推眼鏡

```text
CHANGE: her right hand and expression. Bring her right index finger up to push the bridge of her glasses. She looks at the camera with a confident, playful closed-lip smile and one eyebrow slightly raised. Left hand rests at her waist.
```

S52 眨眼比讚

```text
CHANGE: her right arm and face. Her right hand gives a thumbs-up at chest height. She winks her right eye while her left eye stays open and on the camera, with a wide happy smile showing teeth, matching the energy of the attached "encouragement" reference. Left hand rests at her waist.
```

## 5. 換形象預留（S60 系列，可選）

用途：對應影片右上的「換形象」。之後若做訂閱權益「Sydney 造型」再用。全部從 S01 改，只換衣服。

S60 無袖白上衣＋黑百褶裙（現有 `sydney_manual_input_full.png` 的造型）

```text
CHANGE: only her clothing. Replace the shirt dress with a white sleeveless mock-neck top and a black high-waisted pleated midi skirt with a slim black belt, matching the attached full-body reference. Face, hair, glasses, pose, hands, framing and background unchanged.
```

S61 針織外套（深夜陪聊感）

```text
CHANGE: only her clothing. Dress her in an oversized cream knit cardigan over a plain white tee, sleeves pushed up to the forearms. Face, hair, glasses, pose, hands, framing and background unchanged.
```

S62 西裝外套（正式建議感）

```text
CHANGE: only her clothing. Dress her in a fitted dark navy blazer over a white shirt with the collar open. Face, hair, glasses, pose, hands, framing and background unchanged.
```

## 6. 第二層：影片模型的起訖幀（可選）

nano banana 只出圖。要真的流動，把兩張幀當起訖餵 Veo、Kling 這類 image-to-video，再去背轉動態 WebP。建議配對與影片提示：

| 循環 | 起 | 訖 | 影片提示（英文） |
| --- | --- | --- | --- |
| 待機呼吸＋眨眼 | S01 | S03 | `A seamless 3-second loop. Fixed camera on a flat green background. Subtle idle breathing: shoulders rise about 1% on the inhale and settle on the exhale, hair strands drift very slightly, then one natural blink. No camera motion, no zoom, no background change, no new objects.` |
| 側頭聆聽 | S01 | S10 | `A 1.5-second motion. Fixed camera, flat green background. She tilts her head slightly and lowers her gaze toward the lower-left as she starts listening. Gentle ease-out, no camera motion.` |
| 進入思考 | S01 | S20 | `A 1.5-second motion. Fixed camera, flat green background. She raises her hand to her chin and looks up to her left, thinking. Smooth natural arm movement, no camera motion.` |
| 提示手勢 | S01 | S30 | `A 1.2-second motion. Fixed camera, flat green background. She raises her index finger beside her shoulder and starts to speak, lips parting slightly. No camera motion.` |

## 7. 每張出圖的驗收與後製

驗收：

- 三點檢查：圓細黑框眼鏡、齊眉直瀏海、尖領＋前排扣＋腰結。
- 與 S01 疊圖：眼睛中心位移在畫布高的 1% 內；只有 CHANGE 說的部位不同。
- 綠幕乾淨：背景無陰影、無漸層；髮絲邊緣沒有綠邊。
- 沒有多餘手指、眼鏡穿模、文字或浮水印。

後製：

1. 去背：綠幕 key（或 remove.bg、Photoshop），輸出透明 PNG。
2. 對齊：以 S01 眼睛中心平移對齊，必要時 ±1% 縮放。
3. 眨眼與嘴型若身體有漂移：改成「S01 身體＋只貼眼睛或嘴巴小塊」的合成法。
4. 量 bbox 與人物中心記入 enum，轉 WebP（`cwebp -q 90`）。
5. 檔名對表：`sydney_s01_idle_open`、`s02_idle_halfblink`、`s03_idle_blink`、`s04_idle_glance`、`s10_listen_tilt`、`s11_listen_cheek`、`s12_nod`、`s20_think_chin`、`s21_think_idea`、`s30_explain_tip`、`s31_explain_present`、`s32_read_along`、`s40_sorry`、`s50_wave`、`s51_glasses`、`s52_wink_thumb`。
