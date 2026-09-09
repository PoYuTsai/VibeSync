# VibeSync 電影式官網｜D-M7-REVERSE-STORYBOARD-01

更新日期：2026-08-24

版本：Revision 1.1

狀態：已獲 Eric 最終導演拍板並正式凍結。M8、後續 `D-T7-GREYBOX-ALIGNMENT-01 Revision 1.1` 與 `D-T7-LOOKDEV-01 Revision 1.1` 皆已通過並凍結。目前沒有下一階段自動解鎖；M7 lookdev、T1／T4／T6、完整 animatic、舊 P0／P1、runtime 與 implementation planning 仍暫停。

後續核准：`D-M7-REVERSE-STORYBOARD-01｜Revision 1.1` 的三個閱讀平台、R1～R5、O1～O8 白名單、桌面／手機空間構圖、投入度未綁定規則、`Refracted Continuity` 與 R5 的 T7 起始姿態均已正式凍結。後文對「候選、待拍板、T7 尚未授權」的描述，只記錄本版製作時的歷史邊界；不再覆蓋本段最新治理狀態。

後續 T7 核准：`D-T7-GREYBOX-ALIGNMENT-01｜Revision 1.1 Motion Proof` 已於 2026-08-24 由 Eric 正式拍板。後文若仍將下一成果寫成 T7 Greybox，視為歷史製作順序；最新允許範圍以 `2026-08-23-vibesync-t7-greybox-alignment.md` 的拍板紀錄與後續治理為準。

後續 Lookdev 核准：`D-T7-LOOKDEV-01｜Revision 1.1` 已於 2026-08-24 由 Eric 正式拍板並凍結。後文若仍將 T7 lookdev 寫成待開始或唯一解鎖成果，視為歷史狀態；本次拍板不自動授權下一階段。

上位基準：

- `docs/plans/2026-08-23-vibesync-cinematic-site-yuya-calibrated-bible.md` Revision 16＋M8 Revision 3.1 核准覆蓋。
- `docs/plans/2026-08-23-vibesync-m8-real-product-ui-storyboard-revision-3.md` Revision 3.1，尤其第 9 節 M7→M8 真實目的地。
- 現行 App 真實元件與資料語義；電影不得先宣稱產品目前沒有的資訊。

---

## 0. 本輪唯一成果與權限邊界

本輪只回答一件事：

> M7 中每一個看見的物件，如何由 M6 的真實反射長出，並在下一幕找到唯一、真實、可驗證的 M8 UI 目的地。

本輪產出：

1. 五個 M7 內部狀態的導演規格。
2. 桌面與手機各一張 contact sheet。
3. 八項物件白名單與 M8 一對一目的地。
4. M6→M7 入口姿態，以及供未來 T7 使用的 M7 退出姿態。
5. 正向、反向與 reduced-motion 行為。

本輪不產出：

- M7 lookdev、美術完稿、材質定稿或精確 shader。
- T6／T7 greybox 或任何轉場動畫。
- 精確秒數、scroll 長度、camera 焦段或 easing。
- 凍結 M1 的真實分析結果、投入度數值或定性狀態。
- Flutter、Three.js、WebGL、GSAP、runtime、build、test、commit、push 或 deploy。

五個狀態是同一條攝影機路徑上的內部導演節拍，不是五個 section、五張功能卡或五次 scroll snap。

### Revision 1.1 窄幅補丁範圍

Revision 1 的三個閱讀平台、五個內部狀態、O1～O8 白名單、投入度未綁定、真實作戰板、無 stage raster、真實 Sydney、下一步在前／Coach 在後與 `Refracted Continuity` 全部保留。本版只修：

1. R1 由完整人物卡改為反射中的 AppBar 局部，只讀 `小安`。
2. R2 將歷史節點降為失焦、遮擋且不等長的深度枝節，移除 CRM rows 感。
3. R3 移除缺值符號與產品平面內 production annotation，值區裁出／遮住／退入景深。
4. R4 保留真實分支拓樸，以攝影機焦點建立單一閱讀順序，不新增高亮答案線。
5. R5 讓 O1～O8 全部仍在場，移除非產品文案，並保留 R4 反射脊柱與 edge inheritance。
6. 手機 contact sheet 重做為五個真正 9:16 frame，明示安全區、z-depth 與 R4 三個內部焦點。

---

## 1. 唯一主推薦

M7 不是新的「資料宇宙」，而是同一片濕窗反射逐漸學會三件事：

1. 它指向同一個人。
2. 它屬於一段有前後的互動。
3. 它所承載的產品資訊，各自有真實 UI 終點。

內部導演句：

> 不是把一段關係變成漂亮資料；是讓同一段關係，逐步取得可用的座標。

第一閱讀永遠先是 `小安`，而不是圖表、節點、orb 或功能名。M7 的視覺進展不是「資訊愈來愈多」，而是「同一件事愈來愈能被定位」。

---

## 2. 三個閱讀平台、五個內部狀態

| 閱讀平台 | 內部狀態 | 觀眾只需理解 | 不得形成的感受 |
|---|---|---|---|
| E1｜對象與時間 | R1、R2 | 這是小安，而且不是第一次 | 監控、聊天資料庫、時間倒流 |
| E2｜訊號與位置 | R3、R4 | 本次訊號有邊界；目前走到準備邀約 | 成功率、AI 判案、功能 dashboard |
| E3｜方向與出口 | R5 | Sydney 與下一步都有真實產品落點 | AI 代做、發光成功出口、T7 已開始 |

平台之間允許攝影機移動；平台內必須有足夠穩定的閱讀時間。五個狀態不等距、不等時，也不平均分配視覺奇觀。

---

## 3. 八項物件白名單

除下表外，M7 不得新增任何可辨認物件。裝飾性粒子、額外 icon、假 dashboard 欄位，即使「只是過場」，也不在白名單內。

| ID | M7 物件／語意 | M7 存在方式 | M8 唯一真實目的地 | 現行來源 | 明確禁止 |
|---|---|---|---|---|---|
| O1 | 同一位對象 | `小安` 姓名錨；不使用照片 | `PartnerDetailScreen`、作戰板與 Coach 標題中的 `小安` | `PartnerDetailScreen` AppBar、`GlobalCoachScreen` title | 虛構頭像、身分卡、人物監控 HUD |
| O2 | 最近時間 | 反射線上的 `週三 21:59` 節點 | `最近互動：週三 21:59` | `_PartnerCommandSummaryCard` | 倒數、時間倒播、WED→FRI→SAT 預告條 |
| O3 | 多輪脈絡 | `本輪／上輪／上上輪` 的不可讀枝節，只證明有前後 | 作戰板根節點 `小安・已分析 3 次` 與真實枝節 | `buildPartnerMindMap()`、`PartnerMindMapView` | 假聊天、私訊內容、未存在的共同回憶 |
| O4 | 本次投入度訊號 | 真實 UI 平面內的小型訊號槽、scope boundary、低權重 hollow orb | `PartnerHeatHeroCard` | `PartnerHeatHeroCard`、`PartnerHeatMessaging.scopeExplanation` | 人工分數、固定 `有在回應`、成功率儀表、放大 orb |
| O5 | 關係階段 | `準備邀約` 文字與真實作戰板節點 | `PartnerMindMapEntryCard`、`PartnerMindMapScreen` | 現行 stage label、真實 mind-map topology | `partner_stage_close.webp`、電影票券、巨大階段 icon |
| O6 | 尚未回應的可能 | 低飽和銀灰路徑；與主要線同權或更弱 | 作戰板 `本輪訊號／互動重點` | `map.currentSignal`、`map.relationshipSignal` | 答案線、命定路徑、比產品主線更亮的暖金線 |
| O7 | 下一步 | 路徑取得方向，但終點保持開放 | `下一步行動／主動邀約` | `_MindMapDetailPanel`、`map.fullNextStep` | 成功出口、對方回覆、CTA 橘色提前接管 |
| O8 | Sydney | 真實 head avatar 與 Coach 平面的小型來源座標 | `問教練 Sydney・小安`、`教練參考` strip | `CoachHeadAvatar`、`GlobalCoachScreen`、`_CoachMemorySourceStrip` | 全身立繪、AI 球、引路精靈、候選回覆 |

硬規則：若某個畫面元素無法標出上表 ID 與 M8 目的地，就直接刪除，不以氣氛、轉場或 Yuya 參考為理由保留。

---

## 4. 未完成產品資料的處理

`有在回應` 仍是 M8 導演佔位，不是凍結 M1 經真實分析流程得到的結果。M7 Revision 1.1 因此只設計 O4 的位置、權重、scope 與回到 M8 的方式，不鎖：

- 精確分數。
- 定性 label。
- orb 亮度、填滿程度或狀態映射。
- 因故事需要而固定成 `有在回應`。

Contact sheet 中 O4 使用**中性 hollow orb＋被裁出／遮擋／退入景深的值區**。不得顯示 `—`、空 meter、skeleton、spinner 或其他缺值狀態。`REAL M1 OUTPUT` 只可放在 contact sheet 卡片外的 production annotation，不進 diegetic UI。正式 animatic 若要讀出定性或數值，必須先以凍結 M1 走真實分析流程，並讓 label、數值與 orb 一起使用同一筆輸出。

---

## 5. M7-R1｜反射線辨認出小安

### 敘事功能

先證明「同一個人」，再讓任何產品資訊出現。這是 M8 K1 姓名先落位 gate 的來源。

### 畫面與材質

- M6 末端仍是一條濕窗上的真實街燈反射，顏色為低飽和暖灰／骨白；亮度與飽和度不得使它像浪漫金線或命定路徑。
- 攝影機沿線小幅轉向；只有一小段反射逐漸穩定寬度與邊緣。
- `小安` 不是浮空標籤突然出現，而是由手機反射中一小段被裁切的 AppBar／頂部產品平面取得焦點；只有 baseline、薄邊與極小區域清楚。
- `週三 21:59` 留在後方重景深或反射遮擋中；R1 靜態幀不得直接閱讀，R2 才取得焦點。

### 第一閱讀層

`小安`

### 桌面

只露出 AppBar 的局部薄片，位於畫面中央偏右並帶很小透視角；上下仍被窗面反射、裁切與景深遮住。不得畫成完整矩形、人物身分卡或產品 room。

### 手機

姓名由頂部安全區內的一小段 AppBar 局部取得焦點；反射沿前後深度上升。R1 不顯示可讀時間，也不把桌面橫向反射縮窄成卡片。

### 正向／反向／Reduced motion

- 正向：反射 → 邊緣穩定 → `小安` 可讀。
- 反向：`小安` 失焦並退回手機微光；不是姓名被刪除。
- Reduced motion：濕窗靜態裁切與姓名平面短 dissolve，同時保留來源反射。

### M8 對位與退出姿態

- O1 對位至 `PartnerDetailScreen` AppBar。
- R1 尾端姓名 baseline、水平中心與 M8 K1 AppBar 預先一致；仍保留透視，不開始 T7 收正。

### 禁止造成的解讀

VibeSync 已讀取她所有私人資料、她在被追蹤，或姓名只是資料隧道的第一個 HUD label。

---

## 6. M7-R2｜同一條線已有前後

### 敘事功能

證明這不是匿名、一次性的句子分析；產品記得的是同一位對象的多輪脈絡，但電影不新增任何舊劇情。

### 畫面與材質

- `小安` 姓名錨保持可辨認，但降低為持續錨點，不重複放大。
- `週三 21:59` 由後方沿同一條線靠近並取得焦點。
- 線上只長出 `本輪／上輪／上上輪` 三個微型、局部遮擋或失焦座標；枝節有前後深度、長短差與遮擋，不排成整齊三列。內文只使用不可讀細線或遮罩，不出現假聊天句子。
- 根節點輪廓可被感覺到，但 `小安・已分析 3 次` 到 R4 才完整可讀。

### 第一閱讀層

`週三 21:59`，其次是「這條線前後仍有內容」。

### 桌面

angled plane 繼承 R1 的 AppBar baseline；攝影機只做克制側移，讓不等長的枝節因視差與遮擋被察覺。`週三 21:59` 是唯一清楚文字，不展開成 archive room、CRM rows 或時間軸 dashboard。

### 手機

時間節點由姓名下方沿 z-depth 接近；舊枝節以不同縮放、遮擋與 blur 退入後方，micro label 不得同時完整可讀，一次只讓 `週三 21:59` 正視。

### 正向／反向／Reduced motion

- 正向：姓名維持 → 時間靠近 → 兩個不可讀枝節因視差存在。
- 反向：枝節依序退回同一反射線；週三、週五、週六的事實不倒轉。
- Reduced motion：姓名、時間、模糊歷史三個同位裁切依序顯示，不平移整條時間線。

### M8 對位與退出姿態

- O2 對位 `最近互動：週三 21:59`。
- O3 的根輪廓與枝節角度開始接近真實 `PartnerMindMapView`，但尚不顯示完整作戰板。

### 禁止造成的解讀

資料庫歷史、假聊天紀錄、反向時間旅行、或產品能查看外部聊天 App 的全部訊息。

---

## 7. M7-R3｜這次訊號不是關係答案

### 敘事功能

在關係階段與下一步之前先建立可信邊界：本次投入度只是一次互動的文字訊號，不代表關係進度。

### 畫面與材質

- R2 的時間平面不消失，而是翻出同位的 `PartnerHeatHeroCard` 表面。
- 卡內可讀 `本次互動訊號` 與完整 scope：`只反映這次互動中的文字訊號，不代表關係進度。`
- 數值與定性 label 所在區域被畫面裁出、前景遮住或退入重景深；不顯示空值符號、loading 或待填狀態。鏡頭外才可標記 `REAL M1 OUTPUT SLOT`。
- hollow orb 維持 App 原生小尺寸、低對比、位於平面內；不得離開卡片漂浮。

### 第一閱讀層

完整 scope boundary；其次是 `本次互動訊號` 與低權重 orb。未綁定值本身不是觀眾的閱讀任務。

### 桌面

平面承接 R2 的位置與角度；攝影機停止時只允許 `本次互動訊號`、scope 與小型 orb 可讀，值區在構圖外或重景深，歷史枝節退入後方。

### 手機

真正 9:16 frame 中，訊號卡 edge-to-edge 正視；orb 位於右上小角落，scope 使用正常產品正文尺寸。值區不可見，也不能同時看見完整作戰板。

### 正向／反向／Reduced motion

- 正向：時間平面表面逐漸取得真實卡片邊界 → scope 清楚 → hollow orb 才被察覺。
- 反向：卡片退回時間平面，不讓數值倒數或 orb 放空。
- Reduced motion：時間 state 與訊號 state 短 dissolve；scope 必須有完整閱讀平台。

### M8 對位與退出姿態

- O4 的卡片外框、標題、scope 與 orb 對位 `PartnerHeatHeroCard`。
- 訊號值保持未綁定；未取得真實 M1 輸出前，不列入 T7 可讀文字。

### 禁止造成的解讀

投入度是喜歡程度、成功率、關係進度，或空心 orb 是等待填滿的遊戲 meter。

---

## 8. M7-R4｜目前走到準備邀約

### 敘事功能

讓真實作戰板拓樸取得空間，沿單一**閱讀順序**看見「現在在哪裡」與「可以做什麼」，但不把真實分支重畫成答案路徑，也不把方向拍成保證成功。

### 畫面與材質

- R1～R3 已出現的姓名、時間、歷史與訊號平面向同一根節點折回；不是突然生成新 HUD。
- 根節點完整可讀：`小安・已分析 3 次`。
- 保留 App 真實分支拓樸；攝影機依序聚焦 `本輪訊號／互動重點 → 準備邀約 → 下一步行動`，這是單一閱讀順序，不是新增線性 graph。
- O6 銀灰可能線附著於 `本輪訊號／互動重點`；所有 edge 使用相近中性銀灰／產品紫權重，不得出現一條高亮白線或暖金線指向答案。
- `準備邀約` 只使用文字與真實節點；不使用任何 stage raster。
- 產品原生橘色可留在真實下一步 detail panel 的小面積內，但曝光與景深不得使它成為高潮。

### 第一閱讀層

`小安・已分析 3 次` → `準備邀約` → `下一步行動`。

### 桌面

作戰板維持真實左到右分支拓樸；攝影機依序讓訊號、階段與下一步取得景深、曝光與停頓，其餘節點存在而不可讀。焦點順序不得靠某條 edge 變得最亮，也不是把整張橫向圖一次攤給觀眾。

### 手機

不縮小整張橫圖。R4 review card 必須在同一個 9:16 frame 內證明三個 internal focus：根節點在前／其他層模糊，`準備邀約` 到前景／根節點退後，`下一步行動` 到前景／其餘只露邊緣。可用明確 z-stack 與鏡頭外 F1／F2／F3 標記，但一次只讀一面。

### 正向／反向／Reduced motion

- 正向：既有平面折回真實根節點 → 依單一閱讀順序聚焦訊號、階段、下一步 → 停在下一步入口。
- 反向：焦點依相反閱讀順序返回；真實拓樸不改寫，階段不倒退、分析次數不減少。
- Reduced motion：使用四個真實裁切 state 的短 dissolve，不 pan／zoom 整棵圖。

### M8 對位與退出姿態

- O3 → 作戰板根節點與枝節。
- O5 → `PartnerMindMapEntryCard／PartnerMindMapScreen` 的 `準備邀約`。
- O6 → `本輪訊號／互動重點`。
- O7 → `_MindMapDetailPanel` 的 `下一步行動／主動邀約`。
- R4 尾端各節點都已取得對應 UI 平面的相對位置，但仍保留同一透視角與景深；不得在本格解析成 M8。

### 禁止造成的解讀

作戰板操控對方、下一步是成功路線、銀灰線是 Sydney 判定的真相，或 M7 是四個功能 section。

---

## 9. M7-R5｜Sydney 與下一步取得 M8 座標

### 敘事功能

把最後兩個產品方向——Coach 與下一步——放進同一對象脈絡，並建立供未來 T7 使用的起始姿態；不開始 T7 動畫。

### 畫面與材質

- `下一步行動／主動邀約` 保持可讀，但沒有發光出口、勾選或成功狀態。
- 真實 `CoachHeadAvatar` 只以小型圓形裁切出現在 Coach 平面；標題使用 `問教練 Sydney・小安`。
- `教練參考` strip 只作來源證據，不展開成 citation dashboard。
- R1～R4 的 O1～O8 在同一構圖內全部仍然存在並找到各自 M8 座標；不要求同時可讀，但灰盒 reviewer 必須能追蹤每一層。無目的地的微標、裝飾線與粒子全部退場。
- O7 次要產品文案只使用現行 `提出一個具體、好回答的共同活動。`，或只保留 `主動邀約`。`方向，不是結果` 不得進入產品平面。
- R4 的反射脊柱、主 edge 或共用 baseline 至少保留一項並穿過 R5，不得把 O1～O8 重新置中排成三張漂亮卡。

### 第一閱讀層

`下一步行動`，其次是 `問教練 Sydney・小安`。Sydney 不得搶過人的下一步。

### 桌面

同位 angled planes 形成四層連續構圖：左後為 O1／O2 對象與時間；中央後層是 O3～O6 的 K2 product stack，至少露出作戰板根、訊號卡／orb、`準備邀約` 與銀灰 edge；中央前層是 O7 下一步；右後是 O8 Coach。R4 脊柱或共用 baseline 穿過四層。攝影機停在能追蹤所有出口座標、但只讀 `主動邀約` 的位置。

### 手機

真正 9:16 frame 中，最前層是 O7 下一步；後一層是 O8 Coach；再後方保留 O3～O6 K2 stack 的一至兩條可辨認邊緣；頂部安全區仍有極弱 O1 `小安` baseline，O2 藏於後層時間平面。不能把桌面四層橫向並排塞入手機。

### 正向／反向／Reduced motion

- 正向：下一步取得方向 → Coach 來源平面附著 → 所有物件到達 T7 起始座標後停住。
- 反向：Coach 與下一步退回 R4 路徑；不移除已存在的對象與脈絡。
- Reduced motion：使用下一步、Coach、K2 stack 與姓名 baseline 的固定分層裁切；最後只在 contact sheet 外顯示靜態目的地對位線。

### M8 對位與退出姿態

- O8 → `GlobalCoachScreen`、`CoachHeadAvatar`、`_CoachMemorySourceStrip`。
- O7 → `下一步行動／主動邀約`。
- 所有 O1～O8 在畫面外 annotation 標出 M8 destination；diegetic UI 不顯示工程箭頭、元件名稱、`T7 START POSE ONLY` 或內部導演句。
- 這一格只建立 T7 的起始姿態：保留透視、fog、DOF 與產品外尺寸；不停止透視、不切正投影、不解析成真實 App。

### 禁止造成的解讀

Sydney 提供了現成回覆、她正監看男主、AI 已選定正確答案，或 T7 已經被製作完成。

---

## 10. 桌面導演規格

### 構圖

- 使用一條由左下向右上略微上升的連續反射脊柱；五個狀態沿同一脊柱繼承位置。
- 平面角度只在必要時改變，避免每一格都展示新的 3D 技巧。
- R1～R3 以單一主平面＋後景殘影為主；R4 才允許關係拓樸形成；R5 才同時看見多個目的地座標。
- 大面積負空間保留在反射線外側，讓產品資訊不變成 dashboard wall。
- R1 只允許 AppBar 局部，不得再出現完整人物卡；R5 必須繼承 R4 至少一條主 edge、baseline 或方向脊柱。

### 攝影機

- 單一路徑前進，速度有停有走。
- 只在讀取姓名、scope、階段／下一步時形成穩定平台。
- 禁止 orbit、無目的翻轉、資料隧道、同速橫向巡覽與五張卡輪播。

### 資訊層級

1. 同一個人。
2. 同一條時間脈絡。
3. 訊號的可信邊界。
4. 目前階段與下一步。
5. Sydney 的來源與產品出口。

---

## 11. 手機導演規格

- Contact sheet 必須使用五個可量測的真正 9:16 viewport，標出頂部與底部安全區；frame 本身 edge-to-edge，不顯示裝飾性手機機身。
- `小安` 固定在安全區作持續錨點，但在 R2 後降低對比，不變成 sticky navbar 展示。
- 平面沿前後深度堆疊，一次只讓一面正視；不縮小桌面橫向作戰板。
- R4 的真實拓樸以「根節點 → 準備邀約 → 下一步」三個 internal depth focus 呈現；同一 9:16 frame 可用 z-stack 與鏡頭外 F1／F2／F3 證據，但不得平鋪整棵圖。
- R5 由前至後是下一步、Coach、K2 stack；頂部安全區保留極弱姓名 baseline。只露出足以追蹤 O1～O8 的邊緣，不要求同時閱讀。
- 重要中文必須以正常產品正文尺寸在單一 9:16 viewport 內可讀，不能依賴整張 contact sheet 放大。
- 反向捲動時，平面退回深度但資料不倒轉；reduced-motion 使用固定全螢幕裁切＋短 dissolve。

---

## 12. M6 → M7 入口契約（供未來 T6，不製作 T6）

入口順序必須是：

> 真實濕窗反射 → 穩定方向 → `小安` → `週三 21:59` → 少量產品平面

禁止在辨認對象前先出現：

- 節點網路。
- 完整日期刻度。
- 作戰板。
- orb。
- Sydney。
- 任何產品利益句。

街燈暖灰／骨白逐步去飽和成銀灰產品路徑；R1 不得像香檳金或浪漫命定線，也不突然變成霓虹紫或行動橘。雨水低頻可以轉為同音色產品脈衝，不使用隧道 whoosh。

---

## 13. M7 → M8 退出姿態（供未來 T7，不製作 T7）

| 物件 | R5 退出姿態 | M8 目標姿態 | 本輪是否動畫 |
|---|---|---|---|
| O1 `小安` | 對象平面 AppBar baseline 已對齊 | K1 AppBar | 否 |
| O2 `週三 21:59` | 最近互動平面中軸已對齊 | K1 最近互動 | 否 |
| O3 根節點／枝節 | 角度與真實拓樸一致，仍有透視 | K2 `PartnerMindMapScreen` | 否 |
| O4 訊號卡 | 卡框、scope、orb 位置已對齊，值未綁定 | K2 `PartnerHeatHeroCard` | 否 |
| O5 `準備邀約` | 真實文字節點對位 | K2 stage／map | 否 |
| O6 銀灰可能線 | 附著 `本輪訊號／互動重點` | K2 作戰板路徑 | 否 |
| O7 下一步 | detail panel 邊界與標題已對齊 | K2 `下一步行動／主動邀約` | 否 |
| O8 Sydney | Coach 標題、avatar、strip 取得同位座標 | K3 真實 Sydney | 否 |

本輪只證明所有目的地成立。停止透視、退 fog／DOF、字體回產品尺寸、平面解析成 edge-to-edge App，全部屬於後續 `D-T7-GREYBOX-ALIGNMENT-01`；該成果已由 Eric 另行解鎖，但不屬本文件既有 contact sheet。

---

## 14. 色彩、材質、字體與聲音

### 色彩

- M6 來源：低飽和街燈暖灰。
- M7 主路徑：銀灰，不比真實 UI 主要線更亮。
- Coach：真實產品紫，只存在於 Coach 平面與來源反射。
- 橘色：只保留作戰板真實小 accent；不使用電影級行動橘。人物行動橘仍留給 M8 K6。

### 材質

- R1 保留真實濕窗反射。
- R2～R3 逐步取得產品玻璃邊界，但仍有來源反射。
- R4～R5 使用真實產品平面拓樸；不做廉價毛玻璃、滿版 glow 或粒子塵。

### 字體

- 使用現行 App sans 的尺度與層級。
- 不借 Yuya 的 serif 身分，不用巨型 display 字填滿畫面。
- 正式利益句 `它認得你聊的每一個她` 本輪不列入必要文字；若未來 animatic 使用，只能短暫、低於人物錨點，且需另行裁決。

### 聲音

- 雨水低頻尾韻逐漸變成稀疏產品節點脈衝。
- 每個閱讀平台只給一次很小的材質觸感，不用功能提示音連發。
- R5 音樂與氛圍應變少，為 M8 產品清晰度留空間。

---

## 15. Contact Sheet 閱讀契約

桌面與手機 contact sheet 都必須在每格標出：

- 狀態 ID 與閱讀平台。
- 第一閱讀層。
- 白名單 object ID。
- M8 destination。
- 正向與反向的核心行為。
- Reduced-motion 對應。
- 禁止造成的解讀。
- `T7 START POSE ONLY` 只能放在 contact sheet 卡片外的 production annotation，避免將對位稿誤稱為轉場完成，也不得進 diegetic UI。

Contact sheet 是導演目的地與空間關係圖，不是 final lookdev、runtime screenshot 或 T7 動畫證據。

---

## 16. Revision 1.1 驗收門檻

Revision 1.1 必須同時通過：

1. 桌面與手機各有完整五狀態 contact sheet。
2. 五個狀態清楚屬於三個閱讀平台，不像五個 section。
3. R1 先讀 `小安`，R2 才讀 `週三 21:59`。
4. R2 證明多輪脈絡，但沒有任何可讀的假聊天。
5. R3 顯示完整 scope，且沒有數值、定性 label 或亮度映射。
6. hollow orb 留在真實 UI 平面內且低權重。
7. R4 使用真實 `PartnerMindMapScreen` 分支拓樸與單一閱讀順序；沒有高亮答案線。
8. `準備邀約` 不使用 `partner_stage_close.webp` 或電影票券。
9. 銀灰可能線不比主要產品線更亮，也不寫成答案。
10. R5 使用真實 Sydney head avatar、標題與來源 strip，不用立繪或 AI 球。
11. R1 只有 AppBar 局部與 `小安`；時間到 R2 才可讀，反射保持暖灰／骨白而非浪漫金線。
12. R2 micro labels 與枝節有深度、遮擋與長短差，不像三列 CRM rows。
13. R3 無 `—`、loading、空 meter 或 diegetic production annotation；值區不可見。
14. 手機 contact sheet 有五個真正 9:16 viewport、安全區與正常產品正文尺寸。
15. 手機 R4 以 z-stack／F1～F3 證明一次只正視一面，不平鋪整棵圖。
16. R5 中 O1～O8 全部仍在場；O3～O6 可遮擋但不可消失，且保留 R4 的 edge／baseline／脊柱。
17. R5 產品平面不出現 `方向，不是結果` 或 `T7 START POSE ONLY`。
18. 每個可辨認物件都有 O1～O8 ID 與 M8 目的地。
19. R5 只建立 T7 起始姿態，沒有停止透視或解析成 M8。
20. 無旁白觀看仍可說出至少三項：同一人、前後脈絡、訊號有邊界、準備邀約、下一步。
21. 看完不會把產品理解成監控、成功率工具或 AI 代寫器。

---

## 17. 導演審核附件

- 桌面 contact sheet：`docs/handover-screenshots/m7-reverse-storyboard/vibesync-m7-reverse-storyboard-revision1-1-desktop-contact-sheet.png`
- 手機 9:16 contact sheet：`docs/handover-screenshots/m7-reverse-storyboard/vibesync-m7-reverse-storyboard-revision1-1-mobile-9x16-contact-sheet.png`
- 視覺哲學：`docs/plans/2026-08-23-vibesync-m7-reverse-storyboard-visual-philosophy.md`

兩張 Revision 1.1 contact sheet 是 source-grounded storyboard composite；Revision 1 圖保留為歷史審核證據，不再作為目前視覺候選。真實產品目的地依現行 `PartnerDetailScreen`、`PartnerHeatHeroCard`、`PartnerMindMapEntryCard`、`PartnerMindMapScreen`、`PartnerMindMapView`、`GlobalCoachScreen`、`CoachHeadAvatar` 與 `_CoachMemorySourceStrip`；沒有取得真實 M1 分析輸出前，O4 只呈現位置與可信邊界。

---

## 18. 後續治理

`D-M7-REVERSE-STORYBOARD-01｜Revision 1.1` 已獲 Eric 最終導演拍板：

1. M7 的三個閱讀平台、五狀態、O1～O8 白名單、桌面／手機構圖方向、產品目的地與 T7 起始姿態正式凍結。
2. 後續 T7 Greybox Revision 1.1 與 T7 Lookdev Revision 1.1 已分別完成、通過並凍結；不得用後續參數調校重開本文件。
3. 目前沒有下一階段自動解鎖；任何後續成果須由 Eric 另行明確授權。
4. T1／T4／T6、完整 animatic、M7 lookdev、舊 P0／P1、runtime 與 implementation planning 仍依既有治理保持暫停。
