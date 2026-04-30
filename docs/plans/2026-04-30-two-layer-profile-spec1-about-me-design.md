# Two-Layer Profile Spec 1: About Me / 關於我

> Status: design draft locked by Eric/Codex discussion, pending Claude implementation plan
> Date: 2026-04-30
> Parent roadmap: `docs/plans/2026-04-30-vibesync-memory-coach-roadmap.md`
> Scope: global user profile storage + report entry + manual-input cleanup only. No AI prompt injection.

## 1. 這份 Spec 要解決什麼

VibeSync 正在從「幫我回一句」轉成「有記憶的 AI 約會教練」。

目前產品已經有兩層能力：

- Layer 1：對話分析。截圖 / 手動輸入、OCR、熱度、五維、回覆建議。
- Layer 2：對象記憶。Partner card、partnerId chain、多段互動紀錄、對方特質聚合。

下一層缺的是：

- Layer 3：用戶成長層。App 需要知道「我」是誰，我想練什麼，我平常比較像什麼語氣。

Spec 1 先建立 `About Me / 關於我` 的資料與 UI。它只存資料，不進 AI prompt，不改 OCR，不改 analyze-chat。

## 2. 產品定位

Spec 1 的核心語意：

```text
讓 VibeSync 先記得我，但暫時不讓 AI 使用這份資料。
```

這是一個地基，不是完整 coach memory。

Spec 1 做完後，用戶會感覺：

- VibeSync 不只記得對象，也開始記得我。
- 這些設定是為了讓未來建議更貼近我的語氣與練習目標。
- 填寫是 optional，不是心理測驗，不是人格診斷。

## 3. 這兩張設計圖怎麼歸類

### 3.1 第一張圖：手動輸入頁移除「你的風格 / 你的興趣」

結論：屬於 Spec 1。

原因：

- `你的風格`、`你的興趣` 是 about me，全域資料。
- 手動輸入頁是 per-conversation context，每次對話都填一次會很浪費。
- 這些資料應該移到「我的報告 > 關於我」，一次填、全 app 沿用。

Spec 1 必須包含這個 cleanup：

```text
Manual Input page 移除「你的風格」與「你的興趣」。
```

### 3.2 第二張圖：對象頁右上角「我的風格」per-partner override

結論：不屬於 Spec 1 MVP。

它是後續延伸規格：

```text
Spec 2B: Partner Coaching Override
```

原因：

- 這是 partner-level setting，不是 global user profile。
- 它牽涉 prompt fallback priority：partner override > global About Me > generic。
- 它會增加 PartnerDetail 入口、partner profile schema、測試與 UX 說明。
- 若塞進 Spec 1，會把低風險 local profile 變成中高風險 prompt / partner memory scope。

因此 Spec 1 只保留一個未來鉤子：

```text
Future: Partner-specific coaching override lives in Spec 2B, not Spec 1.
```

## 4. Product Goals

- 讓用戶用約 30 秒建立全域 `關於我`。
- 讓 VibeSync 開始具備「記得使用者」的產品感。
- 把手動輸入頁從 user-profile collection 還原成 conversation input。
- 為 Spec 2 prompt fallback 提供乾淨資料來源。
- 保持 optional、低壓、不像測驗。

## 5. Non-Goals

Spec 1 不做：

- 不修改 `supabase/functions/analyze-chat`。
- 不改 OCR / Edge Function / parser / prompt。
- 不把 `UserProfile` 注入 AI prompt。
- 不新增 partner-level profile override。
- 不新增 proactive notification。
- 不 cloud sync。
- 不自動 migration 舊 `SessionContext.userStyle` / `userInterests`。
- 不做 onboarding 強制填寫。
- 不做 telemetry。

## 6. Information Architecture

底部 tab 維持現狀，不新增第四個 tab。

入口放在：

```text
我的報告 tab 頂部固定卡片
```

Route：

```text
/profile/about-me
```

UI label：

```text
關於我
```

使用 full page，不用 dialog / bottom sheet。

原因：

- 有 chip groups 和 text fields。
- 小螢幕鍵盤行為比較安全。
- 這是 coach memory 設定，心理重量比一般彈窗高。

## 7. Manual Input Page Cleanup

### 7.1 移除項目

從手動輸入頁移除：

- `你的風格`
- `你的興趣`

原因：

- 這兩個是使用者本人資料。
- 不應該每一段對話都重新填。
- 會讓新用戶誤以為每段對話都要重新設定自己。

### 7.2 手動輸入頁保留項目

手動輸入頁應只描述「這段對話 / 這個對象」：

- `認識情境`
- `認識多久`
- `目前目標`
- `對方特質`
- `對話內容`

### 7.3 輕提示文案

若空間允許，可以在頁面底部或個人化區塊原位置放一行輕提示：

```text
想讓建議更像你的語氣？可到「我的報告 > 關於我」設定一次。
```

注意：

- 不要做成強 CTA。
- 不要阻擋使用者建立對話。
- 不要跳 onboarding。

### 7.4 預期 UX

改完後，手動輸入頁語意會變成：

```text
這一頁只是在描述目前這段互動。
使用者本人資料，統一到「關於我」管理。
```

這可以避免「我」和「對方」的資料混在同一頁。

## 8. About Me Card

### 8.1 Empty Profile

顯示於我的報告頂部：

```text
關於我
讓 VibeSync 更像你的教練
花 30 秒填一下，之後 AI 會用更像你的節奏給建議

[開始設定]
```

### 8.2 Filled Profile

顯示 compact summary，只顯示已填欄位：

```text
關於我
互動風格：溫柔
練習目標：自然邀約、降低焦慮
常聊話題：咖啡、旅行、電影

[編輯]
```

Rules：

- 只 render 有值欄位。
- 只有一個欄位有值，就只顯示一行。
- filled card 應比報告主卡更輕，不要搶走 heat / radar 的主視覺。
- empty card 可以稍微更 prominent，因為它是首次設定入口。
- 即使目前沒有 report data，About Me card 也要 render。

## 9. About Me Edit Page

Title：

```text
關於我
```

Subtitle：

```text
花 30 秒設定你的互動風格和練習目標，之後 VibeSync 會更懂你的節奏。
```

Privacy note：

```text
這些設定只用來讓建議更貼近你的語氣，不會顯示給任何對象，你可以隨時修改或清除。
```

## 10. Profile Fields

### 10.1 Interaction Style

Field：

```dart
interactionStyle
```

Selection：

- Single select。
- Max 1。
- Optional。

Options：

| Internal | Label |
|---|---|
| `steady` | 穩重 |
| `direct` | 直接 |
| `humorous` | 幽默 |
| `gentle` | 溫柔 |
| `playful` | 俏皮 |

Helper：

```text
讓未來建議更像你自然會講的語氣。
```

Avoid labels：

- `personality`
- `seductionStyle`
- `datingPersona`

### 10.2 Practice Goals

Field：

```dart
practiceGoals
```

Selection：

- Multi-select。
- Max 3。
- Optional。

Options：

| Internal | Label |
|---|---|
| `softInvite` | 自然邀約 |
| `reduceAnxiety` | 降低焦慮 |
| `humorousReply` | 幽默回覆 |
| `buildCloseness` | 拉近距離 |
| `explainLess` | 少解釋一點 |

Helper：

```text
最多選 3 個，VibeSync 之後會優先幫你練這些能力。
```

When user taps a 4th option：

```text
最多選 3 個
```

### 10.3 Topic Seeds

Field：

```dart
topicSeeds
```

Selection：

- Multi-select。
- Max 5。
- Optional。

Options：

| Internal | Label |
|---|---|
| `fitness` | 健身 |
| `travel` | 旅行 |
| `coffee` | 咖啡 |
| `music` | 音樂 |
| `movies` | 電影 |
| `photography` | 攝影 |
| `food` | 美食 |
| `pets` | 寵物 |
| `reading` | 閱讀 |
| `workLife` | 工作生活 |

Helper：

```text
這些會幫 AI 找到更像你的自然延伸話題。
```

When user taps a 6th option：

```text
最多選 5 個
```

### 10.4 Custom Topics

Field：

```dart
customTopics
```

Type：

- Optional text。
- Max 60 chars。
- Trim before save。

Placeholder：

```text
也可以補充你的常聊話題，例如：重訓、日劇、週末探店
```

### 10.5 Notes

Field：

```dart
notes
```

Type：

- Optional text。
- Max 100 chars。
- Trim before save。

Placeholder：

```text
例如：我慢熟，希望語氣自然一點，不要太油，也不要太快邀約
```

Helper：

```text
這段只給教練參考，不會顯示給任何對象。
```

## 11. Data Model

Recommended feature root：

```text
lib/features/user_profile/
```

Recommended structure：

```text
lib/features/user_profile/
  data/
    repositories/user_profile_repository.dart
    providers/user_profile_providers.dart
  domain/
    entities/user_profile.dart
  presentation/
    screens/about_me_screen.dart
    widgets/about_me_card.dart
    widgets/profile_chip_section.dart
```

Entity：

```dart
class UserProfile {
  final InteractionStyle? interactionStyle;
  final List<PracticeGoal> practiceGoals;
  final List<TopicSeed> topicSeeds;
  final String? customTopics;
  final String? notes;
  final DateTime updatedAt;
}
```

Enums：

```dart
enum InteractionStyle { steady, direct, humorous, gentle, playful }
enum PracticeGoal { softInvite, reduceAnxiety, humorousReply, buildCloseness, explainLess }
enum TopicSeed { fitness, travel, coffee, music, movies, photography, food, pets, reading, workLife }
```

Storage：

- Use encrypted Hive, matching existing local storage conventions。
- Use next available Hive typeId。
- Before choosing typeId, grep existing `@HiveType`。
- Store enum values in a stable format。
- Empty strings normalize to `null`。
- Empty lists remain empty lists。

Existence rule：

```text
All fields empty = no profile.
Any field present = profile exists.
```

## 12. Save / Skip / Clear Behavior

### 12.1 New Empty Profile

If all fields are empty and no profile exists：

- Primary button label：`先跳過`
- Tap returns to report tab。
- Do not persist empty profile。

### 12.2 New Non-Empty Profile

If any field has content：

- Primary button label：`儲存`
- Save profile。
- Return to report tab。
- Show snackbar：

```text
已更新關於我
```

### 12.3 Existing Profile Cleared

If profile existed and user clears all fields：

- Primary button label：`清除設定`
- Tap clears profile。
- Return to report tab。
- Show snackbar：

```text
已清除關於我設定
```

No confirmation dialog in v1。

### 12.4 Save Failure

Show：

```text
儲存失敗，請再試一次
```

Do not show raw exception text。

## 13. Old SessionContext Data

Do not silently migrate old per-conversation `SessionContext.userStyle` or `userInterests`。

Reason：

- Old fields may describe one conversation, not the user's long-term style。
- Silent migration can make users wonder when they configured profile。
- Migration increases scope and testing risk。

Future optional import：

```text
我們找到你之前填過的風格資訊，要匯入到關於我嗎？
[匯入] [不用]
```

Not in Spec 1。

## 14. Tests

### 14.1 Unit Tests

Recommended path：

```text
test/unit/features/user_profile/
```

Cover：

- Empty fields normalize correctly。
- `practiceGoals` max 3。
- `topicSeeds` max 5。
- `customTopics` max 60 chars。
- `notes` max 100 chars。
- Clear profile reads back as null。
- Hive round-trip preserves data。

### 14.2 Provider / Controller Tests

Cover：

- `save(profile)` writes repository。
- Empty save with no prior profile is no-op or clear。
- `clear()` returns state to null。
- Repository failure surfaces to UI layer。

### 14.3 Widget Tests: Report About Me Card

Cover：

- No profile shows `讓 VibeSync 更像你的教練` and `開始設定`。
- Filled profile shows summary lines。
- Partial profile only shows filled fields。
- Tap `開始設定` routes to `/profile/about-me`。
- Tap `編輯` routes to `/profile/about-me`。

### 14.4 Widget Tests: About Me Screen

Cover：

- Empty new profile shows `先跳過`。
- Selecting style changes primary button to `儲存`。
- Practice goals max 3。
- Topic seeds max 5。
- Text fields trim / limit input。
- Existing profile pre-fills。
- Clearing all fields shows `清除設定`。
- Successful save returns to report page。
- Bottom privacy note renders。

### 14.5 Widget Tests: Manual Input Cleanup

Cover：

- Manual input page no longer shows `你的風格`。
- Manual input page no longer shows `你的興趣`。
- Manual input page still shows `認識情境`。
- Manual input page still shows `認識多久`。
- Manual input page still shows `目前目標`。
- Manual input page still shows `對方特質`。
- Manual input page still accepts conversation content。
- If hint is implemented, it routes or references `我的報告 > 關於我` without blocking submit。

### 14.6 Explicitly Not Tested In Spec 1

- `analyze-chat` prompt injection。
- Edge Function behavior。
- OCR。
- Partner override。
- Push notification。

## 15. Implementation Commit Plan

Recommended commits：

1. `[feat] UserProfile domain + Hive adapter`
2. `[feat] UserProfile repository + providers`
3. `[feat] Report About Me card`
4. `[feat] About Me edit screen`
5. `[refactor] Manual input removes user profile fields`
6. `[docs] close Spec 1 implementation queue`

Final verification gate：

```bash
flutter test test/unit/features/user_profile/ test/widget/features/report/ test/widget/features/user_profile/
flutter test test/widget/features/conversation/
flutter analyze --no-fatal-infos lib test
```

Adjust paths to actual implementation。

## 16. Future Specs

### Spec 2A: Prompt Fallback Chain

- Build `UserProfileBlock`。
- Inject profile into prompt only when profile exists。
- Add no-profile regression proving old prompt behavior remains equivalent。
- Keep Edge prompt changes isolated。

### Spec 2B: Partner Coaching Override

- Add partner-level coaching override from PartnerDetail。
- Priority：partner override > global About Me > generic。
- Allows style adjustment for a specific partner only。
- Not in Spec 1。

### Spec 3: Partner Data Quality Guard

- Detect mixed-person contamination in partner cards。
- Warn before injecting low-confidence partner aggregate memory。
- Provide move / split recovery paths。

### Spec 4: Coach Action Loop

- Turn `nextStep` / `finalRecommendation` into concrete tasks。
- Examples：soft invite, lower-pressure reply, explain less, stop chasing, post-date follow-up。

## 17. Open Questions For Later

- Should v1.1 add a one-time hint after first successful analysis?
- Should Settings also link to About Me?
- Should telemetry track completion, edit, and clear rates?
- Should old `SessionContext` data be offered as explicit import?
- Should partner override live behind the person icon or the existing `...` menu?
