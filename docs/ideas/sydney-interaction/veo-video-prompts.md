# Sydney 完整版影片生成指令（Gemini／Veo）

> 接續 `README.md` 的互動模型與 `nano-banana-prompts.md` 的定格包。依據 Eric 2026-09-05 用 Gemini 生成的 10 秒試作（思考 → 想到 → 講解 → 眨眼比讚）寫成，目標是讓 Gemini 一段一段產出可以直接進 App 的完整動態組。提示詞為英文，每段前面有中文說明。

## 0. 試作評估：哪些對、哪些要改

| 面向 | 試作現況 | 完整版怎麼做 |
| --- | --- | --- |
| 角色一致性 | 眼鏡、瀏海、襯衫洋裝、腰結都與現有立繪一致，鏡頭穩、動作幅度剛好 | 保留。每段都用同一張起始圖，靠圖鎖外型 |
| 個性 | 思考 → 想到 → 講 → 比讚的節奏很對，像會聽人講話的學姐 | 保留，拆成獨立段落後仍照這個溫度 |
| 畫面比例 | 16:9 橫式 1280×720 | 改 9:16 直式，起始圖也要是 9:16，才不會被裁或外擴 |
| 背景 | 深紫漸層 | 改純綠幕以便去背成透明疊在 App 漸層上；若不想去背，改用第 2 節的「紫底替代行」，整段當不透明背景 |
| 結構 | 一鏡 10 秒串完所有動作 | 拆成以「休息姿勢 S01」為樞紐的短片：每段從 S01 開始、回到 S01 結束，App 才能依狀態切換與循環 |
| 嘴巴 | 有張嘴說話 | 預設閉嘴。教練回覆是文字沒有語音，嘴動會像壞掉；之後接 TTS 再開嘴型 |
| 音軌與浮水印 | 有音軌；右側有 ✦ 浮水印 | 後製去音軌；去背前先把浮水印區塗綠（第 7 節） |
| 起始姿勢 | 用思考立繪當起始圖，所以開頭是托下巴 | 起始與結尾統一用休息姿 S01；思考與陪讀各自有子樞紐 S20、S32 |

## 1. 產出清單與狀態對照

三張定格（樞紐）加十五段 8 秒短片。App 內實際用到的秒數見最後一欄，其餘由後製裁掉。

| 編號 | 用途 | App 狀態 | 型態 | 起始幀 | 結尾幀 | App 使用 |
| --- | --- | --- | --- | --- | --- | --- |
| S01 | 休息定格（總樞紐） | 全部 | 定格 | 無 | 無 | 靜態備援、減少動態時的畫面 |
| S20 | 思考定格（子樞紐） | 思考 | 定格 | 取 C05a 最後一格 | 無 | 同上 |
| S32 | 陪讀定格（子樞紐） | 陪讀 | 定格 | 取 C08a 最後一格 | 無 | 同上 |
| C01 | 待機呼吸與眨眼 | 待機 | 循環 | S01 | S01 | 全 8 秒，可正反來回播 |
| C02 | 待機變化：瞄一眼輸入列 | 待機（偶爾插入） | 循環變化 | S01 | S01 | 全 8 秒 |
| C03 | 聆聽 | 輸入框 focus 或有字 | 循環 | S01 | S01 | 全 8 秒 |
| C04 | 點頭確認 | 送出瞬間 | 一次性 | S01 | S01 | 約 0.5–3.0 秒 |
| C05a | 進入思考 | 送出後 | 過場 | S01 | S20 | 約 0.5–3.0 秒；倒放即為離開思考 |
| C05b | 思考停留 | `isLoading` | 循環 | S20 | S20 | 全 8 秒 |
| C06 | 想到了、回休息 | 第一段回覆到達 | 過場 | S20 | S01 | 約 0.5–5.0 秒 |
| C07 | 講解提示手勢 | 回覆開始 | 一次性 | S01 | S01 | 約 0.5–6.0 秒 |
| C08a | 進入陪讀 | 長回覆展開 | 過場 | S01 | S32 | 約 0.5–2.5 秒；倒放即為抬頭 |
| C08b | 陪讀 | 退讓檔位 B | 循環 | S32 | S32 | 全 8 秒 |
| C09 | 抱歉 | 錯誤、逾時 | 一次性 | S01 | S01 | 約 0.5–6.5 秒 |
| C10 | 揮手 | 點擊彩蛋 | 一次性 | S01 | S01 | 約 0.5–4.0 秒 |
| C11 | 推眼鏡 | 點擊彩蛋 | 一次性 | S01 | S01 | 約 0.5–3.5 秒 |
| C12 | 眨眼比讚 | 點擊彩蛋、成功訊號 | 一次性 | S01 | S01 | 約 0.5–4.0 秒 |
| C13 | 收尾微笑 | 回覆完成 | 一次性 | S01 | S01 | 約 0.5–3.0 秒 |

第一批先做六段就能跑通整條路：C01、C03、C04、C05a、C05b、C07。其餘依實機檔案大小再擴。

## 2. 每段都要貼的共用規格

生成方式：上傳起始圖（有結尾幀欄位就一併上傳結尾圖），比例選 9:16，長度 8 秒，能選 1080p 就選。提示詞＝第 4 節該段的 ACTION 段 ＋ 下面這段 SHARED RULES。起訖幀功能在 Google Flow 的 Frames to Video（Veo 3.1）或 API 的 `lastFrame` 參數；Gemini App 若只能給起始圖，就靠 SHARED RULES 最後的「回到起始姿勢並停住一秒」。

```text
SHARED RULES
Animate this exact 2D illustration of Sydney from the attached start frame. She is a young East Asian woman with long straight dark hair, a blunt fringe just above the eyebrows, thin round black glasses, and a white short-sleeved shirt dress with a bow belt at the waist. Keep every one of these identical for the whole clip.
Style: keep the clean 2D illustrated look of the start frame, soft shading and crisp linework. Do not add 3D shading, photorealism, depth of field, film grain or glow.
Camera: locked-off tripod shot at eye level, medium shot from the waist up. No zoom, no pan, no push-in, no handheld drift, no reframing. Her head stays in the top third of the frame and she stays horizontally centered.
Background: a flat, uniform, pure chroma-key green that stays perfectly still and unchanged. No gradient, no particles, no light rays, no shadows on the background, and no green light reflecting on her skin or her white dress.
Motion: small, calm, natural amplitude, like a kind senior colleague who is listening. Hips and feet stay planted, hands never cover her face, hair moves only with her breathing and head motion.
Mouth: lips stay closed unless the ACTION says otherwise. No talking, no lip sync, no singing.
Ending: she finishes in exactly the pose of the specified end frame (the start frame unless the ACTION names another) and holds it, breathing, for the final second.
Audio: silent scene, no music, no dialogue, no sound effects.
Avoid: camera movement, lighting changes, background changes, extra fingers, glasses changing shape or disappearing, hair changing length, clothing changing, text, captions, logos, other people, props.
```

紫底替代行（不去背、整段當不透明背景時，換掉上面的 Background 那行）：

```text
Background: a flat dark purple studio backdrop, a very soft vertical gradient from deep ink purple (#150C24) at the top to muted violet (#2A1840) at the bottom, perfectly still for the whole clip. No particles, no light rays, no bokeh, no shadows on the backdrop.
```

## 3. 三張定格

S01 用 nano banana 產（比例改 9:16，其餘沿用 `nano-banana-prompts.md` 第 1 節的角色描述）：

```text
[貼上 Character Bible]
FRAME S01, "rest": the hub pose that every clip starts and ends on. Portrait 9:16. Medium shot from the waist up; the bottom edge of the canvas cuts through her skirt just below the bow belt. She faces the camera squarely, relaxed and upright, shoulders level and soft. Her head is centered horizontally and her eyes sit about 20% from the top of the canvas. Her left hand loosely holds her right wrist in front of her, just below the bow. Calm closed-lip smile, looking straight into the camera. Flat pure chroma-key green background with no shadows.
```

S20 與 S32 不必另外畫：先用起始圖 S01 生成 C05a 與 C08a，各取最後一格存成 PNG，就是思考與陪讀的定格，而且與影片畫風完全一致。

```bash
ffmpeg -sseof -0.05 -i C05a.mp4 -frames:v 1 -update 1 S20_think.png
ffmpeg -sseof -0.05 -i C08a.mp4 -frames:v 1 -update 1 S32_read.png
```

## 4. 各段 ACTION 腳本

每段：上傳指定的起始圖（與結尾圖），貼 ACTION，接著貼 SHARED RULES。

C01 待機呼吸與眨眼（起 S01、訖 S01）

```text
ACTION, 8 seconds: She stands at rest and simply breathes. A slow inhale lifts her shoulders and chest by about 1% every 4 seconds, then they settle. She blinks naturally at about 2.5s and again at 6s: quick, soft blinks of roughly a third of a second. Between 3s and 5s her weight shifts almost imperceptibly to her left and back. A few hair strands drift with her breathing. Her gaze stays on the camera with the calm closed-lip smile. At 8s she is in exactly the starting pose.
```

C02 待機變化：瞄一眼輸入列（起 S01、訖 S01）

```text
ACTION, 8 seconds: 0 to 1.5s she rests and breathes. 1.5 to 2.5s her eyes glance down and to her right, toward the lower-left of the frame, as if a message just arrived, and her head tips down about 2 degrees. 2.5 to 4.5s she reads for a moment and a small smile grows. 4.5 to 5.5s her eyes return to the camera with one soft blink. 5.5 to 8s she holds the rest pose, breathing.
```

C03 聆聽（起 S01、訖 S01）

```text
ACTION, 8 seconds: 0 to 1s from rest she tilts her head about 5 degrees to her left and lowers her gaze to the lower-left of the frame, where the person is typing, while her upper body leans toward the camera by about 2%. 1 to 7s she listens: tiny attentive nods at 2.5s and 5s, a soft blink at 4s, brows slightly lifted, warm closed-lip smile. 7 to 8s she straightens back into exactly the starting pose.
```

C04 點頭確認（起 S01、訖 S01）

```text
ACTION, 8 seconds: 0 to 1s rest. 1 to 2s one clear, warm nod: her chin dips about 8 degrees and comes back, eyes on the camera, and her smile deepens slightly as if saying "got it". 2 to 2.5s a soft blink. 2.5 to 8s she holds the rest pose, breathing.
```

C05a 進入思考（起 S01、訖 S20；若沒有結尾幀欄位，結尾就是描述中的思考姿勢）

```text
ACTION, 8 seconds: 0 to 0.5s rest. 0.5 to 2.5s she raises her right hand and rests the bent index finger under her chin while her left arm folds across her waist to support the right elbow; her eyes drift up and to her left, lips pressed softly together, brows lifting slightly in concentration. 2.5 to 8s she holds this thinking pose with only her breathing and one blink at 5s. The clip ends in the thinking pose, not the rest pose.
```

C05b 思考停留（起 S20、訖 S20）

```text
ACTION, 8 seconds: She keeps thinking with the index finger under her chin for the whole clip. Her eyes move slowly from upper-left to upper-right between 2s and 3s and back between 5s and 6s, as if weighing two options. The index finger taps her chin twice at 4s. She blinks at 1.5s and 6.5s. Her breathing lifts her shoulders slightly. She never looks at the camera in this clip. At 8s she is in exactly the starting thinking pose.
```

C06 想到了、回休息（起 S20、訖 S01）

```text
ACTION, 8 seconds: 0 to 1s thinking pose. 1 to 1.8s her eyes widen a touch and a pleased smile appears: the idea has landed. 1.8 to 2.6s she closes her eyes for a happy half second and tilts her head about 3 degrees. 2.6 to 4.5s her right hand lowers smoothly and her left arm relaxes until her left hand loosely holds her right wrist in front of her; she looks back at the camera with the calm closed-lip smile. 4.5 to 8s rest pose, breathing.
```

C07 講解提示手勢（起 S01、訖 S01）

```text
ACTION, 8 seconds: 0 to 1s rest. 1 to 2s she raises her right hand beside her shoulder with the index finger pointing up, a friendly "here is the tip" gesture; her eyes brighten and she gives a small nod. 2 to 4s the raised hand makes two small emphasizing beats, as if marking two points; lips stay closed, expression warm and confident. 4 to 5.5s her hand lowers back to rest. 5.5 to 8s she holds the rest pose, breathing.
```

C08a 進入陪讀（起 S01、訖 S32；若沒有結尾幀欄位，結尾就是描述中的低頭閱讀姿勢）

```text
ACTION, 8 seconds: 0 to 0.5s rest. 0.5 to 2s her head tips down about 6 degrees and her eyes settle on the text below her, toward the bottom-center of the frame; calm closed-lip smile. 2 to 8s she reads: her eyes scan slowly left to right in lines, one blink at 5s, breathing visible. The clip ends in this reading pose, not the rest pose.
```

C08b 陪讀（起 S32、訖 S32）

```text
ACTION, 8 seconds: Her head stays tipped down about 6 degrees and her eyes read the text below her for the whole clip: they scan slowly left to right in lines, about one line every 1.5 seconds, with soft blinks at 3s and 6.5s. At 4s she gives a tiny approving nod without lifting her head. Calm closed-lip smile throughout, breathing visible. She never looks up at the camera in this clip. At 8s she is in exactly the starting reading pose.
```

C09 抱歉（起 S01、訖 S01）

```text
ACTION, 8 seconds: 0 to 1s rest. 1 to 2.2s she lifts her right hand behind her head with the fingers touching her hair near the nape and tilts her head about 10 degrees to her left; her brows lift and draw together into a sheepish, apologetic closed-lip smile. 2.2 to 4.5s she holds it, with a small shrug of the shoulders at 3s. 4.5 to 6s hand and head return to rest. 6 to 8s rest pose, breathing.
```

C10 揮手（起 S01、訖 S01）

```text
ACTION, 8 seconds: 0 to 1s rest. 1 to 2s she raises her right hand to shoulder height, palm to the camera, and gives a small friendly wave of two beats; her smile opens brightly and her eyes crinkle. 2 to 3.5s the wave finishes and the hand lowers. 3.5 to 8s rest pose, breathing.
```

C11 推眼鏡（起 S01、訖 S01）

```text
ACTION, 8 seconds: 0 to 1s rest. 1 to 2s she raises her right index finger to the bridge of her glasses and pushes them up with a confident, playful look, one eyebrow slightly raised. 2 to 3s the hand lowers and the smile settles. 3 to 8s rest pose, breathing.
```

C12 眨眼比讚（起 S01、訖 S01）

```text
ACTION, 8 seconds: 0 to 1s rest. 1 to 2s her right hand comes up into a thumbs-up at chest height as she winks her right eye and smiles widely with a hint of teeth; her head tilts about 5 degrees. 2 to 3.5s the smile stays as the hand lowers. 3.5 to 8s rest pose, breathing.
```

C13 收尾微笑（起 S01、訖 S01）

```text
ACTION, 8 seconds: 0 to 1s rest. 1 to 2.5s a small satisfied smile and a slow exhale: her shoulders drop softly and she gives one slow blink. 2.5 to 8s rest pose, breathing.
```

## 5. 一鏡到底版（可選，Flow 的 Extend）

若想像試作那樣一次看完整段個性，用 Flow 的 Extend 接段：起始圖 S01，依 C01 → C03 → C04 → C05a → C05b → C06 → C07 → C08a → C08b → C09 → C10 → C11 → C12 → C13 的順序，每段 ACTION 直接當該次 Extend 的提示詞，段與段之間都回到 S01 停一秒。Bruce 依時間碼切段。缺點是 Extend 越接越容易漂（臉、眼鏡、位置），超過四五段就要重新檢查；正式素材仍以第 4 節的獨立短片為準。

## 6. 生成順序與驗收

1. 先產 S01 定格，過三點檢查（圓細黑框眼鏡、齊眉直瀏海、尖領加前排扣加腰結）。
2. 先生成 C01，確認四件事再往下：結尾是否回到起始姿勢；眼鏡有沒有變形或消失；髮絲邊緣是否乾淨；浮水印落在哪個角落。
3. 每段生成後把最後一格疊在起始圖上比對，位移超過畫面高度 1% 或臉變了就重抽，不要拿去後製硬修。
4. 循環段（C01、C02、C03、C05b、C08b）另外把首尾兩格並排看，接點有跳動就重抽。
5. 一段抽三次挑一次是常態；同一段不要改提示詞疊加修，會越改越漂。

## 7. 後製與檔案預算

每段固定四步：去音軌、把浮水印區塗綠、綠幕去背、輸出動態 WebP（Flutter `Image.asset` 原生會播）。示範命令（Windows 的 ffmpeg 同樣可用，浮水印方框位置依實際落點調整）：

```bash
# 循環段：無限循環（-loop 0），15fps 夠用，540x960 進 App
ffmpeg -i C01.mp4 -an -vf "drawbox=x=iw-150:y=ih-150:w=150:h=150:color=0x00FF00:t=fill,chromakey=0x00FF00:0.12:0.06,despill=type=green,scale=540:960:flags=lanczos,fps=15" -c:v libwebp_anim -lossless 0 -q:v 75 -loop 0 sydney_c01_idle.webp

# 一次性段：先裁到 App 使用秒數，只播一次（-loop 1），停在最後一格
ffmpeg -ss 0.5 -t 2.5 -i C04.mp4 -an -vf "drawbox=x=iw-150:y=ih-150:w=150:h=150:color=0x00FF00:t=fill,chromakey=0x00FF00:0.12:0.06,despill=type=green,scale=540:960:flags=lanczos,fps=15" -c:v libwebp_anim -lossless 0 -q:v 75 -loop 1 sydney_c04_nod.webp

# 待機正反來回：眨眼倒放看不出來，接點零跳動
ffmpeg -i C01.mp4 -an -filter_complex "[0:v]split[a][b];[b]reverse[r];[a][r]concat=n=2:v=1[v]" -map "[v]" C01_pingpong.mp4

# 過場倒放（C05a 倒放＝離開思考，C08a 倒放＝抬頭）
ffmpeg -ss 0.5 -t 2.5 -i C05a.mp4 -an -vf reverse C05a_exit.mp4
```

檔案預算是真正的決策點：十五段全做大約 75 秒動畫，540×960、15fps、q75 粗估 15–30MB，放進 App bundle 太重。建議第一批只做第 1 節的六段（約 5–8MB），實機量過再決定其餘要進 bundle、走 Supabase Storage 下載後快取，或改用 Rive 綁骨架。若綠幕去背後髮絲有綠邊，優先調 `chromakey` 的相似度與 `despill`，再不行就改用紫底替代行整段當不透明背景。

## 8. 給 Bruce 的接線摘要

所有段落都經過休息姿 S01 這個樞紐，思考與陪讀各有子樞紐，切換一律 240ms crossfade：

```text
S01 待機：C01 循環（每 3–5 輪插一次 C02）
輸入框 focus 或有字        → C03 循環
送出                       → C04 → C05a → C05b 循環（isLoading）
第一段回覆到達             → C06 → C07 → 短回覆回 C01；長回覆 C08a → C08b 循環
回覆完成                   → （在陪讀則 C08a 倒放）→ C13 → C01
錯誤、逾時                 → （在思考則 C05a 倒放）→ C09 → C01
點擊 Sydney（8 秒冷卻）    → C10 或 C11 或 C12 隨機 → 回到當下狀態
減少動態（motionDisabled） → 只顯示 S01、S20、S32 定格，狀態間 crossfade
```
