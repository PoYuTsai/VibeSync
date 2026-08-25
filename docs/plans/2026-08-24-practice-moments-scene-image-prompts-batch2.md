# 練習室動態：第二批 20 張備用情境圖生成 Prompt 包

2026-08-24。給 Codex（或任何生圖模型）直接執行用的素材規格書，第二批。
2026-08-24 修訂一（Eric 拍板）：本批要有「人入鏡」與「跟朋友出去」的聚會感——換入 5 張朋友聚會構圖、放寬人物規則為「可入鏡但不可辨識」（§3），並把原 5 張覆蓋重疊最高的居家／風景構圖移出本批。

**這份文件解決什麼**：第一批 20 張（PR #30）補的是 `moments_image_catalog.ts` 已宣告的 id——每個 tag 至少有了一張圖。但覆蓋分析（§0）顯示 10 個 tag 只有**一張**圖：下雨天全台北 100 位角色配的是同一扇窗、看書全是同一個書櫃。加上第一批全部是空景，feed 看起來「她永遠一個人」。第二批做兩件事：補最薄的 tag、加入朋友聚會的現場感。

**與第一批的關鍵差異**：第一批的 id 是 catalog 裡**已存在的宣告**；第二批的 id 是**新 id，catalog 還沒有**。所以素材進了 repo 也不會有任何行為改變——這正是「備用」的意思。啟用要靠 §8 的接線 PR（catalog 宣告 + client 對照 + 閘門），**不在本批範圍**。

**範圍**：只產出素材與授權紀錄。`pubspec.yaml` 這次也**不用改**（第一批已註冊整個 `assets/images/practice_moments/` 目錄）。

---

## 0. 為什麼是這 20 張（覆蓋分析＋聚會感）

第一批之後各 tag 的場景圖張數（自拍 sentinel 不計）：

| 張數 | tags |
| --- | --- |
| 只有 1 張 | coffee、dessert、cooking、sky、sea、book、art、music、rain、commute |
| 2 張 | city、walk、travel、nature、pet、desk、work |
| 3 張以上 | cafe、food、night、calm、outdoor、fitness |

一張圖的 tag 意味著：**該題材每次配圖都是同一張**。`rainy_mood` 全部角色永遠配 `moment_rainy_window`；`book_note` 永遠是同一個書櫃。動態是全域內容（設計報告決策 A），跨角色撞圖是接受的，但「永遠同一張」在 feed 上一天就被看穿。

第二批的分配原則：

1. 1 張的 tag 各補至少 1 張（sky 除外——`moment_sunset_sky` 是刻意的單張晨昏兩可天空，再加一張反而稀釋）。
2. **5 張朋友聚會構圖**（乾杯、火鍋、KTV、二人下午茶、觀景台兩杯飲料）——Eric 2026-08-24 拍板：feed 要有「她有朋友、有生活」的訊號。人物規則見 §3。
3. 只用既有的 24 個 tag，不新增 tag——新增 tag 要動 `MomentImageTag` 型別與主題池，那是另一個層級的改動。

修訂一移出的 5 張（`pour_over_kit`、`ridge_city_view`、`park_bench_shade`、`balcony_plants`、`cat_loaf`）：全是「該 tag 已有 ≥2 張」的加深構圖，讓位給聚會張後薄 tag 的覆蓋目標不受影響。若日後想要，原 prompt 在本文件的 git 歷史裡。

---

## 1. 交付規格（硬性）

| 項目 | 規格 | 理由 |
| --- | --- | --- |
| 張數 | **20 張**，一個 id 一張 | id 清單見 §5 |
| 檔名 | `<id>.webp`，例如 `moment_iced_latte.webp` | 檔名拼錯＝接線後那張永遠對不上 |
| 路徑 | `assets/images/practice_moments/`（與第一批同目錄） | 目錄已在 pubspec 註冊，**不要再改 pubspec** |
| 格式 | **WebP**（有損，q78-82） | 同第一批 |
| 尺寸 | **960 × 720（4:3）** | 同第一批（tile 實際渲染 240×180 pt @3x） |
| 單張體積 | **≤ 130 KB**，硬上限 150 KB | |
| 本批總體積 | **≤ 1.1 MB**（第一批實績 849 KB，兩批合計必須 ≤ 2.0 MB） | 設計報告預算 2-3 MB 是兩批共用的，不是每批各一份 |
| 色彩 | sRGB，去除中繼資料 | |

---

## 2. 生成到入庫的管線

與第一批完全相同（`docs/plans/2026-08-24-practice-moments-scene-image-prompts.md` §2）：

> **構圖鐵則：3:2（1536×1024）出圖 → 置中裁 4:3 → 縮 960×720。主體放在畫面中央的 4:3 範圍內，左右各留約 6% 犧牲區。**

```bash
magick "raw/${id}_a.png" \
  -gravity center -crop 1365x1024+0+0 +repage \
  -resize '960x720!' -strip \
  -define webp:method=6 -quality 80 \
  "assets/images/practice_moments/${id}.webp"
```

每個 id 生 2-3 張候選存 `raw/`（不進 repo），人工挑一張入庫，候選數與入選版本記進授權文件（§7）。

---

## 3. 全域硬規則

第一批規格書 §3 的八條裡，除了人物那條，其餘**全部適用**（無可讀文字、時間讀不出來、台灣感、手機隨手拍、深色 UI 上好看、240px 可讀、不重現既有作品）。

**人物規則（修訂一，取代第一批的「畫面裡不能有人」）**——三條，一條都不能破：

1. **任何情況下都不得出現可辨識的人臉。** 沒有正臉、沒有清晰側臉、沒有看鏡頭的人。入鏡的人只能是：背影、畫面邊緣的手、遠景小到認不出、或糊到認不出。
   *理由（這是架構限制，不是保守）*：這批圖是**全域共用素材**，同一張會配給 100 位長相各異的角色。畫面裡任何一張臉都會被讀成「她」或「她的朋友」——「她」不可能同時像 100 位角色的圖鑑照；「她的朋友」則會在解鎖多位角色的使用者 feed 裡重複出現（兩位角色貼出同一位朋友），人設當場穿幫。設計報告 §7.4「不得生成像真實人物的新圖」同時擋掉 AI 人臉的肖像風險。
2. **發文者本人永遠不入鏡。** 每張圖的視角都是「她拿著手機拍」——她的臉、身體、倒影都不出現。聚會感靠現場證據表達：碰杯的手、四人份餐具、對面咬了一口的蛋糕、並排的兩杯飲料。
3. **手可以入鏡，但只能在畫面邊緣、帶動態模糊。** 清晰的手是生圖模型最常畫壞的東西；驗收時逐張數手指，畫錯就重生。

特別提醒本批的高風險點：

1. `moment_temple_incense`：廟宇的匾額、燈籠、籤詩櫃**全是字**。字全部失焦、拍局部角落、或乾脆不入鏡。
2. `moment_bubble_tea_cup`／`moment_viewpoint_drinks`：現實中封膜一定有印刷。**生成無印刷的素面封膜**，杯身也不得有 logo。
3. `moment_bento_lunch`／`moment_street_food_stall`：包裝紙、紙袋、攤車招牌不得有可讀的字。
4. `moment_ktv_room`：螢幕只能是抽象色彩糊光，**不得有任何可讀介面或歌詞字幕**。

---

## 4. 共用前綴與負面詞

**STYLE（接在每條 prompt 前面，兩組通用）**

```
Amateur smartphone photograph, taken casually with one hand. No identifiable
people anywhere in frame. Everyday life in Taipei, Taiwan, present day. Natural
available light, soft and slightly warm color, gentle contrast with lifted
shadows, mild lens softness and fine sensor grain. Slightly imperfect framing,
lived-in and unstaged. Photorealistic. Keep the main subject inside the central
4:3 area of the frame; leave the far left and far right edges empty.
```

**NEGATIVE-A（無人場景用；§5 各條標了用哪組）**

```
people, person, face, hands, fingers, body parts, portrait, crowd close-up,
text, letters, words, chinese characters, japanese characters, signage, labels,
book titles, logos, brand marks, watermark, UI, screen content, captions,
illustration, anime, painting, 3D render, CGI, AI-glossy look, HDR, oversaturated,
neon oversaturation, heavy vignette, blown-out highlights, pure white background,
studio product lighting, perfectly styled flat lay, stock photo look, collage,
split frame, border, frame, blur over the whole image, tilt-shift toy effect
```

**NEGATIVE-B（有人氣場景用：允許背影／邊緣的手，仍禁一切可辨識人臉）**

```
identifiable face, clear face, side profile in focus, person looking at camera,
recognizable person, portrait, close-up of a person, sharp detailed hands,
extra fingers, deformed hands,
text, letters, words, chinese characters, japanese characters, signage, labels,
book titles, logos, brand marks, watermark, UI, screen content, captions,
illustration, anime, painting, 3D render, CGI, AI-glossy look, HDR, oversaturated,
neon oversaturation, heavy vignette, blown-out highlights, pure white background,
studio product lighting, perfectly styled flat lay, stock photo look, collage,
split frame, border, frame, blur over the whole image, tilt-shift toy effect
```

---

## 5. 20 條 Prompt

每張標的「題材數／時段」是把該 id 的 tags 代入 `moments_schedule.ts` 主題池算出的**接線後**實際使用面。與第一批同一條鐵則：**這是這張圖必須撐得住的範圍，不是參考資訊。**

---

### 1. `moment_iced_latte` ｜ NEGATIVE-A
- **tags**：coffee, cafe ｜ 6 個題材（第一杯、下午沒電、週末早午餐、咖啡店踩點、實驗室、開店）｜全時段
- 與 `moment_coffee_cup`（熱的馬克杯）必須一眼可分：這張是**冰的、玻璃杯**。

```
A tall glass of iced latte on a small cafe table, milk still swirling into the
coffee in visible layers, large clear ice cubes, heavy condensation running down
the glass, a plain metal straw. Warm indoor cafe light from one side, background
of the cafe falling into soft blur. No window, no readable menu, no logo on the
glass. Casual slightly tilted framing as if photographed one-handed before the
first sip.
```

- **驗收**：與 `moment_coffee_cup` 一眼可分（冰、玻璃杯、奶紋分層）；杯與吸管無任何印字。

---

### 2. `moment_breakfast_shop_table` ｜ NEGATIVE-B
- **tags**：food, cafe ｜ 9 個題材（第一杯、午餐、晚餐、宵夜、週末早午餐、覓食…）｜全時段
- 台式早餐店桌面＋**背景有店裡的人氣**（糊到認不出的背影）。

```
A Taiwanese breakfast shop table from a seated diner's angle: a plate of sliced
egg pancake roll (dan bing) on a plain melamine plate with a small dish of soy
paste, and a clear plastic cup of milk tea with a straw, on a worn stainless
steel table. One or two other patrons far in the background, seen from behind,
heavily blurred and unidentifiable. No menu, no signage, no window. Slightly
greasy lived-in table surface, casual and unstyled.
```

- **驗收**：美耐皿盤＋不鏽鋼桌的台式早餐店質感；背景人物只有糊掉的背影、認不出是誰；沒有菜單或價目表。

---

### 3. `moment_bento_lunch` ｜ NEGATIVE-A
- **tags**：food, work ｜ 8 個題材（工作卡關、午餐、晚餐、宵夜、覓食、趕稿夜…）｜全時段
- 「在位子上吃便當」，工作感靠桌緣的鍵盤糊影帶出來。

```
An opened Taiwanese takeout lunch box (paper bento box) on an office desk: white
rice, a piece of fried chicken cutlet and stir-fried vegetables, disposable
wooden chopsticks resting across the box corner. The blurred edge of a keyboard
and a plain water bottle at the frame edge. Indoor office light, no window, no
screen content visible, no printing on the box or chopstick sleeve.
```

- **驗收**：便當盒與筷套上無店家印字；看得出是在辦公桌前吃，不是餐廳。

---

### 4. `moment_street_food_stall` ｜ NEGATIVE-B
- **tags**：food, walk, night ｜ 11 個題材（宵夜、下班散步、週末出門、夜市散步、覓食…）｜全時段
- night tag 讓它常出現在晚上，但 food tag 也會讓它落在中午——所以**不拍天空、不拍成一望即知的夜市**：收緊在攤台本身，帆布棚陰影下白天晚上都成立。

```
A close crop of a Taiwanese street food stall counter: stainless steel trays of
braised snacks (lu wei) with dark glossy sauce, steam rising, a pair of long
metal tongs resting on the tray edge, a stack of plain brown paper bags beside
it. Canvas awning shade above so no sky is visible. A few passersby far behind
the stall reduced to unrecognizable blurred shapes from behind. No readable
signs anywhere. Tight, appetite-driven framing.
```

- **驗收**：不拍天空、看不出白天晚上；攤台與紙袋上沒有字；背景人影糊到認不出。

---

### 5. `moment_bubble_tea_cup` ｜ NEGATIVE-A
- **tags**：dessert, food ｜ 8 個題材（下午沒電、午餐、晚餐、宵夜、自己做的東西、覓食…）｜全時段
- 手搖杯是台灣日常的最大公約數。**現實的封膜一定有印刷，這裡必須生成素面**。

```
A sealed plastic cup of bubble milk tea on a wooden table, dark tapioca pearls
settled at the bottom, creamy tea with visible gradient, condensation on the
cup, a fat straw lying next to it still in a plain unprinted wrapper. The seal
film on top is completely plain with no printing. Indoor ambient light, no
window, background softly blurred. Shot from a slightly high casual angle.
```

- **驗收**：封膜、杯身、吸管套全部素面無印刷；珍珠與奶茶漸層一眼可辨。

---

### 6. `moment_baking_tray` ｜ NEGATIVE-A
- **tags**：cooking, dessert ｜ 3 個題材（下午沒電、晚餐、自家廚房）｜noon-evening
- 對應 `home_kitchen` 題材的「成功或失敗都可以講」——**要有自己烤的不完美感**。

```
A baking tray of homemade cookies just out of the oven on a home kitchen
counter, slightly uneven in size and browning — clearly amateur, one cookie a
bit too dark. A worn oven mitt beside the tray, a cooling rack, light flour dust
on the counter. Warm indoor kitchen light, no window, no packaging, no labels
on anything.
```

- **驗收**：餅乾大小與上色不均（自己烤的），不是烘焙坊產品照；無包裝與品牌。

---

### 7. `moment_friends_cheers` ｜ NEGATIVE-B ★聚會
- **tags**：food, night ｜ 8 個題材（午餐、晚餐、宵夜、週末早午餐、現場演出、覓食、夜晚散步、下班）｜全時段
- 「跟朋友吃熱炒」的乾杯瞬間。**手只能在畫面邊緣、帶動態模糊**；驗收要逐隻數手指。

```
Several glasses of beer clinking together in mid-air over a crowded Taiwanese
stir-fry restaurant table, slight motion blur on the glasses, foam sloshing over
one rim. The table below packed with shared dishes mid-meal. Hands enter only
from the frame edges and are slightly motion-blurred; no faces anywhere in
frame. Warm noisy restaurant light, background diners dissolved into
unrecognizable blur. No readable text on anything.
```

- **驗收**：碰杯是主角；手只在邊緣且帶模糊、手指數量正確；全畫面零臉；背景人影認不出。

---

### 8. `moment_hotpot_table` ｜ NEGATIVE-A ★聚會
- **tags**：food ｜ 6 個題材（午餐、晚餐、宵夜、週末早午餐、覓食、下班）｜全時段
- 人不入鏡，**靠四人份餐具與吃到一半的碗**表達「一群人正在吃」。室內無窗＝時段不可讀。

```
A bubbling hotpot in the middle of a dining table set for four, photographed
from one seat: several bowls with different half-eaten contents, multiple pairs
of chopsticks resting at different angles, plates of raw ingredients waiting
their turn, steam rising and slightly fogging the scene. Warm indoor light, no
window, no people in frame — the crowded place settings alone show a gathering
mid-meal. No readable labels on anything.
```

- **驗收**：四人份餐具＋吃到一半的碗（無人入鏡也讀得出「一群人」）；蒸氣有現場感；無窗。

---

### 9. `moment_ktv_room` ｜ NEGATIVE-A ★聚會
- **tags**：music, night ｜ 3 個題材（宵夜、現場演出／單曲循環、夜晚散步）｜evening-late_night
- KTV 包廂「大家剛起身去唱」的瞬間。**螢幕只能是抽象色彩糊光**。

```
Inside a Taiwanese KTV private room: two wireless microphones and a tambourine
on the low table among half-finished drinks and a fruit plate, the big screen
in the background glowing with abstract colorful blur showing no readable
interface or lyrics, dim neon accent lighting along the ceiling. No people in
frame, cushions pressed and drinks unfinished as if everyone just got up to
sing. No readable text on the screen, remote, or menus.
```

- **驗收**：螢幕零可讀介面與字幕；包廂「正在被使用」但無人入鏡；霓虹暗光不過曝。

---

### 10. `moment_cafe_two_cups` ｜ NEGATIVE-B ★聚會
- **tags**：cafe, dessert ｜ 6 個題材（第一杯、下午沒電、週末早午餐、咖啡店踩點、自己做的東西、開店）｜morning-evening
- 「跟閨蜜下午茶」：**對面的座位入鏡但無人**，兩側各咬一口的蛋糕是對面有人的證據。

```
A small cafe table set for two photographed from one seat: two different coffee
cups, two forks, and one shared slice of cake with bites taken from opposite
sides, crumbs on both sides of the plate. The empty chair across the table
softly blurred, a jacket draped over its back. One or two patrons far in the
background heavily blurred and unidentifiable. Warm indoor cafe light, no
window, no readable menu or logo.
```

- **驗收**：兩杯兩叉一份蛋糕、兩側各有咬痕（對面有人的證據）；椅背有外套但無人；背景人影認不出。

---

### 11. `moment_viewpoint_drinks` ｜ NEGATIVE-A ★聚會
- **tags**：walk, outdoor, travel ｜ 8 個題材（下班散步、週末出門、隨手拍、旅行、海邊、上山、夜晚散步、落地）｜全時段
- 「跟朋友走到觀景台」：**並排的兩杯手搖飲**＝同行者的證據。霧面平光＝時段與地點不可讀。

```
Two cups of Taiwanese hand-shake tea standing side by side on a weathered
railing at a lookout, straws in both, light condensation on the cups, city
rooftops dissolved into haze far below. Both cups completely plain with no
printing. Overcast diffuse light so the hour cannot be read, muted grey-green
palette. No people in frame — two drinks on the railing imply the two friends
behind the camera. No recognizable landmark in the haze.
```

- **驗收**：兩杯並排（同行者的證據）；杯身無印刷；霧中無指標性建築；讀不出時段。

---

### 12. `moment_rainy_alley` ｜ NEGATIVE-A
- **tags**：rain, city ｜ 5 個題材（下雨天、下班散步、週末出門、隨手拍、夜晚散步）｜全時段
- 讓 `rainy_mood` 不再永遠配同一扇窗（`moment_rainy_window`）。這張是**出門版的雨**。

```
A narrow Taipei lane in the rain photographed from under an arcade edge: wet
asphalt with strong mirror-like reflections, a row of parked scooters under wet
rain covers, old apartment facades softened by rain haze. Overcast flat grey
light so the hour cannot be read. All distant signboards completely out of
focus and unreadable. No people, no umbrellas anywhere in frame.
```

- **驗收**：地面反光是主角；所有招牌糊到讀不出；灰平光看不出時段；無人無傘。

---

### 13. `moment_bus_window_rain` ｜ NEGATIVE-A
- **tags**：commute, rain ｜ 4 個題材（通勤、下雨天、旅行計畫、落地出勤）｜全時段
- 「在車上」的證據要在畫面裡（座椅或扶手邊角），否則只是一張濕玻璃。

```
Rain-streaked window of a city bus photographed from a seat inside: raindrops
sharp on the glass, the street outside dissolved into soft grey and muted
color blobs of traffic. The edge of the seat back in front and a metal handrail
just entering the frame corner as proof of being on board. Neutral overcast
light, nothing readable outside, interior plain with no route signs or screens.
```

- **驗收**：座椅／扶手邊角入鏡（證明在車上）；窗外糊到認不出地點；車內無路線圖或字。

---

### 14. `moment_scooter_helmet` ｜ NEGATIVE-A
- **tags**：commute, city ｜ 7 個題材（通勤、下班散步、週末出門、隨手拍、旅行、夜晚散步、落地）｜全時段
- 機車通勤是台灣感最高的通勤畫面，而且零文字風險。騎樓陰影＝任何時段都成立。

```
A plain matte helmet resting on the seat of a parked scooter in a Taipei arcade
(qilou) parking row, keys still hanging from the ignition. Tiled arcade columns
and a row of other scooters blurred behind. Even shade under the arcade so the
time of day cannot be read. The helmet has no stickers or graphics, no license
plate legible anywhere in frame.
```

- **驗收**：安全帽素面無貼紙；車牌不可辨識；騎樓陰影下看不出時段。

---

### 15. `moment_open_book_blanket` ｜ NEGATIVE-A
- **tags**：book, calm ｜ 10 個題材（回家癱、週末耍廢、看書、追劇、下班…）｜全時段
- 與 `moment_bookshelf`（書櫃全景）錯開：這張是**看到一半的那本書**。

```
A paperback book lying face-down and open on a soft knitted blanket on a sofa,
clearly paused mid-read, the spine gently creased. A corner of a plain mug on a
side table blurred in the background. Warm lamp light from one side, the rest
of the room falling into shadow, no window or clock in frame. Cover and pages
angled so no text is readable.
```

- **驗收**：書面朝下攤著（讀到一半的感覺）；書封與頁面都讀不出字；無窗無鐘。

---

### 16. `moment_headphones_lamp` ｜ NEGATIVE-A
- **tags**：music, calm ｜ 9 個題材（回家癱、週末耍廢、追劇、單曲循環、下班…）｜全時段
- 讓 `live_music` 題材的「最近單曲循環的歌」有居家版的圖可配。

```
A pair of plain over-ear headphones resting on a small bedside table under a
warm lamp, cable loosely coiled, a phone lying face-down beside them showing no
screen content. The rest of the room falls away into soft darkness, curtains
drawn feel, no window or clock visible so the hour cannot be read. No brand
marks on the headphones.
```

- **驗收**：耳機無品牌標；手機面朝下無畫面；房間暗但沒有可讀時間的線索。

---

### 17. `moment_harbor_boats` ｜ NEGATIVE-A
- **tags**：sea, travel ｜ 3 個題材（旅行計畫、海邊的一天、落地出勤）｜全時段
- 台灣**漁港**，不是遊艇碼頭。travel 類圖的語意是「回憶／計畫中的片段」，白天的照片配深夜的貼文成立（跟第一批 `moment_train_window` 同一邏輯）。

```
A small Taiwanese fishing harbor on an overcast day: moored working fishing
boats with weathered hulls, old tires hung along the concrete pier edge as
fenders, grey-green water, low hills hazy in the distance. Flat diffuse light,
damp coastal atmosphere. Any registration numbers on the hulls too far or too
blurred to read. No people on the boats or pier.
```

- **驗收**：漁船＋輪胎護舷的漁港感，不是遊艇；船身編號讀不出；灰綠陰天不是度假島。

---

### 18. `moment_temple_incense` ｜ NEGATIVE-A
- **tags**：travel, city ｜ 6 個題材（下班散步、週末出門、隨手拍、旅行、夜晚散步、落地）｜全時段
- **本批文字風險最高的一張**：匾額、燈籠、籤詩全是字。拍局部、拍煙，字全部排除或糊掉。

```
A quiet corner of a Taiwanese temple courtyard: a large coiled incense spiral
hanging overhead with a thin ribbon of smoke, part of a carved stone censer
below, one red pillar and the edge of a curved roof eave. Overcast soft light.
Framing deliberately tight on the incense and smoke so that no plaques,
lanterns with writing, or fortune-slip cabinets are in frame; any distant
ornament completely out of focus. No people.
```

- **驗收**：畫面裡零可讀文字（匾額燈籠都不入鏡或全糊）；是隨手一角不是觀光大景。

---

### 19. `moment_riverside_track` ｜ NEGATIVE-A
- **tags**：fitness, outdoor ｜ 5 個題材（練完、上山、海邊、帶完課、教練日）｜morning-evening
- 與第一批 `moment_dog_walk`（同樣在河濱）必須構圖可分：**無狗、無對岸天際線特寫**，改拍腳下那段路。

```
A ground-level view down an empty riverside running path in Taipei: smooth
asphalt with a painted dividing line (no words on the ground), grass strips on
both sides, the grey floodwall running along one edge, a distant bridge reduced
to a pale silhouette in haze. Overcast flat light, slightly humid atmosphere.
No people, no dogs, no readable markings.
```

- **驗收**：與 `moment_dog_walk` 一眼可分（無狗、視角貼地、不拍對岸天際線）；地面標線無文字。

---

### 20. `moment_sketchbook_desk` ｜ NEGATIVE-A
- **tags**：art, desk ｜ 5 個題材（工作卡關、看展、報告、論文、趕稿夜）｜全時段
- 給設計師／插畫家角色的桌面。塗鴉必須**抽象、非文字、非人像**，不得像任何既有作品。

```
An open sketchbook on a work desk under a warm desk lamp, filled with loose
abstract pencil marks and gesture scribbles — purely non-figurative, no letters,
no faces, no recognizable objects. Scattered pencils, a kneaded eraser, pencil
shavings on the desk. The rest of the room falls into shadow so the hour cannot
be read. No readable text anywhere.
```

- **驗收**：塗鴉是抽象筆觸（非文字、非人像、不像任何既有作品）；房間暗處無時間線索。

---

## 6. 交件前檢查

```bash
# 兩批合計 40 張、都是 960x720、單張沒超標、總量在預算內
ls assets/images/practice_moments/*.webp | wc -l          # 要是 40
magick identify -format '%f %wx%h %[size]\n' assets/images/practice_moments/*.webp
find assets/images/practice_moments -name '*.webp' -size +150k   # 要是空的
du -ch assets/images/practice_moments/*.webp | tail -1           # 要 ≤ 2.0M

# 檔名與本文件 §5 對帳（catalog 還沒有這些 id，所以對文件不對 catalog）
for id in moment_iced_latte moment_breakfast_shop_table moment_bento_lunch \
  moment_street_food_stall moment_bubble_tea_cup moment_baking_tray \
  moment_friends_cheers moment_hotpot_table moment_ktv_room \
  moment_cafe_two_cups moment_viewpoint_drinks moment_rainy_alley \
  moment_bus_window_rain moment_scooter_helmet moment_open_book_blanket \
  moment_headphones_lamp moment_harbor_boats moment_temple_incense \
  moment_riverside_track moment_sketchbook_desk; do
  [ -f "assets/images/practice_moments/${id}.webp" ] || echo "MISSING: ${id}"
done   # 不得有任何 MISSING

flutter analyze
```

人眼檢查（與第一批同一套，外加人物三條）：每張縮到 240px 還說得出是什麼；40 張擺在一起是同一家人的色調；放深紫底 `#1F1330` 上不刺眼、無大面積純白；逐張核對 §5 的驗收行；**含人物的每張逐一確認：零可辨識人臉、發文者不入鏡、邊緣的手手指數量正確**。

---

## 7. 授權紀錄

新增 `docs/licenses/practice_moment_scene_assets_batch2.md`，格式照第一批的最終版
（`docs/licenses/practice_moment_scene_assets.md`）：生成模型與日期、候選數／入選版本表、
尺寸與總 bytes、人工檢查描述（**可辨識人臉**／可辨識文字／第三方作品／品牌標識未發現；
含人物的張數與其人物型態——背影／邊緣的手／遠景糊影——逐張列出）、
生成結果不保證唯一與 OpenAI 條款連結。生成輸入指向本文件。

---

## 8. 接線清單（不在本批範圍，素材合併後另開 PR）

素材進 repo 後**不會有任何行為改變**，因為 catalog 還不認識這些 id。啟用的完整清單：

1. **`moments_image_catalog.ts`**：`MOMENT_IMAGES` 追加 20 筆（tags 照 §5；全部使用既有
   `MomentImageTag`，不需要動型別）：

   ```ts
   { id: "moment_iced_latte", tags: ["coffee", "cafe"] },
   { id: "moment_breakfast_shop_table", tags: ["food", "cafe"] },
   { id: "moment_bento_lunch", tags: ["food", "work"] },
   { id: "moment_street_food_stall", tags: ["food", "walk", "night"] },
   { id: "moment_bubble_tea_cup", tags: ["dessert", "food"] },
   { id: "moment_baking_tray", tags: ["cooking", "dessert"] },
   { id: "moment_friends_cheers", tags: ["food", "night"] },
   { id: "moment_hotpot_table", tags: ["food"] },
   { id: "moment_ktv_room", tags: ["music", "night"] },
   { id: "moment_cafe_two_cups", tags: ["cafe", "dessert"] },
   { id: "moment_viewpoint_drinks", tags: ["walk", "outdoor", "travel"] },
   { id: "moment_rainy_alley", tags: ["rain", "city"] },
   { id: "moment_bus_window_rain", tags: ["commute", "rain"] },
   { id: "moment_scooter_helmet", tags: ["commute", "city"] },
   { id: "moment_open_book_blanket", tags: ["book", "calm"] },
   { id: "moment_headphones_lamp", tags: ["music", "calm"] },
   { id: "moment_harbor_boats", tags: ["sea", "travel"] },
   { id: "moment_temple_incense", tags: ["travel", "city"] },
   { id: "moment_riverside_track", tags: ["fitness", "outdoor"] },
   { id: "moment_sketchbook_desk", tags: ["art", "desk"] },
   ```

2. **同檔 `AVAILABLE_MOMENT_IMAGE_IDS`**：把 20 個新 id 加進去。舊版 client（bundle 裡
   沒有這批圖）收到新 id 時由 `resolveMomentImage()` 降級純文字，不會破圖——這是
   `practice_moment_image.dart` 開頭明訂的向前相容鐵則，可以先開閘門不等全員更新。
3. **測試更新**：`moments_schedule_test.ts:193` 與 `moments_image_gate_test.ts:31` 都把
   `SCENE_IMAGE_COUNT` 釘在 20，接線時一併改 40（`SCENE_IMAGE_COUNT` 本身是
   `MOMENT_IMAGES.length - 1` 自動推導，不用手改）。
4. **client `_sceneImageAssets`**（`practice_moment_image.dart`）：兩批共 40 筆
   id → asset 路徑對照一起補（第一批接線若已完成，則只補本批 20 筆）。
5. `pubspec.yaml` **不用動**（目錄已註冊）。

---

## 9. 刻意不做

- **不做可辨識的人臉，包含「她與朋友的合照自拍」。** 這不是本批的取捨，是共用素材的
  架構限制（§3 第 1 條）：臉一旦入鏡就會被讀成「她」或「她的朋友」，而同一張圖配給
  100 位角色。真的要做「她跟朋友的合照」只有一條路——**per-character 素材**：以每位角色
  的圖鑑照為基準做人臉一致性生成，每位 1-2 張。成本：100-200 張新圖 ≈ +13-26 MB bundle
  （等於再放一份角色圖鑑）或改走 Storage/CDN（設計報告 D3 已否決過的基礎設施），外加
  推翻設計報告 §7.4「不得生成像真實人物的新圖」。屬另案，需 Eric 專項拍板。
- 不新增 `MomentImageTag`（tag 面不動，主題池不動）。
- 不補 `sky` tag 的第二張（晨昏兩可的天空一張剛好，多了互相稀釋）。
- 不在本批動 catalog、client 對照、`pubspec.yaml`——素材與接線分開交付、分開回退。
