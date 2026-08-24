# 練習室動態：20 張情境圖生成 Prompt 包

2026-08-24。給 Codex（或任何生圖模型）直接執行用的素材規格書。

**這份文件解決什麼**：`supabase/functions/practice-chat/moments_image_catalog.ts` 已經宣告了 20 個場景圖 id，但**素材檔案還不存在**——所以 `AVAILABLE_MOMENT_IMAGE_IDS` 目前只有自拍 sentinel，動態 feed 現在是一面自拍牆。這 20 張補齊之後，開閘門就好，生成端與 UI 一行都不用改（設計報告 D5c）。

**範圍**：只產出素材與驗收標準。程式接線（`pubspec.yaml`、client 對照表、閘門）列在 §8，**不在這次的範圍**，等圖進來再另一個 PR 做。

---

## 1. 交付規格（硬性）

| 項目 | 規格 | 理由 |
| --- | --- | --- |
| 張數 | **20 張**，一個 id 一張 | id 清單見 §5，多一張少一張都對不上 allowlist |
| 檔名 | `<id>.webp`，例如 `moment_coffee_cup.webp` | client 靠 id 對照，檔名寫錯＝那個題材永遠降級成純文字 |
| 路徑 | `assets/images/practice_moments/` | 新目錄，尚未存在 |
| 格式 | **WebP**（有損，q78-82） | 設計報告決策 2 |
| 尺寸 | **960 × 720（4:3）** | 見下方換算 |
| 單張體積 | **≤ 130 KB**，硬上限 150 KB | |
| 總體積 | **≤ 2.6 MB**（設計報告給的預算是 2-3 MB） | 現況 100 張角色照已佔 13 MB，App 體積是真的在被盯的 |
| 色彩 | sRGB，去掉所有 EXIF/ICC 以外的中繼資料 | |

**尺寸怎麼來的**：`practice_moment_tile.dart` 的配圖框是 `kMomentImageAspectRatio = 4/3`、`kMomentImageMaxHeight = 180`、寬度取文字欄的 0.72 倍。最大裝置上實際渲染是 **240 × 180 pt**，@3x ＝ 720 × 540 px。960 × 720 留 1.33 倍餘裕，足夠且不浪費體積。`BoxFit.cover` ＋ 素材本身就是 4:3 ⇒ 不會被裁到。

---

## 2. 生成到入庫的管線

生圖模型多半不給 4:3。**用 3:2（1536 × 1024）出圖，再置中裁成 4:3**，所以：

> **構圖鐵則：把主體放在畫面中央的 4:3 範圍內，左右兩側各留約 6% 當犧牲區，不要放任何重要東西。**

```bash
# 每個 id 先生 3 張候選存進 raw/（raw 不進 repo）
# 1536x1024 → 置中裁 1365x1024（4:3）→ 縮到 960x720 → WebP
magick "raw/${id}_a.png" \
  -gravity center -crop 1365x1024+0+0 +repage \
  -resize '960x720!' -strip \
  -define webp:method=6 -quality 80 \
  "assets/images/practice_moments/${id}.webp"
```

若生圖只給 1024 × 1024，改成 `-crop 1024x768+0+0`（一樣置中）。

驗收指令：

```bash
# 20 張、都是 960x720、沒有超過 150KB 的
ls assets/images/practice_moments/*.webp | wc -l          # 要是 20
magick identify -format '%f %wx%h %[size]\n' assets/images/practice_moments/*.webp
find assets/images/practice_moments -name '*.webp' -size +150k   # 要是空的
du -ch assets/images/practice_moments/*.webp | tail -1           # 要 ≤ 2.6M
```

---

## 3. 全域硬規則（每一條都有理由，不要繞過）

1. **畫面裡不能有人。** 沒有臉、沒有手、沒有身體部位、沒有背影主角。例外只有兩個：`moment_street_night` 遠處極小的模糊路人、`moment_live_stage` 觀眾席的黑色頭部剪影——兩者都必須認不出是誰。
   *理由*：設計報告 §7.4「不得生成像真實人物的新圖」，這一刀同時把 App Review 的肖像風險與 AI 畫手的破綻全部消掉。而且同一張圖會配給 100 位不同角色，畫面裡一出現人就等於替她們每個人指定了長相。
2. **畫面裡不能有可讀的字。** 沒有招牌、沒有 logo、沒有品牌標、沒有書名、沒有展品說明牌、沒有站名、沒有螢幕上的介面文字。需要招牌氛圍時一律**失焦到讀不出來**。
   *理由*：貼文可見文字端已經禁止真實品牌／店名／地址（`moments_prompt.ts`），圖片端破功等於白做；而且中文字是生圖模型最常畫錯的東西。
3. **時間必須讀不出來**，除非那張圖本來就綁定夜晚。
   *理由*：配圖是靠 tag 交集挑的，同一張圖會跨時段出現——例如 `moment_coffee_cup` 會出現在 14 個題材、清晨到深夜全時段。畫成一望即知的晨光，晚上 11 點的貼文配它就會出戲。**做法：室內場景不要拍到窗外天空，用室內光當主光源。**
   夜晚綁定的只有 `moment_live_stage`（只在 evening／late_night 出現）。
4. **台灣感，不是 Pinterest 感。** 角色都住台北。場景要是台灣人認得的日常：老公寓廚房、騎樓、河濱步道、亞熱帶石階步道、東北角海岸、社區小健身房。不要北歐極簡樣品屋、不要歐美郊區、不要日式和室。
5. **手機隨手拍，不是商業攝影。** 構圖可以歪一點、不完美、有生活痕跡（桌上的水漬、沒收的抹布、翻面的書）。不要打光完美的產品照、不要俯拍擺盤網美圖、不要 HDR。
   *理由*：要跟角色照片同一種語言（現有 100 張是手機自拍質感的寫實照）。
6. **深色 UI 上要好看。** 底色是 `#150C24 → #2A1840` 的深紫漸層，圖片圓角 18。避免大面積純白與過曝高光（在深底上會刺眼），偏暖中性調、陰影不要壓死。
7. **小尺寸要讀得懂。** 實際只有 220 × 165 pt。主體要佔畫面 40-60%、背景乾淨、不要塞細節。
   *驗收法*：把圖縮到 240px 寬看一眼，說不出「這是什麼」就重生。
8. **不得重現既有的真實作品**（`moment_exhibition_wall` 的畫必須是抽象原創）、不得出現真實可辨識的地標建築。

---

## 4. 共用前綴與負面詞（直接複製到每一條 prompt）

**STYLE（接在每條 prompt 前面）**

```
Amateur smartphone photograph, taken casually with one hand. No people in frame.
Everyday life in Taipei, Taiwan, present day. Natural available light, soft and
slightly warm color, gentle contrast with lifted shadows, mild lens softness and
fine sensor grain. Slightly imperfect framing, lived-in and unstaged. Photorealistic.
Keep the main subject inside the central 4:3 area of the frame; leave the far left
and far right edges empty.
```

**NEGATIVE（每條都掛）**

```
people, person, face, hands, fingers, body parts, portrait, crowd close-up,
text, letters, words, chinese characters, japanese characters, signage, labels,
book titles, logos, brand marks, watermark, UI, screen content, captions,
illustration, anime, painting, 3D render, CGI, AI-glossy look, HDR, oversaturated,
neon oversaturation, heavy vignette, blown-out highlights, pure white background,
studio product lighting, perfectly styled flat lay, stock photo look, collage,
split frame, border, frame, blur over the whole image, tilt-shift toy effect
```

---

## 5. 20 條 Prompt

每一張都標了「會出現在幾個題材／哪些時段」——那是 `moments_schedule.ts` 主題池與 `moments_image_catalog.ts` 標籤交集算出來的實際使用面，**不是參考資訊，是這張圖必須撐得住的範圍**。

> 註：`moment_self_portrait` 是 sentinel（用她自己的圖鑑照片），**不需要生圖**，所以是 20 張不是 21 張。

---

### 1. `moment_coffee_cup`
- **tags**：coffee, cafe, calm ｜ **14 個題材**（今天第一杯、下午沒電、回家癱、週末早午餐、咖啡店踩點、追劇、下班、診所日、實驗室、開店、帶完課、花店…）｜**全時段**
- **最高使用率的三張之一。時間必須完全讀不出來。**

```
A single coffee cup on a plain wooden table, seen from a slightly high casual
angle. Either a plain unbranded ceramic mug with milky coffee, or a plain white
takeaway cup with a plain lid. A faint coffee ring on the wood, a folded paper
napkin half under the cup. Indirect indoor light coming from one side, no window
and no sky anywhere in frame, so the hour of the day is impossible to tell.
Warm neutral tones, quiet and unhurried, shallow depth of field with the far
side of the table falling out of focus.
```

- **驗收**：看不出早上或晚上；杯子上沒有任何標誌；縮到 240px 還是一眼「一杯咖啡」。

---

### 2. `moment_cafe_corner`
- **tags**：cafe, work, desk ｜ **8 個題材**（工作卡關、趕稿夜、報告、論文、開店、咖啡踩點…）｜**全時段**
- 也會配在 `deadline_night`（深夜趕稿），所以**不能有白天的窗光**。

```
An empty corner seat in a small independent Taipei cafe: a worn wooden two-person
table, one plywood or rattan chair pushed slightly out, a glass of water and a
closed notebook on the table. A low shelf with a couple of plants and stacked
cups behind. A warm pendant lamp is the main light; a curtain is half drawn so
the outside is only a soft indistinct glow with no sky and no readable signage.
Nobody in the room. Slightly cluttered, lived-in, faint scuffs on the furniture.
```

- **驗收**：房間裡沒有人也沒有正在被使用的痕跡以外的東西；窗外看不出白天黑夜。

---

### 3. `moment_dessert_plate`
- **tags**：dessert, cafe, food ｜ **11 個題材**（午餐、下午想吃糖、晚餐、宵夜、自己做的甜點、吃到好吃的…）｜**全時段**

```
A slice of cake or a small simple dessert on a plain ceramic plate on a wooden
table, one bite already taken, a fork resting on the rim. The edge of a cup of
tea or coffee enters the corner of the frame. Casual angle from a seated person's
eye level, slightly tilted. Plain unbranded tableware, a crumb or two on the
plate. Soft indoor light from the side, no window in frame. Home or small cafe.
```

- **驗收**：已經吃了一口（＝真的在吃，不是擺拍）；沒有店家餐墊或品牌瓷器。

---

### 4. `moment_home_cooking`
- **tags**：cooking, food ｜ **7 個題材**（午餐、晚餐、宵夜、週末早午餐、自己下廚、吃到好吃的、下班後…）

```
A small Taipei apartment kitchen counter in the middle of cooking: a pan on a gas
stove with vegetables just going in, a wooden chopping board with chopped scallion
and garlic beside it, a small bowl of sauce. A little steam. A dish towel thrown
over the counter edge, a condiment bottle with its label turned away from camera.
Warm overhead kitchen light only, no window in frame. Real and slightly messy,
not a cooking-show set.
```

- **驗收**：調味料瓶標籤一律轉開或糊掉；不要空無一物的樣品屋廚房。

---

### 5. `moment_late_night_snack`
- **tags**：food, night ｜ **8 個題材**｜**注意：也會被 `lunch_break`／`food_find` 挑中，出現在中午**
- 所以**不要拍成一望即知的深夜**：靠室內暖燈當唯一光源、不拍窗，讓時間讀不出來。

```
A single bowl of instant noodles or a simple snack on a small table at home,
chopsticks resting across the bowl, a glass of water beside it, steam rising.
A warm yellow lamp overhead is the only light source and the background falls
away into soft darkness. No window, no clock, no phone screen in frame. Cosy and
a little guilty, completely unstyled, one plain bowl on a bare tabletop.
```

- **驗收**：畫面裡沒有任何「現在是幾點」的線索。

---

### 6. `moment_street_night`
- **tags**：night, city, walk ｜ **6 個題材**（下班散步、宵夜、週末出門、看表演、隨手拍、夜間散步）｜**理論上全時段**（`photo_walk` 不限時段）
- 折衷做法：**拍藍調時刻（blue hour）而不是深夜**——傍晚到深夜都成立，白天被挑中時也不會像半夜。

```
A quiet Taipei back street at blue hour just after sunset. Wet-looking asphalt
reflecting warm shop light, a row of parked scooters along the curb, a covered
arcade walkway with worn tiles, tangled overhead power cables, one old banyan
tree. Shop signs exist but are thrown far out of focus so no character is
readable. The sky still holds deep blue light. No people, or at most one tiny
distant blurred silhouette far down the street.
```

- **驗收**：招牌完全讀不出字；天空還有藍不是全黑；沒有可辨識的人。

---

### 7. `moment_sunset_sky`
- **tags**：sky, calm, outdoor ｜ **15 個題材＝使用率最高的一張**（通勤、下班、看到好天色、回家癱、週末耍廢、隨手拍、海邊、爬山、下班後、診所日、落地、帶完課、花店…）｜**全時段，含清晨與早上**
- **最關鍵的一張：必須同時能當「清晨」與「黃昏」讀。** 不要橘紅火燒雲。

```
A wide sky seen from a rooftop or from between apartment buildings. Soft gradient
from pale peach through lavender into light blue, thin scattered clouds catching
gentle light. Along the bottom edge, silhouetted rooftops, a water tower and a few
utility poles and cables. No sun disk visible and no strong orange fire in the
sky, so it could equally be early morning or dusk. Slightly hazy humid air, calm,
low contrast.
```

- **驗收**：把圖給人看問「這是早上還是傍晚」，答不出來就對了。

---

### 8. `moment_sea_view`
- **tags**：sea, travel, outdoor ｜ **4 個題材**（規劃旅行、海邊的一天、爬山、落地）

```
The northeast coast of Taiwan seen from a low seawall: dark volcanic rock in the
foreground, pale turquoise-grey water, small white waves breaking, a distant
headland under a soft bright overcast horizon. Slightly hazy. Cool but not cold
color, muted rather than tropical-postcard. No people, no boats, no buildings.
```

- **驗收**：不要熱帶度假島嶼感；要台灣海岸的灰綠潮濕感。

---

### 9. `moment_mountain_trail`
- **tags**：outdoor, nature, fitness ｜ **6 個題材**（海邊、練完、爬山、帶完課、教練日、花店）

```
A subtropical Taiwan hiking trail: worn stone steps climbing up through dense
green ferns and thin bamboo, a rope handrail on one side, dappled light coming
through the canopy, humid air with a little haze between the trees. Camera tilted
slightly, framed as if taken during a pause to catch breath. No people, no trail
markers with readable text.
```

- **驗收**：亞熱帶石階步道（象山／陽明山那種），不要高山針葉林或歐美泥土步道。

---

### 10. `moment_gym_corner`
- **tags**：fitness ｜ **3 個題材**（練完、帶完課、教練日）｜morning／early_evening／evening

```
A corner of a small neighbourhood gym just after a session: a rack of dumbbells,
a rubber-floor training area, a flat bench with a towel and a water bottle left
on it. A wall mirror reflects only the empty room. Cool ceiling light mixed with
one warm strip along the wall. Nobody in the room, no readable brand names on
any equipment.
```

- **驗收**：鏡子裡不能反射出人；器材上沒有品牌字樣。

---

### 11. `moment_yoga_mat`
- **tags**：fitness, calm ｜ **10 個題材**（回家癱、週末耍廢、追劇、練完、穿搭保養、下班後、診所日、帶完課、教練日、花店）｜**全時段**

```
A yoga mat unrolled on a wooden floor at home, a folded blanket and a cork block
at one end, a water bottle and a phone lying face-down beside it. Soft even light
with no visible window and no visible lamp, so the hour is unreadable. A few
plant leaves enter one corner of the frame. Quiet empty room, nobody present.
```

- **驗收**：墊子有使用痕跡（不是全新）；房間裡沒有人。

---

### 12. `moment_cat_nap`
- **tags**：pet, calm ｜ **9 個題材**（回家癱、週末耍廢、追劇、家裡那隻、穿搭、下班後、診所日、帶完課、花店）｜**全時段**

```
A short-haired mixed-breed cat asleep curled up on a rumpled fabric sofa at home,
seen from slightly above as if by someone standing next to it. A knitted blanket
half kicked aside, the corner of a book. Soft indoor light with no visible window.
Nothing staged, no people in frame, no pet products with labels.
```

- **驗收**：貓要是常見的米克斯短毛（不是名種展示照）；沒拍到人。

---

### 13. `moment_dog_walk`
- **tags**：pet, outdoor, walk ｜ **7 個題材**（下班散步、週末出門、隨手拍、海邊、爬山、家裡那隻、夜間散步）｜**全時段**

```
A small or medium mixed-breed dog seen from behind and slightly above during a
walk on a Taipei riverside park path, a leash running out of the bottom edge of
the frame. Mown grass, a bike lane, blurred distant greenery and a bridge pier.
Soft flat light of an overcast late afternoon. No faces, no identifiable people,
no readable park signage.
```

- **驗收**：狗是背影或俯角，看不到牽繩另一端的人；光線平、不是強烈日落。

---

### 14. `moment_bookshelf`
- **tags**：book, calm ｜ **10 個題材**（回家癱、週末耍廢、看書、追劇、穿搭、下班後、診所日、報告、帶完課、花店）｜**全時段**

```
A corner of a home bookshelf with an open paperback lying face-down on a small
side table, a mug beside it, a warm lamp glowing from the left. Book spines fill
the background but every title is thrown out of focus and unreadable. Wooden
shelf, one small plant, a couple of personal objects. Cosy, low contrast,
nobody in frame.
```

- **驗收**：所有書背文字都糊到讀不出；不要圖書館或書店規模，是家裡的一角。

---

### 15. `moment_desk_work`
- **tags**：desk, work ｜ **4 個題材**（工作卡關、報告、論文、趕稿夜）｜morning／afternoon／evening／late_night
- 會配在深夜趕稿，也會配在早上上班，所以**用桌燈當主光、房間其餘壓暗**。

```
A work desk in the middle of a messy stretch: an open laptop seen from the side
with a dark screen showing no readable interface, scattered sticky notes with no
readable writing, a half-finished cold coffee, a pen on an open notebook whose
pages are blank or illegibly scribbled, one cable trailing across the desk.
A desk lamp is the only light and the rest of the room falls into shadow, so the
hour cannot be read. Nobody at the desk.
```

- **驗收**：螢幕上不能有可辨識的介面或文字；便條紙上的字必須是無意義的筆劃。

---

### 16. `moment_exhibition_wall`
- **tags**：art, city ｜ **5 個題材**（下班散步、週末出門、隨手拍、看展、夜間散步）｜**全時段**

```
A quiet wall in a small art space: two or three framed abstract works hung on a
pale grey wall, lit by track lighting from above, polished concrete floor, a plain
bench in the corner. The artworks are original abstract shapes and colour fields
that do not resemble any existing artwork. No wall labels, no readable text
anywhere. Nobody in the room.
```

- **驗收**：作品必須是原創抽象（不得像任何既有名作）；牆上沒有說明牌。

---

### 17. `moment_live_stage`
- **tags**：music, night ｜ **3 個題材**（宵夜、看表演、夜間散步）｜**只會出現在 evening／late_night**
- **唯一允許拍成夜晚的一張。**

```
A small live house stage seen from the middle of the audience: warm amber and
magenta stage lights, a guitar amp, a mic stand, light beams cutting through haze.
The audience appears only as a band of dark unlit silhouetted heads along the
bottom edge, no faces and nobody identifiable. No performers in frame, or only
indistinct distant silhouettes. No readable band name, no banner text.
```

- **驗收**：觀眾只有黑色剪影；台上沒有可辨識的人臉；沒有任何字。

---

### 18. `moment_flower_bunch`
- **tags**：calm, nature ｜ **9 個題材**（回家癱、週末耍廢、追劇、爬山、穿搭、下班後、診所日、帶完課、花店日常）｜**全時段**

```
A small bunch of cut flowers just brought home, still half wrapped in plain kraft
paper, lying on a kitchen counter next to a plain glass jar of water. Muted colours
— eucalyptus, a few pale blooms, some greenery — not a bright commercial bouquet.
Diffuse soft indoor light, plain background, a few loose leaves and a little water
on the counter. No florist branding on the wrapping paper.
```

- **驗收**：包裝紙上沒有店家印刷；花色偏柔和不是喜氣花籃。

---

### 19. `moment_rainy_window`
- **tags**：rain, calm ｜ **9 個題材**（回家癱、下雨天、週末耍廢、追劇、穿搭、下班後、診所日、帶完課、花店）｜**全時段**

```
Rain on a window seen from inside: sharp water droplets and running streaks in
focus on the glass, the world outside completely defocused into soft grey-green
shapes with two or three warm out-of-focus light blobs. The room side is dark and
stays out of frame. Neither clearly day nor clearly night. Muted, quiet,
slightly melancholic, low saturation.
```

- **驗收**：水珠是清楚的、窗外是完全化開的；沒有可辨識的建築或招牌。

---

### 20. `moment_train_window`
- **tags**：commute, travel ｜ **3 個題材**（早上通勤、規劃旅行、落地）｜morning／afternoon／evening／late_night

```
The view out of a train window: the edge of the window frame and the top corner
of a seat back in the lower foreground, outside are motion-blurred rice fields,
low houses and soft hills of western Taiwan under an even overcast sky. A faint
reflection of the carriage interior on the glass. Muted daylight, calm, no
readable signs, no people, no visible train livery or logo.
```

- **驗收**：車窗框與座椅角落要在（證明是「從車上拍」）；玻璃反射裡不能有人。

---

## 6. 交件檢查表

生完 20 張逐條打勾：

- [ ] `assets/images/practice_moments/` 下正好 20 個 `.webp`，檔名與 §5 的 id **逐字相同**（可用下方指令對）
- [ ] 每張 960 × 720、≤ 130 KB，總計 ≤ 2.6 MB
- [ ] 每張都**沒有人臉、沒有手**（例外：#6 遠處模糊路人、#17 觀眾黑剪影）
- [ ] 每張都**沒有任何可讀的文字或 logo**（招牌、書名、包裝、螢幕、說明牌）
- [ ] 除了 #17，每張都**看不出時間**（室內圖沒有拍到窗外天空）
- [ ] #7 `moment_sunset_sky` 早／晚兩讀（最容易做壞的一張）
- [ ] 每張縮到 240px 寬還說得出「這是什麼」
- [ ] 放在 `#1F1330` 深紫底上看不刺眼、沒有大面積純白
- [ ] 20 張擺在一起色調是同一家人（不要有一張特別冷或特別飽和）

檔名對照（複製這段去核對）：

```
moment_coffee_cup        moment_cafe_corner       moment_dessert_plate
moment_home_cooking      moment_late_night_snack  moment_street_night
moment_sunset_sky        moment_sea_view          moment_mountain_trail
moment_gym_corner        moment_yoga_mat          moment_cat_nap
moment_dog_walk          moment_bookshelf         moment_desk_work
moment_exhibition_wall   moment_live_stage        moment_flower_bunch
moment_rainy_window      moment_train_window
```

```bash
# 檔名與 Edge allowlist 對帳（差集要是空的）
diff <(ls assets/images/practice_moments | sed 's/\.webp$//' | sort) \
     <(grep -o 'moment_[a-z_]*' supabase/functions/practice-chat/moments_image_catalog.ts \
       | grep -v self_portrait | sort -u)
```

---

## 7. 已知取捨（不是 bug，是這次刻意接受的）

配圖是靠「題材 tag ∩ 圖片 tag」挑的，所以會有時段錯配的邊緣情況：

| 情況 | 為什麼會發生 | 這次的處理 |
| --- | --- | --- |
| `moment_late_night_snack` 出現在中午的 `lunch_break` | 它同時帶 `food` 與 `night` | 用「室內暖燈、不拍窗」讓時間讀不出來 |
| `moment_street_night` 出現在早上的 `photo_walk` | `photo_walk` 不限時段且帶 `city` | 改拍藍調時刻而不是深夜 |
| `moment_sunset_sky` 出現在早上的 `morning_commute` | 它帶 `sky` | 畫成清晨／黃昏兩可的粉紫天色 |

真正的根治是把 `moments_schedule.ts` 的題材 tag 收窄或給圖片加時段欄位——**那要動已經上線的排程純函式，屬另案**，素材先照上面的方式規避。

---

## 8. 素材到位之後要改的三個地方（本次不做）

給接手的人：圖進來之後只有這三處，UI 與生成端一行都不用改（設計報告 D5c，`moments_image_gate_test.ts` 已經先把這件事測起來了）。

1. `pubspec.yaml` 的 `flutter.assets` 加一行 `- assets/images/practice_moments/`
2. `lib/features/practice_chat/domain/entities/practice_moment_image.dart` 的 `_sceneImageAssets` 補 20 筆 id → 路徑對照（目前刻意是空 map）
3. `supabase/functions/practice-chat/moments_image_catalog.ts` 的 `AVAILABLE_MOMENT_IMAGE_IDS` 把 20 個 id 加進去（目前只有自拍 sentinel）

另外要一併考慮：`moments_schedule.ts` 的 `IMAGE_PROBABILITY` 目前是 **0.15**，那是「只有自拍一種圖、避免 feed 變成自拍牆」的權宜值（Eric 2026-08-22）。素材到位後這個理由就消失了，要不要調回較高的值**由 Eric 另案拍板**。

授權紀錄（比照 `docs/licenses/practice_draw_reference_assets.md` 的格式，新開一檔）：

```markdown
# Practice Moment Scene Assets

Date: <補>

Scope:
- `assets/images/practice_moments/*.webp`（20 張情境圖）

Source:
- 由 <生圖模型／版本> 依 `docs/plans/2026-08-24-practice-moments-scene-image-prompts.md`
  的 prompt 生成，為 VibeSync 原創概念素材，非取自第三方圖庫或影片。

Usage:
- 僅用於練習室動態貼文的配圖。
- 全部不含人物、不含可辨識文字與品牌標識，亦未重現任何既有作品。
```
