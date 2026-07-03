# F5 文案總審改字清單（2026-07-03）

> 7 路唯讀 fan-out（首頁/分析/opener/coach/練習室＋圖鑑/paywall/設定＋onboarding）。
> 分三級：A＝App Review 風險、B＝計費/正確性語意、C＝術語與標點統一。
>
> **狀態：已全數收案（2026-07-04）。** Eric 拍板＝A1 只換「送→解鎖」、A2/A3 不改、A4+A5+B2–B5+C 全收。
> 落地：`b83cee50`（B1）＋`4bd4d4a2`（A/B/C 批次 42 檔純文案）＋`e7f3aeea`（A7 設定頁「AI 與你的隱私」入口，onboarding 略過保留）。
> 未擴散項：「段互動紀錄」partner_list 以外還有 6 處未統一（拍板範圍外，要做另開）；`analysis_screen.dart:3336`「請識別截圖內容」是送 server 的 payload 非 UI 文案，刻意不動。

## A — App Review 風險

| # | 位置 | 現文案 | 建議 | 理由 |
|---|------|--------|------|------|
| A1 | `practice_room_entry_card.dart:308`、`practice_chat_screen.dart:296` | 每日登入就送新女孩 | 每日登入解鎖新角色 | 「送女孩」物化措辭，17+ 審查敏感 |
| A2 | `practice_chat_screen.dart:345`、`practice_collection_screen.dart:377` | 升級後每天可以翻更多陪練女孩 | 升級後每天可練更多角色 | 付費＋物化措辭 |
| A3 | `practice_collection_screen.dart:850` | 每日翻牌有機會遇到她 | 每日翻牌認識新對象 | 「有機會」＋付費翻牌＝機率式抽卡／博弈讀感 |
| A4 | `opening_rescue_screen.dart:673` | AI 幫你打造完美開場 | AI 幫你想第一句開場 | 「完美」絕對宣稱 |
| A5 | `paywall_screen.dart:1008` | Please manage subscriptions in the iOS app. | 請在 iOS App 內管理訂閱。 | 英文字串外洩 |
| A6 | `paywall_screen.dart:487` 一帶 | （全 paywall 未提免費試用/優惠期） | 若產品含 introductory offer 須補試用條款揭露 | 3.1.2(c)；**若無試用則免改** |
| A7 | `onboarding_screen.dart:71,98` | 「略過」可跳過整個「AI 與你的隱私」揭露頁 | 揭露頁不可略過，或設定頁補 AI 揭露入口 | 揭露可被略過＝拒審風險（**產品決定，非改字**） |
| A8 | `analysis_screen.dart:4037-4057` | mock 回覆字串（「嗨」「哈哈這讓我想到一個笑話」…） | ✅ 已驗碼＝免改 | **驗證結果＝死碼**：`_generateSubtext`/`_generateReplies` 掛 `// ignore: unused_element`、全 repo 零呼叫者，production 不渲染。刪死碼可另案 boy-scout |

## B — 計費／正確性語意

| # | 位置 | 現文案 | 建議 | 理由 |
|---|------|--------|------|------|
| B1 | `coach_follow_up_section.dart:494` | 這次沒有產生可用建議，未扣額度，請再試一次 | ✅ 已驗碼並修（移除「未扣額度」） | **驗證結果＝真 bug**：`GenerationFailedException` 除 5xx 外也涵蓋 200 但 client parse/安全檢查失敗（server 已扣）；coach chat 同型已在 21d59962 修，follow-up 漏。已改「這次沒有產生可用建議，請稍後再試」＋widget 測試同步 |
| B2 | `ai_data_sharing_consent.dart:164` | 同意後，這台裝置之後不會重複提醒。 | 同意後，這個帳號之後不會重複提醒。 | R1-1 後同意已是帳號級，現文案與實作不符 |
| B3 | `settings_screen.dart:726` | 已完成登出，但本機清理時發生小問題… | 已登出，但本機資料清理未完成，請重新開啟 App。 | 「小問題」淡化，與刪帳嚴謹分流語氣不一致 |
| B4 | `paywall_screen.dart:546` 比較表 | Free 陪練女孩「限量」 | 「每日不同／同一位限一輪」 | 「限量」易誤解為總量受限 |
| B5 | `paywall_screen.dart:544` 比較表 | Free 回覆風格「延展」 | 標明「僅延展 1 種」 | 與實碼 gating（Free 僅 extend）對齊、更清楚 |

## C — 術語與標點統一（可一次批改）

**術語組（擇一統一）**
- 「辨識 vs 識別」：`analysis_screen.dart:5382-5383,5496` 同畫面混用 → 統一「辨識」；`4820,4854,2045,2064`「重新跑 OCR」→「重新辨識」（工程術語外洩）
- 「五維雷達 vs 互動雷達」：`analysis_screen.dart:4976` vs `streaming_analysis_loading_widgets.dart:34` → 擇一
- 「完整版/完整回覆/完整分析」：`analysis_screen.dart:245` 等 → 統一「完整分析」
- 「陪練女孩/新女孩/模擬對象/練習對象」：練習室全域 → 統一「角色」或「練習對象」（配合 A1/A2）
- 「翻牌/抽卡/換一位/換人」：`practice_draw_ceremony.dart:559`、`practice_collection_screen.dart:339` 等 → 統一「翻牌」「換人」
- 「續約 vs 續訂」：`paywall_screen.dart:663`、settings:203 → 統一「續訂」；「每 1 個月自動續訂」（483,829）→「每月自動續訂」
- 「安排降級 vs 已排程/已安排」：`paywall_screen.dart:446 vs 431/1041` → 統一「排程降級」
- 「AI 陪練女孩 vs 陪練女孩」：`paywall_screen.dart:546 vs 554` → 統一
- 額度動詞：「生成會使用 1 則額度」（`coach_follow_up_chip_row.dart:77`）→「扣 1 則」；「不會重複扣額度」（`opening_rescue_screen.dart:66`）→ 單位「則」統一
- 「保存 vs 儲存」：`opening_rescue_screen.dart:1177` →「儲存」（台灣慣用）
- 「先跳過 vs 略過」：`about_me_screen.dart:62` →「略過」
- 「Line → LINE」：`partner_list_screen.dart:67`
- 對話計量：`partner_list_screen.dart:220「段互動紀錄」 vs 286「個對話」` → 統一「段對話」
- 「AI 幫你拆解 → 教練幫你拆解」：`coach_follow_up_section.dart:369`（教練人設一致）

**標點組（全域一次掃）**
- 半形省略號 `...` → 全形 `…`：`streaming_analysis_loading_widgets.dart:21-35`、`coach_follow_up_section.dart:470,584`、`paywall_screen.dart:429,430,441`、settings:204,282,902 等（**建議 grep 全域一次改**）
- 錯誤文案句尾句號補齊：`coach_follow_up_section.dart:486-498`
- 括號與空格：「(N 張)/(N張)」→ 全形（N 張）（`analysis_screen.dart:1672,5383`）
- 去雜訊符號：ⓘ（`coach_follow_up_section.dart:440`）、複製提示夾 emoji（`opening_rescue_screen.dart:69,1530`）、「🔄 正在識別截圖」（`analysis_screen.dart:5496`）、圖鑑「COMPLETION 完成度」英文標（`practice_collection_screen.dart:674`）
- 小潤色：needy → 「太黏或太急」（`onboarding_screen.dart:41`）；「← 左右滑動」箭頭矛盾（`opening_rescue_screen.dart:1081`）；「對方資料讀取」→「對方資料解讀」（1049）；402 額度文案三處統一（`practice_collection_screen.dart:235,253,262`）；分析錯誤文案補教練口吻（`analysis_error_widget.dart:162-189`）

## 總評

七頁皆無簡體字混入、無 debug/placeholder 直接外洩（A8 已驗＝死碼免改）、「省 X%」已與 store 實價連動、AI 揭露與刪帳分流紮實。B1 已驗碼證實為真 bug 並修掉（見上表）。最需要 Eric 拍板的剩 A 級（練習室物化＋博弈讀感措辭、揭露頁可略過）。C 級可等拍板後一顆純文案 commit 批次收。
