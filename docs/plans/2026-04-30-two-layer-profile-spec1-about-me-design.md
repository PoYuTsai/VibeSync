# Two-Layer Profile Spec 1: About Me

> Status: design draft locked by Eric/Codex discussion, pending Claude review and implementation plan
> Date: 2026-04-30
> Parent roadmap: `docs/plans/2026-04-30-vibesync-memory-coach-roadmap.md`
> Scope: user profile storage + UI only. No AI prompt injection.

## 1. Context

VibeSync is repositioning from a one-shot reply assistant into a memory-based AI dating coach.

The product already has:

- Layer 1: conversation analysis.
- Layer 2: partner memory through Partner cards and partnerSummary.

The next missing layer is Layer 3: user growth. VibeSync should remember the user's own interaction style, practice goals, and natural topic material so future advice can feel closer to the user's own rhythm.

Spec 1 builds the "About Me" foundation. It creates the user profile data model, local storage, report-tab entry point, and edit flow. It intentionally does not use this data in AI prompts yet.

## 2. Product Goals

- Let users create a lightweight global profile in about 30 seconds.
- Make the product feel like it remembers the user, not only each partner.
- Keep the flow optional and non-blocking.
- Avoid the feeling of a personality test, diagnosis, or surveillance.
- Prepare clean data for Spec 2 prompt fallback chain.

## 3. Non-Goals

- Do not modify `supabase/functions/analyze-chat`.
- Do not deploy or change OCR / Edge Function behavior.
- Do not inject `UserProfile` into AI prompts.
- Do not add partner-level profile overrides.
- Do not add proactive notifications or agent behavior.
- Do not add cloud sync.
- Do not migrate old `SessionContext.userStyle` / `userInterests` automatically.
- Do not add telemetry in v1, though future metrics are documented below.

Spec 1 only builds memory storage and UI. Spec 2 uses that memory.

## 4. Information Architecture

Bottom tabs remain:

1. 首頁
2. 報告
3. 學習

The entry point lives at the top of the `報告` tab, whose page title is currently `我的報告`.

Do not add a fourth bottom tab.

Route:

```text
/profile/about-me
```

UI label:

```text
關於我
```

## 5. About Me Card

### Empty Profile

Shown at the top of the report tab when no profile exists:

```text
關於我

讓 VibeSync 更像你的教練
花 30 秒填一下，之後 AI 會用更像你的節奏給建議

[開始設定]
```

### Filled Profile

Shown as a compact summary:

```text
關於我

風格：溫柔
想練習：自然邀約、降低焦慮
話題素材：咖啡、旅行、電影

[編輯]
```

Rules:

- Only render fields that have values.
- If only one field is filled, only show that field.
- The filled card should be visually lighter than report charts / core report content.
- The empty CTA card can be slightly more prominent.
- The card must render even when there is no report data yet.

## 6. Edit Page

Title:

```text
關於我
```

Subtitle:

```text
讓建議更像你的節奏
花 30 秒填一下，之後 AI 會更懂你的語氣、話題和練習目標
```

Privacy note at bottom:

```text
這些設定只用來讓建議更貼近你的語氣，不會顯示給任何對象，你可以隨時修改或清除
```

Use a full screen page, not a dialog or bottom sheet.

Reason:

- There are multiple chip groups and text fields.
- Keyboard behavior is safer on small screens.
- The feature has the right psychological weight as a "coach memory" setting.

## 7. Profile Fields

### 7.1 Interaction Style

Field:

```dart
interactionStyle
```

Selection:

- Single select.
- Max 1.
- Optional.

Options:

| Internal | Label |
|---|---|
| `steady` | 穩重 |
| `direct` | 直接 |
| `humorous` | 幽默 |
| `gentle` | 溫柔 |
| `playful` | 俏皮 |

Helper:

```text
選一個最像你平常互動的節奏
```

Avoid labels such as `personality`, `seductionStyle`, or `datingPersona`.

### 7.2 Practice Goals

Field:

```dart
practiceGoals
```

Selection:

- Multi-select.
- Max 3.
- Optional.

Options:

| Internal | Label |
|---|---|
| `softInvite` | 自然邀約 |
| `reduceAnxiety` | 降低焦慮 |
| `humorousReply` | 幽默回覆 |
| `buildCloseness` | 拉近距離 |
| `explainLess` | 少解釋一點 |

Helper:

```text
最多選 3 個，VibeSync 會優先給這些方向的建議
```

When user taps a 4th option, keep prior selection and show:

```text
最多選 3 個
```

### 7.3 Topic Seeds

Field:

```dart
topicSeeds
```

Selection:

- Multi-select.
- Max 5.
- Optional.

Options:

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

Helper:

```text
這些會幫 AI 產生更像你的自然話題
```

When user taps a 6th option, keep prior selection and show:

```text
最多選 5 個
```

### 7.4 Custom Topics

Field:

```dart
customTopics
```

Type:

- Optional text.
- Max 60 chars.
- Trim before save.

Placeholder:

```text
也可以補充你的常聊話題，例如：重訓、日劇、週末探店
```

### 7.5 Notes

Field:

```dart
notes
```

Type:

- Optional text.
- Max 100 chars.
- Trim before save.

Placeholder:

```text
例如：我慢熟，希望語氣自然一點，不要太油，也不要太快邀約
```

Helper:

```text
你也可以補充不想要的語氣或界線
```

## 8. Data Model

Recommended feature root:

```text
lib/features/user_profile/
```

Recommended structure:

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

Entity:

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

Enums:

```dart
enum InteractionStyle { steady, direct, humorous, gentle, playful }
enum PracticeGoal { softInvite, reduceAnxiety, humorousReply, buildCloseness, explainLess }
enum TopicSeed { fitness, travel, coffee, music, movies, photography, food, pets, reading, workLife }
```

Storage:

- Use encrypted Hive, matching existing local storage conventions.
- Use the next available Hive typeId.
- Before choosing typeId, grep existing `@HiveType`.
- Store enum values in a stable format.
- Empty strings should normalize to `null`.
- Empty lists should remain empty lists.

Existence rule:

- All fields empty = no profile.
- Any field present = profile exists.

## 9. Save / Skip / Clear Behavior

### New Empty Profile

If all fields are empty and no profile exists:

- Primary button label: `先略過`
- Tap returns to report tab.
- Do not persist an empty profile.

### New Non-Empty Profile

If any field has content:

- Primary button label: `儲存`
- Save profile.
- Return to report tab.
- Show snackbar:

```text
已更新「關於我」
```

### Existing Profile Cleared

If a profile existed and user clears all fields:

- Primary button label: `清除設定`
- Tap clears profile.
- Return to report tab.
- Show snackbar:

```text
已清除「關於我」設定
```

No confirmation dialog in v1.

### Save Failure

Show:

```text
儲存失敗，請稍後再試
```

Do not show raw exception text to users.

## 10. Old SessionContext Data

Do not silently migrate old per-conversation `SessionContext.userStyle` or `userInterests`.

Reason:

- Old fields may reflect a single conversation, not the user's long-term style.
- Silent migration can make users wonder when they configured the profile.
- Migration increases scope and testing risk.

Future optional import:

```text
我們找到你之前填過的風格/興趣，要帶入「關於我」嗎？
[帶入] [不用]
```

Not in Spec 1.

## 11. Tests

### Unit Tests

Recommended path:

```text
test/unit/features/user_profile/
```

Cover:

- Empty fields normalize correctly.
- `practiceGoals` max 3.
- `topicSeeds` max 5.
- `customTopics` max 60 chars.
- `notes` max 100 chars.
- Clear profile reads back as null.
- Hive round-trip preserves data.

### Provider / Controller Tests

Cover:

- `save(profile)` writes repository.
- Empty save with no prior profile is no-op or clear.
- `clear()` returns state to null.
- Repository failure surfaces to UI layer; do not silent catch.

### Widget Tests: Report About Me Card

Cover:

- No profile shows `讓 VibeSync 更像你的教練` and `開始設定`.
- Filled profile shows summary lines.
- Partial profile only shows filled fields.
- Tap `開始設定` routes to `/profile/about-me`.
- Tap `編輯` routes to `/profile/about-me`.

### Widget Tests: About Me Screen

Cover:

- Empty new profile shows `先略過`.
- Selecting style changes primary button to `儲存`.
- Practice goals max 3.
- Topic seeds max 5.
- Text fields trim / limit input.
- Existing profile pre-fills.
- Clearing all fields shows `清除設定`.
- Successful save returns to report page.
- Bottom privacy note renders.

### Explicitly Not Tested In Spec 1

- `analyze-chat` prompt injection.
- Edge Function behavior.
- OCR.
- Partner override.

## 12. Implementation Commit Plan

Recommended commits:

1. `[feat] UserProfile domain + Hive adapter`
2. `[feat] UserProfile repository + providers`
3. `[feat] Report About Me card`
4. `[feat] About Me edit screen`
5. `[docs] close Spec 1 implementation queue`

Final verification gate:

```bash
flutter test test/unit/features/user_profile/ test/widget/features/report/ test/widget/features/user_profile/
flutter analyze --no-fatal-infos lib test
```

Adjust paths to actual implementation.

## 13. Future Specs

Spec 2: Prompt Fallback Chain

- Build `UserProfileBlock`.
- Inject profile into prompt only when profile exists.
- Add no-profile regression proving old prompt behavior remains equivalent.
- Keep Edge prompt changes isolated.

Spec 3: Partner Data Quality Guard

- Detect mixed-person contamination in partner cards.
- Warn before injecting low-confidence partner aggregate memory.
- Provide move / split recovery paths.

Spec 4: Coach Action Loop v1

- Turn `nextStep` / `finalRecommendation` into concrete tasks.
- Examples: soft invite, lower-pressure reply, explain less, stop chasing, post-date follow-up.

## 14. Open Questions For Later

- Should v1.1 add a one-time hint after first successful analysis?
- Should Settings also link to About Me?
- Should telemetry track completion, edit, and clear rates?
- Should old `SessionContext` data be offered as an explicit import?

