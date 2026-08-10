# VibeSync 設計憲法（DESIGN.md）

> 單一事實來源。改任何 presentation 程式碼前先讀這份；`lib/shared/widgets/brand/brand_kit.dart` 的註解只是指標，內容以這裡為準。
> 來源：2026-08-10 由 brand_kit 註解憲法搬出，並併入 anti-AI-slop 稽核（impeccable.style 清單）的拍板結果。

## 1. 品牌色彩身分（不動）

- **暗紫底＋橘色重點**。這是色彩身分，去 slop 動作不得改變它。
- 背景：`brandInk #150C24 → brandSurface #1F1330 → brandSurface2 #2A1840` 垂直漸層，stops `0 / .58 / 1`。
- 重點色：`ctaStart #FF6A2B → ctaEnd`（brandFlame/brandFlameDark）橘——CTA、焦點、icon badge。
- coach tone（Analyze Chat / Opener 洞察層）：紫 `coachAccent #9D78F5` 只負責選取與資訊；主要動作仍是橘。
- 粉 `coachRecommendation #FF5DA8` 保留給 AI 推薦。

## 2. 卡片與表面

- 卡片：brandSurface 系漸層 @ ~.9、圓角 22–24、`white@.10` 邊框、**黑色柔陰影**。
- 陰影一律中性（黑色系）表達高程；彩色發光只允許出現在「刻意保留」清單（§7）。
- 同款卡片不得當頁面結構平鋪堆疊——區塊分層優先用字級、間距、分隔線（S9，待修）。

## 3. 字級

現行 `AppTypography`：28 / 22 / 18 / 16 / 14 / 12。
已知債（S4/S5）：級距多段 <1.25、全庫散落 20 種 fontSize。**目標尺度（B5 批，未動工）：12 / 15 / 19 / 24 / 30 / 38**，動工時必須連同用法一起改，不得只改 token。
底線：內文 ≥12px（繁中筆劃密、10px 實機吃力；S6 待修）；圖表空間不夠時減刻度，不縮字。

## 4. 圓角

憲法值：**22–24（卡片）／18（次級容器）／999（pill）**。
已知債（S7）：全庫實際 14 種值、199 處出格（12/14/8/16 主導）。收斂時保留必要例外並在此登記。

## 5. 間距

目標尺度：**4 / 8 / 16 / 32**。節奏規則：群組內收緊、群組間放寬、標題上方留白 > 下方。
已知債（S8）：現況 4–16 等頻出現、無節奏，與 B5–B7 綁同一批做。

## 6. 動效

單一來源 `AppMotion`：press 120ms / enter 200ms / state 240ms / celebrate 320ms；easeOut `Cubic(.23,1,.32,1)`；easeOutBack 只准 celebrate 檔。原則：一個被設計過的瞬間，而非散落的效果。

## 7. 刻意保留（登記制——在此列出的「slop 樣式」是品牌決策，稽核工具再標也不拆）

| 項目 | 位置 | 理由 |
|---|---|---|
| 紫色系主色盤 | `primary #6B4EE6`、coach 系 | 已上線色彩身分（Tier 3） |
| LiquidBeam 入口光暈 | `practice_room_entry_card.dart`（練習室入口＋建立對象卡，`LiquidBeamEntryPreset`） | Eric 2026-08-09 逐格拍板的品牌記憶點 |
| 首頁頭像 flow | 首頁對象卡頭像流光 | 同上，角速度已對齊 beam |
| 抽卡儀式 glow | `practice_collection_screen.dart` 抽卡/翻牌 `brandFlame` 呼吸光暈 | 儀式性場景，慶祝時刻 |
| shimmer 掃光 | `splash_screen.dart`、`ebook_shelf_section.dart`（白色掃光，非漸層文字） | 品牌 wordmark 儀式；splash 整頁另案（階段 C 最後） |
| 邊緣淡出遮罩 | `home_coach_presence.dart` ShaderMask（dstIn） | 功能性遮罩，稽核誤報 |
| OCR 確認格單發閃光 | `screenshot_recognition_dialog.dart`（ctaStart 脈衝） | 2026-08-09 拍板的注意力提示，功能性 |

規則：想把新的彩色光暈/漸層加進產品＝先加進這張表並說明理由，否則視為 slop。

## 8. 對比門檻

內文 ≥4.5:1、大字（≥18.66px bold 或 24px）≥3:1。
已驗合格：`textSecondary` on bg 8.93、`brandFlame` on `brandInk` 6.62、`glassTextSecondary` 5.65、`coachAccent` on `coachSurface` 5.49。
**待拍板（決策 1）**：主 CTA 白字 on 橘漸層 2.86/3.55——等 Eric 看過深墨字對照 PNG 再定；若拍板保留白字，移入 §7 登記。

## 9. 已知債清單（去 slop 批次進度）

| 批 | 項目 | 狀態 |
|---|---|---|
| B1 | CTA 字色對比（S10） | 等決策 1 |
| B2 | 4px 橘豎條收窄（S2） | 本批 |
| B3 | 彩色陰影改中性（S1，排除 §7） | 本批 |
| B4 | Collection 漸層文字改實色（S3） | 本批 |
| B5–B8 | 字級/小字/圓角/間距尺度重整（S4–S8） | 待排，必須綁一批 |
| B9 | paywall 等卡片堆疊改分層（S9） | 最後 |
| C | 7 個未遷移 screen 上 Brand Kit | 一次一 screen |
| — | S11 自訂繁中字體 | 拍板暫緩（App 體積），上架穩定後再議 |
| — | S12 放射光暈減密度 | 待排；§7 保留項除外 |

## 10. 驗證

`flutter analyze` → 相關 `flutter test` → `test/visual_proof/` 出改前改後 PNG 對照 → 對比值重算 → 真機。
