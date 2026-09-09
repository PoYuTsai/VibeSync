# D‑T4‑GREYBOX‑ALIGNMENT‑01｜M4 → M5 同面雨窗轉場

更新日期：2026-08-24  
版本：Revision 1.1 Approved  
狀態：Eric 已拍板；正式通過並凍結，不需要 Revision 1.2  
唯一主推薦：A｜Same-surface focus pull／同面焦點顯影

> 2026-08-24 核准覆蓋：Revision 1.1 已完成 Mobile edge-to-edge、移除 `focusRing`、W1～W10 單一 instance、G5 Sydney 幾何離場與 reduced-motion 驗證。Camera state 可逆、physical rain state 不可逆。下文若仍出現候選或待審字樣，一律視為歷史描述。

## 1. 本輪只回答一個高風險問題

> M4「證據停止的地方」能否在沒有硬切、黑場、crossfade、第二張場景或雨滴 portal 的情況下，成為 M5 的真實濕窗？

本輪不是 T4 lookdev、最終 shader、聲音設計或完整 animatic。它只證明：

1. M4 與 M5 是同一片玻璃。
2. 現實街景從第 1 幀就在玻璃後方，只是尚不可辨認。
3. 水氣以連續水膜收成一顆主雨滴，不用粒子聚集。
4. 轉場由粗糙度、折射、焦點、曝光與攝影機距離完成，不換畫面。
5. 回看可以返回觀看位置，但不能讓雨滴逆重力上升。

## 2. 不得重開的上位真相

- M4 不是「答案藏在霧後」，而是證據到此停止。
- Sydney 台詞與可信邊界維持凍結；不得新增旁白或哲學文案。
- M5 只拍男主所在的單一現實空間與普通小雨。
- 不出現女生、撐傘者、森林、海、宇宙、星塵或水滴內的象徵影像。
- 主雨滴是接力物，不是命運、眼淚、愛情或 portal。
- M5 的暖光只能有真實街燈來源，不能變成浪漫金色大道。
- 手機只允許一顆主水滴與一條窗框線，不縮入桌面 panorama。

## 3. 三個拋棄式結構方案

### A｜Same-surface focus pull／同面焦點顯影（正式主推薦）

街景從第 1 幀就在同一片玻璃後方。M4 的暗面不是另一個世界，而是玻璃表面的高 roughness、低 transmission、暗曝光與近焦結果。水膜收成主雨滴後，攝影機以微距跟隨；同一表面逐步降低粗糙度與模糊，窗框、濕街與有來源的燈光才被辨認。

優點：

- 同一表面連續性最可驗證。
- 「未知」不會被拍成藏有答案的霧。
- 雨滴只是焦點與尺度接力，不會被神化。
- 最接近 Yuya Demo 的導演文法：上一鏡的材質與位置直接長成下一鏡。

風險：

- 若曝光與焦點節拍不清，可能只像普通 blur-to-sharp。
- 若街景太早可辨認，M4 的證據邊界會失效。
- 若雨滴太亮或太大，會變成香水廣告式 hero object。

### B｜Droplet lens aperture／雨滴鏡片開口（淘汰）

讓主雨滴放大成局部鏡片，先在水滴內看見街景，再擴張到全窗。

淘汰理由：

- 容易把雨滴拍成 portal 或藏有答案的容器。
- 會暗示「真相一直在水滴後面」，違反 M4 的證據倫理。
- 巨大水滴容易成為全片奇觀與香水廣告視覺。

### C｜Window-frame reveal／窗框掃掠揭露（淘汰）

用窗框近邊掃過鏡頭，把暗證據面換成雨窗。

淘汰理由：

- 即使可以做成幾何遮擋，仍最像兩個場景被 wipe 交換。
- 窗框會搶走主雨滴的接力責任。
- 容易與已凍結 T1 的 frame-edge occlusion 重複同一招。

## 4. 正式物件白名單

| ID | 物件 | M4 起始責任 | M5 目的地 | 禁止替換 |
|---|---|---|---|---|
| W1 | `glassPlane` | 證據所在的同一表面 | 現實濕窗 | 不建立第二片玻璃 |
| W2 | `evidenceLine` | 衰減、失去方向的證據線 | 退為不可辨認反射 | 不長成答案路徑 |
| W3 | `SydneyPlate` | M4 的次要教練泡泡 | 隨焦點退出主讀 | 不新增旁白或立繪 |
| W4 | `condensationFilm` | 玻璃上的薄水氣 | 收成主雨滴後留低強度水膜 | 不用粒子聚集 |
| W5 | `mainDroplet` | 同面形成的單一水滴 | M5 微距接力物 | 不 clone、不換 hero asset |
| W6 | `windowFrame` | 後方已存在、不可辨認 | 真實窗框線 | 不作 wipe 主角 |
| W7 | `streetWorld` | 從 frame 1 存在但失焦 | 男主側的真實濕街 | 不換 screenshot／scene |
| W8 | `streetReflection` | 低強度來源反射 | 街燈在濕地面的反射 | 不變資料線 |
| W9 | `rainLayer` | 物理時間中的普通雨 | 持續向下 | 不因回看倒流 |
| W10 | `realLights` | 有來源但不可辨認 | 一組街燈／車燈 | 不加無來源 glow |

白名單外的星塵、粒子雲、女性剪影、傘、森林、海、星球、資料隧道、愛心、成功符號與額外 UI 一律禁止。

## 5. A 方案的六個閱讀 gate

### T4‑G0｜證據停止

- W1、W7 從第一幀同時存在。
- W2 已失去連續方向；不可指向霧後答案。
- W3 可讀但只屬次要平台。
- W7 只能形成無法辨認的亮暗來源，不得先看出街景。

### T4‑G1｜局部凝結

- W4 在同一表面局部收縮。
- W5 從連續水膜中成形，不是多顆粒子飛來組裝。
- 不出現魔法聚合聲、glow 或吸附動畫。

### T4‑G2｜水滴受重力

- W5 開始持續向下；攝影機微距跟隨。
- W3 與 W2 退為次要，不靠 crossfade 消失。
- 玻璃後方仍不可完整閱讀，但真實光源開始提供折射差。

### T4‑G3｜背景解析

- 同一 W7 只透過 focus、roughness、transmission、曝光與相對攝影機距離取得輪廓。
- 不能在這裡建立或替換第二個街景 DOM／texture／screenshot。
- 第一個辨認應是「這是一扇濕窗」，不是「這是某個浪漫地點」。

### T4‑G4｜窗框與街景成立

- W6、W8、W10 依序取得足夠對比。
- 普通小雨、濕街與一個真實暖光來源成立。
- 不出現遠方女性、撐傘者或故事結果。

### T4‑G5｜M5 穩定閱讀平台

- 同一主雨滴仍在玻璃上並繼續下落。
- W7 已可讀為男主側現實空間。
- M4 的銀灰證據線不再是主讀，但可作為低強度表面記憶。
- 平台必須能承接後續 M5 的雨景，而非提前進入 M6 關係路徑。

Revision 1 proof 使用 0／32／60／92／124／152／160 作為稽核畫格；這些 frame window 是證據參數，不是最終秒數。

## 6. 桌面與手機分開導演

### Desktop

- 可使用小幅 X／Z 位移與 Y 軸角度，讓觀眾感到貼近玻璃再慢慢拉開。
- 街景可以提供較寬的左右來源反射，但只能有一個主雨滴。
- 窗框不得掃滿畫面形成 wipe。

### Mobile 9:16

- 以深度與垂直跟隨為主，橫移接近零。
- 只保留一顆主雨滴與一條主要窗框線。
- 街景以垂直層次解析；不把桌面街景縮小成 panorama。
- M5 平台仍需 edge-to-edge，不塞入桌面 debug 牆或雙平面。

## 7. 回看與不可逆物理

T4 不沿用 T1／T7 的 audience-state 對稱契約。

- Frame 0→160：攝影機由 M4 走到 M5。
- Frame 161→320：攝影機狀態由 M5 返回 M4 的觀看位置。
- 物理時間始終以 actual frame 0→320 前進。
- W5 的 `dropY` 必須單調不減；W9 的雨線也持續向下。
- 因此對稱 camera gate 不要求像素一致，也禁止宣稱 SSIM／bit-identical。

正確敘事是：

> 視角可以回看，時間沒有倒轉。

Reviewer 的逐格後退與 scrub 只是歷史畫格稽核工具，不是網站正式播放時的物理規則。

## 8. Reduced-motion

Reduced-motion 不另做兩張 screenshot dissolve：

1. 保留 W1 與 W7 同時存在。
2. W4 以短距離形變收成 W5。
3. W5 仍有小幅、持續向下的物理位移。
4. 以較短的焦點／曝光階梯完成 G3→G5。
5. 手機仍只正視一個表面。
6. 不刪除主雨滴、窗框來源或真實街景目的地。

## 9. 正式通過門檻

1. 移除 debug 後，G0 能被讀成同一片玻璃上的證據邊界，不是黑場。
2. W7 從第一幀存在，且全程只有一個 instance；沒有 screenshot replacement、第二 scene 或 crossfade。
3. W4→W5 是連續水膜收成單一水滴，不是粒子聚集。
4. G3 的街景辨認來自光學／攝影機參數，而非新畫面進場。
5. 桌面與手機都能從 G0 追蹤同一 W5 到 G5。
6. 回看段 `dropY` 單調不減；雨滴沒有逆重力回升。
7. M5 只含男主側普通雨景，不偷渡女生、傘或宏大象徵。
8. B 的 portal 感與 C 的 wipe 感不得回流 A。
9. Reduced-motion 保留同面來源、主雨滴與真實街景目的地。
10. T4 終點停在 M5，不提前把街燈反射抽象成 M6／M7 關係路徑。

## 10. Revision 1 正式證據

- Desktop 1920×1080 Motion Proof：321 frames、12 fps、26.75 秒。
- Mobile 1080×1920 Motion Proof：321 frames、12 fps、26.75 秒。
- Desktop／Mobile contact sheets。
- Same-surface evidence：G0／G3／G5 的同一玻璃與同一 W7。
- Droplet physics evidence：actual frame 0／80／160／240／320。
- A／B／C throwaway comparison。
- Reduced-motion strip。
- 本機互動 reviewer：播放、scrub、逐格與 gate 跳轉。

## 11. 本輪凍結與授權邊界

Revision 1 目前是導演候選，不得自行宣稱通過或凍結。

若獲導演拍板，建議凍結：

- A 為唯一正式 T4 結構；B／C 淘汰。
- W1～W10 identity、單一目的地與禁止替換規則。
- G0→G5 的理解順序。
- 同面 street-from-frame-1 契約。
- 單一主雨滴與物理時間不可逆。
- 桌面／手機各自構圖與 reduced-motion 來源。

本輪不凍結：

- 最終秒數、scroll 距離、easing、焦段。
- roughness、IOR、transmission、water thickness、fog、DOF 與曝光數值。
- 最終雨滴 shader、雨痕生成、聲音與混音。
- 最終 M5 場景資產與 WebGL 效能預算。

本輪未授權：

- T4 lookdev。
- T6 Greybox、完整 animatic、舊 P0／P1。
- runtime、`marketing-site/`、build、test、commit、push、deploy。

## 正式請審結論

> 建議拍板 A｜Same-surface focus pull。它讓 M4 與 M5 真正共享同一塊玻璃；未知沒有被藏成答案，雨滴沒有被神化，現實世界也不是片尾突然貼上的第二張畫面。
