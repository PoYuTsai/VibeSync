# Seedance 2.5／Higgsfield 提示詞工程研究

日期：2026-08-26  
範圍：只採用 ByteDance Seed、BytePlus／ModelArk、Higgsfield 與官方 GitHub 組織的第一方資料。第三方 GitHub 專案只列出、未讀取原始內容、未安裝、未採用。

## 結論先講

這次 V1 最適合走「少量、明確分工的 reference + 高密度電影導演 prompt」：reference 只固定 Sydney 身分與六個元素的外觀；背景、世界、光線、鏡頭、物理與聲音全部用 prompt 建立。這會比替每個場景先生成一張完整底圖，更能保留 Seedance 2.5 的場景想像空間。

建議預設：

- 不放背景圖、風格圖或 GPT 生成的完整構圖圖。
- 最小 reference 組合為 7 張：Sydney 1 張 + 六元素各 1 張。
- 若 Sydney 身分穩定性比 reference 數量更重要，改為 8 張：乾淨正面 headshot + 單人正面 full-body + 六元素各 1 張。BytePlus 官方不建議多視角／三視圖人物板，因為可能被誤認為多個人物。
- 不使用普通 reference 充當首幀或尾幀；只有 Higgsfield 畫面出現專用 Start Frame／End Frame 欄位時，那兩張圖才有首尾錨點語意。V1 為保留場景想像空間，先不用專用首尾幀。
- 第一版就開啟原生音訊，讓環境聲、foley 與配樂跟畫面一起生成；字幕與品牌字先不要燒進畫面，後製再加。
- 25–30 秒 prompt 寫成同一個有標籤的 production brief：全片視覺規則 → reference key → 場景與人物 → 第一幀／走位 → 時間軸 → 鏡頭與光學 → 物理與連續性 → 音訊。

## 1. 多張 reference：順序、角色與首尾幀

### 1.1 上傳順序會決定編號，但不會自動決定用途

Higgsfield 官方案例明確說明：第一張上傳圖會成為 `@image_1`，第二張成為 `@image_2`，依此類推；因此上傳順序是 prompt contract 的一部分。ByteDance／BytePlus 官方案例也以 `@Image 1`、`@Image 2` 明確指定場地、人物、道具與風格來源。

但是「排第一」不等於模型自然知道它是主角或首幀。每個 reference 都應在 prompt 內綁定：

1. 它是誰／什麼。
2. 要沿用哪些特徵。
3. 不要沿用哪些維度，例如背景、姿勢、打光或構圖。

推薦寫法：

```text
REFERENCE KEY — attach in this exact order:
@image_1 = SYDNEY FACE IDENTITY. Use only her facial identity, hairline, eye shape,
skin tone and age. Do not inherit the reference background, lighting, pose,
composition, lens or visual style.

@image_2 = SYDNEY BODY AND WARDROBE. Use only her body proportions, outfit,
materials and silhouette. It is the same single Sydney as @image_1.

@image_3 = ELEMENT 1. Preserve only its exact silhouette, material, color and markings.
...
@image_8 = ELEMENT 6. Preserve only its exact silhouette, material, color and markings.
```

若只有一張 Sydney 圖，使用 `@image_1`，六元素依序放 `@image_2` 到 `@image_7`。人物圖最好清楚、銳利、正面、光線均勻、背景乾淨。不要在一張人物板塞前／後／左／右多個 Sydney；BytePlus 官方指出這可能造成 ID drift、複製人物或雙胞胎效果。

來源：

- [Higgsfield：上傳位置決定 `@image_N`](https://higgsfield.ai/blog/make-game-trailer-with-ai)
- [Higgsfield Canvas Help：在 prompt 開頭明確定義 reference 的角色](https://higgsfield.ai/creator-hub/help-center/tools/how-do-i-use-canvas)
- [ByteDance Seed：2.5 多 reference 官方範例](https://seed.bytedance.com/en/blog/one-take-creation-flexible-referencing-introducing-seedance-2-5)
- [BytePlus：Seedance 2.x prompt guide](https://docs.byteplus.com/api/docs/ModelArk/2222480)

### 1.2 一般 reference、Start Frame、End Frame 是不同角色

BytePlus 官方 API 把以下模式分開：

- First-frame I2V：1 張首幀圖。
- First-and-last-frame I2V：2 張圖，分別錨定起點與終點，模型補中間運動。
- Multimodal reference：Seedance 2.5 可放 1–30 張 reference images，另可搭配影片與音訊；這些素材的用途由 prompt 內的 `@Image N`／`@Video N`／`@Audio N` 關係決定。

所以，普通 reference 的第一張圖只會是 `@image_1`，不應推定為「畫面必須從這張開始」。反過來，專用 Start/End Frame 會強制更多構圖與起終狀態，通常會減少模型自由建立場景的空間。

Higgsfield 的一般平台頁面有 Start/End Frame 功能，但目前 Seedance 2.5 專屬產品頁沒有清楚列出該欄位是否在每種生成模式都提供。以實際 UI 為準：只有看到明確的 Start Frame／End Frame 欄位才使用；若只有 References，就全部按普通 reference 處理。

來源：

- [BytePlus LAS：Seedance 2.5 模式、reference 上限與首尾幀](https://docs.byteplus.com/en/docs/byteplus_las/video_gen_enhanced)
- [Higgsfield AI Video：平台級首尾幀功能](https://higgsfield.ai/ai-video)
- [Higgsfield Seedance 2.5 產品頁](https://higgsfield.ai/seedance/2.5)

### 1.3 給 Sydney／六元素的實際放法

優先順序是「最需要精準的素材最先宣告」，不是把所有圖塞滿：

| 上傳位置 | 建議素材 | prompt 內角色 | 不沿用 |
|---|---|---|---|
| `@image_1` | Sydney 乾淨 headshot | 臉、年齡、髮際、五官、膚色 | 背景、光線、鏡頭、表情、構圖 |
| `@image_2` | Sydney 單人正面 full-body | 身形、服裝、材質、輪廓 | 背景、姿勢、場景風格 |
| `@image_3…8` | 六元素各一張乾淨 packshot | 每件的輪廓、材質、顏色、標記 | 原圖背景、打光、比例關係、漂浮姿勢 |

如果現有 Sydney 圖只有一張，就把它放 `@image_1`，六元素順延。背景與世界不要上傳 reference，由 prompt 寫出具體 production design，這正是保留模型想像空間的地方。

## 2. 長度、畫質與音訊能力

### 2.1 已確認能力

- ByteDance Seed 官方：單次最高 30 秒 audio-video，支援多輪延長；長片可在 30 秒內安排 setup、development、turning point、resolution。
- BytePlus API：Seedance 2.5 輸出 4–30 秒、24 fps、480p／720p；`generate_audio` 預設為 `true`。API 也支援首幀、首尾幀、multimodal reference、editing 與 extension。
- ByteDance 官方 reference 上限：單次最多 30 張圖片、10 段影片、10 段音訊。
- Higgsfield 產品頁：單次最高 30 秒、同步聲音、最高 50 個平台 reference inputs；官方 prompting guide 宣稱最高 1080p。這些是 Higgsfield 平台包裝，和 BytePlus API 的輸出檔位不同，實際解析度與 reference 類型仍以生成按鈕旁的當前 UI 為準。

來源：

- [ByteDance Seedance 2.5 正式發布](https://seed.bytedance.com/en/blog/one-take-creation-flexible-referencing-introducing-seedance-2-5)
- [ByteDance Seedance 2.5 模型頁](https://seed.bytedance.com/en/seedance2_5)
- [BytePlus LAS Seedance 2.5 API](https://docs.byteplus.com/en/docs/byteplus_las/video_gen_enhanced)
- [Higgsfield Seedance 2.5](https://higgsfield.ai/seedance/2.5)
- [Higgsfield Seedance 2.5 prompting guide](https://higgsfield.ai/blog/seedance-2-5-prompting-guide)

### 2.2 第一版可以直接有聲音，但字幕建議後製

可以而且應該在 V1 就生成：

- 空間底噪與環境聲。
- 與動作同步的 foley，例如腳步、金屬鎖定、材質摩擦、呼吸、布料、能量脈衝。
- 一條簡單、明確的音樂曲線，或明確要求無配樂。
- 必要且短的對白；若有對白，要說清楚誰說、何時說、語氣與語言。

字幕方面，BytePlus 官方文件指出 Seedance 能生成字幕、speech bubble 與一般文字，但也明確承認「意外字幕」無法 100% 避免；文字與字幕仍是需要驗收的生成物。對這次 V1，視覺目標是電影場景與動作連續性，因此建議：

- prompt 明寫 `No on-screen text, no captions, no subtitles, no logos, no watermark.`
- 對白可以生成，但字幕另外後製。
- 若一定要測內建字幕，只測一句短、常用字、固定位置的字幕；不要把 App UI、品牌字或關鍵 CTA 成敗綁在首次生成。
- 所有對白／旁白最好在結尾前 1–2 秒結束，保留環境聲尾巴；官方 FAQ 提到有旁白的影片結尾可能出現 cut-off noise，必要時後製 fade-out。

來源：

- [BytePlus Seedance 2.x prompt guide：文字、字幕、音訊與已知問題](https://docs.byteplus.com/api/docs/ModelArk/2222480)
- [Higgsfield：原生 ambience、foley、score](https://higgsfield.ai/seedance/2.5)

## 3. 25–30 秒長 prompt 的建議結構

Higgsfield 官方測試建議把 prompt 寫成一個連續文字區塊，但以清楚標籤分節。ByteDance／BytePlus 官方範例則使用時間碼控制故事、鏡頭、運動和節奏。兩者可合併成以下結構：

```text
FORMAT AND GLOBAL VISUAL RULE
總長、比例、24fps、單一長鏡頭或明確鏡頭數、live-action 電影質感、色彩與禁止漂移的全片規則。

REFERENCE KEY
依上傳順序綁定 Sydney 與六元素；每張只指定要繼承的維度，明確排除原圖背景／光線／姿勢／構圖。

SCENE CONTEXT
一句話說明這 25–30 秒的戲劇目標、事件與情緒弧線。

LOCATION / PRODUCTION DESIGN
空間幾何、前中後景、材質、尺度、時段、天氣、空氣與唯一主要光源。不要只寫「cinematic」。

CHARACTER AND CONTINUITY LOCK
同一位 Sydney、同一套服裝、同一髮型、同一物件狀態；六元素出現數量與狀態不可回復或複製。

FIRST FRAME AND BLOCKING
第一個可見 frame 已經有什麼；Sydney 在哪、朝哪裡、手在何處；六元素各自初始位置；鏡頭高度、距離與視線方向。

TIMELINE
0.0–4.0s：一個主要事件 + 鏡頭行為 + 明確結束狀態。
4.0–9.0s：下一個因果事件，不重新介紹世界。
9.0–15.0s：轉折或高風險動作；寫清楚接觸、重量、速度與終點。
15.0–21.0s：主視覺 payoff；不要同時加入第二個複雜肢體互動。
21.0–25.0s：結尾姿勢／畫面落點與聲音尾巴。

OPTICS AND CAMERA
焦段或視角、機位、攝影機質量感、運動路徑、焦點與景深。單鏡到底就明寫 no cuts；多鏡頭就逐鏡標 `Hard cut`。

PHYSICS AND ANATOMY
重量轉移、慣性、接觸陰影、衣料／頭髮／粒子行為、手的起終姿勢、每個元素的數量與狀態。

LIGHTING
一個有物理來源與方向的 key light，加合理 fill／bounce；寫光如何隨人物與鏡頭移動，而不是堆「cinematic lighting」。

AUDIO
環境底聲 → 每個事件的同步 foley → 配樂情緒曲線或 no score → 對白時間與語氣 → 最後 1–2 秒自然收尾。
```

可操作原則：

- 一個時間段只安排一個主要因果動作；25 秒約 4–5 個自然 beat，這是基於官方長片範例與複雜互動限制的保守推論，不是硬性模型上限。
- 每段都寫「開始狀態 → 動作 → 結束狀態」，尤其是手、抓握、物件轉移與變形。
- 要一鏡到底，就不要同時寫 `Shot 1/2/3` 和 `Hard cut`；要多鏡頭，就不要用 `single continuous take`。
- 時間碼總和必須與設定總長一致，不能 25 秒 prompt 裡又要求 30 秒 ending。
- 場景想像空間來自「不給背景 reference」，不是把場景寫得含糊。空間、材料、光源、鏡頭和物理越具體，模型越能把創意用在 production design，而不是用在猜基本關係。

來源：

- [Higgsfield Seedance 2.5 prompting guide：分節順序](https://higgsfield.ai/blog/seedance-2-5-prompting-guide)
- [ByteDance 2.5：時間碼、多鏡頭與一鏡到底範例](https://seed.bytedance.com/en/blog/one-take-creation-flexible-referencing-introducing-seedance-2-5)
- [BytePlus：timeline storyboard 與 reference mapping](https://docs.byteplus.com/api/docs/ModelArk/2222480)

## 4. 降低角色漂移、額外肢體與遊戲／動漫感

### 4.1 角色漂移

- 人物 reference 用獨立、清楚、正面、光線均勻的單人圖片。
- Sydney 最穩妥是 headshot + 單一正面 full-body，分成兩張輸入；不要三視圖或多個角度同框。
- prompt 只用 2–3 個穩定特徵辨認她，再綁 `@image_1`／`@image_2`；不要一面以 reference 鎖臉，一面用文字改寫成另一種五官。
- 每個 beat 都叫她同一個名字 `SYDNEY`，不要交替使用「woman／girl／heroine」造成新 subject。
- 保持 reference 跨三次生成不變；不要每 part 換一張新的 Sydney。
- 角色與元素的 reference 都限制作用範圍，避免原圖背景、光線與構圖污染電影世界。

ByteDance 官方也承認：複雜動作的物理合理性，以及多 subject 互動時的穩定性，仍有改善空間。這不是靠堆更多形容詞能完全消除的限制。

### 4.2 手、額外肢體與物件接觸

- 比起只寫動作名稱，寫清楚手的起始位置、接觸點、運動路徑與結束位置。
- 一個 beat 只做一次關鍵抓取／交換／穿戴；不要同時抓、轉身、跌落、變形又操作第二件物品。
- 用正向 anatomy lock：`Sydney remains one anatomically correct human with one left arm, one right arm, two hands and five natural fingers per hand throughout.`
- 關鍵手勢若是全片成敗點，可另給乾淨手勢 reference；但不要為每個小動作增加 reference。
- 手與道具接觸時寫出重量、摩擦、指尖壓力、物件慣性和接觸陰影；避免「magically grabs」這類讓模型自行補物理的句子。
- 若畫面可成立，讓手部動作在 medium shot 完成，不要在極廣角小人物中要求精細手指，也不要用太快的遮擋掩蓋所有過程。

### 4.3 避免「太 GPT」、遊戲或動漫質感

不要只加 `cinematic, epic, 8K, ultra detailed`。Higgsfield 官方寫實指南指出，真正拉開差異的是可執行的物理與攝影資訊：

- 正向總規則：`photographed live-action feature film, real human skin, natural asymmetry, grounded physical production design`。
- 指定一個 motivated light source、方向、色溫、衰減、陰影與反射；避免人物從所有方向均勻發亮。
- 指定鏡頭與攝影機質量感：例如 35mm／50mm、肩扛呼吸、dolly 慣性、真人操作的小修正，而非漂浮虛擬攝影機。
- 寫重量轉移、落腳、碰撞、慣性、布料和頭髮反應。
- 寫真實皮膚毛孔、細毛、輕微不對稱與自然眼睛反光；避免塑膠平滑肌膚、均勻高光與過度銳化。
- 若目標是實拍電影，不要同時使用 `Unreal Engine`、`game cinematic`、`Octane render`、`anime`、`cel shading`、`3D animation` 等相反風格信號。
- 放在結尾的 exclusions 保持短而具體：`No game-engine rendering, no anime, no illustration, no plastic skin, no duplicated Sydney, no on-screen text.`

Higgsfield 一篇官方案例說 Seedance 對一般自然語言否定句可能反向理解，例如「她不要笑」反而誘發笑容；BytePlus 官方則建議用少量 constraint words 降低字幕、Logo、變形與複製人物。兩者可兼容：人物狀態與動作先用正向語句寫清楚，結尾只留少量全局禁項，不要寫一大段 negative prompt。

來源：

- [BytePlus：ID drift、多視角 reference、雙胞胎、字幕與 constraints](https://docs.byteplus.com/api/docs/ModelArk/2222480)
- [Higgsfield：手與臉的失敗原因及固定起終狀態](https://higgsfield.ai/blog/ai-video-hands-faces)
- [Higgsfield：具體光線、鏡頭與物理比「realistic」更有效](https://higgsfield.ai/blog/ai-video-look-real-2026)
- [Higgsfield：reference、物理與長鏡頭 drift checklist](https://higgsfield.ai/blog/why-ai-video-generations-fail)
- [Higgsfield：reference 角色範圍與實際 anatomy lock 範例](https://higgsfield.ai/blog/ai-ecommerce-ads-2026)

## 5. 官方 GitHub／skill 調查

### 5.1 有官方資源，但沒有找到 Seedance 2.5 專屬官方 GitHub prompt repo

- [ByteDance-Seed 官方 GitHub 組織](https://github.com/bytedance-seed)存在；截至調查日，公開 repo 清單未查得 Seedance 2.5 模型、權重或專屬 prompting skill。
- [Higgsfield 官方 GitHub Skills repo](https://github.com/higgsfield-ai/skills)存在，適合視為 Higgsfield 工作流資源入口；本次沒有讀取或安裝 repo 原始內容，也未確認其中有通用 Seedance 2.5 電影 prompting skill。
- [ByteDance 官方 `agentkit-samples`](https://github.com/bytedance/agentkit-samples/tree/main/skills/byted-bp-seedance-viral-creative-rewrite-skill)有一個 Seedance viral creative rewrite skill，但它是 BytePlus Seedance 2.0 的廣告模板改寫／產品圖工作流，不是通用 Seedance 2.5 電影 prompt skill，因此本次不把它當 2.5 規格來源。
- Higgsfield 官方在 [AI vs VFX 工作流](https://higgsfield.ai/blog/ai-vs-vfx)提供 [`prompt-builder-2-5.skill` 官方附件](https://assets.ctfassets.net/91663d1w6kgm/g2XNwtkfVP6NsmZMCMlFM/0c12209a557c53aa5f3fa1e93b62df9e/prompt-builder-2-5.skill)，但它不是 GitHub repo。本次只確認附件存在，未下載、未解壓、未執行；若要採用，應另做安全 intake 後再比較其規則與當前官方文件。

### 5.2 查到但未採用的第三方 repo

以下不是 ByteDance Seed、BytePlus 或 Higgsfield 官方來源，本次沒有讀取原始內容，也沒有安裝或引用其規則：

- <https://github.com/seedanceprompts/seedance-prompts>
- <https://github.com/MapleShaw/seedance2.0-prompt-skill>
- <https://github.com/mqrox/seedance-2.0-prompt-skill>
- <https://github.com/ardha27/seedance-prompts>
- <https://github.com/bytedance-seedance/seedance-2.0>（組織名稱不是官方 `ByteDance-Seed` 或 `bytedance`，不可因名稱相似視為官方）

## 6. 對這次 V1 的最終可操作決策

1. 上傳 Sydney 與六元素，不上傳任何完整場景底圖。
2. 若素材足夠，Sydney 用兩張獨立圖：headshot、front full-body；若不夠就只用一張乾淨單人圖，不臨時生成多視角拼貼。
3. 六元素各一張、依故事出場次序排列；prompt 逐張明寫「只繼承形狀／材質／顏色／標記，不繼承背景與光線」。
4. 不選專用 Start/End Frame；用文字的 `FIRST FRAME AND BLOCKING` 描述開場，讓 Seedance 自己生成電影場景。
5. V1 開啟原生 audio，prompt 最後寫環境聲、逐事件 foley 與簡單 score；不生成畫內字幕、App UI 或關鍵品牌字。
6. 25 秒內控制在 4–5 個因果 beat；每段都落到明確 end-state，尤其是 Sydney 的手、元素數量與所在位置。
7. prompt 的電影感靠空間、材質、光源、鏡頭、表演和物理，不靠額外背景 reference，也不靠一串 `cinematic/8K/epic`。

## 7. 尚未完全確定、送出前要看 UI 的項目

- Higgsfield 目前的 Seedance 2.5 生成面板是否對這個帳號開放專用 Start／End Frame 欄位。
- 參考模式在 Higgsfield 當下實際允許的圖片／影片／音訊數量；官方平台寫 50 inputs，ByteDance 原生規格寫 30 images + 10 videos + 10 audio。
- Higgsfield 當下可選解析度與價格；其產品／blog 頁面寫到 1080p，而 BytePlus 官方 2.5 API 是 480p／720p，屬不同平台供應設定。
- 若需要精確 Sydney 聲線，是否會提供 voice reference；否則只以 prompt 指定音色與演法，不能保證跨三段聲線完全一致。
