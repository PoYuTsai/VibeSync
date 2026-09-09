# D-T7-LOOKDEV-01｜Afterrain Optics

狀態：Revision 1.1 已獲 Eric 最終導演拍板並正式凍結；不需要 Revision 1.2。  
日期：2026-08-24  
上位真相源：M7 Revision 1.1、T7 Revision 1.1 Greybox、M8 Revision 3.1。  
視覺哲學：`Afterrain Optics`，作為 `Refracted Continuity` 的表面表達。

## 導演拍板紀錄｜2026-08-24

`D-T7-LOOKDEV-01｜Revision 1.1` 已完成外部導演審核並由 Eric 正式拍板：

- G0 已先讀成濕窗介質，而非暗紫卡片牆；濕介質耦合是後續實作不得省略的最低成立門檻。
- 暖灰 → 銀灰 → 產品邊界 → Coach 紫的單一光源責任成立。
- G2 只保留真實 `本次互動訊號`、完整 scope、低權重 hollow orb 與 camera crop；沒有代理文案、人工數值或未驗證資料。
- G3 保留真實拓樸與 `#FF6A2B`，但橘色不是第一閱讀層；節點、edge 與手機焦點層級成立。
- G4 延續 Revision 1 的受控 Sydney 紫；桌面與手機 audience viewport 的 RGB pixel diff bounding box 均為 `None`。
- L1～L4 Material Response 與 `Afterrain Optics` 視覺哲學通過。

正式凍結：

- `Afterrain Optics` 視覺哲學，以及暖灰 → 銀灰 → 產品玻璃 → Coach 紫的色彩責任。
- 桌面／手機 G0～G4 的材質方向、G0 濕介質耦合、G1 深紫產品 surface、G2 產品真相、G3 視覺權重上限與 G4 現行克制程度。
- L1～L4 四層 Material Response。
- 不新增霓虹 HUD、宇宙、巨大 orb、人工資料或 O1～O8 白名單外的新物件。

本輪不凍結：精確 roughness／IOR／transmission／shader 數字、雨痕速度與生成方式、fog／DOF／曝光最終值、camera timing／easing／scroll 距離、聲音與混音、WebGL 實作與效能預算，以及尚未由真實 M1 分析流程產出的投入度數值／定性結果。這些參數不得反向改寫已凍結的層級、產品文案、O1～O8、K1～K3 或色彩責任。

本次拍板不自動授權下一階段；T1／T4／T6、完整 animatic、M7 lookdev、舊 P0／P1、runtime、`marketing-site/`、implementation planning、build、test、commit、push 與 deploy 均繼續暫停。

## Revision 1.1 Delta｜2026-08-24

Revision 1 的視覺哲學與總方向先獲導演通過、圖面當時尚未凍結；Revision 1.1 隨後不重做 Greybox、不修改 M7／M8、不新增 Motion Proof，只修下列六項表面表達，並已依上節正式通過：

1. G0 讓濕介質穿過一至兩塊平面邊緣：不同深度平面使用不同反射／透射比例，雨痕與來源反射在表面發生偏移、折斷與粗糙度變化；主線到 G1 前仍略微破碎。
2. G1 lock endpoint 的摘要卡由中性炭灰校準回真實深紫產品 surface；動態閱讀仍維持 `小安` 先取得局部對比，`週三 21:59` 後取得完整焦點。
3. G2 audience viewport 只保留真實 `本次互動訊號`、完整 scope 與低權重 hollow orb；刪除 `這次的文字訊號`、`只反映這次互動` 及任何替未綁定值區補上的代理文案。值區繼續由 camera crop 離場。
4. G3 保留真實 `#FF6A2B`，但縮小可見面積並壓低感知曝光；節點回到產品低透明 border，非焦點節點再退一級，O6 與其他 edge 使用相近銀灰權重。
5. 手機 G3 以焦點／景深表達 root → stage → next；正式靜態板只讓當前階段與 detail panel 清楚，其餘拓樸存在但不搶讀。
6. Material Board L1 改以方向性粗糙度、水膜厚度、反射形變與邊緣折射差說明濕窗；L2 刪除多數圓點並標明材質樣本不代表場景節點。

Revision 1.1 不得更動：G0～G4 順序、O1～O8 identity／parent／destination、K1／K2／K3 幾何、真實作戰板拓樸、Sydney UI、正向／反向與 reduced-motion、M7／M8 文案或 T7 終點 K3。

Revision 1.1 通過門檻：

- 拿掉標題後，G0 先被看成濕窗介質，而不是暗紫卡片牆。
- 同一束光的暖灰 → 銀灰 → 產品邊界 → Coach 紫責任連續。
- G2 沒有合成代理文案或未驗證資料。
- G3 瞇眼測試時，橘色直條不是第一閱讀層。
- 手機 G3 一次只有當前焦點節點與 detail panel 清楚。
- G4 維持 Revision 1 的克制程度，不反向增亮。

## 0. 本輪唯一任務

在不改動 G0～G4、O1～O8、K1／K2／K3 與正反向契約的前提下，證明 T7 可以從無材質 Greybox 進入一套可拍、可讀、可回到真實產品的表面系統。

本輪只裁決：

- 濕窗暖灰如何校準為銀灰產品路徑。
- 產品玻璃、Coach 介面與真實 UI 的表面響應。
- fog、DOF、曝光退出與 edge／baseline 接力。
- 字體由空間尺度回到產品尺度時的可讀性。
- hollow orb、產品原生橘與 Coach 紫的層級。
- 桌面與手機各自的材質權重。

本輪不裁決：精確秒數、最終 easing、聲音、runtime shader、瀏覽器效能預算、實作框架或 production token 修改。

## 1. 核心方向｜Afterrain Optics

高級感不來自增加發光物件，而來自同一批物件在不同介質中留下可追蹤的光學證據。T7 的視覺接力是：

> 雨後現實反光 → 低彩度銀灰解讀 → 真實產品玻璃 → 受控 Coach 紫

四段不是四個世界。光源方向、脊柱、遮擋來源與 O1～O8 的 identity 都必須連續。每一次變清楚，都由粗糙度下降、焦點平面變薄、透視收正與文字回到真實尺寸共同完成，不靠 screenshot replacement、純 fade 或突然點亮。

## 2. 四層材質系統

### L1｜Physical Wet Glass

用途：承接 M6 的真實濕窗，建立 G0 的物理來源。

- 基底為低彩度暖灰黑，不使用純黑太空背景。
- 雨痕有重力方向、局部聚合與不同粗糙度；不使用均勻粒子或星塵。
- 街燈反射保留暖意，但面積小、亮度低，不形成橘色成功路徑。
- 景深可遮住資訊，但不可暗示答案藏在霧後。
- 水滴只作材質與焦點證據，不折射森林、海、地球或宇宙。

Lookdev 參考值（未凍結，且不修改產品 token）：

- 底色：`#111217`／`#17171A`
- 濕窗暖灰：`#958E82`
- 雨後高光：`#C8BBA4`
- 最大環境飽和度：18%

### L2｜Interpretive Silver

用途：將 M6 的街燈反射校準成 O6 銀灰可能線與 T7 連續脊柱。

- 色相接近香檳白／暖銀，不接近 CTA 橘。
- 線寬穩定前仍保留濕玻璃的折射破碎；穩定後才取得可追蹤方向。
- 不做霓虹外發光，不做資料隧道，不顯示成功率或答案。
- O6 的亮度不得高於正在解析的真實 UI edge。
- 反向觀看時，銀線必須回到反射，不得像取消一條已完成的答案線。

Lookdev 參考值（未凍結）：

- 主銀灰：`#C9C3B8`
- 冷側反射：`#9CA3B0`
- 可見 edge alpha：32%～58%
- 柔光半徑：只作材質擴散，不超過線寬的 3 倍

### L3｜Product Glass

用途：讓 G1～G3 的物件解析回現行 VibeSync，而不是生成電影專用 HUD。

- 基底沿用產品深色世界：`brandInk #150C24`、`brandSurface #1F1330`、`brandSurface2 #2A1840`，K1／K2 背景再銜接 `#070812`／`#0B0A14`。
- 產品卡面依真實 UI 使用白色約 8% 的 surface、白色約 14% 的 border。
- 玻璃效果只存在於邊、反射與深度，不把每張卡都做成透明毛玻璃。
- 解析中的卡仍可保留濕窗反射；完全進入 K1／K2 後必須回到真實產品質感與資訊密度。
- 產品內容不可為了電影構圖改成假數值、假拓樸或更漂亮的摘要。

### L4｜Coach Surface

用途：G4 最後解析 O8，讓 Sydney 成為可信的教練介面，而非發光角色或全知 AI。

- 背景使用現行 Coach 深藍紫：`#2A1831`、`#111329`、`#090C1B`。
- Coach 紫使用 `#9D78F5`／`#C68BFF`，只標示教練來源、頭像與當下閱讀焦點。
- Sydney 頭像保持真實來源與人像質感，不加 halo、不投射巨大剪影。
- `教練參考` strip 與真實泡泡保留產品樣式；不新增電影專用 citation。
- G4 可只讀 Sydney，但 K1／K2 必須仍以反射、暗邊或 hidden stack 留在同一 scene graph。

## 3. 色彩責任與面積階級

| 色彩 | 唯一職責 | 允許位置 | 禁止 |
| --- | --- | --- | --- |
| 雨後暖灰 | 現實物理來源 | G0、未解析 edge、濕窗反射 | 變成浪漫金色大道 |
| 銀灰 | 可被重新閱讀的方向 | O6、baseline、解析接力 | 變成正確答案或成功路徑 |
| Coach 紫 | 教練與解讀層 | O8、Coach header、來源 strip | 佔滿環境、變成 AI 能量場 |
| 產品原生橘 `#FF6A2B` | 現行產品行動／detail | K2 真實元件內 | 提前接管 T7、替結果慶祝 |
| 白／淡紫文字 | 證據與可讀性 | 真實 UI、必要座標 | 做成空間中的廣告標語 |

面積規則：

- 任一畫格中，Coach 紫的高彩度面積不超過可見畫面的約 8%。
- 原生橘只在真實產品元件內短暫可見，T7 環境本身不使用高飽和橘。
- hollow orb 是 O4 內的第二或第三閱讀層，不獨立居中，不放大為全片核心。
- 銀灰線只負責方向；它不得同時成為最亮、最粗、最高彩度的元素。

## 4. G0～G4 表面節拍

### G0｜R5 START｜先看見介質，不先看見答案

- O1～O8 全部仍在原 scene graph，但主要以折射邊、投影輪廓與遠近層次存在。
- 真實濕窗暖灰占主導；銀灰只從街燈反射中開始取得方向。
- 桌面可見多個 angled planes 的深度；手機只讓最前層輪廓可辨，其餘沿 z 軸退後。
- 不可像「產品卡片漂浮在雨景前」，介質必須穿過物件邊緣。

### G1｜IDENTITY LOCK｜姓名先收正，時間後對焦

- O1 `小安` 先從折射 baseline 收正；姓名變清楚時，周邊反射仍保留輕微不穩定。
- 短節拍後 O2 `週三 21:59` 才取得焦點。
- 身分層使用產品深色玻璃，不放大成巨大標題，不新增頭像。
- 其他物件不 fade，只降低對比、保留可追蹤 edge。

### G2｜SIGNAL LOCK｜看見訊號，也同時看見邊界

- O4 取得 `PartnerHeatHeroCard` 真實卡框、scope 與低權重 orb。
- 值區由 camera crop 離開畫框；不可用黑遮條、空 meter 或模糊數字假裝未決。
- scope 文字與 orb 同時存在，但第一閱讀層是「這只反映本次互動」。
- 銀灰脊柱可擦過卡面邊緣，不穿過可讀文字。

### G3｜MAP LOCK｜真實拓樸取得空間

- O3／O5／O6／O7 依現行 PartnerMindMapScreen 收成真實路徑。
- 閱讀順序是 `本輪訊號 → 互動重點 → 準備邀約 → 下一步行動`，不是四張同時彈出的功能卡。
- 原生橘 detail panel 保留產品真相，但透過曝光與 DOF 低於後續人物行動高潮。
- O6 附著真實 edge，不高亮、不冒出電影版節點。

### G4｜COACH LOCK｜產品交出方向，不交出答案

- O8 沿既有 Coach header baseline 收正為真實 `問教練 Sydney・小安`。
- Sydney 頭像、`教練參考` strip 與凍結訊息形成唯一閱讀平台。
- K1／K2 仍在後方，以很低強度的折射邊或反射證明 continuity；不可讀成另一個 dashboard。
- T7 到此為止，不提前露出外部聊天 K4，不讓 CTA 橘進場。

## 5. 光線、霧、景深與曝光退出

### 光線

- 主光方向始終可回溯到濕窗街燈反射；不能每一個產品面各有獨立 rim light。
- 高光只沿可解釋的玻璃 edge 或 UI border 出現。
- 文字不使用 bloom；必要文字靠局部對比與焦點取得可讀性。

### Fog

- G0 的霧用來降低方向資訊，不遮藏終極答案。
- 隨 G1～G4 前進，霧不是均勻淡出，而是由正在收正的焦點平面向外退出。
- 最終 K3 可保留極薄環境霧，不能污染真實 Coach UI。

### DOF

- 每個閱讀平台只有一個主要焦平面。
- 姓名、時間、scope、階段、下一步、Sydney 必須依序取得焦點，不同時搶讀。
- 手機景深更克制；模糊半徑不得吃掉小字筆畫。

### 曝光退出

- 解析不是「變亮」，而是表面粗糙度下降、局部曝光收斂、黑位回到產品真值。
- 進入 K1／K2／K3 後，環境高光必須退出，讓產品白字、14% border 與原生色成為可讀基準。

## 6. 字體與閱讀平台

本輪導演板採：

- 繁中：Noto Sans TC，負責所有產品內容與必要中文座標。
- 大型拉丁標記：Instrument Sans，只出現在審核板標題，不進產品 UI。
- 技術微標：Geist Mono，只出現在審核註記，不進 audience viewport。

產品畫面中的字體比例、行高與粗細必須回到真實 App；不借 Yuya 的 serif 當品質捷徑。空間文字只允許 `小安`、`週三 21:59` 與 frozen UI 自身內容，不新增利益句或哲學旁白。

## 7. 桌面與手機分開導演

### Desktop

- 可利用 angled planes、側向遮擋與較長的 baseline 接力。
- 允許同時看見兩至三層 depth，但只允許一層可讀。
- K1／K2 退到 K3 後方時，可用折射暗邊證明 hidden stack。
- 不把所有產品平面排成等距卡片牆。

### Mobile 9:16

- 沿 z 軸一次只正視一面；不能縮小桌面橫向作戰板塞入手機。
- O2 與 O6 必須仍可追蹤，但可透過頂部時間痕跡與側邊銀線存在。
- 玻璃 blur、fog 與 glow 強度比桌面低，優先保住繁中小字與真實 UI 邊界。
- G3 依 root → stage → next 取得前後焦點；G4 才由 O8 edge-to-edge 接手。

## 8. 正向、反向與 Reduced Motion

- 正向：物理反射逐步取得產品邊界。
- 反向：產品邊界逐步失去方向，回到反射；不是取消分析、撤回答案或時間倒帶。
- 同一對稱點的 audience viewport 應有效一致，但不要求 debug HUD bit-identical。
- Reduced motion 保留 K1 → K2 signal → K2 map／next → K3 四狀態；材質改用短距離 cross-dissolve、edge inheritance 與焦點切換，不能刪除 O2 或 O6。
- reduced-motion 的 dissolve 只允許作用於表面響應；物件 identity、parent 與 destination 不變。

## 9. 導演驗收門檻

### 必須通過

1. 不看標籤也能辨認四段是同一束光、同一批物件與同一空間。
2. G0 讀成濕窗與反射，不讀成星空、資料隧道或產品卡牆。
3. G1 明確先讀 `小安`，再讀 `週三 21:59`。
4. G2 同時可讀 scope 與低權重 orb，且沒有人工數值或遮條。
5. G3 是現行 PartnerMindMapScreen 的拓樸，不是 Yuya DNA 圓環或電影 HUD。
6. G4 只讀 Sydney；K1／K2 仍可由光學證據追蹤，但不與 Coach 搶讀。
7. Coach 紫、hollow orb 與產品橘各守住唯一職責。
8. 手機 9:16 的必要繁中在縮小預覽仍可辨識，且不是桌面版縮小。
9. 反向觀看時不產生撤回訊息、取消勇氣或時間倒轉的解讀。
10. 無任何新增 O9、假數值、假聊天、假 citation、stage raster 或提前 K4。

### 直接退回

- 套版 glassmorphism、霓虹 HUD、星塵宇宙、中央巨大 orb。
- 以純 fade 或換 screenshot 掩蓋 continuity。
- 紫色壓過人物與產品，或橘色在 T7 成為勝利訊號。
- 每個畫格都像獨立海報，無法追蹤同一束光與同一批物件。
- 為了美觀修改真實產品資訊、拓樸、文字或資料可信邊界。

## 10. Revision 1.1 正式交付物

- Desktop G0～G4 Lookdev Contact Sheet。
- Mobile 9:16 G0～G4 Lookdev Contact Sheet。
- Material Response Board：濕窗、銀灰解讀、產品玻璃、Coach 表面、字體回位與色彩責任。
- 本規格與 `Afterrain Optics` 視覺哲學。
- 自足式 GPT 審核 ZIP，附檔案清單與 SHA256。

## 11. 治理

Revision 1.1 已正式通過並凍結；Revision 1 的候選治理已結束。凍結效力只涵蓋本文件「導演拍板紀錄」所列的材質方向、色彩責任、光學接力與桌機／手機視覺層級，不把參考數值升格為 production shader 參數。

- M7 Revision 1.1、T7 Greybox Revision 1.1 與 M8 Revision 3.1 繼續凍結。
- 本次拍板沒有自動解鎖下一份成果；任何下一階段都需要 Eric 另行明確授權。
- M7 lookdev、T1／T4／T6、完整 animatic、舊 P0／P1 與 implementation planning 繼續暫停。
- 不修改 runtime、`marketing-site/`、產品 token、真實 App 元件或資料。
- 不 build、test、commit、push 或 deploy。
