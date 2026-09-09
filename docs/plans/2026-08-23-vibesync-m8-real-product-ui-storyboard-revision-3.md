# VibeSync 電影式官網｜M8 真實產品 UI Storyboard Revision 3.1

更新日期：2026-08-24

狀態：已完成 Revision 3.1 consistency patch，獲 Eric 導演拍板並正式重新凍結；後續 M7 Revision 1.1、T7 Greybox Revision 1.1 與 T7 Lookdev Revision 1.1 亦已通過並凍結。目前沒有下一階段自動解鎖；完整 animatic、T1／T4／T6、舊 P0／P1 與 runtime 實作仍暫停。

上位基準：`docs/plans/2026-08-23-vibesync-cinematic-site-yuya-calibrated-bible.md` Revision 16

前版紀錄：`docs/plans/2026-08-23-vibesync-m8-real-product-ui-storyboard.md` Revision 2

後續核准覆蓋：M7 Revision 1.1、`D-T7-GREYBOX-ALIGNMENT-01 Revision 1.1` 與 `D-T7-LOOKDEV-01 Revision 1.1` 已分別完成導演拍板並凍結。後文若仍寫「M7 可開始／T7 仍暫停／下一成果是 M7／只解鎖 T7 lookdev」，均只屬本版當時的歷史狀態；最新治理以 Story Bible 的後續覆蓋為準。M8 本身不因後續核准而重開，且本次 Lookdev 拍板不自動授權下一階段。

## 0. 治理狀態

本次不是推翻 Revision 16，而是把 M8 實際 storyboard 暴露出的產品真相與真人感問題，精準回寫到 M8。Revision 3.1 只完成四項一致性補丁，不重畫七格，也不改動已通過的主結構。

### Revision 3 曾窄幅重開（Revision 3.1 已完成並關閉）

- M8 桌面 storyboard。
- M8 手機 storyboard。
- `D-M8-01` 第一則精確文字。
- M8 七個 keyframe／四個閱讀平台的構圖與資訊層級。
- 真實 `PartnerMindMapScreen` 的呈現。
- 真實投入度輸出。
- 真實 Sydney UI。
- VibeSync 與外部聊天的交接。
- 片尾品牌平面。

### 繼續凍結

- `D-M1-01`。
- `D-SYDNEY-01`。
- `D-M6-01`。
- M8 第二則：`妳下週有空的話，要不要一起出去走走？`
- 兩次分開送出。
- Sydney 不代寫、不預填、不代發。
- 女生不顯示已讀、輸入中、上線、回覆或任何反應。
- 送出不可逆。
- 短黑場。
- 現有片尾定位與 App Store CTA。
- 其餘 M1～M8 故事與證據倫理。

### 先前拍板狀態

`D-M8-STORYBOARD-01` 保留為歷史決策，但因 storyboard 實際畫面暴露出資訊重複、人工分數、產品 UI 失真與片尾層級衝突，已停止作為製作依據。其「再次通過才重新凍結」條件已由 `D-M8-STORYBOARD-03.1` 完成。

---

## 1. D-M8-01-R1｜第一則窄幅修訂

### 第一則｜正式修訂

> 我剛剛才發現，那天我只回妳記得帶傘哈哈

### 第二則｜維持凍結

> 妳下週有空的話，要不要一起出去走走？

### 修訂邊界

- 第一則只承認男主自己的回覆，不定義她當時的意圖。
- 「回去看」由畫面短暫重現 M1 舊聊天證明，不再由文字重述。
- 第一則不再複述「想出去走走」，讓第二則的「一起出去走走」重新取得自然重量。
- 不加入「居然、原來、一句、只顧著、結果、報天氣」。
- 第二則字面與所有送出行為規則不變。

---

## 2. 唯一主推薦：七個 keyframe，四個閱讀平台

M8 不再被呈現成九個獨立 section。七個 keyframe 是動畫內部狀態，不等於七次 scroll snap；觀眾只感受到四個穩定閱讀平台。

| 閱讀平台 | Keyframe | 唯一任務 |
|---|---|---|
| A｜真實產品 payoff | K1 同一對象；K2 本次訊號＋目前階段 | 證明 VibeSync 認得小安、記得脈絡、知道目前可做什麼。 |
| B｜Sydney | K3 真實 Coach UI | 守住未知，把主導權交還給男主。 |
| C｜外部聊天 | K4 交接＋第一則輸入；K5 第一則送出；K6 第二則送出 | 讓人物自己承認、停頓、邀請。 |
| D｜品牌 | K7 短黑後片尾 | 以同一已送出狀態承接品牌，但不讓聊天文字與品牌文字競爭。 |

主路徑仍是：

> 真實對象產品脈絡  
> → 真實作戰板  
> → 真實 Sydney  
> → 同一外部聊天  
> → 兩次人物送出  
> → 短黑  
> → 同一 sent state＋品牌 CTA

---

## 3. 現行 App 真相源

| 要證明的事 | 真實頁面／元件 | Revision 3.1 使用規則 |
|---|---|---|
| 同一位對象 | `PartnerDetailScreen` AppBar、`_PartnerCommandSummaryCard` | 只讓一個 `小安` 成為第一閱讀層；不能在 storyboard 另畫不存在的頭像或資料卡。 |
| 最近互動 | `_SummaryLine(label: 最近互動)` | 使用真實時間欄位；不把 `有在回應` 重複放進 K1 的主要資訊。 |
| 本次投入度 | `PartnerHeatHeroCard` | 不人工合成分數。正式數字只能來自凍結 M1 的真實分析輸出。 |
| 投入度可信邊界 | `PartnerHeatMessaging.scopeExplanation` | 使用真實完整文案：`只反映這次互動中的文字訊號，不代表關係進度。` |
| 紫色 orb | `PartnerHeatHeroCard._HeatOrb` | 是真實產品裝飾，可存在但不得放大、離開 UI 平面或成為 Yuya 式核心球。 |
| 目前階段 | `PartnerMindMapEntryCard` 與作戰板階段節點 | 使用 `準備邀約` 文字狀態；不使用 report dock 的 stage raster。 |
| 整段脈絡 | `PartnerMindMapScreen`、`PartnerMindMapView` | 保留真實左到右作戰板拓樸；不得另畫中央 DNA 圓環、放射 topology 或電影專用節點。 |
| 作戰重點 | `_MindMapDetailPanel` | 使用真實 `互動重點／本輪訊號／下一步行動／問教練` 結構。 |
| Sydney 認得同一人 | `GlobalCoachScreen` | 保留真實標題 `問教練 Sydney・小安`，不另拆電影版 header。 |
| Sydney 參考來源 | `_CoachMemorySourceStrip` | 使用真實 `教練參考` strip 與現行來源 chips；不發明 citation 句。 |
| Sydney 頭像 | `CoachHeadAvatar`＋`sydney_greeting.png` | 使用真實頭像，不使用字母 S、光球或漂浮虛擬人。 |
| 最終定位 | `docs/positioning.md` | 字面不重寫，只重新安排層級。 |

### 3.1 人工 `54` 正式撤回

`PartnerHeatHeroCard` 的程式契約明定數字只讀取既有資料，不得合成。Revision 2 的 `54／有在回應` 是 storyboard 人工 fixture，正式撤回。

新規則：

- 若凍結 M1 經真實分析流程產生合法數值，正式 animatic 才能顯示該終值。
- 在尚未取得真實輸出前，Revision 3.1 contact sheet 只把 `有在回應` 當定性導演佔位，不聲稱存在特定分數。
- 若最終真實分數不是 `有在回應` 區間，狀態文字與數字必須一起更新，不能只保留故事較好看的標籤。
- 電影構圖可讓數字落在第二／第三閱讀層或裁切外，但不能修改 App runtime 假裝產品本身沒有數字。

### 3.2 真實作戰板正式保留

先前「第 4 張應刪除」的裁決撤回。錯的是 Revision 2 低擬真轉譯，不是真實產品功能。

Revision 3.1 延續並凍結：

- 使用現行 `PartnerMindMapScreen` 的左到右樹狀拓樸。
- 使用真實節點類型、連線方向、底部 `作戰重點` panel 與 `問教練` 入口。
- 不額外補 `本輪／上輪／上上輪` 以外的電影專用節點。
- 不模仿 Yuya 的 Project DNA 中央圖形。
- 讓圖存在，但每個 keyframe 只對焦一條閱讀路徑。

---

## 4. 故事資料與顯示契約

| 欄位 | Revision 3.1 | 邊界 |
|---|---|---|
| 對象暱稱 | `小安` | 合成名字，全片一致；不新增頭像。 |
| 分析次數 | `3` | 只出現在真實作戰板根節點，不塞入不存在的對象卡 tag。 |
| 最近互動 | `週三 21:59` | 只作 M1→M8 時間證據。 |
| 本次定性狀態 | `有在回應`，暫作導演佔位 | 正式 animatic 必須與真實分析數值一起驗證。 |
| 本次數值 | 未指定 | 禁止 storyboard 人工填數。 |
| 目前階段 | `準備邀約` | 使用現行產品文字階段。 |
| 下一步短層級 | `主動邀約` | 作為 story fixture 放入現有下一步欄位，不新增 UI 元件。 |
| 下一步補充 | `提出一個具體、好回答的共同活動。` | 次要閱讀層，不與 Sydney 重複「把意思說清楚」。 |
| Sydney 台詞 | 完整沿用 `D-SYDNEY-01` | 放入真實 Coach 泡泡，不另加候選句。 |
| 第一則 | `D-M8-01-R1` | 男主自行輸入、送出。 |
| 第二則 | 原 `D-M8-01` 第二則 | 字面不變，男主自行輸入、送出。 |

---

## 5. 狀態模型與唯讀分支

| 狀態 | 對應 Keyframe | 可逆性 | `直接看產品` |
|---|---|---|---|
| `P1` | K1 同一對象 | 可回看 | 可進入 |
| `P2` | K2 訊號／階段／真實作戰板 | 可回看 | 可進入並停在此唯讀平台 |
| `C1` | K3 真實 Sydney | 送出前可回看 | 不可觸發 |
| `T1` | K4 交接與第一則輸入 | 送出前可回看 | 不可觸發 |
| `S1` | K5 第一則已送出 | 事件不可逆 | 不可觸發 |
| `S2` | K6 第二則已送出 | 事件不可逆 | 不可觸發 |
| `F1` | K7 短黑後片尾 | CTA 可互動，sent state 不倒退 | 不可觸發 |

### `直接看產品`

- 只進入獨立的 `P1 → P2` 唯讀產品 payoff。
- 不出現 Sydney 最終訊息、外部輸入框、第一則、第二則或 sent flag。
- 返回後恢復原電影進度與原 sent flags。
- 桌面與手機都不得使用產品內 breadcrumb 暗示 VibeSync 能直接控制外部聊天。

---

## 6. 桌面 Contact Sheet｜七個 Keyframe

桌面不是 desktop dashboard。產品 UI 維持真實手機比例或真實產品平面；只有 K4 交接後，外部聊天取得較大的構圖權重。

### D-R3-1｜K1 同一對象

- **平台**：A｜真實產品 payoff。
- **畫面**：M7 姓名錨收正至 `PartnerDetailScreen`。攝影機裁切避免 AppBar 與命令卡兩個 `小安` 同時成為重音；只讓一個名稱清楚。
- **第一閱讀層**：`小安`。
- **必要可讀文字**：`最近互動`、`週三 21:59`。
- **可略讀 microcopy**：真實接法與 tags；`最近一次：有在回應` 不作此格重音。
- **Sydney**：不出現。
- **行動橘**：電影層不進場；真實 App 原生小 accent 維持原尺寸。
- **正向**：M7 姓名錨先對齊 AppBar 的 `小安`，停一個短但可辨認的節拍；焦點才落到 `週三 21:59`，再連續往下進 K2，不形成獨立 section。
- **Animatic gate**：觀看順序必須可讀為「先確認同一個人，再確認產品記得那次互動」；不得讓時間戳先於姓名成為最大重音。
- **反向**：返回 M7 姓名錨；不倒跑任何數值。
- **Reduced motion**：同位裁切＋短 dissolve。
- **M7 起始物件**：同一位對象姓名錨、最近時間節點。
- **真實來源**：`PartnerDetailScreen` AppBar、`_PartnerCommandSummaryCard` 的 `最近互動`。
- **刪除而不虛構**：不新增頭像；不把 `已分析 3 次` 塞入對象卡；不重畫不存在的 profile dashboard。

### D-R3-2｜K2 訊號、階段與真實作戰板

- **平台**：A｜與 K1 同一閱讀平台，連續向下／向內看清產品。
- **畫面**：先短停 `PartnerHeatHeroCard` 的狀態文字與 scope disclaimer，再落到 `準備邀約`，接著由真實 `PartnerMindMapEntryCard` 進入現行 `PartnerMindMapScreen` 的根節點與一條真實閱讀路徑，最後停在 `下一步／問教練` 入口；這是同一產品脈絡的連續焦點，不是三個 scroll snap，也不得同時要求閱讀所有區塊。
- **第一閱讀層**：依序為 `有在回應` → `準備邀約` → `小安・已分析 3 次`。
- **必要可讀文字**：`只反映這次互動中的文字訊號，不代表關係進度。`、`目前階段`、`準備邀約`、`下一步行動`、`主動邀約`。
- **可略讀 microcopy**：真實分數、投入度 subtitle、作戰板其他節點、`提出一個具體、好回答的共同活動。`
- **Sydney**：只在真實作戰板底部 `問教練` 入口存在。
- **行動橘**：只保留產品原生下一步節點／按鈕的小面積 accent；正式曝光與景深權重必須低於 K6 的人物行動橘，不成為電影高潮。
- **正向**：投入度免責句與狀態同時可讀；stage badge 不像按鈕；作戰板使用真實左到右拓樸，最後停在 `作戰重點` panel。
- **反向**：沿同一焦點順序回看；階段不倒退、分析次數不減少。
- **Reduced motion**：三個真實裁切 state 以短 dissolve 接力，不 pan／zoom 整棵圖。
- **M7 起始物件**：投入度節點、階段、時間路徑、銀灰可能線、下一步終點。
- **真實來源**：`PartnerHeatHeroCard`、`PartnerMindMapEntryCard`、`PartnerMindMapScreen`、`PartnerMindMapView`、`_MindMapDetailPanel`。
- **刪除而不虛構**：不出人工 `54`；不放大 orb；不畫中央 DNA；不使用 `partner_stage_close.webp`；不新增電影專用節點。

### D-R3-3｜K3 真實 Sydney

- **平台**：B｜Sydney。
- **畫面**：作戰板真實 `問教練` 入口解析成 `GlobalCoachScreen`。標題維持 `問教練 Sydney・小安`；上方出現真實 `教練參考` strip 與現行來源 chips；使用真實 Sydney 頭像。
- **第一閱讀層**：`問教練 Sydney・小安`，接著完整三句。
- **必要可讀文字**：完整 `D-SYDNEY-01`。
- **可略讀 microcopy**：`教練參考`＋`對象資料` 等真實 chips；不新增 citation 句。
- **Sydney**：真實 `CoachHeadAvatar`，不對嘴、不換姿勢。
- **行動橘**：不落在 Sydney 命令或泡泡上。
- **正向**：context strip 先建立來源，泡泡整句出現；鏡頭完全停住。
- **反向**：未送出可回 K2；送出後重看不影響外部 sent state。
- **Reduced motion**：同位切換，泡泡整句顯示。
- **M7 起始物件**：Sydney 平面、Coach 頭像。
- **真實來源**：`GlobalCoachScreen`、`_CoachMemorySourceStrip`、`CoachHeadAvatar`。
- **刪除而不虛構**：不使用字母 S、通用 AI 球、候選句、複製、預填或成功保證。

### D-R3-4｜K4 交接與第一則輸入

- **平台**：C｜外部聊天與人物選擇。
- **畫面**：Sydney 產品平面滑出；同位置的 `小安` 由中性外部聊天 header 接手。交接前短暫重現 M1 四顆泡泡，再回到週六空輸入框。任何 `VibeSync → 外部聊天` 只可放在鏡頭外 storyboard annotation，不進 diegetic UI。
- **第一閱讀層**：空輸入框取得焦點，接著第一則由兩至三個自然語意節拍輸入。
- **必要可讀文字**：`我剛剛才發現，那天我只回妳記得帶傘哈哈`。
- **可略讀 microcopy**：`週六 00:4X`、中性外部聊天 chrome。
- **Sydney**：產品平面退出後不再出現。
- **行動橘**：尚未進場；第一則不是高潮。
- **正向**：空輸入框 → 游標取得焦點 → 自然輸入 → 第一次送出。
- **K4 internal beat 0**：外部聊天取得焦點後，先看見空輸入框＋可見游標；此時沒有任何預填文字。
- **K4 internal beat 1**：第一段文字才由男主從零開始出現。兩個 internal beat 不增加 keyframe 或閱讀平台。
- **反向**：`S1` 前可回空輸入框；`S1` 後回到本格直接顯示第一則已送出，不重打。
- **Reduced motion**：空輸入框停一拍，再切成完整第一則已送出；不逐字。
- **M7 起始物件**：沒有新物件，這是產品交回主導權的出口。
- **真實來源**：左側為真實 Coach；右側為 M1 同一外部聊天 shell。
- **刪除而不虛構**：無 VibeSync breadcrumb、無預填、無剪貼簿、無 AI 代發。

### D-R3-5｜K5 第一則已送出

- **平台**：C。
- **畫面**：第一則使用外部聊天正常 outgoing style；輸入框清空、send icon inactive。畫面保持中性，沒有任何女生狀態。K4 的雙平面交接在此已結束，Coach 平面必須完全退出；最多只可留下無法辨認內容的暗紫邊緣或環境反射。
- **第一閱讀層**：第一則泡泡與其下方空白。
- **必要可讀文字**：第一則完整文字。
- **可略讀 microcopy**：送出時間。
- **Sydney**：不出現、不鼓勵；不得辨認出頭像、標題、泡泡、文字或輸入框。
- **行動橘**：不進場。
- **正向**：停一個自然節拍，男主在無外部回饋下再次進入輸入框。
- **反向**：`S1` 永久保留。
- **Reduced motion**：固定閱讀平台，不做等待點或呼吸動畫。
- **M7 起始物件**：下一步尚未完成。
- **真實來源**：M1 外部聊天 shell＋`D-M8-01-R1`。
- **刪除而不虛構**：無已讀、typing dots、上線、回覆或 Sydney thumbs-up。

### D-R3-6｜K6 第二則送出

- **平台**：C。
- **畫面**：第二則以正常泡泡最大寬度自然折成兩行，不在字串人工換行。開始輸入時 send icon 與男主側環境反射取得行動橘；送出瞬間達最高亮度，落定後 bubble 回到中性 outgoing style，輸入框失焦、send icon inactive。Coach 平面已完全退出，不得與人物高潮並存。
- **第一閱讀層**：`妳下週有空的話，要不要一起出去走走？`
- **必要可讀文字**：第二則完整文字。
- **可略讀 microcopy**：無。
- **Sydney**：不出現；不得辨認出任何 Coach UI 殘影。
- **行動橘**：只存在於第二則輸入與送出瞬間；不得在落定泡泡上留下永久橘框。
- **正向**：第二次送出建立 `S2`，留一拍安靜。
- **反向**：`S2` 永久保留，只能回看。
- **Reduced motion**：空輸入框 → 中性已送出泡泡；橘色只以一次短暫 opacity／haptic 回饋出現。
- **M7 起始物件**：下一步由人的行動完成，結果仍未知。
- **真實來源**：同一外部聊天 shell＋原 `D-M8-01` 第二則。
- **刪除而不虛構**：無永久橘泡泡、成功、配對、回覆、煙火或勝利音。

### D-R3-7｜K7 短黑後片尾

- **平台**：D｜品牌。
- **畫面**：短黑後回到同一 sent state，但兩顆泡泡移至上方三分之一並降至 8～12% 閱讀強度；輸入框與 send icon 完全退場。下方 50～55% 升起接近實色的深紫品牌平面；品牌文案只放在實色平面，不壓聊天文字。真實 VibeSync 產品可作極弱側後景。
- **第一閱讀層**：`不只教你回這句`。
- **必要可讀文字**：`VibeSync`、`你專屬的 AI 戀愛教練`、`不只教你回這句`、`教練帶你從曖昧一路走到約出來`、`在 App Store 下載`。
- **可略讀 microcopy**：Privacy、Terms、返回電影。
- **Sydney**：不新增角色姿勢，只能作極弱產品記憶。
- **行動橘**：重新成為 CTA 唯一互動焦點。
- **正向**：靜態 finale，不再自動播放。
- **反向**：返回 K6，兩則仍已送出。
- **Reduced motion**：短黑後直接顯示固定分層構圖。
- **M7 起始物件**：不新增功能，只總結已證明的價值。
- **真實來源**：K2／K3 真實產品後景＋K6 同一 sent state＋正式定位。
- **刪除而不虛構**：品牌文字不得穿過聊天文字；不顯示輸入框、女生回覆、新 slogan 或空白廣告海報。

---

## 7. 手機 Contact Sheet｜七個 Keyframe

手機 edge-to-edge。不得把桌面雙平面縮小塞進窄螢幕；產品與外部聊天以全螢幕交棒。

### M-R3-1｜K1 同一對象

- **平台／第一閱讀層**：A／`小安`。
- **必要文字**：`最近互動`、`週三 21:59`。
- **略讀**：真實接法與 tags。
- **Sydney／橘色**：不出現／電影層不進場。
- **正向／反向**：`小安` 先落位一個可辨認節拍，焦點才轉到 `週三 21:59` 並連續進 K2／回 M7 姓名錨。
- **Reduced motion**：同位 dissolve。
- **M7 物件**：姓名錨、最近時間。
- **真實來源**：`PartnerDetailScreen`。
- **刪除**：不新增頭像，不把分析次數塞入不存在的 tag；避免兩個 `小安` 同時搶重音。

### M-R3-2｜K2 訊號、階段與真實作戰板

- **平台／第一閱讀層**：A／`有在回應` → `準備邀約` → `小安・已分析 3 次`。
- **必要文字**：完整 scope disclaimer、`下一步行動`、`主動邀約`。
- **略讀**：真實數值、orb、其他節點與補充句。
- **Sydney／橘色**：只在作戰板 `問教練` 入口／原生小 accent。
- **正向／反向**：依序閱讀「狀態＋可信邊界 → 準備邀約 → 作戰板根節點＋一條真實路徑 → 下一步／問教練」；相反順序回看時資料不倒轉。原生橘色保持低於 K6 行動橘的視覺權重。
- **Reduced motion**：三個全螢幕真實裁切 state，不移動整棵 graph。
- **M7 物件**：投入度、階段、時間、可能線、下一步。
- **真實來源**：`PartnerHeatHeroCard`、`PartnerMindMapEntryCard`、`PartnerMindMapScreen`。
- **刪除**：人工 `54`、放大 orb、中央 DNA、stage raster、電影專用節點。

### M-R3-3｜K3 真實 Sydney

- **平台／第一閱讀層**：B／`問教練 Sydney・小安`＋三句台詞。
- **必要文字**：完整 `D-SYDNEY-01`。
- **略讀**：真實 `教練參考` strip 與來源 chips。
- **Sydney／橘色**：真實頭像／不進場。
- **正向／反向**：整句顯示／送出前可回作戰板，送出後只回看。
- **Reduced motion**：同位切換。
- **M7 物件**：Sydney 平面。
- **真實來源**：`GlobalCoachScreen`、`_CoachMemorySourceStrip`、`CoachHeadAvatar`。
- **刪除**：字母 S、通用 AI 球、電影 citation、候選句與預填。

### M-R3-4｜K4 全螢幕交接與第一則輸入

- **平台／第一閱讀層**：C／空輸入框 → 第一則。
- **必要文字**：第一則完整修訂文字。
- **略讀**：週六時間；交接前短暫 M1 四泡泡。
- **Sydney／橘色**：外部聊天接手後完全退出／不進場。
- **正向／反向**：Coach 全螢幕退場，外部聊天全螢幕接手，空框後自然輸入／`S1` 前可回空框，之後只顯示 sent state。
- **K4 internal beat 0／1**：先顯示空輸入框＋可見游標，再由男主從零輸入第一段；不得讓 contact sheet 或 animatic 只留下已有文字的輸入框，兩拍不新增第八格。
- **Reduced motion**：Coach 靜態畫面 → 外部聊天空框 → 第一則已送出。
- **M7 物件**：產品交回人物的出口。
- **真實來源**：真實 Coach＋M1 外部聊天 shell。
- **刪除**：VibeSync breadcrumb、兩 App 同材質、overlay composer、AI 預填。

### M-R3-5｜K5 第一則已送出

- **平台／第一閱讀層**：C／第一則與下方空白。
- **必要文字**：第一則完整文字。
- **中文換行**：原始字串不插入人工換行；以泡泡最大寬度、內距與語意 no-break 保護 `帶傘哈哈`，禁止在 `帶／傘` 之間斷行。
- **略讀**：送出時間。
- **Sydney／橘色**：不出現／不進場。
- **正向／反向**：停一拍後再聚焦輸入框／`S1` 永久保留。
- **Reduced motion**：固定閱讀平台。
- **M7 物件**：下一步尚未完成。
- **真實來源**：M1 外部聊天 shell＋`D-M8-01-R1`。
- **刪除**：已讀、typing dots、上線、回覆、等待動畫。

### M-R3-6｜K6 第二則送出

- **平台／第一閱讀層**：C／第二則自然兩行；理想視覺為 `妳下週有空的話，`／`要不要一起出去走走？`。
- **必要文字**：第二則完整文字。
- **中文換行**：原始字串不插入人工換行；以泡泡最大寬度、內距與語意 no-break 保護 `出去走走？`，禁止在 `走／走` 之間斷行。
- **略讀**：無。
- **Sydney／橘色**：不出現／只在輸入與送出瞬間。
- **正向／反向**：送出後泡泡回中性、輸入框失焦／`S2` 永久保留。
- **Reduced motion**：短暫橘色回饋後直接顯示中性 sent state。
- **M7 物件**：人的行動完成。
- **真實來源**：同一外部聊天 shell＋凍結第二則。
- **刪除**：永久橘框、大片橘暈、女生反應、成功訊號。

### M-R3-7｜K7 分層片尾

- **平台／第一閱讀層**：D／`不只教你回這句`。
- **必要文字**：正式定位四層＋App Store CTA。
- **略讀**：Privacy、Terms、返回電影。
- **Sydney／橘色**：不新增角色／只在 CTA。
- **正向／反向**：短黑後固定 finale／回 K6 時 sent state 不變。
- **Reduced motion**：固定上方模糊聊天＋下方實色品牌平面。
- **M7 物件**：無新增。
- **真實來源**：K2／K3 真實產品痕跡＋K6 sent state＋正式定位。
- **刪除**：輸入框、send icon、可讀聊天文字與品牌文字重疊、新 slogan、女生回覆。

---

## 8. 產品層與外部聊天層

| 維度 | VibeSync | 外部聊天 |
|---|---|---|
| 背景 | 墨紫／深紫品牌面 | 中性近黑／深灰 |
| 身分 | `問教練 Sydney・小安`、`教練參考` | 只顯示聯絡人 `小安` |
| 輸入框 | 問 Sydney 的問題 | 男主傳給小安的訊息 |
| 動作 | 提供方向與脈絡 | 人物自行輸入與送出 |
| 橘色 | 原生操作 accent，非人物高潮 | 第二則輸入／送出瞬間的電影反射；落定後恢復中性 |
| 禁止 | 預填、代發、女生內心 | VibeSync breadcrumb、Sydney 建議句、成功預測 |

交接由兩個不同 header 接手完成：

> `問教練 Sydney・小安`  
> → `小安`

鏡頭外可標記「VibeSync → 外部聊天」供 storyboard 審稿，但不得進入角色看得到的 UI。

---

## 9. M7 → M8 真實目的地（供未來使用，本輪不啟動 M7）

| M7 語意 | M8 真實目的地 | Revision 3.1 裁決 |
|---|---|---|
| 同一位對象 | `PartnerDetailScreen`／作戰板／Coach 標題中的 `小安` | 保留姓名，刪除頭像候選。 |
| 最近時間 | `最近互動：週三 21:59` | 保留。 |
| 多輪脈絡 | 作戰板根節點 `小安・已分析 3 次` 與真實枝節 | 保留真實拓樸，不另畫 DNA。 |
| 投入度 | `PartnerHeatHeroCard` | 保留定性與 scope；禁止人工分數；orb 不升格。 |
| 階段 | `準備邀約` | 保留文字狀態；stage raster 刪除。 |
| 銀灰可能線 | 作戰板 `本輪訊號`／`互動重點` | 保留不確定性，不變成答案。 |
| 下一步 | `下一步行動`／`主動邀約` | 保留為方向，不承諾結果。 |
| Sydney | 真實 Coach 頁、頭像、來源 strip | 保留，不另畫 AI 球。 |

任何沒有上述真實目的地的 M7 物件，未來一律刪除。

---

## 10. 輸入、送出、回捲與 reduced-motion

### 10.1 第一則

1. 外部聊天取得焦點。
2. 空輸入框至少存在一個可辨認節拍。
3. 文字以兩至三個自然語意節拍輸入，不必逐字播完。
4. 送出後輸入框清空，send icon inactive。
5. 不出現女生狀態。

### 10.2 第二則

1. 男主在無回覆、無 Sydney 鼓勵下重新聚焦輸入框。
2. 開始輸入時行動橘才進場。
3. 送出瞬間達最高亮度。
4. 泡泡落定後回外部聊天中性 outgoing style。
5. 輸入框失焦、send icon inactive。

### 10.3 不可逆

- `S1`、`S2` 各只發生一次。
- 回捲只能回看，不得把泡泡退回輸入框或刪字。
- resize、切換前景、進出唯讀產品預覽都不得改變既有 sent flags。

### 10.4 Reduced motion

- 保留七個 keyframe 與四個閱讀平台的次序。
- 透視、pan、長 camera 改成靜態裁切與短 dissolve。
- 輸入過程可省略，但空框與 sent state 必須分開。
- 橘色仍只作第二次行動的短暫回饋。

---

## 11. 片尾閱讀層級

手機與桌面都遵守：

1. `不只教你回這句`。
2. `教練帶你從曖昧一路走到約出來`。
3. `VibeSync／你專屬的 AI 戀愛教練`。
4. `在 App Store 下載`。

背景 sent state 只負責證明「人物已經行動」，不再承擔逐字閱讀。聊天文字不得穿過上述四層；輸入框與 send icon 完全退場。

---

## 12. Revision 3.1 驗收條件

Revision 3.1 已依 Eric 裁決完成下列驗收：

1. 有桌面完整 contact sheet。
2. 有手機完整 contact sheet。
3. 清楚標示七個 keyframe、四個閱讀平台。
4. 真實 `PartnerMindMapScreen` 拓樸可辨認，不是概念 HUD。
5. 沒有人工 `54` 或任何人工精確投入度分數。
6. 紫色 orb 維持產品原生低權重，不離開 UI 平面。
7. 使用真實 Sydney 頭像、標題與 `教練參考` strip。
8. 外部聊天沒有 VibeSync breadcrumb，且材質明顯不同。
9. 交接可讀為：空輸入框 → 第一則 → 停頓 → 第二則。
10. 第二則落定後恢復中性泡泡，輸入框失焦。
11. 片尾聊天狀態與品牌文案完全分層，不互相穿過。
12. 每個 keyframe 都標明真實 App 來源與「不存在就刪除」。
13. 桌面與手機都不是七個獨立 section；七格只是內部 keyframe。
14. 不靠旁白仍能讀懂同一人、脈絡、階段、方向與人物自行送出。
15. 桌面 K5／K6 已移除所有可辨認 Coach 平面。
16. 手機兩則訊息未修改原始字串，且不拆開 `帶傘哈哈`、`出去走走？`。
17. K4 已明確標示空輸入框＋游標，再進入人物輸入的 internal beat。
18. Revision 16 已加入 Revision 3.1 上位覆蓋，不再恢復舊第一則或 stage raster。

---

## 13. 導演審核附件

- 桌面 contact sheet：`docs/handover-screenshots/m8-revision3/vibesync-m8-revision3-1-desktop-contact-sheet.png`
- 手機 contact sheet：`docs/handover-screenshots/m8-revision3/vibesync-m8-revision3-1-mobile-contact-sheet.png`
- 視覺哲學：`docs/plans/2026-08-23-vibesync-m8-revision3-visual-philosophy.md`

兩張 contact sheet 是 keyframe 與閱讀平台的導演審核圖，不是 App runtime screenshot，也不是最終 lookdev。K2 以現行 `partner_mindmap.png` 證據、真實頁面拓樸與真實元件結構製作 source-faithful composite；正式 animatic 仍須使用通過真實資料管線的固定產品 snapshot。

---

## 14. D-M8-STORYBOARD-03.1｜正式重新凍結

Eric 已裁決 Revision 3 主結構通過，並核准四項 consistency patch：桌面 K5／K6 Coach 完全退出、手機中文語意換行、K4 空輸入框 internal beat、Revision 16 上位覆蓋。四項補丁均已入檔與進入 contact sheet。

因此正式記錄：

- 七個 keyframe、四個閱讀平台、桌面／手機分開導演與 K1～K7 主結構重新凍結。
- `D-M8-01-R1` 第一則與原 `D-M8-01` 第二則正式凍結。
- 真實 `PartnerMindMapScreen`、無人工 `54`、低權重 orb、真實 Sydney UI、外部聊天邊界、兩次不可逆送出與分層片尾正式凍結。
- M7 可在下一個明確製作階段依第 9 節一對一回推；本次補丁本身不啟動 M7。
- T7 仍須等待 M7 灰盒目的地成立；舊 P0／P1 與 runtime implementation planning 繼續暫停。

---

## 15. NOT in scope

- M7 空間構圖、美術完稿或物件動畫。
- T1／T4／T6／T7 greybox。
- Flutter、Three.js、WebGL、GSAP 或 sent-state 的實作方案。
- 修改 App runtime 來配合電影。
- 執行真實 AI 分析或指定最終投入度數值。
- build、test、commit、push、deploy。
- 重算舊 P0／P1 implementation plan。

Revision 3.1 已完成並重新凍結；其後 M7、T7 Greybox 與 T7 Lookdev 均已依序完成、通過並凍結。這段歷史製作順序不構成新的工作授權；目前完整 animatic、T1／T4／T6、舊 P0／P1、runtime 與 implementation planning 均繼續暫停。
