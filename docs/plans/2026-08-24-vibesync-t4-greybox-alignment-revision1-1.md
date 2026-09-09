# D‑T4‑GREYBOX‑ALIGNMENT‑01｜Revision 1.1 Motion Patch

更新日期：2026-08-24  
狀態：已獲 Eric 最終導演拍板並正式凍結；不需要 Revision 1.2  
上位文件：`2026-08-24-vibesync-t4-greybox-alignment.md` Revision 1  
補丁範圍：真正 Mobile 9:16、移除 `focusRing`、W3 在 G5 幾何退出

## 1. 導演裁決

Revision 1 的核心方案已通過：

- A｜Same-surface focus pull／同面焦點顯影維持唯一正式主推薦。
- B｜Droplet lens aperture 與 C｜Window-frame reveal 維持淘汰，不再比較。
- W1／W7 同面、W4→W5 單一水膜／水滴、G0→G5、Camera 可逆／Physics 不可逆全部不重開。

Revision 1 當時尚未凍結，只因三個輸出／畫面阻擋；Revision 1.1 已全部修正並通過：

1. Mobile MP4 的 metadata 是 9:16，但 audience 被 1920×1080 parent 裁掉約 35.3%。
2. Audience viewport 內存在白名單外的規則圓形 `focusRing`。
3. Desktop G5 仍能辨認 Sydney 紫色矩形；真正 9:16 後手機也可能出現同一問題。

## 2. Revision 1.1 精確修正

### Patch A｜Mobile audience 真正 edge-to-edge 9:16

正式 render state：

- `.proof-shell.platform-mobile`：1080×1920。
- `.platform-mobile .audience`：`left:0; top:0; width:1080px; height:1920px`。
- Audience 無外層手機殼、圓角邊框或黑色 letterbox。
- Render mode 隱藏 mobile frame title 與 debug panel；phase、frame、gate 與 ID 改由外部 reviewer 提供。
- G0 能看見完整 Sydney 次要泡泡與同面水氣。
- G3→G5 使用完整直式玻璃空間。
- Mobile 水平窗框移到畫外並降至極低權重；垂直窗框成為唯一主要構圖線。

### Patch B｜移除白名單外 `focusRing`

- `focusRing` DOM 已刪除。
- `.focus-ring` CSS 已刪除。
- JS reference、reset、opacity 與 transform 全部刪除。
- 正式 audience 只包含 W1～W10。
- 不建立 W11，也不以另一個規則 halo 取代。
- G0／G1 的注意力由 W4 不規則水膜、局部曝光、DOF 與 W5 成形自然建立。
- W4 改為非對稱邊界與不等比收縮，保留重力／表面張力方向。

### Patch C｜W3 Sydney 在 G5 幾何退出

- W3 保持同一 DOM／instance。
- Desktop 與 Mobile 都透過 off-camera X 位移、負 Z-depth、少量縮小與 defocus 退出。
- 不刪 DOM、不 clone、不用 `opacity:0` hard fade。
- G5 時 W3 的 bounding rect 必須完全離開 audience viewport，或已失去矩形辨識；本版採完全 off-camera。
- M4 的 W2 可留下極低強度表面記憶，但 Sydney UI 本身不得進入 M5 穩定平台。

## 3. 不得重開

- A／B／C 裁決。
- W1～W10 identity 與唯一目的地。
- W7 從 frame 1 存在，沒有第二個 street scene。
- W4→W5 的單一水膜／主雨滴責任。
- G0→G5 的閱讀順序。
- `Camera state 可逆；physical rain state 不可逆`。
- 不換 scene、screenshot 或 crossfade。
- 不新增女生、傘、森林、海、宇宙、星塵或命運象徵。
- T4 終點仍是 M5，不提前進入 M6／M7 路徑。

## 4. Revision 1.1 重新驗收 gate

### Mobile G0～G5

1. 1080×1920 每個像素都屬於完整 audience；無被 parent 裁切的下半段。
2. G0 可見 Sydney 次要泡泡、水膜、證據線與不可辨認真實光源。
3. G1／G2 只由 W4／W5 建立焦點；不存在規則圓環。
4. G3 能從完整直式玻璃辨認同一 W7，不是 screenshot swap。
5. G4 以一條主要垂直窗框、普通雨線與來源燈光成立。
6. G5 是完整直式濕窗，W3 已離場，沒有 device chrome 或大片空黑區。

### Desktop G5

1. 縮小、移除 debug 後，第一印象是普通濕窗與雨夜。
2. 左下不再辨認 Sydney 頭像、文字、泡泡或紫色矩形。
3. 主雨滴仍是接力物，但不是中央 hero／portal。
4. 沒有 `focusRing` 或其他規則 halo。

### White-list／source

- `focusRing`／`focus-ring` token count：0。
- W1～W10 各只有正式責任；W7 與 W5 各建立一次。
- `cloneNode`／`innerHTML`／`replaceWith`／street opacity swap：0。
- W3 在 G5 仍存在同一 DOM，但 bounding rect 在 audience 外。

### Physics

- Desktop `dropY`：0→145 單調不減。
- Mobile `dropY`：0→185 單調不減。
- Camera return 不改寫 actual-frame physical progress。
- 不做、也不宣稱 audience-state 對稱 SSIM／pixel match。

### Reduced-motion

- 機械式重輸出真正 edge-to-edge Mobile 9:16。
- 保留 W1／W7、W4→W5、持續下落與 G3→G5 焦點階梯。
- 不改創意方向、不改成 screenshot dissolve。

## 5. Revision 1.1 交付

- Desktop Motion Proof，1920×1080／321 frames／12 fps。
- 真正 Mobile 9:16 Motion Proof，1080×1920／321 frames／12 fps。
- Desktop Contact Sheet。
- Mobile 9:16 Contact Sheet。
- Same-surface Evidence。
- Droplet Physics Evidence。
- Reduced-motion Strip。
- Prototype／deterministic renderer source。
- Revision 1.1 spec／QA／manifest／ZIP sidecar。
- Revision 1 的 A／B／C comparison 可沿用；不構成重新比較。

## 6. 正式凍結範圍

本版已獲導演通過，以下正式凍結：

- A｜Same-surface focus pull 為唯一 T4 結構。
- B／C 正式淘汰。
- W1～W10 白名單，且 diegetic viewport 不得增加 focus halo。
- 真正 Mobile edge-to-edge 9:16。
- W3 在 G5 幾何退出。
- G0→G5、桌面／手機分開導演與 reduced-motion 來源。
- Camera state 可逆、physical rain state 不可逆。

仍不凍結：最終秒數、scroll、easing、焦段、roughness／IOR／transmission、水滴 shader、fog／DOF／曝光、聲音與 WebGL 實作參數。

## 7. 治理邊界

Revision 1.1 已正式通過並凍結；不需要 Revision 1.2。本次拍板不自動解鎖下一階段。

- T4 lookdev 繼續暫停。
- T6、完整 animatic、舊 P0／P1 繼續暫停。
- runtime、`marketing-site/`、build、test、commit、push、deploy 未授權。
- M1／M2、T1、M7／M8、T7 Greybox／Lookdev 維持既有凍結。

## 正式裁決

> `D‑T4‑GREYBOX‑ALIGNMENT‑01 Revision 1.1` 正式通過並凍結。A｜Same-surface focus pull 是唯一正式方案；B／C 維持淘汰。Mobile G0～G5、Desktop G5、W1～W10、Reduced-motion 與 Camera／Physics 契約均通過。
