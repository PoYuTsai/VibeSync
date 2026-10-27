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
| `onboarding_page_view` | `page_index` (int) | OnboardingScreen.onPageChanged |
| `onboarding_skip` | `page_index` (int) | _skipOnboarding |
| `onboarding_branch_answer` | `has_partner` (bool) | _completeOnboardingTo |
| `onboarding_questionnaire_submit` | `goals_count` (int) | 批 2 問卷頁（2026-08-04 拿掉互動風格題後 style_set 移除） |
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
| `paywall_opened` | `entry` (enum: `general` / `locked_cards` / `quota_exhausted`) | PaywallScreen.initState：每開一次一筆。入口是 go_router extra 帶來的 PaywallEntry，沒帶算 `general`；額度不夠的四種入口（今天／這個月、用完／不夠這次用）都記 `quota_exhausted`（2026-10-18：量從哪裡打開付費頁） |
| `paywall_purchase_completed` | `tier` (enum: `starter` / `essential`), `entry` (同上 enum), `purchaser` (UUID，只驗證、不落庫) | PaywallScreen._subscribe：RevenueCat 回成功才記；`tier` 是買的商品對應的方案。取消、失敗、逾時、例外、排程降級、恢復購買都不記；不帶價格、商品 id、收據。`purchaser` 是開始購買時的登入帳號，付款確認回來時已換帳號或登出就不送 |
| `locked_cards_upgrade_tap` | `locked_count` (int) | GuideV3LockedBlock「看方案」：結果頁與分析紀錄共用同一塊，張數就是區塊寫的「還有 N 張」 |

值域限制（server 端強制）：

- `page_index`：0–20 的整數。
- `goals_count`：0–5 的整數。
- `seeds_count`：0–5 的整數。
- `locked_count`：1–5 的整數。
- `item`：上表 enum 之一，其他值剝除整鍵。
- `source`：上表 enum 之一，其他值剝除整鍵。
- `entry`：上表 enum 之一，其他值剝除整鍵。
- `tier`：`starter` / `essential` 之一（`free` 不是購買結果），其他值剝除整鍵。
- `purchaser`：只有 `paywall_purchase_completed` 收。必須是 UUID 而且等於登入帳號的
  `user.id`；缺少、格式不對或不同，**整筆拒絕**（400，不寫入）。驗完剝掉、不落庫。
  其他事件帶了一律剝掉（2026-10-18 主審 r2：認證權杖在 HTTP 送出當下才取，付款確認
  期間換帳號時，事件會用到別人的登入；Eric 核准由 server 比對擋下）。
- bool 鍵只收 true/false（`has_partner`、`has_style`、`has_notes`、`has_custom_topics`、`is_recommended`）。
- 任何 string 值長度上限 40 字元，超長截斷。

付費頁三個事件的解讀（2026-10-18）：

- server 白名單要先部署，app 送的這三個事件才收得到；舊 server 回 400，client 吞掉，資料就少了那段。
- 結果頁的「看方案」連點時付費頁只開一次（防重入），所以 `locked_cards_upgrade_tap` 可能比 `entry=locked_cards` 的 `paywall_opened` 多。
- 付款確認期間換帳號或登出，那筆購買事件會被丟掉（寧可少記，不記到別人身上）。
- 免費看幾張卡的決定（audit 三層方案）：累積二到四週，比 `entry=locked_cards` 開了幾次付費頁、其中幾次買了。

## once-flag 去重

`first_analysis_completed` / `first_practice_completed` 用 SharedPreferences key
`funnel_once_<event>` 在本機去重，只送第一次。server 不做唯一約束（best-effort
通道，重複列在查詢端 dedup）。

## 登入前的事件：先排隊、登入後補送（2026-10-27）

onboarding 走在登入之前，那時伺服器沒有帳號可以掛，事件以前一律被拒（401）、client
吞掉，等於沒記。改成（onboarding 轉換第 4 步）：

- 沒登入時 client 不送，把事件存進手機 SharedPreferences 的 `funnel_pending_queue_v1`
  （JSON 陣列）。每筆只有事件名、已過白名單的屬性、當時的 `clientTs`、排進來的時間與
  補送失敗次數；沒有對話、名字或自由文字。最多 50 筆，滿了丟最舊的。
- 登入後進首頁時（MainShell 掛上 `OnboardingHandoffApplier`，跟問卷交接同一個時機；
  每次開 App 進首頁都會跑，沒有佇列就什麼都不做）呼叫 `flushPending()`：排隊超過 7 天
  的丟掉（太久以前的可能是別人用這支手機時留下的）；其餘逐筆照原本的 body 送，成功的
  移除，失敗的留著下次進首頁再送，每筆最多試 3 次。同時呼叫只跑一輪；補送途中登出就停，
  剩下的留著。
- 補送的事件掛在補送當下登入的帳號；`client_ts` 是事件當時的時間，`created_at` 是補送
  的時間，算 onboarding 各頁時間要看 `client_ts`。伺服器不用改。
- 從頭到尾沒登入就離開的人仍然看不到；那一段改用 App Store Connect 的首次下載數對照每天
  新帳號數粗估。onboarding 各頁的流失率只代表後來有登入的人。

## 讀取方式

無 client 讀路徑（RLS 無任何 client policy）。分析用 Management API 下 SQL，例：

```sql
select event, count(distinct user_id)
from funnel_events
where created_at > now() - interval '7 days'
group by event;
```

漏斗數字至少累積一週再解讀。
