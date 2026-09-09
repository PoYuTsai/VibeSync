# D‑FULL‑ANIMATIC‑01｜Revision 1.1 窄幅補丁

> **後續同版覆蓋（2026-08-25）**：`2026-08-25-vibesync-full-m1-m8-animatic-revision1-1-consistency-patch.md` 所列 Mobile M4 與 P1／K1 補丁已獲外部總導演通過。`D‑FULL‑ANIMATIC‑01 Revision 1.1` 已正式凍結，不建立 Revision 1.2／2；下一 Gate 是真人黑箱與真實 iPhone QA。

更新日期：2026-08-25  
狀態：依 Revision 1 導演裁決執行；Director Candidate，尚未凍結  
上位真相源：Revision 16、M7 Revision 1.1、M8 Revision 3.1、T1／T4／T6／T7 Revision 1.1、T7 Lookdev Revision 1.1、Full Animatic Revision 1 導演審核紀錄

## 1. 唯一任務

在不改任何凍結文字、故事、轉場結構或 M8 人物節奏的前提下，修正三件事：

1. Mobile 必要繁中在約 390 CSS px 寬度下可直接閱讀。
2. K1、K2 signal、K2 map、K3 Sydney 各有明確穩定閱讀平台。
3. 「直接看產品」先讀 K1，再讀 K2，且不觸發 K3／K4 或 sent state。

## 2. 時間重新分配

總長維持 92 秒、12 fps、1104 frames；M8 K4～K7 保持原 frames 936～1103，不縮短人物行動。

| 範圍 | Revision 1.1 | 變更 |
| --- | ---: | --- |
| M1～M4 | 0000–0431 | 不變 |
| T4／M5 | 0432–0533 | 10 秒縮為 8.5 秒；只刪重複穩定雨窗 |
| T5／M6 | 0534–0599 | 8 秒縮為 5.5 秒；內容與接力物不刪 |
| T6／M7 | 0600–0767 | 維持 14 秒，整段前移 |
| T7／M8 K1～K3 | 0768–0935 | 10 秒增為 14 秒 |
| M8 K4～K7 | 0936–1103 | 維持 14 秒不變 |

M8 A／B 內部平台：

- K1：姓名／最近互動完整落定後約 1.5～2 秒。
- K2 signal：完整 scope 約 2.5～3 秒。
- K2 map／next：約 2.5 秒。
- K3 Sydney：三句完整落定後約 5.5～6 秒，再進外部聊天。

相鄰平台可用短交疊完成同物件解析，但不得以交疊抵銷實際可讀時間。

## 3. Mobile typography gate

- 1080×1920 輸出中的必要正文使用約 42～48 raster px。
- 次要但需辨識資訊約 34～38 px。
- 只有無須閱讀的 microcopy 可維持 24～28 px。
- M1、M3、M4、M7 必要產品文字、M8 K3、M8 K4～K6 均在範圍內。
- 不修改字串；只改 font-size、line-height、bubble width、padding 與容器高度。
- `帶傘哈哈`、`出去走走？` 繼續避免詞內斷行。
- 第一則形成自然短多行；第二則自然形成兩行。
- 驗收以約 390×844／393×852 CSS viewport 的等效 100% 顯示為準，不以 1080px 原圖放大判斷。

## 4. 唯讀產品分支

`直接看產品` 的狀態序列固定為：

> 目前電影 frame／sent flags 取樣  
> → P1／K1：小安＋最近互動  
> → P2／K2：訊號、階段與作戰板  
> → 返回原 frame 與原 sent flags

禁止進入 K3 Sydney、外部聊天、輸入、兩次送出、黑場或 finale。這是唯讀檢視，不是主敘事快轉。

## 5. Reduced-motion

沿用既有狀態數與內容，只同步：

- 新 Mobile typography。
- 新 M8 A／B frame 座標與停留時間。
- P1→P2 唯讀證據。

不得新增 keyframe、刪除 O2／O6、刪除空框或合併兩次送出。

## 6. Revision 1.1 通過門檻

1. 約 390 CSS px 寬度下，所有必要 Mobile 文字不縮放即可讀。
2. 第二則自然兩行；第一則不再是一條微小長句。
3. `帶傘哈哈` 與 `出去走走？` 不拆詞。
4. K3 Sydney 三句可按一般繁中閱讀速度完整讀完一次。
5. K2 scope、階段與下一步各有可辨認節拍。
6. 產品 payoff 的清晰度與停頓明顯高於前段抽象世界。
7. 唯讀分支完整呈現 P1→P2，且精確恢復原 frame／sent flags。
8. M8 K4～K7、行動橘、短黑與 finale 完全不因補時被壓縮。
9. Desktop 不因 Mobile 修正而被反向放大或改構圖。
10. 無人工分數、女生反應、產品外功能或新物件。

## 7. 治理

Revision 1.1 是唯一允許的下一候選。通過前不凍結 Full Animatic，不啟動真人黑箱、手機實機 QA、P0／P1、runtime、`marketing-site/`、implementation planning、build、test、commit、push 或 deploy。
