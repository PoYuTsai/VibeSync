# VibeSync 電影式官網｜D-T7-GREYBOX-ALIGNMENT-01

更新日期：2026-08-24

版本：Greybox Revision 1.1 Motion Proof

狀態：已獲 Eric 最終導演拍板並正式凍結。Revision 1.1 的桌面／手機正反向 Motion Proof、G2 camera crop、G4 hidden-stack cutaway 與 reduced-motion strip 均已通過；後續 `D-T7-LOOKDEV-01 Revision 1.1` 亦已通過並凍結。M7 Revision 1.1 與 M8 Revision 3.1 維持正式凍結；目前沒有下一階段自動解鎖，runtime 與 implementation planning 仍未授權。

上位基準：

- `docs/plans/2026-08-23-vibesync-cinematic-site-yuya-calibrated-bible.md` Revision 16＋M8 Revision 3.1＋M7 Revision 1.1 核准覆蓋。
- `docs/plans/2026-08-23-vibesync-m7-one-to-one-reverse-storyboard.md` Revision 1.1，尤其 R5 與 O1～O8 白名單。
- `docs/plans/2026-08-23-vibesync-m8-real-product-ui-storyboard-revision-3.md` Revision 3.1，尤其 K1～K3 與第 9 節真實目的地。
- `docs/plans/2026-08-23-vibesync-m7-reverse-storyboard-visual-philosophy.md`：`Refracted Continuity`。

## 導演拍板紀錄｜2026-08-24

`D-T7-GREYBOX-ALIGNMENT-01｜Revision 1.1 Motion Proof` 已完成外部證據審核並由 Eric 正式拍板：

- 桌面與手機 MP4 的解析度、12 fps、321 frames 與 26.75 秒 metadata 通過。
- G0→G4→G0 的正反向契約、O1～O8 stable ID／parent／depth／visibility 證據通過。
- G2 值區由 camera viewport 裁切，scope 與 orb 留在鏡內；不是 empty state、censor bar 或人工數值。
- G4 audience viewport 只讀 Sydney，但 K2／K1 仍保留於同一 scene graph 後方。
- Reduced motion 維持 K1→K2 signal→K2 map→K3，且未刪除 O2／O6。

正反向一致性的精確表述固定為：

> 經稽核的對稱點中，`audience viewport` 視覺上有效一致；本機技術 QA 的四組抽樣 crop 為 pixel-exact。完整影片畫面因 debug HUD、frame 編號與 FORWARD／REVERSE 標示不同，不得宣稱全畫面 bit-identical。

離線 HTML 的 scrub、frame step、Gate jump 與正反向播放已通過本機 Chrome QA；外部 Reviewer 本輪未操作 HTML。HTML 不屬本次凍結成立的必要前提，MP4、PNG 與 Spec 證據包已足以完成導演裁決。

本次凍結的是物件白名單、固定 parent、解析順序、K1～K3 目的地、G2 crop 邏輯、G4 hidden stack 與 reduced-motion continuity。精確秒數、scroll 距離、焦段、easing、fog／DOF、材質、shader 與聲音仍留給 lookdev／animatic，不得藉此重開已凍結的連續性契約。

---

## 0. 本輪唯一任務

本 Greybox 只證明：

> R5 中同一批 O1～O8，能在不消失、不重新生成、不換成另一張截圖、也不靠純 fade 的前提下，依序解析成 M8 K1、K2、K3。

本輪交付：

1. 桌面五狀態 alignment contact sheet。
2. 手機五個真正 9:16 狀態的 alignment contact sheet。
3. O1～O8 逐物件連續性帳本。
4. 正向、反向與 reduced-motion 契約。
5. R3／O4 有來源遮擋的 Greybox 解法。
6. 桌面與手機 9:16 的 G0→G4→G0 Motion Proof。
7. 可正反向播放、scrub 與逐格檢查的離線審核頁。
8. G2 camera crop、G4 hidden-stack cutaway 與 reduced-motion 四狀態補證。

本輪不交付：

- T7 lookdev、最終材質、shader、聲音或混音。
- 精確秒數、scroll 距離、焦段、easing、fog 或 DOF 數值。
- M7 或 M8 的新構圖、新文案、新功能與新物件。
- O4 的人工分數、定性 label 或 orb 狀態映射。
- T1／T4／T6 Greybox、完整 animatic、舊 P0／P1。
- Flutter、Three.js、WebGL、GSAP、runtime、`marketing-site/`、build、test、commit、push 或 deploy。

五個狀態是同一段轉場的 debug sample，不是五個 section、五次 scroll snap 或五張功能卡。

### Revision 1.1 窄幅補證範圍

Revision 1 已正式通過：解析順序、K1／K2／K3 真實目的地、O1～O8 白名單、桌面／手機構圖方向、無人工分數、真實作戰板、真實 Sydney 與 `Refracted Continuity`。Revision 1.1 不重畫五個狀態，也不重開 M7／M8，只把靜態聲明升級為可逐格驗證的證據：

1. 桌面 G0→G4→G0 正向／反向無材質 Motion Proof。
2. 手機 9:16 G0→G4→G0 正向／反向 Motion Proof。
3. 每個 motion frame 的 stable object ID、固定 parent、depth、transform、visible／occluded／off-camera、M8 destination。
4. G1 先讓 O1 `小安` 穩定，再讓 O2 `週三 21:59` 取得焦點。
5. G3 手機依 root→stage→next 一次正視一面，O2 與 O6 全程可由 debug overlay 追蹤。
6. G2 值區真正落到 camera viewport 外，不形成空白、loading、空 meter 或 censor bar。
7. G4 audience viewport 維持乾淨 Sydney；畫框外 cutaway 證明 O1～O7 仍在同一 scene graph 後方。
8. K1→K2 signal→K2 map→K3 的 reduced-motion 四狀態 strip；O2／O6 不因降動態而刪除。

Revision 1 靜態 contact sheet 繼續作為 alignment blueprint，不再被稱為 Motion Proof。

---

## 1. 唯一解析順序

| Greybox 狀態 | 解析任務 | 取得 M8 目的地 | 穩定閱讀平台 |
|---|---|---|---|
| G0｜R5 START | 確認 O1～O8 全部仍在場 | 尚未解析 | 無；只建立起始姿態 |
| G1｜IDENTITY LOCK | O1／O2 停止透視、姓名先於時間 | M8 K1 | `小安` → `週三 21:59` |
| G2｜SIGNAL LOCK | O4 取得真實卡框、scope 與低權重 orb | M8 K2 前半 | `本次互動訊號`＋完整可信邊界 |
| G3｜MAP LOCK | O3／O5／O6／O7 收成真實拓樸與下一步 | M8 K2 後半 | `準備邀約` → `下一步行動／主動邀約` |
| G4｜COACH LOCK | O8 最後停止透視，取得真實 Coach 頁 | M8 K3 | `問教練 Sydney・小安`＋凍結台詞 |

閱讀順序固定為：

> 對象與時間  
> → 訊號與 scope  
> → 階段、作戰板與下一步  
> → Sydney

不是所有平面同時「啪」一聲轉正，也不是 M7 fade out 後貼入三張 M8 screenshot。

---

## 2. 逐物件連續性帳本

| ID | G0 起始姿態 | 中途必須持續存在 | 最終目的地 | 禁止 |
|---|---|---|---|---|
| O1 `小安` | 左後／手機頂部弱 baseline | G1 先取得 AppBar baseline；G2～G4 留在產品 header 脈絡 | K1 `PartnerDetailScreen` AppBar；Coach title 同名 | 完整浮空身分卡、虛構頭像 |
| O2 `週三 21:59` | 左後時間平面／手機後層 | G1 在姓名後取得焦點；其後留作最近互動證據 | K1 `最近互動` | 倒數、時間倒播、手機版直接刪除 |
| O3 根節點／枝節 | 中央後層 K2 stack | G1～G2 保持可追蹤邊緣；G3 才取得真實拓樸 | K2 `小安・已分析 3 次` 與真實枝節 | 假聊天、CRM rows、中央 DNA |
| O4 訊號卡 | 中央後層；值未綁定 | G2 卡框、scope、orb 對齊；G3～G4 留在 K2 脈絡 | K2 `PartnerHeatHeroCard` | 人工分數、固定 `有在回應`、黑色 censor bar |
| O5 `準備邀約` | 中央後層真實文字節點 | G3 依真實拓樸取得焦點 | K2 stage／map | stage raster、票券、巨大 icon |
| O6 銀灰可能線 | R4 脊柱上的弱 edge | 全程保持可追蹤但不變亮；G3 附著真實訊號／互動重點 | K2 作戰板 edge | 答案線、成功路徑、手機版省略 |
| O7 下一步 | G0 中央前層／手機最前 | G1～G2 向 K2 detail panel 收束；G3 才成真實下一步 | K2 `下一步行動／主動邀約` | 成功出口、CTA 橘提前接管 |
| O8 Sydney | G0 右後／手機 O7 後一層 | G1～G3 維持同一 Coach 平面與 avatar 來源；G4 最後正視 | K3 `GlobalCoachScreen` | AI 球、立繪引路、候選句或預填 |

硬規則：debug overlay 可在產品畫框外標示 O1～O8 與 destination；產品畫框內不出現 object ID、alignment guide、投影角度、工程箭頭或 `T7` 字樣。

---

## 3. 桌面 Greybox

### G0｜R5 START

- 左後保留 O1／O2；中央後層保留 O3～O6；中央前層是 O7；右後是 O8。
- R4 水平脊柱穿過四層；所有平面仍有透視、fog、DOF 與產品外尺寸。
- O1～O8 全部在 debug ledger 中亮起，不要求同時可讀。

### G1｜IDENTITY LOCK

- O1 的 AppBar baseline 先與 K1 對齊；至少一側仍由前一拍裁切或遮擋進入，不瞬間變成完整卡。
- `小安` 先穩定一個可辨認節拍，O2 才沿同一 baseline 收到 `最近互動：週三 21:59`。
- O3～O8 不 fade；它們保持後景 edge、投影輪廓或同一脊柱上的未解析平面。
- 大位移完成後形成第一個閱讀平台。

### G2｜SIGNAL LOCK

- 攝影機由 K1 同一產品面向內／向下接到 K2；不是切到另一支手機。
- O4 以卡框 edge、scope baseline 與 hollow orb 位置對齊 `PartnerHeatHeroCard`。
- O4 值區在 Greybox 中採用**攝影機裁切**：值區自然落在 viewport 外，不使用漂浮黑色 blur mask。
- O3／O5／O6／O7 保持同一 K2 stack 的後景幾何；O8 仍在右後。
- scope 取得第二個穩定閱讀平台。

### G3｜MAP LOCK

- O3 的根節點與枝節保持真實左到右分支拓樸；不為電影拉直。
- O5、O6、O7 依序降低透視、繼承 edge／baseline，落到 `準備邀約`、`本輪訊號／互動重點` 與 `下一步行動`。
- 所有 edge 權重相近；焦點順序由攝影機與景深建立，不畫高亮成功線。
- O7 落到 K2 detail panel 後才可讀 `主動邀約`；產品原生橘維持小面積低權重。
- 形成第三個穩定閱讀平台。

### G4｜COACH LOCK

- O8 沿 R5 既有右後平面與 Coach header baseline 收正，不重新生成 Sydney 畫面。
- 真實 avatar、`問教練 Sydney・小安` 與 `教練參考` strip 各自沿原座標取得產品尺寸。
- K1／K2 已解析的物件仍在同一 App 路徑中；不是被 Coach 畫面抹除，只是不再同時可讀。
- Coach 完全停止後才呈現凍結 Sydney 泡泡，形成第四個閱讀平台。

---

## 4. 手機 9:16 Greybox

手機五格都是獨立 9:16 viewport；不把桌面四層橫向縮進手機。

### G0｜R5 START

- 最前 O7、後一層 O8、再後 O3～O6；頂部安全區保留 O1 baseline，O2 在後層時間平面。
- O2 與 O6 可以不可讀，但 debug ledger 必須證明仍在場。

### G1｜K1 全螢幕取得焦點

- O1 由頂部 baseline 成為 edge-to-edge K1 header；O2 從後層靠近成 `最近互動`。
- 其餘 K2／K3 stack 沿 z 軸退後，不向左右飛出或刪除。

### G2｜K2 訊號面

- K1 沿同一前後軸退為產品脈絡；O4 從 K2 stack 正視。
- 值區由 viewport 裁切自然離場；scope 與小型 orb 保留。
- O6 仍以一小段弱 edge 穿過後層，debug ledger 可追蹤。

### G3｜K2 作戰板面

- 不顯示完整橫向 graph；根節點、`準備邀約`、下一步依 z-depth 先後取得焦點。
- Contact sheet 只採代表性的 `準備邀約 → 下一步` 對位狀態；完整三段焦點留在同一狀態內，不增加 scroll snap。
- O7 成為最前方真實 detail panel；O8 仍在後層。

### G4｜K3 Coach 面

- O8 由後層沿 z 軸靠近，直接成 edge-to-edge `GlobalCoachScreen`。
- K2 stack 退回同一 App 深度，不橫向縮成多張小卡。
- `教練參考` 先建立來源，Sydney 泡泡在鏡頭完全停止後才可讀。

---

## 5. 正向、反向與 Reduced motion

### 正向

1. 每次只解析一個目的地群組。
2. 先 edge／baseline 對齊，再降低透視，接著退出 fog／DOF，最後字體回到產品尺寸。
3. 每次大位移後留一個閱讀平台；不鎖秒數。
4. UI 觸感只在最後幾何落定後出現；不靠音效掩蓋純切換。

### 反向

- K3 退回 O8 Coach 平面。
- K2 的 detail、stage、signal、root 依相反焦點順序展開回 O3～O7。
- K1 退回 O1／O2 angled planes。
- 資料不倒數、階段不倒退、分析次數不減少。
- 送出事件尚未發生，因此本轉場全部可回看；不得以反向播放表現資料被刪除。

### Reduced motion

- 使用四個同位真實裁切：K1、K2 signal、K2 map、K3。
- 每次只短 dissolve 材質與景深，不移動整棵 graph、不做 3D fly-through。
- O1～O8 的 destination ledger 仍相同；reduced motion 不能省略 O2 或 O6。

### Revision 1.1 Motion Proof 稽核資料

每個 object instance 使用固定 ID 與固定 scene parent：

| Stable ID | 固定 parent | M8 destination |
|---|---|---|
| `t7-o1-name` | `t7Root/k1` | K1 AppBar |
| `t7-o2-time` | `t7Root/k1` | K1 recent interaction |
| `t7-o3-map-root` | `t7Root/k2` | K2 mind-map root |
| `t7-o4-signal` | `t7Root/k2` | K2 heat card |
| `t7-o5-stage` | `t7Root/k2` | K2 stage |
| `t7-o6-edge` | `t7Root/k2` | K2 signal／interaction edge |
| `t7-o7-next` | `t7Root/k2` | K2 next-step panel |
| `t7-o8-coach` | `t7Root/k3` | K3 Coach |

Motion Proof 的 debug overlay 每一幀都必須顯示：stable ID、parent、depth、position／rotation／scale 摘要、visibility 與 destination。`occluded` 與 `off-camera` 是可驗證狀態，不等於刪除。正向與反向共用同一批 instance 與同一組 transform keyframe；反向只改變取樣方向，不建立另一套 reverse 物件。

---

## 6. Greybox 通過門檻

1. O1～O8 在桌面與手機都能由 debug ledger 逐格追蹤。
2. 沒有物件 fade 後重生、換 screenshot 或無來源返回。
3. G1 明確先讀 `小安`，再讀 `週三 21:59`。
4. G2 的 O4 遮擋有攝影機裁切來源，沒有黑色 censor bar。
5. O4 不含人工分數、固定定性 label 或放大 orb。
6. G3 保留真實分支拓樸；沒有高亮答案線或中央 DNA。
7. O6 在手機仍可由 debug ledger 證明到達 K2。
8. O7 是方向而非成功出口，人物行動橘不進場。
9. G4 使用真實 Sydney 頭像、標題與來源 strip；沒有候選回覆或預填。
10. 每次大位移後都有可讀平台，且解析順序不是同時展開。
11. 正向與反向使用同一批物件；資料狀態不倒轉。
12. 轉場由透視、edge、baseline、fog／DOF、字級與材質共同完成，不靠純 fade。
13. 手機使用五個真正 9:16 viewport，一次只正視一面。
14. Contact sheet 的 debug 字與對位線全部位於 diegetic viewport 外。
15. 最終只抵達 M8 K3；不提前進入外部聊天 K4 或任何 sent state。

評分規則：若只呈現「M7 fade out → M8 screenshot fade in」，本 Greybox 直接判定 0 分。只有 O1～O8 的來源、路徑、目的地與反向都可驗證，才可進入下一輪。

---

## 7. 導演審核附件

- Revision 1.1 可 scrub Motion Proof：`docs/handover-screenshots/t7-greybox-alignment/vibesync-t7-greybox-motion-proof.html`
- 桌面正反向 MP4：`docs/handover-screenshots/t7-greybox-alignment/vibesync-t7-greybox-motion-proof-desktop.mp4`
- 手機 9:16 正反向 MP4：`docs/handover-screenshots/t7-greybox-alignment/vibesync-t7-greybox-motion-proof-mobile-9x16.mp4`
- G2 camera crop 證據：`docs/handover-screenshots/t7-greybox-alignment/vibesync-t7-greybox-revision1-1-g2-crop-evidence.png`
- G4 hidden-stack cutaway：`docs/handover-screenshots/t7-greybox-alignment/vibesync-t7-greybox-revision1-1-g4-scene-cutaway.png`
- Reduced-motion 四狀態 strip：`docs/handover-screenshots/t7-greybox-alignment/vibesync-t7-greybox-revision1-1-reduced-motion-strip.png`
- 桌面：`docs/handover-screenshots/t7-greybox-alignment/vibesync-t7-greybox-alignment-desktop-contact-sheet.png`
- 手機 9:16：`docs/handover-screenshots/t7-greybox-alignment/vibesync-t7-greybox-alignment-mobile-9x16-contact-sheet.png`
- M7 起點：`docs/handover-screenshots/m7-reverse-storyboard/vibesync-m7-reverse-storyboard-revision1-1-desktop-contact-sheet.png` 與手機版。
- M8 目的地：`docs/handover-screenshots/m8-revision3/vibesync-m8-revision3-1-desktop-contact-sheet.png` 與手機版。

Revision 1 contact sheet 是 alignment blueprint；Revision 1.1 HTML／MP4／cutaway／strip 才是本輪動態與 hidden geometry 的驗收證據。全部仍是無材質導演 Greybox，不是 final UI、lookdev、runtime screenshot 或可直接交付工程的動畫參數。

---

## 8. 後續治理

後續 `D-T7-LOOKDEV-01 Revision 1.1` 已另行通過並凍結；本節原先解鎖 lookdev 的任務已完成。最新治理如下：

- Greybox 繼續凍結物件連續性、空間對位與正反向契約；Lookdev 另行凍結材質方向、色彩責任與表面層級。
- 精確秒數、焦段、easing、production shader 數字、聲音與最終動畫仍未凍結，但不得違反上述兩份凍結契約。
- 目前沒有下一階段自動解鎖；M7 lookdev、T1／T4／T6、完整 animatic、舊 P0／P1 與 implementation planning 繼續暫停。
- runtime、`marketing-site/`、build、test、commit、push、deploy 均未授權。

若後續參數證明必須違反凍結契約，須由 Eric 另行窄幅重開，不得靜默改寫。
