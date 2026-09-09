# 導演板 B1–B9｜單幀 Prompt v2

配套：`2026-08-29-vibesync-film-60s-ice-fire-script-v2.md`
取代：`2026-08-29-vibesync-film-boards-b1-b7-prompts-v1.md`
用途：每張一個職責，給圖像模型出**單幀**用；不是影片 Prompt。工具與點數由 Eric 決定後才跑。
已驗證工具：Higgsfield `cinematic_studio_2_5`，16:9，2K，每張 2 credits；環境參考用 `medias:[{role:"image", value:"776f4f15-471d-4008-8d73-499581700aac"}]`（ENV0 V1 job）。

固定空間地圖（每張都重複）：井道垂直、重力向下、畫面下＝深處；井壁是密鋪的熄掉手機螢幕（深紫黑玻璃、細黑金屬框、冷藍細縫）；橘光永遠來自下方；沒有天空、沒有戶外、沒有機械門。

共用尾綴（每張都貼）：
`Enclosed vertical shaft whose walls are tiled with countless powered-off smartphone screens, dead dark purple-black wet glass in thin black metal frames, cold blue refraction seams, no sky, no outdoors, no ceiling light, cinematic film still, 16:9, photoreal, shallow depth, gravity clearly downward.`

共用禁止（每張都貼）：
`No text, no UI, no logos, no extra limbs, no second face, no anime, no game level look, no industrial elevator, no train tunnel, no submarine.`

環境參考句（用 ENV0 當 medias 時加在最前面）：
`Use the reference image only for the wall material and colors, not for camera or layout.`

---

## B1｜網站起霜＋手指滑掉（不生成，合成）
用真實 hero 截圖：手機占滿畫面 → 玻璃四邊起霜往中心爬 → 橘色入口鈕是唯一沒霜的地方且發光 → 最後 1 秒一隻手指抓在玻璃上緣、滑掉。
做法：Photoshop／Figma 疊霜貼圖；手指滑掉可單獨生成一張極近景（手指＋玻璃邊緣）再合成。
**已驗證視覺標準（Eric 2026-08-29 拍板）**：製片主資料夾 `08_所有付費測試影片…/影片_H264_AAC/14_PART1_R1_完整30s_195credits_H264_AAC.mp4` 的 **0–4 秒**：0–1s 手指按真實 App 學習頁的橘色 `>` 鈕（極近景）→ 1.25–4.25s 手持手機、藍白冰晶從玻璃四邊往中心結，App 畫面（AI 實戰練習室卡）仍看得到、橘鈕仍亮。關鍵幀存於 `docs/handover-screenshots/film-boards-2026-08-29/B1-ref-from-14/`；真實 App 截圖存於同層 `real-app/`。U1 後段照這個做，不重新發明。

## B2｜第一人稱倒數開始（v1 B2_a 已成立，補「螢幕剝落」變體）
Refs：`@ENV0`
```
First-person POV falling straight down a vertical shaft. Two bare male hands in the lower third of frame, fingers spread, frost crystals covering fingertips and creeping to the wrists, skin under the frost pale blue. Both side walls are motion-blurred upward. A few dark smartphone-screen panels have peeled off the walls and are flying toward the camera, about to stick to the viewer. At dead center far below, one tiny warm orange point of light. + 共用尾綴 + 共用禁止
```
證明：真墜落、冰＝倒數尺規、繭開始長、橘點在下。

## B3｜第三人稱尺度
Refs：`@M0`（身份）、`@ENV0`
```
Wide side view inside a vast vertical shaft. A lone man <<<247e5e3c-5b28-4650-be9f-4a043943f0f3>>> in dark clothes, body rigid and straight like a statue, falling head-up feet-down, arms locked at his sides with white frost covering both forearms, several dark dead phone-screen panels stuck to his shoulders and back like plates of armor. He is small in frame; the shaft walls extend far above and far below him. One tiny orange light far beneath him. Faint dust streaks moving upward past him. + 共用尾綴 + 共用禁止
```
證明：井道深度、僵直＝危險、繭在長、方向。

## B4｜Sydney 從下往上蹬牆（取代 v1 B4）
Refs：`@Sydney`（身份）、`@ENV0`
```
Medium-wide shot from slightly above. Sydney <<<db109a5a-f9a4-4999-905f-7809d5e1d69a>>> is launching UPWARD along the wall of the shaft, one boot planted hard on a dead phone-screen panel, body angled up, hair and fabric streaming downward behind her. Every screen panel her boots have touched below her is lit up warm orange, forming a trail of glowing screens leading down into the dark. Her open palm holds a small ball of warm orange fire. She looks straight up, jaw tight. + 共用尾綴 + 共用禁止
```
證明：她從井底來、火點亮螢幕、她在受力。**這張不放男主。**

## B5｜接觸極近景
Refs：無身份 ref（只有手）
```
Extreme close-up, two hands only. A woman's hand gripping a man's forearm that is encased in white frost with a dark phone-screen panel frozen onto it. Where her palm touches the ice, orange fire meets it and bursts into steam; tiny ice shards, water droplets and steam fly UPWARD. The screen panel under her palm is beginning to glow orange. No faces, no bodies beyond the elbows. + 共用尾綴 + 共用禁止
```
證明：接觸幾何、火碰冰的物理、火點亮螢幕、重力方向不丟。

## B6｜極遠景證明（v1 B6_c 已成立，補「井底微光」變體）
Refs：`@ENV0` 只
```
Extreme wide shot, locked-off camera, side view across a vast vertical shaft, its full height filling the frame from top edge to bottom edge. Dead center, one minuscule falling speck no bigger than a grain of rice, half white with frost and half glowing warm orange, a faint thread of steam rising above it. At the very bottom of the shaft, a flat horizontal surface glowing faintly like a single lit screen, reflecting the speck. Everything else is dark. + 共用尾綴 + 共用禁止
```
證明：真的掉很遠＋出口在下面。

## B7｜英雄鏡頭：站在冰繭上
Refs：`@Sydney`、`@COCOON`（若已建）、`@ENV0`
```
Medium shot, low angle. Sydney <<<db109a5a-f9a4-4999-905f-7809d5e1d69a>>> braces one hand flat against a huge tumbling cocoon of ice and dark dead phone-screen panels, three times her size, a rigid human shape dimly visible frozen inside it. Her other palm is raised high holding warm orange fire. Starting from the screen panel under her braced hand, the dead screens on the cocoon are lighting up orange one after another in an expanding ripple. Shards of ice fly upward on both sides of her, framing her. Her hair and jumpsuit are pulled upward by the fall. + 共用尾綴 + 共用禁止
```
證明：我們的「站在炎魔身上」；火贏的方法是點亮螢幕。

## B8｜繭裡面：他自己動了
Refs：無身份 ref（只有手）
```
Extreme close-up inside a frozen cocoon. A man's hand encased in white frost, seen from inside the ice; one finger is bending, cracking the frost around it, reaching toward a woman's palm pressed against the outside of the ice where a tiny, almost extinguished orange ember glows. Hairline cracks are spreading outward through the ice from his fingertip, lit orange from her side. No faces. + 共用尾綴 + 共用禁止
```
證明：主角自己做決定；裂紋從內而外。

## B9｜火贏、減速、對看、腳下光的湖（取代 v1 B7）
Refs：`@Sydney`、`@M0`、`@ENV0`
```
Medium two-shot inside the shaft. Sydney <<<db109a5a-f9a4-4999-905f-7809d5e1d69a>>> holds the man <<<247e5e3c-5b28-4650-be9f-4a043943f0f3>>> by both shoulders, their bodies nearly stopped mid-air. The ice cocoon around him has just shattered outward; its fragments are dark phone-screen panels, each one lighting up warm orange as it flies UPWARD past them, with meltwater droplets and steam rising too. Her palm fire is a tiny ember. His fingers are moving. They look at each other at eye level. Far below their feet, a flat glowing surface like a lake of light. + 共用尾綴 + 共用禁止
```
證明：Part 結尾狀態＝接真實 App 的前一幀。

---

## 出圖規則
- **垂直文法（2026-08-29 冷審後定案）**：16:9 裡任何「shaft／tunnel＋消失點在中央」的構圖，靜態單幀一律被讀成水平走廊，加了湖就變地板。第三人稱與極遠景改用 **平牆文法**：`camera looking horizontally at a flat wall filling the background, seams perfectly vertical and horizontal, NO perspective, NO vanishing point, NO corridor`，靠人物頭髮／衣襬向上、塵埃向上、底邊橘光來給重力（就是 LOTR 1:02 那顆的拍法）。俯視隧道構圖只留給第一人稱（B2）與 U4 的「從上往下看小點退遠」，因為那兩種在動態裡會被牆面上刷救回來。
- **B8 冰內視角**：鏡頭在冰裡面往外看、冰填滿畫面、只准兩隻手、明寫 `no face, no head`；「No faces」單獨一句守不住，要配構圖鎖死。
- 每張只放該板列出的 refs；ENV0 永遠不當人物參考。
- Element 用 `<<<element_id>>>` 內嵌在 prompt；環境用 medias job_id。
- 同一張 3 次不成立就刪一個名詞，不加限制詞。「米粒大」這種尺寸詞模型常無視（B6_d 教訓），改用「smaller than one screen tile」這類相對尺寸。
- 出圖後逐張只問一句：「冷觀眾看得懂它要證明的那件事嗎？」

## 已成立（v1 留用）
- ENV0 V1：`docs/handover-screenshots/film-boards-2026-08-29/ENV0_v1_俯視螢幕井.png`
- B2_a：`.../B2_a.png`
- B6_c：`.../B6_c_V1側面.png`
