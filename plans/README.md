# VibeSync 動效專業化計畫（2026-08-17 審計產出）

錨定 commit `7f150ead`。來源：improve-animations 四路審計（目的與頻率／曲線與 token／物理感與可中斷性／效能與無障礙），所有發現均經原碼複核。**執行前若 HEAD 已遠離錨點，先對照各計畫的 current 片段，有漂移就 STOP 回報。**

## 計畫總表

| # | 標題 | 嚴重度 | 狀態 |
|---|------|--------|------|
| 001 | 底部 tab fade-through（保狀態）＋TickerMode | HIGH | TODO |
| 002 | 按壓回饋統一＋GradientButton 死碼清除 | HIGH | TODO |
| 003 | 無限循環動畫 reduced-motion 閘門 | HIGH | TODO |
| 004 | Sydney 姿勢降頻＋crossfade | MEDIUM | TODO |
| 005 | 分析結果回覆區進場（payoff 時刻） | HIGH | TODO |
| 006 | 對象卡 container transform（引入 animations 套件） | HIGH | TODO |
| 007 | /paywall modal 轉場 | MEDIUM | TODO |
| 008 | 載入→內容 crossfade ×2 | MEDIUM | TODO |
| 009 | 紀錄 sheet → 詳情 SharedAxis | MEDIUM | TODO |
| 010 | 分析主鈕進場壓進預算 | MEDIUM | TODO |
| 011 | 圖表揭示 chartReveal token | MEDIUM | TODO |
| 012 | 程式捲動 AppMotion.scroll（12 處） | MEDIUM | TODO |
| 013 | showAppSheet() 統一 20 個 bottom sheet | MEDIUM | TODO |
| 014 | 抽卡儀式效能重構 | HIGH(perf) | TODO |
| 015 | 首頁效能小刀三處 | MEDIUM(perf) | TODO |
| 016 | token 採用率總清掃 | LOW | TODO |

## 執行順序（Eric 拍板：全做、照批次）

**批次一（手感差最多）**：002 → 003 → 001 → 004
**批次二（產品時刻與導航）**：005 → 006 → 007 → 008 → 009
**批次三（收斂與效能）**：010 → 011 → 012 → 013 → 014 → 015 → 016

## 依賴關係

- 001 與 004 都動 `main_shell.dart`：**先 001 後 004**。
- 002 新增 `AppMotion.pressDown/pressUp`；016-C 的 `partner_mindmap_card_list` 替換引用它——**002 先於 016**。
- 006 引入 `animations` 套件；009 依賴它——**006 先於 009**。
- 013 新增 `AppMotion.drawer`；011/012 各自新增 token——都改 `app_motion.dart`，同批次內循序做避免衝突。
- 每個計畫一個（或計畫內註明的多個）獨立 commit，繁中訊息；照 VibeSync 標準流程驗證後出貨。

## 通用守則

- 只動計畫列出的檔案；不順手重構。
- 所有新 duration/curve 一律進 `lib/core/theme/app_motion.dart`，不留裸數字。
- 每批做完 `flutter analyze`＋`flutter test` 全綠再進下一批。
- feel check 需要真機的項目（001/005/006/013/014/015）留給 Eric 的 TestFlight 驗收清單。
