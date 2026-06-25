# AI 實戰陪練女孩 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade `AI 實戰練習室` from a 10-reply generic practice room into a realistic dating-app style陪練女孩 experience: 1 quota = 20 AI replies, paid users can continue the same girl for another paid 20-reply round, Free users can start new girls within quota but cannot continue the same girl into round 2, each girl has profile/photo/profession/interests/reaction model, and debrief evaluates whether the user is moving toward「約出來」.

**Architecture:** Keep the existing Supabase Edge `practice-chat` server-side ledger as the billing authority. Flutter owns local visible-thread UX and Hive persistence. Client sends only allowlisted IDs and display metadata needed for UI; server owns persona/difficulty/reaction/signal prompt snippets. Profile photos live in Supabase Storage/CDN and are referenced by URL, not stored as DB binary or bundled in the app. No DB migration unless implementation discovers that current server ledger cannot support round continuation safely; if a migration becomes necessary, stop and get Eric approval first.

**Tech Stack:** Flutter 3.x, Riverpod, Hive CE, Supabase Edge Functions/Deno, DeepSeek API through existing `practice-chat`, RevenueCat subscription state, Supabase Storage/CDN for profile images.

---

## Reference Inputs

- Product spec: `docs/superpowers/specs/2026-06-25-practice-chat-20-turns-continue-date-goal-design.md`
- Current implementation plan baseline: `docs/superpowers/plans/2026-06-24-practice-chat-persona-difficulty-impl.md`
- Current practice client files:
  - `lib/features/practice_chat/domain/entities/practice_profile.dart`
  - `lib/features/practice_chat/domain/entities/practice_session.dart`
  - `lib/features/practice_chat/data/providers/practice_chat_providers.dart`
  - `lib/features/practice_chat/data/services/practice_chat_api_service.dart`
  - `lib/features/practice_chat/presentation/screens/practice_chat_screen.dart`
- Current practice Edge files:
  - `supabase/functions/practice-chat/practice_persona.ts`
  - `supabase/functions/practice-chat/validate.ts`
  - `supabase/functions/practice-chat/prompt.ts`
  - `supabase/functions/practice-chat/quota_decision.ts`
  - `supabase/functions/practice-chat/index.ts`
- Current paywall file:
  - `lib/features/subscription/presentation/screens/paywall_screen.dart`
- Candidate visual direction contact sheets already approved to use:
  - `C:\Users\eric1\.codex\generated_images\019ef7e2-fa73-71d3-850d-1197f8be8c05\vibesync_candidate_sets\set_01.png`
  - `C:\Users\eric1\.codex\generated_images\019ef7e2-fa73-71d3-850d-1197f8be8c05\vibesync_candidate_sets\set_02.png`
  - `C:\Users\eric1\.codex\generated_images\019ef7e2-fa73-71d3-850d-1197f8be8c05\vibesync_candidate_sets\set_03.png`
  - `C:\Users\eric1\.codex\generated_images\019ef7e2-fa73-71d3-850d-1197f8be8c05\vibesync_candidate_sets\set_04.png`
  - `C:\Users\eric1\.codex\generated_images\019ef7e2-fa73-71d3-850d-1197f8be8c05\vibesync_candidate_sets\set_05.png`

## Product Invariants

- One paid practice round costs exactly 1 quota and allows at most 20 AI replies.
- First successful AI reply in a new billing round deducts quota; failed DeepSeek generation does not deduct.
- Paid users can continue the same girl after 20 replies; continuation deducts another quota and grants another 20 AI replies.
- Free users cannot continue the same girl into round 2. They can still start a new girl if quota remains.
- Continue keeps the same `profileId`, `displayName`, `professionId`, `professionLabel`, `photoId`, `photoUrl`, `personaId`, and resolved `difficulty`.
- `換一位` changes the girl identity: `profileId`, name, photo, profession, persona, profile metadata, and reaction model. It keeps the current difficulty selection.
- Changing difficulty changes only the next not-yet-started round. It does not mutate the current girl after messages exist.
- Random difficulty resolves once into `easy`, `normal`, or `challenge`, then remains stable for that visible thread/round.
- MVP max visible-thread cap is 3 rounds, 60 AI replies. After that, guide the user to debrief/new girl instead of infinite continuation.
- All generated profile people are fictional adult women, age 22 or above. Do not use real people, real company logos, real airline uniforms, school uniforms, or brand identifiers.
- Server logs can include IDs such as `profileId`, `personaId`, and `difficulty`; server logs must never include prompt snippets, full profile reaction text, DeepSeek API key, or full chat transcript except existing approved debug paths.

## Profile And Persona Model

### Core Profile Fields

Implement a single profile shape that both client and server can represent safely:

```ts
type PracticeGirlProfile = {
  profileId: string;
  displayName: string;
  age: number;
  heightCm: number;
  city: string;
  zodiac: string;
  relationshipGoal: string;
  professionId: string;
  professionLabel: string;
  photoId: string;
  photoUrl: string;
  personaId: PersonaId;
  personalityTags: string[];
  interestTags: string[];
  lifestyleTags: string[];
  selfIntro: string;
  reactionModel: {
    likes: string[];
    dislikes: string[];
    warmsWhen: string[];
    coolsWhen: string[];
    inviteThreshold: string;
  };
  signalStyle: string[];
};
```

Flutter should have an equivalent Dart model for display and request metadata. Prompt-only fields may live server-side only. If keeping duplicated catalogs in client and Edge for MVP, add a test that every client `profileId` exists server-side and every profile references valid `personaId`, `professionId`, and `photoId`.

### MVP Profile Catalog Requirements

Create 60 fictional profiles using `practice_girl_001` through `practice_girl_060`, matching the five approved 12-image set directions.

Name pool should be English display names, with no duplicates inside the first 20:

```text
Alice, Ivy, Zoe, Mia, Chloe, Emma, Ava, Nina, Bella, Lily,
Ella, Yuna, Rina, Katie, Amber, Ruby, Grace, Claire, Vivian, Olivia,
Mandy, Natalie, Fiona, Celine, Wendy, Joyce, Ashley, Hannah, Emily, Ariel,
Jasmine, Peggy, Kelly, Joanne, Nicole, Tina, Cindy, Stella, Janet, Monica,
Sandy, Elaine, Vicky, Angela, Renee, Sophie, Annie, Dora, Nora, Phoebe,
Jessie, Sharon, Crystal, Sunny, April, Iris, Betty, Carol, Daphne, Teresa
```

Profession distribution:

```text
大學生 x 6
研究生 x 4
空服員 x 5
醫院護理師 x 5
診所護理師 x 4
牙醫助理 x 5
精品銷售 x 4
咖啡師 x 4
行銷企劃 x 4
設計師 x 4
瑜珈老師 x 4
健身教練 x 4
美甲師 x 4
活動公關 x 3
```

Interest/lifestyle variety must include at least these themes across the 60 profiles:

```text
旅行, 自助旅行, 美食, 咖啡, 烘焙, 做菜, 看書, 文青展覽, 藝術, 瑜珈,
健身, 戶外爬山, 沙灘陽光, 重機, 寵物, 搞笑表情, 拍照, 做指甲,
夜景散步, 工作生活平衡, 週末小旅行, 電影, 音樂祭, 潛水或海邊活動
```

Beauty/visual direction:

- Do not make all faces look like the same AI person. Vary eye shape, face shape, cheekbone, nose, hairstyle, body type, styling, expression, and scene.
- Mix attractive, pretty, cute, sporty, ordinary-realistic, mature, playful, and slightly awkward expressions.
- Some profiles can be visually attractive and fit, but avoid explicit sexual framing. Bikini/beach can exist as normal travel/summer context, cropped and tasteful.
- Fitness/yoga photos can show body shape but should read as lifestyle/profile-photo, not adult-content marketing.
- College/graduate profiles must look adult, age 22+.
- Airline/medical/professional looks must avoid real company marks and real uniforms.

### Difficulty Standards

Keep current difficulty IDs: `easy`, `normal`, `challenge`.

`easy`:

- Friendly, gives more repair space, responds to imperfect but respectful attempts.
- Still does not reward offensive, pressure-heavy, or creepy escalation.
- Can accept a date if user builds comfort, specificity, and low-pressure logistics.
- Should not be a guaranteed win.

`normal`:

- Realistic baseline. Does not over-help boring or generic messages.
- Requires actual attraction, comfort, shared context, or a plausible reason to meet.
- Gives mixed signals sometimes; user must read the context instead of assuming every warm line means she is ready.
- Too-fast邀約, interview mode, or weak rapport should lead to deflection or soft no.

`challenge`:

- Selective, higher standards, more likely to cold reply, refuse, tease, topic-shift, or push back.
- Does not rescue boring chat.
- Can use false windows, vague availability, or playful tests that weaker users may misread.
- Still allows success if user shows strong calibration, emotional availability, humor, boundaries, and good logistics.

All difficulties:

- Date outcome is determined by transcript quality, not by turn count.
- A strong user can get a high date chance in round 1.
- A medium user may need round 2.
- A user who becomes cold, aggressive, controlling, entitled, too sexual too fast, or goal-fixated should cool the girl down and receive debrief feedback.

### Signal And Misread Model

Add these concepts to the server prompt and debrief prompt. Do not expose these labels directly to the user in-character unless debriefing.

Signals the AI girl may produce:

- `主動窗口`: asks a question, shares availability, opens a topic, gives a reason to continue.
- `報備行程`: casually mentions schedule/location/life context. This is a possible connection point, not always an invitation.
- `脆弱性暴露`: shares tiredness, stress, insecurity, disappointment, or a softer emotional detail.
- `語氣試探`: teasing, sarcasm, mild challenge, “你都這樣喔?” style testing.
- `混合訊號`: warm and distant at the same time.
- `假窗口`: looks like an opening but is not enough to invite yet.

User skills being trained:

- `內容下切`: pick one concrete detail and go deeper naturally.
- `關係連結`: connect her detail to the user’s own real experience without hijacking.
- `在場感`: respond to the emotional subtext, not only literal content.
- `低壓邀約`: invite with context, specificity, and an easy out.

Debrief should flag:

- Missed down-cutting.
- Missed vulnerability.
- Goal-fixated invite.
- False-window misread.
- Cold/aggressive/controlling behavior.
- Interview mode.
- Over-agreement and weak frame.

## Implementation Tasks

### Batch 0: Preflight And Branch Hygiene

- [ ] Run the required VibeSync bootstrap.

```powershell
Get-Content docs/snapshot.md
Get-Content docs/shared-agent-rules.md
git log --oneline -15
Get-Content docs/reviews/ai-arbitration-queue.md -TotalCount 120
git status --short --branch
```

Expected:

```text
## main...origin/main
```

or only unrelated dirty files explicitly named before editing.

- [ ] Confirm implementation range before editing.

```powershell
git rev-parse --short HEAD
```

Record this base commit in the implementation closeout so Codex review can target `<base>..HEAD`.

- [ ] Inspect current practice tests before edits.

```powershell
rg -n "practice_chat|practice-chat|PracticeSession|PracticeProfile|MAX_AI_REPLIES|AI 模型|Sonnet AI" test supabase/functions/practice-chat lib/features/practice_chat lib/features/subscription/presentation/screens/paywall_screen.dart
```

Expected:

```text
supabase/functions/practice-chat/quota_decision.ts:... MAX_AI_REPLIES = 10
lib/features/practice_chat/data/providers/practice_chat_providers.dart:... kMaxPracticeAiReplies = 10
lib/features/subscription/presentation/screens/paywall_screen.dart:... Sonnet AI
```

### Batch 1: Edge Catalog, Validation, 20-Reply Cap

- [ ] Create server-owned profile catalog.

Modify or split from:

- `supabase/functions/practice-chat/practice_persona.ts`

Preferred shape:

- Keep `PersonaId`, `PracticeDifficulty`, and current `resolvePracticeProfile`.
- Add `PracticeGirlProfileId`, `PracticeProfessionId`, `PracticePhotoId`, `PracticeGirlProfile`.
- Add `GIRL_PROFILES` with 60 entries.
- Add `resolvePracticeProfile(args)` so it returns both existing persona/difficulty fields and optional girl fields.
- Old clients with no `profileId` still fallback to a valid default profile.

Minimum server return fields:

```ts
export interface PracticeProfile {
  personaId: PersonaId;
  personaLabel: string;
  personaPrompt: string;
  difficulty: PracticeDifficulty;
  difficultyLabel: string;
  difficultyPrompt: string;
  girl: PracticeGirlProfile;
}
```

- [ ] Add validation for profile metadata.

Modify:

- `supabase/functions/practice-chat/validate.ts`
- `supabase/functions/practice-chat/validate_test.ts`

Accept optional top-level request fields:

```json
{
  "profileId": "practice_girl_001",
  "professionId": "flight_attendant",
  "photoId": "practice_girl_001",
  "roundIndex": 1,
  "visiblePracticeThreadId": "local-visible-thread-id"
}
```

Rules:

- Invalid `profileId` throws `invalid_profileId`.
- Invalid `professionId` throws `invalid_professionId`.
- Invalid `photoId` throws `invalid_photoId`.
- If `profileId` exists, `professionId` and `photoId` must match that profile when provided.
- Missing fields fallback to default profile, default persona, and normal difficulty.
- `roundIndex` defaults to `1`, accepts only integer `1..3`.
- `visiblePracticeThreadId` is optional string, max 128 chars, never used as auth identity.

Tests:

```powershell
deno test --allow-env supabase/functions/practice-chat/validate_test.ts
```

Expected:

```text
ok | ... profile：合法 profileId 通過並解析 girl profile
ok | ... profile：非法 profileId → invalid_profileId
ok | ... profile：profession/photo mismatch → invalid_profile_metadata
ok | ... roundIndex：缺值 fallback 1
ok | ... roundIndex：4 → invalid_roundIndex
```

- [ ] Increase cap from 10 to 20.

Modify:

- `supabase/functions/practice-chat/quota_decision.ts`
- `supabase/functions/practice-chat/quota_decision_test.ts`

Change:

```ts
export const MAX_AI_REPLIES = 20;
```

Update comments and tests that assert `10`.

Command:

```powershell
deno test --allow-env supabase/functions/practice-chat/quota_decision_test.ts
```

Expected:

```text
20 passed
```

Do not change `PRACTICE_QUOTA_COST`; it remains `1`.

### Batch 2: Edge Prompt Quality, Date Goal, Debrief Schema

- [ ] Upgrade chat prompt profile injection.

Modify:

- `supabase/functions/practice-chat/prompt.ts`
- `supabase/functions/practice-chat/prompt_test.ts`

`buildProfilePrompt(profile)` must include:

- display name
- age
- city
- profession label
- self intro
- personality/interest/lifestyle tags
- persona prompt
- difficulty prompt
- reaction model
- signal/misread model
- instruction that she is the simulated girl, not the coach
- instruction not to announce metadata mechanically
- instruction not to mention photo appearance unless the user brings up profile/photo context

Prompt behavior to encode:

- AI is the woman being chatted with.
- She can be warm, playful, busy, uncertain, teasing, defensive, or cold depending on transcript and profile.
- She should not agree with everything.
- She should not reveal hidden labels like `false window`, `reactionModel`, or `difficulty`.
- She can accept a date only when user has earned enough comfort/interest/logistics for this profile and difficulty.
- If user is cold/aggressive/controlling/too sexual/too goal-fixated, cool down or refuse.

Tests should assert snippets exist without exact-matching the entire prompt:

```powershell
deno test --allow-env supabase/functions/practice-chat/prompt_test.ts
```

Expected:

```text
ok | ... buildChatMessages：system prompt 帶入 girl profile identity
ok | ... buildChatMessages：system prompt 帶入 reaction model
ok | ... buildChatMessages：system prompt 帶入 signal/misread model
ok | ... buildChatMessages：challenge 允許冷回/拒絕/推回
ok | ... buildChatMessages：不要求自我介紹 metadata
```

- [ ] Upgrade debrief schema and parser.

Modify:

- `supabase/functions/practice-chat/prompt.ts`
- `supabase/functions/practice-chat/index.ts`
- `supabase/functions/practice-chat/debrief_card_test.ts`
- `lib/features/practice_chat/data/services/practice_chat_api_service.dart`
- `lib/features/practice_chat/domain/entities/practice_session.dart`
- `lib/features/practice_chat/data/providers/practice_chat_providers.dart`
- `lib/features/practice_chat/presentation/screens/practice_chat_screen.dart`

Edge debrief JSON must include existing fields plus:

```json
{
  "dateChance": "low | medium | high",
  "dateChanceReason": "why the current transcript is or is not ready to invite",
  "nextInviteMove": "the next concrete move if the user wants to move toward meeting"
}
```

Parser rules:

- Unknown or malformed `dateChance` defaults to `medium` only if there is useful reason text; otherwise default `low`.
- Trim all strings.
- Cap `dateChanceReason` and `nextInviteMove` to user-facing short paragraphs.
- Existing old card fields remain backward-compatible.

Tests:

```powershell
deno test --allow-env supabase/functions/practice-chat/debrief_card_test.ts
flutter test test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart
```

Expected:

```text
ok | parses dateChance/dateChanceReason/nextInviteMove
ok | malformed dateChance falls back safely
```

### Batch 3: Free/Paid Continuation Gate

- [ ] Decide whether continuation is enforced client-only or Edge also checks tier.

Preferred MVP:

- Client gates Free continuation using current RevenueCat/subscription provider.
- Edge accepts `roundIndex` for logging/prompt only, because current `practice-chat` ledger charges per `sessionId` and tier-aware gating may not already exist in this Edge function.
- If Edge already has reliable tier context from quota helpers, add a server-side Free `roundIndex > 1` `upgrade_required` response.
- If Edge lacks reliable tier context, do not add a fake server tier check. Keep client gate and document residual risk in closeout.

Stop condition:

- If enforcing Free continuation server-side requires a DB migration or new subscription lookup path, stop and ask Eric before expanding scope.

- [ ] Add continuation request metadata.

Modify:

- `supabase/functions/practice-chat/validate.ts`
- `supabase/functions/practice-chat/index.ts`
- `lib/features/practice_chat/data/services/practice_chat_api_service.dart`
- `test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart`

`PracticeProfileDto` or new DTO must send:

```dart
{
  'profileId': profileId,
  'professionId': professionId,
  'photoId': photoId,
  'personaId': personaId,
  'difficulty': difficulty,
  'roundIndex': roundIndex,
  'visiblePracticeThreadId': visiblePracticeThreadId,
}
```

Tests:

```powershell
flutter test test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart
```

Expected:

```text
sendMessage body includes profileId/professionId/photoId/roundIndex/visiblePracticeThreadId
requestDebrief body includes same profile metadata
```

### Batch 4: Flutter Profile Catalog, Hive, State Machine

- [ ] Extend Flutter profile models.

Modify:

- `lib/features/practice_chat/domain/entities/practice_profile.dart`

Add:

- `PracticeGirlProfile`
- `PracticeProfession`
- `PracticePhoto`
- 60 profile metadata entries matching the server IDs
- a `createPracticeProfile()` that randomizes full girl profile plus persona and difficulty
- `fallbackPracticeProfile()` that returns a complete profile
- helpers to change girl while keeping difficulty
- helpers to change difficulty while keeping girl

Client catalog should include display fields and `photoUrl`. Do not include prompt snippets or reaction-model private prompt text if the UI does not need it.

- [ ] Extend Hive session safely.

Modify:

- `lib/features/practice_chat/domain/entities/practice_session.dart`
- regenerate `lib/features/practice_chat/domain/entities/practice_session.g.dart`
- `test/unit/features/practice_chat/data/repositories/practice_session_repository_test.dart`

Append new Hive fields after current field `12`; do not renumber existing fields.

Add nullable fields:

```dart
profileId
displayName
age
heightCm
city
zodiac
relationshipGoal
personalityTags
interestTags
lifestyleTags
selfIntro
professionId
professionLabel
photoId
photoUrl
roundIndex
roundAiReplyCount
maxRounds
dateChance
dateChanceReason
nextInviteMove
```

Use nullable fields and fallback for legacy local sessions.

Command:

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter test test/unit/features/practice_chat/data/repositories/practice_session_repository_test.dart
```

Expected:

```text
save 後可持久化 full girl profile metadata
舊 local session 缺 profile fields 時 fallback safely
```

- [ ] Implement controller round state.

Modify:

- `lib/features/practice_chat/data/providers/practice_chat_providers.dart`
- `test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart`

State additions:

```dart
int roundIndex;          // starts 1
int roundAiReplyCount;   // 0..20 for current round
int maxRounds;           // 3
bool get roundComplete => roundAiReplyCount >= kMaxPracticeAiReplies;
bool get canContinuePaid => roundComplete && roundIndex < maxRounds;
```

Implementation rules:

- `kMaxPracticeAiReplies = 20`.
- `aiReplyCount` remains total visible-thread AI replies for local display.
- `roundAiReplyCount` tracks current paid round.
- On send success, use server `aiTurnCount` as current billing-session count; total count increments based on appended AI replies or explicit returned total if added.
- To continue same girl, create a fresh billing `sessionId` for Edge if current server ledger is capped, but preserve a stable `visiblePracticeThreadId` in Hive/state.
- Store full visible transcript in Hive.
- Continue resets `roundAiReplyCount` to `0`, increments `roundIndex`, clears round-complete error, keeps same profile.
- Free `continue` opens paywall and does not mutate messages.
- `換一位` before first message changes full girl identity and persona but keeps difficulty.
- At round complete, allow user to choose `續玩 20 則`, `教練拆解`, or `換一位`.

Tests:

```powershell
flutter test test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart
```

Expected:

```text
new session starts with full girl profile
20 replies marks roundComplete
paid continue keeps same profile and increments roundIndex
free continue opens paywall path without changing state
換一位 changes profile/persona/photo/profession and keeps difficulty
change difficulty keeps same profile identity
old session fallback remains readable
```

### Batch 5: Flutter UI And Paywall

- [ ] Update practice chat screen profile UX.

Modify:

- `lib/features/practice_chat/presentation/screens/practice_chat_screen.dart`
- `test/widget/features/practice_chat/practice_chat_screen_style_test.dart`

Opening screen should show:

```text
本場對象：Alice · 空服員 · 幽默吐槽型 · 一般
```

Profile card should show:

- circular or softly rounded profile photo
- display name
- age
- profession
- city
- tags: interests/lifestyle/personality
- copy: `對方是有個性的模擬對象，不是教練。傳第一句出去，看看她怎麼回。`
- quota copy: `首次 AI 回覆成功才扣 1 則；本輪最多 20 則 AI 回覆。教練拆解不另扣。`

During a round:

```text
本輪還能聊 17 則
首次 AI 回覆成功才扣 1 則
```

After first AI reply:

```text
本輪已扣 1 則，還能聊 17 則
```

At 20 replies:

```text
這輪聊滿 20 則
```

Paid CTA:

```text
續玩 20 則
```

Free CTA:

```text
升級後續玩 20 則
```

Secondary CTA:

```text
教練拆解
換一位
```

Debrief display should include:

```text
約出來機會：低 / 中 / 高
原因：...
下一步邀約動作：...
```

Do not add visible instructional text explaining implementation details, prompt rules, keyboard shortcuts, or hidden labels.

- [ ] Add image loading.

Use existing app image tooling if available. If no existing cache wrapper exists, add `cached_network_image` only if already in `pubspec.yaml`; otherwise use `Image.network` with a stable placeholder/error builder to avoid dependency churn.

Photo UX rules:

- Do not block sending a first message if image loading is slow.
- Use fixed dimensions/aspect ratio so loading/error states do not shift layout.
- Use tasteful crop; avoid full-screen glamour layout in the practice room.

Widget tests:

```powershell
flutter test test/widget/features/practice_chat/practice_chat_screen_style_test.dart
```

Expected:

```text
new room shows girl name, profession, difficulty, and profile card
round complete shows paid/free continuation CTA based on tier override
debrief renders dateChance fields
```

- [ ] Update paywall comparison and bullets.

Modify:

- `lib/features/subscription/presentation/screens/paywall_screen.dart`

Feature comparison:

```text
AI 陪練女孩 | 限量 | 開放 | 開放
AI 模型 | 經濟型 | 高階型 | 高階型
```

Starter/Essential card bullet replacement:

```text
五種風格全開 + 高階 AI
```

Remove user-facing `Haiku`, `Sonnet`, or model-brand copy from this paywall surface.

Tests:

```powershell
rg -n "Haiku|Sonnet|Sonnet AI" lib/features/subscription/presentation/screens/paywall_screen.dart
```

Expected:

```text
no matches
```

Run subscription/paywall widget tests if present:

```powershell
flutter test test/widget/features/subscription
```

If that path has no tests, record `not present` in closeout and run targeted analyze.

### Batch 6: Asset Pipeline

- [ ] Do not use the contact sheets directly in the app.

The five approved contact sheets are direction only. Production app assets must be 60 individual images, not 12-up sheets.

- [ ] Prepare 60 individual fictional adult profile images.

Generation requirements:

- Square final crop, `512x512`.
- WebP output.
- Target 40-90 KB per image after compression.
- File names:

```text
practice_girl_001.webp
practice_girl_002.webp
...
practice_girl_060.webp
```

- [ ] Upload to Supabase Storage/CDN.

Suggested bucket/path:

```text
practice-profiles/v1/practice_girl_001.webp
```

Add the final public URLs to the Flutter/server catalog.

Validation command after URLs are added:

```powershell
rg -n "practice_girl_0(01|30|60)|photoUrl" lib/features/practice_chat supabase/functions/practice-chat
```

Expected:

```text
profile catalog includes photoUrl for 001, 030, and 060
```

- [ ] If final images are not ready at code implementation time, use approved CDN placeholder URLs for all profiles only if Eric explicitly accepts a staged rollout. Do not ship broken image URLs.

### Batch 7: Verification, Review, Deploy

- [ ] Run Edge targeted suite.

```powershell
deno test --allow-env supabase/functions/practice-chat/validate_test.ts supabase/functions/practice-chat/prompt_test.ts supabase/functions/practice-chat/deepseek_test.ts supabase/functions/practice-chat/debrief_card_test.ts supabase/functions/practice-chat/quota_decision_test.ts
deno check supabase/functions/practice-chat/index.ts
```

Expected:

```text
0 failed
Check file:///.../supabase/functions/practice-chat/index.ts
```

- [ ] Run Flutter targeted suite.

```powershell
flutter test test/unit/features/practice_chat
flutter test test/widget/features/practice_chat
flutter analyze
```

Expected:

```text
All tests passed
No issues found!
```

- [ ] Confirm no Supabase migration unless explicitly approved.

```powershell
git diff --name-only <base>..HEAD -- supabase/migrations
```

Expected:

```text
no output
```

If there is output, stop and explain why migration was necessary before deploy.

- [ ] Commit in small concerns.

Recommended commits:

```text
feat(practice): 建立陪練女孩個人檔案 catalog
feat(practice-chat): 擴充陪練 prompt 與 20 則上限
feat(practice): 支援同一位續玩與 Free 續玩門檻
feat(practice): 顯示陪練女孩檔案與約出來拆解
feat(subscription): 更新陪練與 AI 模型付費文案
```

- [ ] Request Codex review before saying dogfood-safe.

Review scope:

```text
<implementation-base>..HEAD
```

Review focus:

- quota/cost correctness
- Free cannot continue same girl
- paid continue charges again
- Edge prompt/schema compatibility
- Hive backward compatibility
- image URL/loading UX
- no prompt injection via client profile fields
- no real-person/brand leakage in profile assets

- [ ] Deploy only after review and Eric/owner approval.

If pushed to `main`, Edge auto-deploy may run. Confirm:

```powershell
gh run list --workflow "Deploy Edge Function" --limit 3
```

Expected:

```text
completed success
```

Do not declare TestFlight dogfood-safe until:

- Edge deploy is green.
- iOS/TestFlight rebuild with new Flutter code is complete.
- Real-device smoke passes.

## Real-Device Smoke Checklist

- [ ] New practice room shows profile photo, English name, age/profession/tags, persona, and difficulty.
- [ ] `換一位` changes girl/name/photo/profession/persona but keeps selected difficulty.
- [ ] Difficulty chip changes difficulty but keeps same girl before first message.
- [ ] First user message does not deduct until first AI reply succeeds.
- [ ] After first AI reply, quota text says the round has charged 1.
- [ ] Round allows 20 AI replies, not 10.
- [ ] At 20 replies, input is locked and continuation/debrief CTAs appear.
- [ ] Paid continuation keeps same girl and starts another 20-reply round.
- [ ] Paid continuation deducts 1 more quota on first successful AI reply of round 2.
- [ ] Free continuation opens upgrade/paywall and does not continue same girl.
- [ ] Free can still start a new girl if quota remains.
- [ ] Leaving mid-round and returning resumes the same visible thread.
- [ ] Leaving after round complete and returning still allows continue/debrief.
- [ ] Debrief includes `約出來機會`, reason, and next invite move.
- [ ] Challenge difficulty does not blindly agree and can push back/refuse.
- [ ] Normal difficulty is not too easy to ask out.
- [ ] Old local practice sessions still open without crashing.

## Failure Matrix

| Risk | Required Behavior |
| --- | --- |
| DeepSeek fails before first reply | No quota charge, user message restored or retryable |
| Server ledger says cap reached | Client locks input and shows continue/debrief path |
| Free user presses continue | Opens paywall, no new billing session, no lost messages |
| Paid user presses continue but quota exhausted | Shows quota/paywall path, keeps transcript |
| User switches girl before first message | New profile/persona/photo, same difficulty |
| User switches difficulty before first message | Same profile/persona/photo, new resolved difficulty |
| User leaves mid-round | Same visible thread resumes |
| Old Hive row lacks new fields | Fallback full profile loads safely |
| Bad client sends fake profileId | Edge rejects or falls back according to validation rules, never accepts prompt text |
| Asset URL fails | UI shows stable placeholder, sending still works |

## Plan Self-Review

- Spec coverage: 20 replies, paid continuation, Free no same-girl continuation, same-girl continuation, `換一位`, random names, professions, photos, paywall copy, debrief date chance, realistic signal/misread, and difficulty standards are all represented.
- No open placeholders: all IDs, fields, commands, and expected behaviors are concrete.
- Risk handling: quota/cost, Edge schema, AI prompt, Hive persistence, and paywall changes are marked high-risk and require Codex review before dogfood-safe.
- Data boundary: client never sends prompt text; server owns hidden prompt/reaction/signal interpretation; photos are CDN URLs, not DB binary or bundled assets.
