# AI 實戰練習室 v2：角色狀態升溫引擎（Phase 1）

## 背景

2026-07-07 dogfood 發現：「輕鬆」難度下，用提示產生的回覆仍可能被扣分。根因不是單一 prompt 壞掉，而是舊 beginner 升溫判定把最後一句 user 訊息硬分成 `event / personal / flirt`。在 `building_familiarity` 階段，`personal` 先天扣熱度，`ordinary + minor` 正向回合又歸零，導致自然聊天或接梗常被錯殺。

## 決策

Phase 1 取消「話題類型 = 分數」的核心假設，改成「互動結果 = 分數」：

- 使用者有沒有接住她的情緒、玩笑、上下文？
- 使用者是否防禦、過度解釋、討好、硬推？
- 她是否丟出一致性測試，而使用者是接住還是失手？
- 是否踩到界線或明顯越級？

UI 仍沿用現有 heat / familiarity / stage，避免 client 重建與 DB migration。這階段只改 server-side prompt、分類 schema、delta mapping、hint/debrief 教學語言。

## 新分類契約

`TurnClassification` 改為：

- `connection`: `caught | neutral | missed | defensive | overstepped`
- `impact`: `minor | medium | strong`
- `testHandling`: `none | passed | failed`
- `boundary`: `safe | pushy | overstep`
- `hintAlignment`: `none | aligned | diverged`

`event / personal / flirt / quality / overstep` 不再是主分類契約。

## 小測試設計

使用者可見文案稱「小測試 / 一致性測試 / 測你穩不穩」，不使用黑話。各 persona 都可能丟，但頻率與形狀不同：

- `teasing_humor`: 高，吐槽、反問、評分、輕鬆挑釁。
- `cool_rational`: 高，反問、穩定性觀察、保留式測試。
- `clear_boundaries`: 中，界線、步調、安全感測試。
- `playful_extrovert`: 中，玩笑節奏與自信測試。
- `slow_worker`: 低，柔和、慢熱、低壓觀察。

難度只調整強度：輕鬆少量且給台階；一般偶爾；挑戰更常、更尖銳。

## 非目標

- 不新增 DB mood / innerThought 長期狀態。
- 不改 Flutter UI 或 client schema。
- 不碰 analyze-chat、OCR、訂閱 quota。
- 不把「小測試」做成固定劇本；只提供 persona 行為邊界與判分教學。
