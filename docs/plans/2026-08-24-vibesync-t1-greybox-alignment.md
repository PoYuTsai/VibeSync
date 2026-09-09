# VibeSync 電影式官網｜D-T1-GREYBOX-ALIGNMENT-01

> 歷史基準：本文件記錄 Revision 1。導演已裁決 A 的核心結構通過、僅需 Motion Patch；最新候選以 `2026-08-24-vibesync-t1-greybox-alignment-revision1-1.md` 為準。Revision 1 本身未獲凍結。

更新日期：2026-08-24

版本：Revision 1 Director Candidate

狀態：已依 Eric「授權繼續往下推進」完成桌面／手機 Greybox、三方案 throwaway prototype、正反向 Motion Proof 與靜態證據；尚待導演審核，未凍結。

上位基準：

- `docs/plans/2026-08-23-vibesync-cinematic-site-yuya-calibrated-bible.md` 的 M1、M2 與 T1。
- `D-M1-01` 真人聊天定稿。
- 已凍結的 `D-T7-LOOKDEV-01 Revision 1.1` 只提供後段表面品質基準；不把 T7 材質偷渡回 M1。

## 0. 本輪唯一問題

> 一段第一次看完全普通的聊天，能否只靠**同一塊聊天平面的近側邊框**遮住鏡頭，讓同一批文字取得空間與第二次閱讀，而不變成泡泡特效、文字 MV、產品 dashboard 或硬切？

本輪不是 M1／M2 lookdev，也不是完整 animatic。只驗證 T1 的接力物、攝影機、物件 identity、正反向與 reduced-motion 語意。

## 1. 三方案原型與唯一主推薦

Throwaway prototype：`docs/handover-screenshots/t1-greybox-alignment/vibesync-t1-greybox-prototype.html`

可用 `?variant=A`、`?variant=B`、`?variant=C` 切換，左右方向鍵亦可切換；桌面／手機與 timeline 共用同一份狀態。

### A｜Frame-edge occlusion｜正式候選

- 整組聊天先側傾／靠近；單顆泡泡不先飛散。
- 桌面以聊天平面的近側直邊擦過鏡頭；手機以同一平面的近側下緣／側緣完成深度優先遮擋。
- 幾何遮擋覆蓋狀態切換；遮擋離開後，P3～P10 仍是同一批 DOM 物件，只改 transform、surface emphasis 與閱讀焦點。
- 最符合已拍板的「側傾、遮擋、展開」，也是唯一進正式 Motion Proof 的方案。

### B｜Bottom-lip reveal｜保留為反例

- 手機上自然，但桌面容易讀成 bottom sheet／tray 被拉起。
- 觀看語法偏 UI 導覽，而不是重新閱讀同一段對話。
- 不進正式候選。

### C｜Date-baseline hinge｜保留為反例

- 以「週三」日期基線作折頁鉸鏈，概念鮮明但會讓日期本身變成導演機關。
- 容易把普通聊天拍成文字設計展示，提前要求觀眾注意「時間有秘密」。
- 不進正式候選。

正式主推薦只有 A；B、C 不並行送往 production。

## 2. 凍結輸入，不得藉 Greybox 改寫

### M1 精確文字

她，同一訊息群組：

> 週五那個案子臨時取消了，突然空一整天

> 想說看要不要出去走走

他：

> 週五好像會下雨欸，出門記得帶傘

她：

> 好哈哈

### M1 導演邊界

- 第一次觀看不得暗示她失望、男主答錯、這是明確邀請或錯過已經發生。
- 沒有 Sydney、Coach 紫、行動橘、雨聲、悲傷音樂、分析標籤或產品資料。
- 聊天文字依泡泡自然換行；不人工排詩。

### M2 導演邊界

- 第二次閱讀來自回覆方向與觀看距離，不來自文法課或新增旁白。
- 「週五」「突然空一整天」「出去走走」必須源自原訊息，不重打一份電影文字。
- 弱銀灰可能線只代表另一種合理讀法，不標 `你們`、不畫愛心、不比主路徑亮。

## 3. T1 物件白名單

| ID | 原始物件 | Forward 中的責任 | Reverse 中的責任 |
| --- | --- | --- | --- |
| P1 | `chatPlane` | 整組聊天唯一父平面；先動、靠近、遮擋後退為 M2 背景 | 回到 M1 正視聊天，不重新生成 |
| P2 | `nearEdge` | 附著於 P1 的近側邊框，成為 camera occluder | 沿同一路徑離開，不能變成獨立 wipe layer |
| P3 | `wedSeparator` | M1 日期證據；M2 後退 | 回到原日期位置 |
| P4 | 第一則 incoming bubble | 保留原 context | 回到原泡泡位置 |
| P5 | 第二則 incoming bubble | 保留可能活動語境 | 回到原泡泡位置 |
| P6 | 男主 outgoing bubble | 證明回覆方向落在天氣／她出門 | 回到原泡泡位置 |
| P7 | 原字串內 `週五` span | 取得時間錨尺度與焦點 | 收回原字串，不做新文字替換 |
| P8 | 原字串內 `突然空一整天` span | 取得第二焦點 | 收回原字串 |
| P9 | 原字串內 `出去走走` span | 取得第三焦點與共同活動的合理可能 | 收回原字串 |
| P10 | `好哈哈` bubble | 保留對話如何普通結束 | 回到原泡泡位置；不增加情緒 |
| P11 | 主閱讀路徑 | 男主實際採用的「她出門／天氣」方向 | 退回不可見，不倒播成答案取消 |
| P12 | 弱可能路徑 | 多延伸一段的另一種合理讀法 | 退回不可見；不變亮、不被證實 |

除 P1～P12 外，不得新增漂浮單字、愛心、粒子、玻璃碎片、AI scan、情緒分數、女生剪影或 M2 專用重打文案。

## 4. 六個驗收 Gate

Motion Proof 為 12 fps、321 frames、26.75 秒；161 個 forward frames＋160 個 reverse frames。這是逐格證據節奏，不是最終網站秒數。

| Gate | 代表 frame | Audience viewport 必須看見 | 失敗解讀 |
| --- | ---: | --- | --- |
| T1-G0 | 0 | 完全正常的 M1 聊天；P11／P12 不可見 | 一進站就像分析案例 |
| T1-G1 | 40 | 整塊聊天平面先有極小側傾／靠近；泡泡仍是群組 | 單顆泡泡開始表演 |
| T1-G2 | 80 | P2 幾何邊框實際覆蓋 camera；不是 opacity fade | 黑場、crossfade、另一張 screenshot |
| T1-G3 | 96 | 遮擋離開；P3～P10 是同一批物件，開始取得深度 | 泡泡碎裂／重新生成 |
| T1-G4 | 124 | 原文字依序取得焦點；一次只需讀一個 evidence | 三張並排 evidence card |
| T1-G5 | 160 | M2 穩定閱讀平台；P11 主路徑與更弱 P12 同時存在 | 弱可能線被拍成正解 |

Gate 之間是同一條連續曲線，不是六次 scroll snap。

## 5. Camera 與遮擋契約

### 桌面

- M1 聊天約佔 audience viewport 38～42%，略偏右；左側保留暗紫負空間。
- P1 先小幅 rotateY／靠近，近側直邊 P2 才取得足夠畫面面積成為遮擋。
- 遮擋期間允許在 P2 背後切換 P1 surface 與子物件閱讀狀態；不得在未遮住鏡頭時偷換 DOM 或 screenshot。
- 遮擋後 camera 只做小幅側移；不飛隧道、不 orbit。

### 手機 9:16

- M1 edge-to-edge，不套另一支手機框。
- 以 P1 的近側下緣／側緣完成同一種幾何遮擋；深度大於橫移。
- M2 evidence 前後堆疊；不把桌面左右分岔縮進直式畫面。

桌面與手機可以使用不同邊緣方向，但都必須證明 P2 附著於 P1，而不是另開一個全螢幕 transition div。

## 6. 同物件與反向契約

- 互動原型中的 P1～P12 是固定 DOM；`window.setT1Frame(frame)` 只改 transform、surface emphasis、focus 與 P11／P12 visibility。
- 沒有 screenshot replacement、innerHTML replacement、泡泡 clone 或純 fade 換場。
- frame `n` 與 frame `320-n` 由同一個 `stateFrame()` 取得相同 audience state；方向與 frame label 可以不同，因此不宣稱含 debug HUD 的整張影片 bit-identical。
- 反向回到 M1 時，P7／P8／P9 收回原字串，P11／P12 退場；不讓文字碎片「拼回」、不暗示時間倒轉。

## 7. Reduced motion

Reduced-motion strip 保留四個語意狀態：

1. M1 normal chat。
2. P1 短距離側傾＋P2 幾何遮擋。
3. 同物件取得有限 2D 錯位與焦點。
4. M2 正視閱讀平台＋P11／P12。

它不使用長距離 translateZ 或大幅視差，但不能刪除邊框接力、第二次閱讀或弱可能線。Reduced motion 不是 M1 直接 crossfade 成 M2 靜態圖。

## 8. 聲音責任（本輪只寫契約，不製作）

- M1 只允許室內底噪與普通訊息落定觸感。
- P1 開始靠近後，原訊息觸感可延長為短玻璃摩擦音。
- P2 遮擋前不能預告「大轉場」；無 whoosh、AI scan 或低頻撞擊。
- M2 空間低頻可以 pre-lap 一點，但無配樂高潮。

## 9. 正式候選證據

- 可切換三方案的 throwaway prototype：`docs/handover-screenshots/t1-greybox-alignment/vibesync-t1-greybox-prototype.html`
- 可 scrub 審核頁：`docs/handover-screenshots/t1-greybox-alignment/vibesync-t1-greybox-motion-proof.html`
- Desktop Motion Proof：`vibesync-t1-greybox-motion-proof-desktop.mp4`
- Mobile Motion Proof：`vibesync-t1-greybox-motion-proof-mobile-9x16.mp4`
- Desktop contact sheet：`vibesync-t1-greybox-desktop-contact-sheet.png`
- Mobile contact sheet：`vibesync-t1-greybox-mobile-9x16-contact-sheet.png`
- P2 camera occlusion：`vibesync-t1-greybox-occlusion-evidence.png`
- P1～P12 same DOM：`vibesync-t1-greybox-same-dom-evidence.png`
- Reduced motion：`vibesync-t1-greybox-reduced-motion-strip.png`
- 可重現 renderer：`render_t1_greybox_proof.mjs`

## 10. 導演通過門檻

T1 要取得 Transition Greybox 評分 2，必須同時成立：

1. 不看 debug label，T1-G0 仍只像普通聊天。
2. T1-G1 是整組聊天先動，不是泡泡特效。
3. T1-G2 的遮擋可追溯到 P1 的 P2 邊框，沒有純 fade／硬切。
4. T1-G3～G5 可逐格追蹤同一批 P3～P10；沒有文字 clone 或 screenshot replacement。
5. P7／P8／P9 源自原訊息，沒有重打電影文案。
6. P12 比 P11 弱，且不標答案、不暗示女生真實意圖。
7. 桌面與手機各自成立；手機不是桌面縮小。
8. 反向回位不變成碎片拼回或時間倒帶。
9. Reduced motion 仍保留完整 T1 語意。
10. 沒有 Sydney、雨、宇宙、產品數值、Coach 紫或行動橘提前進場。

### 直接退回

- 泡泡四散、碎玻璃、所有文字一起浮成 3D 字。
- 遮擋只是黑色 overlay／crossfade，與 P1 邊框無幾何關係。
- 「週五」「出去走走」被另打成巨型廣告字，原訊息反而消失。
- 弱路徑比主路徑更亮，或出現 `我們／你們`、愛心、女生剪影。
- 手機出現橫向大分岔、過度視差或不可讀中文。

## 11. 本輪不裁決

- 最終秒數、camera easing、scroll 距離與阻尼。
- M1／M2 最終材質、shader、fog、DOF、motion blur 與曝光。
- M2 文字的最終 display 字體、尺度與精確構圖。
- T2、M3 或 Sydney 進場。
- 聲音、配樂、混音。
- Three.js／WebGL／DOM 的 production 分工與效能預算。

Greybox 中的深紫與銀灰只為層級辨識，不是 T1 lookdev 凍結。

## 12. 治理

- `D-T1-GREYBOX-ALIGNMENT-01 Revision 1` 現為導演候選，尚未凍結。
- M8 Revision 3.1、M7 Revision 1.1、T7 Greybox Revision 1.1 與 T7 Lookdev Revision 1.1 繼續凍結。
- 在 T1 通過前，不啟動 T1 lookdev、T4／T6 Greybox、完整 animatic 或其餘轉場。
- 舊 P0／P1、runtime、`marketing-site/` 與 implementation planning 繼續暫停。
- 不 build、test、commit、push 或 deploy。

本輪通過只凍結 T1 的接力物、物件 identity、G0～G5 解析順序、桌面／手機 camera 語法、正反向與 reduced-motion 契約；不會自動凍結最終材質、秒數或實作參數，也不自動授權下一階段。
