# D‑T6‑GREYBOX‑ALIGNMENT‑01｜Revision 1.1 Motion Patch Delta

更新日期：2026-08-24  
狀態：已獲 Eric／外部總導演正式通過並凍結；不需要 Revision 1.2  
上位文件：`2026-08-24-vibesync-t6-greybox-alignment.md`  
唯一正式候選：A｜Reflection-edge inheritance

## 1. 為什麼只做 1.1

Revision 1 已通過故事功能、A／B／C 選擇、Q1～Q8 單一 instance、M7‑R1 終點、camera return、physical rain 與 reduced-motion 的結構契約。導演覆核只指出一個尚未被運動畫面證明的核心：

> Q2 的局部反射邊緣，是否真的在同一位置依序成為 Q4 手機微光與 Q5 AppBar 的近邊，而不是完整反射一起變成產品線、再由一張卡片漂入。

因此 Revision 1.1 只修 G1／G2／G3／G5 的幾何與閱讀權重；不是新方案、不是 Revision 2，也不重開 M6、M7、M8、T1、T4 或 T7。

## 2. 三項窄幅補丁

### Patch A｜局部邊緣穩定

- Q2 主反射全程維持寬、破碎、低對比且可追溯到街燈。
- 只有 Q2 的一段短 material pass 逐步去飽和、縮窄並取得方向。
- 這個 material pass 沒有新的 Q ID，不是 Q9，也不是資料線或節點。
- 抵達 G5 時，非附著區的 Q2 與該短邊都退回低權重，不能壓過姓名。

### Patch B｜Q4 成為可見的幾何橋

- Q4 固定在同一個 attachment anchor。
- Q4 的方向與 Q2 局部切線一致；G2 可辨認為一段來源反光，但不能讀成手機輪廓或 UI。
- Q4 的感知權重低於完成後的 Q5，並在 G5 回退成來源證據。

### Patch C｜Q5 從共邊長出，而非漂入

- Q5 的左下 attachment point 從第 1 幀固定在 Q2／Q4 的同一 anchor。
- G3 先在局部切線角度，以 `scaleY` 從近乎 edge-on 的薄邊取得高度；不從畫外位移、不使用 opacity crossfade、不以 `scaleX` 像 ribbon 展開。
- Q5 與 Q2／Q4 共享近邊若干畫格後，才小幅轉到最終 AppBar 角度。
- Endpoint 維持非對稱裁切與右側衰減，只呈現 AppBar fragment，不形成完整圓角身分卡。
- Q6 `小安` 是唯一銳利第一閱讀層；Q7 `週三 21:59` 仍不可讀。

## 3. 同步更新 reduced-motion

Reduced-motion 使用同一 Q1～Q8、同一 attachment anchor 與同一局部 material pass：

1. 物理反射保持寬、破碎。
2. 局部短邊取得方向。
3. Q4 在同一切線上可辨認。
4. Q5 由共邊取得高度。
5. Q6 聚焦；Q7 保持失焦。

不得改成 M6 screenshot dissolve 成 M7 screenshot。

## 4. 本輪沒有重開

- A 仍是唯一候選；B／C 維持淘汰。
- Q1～Q8 identity、parent 與目的地不變。
- Q8 的物理雨勢只向前；camera return 語意不變。
- T6 終點仍是 M7‑R1，不能提前讀出時間。
- 不新增 Q9、完整手機、avatar、身分卡、節點、資料 ribbon、產品頁、Sydney、orb、作戰板或行動橘。
- 不修改 runtime、`marketing-site/`、Flutter 或產品資料。

## 5. Revision 1.1 通過門檻

1. G1 只有 attachment region 穩定；全長 Q2 仍是物理反射。
2. G2 可看見 Q4 與局部 Q2 共用方向，但仍不可讀裝置或產品。
3. G3 的 Q5 attachment point 與 Q2／Q4 近邊在同一位置；Q5 由該邊取得高度。
4. G3 沒有 opacity 換景、畫外飛入、ribbon extrusion 或 screenshot replacement。
5. G5 的全長反射退為來源證據；第一眼先讀 `小安`。
6. Q5 仍是被裁切的 AppBar fragment，不是完整身分卡。
7. Q7 在桌面與手機都不可讀。
8. Reduced-motion 保留相同來源、anchor、物件與閱讀順序。

## 6. 送審範圍

Revision 1.1 只更新並送審：

- Desktop／Mobile Motion Proof。
- Desktop／Mobile Contact Sheet。
- Real Reflection Source Evidence。
- Edge Inheritance Evidence。
- Identity Hierarchy Evidence：完整 viewport、近裁切、瞇眼層級與手機 endpoint。
- Desktop／Mobile Reduced-motion Strip。
- Prototype、renderer、QA record 與 manifest。

Revision 1 已通過的 A／B／C、return semantics 與 rain physics 不要求重審。

## 7. 治理

Revision 1.1 已獲 Eric／外部總導演正式拍板。T1／T4／T6／T7 四條高風險結構轉場至此全部完成結構驗證；依 Eric 先前授權，下一步直接開始完整 M1～M8 animatic，不再要求 Eric 手動搬運裁決。
