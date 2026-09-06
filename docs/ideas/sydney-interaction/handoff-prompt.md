# Sydney 動態素材完整版：交辦提示詞

> 一段可直接貼給執行夥伴（人或 AI 皆可）的完整任務提示詞。形象鎖定以現有四張立繪為唯一真相源；細節背景見同資料夾的 `README.md`、`veo-video-prompts.md`、`nano-banana-prompts.md`。

````text
【任務】Sydney 教練動態素材完整版（維持原有形象）

你要做的事：在完全不改變 Sydney 既有形象的前提下，用 Gemini（nano banana 出定格、Veo 出影片）產出一組可進 App 的動態素材：1 張休息定格、2 張子定格、15 段 8 秒短片，後製成透明背景的動態 WebP，附驗收表回報。這是素材製作任務，不改 App 程式；接進 App 是之後另一個 PR。
背景文件（可選讀）在 VibeSync repo 分支 claude/sydney-interaction-design-fc0k0r 的 docs/ideas/sydney-interaction/：README.md（互動模型）、veo-video-prompts.md（影片指令全文）、nano-banana-prompts.md（定格包）。本提示詞已自足，讀不到也能做。

【一、形象鎖定：最高優先，任何情況不得偏離】
真相源是 repo 現有四張立繪：assets/images/coach/sydney_greeting.png、sydney_thinking.png、sydney_tip.png、sydney_encouragement.png（1023×1537、透明背景）。每一次生成都要上傳其中至少兩張當參考圖（建議 greeting 加 thinking，再加一張從 greeting 裁出的臉部特寫），並在提示詞明講 the attached reference images。不要用 sydney_manual_input_full.png 當參考，那是另一套服裝。
Sydney 的形象（英文定義在 SHARED RULES 與 PROMPT S01 裡，中文對照如下）：二十多歲東亞女性；長直、深棕近黑的頭髮過肩；齊眉直瀏海；細圓黑框眼鏡；暖棕色眼睛；閉唇淺笑、自然淡粉唇色、白皙帶淡腮紅；白色短袖襯衫洋裝、尖領、前排扣、腰間白色蝴蝶結綁帶；半寫實動漫插畫風：乾淨數位繪、柔和賽璐璐加些微寫實皮膚、無粗黑描邊。
禁止：換髮型或髮長、換眼鏡或拿掉眼鏡、換服裝或配色、改妝容、加道具、改成寫實或 3D、加字幕或 Logo、張嘴說話、生成任何「換形象／換造型」系列。形象上若出現取捨（例如眼鏡反光、瀏海長度、笑容大小），停下來問 Eric，不要自己決定。
三點檢查（每一張圖、每一段影片的首格與末格都要過）：1 圓細黑框眼鏡；2 齊眉直瀏海；3 尖領加前排扣加腰結。任一不過就重抽，不要拿去後製硬修。

【二、產出清單】
定格：
- S01 休息定格（總樞紐，所有短片的起訖姿勢）：9:16、綠幕、腰上中景。
- S20 思考定格（子樞紐）：取 C05a 最後一格。
- S32 陪讀定格（子樞紐）：取 C08a 最後一格。
短片（每段 8 秒、9:16、綠幕；「App 使用」是後製要裁到的秒數）：
- C01 待機呼吸與眨眼｜循環｜起 S01 訖 S01｜全 8 秒
- C02 待機變化：瞄一眼輸入列｜循環變化｜起 S01 訖 S01｜全 8 秒
- C03 聆聽｜循環｜起 S01 訖 S01｜全 8 秒
- C04 點頭確認｜一次性｜起 S01 訖 S01｜0.5–3.0 秒
- C05a 進入思考｜過場｜起 S01 訖 S20｜0.5–3.0 秒
- C05b 思考停留｜循環｜起 S20 訖 S20｜全 8 秒
- C06 想到了、回休息｜過場｜起 S20 訖 S01｜0.5–5.0 秒
- C07 講解提示手勢｜一次性｜起 S01 訖 S01｜0.5–6.0 秒
- C08a 進入陪讀｜過場｜起 S01 訖 S32｜0.5–2.5 秒
- C08b 陪讀｜循環｜起 S32 訖 S32｜全 8 秒
- C09 抱歉｜一次性｜起 S01 訖 S01｜0.5–6.5 秒
- C10 揮手｜一次性｜起 S01 訖 S01｜0.5–4.0 秒
- C11 推眼鏡｜一次性｜起 S01 訖 S01｜0.5–3.5 秒
- C12 眨眼比讚｜一次性｜起 S01 訖 S01｜0.5–4.0 秒
- C13 收尾微笑｜一次性｜起 S01 訖 S01｜0.5–3.0 秒
第一批六段：C01、C03、C04、C05a、C05b、C07。做完先回報，Eric 看過再做其餘九段。

【三、執行步驟】
步驟 1：休息定格 S01（nano banana）
- 用「編輯」不要重畫：上傳 sydney_greeting.png 當底圖，thinking 當參考，只把雙手放下改成休息姿、笑容收成閉唇淺笑、背景改純綠，其餘一律不動。提示詞見 PROMPT S01。輸出 9:16。
- 若 9:16 輸出把臉或比例改了，改成 2:3 輸出（與立繪同機位），再用 POST-PROCESSING 的裁切命令中心裁成 9:16 腰上。
- 驗收：三點檢查；與 greeting 疊圖，臉部位置與大小一致；綠幕無陰影、無漸層。
步驟 2：試片 C01（Veo）
- 起始圖＝S01；介面有結尾幀欄位就也放 S01（Google Flow 的 Frames to Video 或 API 的 lastFrame）。比例 9:16、8 秒、能選 1080p 就選。
- 提示詞＝ACTION C01 全文，接著貼 SHARED RULES 全文。
- 驗收四件事：末幀回到起始姿勢；眼鏡沒有變形或消失；髮絲邊緣乾淨；找到浮水印落點。把末幀疊在 S01 上，位移不得超過畫面高度 1%。
- 過不了就用同一組提示詞重抽，最多三次。三次都過不了形象檢查，停下來回報 Eric，改走【六】備援路線。
步驟 3：其餘十四段
- 順序：C03、C04、C05a、C05b、C07 → 回報 → C06、C08a、C08b、C13 → C02、C09、C10、C11、C12。
- C05a 生成通過後，取最後一格存成 S20_think.png，當 C05b 與 C06 的起始圖；C08a 最後一格存成 S32_read.png，當 C08b 的起始圖。取末幀命令見 POST-PROCESSING。
- 每段驗收同步驟 2；循環段（C01、C02、C03、C05b、C08b）另外把首尾兩格並排比對，接點不得跳動。
- 同一段不要在錯的結果上疊加修改提示詞，會越改越漂；重抽就是同一組提示詞再來一次。
步驟 4：後製
- 每段四步：去音軌、把浮水印區塗綠、綠幕去背、輸出動態 WebP（540×960、15fps、q75；循環段無限循環，一次性段只播一次並裁到 App 使用秒數）。命令範本見 POST-PROCESSING。
- 髮絲有綠邊：先調 chromakey 相似度與 despill；仍不行回報 Eric，不要自行改成紫底或其他背景。
步驟 5：交付與回報
- 雲端資料夾三夾（素材不要 commit 進 repo，太大）：raw（原始 mp4 全部保留，含淘汰的）、stills（S01、S20、S32 原圖與去背版）、webp（處理後成品）。
- 一張首尾幀對照總表：每段首格與末格並排，15 段排成一張圖，讓 Eric 一眼看形象有沒有漂。
- 驗收表：每段抽了幾次、選了第幾次、末幀位移、三點檢查結果、備註。
- 用繁體中文回報：完成哪些段、哪些沒過、哪些需要 Eric 拍板。

【四、SHARED RULES：每段影片提示詞的第二段，原文貼上】
===== SHARED RULES 開始 =====
SHARED RULES
Animate this exact 2D illustration of Sydney from the attached start frame. She is a young East Asian woman with long straight dark hair, a blunt fringe just above the eyebrows, thin round black glasses, and a white short-sleeved shirt dress with a bow belt at the waist. Keep every one of these identical for the whole clip, exactly as in the attached reference images.
Style: keep the clean 2D illustrated look of the start frame, soft shading and crisp linework. Do not add 3D shading, photorealism, depth of field, film grain or glow.
Camera: locked-off tripod shot at eye level, medium shot from the waist up. No zoom, no pan, no push-in, no handheld drift, no reframing. Her head stays in the top third of the frame and she stays horizontally centered.
Background: a flat, uniform, pure chroma-key green that stays perfectly still and unchanged. No gradient, no particles, no light rays, no shadows on the background, and no green light reflecting on her skin or her white dress.
Motion: small, calm, natural amplitude, like a kind senior colleague who is listening. Hips and feet stay planted, hands never cover her face, hair moves only with her breathing and head motion.
Mouth: lips stay closed unless the ACTION says otherwise. No talking, no lip sync, no singing.
Ending: she finishes in exactly the pose of the specified end frame (the start frame unless the ACTION names another) and holds it, breathing, for the final second.
Audio: silent scene, no music, no dialogue, no sound effects.
Avoid: camera movement, lighting changes, background changes, extra fingers, glasses changing shape or disappearing, hair changing length, clothing changing, text, captions, logos, other people, props.
===== SHARED RULES 結束 =====

【五、PROMPT S01：nano banana 編輯模式，底圖 sydney_greeting.png】
===== PROMPT S01 開始 =====
Using the attached image of Sydney (the "greeting" illustration) as the base, and the other attached images as identity references, make a minimal edit.
CHANGE: only her arms, her smile, the background and the canvas ratio. Lower both arms so she stands at rest with her left hand loosely holding her right wrist in front of her, just below the bow belt; shoulders level and relaxed. Soften her smile into a calm closed-lip smile, eyes still on the camera. Replace the background with a flat, uniform, pure chroma-key green (#00FF00) with no shadow, no gradient and no floor. Output a portrait 9:16 canvas: medium shot from the waist up, the bottom edge cutting through her skirt just below the bow belt, her head centered horizontally with her eyes about 20% from the top.
KEEP everything else identical: the same face, the same thin round black glasses, the same blunt fringe and hair length, the same white short-sleeved shirt dress with the pointed collar, front buttons and bow belt, the same semi-realistic anime illustration style, the same lighting and the same scale of her face. No text, no props, no logo.
===== PROMPT S01 結束 =====

【六、ACTION 腳本：每段影片提示詞的第一段。複製該段從 ACTION 到空行為止，接著貼 SHARED RULES】

— C01 待機呼吸與眨眼（起 S01、訖 S01）—
ACTION, 8 seconds: She stands at rest and simply breathes. A slow inhale lifts her shoulders and chest by about 1% every 4 seconds, then they settle. She blinks naturally at about 2.5s and again at 6s: quick, soft blinks of roughly a third of a second. Between 3s and 5s her weight shifts almost imperceptibly to her left and back. A few hair strands drift with her breathing. Her gaze stays on the camera with the calm closed-lip smile. At 8s she is in exactly the starting pose.

— C02 待機變化：瞄一眼輸入列（起 S01、訖 S01）—
ACTION, 8 seconds: 0 to 1.5s she rests and breathes. 1.5 to 2.5s her eyes glance down and to her right, toward the lower-left of the frame, as if a message just arrived, and her head tips down about 2 degrees. 2.5 to 4.5s she reads for a moment and a small smile grows. 4.5 to 5.5s her eyes return to the camera with one soft blink. 5.5 to 8s she holds the rest pose, breathing.

— C03 聆聽（起 S01、訖 S01）—
ACTION, 8 seconds: 0 to 1s from rest she tilts her head about 5 degrees to her left and lowers her gaze to the lower-left of the frame, where the person is typing, while her upper body leans toward the camera by about 2%. 1 to 7s she listens: tiny attentive nods at 2.5s and 5s, a soft blink at 4s, brows slightly lifted, warm closed-lip smile. 7 to 8s she straightens back into exactly the starting pose.

— C04 點頭確認（起 S01、訖 S01）—
ACTION, 8 seconds: 0 to 1s rest. 1 to 2s one clear, warm nod: her chin dips about 8 degrees and comes back, eyes on the camera, and her smile deepens slightly as if saying "got it". 2 to 2.5s a soft blink. 2.5 to 8s she holds the rest pose, breathing.

— C05a 進入思考（起 S01、訖 S20；沒有結尾幀欄位時，結尾就是描述中的思考姿勢）—
ACTION, 8 seconds: 0 to 0.5s rest. 0.5 to 2.5s she raises her right hand and rests the bent index finger under her chin while her left arm folds across her waist to support the right elbow, matching the attached "thinking" reference; her eyes drift up and to her left, lips pressed softly together, brows lifting slightly in concentration. 2.5 to 8s she holds this thinking pose with only her breathing and one blink at 5s. The clip ends in the thinking pose, not the rest pose.

— C05b 思考停留（起 S20、訖 S20）—
ACTION, 8 seconds: She keeps thinking with the index finger under her chin for the whole clip. Her eyes move slowly from upper-left to upper-right between 2s and 3s and back between 5s and 6s, as if weighing two options. The index finger taps her chin twice at 4s. She blinks at 1.5s and 6.5s. Her breathing lifts her shoulders slightly. She never looks at the camera in this clip. At 8s she is in exactly the starting thinking pose.

— C06 想到了、回休息（起 S20、訖 S01）—
ACTION, 8 seconds: 0 to 1s thinking pose. 1 to 1.8s her eyes widen a touch and a pleased smile appears: the idea has landed. 1.8 to 2.6s she closes her eyes for a happy half second and tilts her head about 3 degrees. 2.6 to 4.5s her right hand lowers smoothly and her left arm relaxes until her left hand loosely holds her right wrist in front of her; she looks back at the camera with the calm closed-lip smile. 4.5 to 8s rest pose, breathing.

— C07 講解提示手勢（起 S01、訖 S01）—
ACTION, 8 seconds: 0 to 1s rest. 1 to 2s she raises her right hand beside her shoulder with the index finger pointing up, a friendly "here is the tip" gesture matching the attached "tip" reference; her eyes brighten and she gives a small nod. 2 to 4s the raised hand makes two small emphasizing beats, as if marking two points; lips stay closed, expression warm and confident. 4 to 5.5s her hand lowers back to rest. 5.5 to 8s she holds the rest pose, breathing.

— C08a 進入陪讀（起 S01、訖 S32；沒有結尾幀欄位時，結尾就是描述中的低頭閱讀姿勢）—
ACTION, 8 seconds: 0 to 0.5s rest. 0.5 to 2s her head tips down about 6 degrees and her eyes settle on the text below her, toward the bottom-center of the frame; calm closed-lip smile. 2 to 8s she reads: her eyes scan slowly left to right in lines, one blink at 5s, breathing visible. The clip ends in this reading pose, not the rest pose.

— C08b 陪讀（起 S32、訖 S32）—
ACTION, 8 seconds: Her head stays tipped down about 6 degrees and her eyes read the text below her for the whole clip: they scan slowly left to right in lines, about one line every 1.5 seconds, with soft blinks at 3s and 6.5s. At 4s she gives a tiny approving nod without lifting her head. Calm closed-lip smile throughout, breathing visible. She never looks up at the camera in this clip. At 8s she is in exactly the starting reading pose.

— C09 抱歉（起 S01、訖 S01）—
ACTION, 8 seconds: 0 to 1s rest. 1 to 2.2s she lifts her right hand behind her head with the fingers touching her hair near the nape and tilts her head about 10 degrees to her left; her brows lift and draw together into a sheepish, apologetic closed-lip smile. 2.2 to 4.5s she holds it, with a small shrug of the shoulders at 3s. 4.5 to 6s hand and head return to rest. 6 to 8s rest pose, breathing.

— C10 揮手（起 S01、訖 S01）—
ACTION, 8 seconds: 0 to 1s rest. 1 to 2s she raises her right hand to shoulder height, palm to the camera, and gives a small friendly wave of two beats, matching the attached "greeting" reference; her smile opens brightly and her eyes crinkle. 2 to 3.5s the wave finishes and the hand lowers. 3.5 to 8s rest pose, breathing.

— C11 推眼鏡（起 S01、訖 S01）—
ACTION, 8 seconds: 0 to 1s rest. 1 to 2s she raises her right index finger to the bridge of her glasses and pushes them up with a confident, playful look, one eyebrow slightly raised. 2 to 3s the hand lowers and the smile settles. 3 to 8s rest pose, breathing.

— C12 眨眼比讚（起 S01、訖 S01）—
ACTION, 8 seconds: 0 to 1s rest. 1 to 2s her right hand comes up into a thumbs-up at chest height as she winks her right eye and smiles widely with a hint of teeth, matching the energy of the attached "encouragement" reference; her head tilts about 5 degrees. 2 to 3.5s the smile stays as the hand lowers. 3.5 to 8s rest pose, breathing.

— C13 收尾微笑（起 S01、訖 S01）—
ACTION, 8 seconds: 0 to 1s rest. 1 to 2.5s a small satisfied smile and a slow exhale: her shoulders drop softly and she gives one slow blink. 2.5 to 8s rest pose, breathing.

【七、POST-PROCESSING 命令範本（ffmpeg，Windows 亦可；浮水印方框位置依實際落點調整）】
取末幀當子定格：
ffmpeg -sseof -0.05 -i C05a.mp4 -frames:v 1 -update 1 S20_think.png
ffmpeg -sseof -0.05 -i C08a.mp4 -frames:v 1 -update 1 S32_read.png
2:3 定格中心裁成 9:16 腰上（只在步驟 1 走 2:3 路線時用；0.70 是保留的高度比例，依腰結位置微調）：
ffmpeg -i S01_23.png -vf "crop=ih*0.70*9/16:ih*0.70:(iw-ow)/2:0" S01_rest.png
循環段（無限循環）：
ffmpeg -i C01.mp4 -an -vf "drawbox=x=iw-150:y=ih-150:w=150:h=150:color=0x00FF00:t=fill,chromakey=0x00FF00:0.12:0.06,despill=type=green,scale=540:960:flags=lanczos,fps=15" -c:v libwebp_anim -lossless 0 -q:v 75 -loop 0 sydney_c01_idle.webp
一次性段（先裁到 App 使用秒數，只播一次，停在最後一格）：
ffmpeg -ss 0.5 -t 2.5 -i C04.mp4 -an -vf "drawbox=x=iw-150:y=ih-150:w=150:h=150:color=0x00FF00:t=fill,chromakey=0x00FF00:0.12:0.06,despill=type=green,scale=540:960:flags=lanczos,fps=15" -c:v libwebp_anim -lossless 0 -q:v 75 -loop 1 sydney_c04_nod.webp
待機正反來回（眨眼倒放看不出來，接點零跳動）：
ffmpeg -i C01.mp4 -an -filter_complex "[0:v]split[a][b];[b]reverse[r];[a][r]concat=n=2:v=1[v]" -map "[v]" C01_pingpong.mp4
過場倒放（C05a 倒放＝離開思考，C08a 倒放＝抬頭）：
ffmpeg -ss 0.5 -t 2.5 -i C05a.mp4 -an -vf reverse C05a_exit.mp4
檔名：sydney_c01_idle、c02_idle_glance、c03_listen、c04_nod、c05a_think_in、c05b_think_loop、c06_idea_out、c07_tip、c08a_read_in、c08b_read_loop、c09_sorry、c10_wave、c11_glasses、c12_wink_thumb、c13_settle。

【八、備援路線：只有在 Veo 三次都維持不了形象時才走】
改做定格 crossfade：以 S01 當底圖，用 nano banana 編輯模式產 16 張同機位定格（清單與提示詞在 repo 分支的 docs/ideas/sydney-interaction/nano-banana-prompts.md 第 4 節；每張只改一個部位、其餘 pixel-identical）。驗收與後製同上：三點檢查、疊圖對齊、去背、WebP。這條路線 App 端用 crossfade 加程式呼吸與眨眼也能有活著的感覺。走這條前先回報 Eric。

【九、不做的事】
- 不改 App 程式；不動付費、額度、AI 請求。
- 不做換形象、換造型系列；不改 Sydney 任何外觀元素。
- 不把 mp4、webp 或大圖 commit 進 repo。
- 不對外公開素材連結。
- 形象取捨不自己決定，回 Eric 拍板。
````
