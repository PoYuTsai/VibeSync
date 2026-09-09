# VibeSync 電影式官網｜D-T1-GREYBOX-ALIGNMENT-01 Revision 1.1

更新日期：2026-08-24

版本：Revision 1.1 APPROVED／FROZEN

狀態：已獲 Eric 最終導演拍板並正式凍結；不需要 Revision 1.2。

基準：`2026-08-24-vibesync-t1-greybox-alignment.md` Revision 1，以及導演的 Revision 1 窄幅補丁裁決。

## 1. 本輪沒有重開的內容

- A｜Frame-edge occlusion 是唯一主推薦；B／C 維持淘汰。
- P2 是 P1 的附著近側邊；P1～P12 stable identity、same-DOM、無 clone、無 screenshot replacement。
- 桌面與手機使用不同 camera 軸；手機以深度為主。
- P11 是較強主路徑，P12 是更弱的合理可能，不宣稱答案。
- Forward／reverse 共用同一個 audience state；reduced-motion 保留幾何接力。
- D-M1-01 精確文字、M2 證據倫理及 M7／M8／T7 凍結內容。

## 2. Revision 1.1 唯一兩項修正

### 2.1 Mobile G3｜遮擋退出與同物件重現重疊

Revision 1 的 mobile exit window 落後於 P2 遮擋退出，造成 P2 已離開後仍有約八至十幀空暗場。

Revision 1.1 只提前 mobile 的 recovery window；P2 的來源、方向與 occluder pulse 不變：

- P2 邊界仍在 camera 前移動時，P3～P10 已開始由後方重新可見。
- Frame 80 仍是最大幾何遮擋；Frame 92 已能辨認原聊天；Frame 96 與 100 持續展開。
- 沒有 crossfade、第二個聊天 shell、背景 screenshot 或新的 transition layer。
- Desktop exit curve 保留 Revision 1 路徑。

Proof 參數只屬 Greybox，不是最終 timing：mobile exit range 由 `.51–.70` 調整為 `.47–.64`。

### 2.2 G4｜P7 → P8 → P9 三段 focus window

Revision 1 的 P7、P8、P9 共用 `settle = range(p, .76, 1)`；Revision 1.1 已拆成三段重疊但可辨認的閱讀節拍：

1. P7 `週五`：Frame 112 左右先取得尺寸、對比與短暫 focus；P8／P9 留在原句或低權重。
2. P8 `突然空一整天`：Frame 126 左右成為唯一主焦點；P7 留作時間錨，P9 尚未主讀。
3. P9 `出去走走`：Frame 144 左右取得主焦點；到 G5 持續為第一閱讀層，P7／P8 退為脈絡錨。

P11／P12 改至 P9 focus 後半才開始完整顯現；caption 更晚出現。三者沒有重新打字，也沒有離開原字串生成第二份電影文字。

## 3. Reduced-motion 同步

Reduced-motion 沿用同一 A 結構，但縮短位移與取消長距離 Z 運動。Revision 1.1 同樣拆出：

> 普通聊天 → 短距離幾何遮擋 → 同物件重現 → 週五 → 突然空一整天 → 出去走走 → 弱可能線

它不是 M1／M2 screenshot crossfade，也沒有省略 P2、P7、P8、P9、P11 或 P12。

## 4. 正式證據

- Desktop／Mobile Motion Proof：321 frames、12 fps、26.75 秒，G0→G5→G0。
- Desktop／Mobile Contact Sheet：Frame `0／40／80／96／112／126／144／160`。
- Mobile G3 continuity：Frame `80／92／100`。
- Same-DOM evidence：P1～P12 的既有結構證據機械式重輸出。
- Reduced-motion strip：Frame `0／64／96／112／126／144／160`，桌面與手機各一列。
- Reviewer HTML：可 scrub、逐格、切換 viewport，G4a／G4b／G4c 可直接跳轉。

## 5. Revision 1.1 驗收門檻

1. Mobile P2 邊界離開時，至少一部分原 AppBar、泡泡或文字平面已可辨認；不得再出現持續空暗場。
2. P7、P8、P9 具有人眼可辨識的先後主焦點，而不是一起變強。
3. G5 第一閱讀層為 `出去走走`；P7／P8 只保留脈絡。
4. P11／P12 不早於 P9 後半搶讀；P12 仍弱於 P11。
5. Reduced-motion 仍有相同三段閱讀順序。
6. 最大遮擋沒有被延長成無方向黑幕；前後畫格仍可追蹤 P2 的移動來源。

## 6. QA 結論

- Renderer 通過 `node --check`。
- 兩支 MP4 metadata 均為預期值。
- Audience viewport 六組正反向對稱抽查全數 `SSIM > 0.996`；正式措辭仍是「對稱點有效一致」，不宣稱完整畫面 bit-identical。
- Contact sheets、Mobile G3 evidence、same-DOM 與 reduced-motion strip 已實際開啟檢視。

## 7. 正式凍結與治理

Revision 1.1 已正式通過並凍結：A｜Frame-edge occlusion、P1／P2 父子關係、P1～P12 stable identity、same-DOM、mobile 深度優先遮擋、遮擋退出與原聊天重現的重疊、P7→P8→P9 焦點順序、P9 的 G5 主讀、P11／P12 晚 reveal 與強弱層級、正反向同一 audience state、reduced-motion 的同一幾何來源與閱讀順序。

精確 frame window、`.47–.64` 等 proof 參數、最終秒數／scroll、easing、焦段、P2 材質、P7／P8／P9 最終字級差、DOF／motion blur／fog、P11／P12 曲線控制點與聲音不凍結；但不得反向破壞上述正式契約。

本次拍板不自動解鎖下一階段，以下繼續暫停：

- T1 lookdev
- T4／T6 Greybox
- 完整 animatic
- 舊 P0／P1
- runtime／`marketing-site/`
- implementation planning
- build／test／commit／push／deploy

M1／M2、M7／M8、T7 Greybox／Lookdev 均維持既有凍結；不得因後續參數調整重開 A／B／C、接力物或證據倫理。
