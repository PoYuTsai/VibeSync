# 導演板 B9–B12｜單幀 Prompt v3

配套：`2026-08-29-vibesync-film-60s-ice-fire-script-v3.md`
關係：B1–B8 沿用 `2026-08-29-vibesync-film-boards-b1-b9-prompts-v2.md`（含共用尾綴、共用禁止、平牆文法、出圖規則）；本檔只列 v3 新增／重寫的四張。B9 取代 v2 B9。
工具：Higgsfield `cinematic_studio_2_5`，16:9，2K，每張 2 credits。

v3 新增的固定描述（缸，每張有缸的都貼）：
`A colossal wide rectangular glass tank framed by a thick metallic gold frame with chamfered corners; the left edge of the frame glows cyan, the right edge glows gold. Inside the tank warm golden light. A faint isometric cube emblem etched into the glass at its center: three cube faces each carrying a G-shaped maze pattern, a stack of chevrons on top, violet-to-gold gradient.`

**2026-08-29 修正**：原「portrait／上下青條／六角迷宮」三處與真實卡背不符（真機截圖對照）。已出的 B10／B12 徽記與框靠後製換真 logo，不重出；再出圖時用上面這段，並把 `practice_draw_card_back_base.png` 上傳當 `image` 參考。

大廳（B9–B12 共用，取代井道尾綴）：
`Floor of a vast dark hall made of lit smartphone screens glowing warm gold, walls tiled with powered-off dark purple-black phone screens, no sky, no outdoors, cinematic film still, 16:9, photoreal, shallow depth.`

## B9｜落地（取代 v2 B9）
Refs：`@Sydney`、`@M0`、`@ENV0`（只當牆材質）
```
Wide shot. Sydney <<<db109a5a-f9a4-4999-905f-7809d5e1d69a>>> and the man <<<247e5e3c-5b28-4650-be9f-4a043943f0f3>>> have just landed on their feet on a floor of glowing golden screens, both seen from behind at three-quarter angle, still catching their balance. Above and around them, dark phone-screen panels and ice shards are still flying UPWARD, each panel lighting up orange as it rises. Meltwater drips off his sleeves; his frost is cracking and falling away. Far ahead at the end of the hall, a tall rectangle of warm golden light. + 大廳 + 共用禁止
```
證明：火贏、站起來、前方有東西。

## B10｜荒謬鏡：缸（Eric＋Bruce 2026-08-29 定案：泰式金魚缸的展示感，有點色但不太色，全片視覺高潮）

2026-08-29 追加硬鎖：缸裡是**會呼吸、會轉頭、會用眼神回應男主與 Sydney 的擬真人物**，不是照片牆。Demo B10 只保留空間／框／群像密度，重複臉與錯六角徽記都不進正式版。

### B10-A｜鎖定群像首幀

Refs：`@TANK`、`@GIRL_FG01`～`@GIRL_FG08`（從真實 App `practice_girls` 選出並各自建 Element）。8 位 Element 只鎖身份；本首幀鎖座位、晚禮服、手勢與眼線起點。
```
Locked-camera over-the-shoulder shot from behind two real figures: the man's back and right shoulder occupy the lower left foreground, Sydney's white shoulder and dark hair occupy the lower right foreground, both softly out of focus and providing two precise eyeline targets. Filling the frame: + 缸描述 + Behind the glass is a real tiered showroom, not a wall of photographs, lit like a luxurious lounge in warm gold and soft rose. About one hundred adult East Asian women in elegant evening dresses and cocktail outfits sit and stand on tiered steps and plush seats at different depths, tasteful and glamorous. The front two rows contain eight fixed hero women using @GIRL_FG01 through @GIRL_FG08, four in the first row and four in the second row. Preserve every hero woman's exact facial identity, hair, age and body type; no duplicated faces, no face blending and no seat swapping. Give each hero woman a distinct physically grounded resting pose: hands folded on knees, one hand on a chair back, relaxed shoulders, slight forward lean, or ankles crossed. Four hero women begin by looking at the man's shoulder position, two begin by looking at Sydney's position, and two hold an observant three-quarter gaze between them; nobody stares at the center of the camera lens. All rear rows are distinct but softer and less legible, creating depth without competing with the eight hero faces. Fingertips and natural breath fog the glass in a few places. The actual isometric cube emblem is only a faint etched reflection behind the crowd. + 大廳 + No neck number tags, no generated text, no nudity, no lingerie, no bar counter, no lip biting, no synchronized pose, no mannequins, no portrait cards + 共用禁止
```
驗收：8 位 Element 身份、4+4 座位、雙前景肩線、眼線起點、手與晚禮服全部成立才可做動態。`Practice ID` 在後製加於玻璃／座位下緣，不交給生成模型寫字。

### B10-B｜3–4 秒擬真人群像表演鏡

工具：Seedance 2.5 image-to-video；start frame＝通過的 B10-A；references＝同 8 位 Hero Girl Elements。鏡頭鎖死，剪取最佳連續 3 秒。
```
The eight hero women remain in their exact seats and preserve their exact identities, clothing and anatomy. They are living real people observing the man and Sydney through glass, not a still photograph. Motion is restrained, asynchronous and individually timed. FG01 maintains eye contact with the man and lifts only one corner of her closed mouth by a few millimeters. FG02 lowers her chin slightly while keeping a curious gaze on him. FG03 looks at Sydney first, then moves only her eyes toward the man. FG04 raises one eyebrow very subtly near the end. FG05 takes one quiet breath and leans forward by two centimeters. FG06 shifts her gaze from Sydney to the man and lets a small closed-mouth smile appear. FG07 tilts her head by only three degrees without moving her seat. FG08 blinks once late, then holds a calm evaluative gaze. Start each micro-action four to eight frames apart. The rear crowd only breathes, blinks sporadically and makes sparse independent eye movements; no wave of synchronized motion. Natural skin, tiny eye saccades, subtle asymmetry, real fabric weight, real breathing and realistic reflections on the glass. The camera does not push, pan, orbit or zoom. No one changes seats, crosses rows, touches the glass dramatically, waves, speaks, opens her mouth, bites her lip or performs a sexual gesture.
```
證明：冷觀眾一眼讀成「很多真實練習對象正在看男主與教練」；前景 8 人有不同人格但沒有搶戲；性感來自克制眼神與停頓，不讀成八大、拍賣或一群 AI 同步人偶。

## B11｜Sydney 眨眼
Refs：`@Sydney`
```
Close-up. Sydney <<<db109a5a-f9a4-4999-905f-7809d5e1d69a>>> turns her head back over her shoulder to look at someone just behind the camera, chin slightly down, one eye closed in a quick playful wink, the other eye bright and locked on the viewer, a small crooked smile. A man's dark shoulder is soft in the foreground edge. Warm golden light from the huge glass tank behind her rims her hair; a faint cyan neon line runs across the top of the background. + 大廳 + 共用禁止
```
證明：表演像真人不像 CG；眼神對到鏡頭。

## B12｜接點中間格：缸縮成卡
Refs：`@TANK`、`@CARD_BACK`（只當顏色與徽記形狀參考，用 medias）
```
Very wide shot, camera far back and high. Two tiny figures stand at the foot of + 缸描述 + The tank is small in the frame, centered, and reads as a giant playing card standing upright. The glass is darkening from its four corners toward the center into deep navy-black; the women inside are dissolving into that darkness and only a few faint faces remain near the middle. The hexagonal maze emblem at the center is glowing in violet and gold, with thin radial star lines emerging around it. Gold chamfered frame and cyan neon edges fully lit. + 大廳 + 共用禁止
```
證明：缸→卡的幾何與明暗過渡成立；徽記位置對得上真實卡背。成立後改後製 morph，不再生成。

## 出圖規則（v3 補充）
- B10 的一百人：不寫「exactly 100」，模型無視數字；用「about one hundred… at different depths」。只有前兩排固定 8 位 Hero Girls 需要身份可讀，後排只需群像深度。
- Element 只提供「她是誰」，不能拿來取代姿勢／微表情導演。B10-A 首幀鎖位置與姿勢；B10-B 時間軸逐人寫眼神與嘴角，且動作錯開。
- B10 不混在 Part 2 長片裡順帶生成；獨立做 3–4 秒受控 image-to-video，否則八位身份、男主、Sydney、缸與長段劇情會互相污染。
- B10、B12 的框：金＋青只准出現在框；缸內光只准金。若模型把青灑進缸內，刪「neon」一詞不加限制。
- B11 一定要 `one eye closed`＋`the other eye… locked on the viewer` 同時寫，只寫 wink 會出雙眼閉。
- 其餘規則沿用 v2。
