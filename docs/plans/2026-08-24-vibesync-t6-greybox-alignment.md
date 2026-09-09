# D‑T6‑GREYBOX‑ALIGNMENT‑01｜M6 真實反射 → M7‑R1 同一對象辨認

更新日期：2026-08-24  
版本：Revision 1.1 Approved  
狀態：已獲 Eric／外部總導演正式通過並凍結；不需要 Revision 1.2  
唯一主推薦：A｜Reflection-edge inheritance／反射共邊辨認

> **正式核准覆蓋（2026-08-24）**：Revision 1 的 A 方案、Q1～Q8、return／rain 與時間邊界維持成立；G1／G2／G3／G5 的局部共邊證據由 `2026-08-24-vibesync-t6-greybox-alignment-revision1-1.md` 覆蓋並正式凍結。核准紀錄以 `APPROVED_RECORD_REVISION1_1.md` 為準；後文候選語句只算歷史描述。

## 1. 本輪只回答一個高風險問題

> M6 濕窗上的真實街燈反射，能否在不變成資料隧道、不翻成另一張 UI、不新增節點網路的前提下，逐步取得「這是同一位對象小安」的產品語意？

本輪是四條高風險 Greybox 中最後一條。它不做 M7 lookdev、不做完整 M7、不做 T7，也不進入 M8。它只證明：

1. 第一閱讀仍是真實濕窗、街燈來源與其反射。
2. 反射只先穩定一小段，不一開始就像關係圖或資料路徑。
3. 手機微光、AppBar 薄片與姓名由同一條反射邊緣依序取得幾何。
4. `小安` 是 AppBar 內的原生姓名，不是浮空 HUD label。
5. T6 終點停在凍結的 M7‑R1；`週三 21:59` 仍不可讀，留給 M7‑R2。

## 2. 邊界校正：T6 不越過 M7‑R1

上位 Transition Bible 把完整入口順序寫成：

> 真實濕窗反射 → 穩定方向 → `小安` → `週三 21:59` → 少量產品平面

但已凍結的 M7 Revision 1.1 更精確規定：R1 第一閱讀只能是 `小安`，`週三 21:59` 在 R1 必須仍被景深／反射遮擋，到 R2 才取得焦點。

因此本 T6 proof 的正式終點是：

> 真實濕窗反射 → 穩定方向 → 手機微光共邊 → AppBar 薄片附著 → `小安` 可讀

Q7 `timeSeed` 可以從第 1 幀存在，作為下一段的空間來源；但整個 T6 audience viewport 內不得讀到 `週三 21:59`。這不是刪除時間，而是守住已凍結的 R1／R2 閱讀順序。

## 3. 不得重開的上位真相

- D‑M6‑01 維持：主雨滴拉遠成普通濕窗，手機只是一點現實微光，literal 地球／宇宙／森林／海不回流。
- M6 只改變觀看尺度與方向，不替人物增加命運。
- M7 Revision 1.1 的 R1～R5、O1～O8、桌面／手機構圖與產品目的地維持凍結。
- T7 Greybox／Lookdev、M8 Revision 3.1 與所有真實產品 UI 維持凍結。
- T6 不出現作戰板、orb、Sydney、投入度、階段、下一步或產品利益句。
- 暖灰／骨白只能逐步去飽和成銀灰；不突然變霓虹紫、行動橘或浪漫香檳金。

## 4. 三個拋棄式結構方案

### A｜Reflection-edge inheritance／反射共邊辨認（唯一主推薦）

真實街燈與其濕窗反射從第 1 幀存在。攝影機沿反射小幅轉向，只讓一小段邊緣逐漸穩定。手機微光先與這段邊緣共享方向；同一個被裁切的 AppBar 薄片再由近乎 edge-on 的姿態取得寬度。`小安` 最後在薄片內聚焦，時間仍失焦。

為何推薦：

- 前後鏡共享真實接力物，不靠純 fade 或第二張 screenshot。
- 產品平面繼承反射的邊、方向與位置，符合 Yuya Demo 的同位平面／材質接力文法。
- 發生的是「辨認」，不是世界忽然科技化。
- 可以明確停在 M7‑R1，不偷跑 R2。

風險：

- 反射若一開始太細、太直、太亮，會先被看成資料線。
- AppBar 若在共邊前就完整出現，會像 UI overlay。
- 姓名若和時間同時清楚，會破壞 M7 凍結順序。

### B｜Reflection ribbon extrusion／反射帶擠出（淘汰）

讓反射逐漸變寬、取得厚度，再把 AppBar 放到發光帶上。

淘汰理由：

- 反射會變成霓虹道路、資料高速公路或 tunnel entrance。
- 視覺奇觀會早於「同一個人」。
- 容易新增不屬於 M7 的 ribbon／node 系統。

### C｜Phone-glass flip／手機反光翻面（淘汰）

先形成一塊手機螢幕反光，再將它翻面成 AppBar。

淘汰理由：

- 最像 card flip、device reveal 或 screenshot replacement。
- 會讓觀眾以為鏡頭進入另一支手機，而不是沿同一反射辨認產品脈絡。
- UI 的平面來源雖直觀，但沒有繼承街燈反射的核心責任。

## 5. 正式物件白名單

| ID | 物件 | M6 起始責任 | T6／M7‑R1 目的地 | 禁止替換 |
|---|---|---|---|---|
| Q1 | `wetGlass` | 真實濕窗介質 | 持續存在的物理表面 | 不建立第二個 scene／portal |
| Q2 | `streetReflection` | 有街燈來源、破碎暖灰反射 | 穩定一小段並成為產品邊緣來源 | 不生成 tunnel／node network |
| Q3 | `sourceStreetlight` | 反射的現實光源與街景 | 持續提供來源證據 | 不變成無來源 glow |
| Q4 | `phoneMicroReflection` | 不可讀的手機微光 | 與 Q2 共邊，提供 UI 平面來源 | 不顯示完整手機／產品 screenshot |
| Q5 | `appBarFragment` | 從第 1 幀存在但 edge-on、裁切、失焦 | M7‑R1 被裁切的真實 AppBar 薄片 | 不 clone、不另貼身分卡 |
| Q6 | `nameAnchor` | Q5 內的同一文字節點 | `小安` 成為唯一第一閱讀層 | 不做浮空 label／typewriter |
| Q7 | `timeSeed` | Q5 內的後續時間來源 | T6 全程不可讀；留給 M7‑R2 | 不提前讀出 `週三 21:59` |
| Q8 | `residualRain` | M6 殘留物理雨痕 | 實際時間持續向下 | 不因 camera return 倒流 |

Q1 內的窗框、水膜與反射折痕是同一物理介質的子表面，不新增敘事物件。Q3 內的建築、路面與遠處小光只用來證明來源，不是新世界觀。

白名單外的 date node、網格、orb、作戰板、Sydney、階段圖、成功符號、資料粒子、星塵、宇宙、女性剪影與外部聊天一律禁止。

## 6. A 方案的六個閱讀 gate

### T6‑G0｜真實反射

- Q1、Q2、Q3、Q4、Q5、Q6、Q7、Q8 從第 1 幀已建立，沒有中途替換。
- 第一眼只能讀到濕窗、街燈來源與破碎暖灰反射。
- Q5 接近 edge-on 且被裁切／失焦；Q6／Q7 都不可讀。
- 反射不含節點、箭頭、日期刻度或產品紫。

### T6‑G1｜方向穩定

- 只穩定 Q2 的一小段寬度與邊緣。
- Q2 由破碎暖灰逐步去飽和；仍可被理解為反射。
- 攝影機沿線小幅轉向，不高速前進，也不建立隧道消失點。

### T6‑G2｜手機微光共邊

- Q4 的反射方向與 Q2 局部切線對齊。
- Q4 仍不能讀成完整裝置或產品卡。
- 沒有產品文案、姓名、時間或其他 UI 先取得焦點。

### T6‑G3｜產品邊界附著

- 同一 Q5 由 edge-on／裁切姿態取得少量寬度。
- Q5 的近邊與 Q2 共享位置與方向，讓產品邊界看起來由反射取得，而非畫面上方貼入。
- Q6 仍模糊；Q7 更弱。

### T6‑G4｜姓名取得焦點

- Q6 `小安` 在同一 Q5 內聚焦。
- 不逐字打字、不放大成標題、不加 avatar 或個人資料卡。
- Q7 仍保持足以阻止閱讀的 blur／反射遮擋。

### T6‑G5｜M7‑R1 穩定閱讀平台

- 第一閱讀層只有 `小安`。
- Q5 仍是帶小透視的局部薄片，不是完整產品頁。
- Q2、Q3 與 Q4 仍提供低強度來源證據；不能在姓名出現後全部消失。
- `週三 21:59` 仍不可讀；T6 到此停止。

Revision 1 proof 使用 Frame `0／32／64／96／128／152／160` 作為 gate 稽核參數；不是最終秒數。

## 7. 桌面與手機分開導演

### Desktop 1920×1080

- Audience 為 1440×810，右側 debug 只屬審核工具。
- 反射以斜向深度穿過畫面，AppBar 薄片位於中央偏右。
- 可使用少量 X／Z 位移與 Y 軸透視，不能 orbit 或高速沿線飛行。
- `小安` 先在局部薄片取得焦點；不得形成產品 room。

### Mobile 1080×1920

- Audience 真正 edge-to-edge 9:16，沒有 device shell、debug 牆或桌面 letterbox。
- 反射沿垂直深度上升；一次只正視一個小平面。
- AppBar 位於頂部安全區內，但保持局部裁切與小透視。
- 不把桌面斜向全景縮成窄卡；不讀時間。

## 8. Camera return 與物理時間

本 proof 使用 321 frames／12 fps：

- Frame 0→160：camera state 由 M6 進入 M7‑R1。
- Frame 161→320：camera state 返回 M6 的觀看位置。
- Q5／Q6 在返回時退回 edge-on、失焦與手機微光，不是被刪除。
- Q8 的 physical state 始終依 actual frame 前進，雨痕持續向下。

因此本輪不要求、不宣稱 audience viewport 對稱點像素一致。正確語意是：

> 視角可以回看；姓名重新失焦，物理雨勢沒有倒播。

時間事實也沒有反轉；T6 根本尚未把 `週三 21:59` 讀出來。

## 9. Reduced-motion

Reduced-motion 使用同一 Q1～Q8：

1. 保留真實濕窗與來源反射。
2. 用較短的 Q2 邊緣穩定取代大幅攝影機前進。
3. Q5 使用短距離 scale／crop／focus 接力，不換 screenshot。
4. Q6 由失焦到可讀；Q7 仍不可讀。
5. Mobile 仍是單一 9:16 表面。
6. Q8 仍保持物理時間向前。

短 dissolve 只允許作為姓名平面與來源反射的焦點接力；不得把整張 M6 screenshot dissolve 成 M7 screenshot。

## 10. 與 Yuya Demo 的關係

本輪借用的是導演文法，不是外觀：

- 上一個物件的位置、邊緣與材質成為下一個平面的起點。
- 大幅內容前先建立尺度與距離。
- 一次只讓一個閱讀焦點成立。
- 平面進入空間後仍能回到真實產品目的地。

本案原創且不可誤稱為 Yuya 原片內容：

- 濕窗、街燈反射、手機微光。
- `小安` 的同一對象倫理。
- 姓名先於時間的 R1／R2 gate。
- Camera return 與 residual rain 不倒播。

## 11. 正式通過門檻

1. 移除 debug 後，G0 第一眼仍是真實濕窗反射，不是銀色資料線。
2. Q2 能追溯到 Q3 的現實光源；沒有無來源 glow。
3. Q5 從第 1 幀存在且只有一個 instance；沒有 clone、第二 screenshot、scene replacement 或純 crossfade。
4. G2 仍不可讀任何產品 UI。
5. G3 可看出 Q5 的邊與 Q2 共邊，而不是卡片從畫外飛入。
6. G5 的 `小安` 在桌面與實際 9:16 手機可讀。
7. G5 的 `週三 21:59` 在桌面與手機都不可讀。
8. 全程沒有節點網路、完整時間線、orb、作戰板、Sydney、利益句、紫色能量場或行動橘。
9. Mobile 以垂直深度辨認單一 AppBar，不壓縮桌面構圖。
10. Return 時 Q5／Q6 失焦退回來源，Q8 仍向下；不宣稱 pixel symmetry。
11. Reduced-motion 保留 Q2 來源、Q5 同一 instance、Q6 聚焦與 Q7 不可讀。
12. T6 終點精確停在 M7‑R1，不提前開始 R2 或 T7。

## 12. Revision 1.1 正式證據

- Desktop Motion Proof：1920×1080、321 frames、12 fps、26.75 秒。
- Mobile Motion Proof：1080×1920、321 frames、12 fps、26.75 秒。
- Desktop／Mobile Contact Sheet。
- Real Reflection Source Evidence：G0／G2／G3。
- Edge Inheritance Evidence：G1／G2／G3／G5。
- Identity Hierarchy Evidence：完整 viewport、近裁切、瞇眼層級與 Mobile G5。
- Desktop／Mobile Reduced-motion Strip。
- 可操作 Prototype。
- QA Record、Package Manifest 與 SHA256。

Revision 1 已通過且未重開的 Return Semantics、A／B／C comparison 與 rain physics 保留在歷史封包，不要求於 Revision 1.1 重複送審。

## 13. 若獲導演拍板，建議凍結

- A｜Reflection-edge inheritance 為唯一正式 T6 結構；B／C 淘汰。
- Q1～Q8 stable identity、parent 與單一目的地。
- G0→G5 的理解順序。
- 真實來源反射先於產品語意。
- Q4→Q5 的共邊接力。
- Q6 `小安` 可讀、Q7 `週三 21:59` 不可讀的 T6 終點。
- Desktop 斜向深度與 Mobile 垂直深度的分開導演。
- Camera state 可返回、Q8 physical rain 不倒播。
- Reduced-motion 使用同一來源與同一物件。

## 14. 本輪不凍結

- 最終秒數、scroll 距離、frame window 與 easing。
- 精確焦段、camera path、DOF、fog、motion blur 與曝光。
- 反射 shader、roughness、IOR、transmission、水膜厚度與雨痕生成。
- AppBar 最終 pixel-perfect 產品尺寸與字型參數。
- 聲音 pre-lap、產品脈衝、雨聲與混音。
- T6 lookdev、M7 lookdev、完整 animatic 與 WebGL 效能預算。

這些後續參數不得反向改變來源順序、Q1～Q8 identity、R1／R2 邊界或禁止解讀。

## 15. 治理狀態

Revision 1.1 已獲 Eric／外部總導演正式拍板並凍結；不需要 Revision 1.2。本輪沒有修改 runtime、`marketing-site/`、Flutter、產品資料或任何 production code；沒有執行 build、test、commit、push 或 deploy。

T6 通過後：

- T6 獨立 lookdev 仍暫停。
- 完整 M1～M8 animatic 依 Eric 既有授權正式解鎖，成為下一個成果。
- 舊 P0／P1 與 implementation planning 暫停。
- runtime／`marketing-site/` 不得修改。

四條高風險結構轉場 T1／T4／T6／T7 已全部完成 Greybox 結構驗證；本文件不授權 runtime 或 P0／P1，只解鎖完整 Animatic。

## 正式請審結論

> 建議拍板 A｜Reflection-edge inheritance。它讓觀眾先看見一條有來源的雨後反射，再沿同一條邊辨認出 `小安`；產品沒有從現實上方貼進來，現實也沒有被抽成資料隧道。T6 精確停在 M7‑R1，把時間與更多產品資訊留給已凍結的後續閱讀。
