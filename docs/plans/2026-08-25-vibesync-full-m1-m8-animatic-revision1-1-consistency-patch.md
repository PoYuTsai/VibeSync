# D‑FULL‑ANIMATIC‑01｜Revision 1.1 Mobile Consistency Patch

更新日期：2026-08-25  
狀態：已獲 Eric／外部總導演正式通過並凍結；不需要 Revision 1.2／2  
上位真相源：Revision 16 與其核准覆蓋、Full Animatic Revision 1.1、Revision 1.1 導演複核紀錄

## 1. 唯一任務

不改總長、文案、故事、七條轉場、M8 節奏或產品設計，只修：

1. Mobile M4 先完整讀完 Sydney，再由同一暗面邊界接手。
2. Mobile P1／K1 以真實 AppBar 顯示 `小安`，再讀最近互動時間。

## 2. Mobile M4

- M4 精確文案、Coach 平面、T3／T4 幾何與總 frames 不變。
- 文字於 frame 350 完整落定。
- Mobile 暗面由 frame 382 才開始進場；frames 350～381 提供 32 frames／約 2.67 秒完整閱讀平台。
- 暗面只在觀眾已能完整讀完後穿過既有平面；不加 glow、outline、局部高亮或新的遮擋物。
- Desktop 原時序不變。

## 3. Mobile P1／K1

- 使用既有 `identityPlane` 與真實 `PartnerDetailScreen` AppBar，不新增物件、頭像、tag 或資料卡。
- Mobile AppBar 落在頂部安全區，`小安` 為第一閱讀層。
- 既有 `最近互動／週三 21:59` 卡片延後一個短節拍取得焦點；完整 K1 payoff 窗口不縮短。
- Desktop P1、P2 signal、P2 map、K3、返回 frame 與 sent flags 不變。

## 4. 唯讀分支證據

新增從 M5 雨景 frame 490 啟動的 Mobile 證據序列：

> M5（進入前無姓名）  
> → P1／K1：小安＋最近互動  
> → P2／K2 signal  
> → P2／K2 stage／map  
> → 精確返回 M5

同一證據板仍保留 Mobile frame 1040 sent-state 返回與 Desktop 已通過流程，以防狀態保存回歸。

## 5. Reduced-motion

- 使用相同 Mobile M4 閱讀平台時序。
- Mobile P1 顯示同一 AppBar 與身分錨。
- 不增加或刪除狀態，不改 O2／O6、空框與兩次送出。

## 6. 通過門檻

1. 390 CSS px 等效觀看時，M4 兩句可完整、連續閱讀至少一次。
2. 暗面接手前已有 2.5～3 秒穩定平台。
3. Mobile P1 可同時辨識 `小安`、`最近互動`、`週三 21:59`。
4. 從 M5 啟動時，P1 不依賴前一幕姓名仍能證明同一對象。
5. 返回 M5 與返回 sent state 均不建立、取消或改寫敘事狀態。
6. Reduced-motion 使用同一語意順序。
7. Desktop 與其他已通過成果不重編碼、不回歸。

## 7. 治理

本補丁仍名為 Revision 1.1，已正式凍結；核准紀錄以 `APPROVED_RECORD_REVISION1_1.md` 為準。下一 Gate 是真人黑箱與實機 QA；完成前 P0／P1、runtime、`marketing-site/`、implementation planning、build、test、commit、push 與 deploy 仍暫停／未授權。
