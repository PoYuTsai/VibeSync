# 主+副互動風格（Style Pair）設計

> 2026-06-10 拍板（Eric）。源頭：夥伴 TF 回饋「真實的人不會只有一種氣場」。
> Scope 鎖定：只做主+副風格。AI 預填 / 對話式 onboarding 進 feature queue，上線後再排。

## 需求拆解

- 表面需求：互動風格 70%/30% 權重混合。
- 真實需求：AI 產出立體感——單一風格標籤讓回覆扁平。
- 拍板：% 是假精度（LLM 對權重數字無感），改「選 2 個有排序」= 主+副。

## 資料模型（零遷移）

- `UserProfile`：`@HiveField(0) interactionStyle` 原地不動＝主風格；新增
  `@HiveField(6) InteractionStyle? secondaryStyle`。舊資料讀出 secondary=null，無需 migration。
- `PartnerStyleOverride`（typeId=13）：新增 `@HiveField(5) secondaryStyle`，兩畫面 UI 一致。
- 驗證（`.create` factory，違反丟 `ArgumentError`）：
  - 有副必有主（secondary != null ⇒ primary != null）
  - 副 != 主

## 合併語義（resolveEffectiveStyle）

- (主, 副) 視為**原子單位**：partner.primary 非 null → 整組用 partner 的 (主, 副)；否則整組用全域。
- 絕不欄位級混搭（partner 主 + 全域副）——會混出用戶沒選過的人格，違反「不替你假裝成另一個人」contract。
- `EffectiveStyle` entity 加 `secondaryStyle` 欄位。

## UI 互動（about_me_screen + partner_style_edit_screen）

`ProfileChipSection` 加「有序雙選」模式（或專用 `StylePairChipSection`，實作時取 diff 小者）。
選中 chip 標 `主`/`副` badge。副標題改「先點主風格，再點副風格（可只選主）」。

點擊狀態機（永遠可預測、不會出現非法狀態）：

| 點擊 | 行為 |
|---|---|
| 未選 chip，0 選 | 成為主 |
| 未選 chip，1 選 | 成為副 |
| 未選 chip，2 選 | 取代副（主不被路過點擊偷換） |
| 主 chip | 取消主；有副 → 副升格為主 |
| 副 chip | 取消副 |

## Prompt 層（EffectiveStylePromptBuilder）

- 只有主（含所有舊用戶）：輸出 **byte-for-byte 與現狀一致** ← 最重要回歸保險。
- 主+副：`- Preferred voice: 以穩重為主、幽默為輔；<主 prompt>。<副的點綴版 prompt>`
- 副風格新增 `_secondaryStylePrompt` 降權措辭（「點綴、不要蓋過主基調」），不重用主風格全力描述——避免 LLM 把兩風格平均掉。
- analysis 900 / coachFollowUp 500 字數預算不變（雙風格約 +40 字）。

## 測試

- factory 驗證邊界（有副無主、副=主）
- Hive round-trip：舊 binary 讀出 secondary=null
- resolve 原子合併（partner 有主 → 整組贏；無 → 整組全域）
- prompt builder：單風格輸出快照不變 + 雙風格新格式
- UI 點擊狀態機 5 條規則

## 不做（feature queue）

- 「從我的對話推斷」AI 預填按鈕（會變成獨立產品功能：Edge call、成本、隱私、失敗狀態）
- 完整對話式 onboarding（送審前不碰流程）
