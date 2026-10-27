# 漏斗事件字典 v1（funnel-events-v1）

> 真相源：本檔是 client `FunnelTracker` 與 Edge `submit-feedback` `kind:"funnel"` 分支
> 白名單的唯一依據。**改這份字典，必須同一批 commit 同步改 client 與 server 兩層白名單**
>（教訓：AI 鍵盤案的 SQL 白名單漂移——Deno 綠只驗 TS 層）。

## 目的

量測 onboarding → 首次價值 → 留存動作的轉化漏斗（onboarding 轉化診斷 2026-07-31 的
Tier 2 埋點前置債）。資料落 `public.funnel_events`，只有 service role（Edge）可寫，
查詢走 Supabase Management API。

## 隱私鐵則（照案 1 批 3 outcome_events 前例）

- payload 只有 `event` 名＋下表白名單鍵；**絕不**帶對話內容、對象名、自由文字。
- 只拿來驗證、不落庫的鍵：`purchaser`（見值域限制）。server 驗完就剝掉，row 只有
  `user_id`（本來就是登入帳號）。
- client＋server 雙層白名單：client 只送白名單鍵；server 對事件名 enum 硬擋
  （字典外一律 400）、對 properties 剝除白名單外鍵、值超長截斷。
- best-effort 上傳：失敗吞掉、絕不 block UI、絕不重試風暴；唯一會重試的是登入前排隊的
  補送（每筆最多 3 次，見「登入前的事件」）。
- 揭露：設定頁 AI 隱私頁「去識別化使用事件」段落涵蓋本通道。

## 事件白名單 v1

| event | properties（白名單鍵） | 打點位置 |
|---|---|---|
| `onboarding_page_view` | `page_index` (int) | OnboardingScreen：每換一頁一筆（含按上一頁回去），第 0 頁在進場時補。2026-10-27 起 4 頁版是 0–3（0 選路徑、1 測驗題、2 目標、3 登入後做什麼）；9 頁版是 0–8 |
| `onboarding_skip` | `page_index` (int) | 不走完 onboarding 就離開：4 頁版只有第 1 頁的「先逛逛」（`page_index`＝0）。「我有帳號」不記；第 2、3 頁的「直接開始」「略過」只是跳到最後一頁，也不記 |
| `onboarding_branch_answer` | `has_partner` (bool) | 9 頁版的分流頁。4 頁版（2026-10-27 onboarding 轉換第 12 步）不送，改送 `onboarding_intent`；留在字典給舊版 App 與手機裡還沒補送的佇列 |
| `onboarding_questionnaire_submit` | `goals_count` (int) | 按下 onboarding 最後的按鈕時（4 頁版是最後一頁的「繼續」；2026-08-04 拿掉互動風格題後 style_set 移除）。按「直接開始」跳過目標頁的人也會送，`goals_count`＝0 |
| `onboarding_intent` | `intent` (enum: `analyze` / `opener` / `practice` / `browse`) | 4 頁版第 1 頁（2026-10-27 onboarding 轉換第 12 步）：她回我了＝`analyze`、剛配對＝`opener`、還沒有對象＝`practice`、先逛逛＝`browse`。每按一次記一筆，按上一頁回來改選會再記一筆，以最後一筆為準 |
| `onboarding_quiz_answer` | `correct` (bool) | 4 頁版第 2 頁那一題第一次作答時（2026-10-27）：答對 true、答錯 false；作答一次就定案，按「直接開始」跳過的不記 |
| `quota_strip_tap` | — | HomeQuotaStrip |
| `opener_entry_tap` | — | HomeFeatureEntries |
| `coach_entry_tap` | `has_partner` (bool) | HomeFeatureEntries |
| `first_analysis_completed` | — | 分析完成 hook（本機 once-flag 去重） |
| `first_practice_completed` | — | endPractice hook（本機 once-flag 去重） |
| `keyboard_setup_shown` | — | app.dart 鍵盤設定 push 點 |
| `keyboard_setup_completed` | — | markKeyboardCompleted |
| `checklist_item_done` | `item` (enum: `profile` / `first_action` / `keyboard`) | 起步清單（2026-08-01 起三項：跟進提醒項移除） |
| `about_me_opened` | `source` (enum: `checklist` / `card` / `settings`) | AboutMeScreen.initState |
| `about_me_saved` | `has_style` (bool), `goals_count` (int), `seeds_count` (int), `has_notes` (bool), `has_custom_topics` (bool) | AboutMeScreen 儲存成功後 |
| `about_me_cleared` | — | AboutMeScreen 清除成功後 |
| `new_topic_copied` | `is_recommended` (bool) | NewTopicView 複製開場句（2026-10-12：量新話題有沒有被拿去傳；只記是不是推薦那題，不含句子） |
| `paywall_opened` | `entry` (enum: `general` / `locked_cards` / `quota_exhausted` / `practice_draw`) | PaywallScreen.initState：每開一次一筆。入口是 go_router extra 帶來的 PaywallEntry，沒帶算 `general`；額度不夠的四種入口（今天／這個月、用完／不夠這次用）都記 `quota_exhausted`（2026-10-18：量從哪裡打開付費頁）；練習室翻牌撞牆記 `practice_draw`（2026-10-27 Onboarding 第 2 步：免費首抽用掉後再按翻牌、402 後自動開的付費頁、SR 限定翻牌鎖卡、練習室翻牌鎖住時的升級鈕，以及錯誤橫幅確定是翻牌的錯時；共用額度用完、續聊同一位被擋、Game 介紹「查看方案」仍記 `general`） |
| `paywall_purchase_completed` | `tier` (enum: `starter` / `essential`), `entry` (同上 enum), `purchaser` (UUID，只驗證、不落庫) | PaywallScreen._subscribe：RevenueCat 回成功才記；`tier` 是買的商品對應的方案。取消、失敗、逾時、例外、排程降級、恢復購買都不記；不帶價格、商品 id、收據。`purchaser` 是開始購買時的登入帳號，付款確認回來時已換帳號或登出就不送 |
| `locked_cards_upgrade_tap` | `locked_count` (int) | GuideV3LockedBlock「看方案」：結果頁與分析紀錄共用同一塊，張數就是區塊寫的「還有 N 張」 |
| `quota_block_shown` | `feature` (enum: `analyze` / `opener` / `new_topic` / `coach` / `practice` / `keyboard`), `scope` (enum: `daily` / `monthly` / `unknown`), `block_source` (enum: `precheck` / `server`) | 告訴使用者「額度不夠」的那一刻（2026-10-27）：分析確認框不足與 429、開場救星預檢與 429、新話題預檢／按鈕被擋／429、教練 429、練習翻牌 402／429 與「換一位」、加抽前的預檢、鍵盤額度訊號。同一次執行同一個 feature＋scope 只記一次，見「額度不足事件」 |

值域限制（server 端強制）：

- `page_index`：0–20 的整數。
- `goals_count`：0–5 的整數。
- `seeds_count`：0–5 的整數。
- `locked_count`：1–5 的整數。
- `item`：上表 enum 之一，其他值剝除整鍵。
- `source`：上表 enum 之一，其他值剝除整鍵。
- `entry`：上表 enum 之一，其他值剝除整鍵。
- `tier`：`starter` / `essential` 之一（`free` 不是購買結果），其他值剝除整鍵。
- `feature`：`analyze` / `opener` / `new_topic` / `coach` / `practice` / `keyboard` 之一，
  其他值剝除整鍵。
- `scope`：`daily` / `monthly` / `unknown` 之一，其他值剝除整鍵。
- `block_source`：`precheck` / `server` 之一，其他值剝除整鍵。不叫 `source`：server 的值域
  表以鍵名全域共用，`source` 已經是 `about_me_opened` 的鍵（`checklist` / `card` /
  `settings`），兩邊值域互不相通。
- `intent`：`analyze` / `opener` / `practice` / `browse` 之一，其他值剝除整鍵。只有
  `onboarding_intent` 收（2026-10-27）。
- `correct`：只收 true/false，其他值剝除整鍵。只有 `onboarding_quiz_answer` 收；不帶題號
  或選了哪個選項。
- `purchaser`：只有 `paywall_purchase_completed` 收。必須是 UUID 而且等於登入帳號的
  `user.id`；缺少、格式不對或不同，**整筆拒絕**（400，不寫入）。驗完剝掉、不落庫。
  其他事件帶了一律剝掉（2026-10-18 主審 r2：認證權杖在 HTTP 送出當下才取，付款確認
  期間換帳號時，事件會用到別人的登入；Eric 核准由 server 比對擋下）。
- bool 鍵只收 true/false（`has_partner`、`has_style`、`has_notes`、`has_custom_topics`、`is_recommended`、`correct`）。
- 任何 string 值長度上限 40 字元，超長截斷。

付費頁三個事件的解讀（2026-10-18）：

- server 白名單要先部署，app 送的這三個事件才收得到；舊 server 回 400，client 吞掉，資料就少了那段。
- `entry=practice_draw`（2026-10-27）也是 server 先部署：舊 server 不認得這個值只剝掉 `entry`、事件照收，那段期間的翻牌入口會變成沒有 `entry` 的 `paywall_opened`。
- 結果頁的「看方案」連點時付費頁只開一次（防重入），所以 `locked_cards_upgrade_tap` 可能比 `entry=locked_cards` 的 `paywall_opened` 多。
- 付款確認期間換帳號或登出，那筆購買事件會被丟掉（寧可少記，不記到別人身上）。
- 免費看幾張卡的決定（audit 三層方案）：累積二到四週，比 `entry=locked_cards` 開了幾次付費頁、其中幾次買了。

onboarding 4 頁版的解讀（2026-10-27，onboarding 轉換第 12 步）：

- server 白名單要先部署：舊 server 不認得 `onboarding_intent`、`onboarding_quiz_answer`，
  回 400；這兩個事件多半是登入前排隊、登入後補送，補送被拒會再試，每筆最多 3 次就丟掉。
- 事件不帶 App 版本，9 頁版與 4 頁版的 `page_index` 意義不同：跨版本比較要用新版上線日期切
  （同一支手機只會走其中一版）。
- 4 頁版沒有「有沒有對象」這一題：`intent`＝`practice` 是「還沒有對象，想先練」，其他三個值
  不代表一定有對象（`browse` 是沒選）。

## once-flag 去重（2026-10-27 起送成功才算）

`first_analysis_completed` / `first_practice_completed` 與起步清單的
`checklist_item_done`（逐項）每個帳號只送一次（onboarding 轉換第 5 步）：

- 記號鍵 `funnel_once_v2_<user_id>_<onceKey 或事件名>`，分帳號：同一支手機登出換另一個
  帳號，第二個帳號的「第一次」照樣記。
- 先送，伺服器收下（2xx）才寫記號；斷網、被拒或丟錯都不寫，下次觸發再送。同一個鍵送出
  中再觸發直接略過（起步清單每次重建都會觸發），同一次執行同一個鍵最多試 3 次。
- 事件、送出時的身份、成功記號綁同一個帳號：記號鍵用一開始讀到的帳號，送出前與寫記號
  前都確認登入的還是它；中途換帳號或登出就不送、不記號，也不改成排隊（2026-10-27
  Codex 主審第 1 輪 P2：以前會把 A 的事件送給 B、記號寫給 A）。
- 沒登入時交給下面的「登入前的事件」佇列，不寫記號；同一次執行同一個鍵只排一次。
- 舊鍵 `funnel_once_<event>`（不分帳號、送之前就寫）不再讀：升級後每個帳號可能再送一次
  「第一次」事件。

server 不做唯一約束（best-effort 通道），重複列在查詢端以 `user_id` 去重。

## 登入前的事件：先排隊、登入後補送（2026-10-27）

onboarding 走在登入之前，那時伺服器沒有帳號可以掛，事件以前一律被拒（401）、client
吞掉，等於沒記。改成（onboarding 轉換第 4 步）：

- 沒登入時 client 不送，把事件存進手機 SharedPreferences 的 `funnel_pending_queue_v1`
  （JSON 陣列）。每筆有內部編號（排隊時間加亂數，補送時只動那一筆）、事件名、已過白名單
  的屬性、當時的 `clientTs`、排進來的時間與補送失敗次數，第一次補送時再加上綁定的帳號
  id（`owner`）；沒有對話、名字或自由文字。最多 50 筆，滿了丟最舊的。
- 登入後進首頁時（MainShell 掛上 `OnboardingHandoffApplier`，跟問卷交接同一個時機；
  每次開 App 進首頁都會跑，沒有佇列就什麼都不做）呼叫 `flushPending()`：排隊超過 7 天
  的丟掉（太久以前的可能是別人用這支手機時留下的）；還沒綁帳號的綁給現在登入的帳號
  （存 `owner`），已經綁給別的帳號的（之前補送到一半就換帳號）直接丟掉、不送；其餘逐筆
  照原本的 body 送，成功的移除，失敗的留著下次進首頁再送，每筆最多試 3 次。同時呼叫只跑
  一輪；補送途中登出或換帳號就停，剩下的留給原帳號。
- 補送的事件掛在第一次補送時綁定的帳號，同一批 onboarding 事件不會分到兩個帳號
  （2026-10-27 Codex 主審第 1 輪 P2）；綁定之後、沒登入時才排進來的事件還沒綁帳號，
  照舊給下一個登入的帳號。`client_ts` 是事件當時的時間，`created_at` 是補送的時間，
  算 onboarding 各頁時間要看 `client_ts`。伺服器不用改。
- 從頭到尾沒登入就離開的人仍然看不到；那一段改用 App Store Connect 的首次下載數對照每天
  新帳號數粗估。onboarding 各頁的流失率只代表後來有登入的人。

## 額度不足事件（2026-10-27）

撞到額度是免費用戶最可能付費的時刻，但很多擋下發生在 App 端（確認框直接停用「開始
分析」），請求沒送出、伺服器看不到；以前只記得點進付費頁的人。`quota_block_shown`
在每個「告訴使用者額度不夠」的地方記一筆（onboarding 轉換第 6 步）：

- 同一次執行、同一個 `feature`＋`scope` 只記一次（App 重開才會再記）：算的是「撞過
  額度的人」，不是撞了幾次。同一次執行先被預檢擋過，之後的 429 不會再記。
- `block_source=precheck`：App 自己先擋，請求沒送出（伺服器的 ai_logs 看不到）；
  `block_source=server`：伺服器回 429／402，或鍵盤轉來伺服器確認過的額度訊號。
- `scope` 照畫面上告訴他的每日或每月；App 分不出來時是 `unknown`：練習翻牌一律 unknown
  （402 是方案沒有翻牌額度、429 沒帶是哪一種，加抽前的預檢也照同一個口徑）、鍵盤訊號、
  教練 429 沒帶錯誤碼。
- 只是記錄，不改任何額度判斷、按鈕狀態或付費頁。
- server 白名單要先部署，app 送的才收得到；舊 server 對不認得的事件回 400，client 不算
  記過，下次擋到時再送（同一次執行最多 3 次）。
- 每週 cohort 查詢的「7 天內撞額度」用這個事件（以 `user_id` 去重）。

## 讀取方式

無 client 讀路徑（RLS 無任何 client policy）。分析用 Management API 下 SQL，例：

```sql
select event, count(distinct user_id)
from funnel_events
where created_at > now() - interval '7 days'
group by event;
```

漏斗數字至少累積一週再解讀。
