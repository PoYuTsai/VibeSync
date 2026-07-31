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
- client＋server 雙層白名單：client 只送白名單鍵；server 對事件名 enum 硬擋
  （字典外一律 400）、對 properties 剝除白名單外鍵、值超長截斷。
- best-effort 上傳：失敗吞掉、絕不 block UI、絕不重試風暴。
- 揭露：設定頁 AI 隱私頁「去識別化使用事件」段落涵蓋本通道。

## 事件白名單 v1

| event | properties（白名單鍵） | 打點位置 |
|---|---|---|
| `onboarding_page_view` | `page_index` (int) | OnboardingScreen.onPageChanged |
| `onboarding_skip` | `page_index` (int) | _skipOnboarding |
| `onboarding_branch_answer` | `has_partner` (bool) | _completeOnboardingTo |
| `onboarding_questionnaire_submit` | `style_set` (bool), `goals_count` (int) | 批 2 問卷頁 |
| `quota_strip_tap` | — | HomeQuotaStrip |
| `opener_entry_tap` | — | HomeFeatureEntries |
| `coach_entry_tap` | `has_partner` (bool) | HomeFeatureEntries |
| `first_analysis_completed` | — | 分析完成 hook（本機 once-flag 去重） |
| `first_practice_completed` | — | endPractice hook（本機 once-flag 去重） |
| `keyboard_setup_shown` | — | app.dart 鍵盤設定 push 點 |
| `keyboard_setup_completed` | — | markKeyboardCompleted |
| `checklist_item_done` | `item` (enum: `profile` / `first_action` / `follow_up` / `keyboard`) | 批 2 起步清單 |

值域限制（server 端強制）：

- `page_index`：0–20 的整數。
- `goals_count`：0–5 的整數。
- `item`：上表 enum 之一，其他值剝除整鍵。
- bool 鍵只收 true/false。
- 任何 string 值長度上限 40 字元，超長截斷。

## once-flag 去重

`first_analysis_completed` / `first_practice_completed` 用 SharedPreferences key
`funnel_once_<event>` 在本機去重，只送第一次。server 不做唯一約束（best-effort
通道，重複列在查詢端 dedup）。

## 讀取方式

無 client 讀路徑（RLS 無任何 client policy）。分析用 Management API 下 SQL，例：

```sql
select event, count(distinct user_id)
from funnel_events
where created_at > now() - interval '7 days'
group by event;
```

漏斗數字至少累積一週再解讀。
