# Practice Beginner Temperature Hint Implementation Plan

## 2026-07-03 實作對齊補記

> 本計畫是動工前版本，原文照留。實作已完成（雙軸升溫版）並於 2026-07-03 再修一輪風險；以下逐條記錄最終實作與本計畫的差異，日後讀者以補記為準。

- **temperature 模組實作與本計畫不同**：最終為「雙軸升溫」＝temperature（熱度）＋familiarity（熟悉度），judge 是 classifier（category/quality/impact 矩陣換算 delta），非本文 `parseTemperatureJudgement` 直接收 delta 的設計；clamp 為 heat [-12,+8]、familiarity [-12,+12]（越界強制 ≤-6），本文「delta clamp -8..8」相關步驟作廢。
- **RPC 授權策略與本文不同（原文作廢）**：本文「Grant execution to the service role and authenticated role」一句作廢——實際 migration 全部 REVOKE anon/authenticated、GRANT service_role only（比照 `20260624120000` 現行風格）。
- **RPC 簽名策略（與原文不同）**：不留 overload。`commit_practice_chat_turn` 現役唯一簽名為 7-arg；本文的 6-arg overload 與更舊的 3/4-arg 簽名已由 migration `20260703160000` DROP（該 migration 須在新 Edge 部署後才套用）。
- **client temperatureScore 已被忽略（與原文不同）**：本文 Step 4 的 `p_initial_temperature_score: request.temperatureScore` 語義已被取代——server 一律 ledger 權威（首回合固定 30），standard 模式 commit 傳 null。
- **hint 冪等已實作（原文未涵蓋）**：client 產 requestId（失敗沿用、成功才 rotate）＋server ledger replay（`last_hint_request_id`/`last_hint_result` 欄位，migration `20260703150000`），replay 命中不重扣、不重生成。
- **mode locked 已實作**：server 回 409＋`practice_mode_locked`（同本文 Step 4 mapping），client 已補分流——不誤標 session complete、不誤導續聊。
- **hint gate 已擋聊滿（原文未列）**：`aiCount >= 20` → 409 `practice_session_complete`；hint 上限 5/回合維持 server-side 為準。
- **judge 獨立常數（原文未列）**：`TEMPERATURE_JUDGE_MAX_TOKENS=450`、temp 0.2、timeout 30s、失敗 fallback delta 0（溫度不動）；judge prompt 已含防注入（recentContext 標 untrusted data）。
- **client 併發防護（原文未列）**：hint 在途禁送 chat（canSend）、過期 hint 回應以 generation 序號丟棄。
- **成本結構認列**：beginner 每回合 2 次 DeepSeek call（chat 200tok＋judge 450tok）、hint 1 call 650tok 扣 1 額度；一場滿載約 48 calls、最多 6 額度（1 chat＋5 hint）。
- **部署順序（新增，取代本文 Step 14）**：migration `20260703150000`（hint replay 欄位）→ 部署新 practice-chat Edge → migration `20260703160000`（DROP 舊簽名）。順序不可倒置，否則舊 Edge 會呼叫已被 DROP 的簽名。

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` for parallel implementation when possible, or `superpowers:executing-plans` for single-agent implementation. Track this plan with the checkbox items below and keep one commit per concern.

**Goal:** Add a beginner learning mode to AI 實戰練習室 with a live 升溫指數, temperature-influenced practice replies, and paid on-demand hint coaching while preserving the existing 實戰 mode.

**Architecture:** Extend the existing Flutter practice-chat state and Supabase `practice-chat` Edge Function with a beginner-only contract. Chat remains the source of truth for successful practice turns; a post-reply temperature judge updates beginner sessions, and a new `hint` mode charges quota only after a valid hint response is produced. Standard mode falls back for old clients and old Hive sessions, so the current practice experience remains unchanged.

**Tech Stack:** Flutter 3.x, Riverpod, Hive CE, Supabase Edge Functions on Deno TypeScript, Supabase Postgres RPC, DeepSeek chat completions, existing subscription quota helpers.

---

## Product Contract

This plan implements the approved spec in `docs/superpowers/specs/2026-06-28-practice-beginner-temperature-hint-design.md`.

Locked behavior:

- The practice room entry shows a pre-message mode switch: `實戰` and `新手`.
- Existing behavior is `實戰` and remains the default for old sessions and old clients.
- Mode is locked after the first user message in a round.
- `新手` mode starts at `升溫指數 30/100`.
- Temperature is free and updated after successful AI replies.
- Temperature affects the next AI reply through broad prompt bands, using the 3-lite model.
- Hint is available only in `新手` mode, only after at least one AI reply, and only when the latest turn is AI.
- Each successful hint generation deducts 1 message.
- Failed hint generation, invalid hint payload, timeout, quota rejection, or server gate rejection does not deduct quota.
- Each round allows at most 5 successful hints, enforced server-side.
- Hint returns exactly two fill-input replies and one read-only teaching note:
  - `升溫回覆`
  - `穩住回覆`
  - `這邊該怎麼回覆的心法`
- Tapping a hint reply fills the input and does not auto-send.
- Hint content is not appended to transcript unless the user sends it.

## Safety Rules

- Do not run `supabase db push`.
- Create a migration file and apply it only through the established Supabase migration path for this repo.
- `analyze-chat`, opener, subscription, RevenueCat, and unrelated Edge Functions are out of scope.
- Keep standard practice prompts free of beginner temperature instructions.
- Do not trust client-sent `temperatureScore` or `hintUsedCount` as authoritative. Server ledger wins.
- Do not store hint coaching or hint options in Hive transcript.
- Preserve all old Hive sessions by using nullable fields and defaults.

## Files To Modify

Backend:

- `supabase/migrations/20260628120000_practice_beginner_temperature_hint.sql`
- `supabase/functions/practice-chat/index.ts`
- `supabase/functions/practice-chat/validate.ts`
- `supabase/functions/practice-chat/quota_decision.ts`
- `supabase/functions/practice-chat/prompt.ts`
- `supabase/functions/practice-chat/temperature.ts`
- `supabase/functions/practice-chat/hint.ts`
- `supabase/functions/practice-chat/validate_test.ts`
- `supabase/functions/practice-chat/quota_decision_test.ts`
- `supabase/functions/practice-chat/prompt_test.ts`
- `supabase/functions/practice-chat/temperature_test.ts`
- `supabase/functions/practice-chat/hint_test.ts`
- `supabase/functions/practice-chat/index_test.ts`

Flutter:

- `lib/features/practice_chat/domain/entities/practice_learning_mode.dart`
- `lib/features/practice_chat/domain/entities/practice_temperature.dart`
- `lib/features/practice_chat/domain/entities/practice_hint.dart`
- `lib/features/practice_chat/domain/entities/practice_session.dart`
- `lib/features/practice_chat/domain/entities/practice_session.g.dart`
- `lib/features/practice_chat/data/services/practice_chat_api_service.dart`
- `lib/features/practice_chat/data/providers/practice_chat_providers.dart`
- `lib/features/practice_chat/presentation/screens/practice_chat_screen.dart`
- `test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart`
- `test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart`
- `test/unit/features/practice_chat/data/repositories/practice_session_repository_test.dart`
- `test/widget/features/practice_chat/practice_chat_screen_style_test.dart`

Docs:

- `docs/bug-log.md` only if implementation uncovers a bug or production-risk decision worth durable history.
- `docs/reviews/ai-arbitration-queue.md` only if Codex review produces an OPEN item.

## Data Model

Add beginner ledger fields to `practice_chat_sessions`:

```sql
ALTER TABLE public.practice_chat_sessions
  ADD COLUMN IF NOT EXISTS practice_mode TEXT NOT NULL DEFAULT 'standard',
  ADD COLUMN IF NOT EXISTS temperature_score INTEGER,
  ADD COLUMN IF NOT EXISTS hint_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS temperature_updated_at TIMESTAMPTZ;

ALTER TABLE public.practice_chat_sessions
  DROP CONSTRAINT IF EXISTS practice_chat_sessions_practice_mode_check;

ALTER TABLE public.practice_chat_sessions
  ADD CONSTRAINT practice_chat_sessions_practice_mode_check
  CHECK (practice_mode IN ('standard', 'beginner'));

ALTER TABLE public.practice_chat_sessions
  DROP CONSTRAINT IF EXISTS practice_chat_sessions_temperature_score_check;

ALTER TABLE public.practice_chat_sessions
  ADD CONSTRAINT practice_chat_sessions_temperature_score_check
  CHECK (temperature_score IS NULL OR temperature_score BETWEEN 0 AND 100);

ALTER TABLE public.practice_chat_sessions
  DROP CONSTRAINT IF EXISTS practice_chat_sessions_hint_count_check;

ALTER TABLE public.practice_chat_sessions
  ADD CONSTRAINT practice_chat_sessions_hint_count_check
  CHECK (hint_count BETWEEN 0 AND 5);
```

Create a new 6-argument overload for chat commits:

```sql
CREATE OR REPLACE FUNCTION public.commit_practice_chat_turn(
  p_user_id UUID,
  p_session_id TEXT,
  p_charge_quota BOOLEAN,
  p_max_replies INTEGER,
  p_practice_mode TEXT,
  p_initial_temperature_score INTEGER
)
RETURNS TABLE(new_ai_count INTEGER, did_charge BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.practice_chat_sessions%ROWTYPE;
  v_mode TEXT := COALESCE(NULLIF(p_practice_mode, ''), 'standard');
  v_initial_temperature INTEGER := LEAST(GREATEST(COALESCE(p_initial_temperature_score, 30), 0), 100);
BEGIN
  IF v_mode NOT IN ('standard', 'beginner') THEN
    RAISE EXCEPTION 'PRACTICE_INVALID_MODE';
  END IF;

  INSERT INTO public.practice_chat_sessions (
    user_id,
    session_id,
    ai_count,
    charged,
    debrief_count,
    practice_mode,
    temperature_score,
    hint_count
  )
  VALUES (
    p_user_id,
    p_session_id,
    0,
    FALSE,
    0,
    v_mode,
    CASE WHEN v_mode = 'beginner' THEN v_initial_temperature ELSE NULL END,
    0
  )
  ON CONFLICT (user_id, session_id) DO NOTHING;

  SELECT * INTO v_existing
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF v_existing.ai_count >= p_max_replies THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_COMPLETE';
  END IF;

  IF v_existing.practice_mode <> v_mode THEN
    RAISE EXCEPTION 'PRACTICE_MODE_LOCKED';
  END IF;

  did_charge := FALSE;
  IF NOT v_existing.charged AND p_charge_quota THEN
    PERFORM public.increment_usage(p_user_id, 1);
    did_charge := TRUE;
  END IF;

  UPDATE public.practice_chat_sessions
  SET
    ai_count = ai_count + 1,
    charged = TRUE,
    practice_mode = v_mode,
    temperature_score = CASE
      WHEN v_mode = 'beginner' THEN COALESCE(temperature_score, v_initial_temperature)
      ELSE NULL
    END,
    updated_at = NOW()
  WHERE user_id = p_user_id AND session_id = p_session_id
  RETURNING ai_count INTO new_ai_count;

  RETURN NEXT;
END;
$$;
```

Create an RPC for successful hints:

```sql
CREATE OR REPLACE FUNCTION public.record_practice_hint(
  p_user_id UUID,
  p_session_id TEXT,
  p_charge_quota BOOLEAN,
  p_max_hints INTEGER
)
RETURNS TABLE(new_hint_count INTEGER, did_charge BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing public.practice_chat_sessions%ROWTYPE;
BEGIN
  SELECT * INTO v_existing
  FROM public.practice_chat_sessions
  WHERE user_id = p_user_id AND session_id = p_session_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_existing.charged OR v_existing.ai_count < 1 THEN
    RAISE EXCEPTION 'PRACTICE_SESSION_NOT_STARTED';
  END IF;

  IF v_existing.practice_mode <> 'beginner' THEN
    RAISE EXCEPTION 'PRACTICE_HINT_BEGINNER_ONLY';
  END IF;

  IF v_existing.hint_count >= p_max_hints THEN
    RAISE EXCEPTION 'PRACTICE_HINT_LIMIT';
  END IF;

  did_charge := FALSE;
  IF p_charge_quota THEN
    PERFORM public.increment_usage(p_user_id, 1);
    did_charge := TRUE;
  END IF;

  UPDATE public.practice_chat_sessions
  SET hint_count = hint_count + 1, updated_at = NOW()
  WHERE user_id = p_user_id AND session_id = p_session_id
  RETURNING hint_count INTO new_hint_count;

  RETURN NEXT;
END;
$$;
```

Create an RPC for temperature persistence:

```sql
CREATE OR REPLACE FUNCTION public.update_practice_temperature(
  p_user_id UUID,
  p_session_id TEXT,
  p_temperature_score INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_score INTEGER := LEAST(GREATEST(COALESCE(p_temperature_score, 30), 0), 100);
BEGIN
  UPDATE public.practice_chat_sessions
  SET
    temperature_score = v_score,
    temperature_updated_at = NOW(),
    updated_at = NOW()
  WHERE user_id = p_user_id
    AND session_id = p_session_id
    AND practice_mode = 'beginner';
END;
$$;
```

Grant execution to the service role and authenticated role following the current migration style in `supabase/migrations/20260624120000_practice_chat_sessions.sql`.

## API Contract

`chat` request additions:

```json
{
  "mode": "chat",
  "practiceMode": "beginner",
  "temperatureScore": 30
}
```

`chat` response additions only for beginner mode:

```json
{
  "temperature": {
    "score": 33,
    "delta": 3,
    "band": "cold",
    "reason": "有接住對方給的資訊，並維持低壓力追問。"
  },
  "hintUsedCount": 0
}
```

`hint` request:

```json
{
  "mode": "hint",
  "sessionId": "uuid",
  "practiceMode": "beginner",
  "turns": [
    { "role": "user", "text": "..." },
    { "role": "ai", "text": "..." }
  ],
  "personaId": "cool_foodie",
  "difficulty": "normal",
  "profileId": "practice_girl_001",
  "roundIndex": 1,
  "visiblePracticeThreadId": "uuid"
}
```

`hint` response:

```json
{
  "replies": [
    {
      "type": "warm_up",
      "label": "升溫回覆",
      "text": "那我先查朧月。你如果只推一道，會推熟成魚還是酒單？"
    },
    {
      "type": "steady",
      "label": "穩住回覆",
      "text": "好，我自己查。你剛剛提到酒單，看起來你蠻懂這類店。"
    }
  ],
  "coaching": "她願意給店名代表還有一點互動空間。先接住資訊，再問一個具體但低壓力的問題。",
  "costDeducted": 1,
  "hintUsedCount": 1,
  "monthlyRemaining": 123,
  "dailyRemaining": 12,
  "provider": "deepseek",
  "model": "deepseek-v4-flash",
  "generatedAt": "2026-06-28T00:00:00.000Z"
}
```

Error mapping:

- `invalid_mode`: HTTP 400.
- `practice_session_not_started`: HTTP 403.
- `practice_hint_beginner_only`: HTTP 403.
- `practice_hint_not_available`: HTTP 403.
- `practice_hint_limit`: HTTP 403.
- `practice_session_complete`: HTTP 409.
- quota exceeded: HTTP 429 with existing quota payload.
- generation failure or malformed DeepSeek JSON: HTTP 500 and no quota deduction.

## Backend Steps

### 1. Add Contract Tests For Request Validation

- [ ] Update `supabase/functions/practice-chat/validate_test.ts`.

Test cases:

- Missing `practiceMode` on `chat` returns `practiceMode: "standard"`.
- `practiceMode: "standard"` is accepted.
- `practiceMode: "beginner"` is accepted.
- Invalid `practiceMode` throws `invalid_practiceMode`.
- `temperatureScore` accepts integers from 0 to 100.
- Missing `temperatureScore` on beginner falls back to 30.
- Invalid temperature throws `invalid_temperatureScore`.
- `mode: "hint"` is accepted.
- Hint with no AI turns throws `invalid_hint_no_ai_turns`.
- Hint whose latest turn is not AI throws `invalid_hint_last_turn_must_be_ai`.
- Chat still requires latest turn to be user.

Run:

```powershell
deno test --allow-env supabase/functions/practice-chat/validate_test.ts
```

Expected before implementation: failing tests for `practiceMode`, `temperatureScore`, and `hint`.

- [ ] Update `supabase/functions/practice-chat/validate.ts`.

Implementation details:

- Extend `PracticeMode` in `quota_decision.ts` to include `"hint"`.
- Add `PracticeLearningMode = "standard" | "beginner"` in `validate.ts` or import it from `quota_decision.ts`.
- Add `practiceMode: PracticeLearningMode` and `temperatureScore: number` to `PracticeChatRequest`.
- Normalize missing `practiceMode` to `"standard"`.
- Normalize missing beginner `temperatureScore` to `30`.
- For standard mode, keep `temperatureScore` parsed but unused by handler.
- For hint mode, require at least one AI turn and latest turn AI.

Run again:

```powershell
deno test --allow-env supabase/functions/practice-chat/validate_test.ts
```

Expected after implementation: all validation tests pass.

Commit:

```powershell
git add supabase/functions/practice-chat/validate.ts supabase/functions/practice-chat/validate_test.ts supabase/functions/practice-chat/quota_decision.ts
git commit -m "test(practice-chat): 補上新手模式請求驗證"
```

### 2. Add Ledger Migration And Gate Tests

- [ ] Create `supabase/migrations/20260628120000_practice_beginner_temperature_hint.sql`.

The migration must include:

- New columns on `practice_chat_sessions`.
- Check constraints for mode, temperature, and hint count.
- 6-argument `commit_practice_chat_turn`.
- `record_practice_hint`.
- `update_practice_temperature`.
- Execution grants matching the existing practice-chat migration style.

- [ ] Update `supabase/functions/practice-chat/quota_decision_test.ts`.

Test cases:

- Existing chat gate behavior is unchanged.
- Hint gate rejects missing ledger.
- Hint gate rejects `charged: false`.
- Hint gate rejects `aiCount: 0`.
- Hint gate rejects `practiceMode: "standard"`.
- Hint gate rejects `hintCount >= 5`.
- Hint gate allows beginner ledger with `charged: true`, `aiCount >= 1`, and `hintCount < 5`.
- `MAX_HINTS_PER_ROUND` is 5.

- [ ] Update `supabase/functions/practice-chat/quota_decision.ts`.

Implementation details:

```ts
export const MAX_HINTS_PER_ROUND = 5;
export type PracticeMode = "chat" | "debrief" | "hint";
export type PracticeLearningMode = "standard" | "beginner";

export interface SessionLedger {
  exists: boolean;
  aiCount: number;
  charged: boolean;
  debriefCount: number;
  practiceMode: PracticeLearningMode;
  temperatureScore: number | null;
  hintCount: number;
}

export function decideHintGate(opts: {
  ledger: SessionLedger;
  maxHints?: number;
}): { allowed: boolean; reason?: string } {
  const max = opts.maxHints ?? MAX_HINTS_PER_ROUND;
  const { exists, charged, aiCount, practiceMode, hintCount } = opts.ledger;
  if (!exists || !charged || aiCount < 1) {
    return { allowed: false, reason: "practice_session_not_started" };
  }
  if (practiceMode !== "beginner") {
    return { allowed: false, reason: "practice_hint_beginner_only" };
  }
  if (hintCount >= max) {
    return { allowed: false, reason: "practice_hint_limit" };
  }
  return { allowed: true };
}
```

Run:

```powershell
deno test --allow-env supabase/functions/practice-chat/quota_decision_test.ts
```

Expected after implementation: all quota decision tests pass.

Commit:

```powershell
git add supabase/migrations/20260628120000_practice_beginner_temperature_hint.sql supabase/functions/practice-chat/quota_decision.ts supabase/functions/practice-chat/quota_decision_test.ts
git commit -m "feat(practice-chat): 新增新手模式 ledger 閘門"
```

### 3. Add Temperature Module And Prompt Bands

- [ ] Create `supabase/functions/practice-chat/temperature_test.ts`.

Test cases:

- `clampTemperature(-5)` returns 0.
- `clampTemperature(101)` returns 100.
- `temperatureBandFor(0)` returns `frozen`.
- `temperatureBandFor(25)` returns `cold`.
- `temperatureBandFor(50)` returns `neutral`.
- `temperatureBandFor(70)` returns `warm`.
- `temperatureBandFor(95)` returns `hot`.
- `applyTemperatureDelta(30, 4)` returns 34.
- `parseTemperatureJudgement` accepts valid JSON and clamps delta to `-8..8`.
- `parseTemperatureJudgement` rejects missing `delta`.
- `parseTemperatureJudgement` trims reason to a short string.

- [ ] Create `supabase/functions/practice-chat/temperature.ts`.

Exports:

```ts
export type TemperatureBand = "frozen" | "cold" | "neutral" | "warm" | "hot";

export interface TemperatureJudgement {
  score: number;
  delta: number;
  band: TemperatureBand;
  reason: string;
}

export function clampTemperature(score: number): number;
export function clampTemperatureDelta(delta: number): number;
export function temperatureBandFor(score: number): TemperatureBand;
export function temperatureBandInstruction(score: number): string;
export function applyTemperatureDelta(current: number, delta: number): TemperatureJudgement;
export function buildTemperatureJudgeMessages(opts: {
  priorScore: number;
  turns: PracticeTurn[];
  assistantReply: string;
  profile: PracticeProfile;
}): ChatMessage[];
export function parseTemperatureJudgement(raw: string, priorScore: number): TemperatureJudgement;
```

Temperature bands:

- `0..20` -> `frozen`
- `21..40` -> `cold`
- `41..60` -> `neutral`
- `61..80` -> `warm`
- `81..100` -> `hot`

Judge JSON format:

```json
{
  "delta": 3,
  "reason": "接住對方資訊並低壓追問。"
}
```

Rules:

- Delta must be an integer.
- Delta is clamped to `-8..8`.
- Score is clamped to `0..100`.
- Reason is optional after parsing but response always returns a non-empty fallback reason.

- [ ] Update `supabase/functions/practice-chat/prompt_test.ts`.

Test cases:

- Standard `buildChatMessages(turns, profile)` does not include `升溫指數`.
- Beginner `buildChatMessages(turns, profile, { practiceMode: "beginner", temperatureScore: 30 })` includes `升溫指數 30/100`.
- Beginner prompt includes exactly one band instruction matching `cold` at score 30.
- Beginner prompt does not mention hints.

- [ ] Update `supabase/functions/practice-chat/prompt.ts`.

Implementation details:

- Add optional third parameter:

```ts
export function buildChatMessages(
  turns: PracticeTurn[],
  profile: PracticeProfile,
  options: {
    practiceMode?: PracticeLearningMode;
    temperatureScore?: number;
  } = {},
): ChatMessage[];
```

- Append temperature instructions to the system prompt only when `options.practiceMode === "beginner"`.
- Use `temperatureBandInstruction(options.temperatureScore ?? 30)`.

Run:

```powershell
deno test --allow-env supabase/functions/practice-chat/temperature_test.ts supabase/functions/practice-chat/prompt_test.ts
```

Expected after implementation: all temperature and prompt tests pass.

Commit:

```powershell
git add supabase/functions/practice-chat/temperature.ts supabase/functions/practice-chat/temperature_test.ts supabase/functions/practice-chat/prompt.ts supabase/functions/practice-chat/prompt_test.ts
git commit -m "feat(practice-chat): 加入新手升溫判定與 prompt"
```

### 4. Wire Temperature Into Chat Handler

- [ ] Update `supabase/functions/practice-chat/index_test.ts`.

Test cases:

- Standard chat response does not include `temperature`.
- Beginner first chat call uses initial temperature 30 and returns a `temperature` object.
- Beginner second chat call uses ledger temperature rather than client-sent temperature.
- Temperature judge failure still returns AI reply and previous temperature.
- Chat commit uses the 6-argument RPC with `practiceMode`.
- Mode mismatch maps `PRACTICE_MODE_LOCKED` to HTTP 409 and no successful response.
- Ledger select includes `practice_mode`, `temperature_score`, and `hint_count`.

- [ ] Update `supabase/functions/practice-chat/index.ts`.

Implementation details:

- Fetch ledger fields:

```ts
.select("ai_count, charged, debrief_count, practice_mode, temperature_score, hint_count")
```

- Build `SessionLedger` with fallbacks:

```ts
practiceMode: ledgerRow?.practice_mode === "beginner" ? "beginner" : "standard",
temperatureScore: typeof ledgerRow?.temperature_score === "number" ? ledgerRow.temperature_score : null,
hintCount: typeof ledgerRow?.hint_count === "number" ? ledgerRow.hint_count : 0,
```

- Compute chat temperature:

```ts
const beginnerMode = request.practiceMode === "beginner";
const currentTemperature = beginnerMode
  ? ledger.temperatureScore ?? request.temperatureScore ?? 30
  : null;
```

- Pass beginner options into `buildChatMessages`.
- Call the new `commit_practice_chat_turn` overload with:

```ts
p_practice_mode: request.practiceMode,
p_initial_temperature_score: request.temperatureScore,
```

- After successful commit, run temperature judge only for beginner mode.
- If judge succeeds, call `update_practice_temperature`.
- If judge fails, log `practice_chat_temperature_judge_failed`, keep current temperature, and return a zero delta.
- Include `hintUsedCount: ledger.hintCount` for beginner chat responses.

- [ ] Extend `mapLedgerError`.

Mappings:

- `PRACTICE_MODE_LOCKED` -> `{ error: "practice_mode_locked", status: 409 }`
- `PRACTICE_INVALID_MODE` -> `{ error: "invalid_practiceMode", status: 400 }`

Run:

```powershell
deno test --allow-env --allow-net=127.0.0.1 supabase/functions/practice-chat/index_test.ts supabase/functions/practice-chat/temperature_test.ts supabase/functions/practice-chat/prompt_test.ts
```

Expected after implementation: chat handler tests pass.

Commit:

```powershell
git add supabase/functions/practice-chat/index.ts supabase/functions/practice-chat/index_test.ts
git commit -m "feat(practice-chat): 串接新手升溫回覆流程"
```

### 5. Add Hint Generation Module

- [ ] Create `supabase/functions/practice-chat/hint_test.ts`.

Test cases:

- `parseHintResult` accepts valid JSON with `warmUp`, `steady`, and `coaching`.
- Returned labels are fixed to `升溫回覆` and `穩住回覆`, ignoring model labels.
- Empty warm-up text throws `malformed_hint`.
- Empty steady text throws `malformed_hint`.
- Empty coaching throws `malformed_hint`.
- Text longer than 160 characters is trimmed to 160 characters.
- Coaching longer than 240 characters is trimmed to 240 characters.
- `buildHintMessages` includes current temperature and latest transcript.
- `buildHintMessages` instructs the model that hints must not be manipulative, sexual, insulting, or pressure-based.

- [ ] Create `supabase/functions/practice-chat/hint.ts`.

Exports:

```ts
export type HintReplyType = "warm_up" | "steady";

export interface HintReply {
  type: HintReplyType;
  label: "升溫回覆" | "穩住回覆";
  text: string;
}

export interface PracticeHintResult {
  replies: [HintReply, HintReply];
  coaching: string;
}

export function buildHintMessages(opts: {
  turns: PracticeTurn[];
  profile: PracticeProfile;
  temperatureScore: number;
}): ChatMessage[];

export function parseHintResult(raw: string): PracticeHintResult;
```

Model JSON format:

```json
{
  "warmUp": "那我先查朧月。你如果只推一道，會推熟成魚還是酒單？",
  "steady": "好，我自己查。你剛剛提到酒單，看起來你蠻懂這類店。",
  "coaching": "她願意給店名代表還有一點互動空間。先接住資訊，再問一個具體但低壓力的問題。"
}
```

Content rules inside the hint prompt:

- Traditional Chinese only.
- Reply options must be ready to send.
- Each option must be under 60 Chinese characters when possible.
- `升溫回覆` can make a small forward move, but must stay low-pressure.
- `穩住回覆` protects the conversation from losing points and avoids chasing.
- Coaching explains the conversational principle, not a script dump.
- No PUA tactics, guilt, insults, sexual pressure, or forced invitation.

Run:

```powershell
deno test --allow-env supabase/functions/practice-chat/hint_test.ts
```

Expected after implementation: hint module tests pass.

Commit:

```powershell
git add supabase/functions/practice-chat/hint.ts supabase/functions/practice-chat/hint_test.ts
git commit -m "feat(practice-chat): 新增新手提示生成器"
```

### 6. Wire Hint Mode Into Edge Handler

- [ ] Update `supabase/functions/practice-chat/index_test.ts`.

Add hint handler cases:

- `mode: "hint"` rejects standard practice mode.
- Hint before first AI reply returns 403.
- Hint when latest turn is user returns 400 from validation.
- Hint over 5 successful hints returns 403 and no quota payload.
- Hint quota exceeded returns 429 before provider call.
- DeepSeek failure returns 500 and does not call `record_practice_hint`.
- Malformed hint JSON returns 500 and does not call `record_practice_hint`.
- Successful hint calls `record_practice_hint` after parsing.
- Successful hint response includes two replies, coaching, `costDeducted: 1`, remaining counts, provider, model, generatedAt.

- [ ] Update `supabase/functions/practice-chat/index.ts`.

Implementation details:

- Add constants:

```ts
const HINT_MAX_TOKENS = 450;
const HINT_TEMPERATURE = 0.45;
```

- Branch after ledger fetch and before debrief:

```ts
if (request.mode === "hint") {
  // gate, quota preflight, generation, parse, record, response
}
```

- Use `decideHintGate({ ledger })`.
- For quota preflight, reuse `checkQuota` with `PRACTICE_QUOTA_COST`.
- Call DeepSeek with `jsonMode: true`.
- Parse with `parseHintResult`.
- After parse success, call `record_practice_hint` with:

```ts
p_user_id: user.id,
p_session_id: request.sessionId,
p_charge_quota: !accountIsTest,
p_max_hints: MAX_HINTS_PER_ROUND,
```

- If record fails, map:

```ts
PRACTICE_HINT_LIMIT -> practice_hint_limit, 403
PRACTICE_HINT_BEGINNER_ONLY -> practice_hint_beginner_only, 403
PRACTICE_SESSION_NOT_STARTED -> practice_session_not_started, 403
```

- Use `deducted = didCharge ? PRACTICE_QUOTA_COST : 0`.
- Call `remainingFrom(sub, limits, deducted)`.
- Log `practice_chat_succeeded` with `mode: "hint"` and `costDeducted`.

Run:

```powershell
deno test --allow-env --allow-net=127.0.0.1 supabase/functions/practice-chat/index_test.ts supabase/functions/practice-chat/hint_test.ts supabase/functions/practice-chat/quota_decision_test.ts
```

Expected after implementation: hint handler tests pass.

Commit:

```powershell
git add supabase/functions/practice-chat/index.ts supabase/functions/practice-chat/index_test.ts supabase/functions/practice-chat/quota_decision.ts supabase/functions/practice-chat/quota_decision_test.ts
git commit -m "feat(practice-chat): 串接新手提示扣款流程"
```

## Flutter Steps

### 7. Add Domain Entities And API Parsing

- [ ] Create `lib/features/practice_chat/domain/entities/practice_learning_mode.dart`.

Expected API:

```dart
enum PracticeLearningMode {
  standard,
  beginner;

  String get wireName => switch (this) {
        PracticeLearningMode.standard => 'standard',
        PracticeLearningMode.beginner => 'beginner',
      };

  String get label => switch (this) {
        PracticeLearningMode.standard => '實戰',
        PracticeLearningMode.beginner => '新手',
      };

  static PracticeLearningMode fromWire(String? value) {
    return value == 'beginner'
        ? PracticeLearningMode.beginner
        : PracticeLearningMode.standard;
  }
}
```

- [ ] Create `lib/features/practice_chat/domain/entities/practice_temperature.dart`.

Expected API:

```dart
class PracticeTemperature {
  final int score;
  final int delta;
  final String band;
  final String reason;

  const PracticeTemperature({
    required this.score,
    required this.delta,
    required this.band,
    required this.reason,
  });

  bool get wentUp => delta > 0;
  bool get wentDown => delta < 0;
}
```

- [ ] Create `lib/features/practice_chat/domain/entities/practice_hint.dart`.

Expected API:

```dart
enum PracticeHintReplyType { warmUp, steady }

class PracticeHintReply {
  final PracticeHintReplyType type;
  final String label;
  final String text;
}

class PracticeHintResult {
  final List<PracticeHintReply> replies;
  final String coaching;
  final int costDeducted;
  final int hintUsedCount;
  final int? monthlyRemaining;
  final int? dailyRemaining;
}
```

- [ ] Update `test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart`.

Test cases:

- `sendMessage` includes `practiceMode` when called.
- Beginner `sendMessage` parses `temperature`.
- Standard `sendMessage` accepts missing `temperature`.
- `requestHint` sends `mode: "hint"`.
- `requestHint` parses two replies and coaching.
- `requestHint` maps HTTP 429 to `PracticeQuotaExceededException`.
- `requestHint` maps HTTP 403 `practice_hint_limit` to a new typed exception.
- Malformed hint response throws `PracticeGenerationFailedException`.

- [ ] Update `lib/features/practice_chat/data/services/practice_chat_api_service.dart`.

Implementation details:

- Import new domain entities.
- Extend `PracticeChatReply` with `PracticeTemperature? temperature` and `int? hintUsedCount`.
- Add optional `PracticeLearningMode practiceMode = PracticeLearningMode.standard` to `sendMessage`.
- Add optional `int? temperatureScore` to `sendMessage`.
- Include `practiceMode.wireName` and `temperatureScore` in body.
- Add `Future<PracticeHintResult> requestHint(...)`.
- Add typed exception:

```dart
class PracticeHintLimitException implements Exception {
  PracticeHintLimitException();
}
```

- In `_guardStatus`, preserve existing behavior for chat and debrief.
- In `requestHint`, handle 403 errors directly so `practice_hint_limit` can show friendly copy.

Run:

```powershell
flutter test test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart
```

Expected after implementation: service tests pass.

Commit:

```powershell
git add lib/features/practice_chat/domain/entities/practice_learning_mode.dart lib/features/practice_chat/domain/entities/practice_temperature.dart lib/features/practice_chat/domain/entities/practice_hint.dart lib/features/practice_chat/data/services/practice_chat_api_service.dart test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart
git commit -m "feat(practice-chat): 新增新手模式 API 合約"
```

### 8. Persist Beginner Session State

- [ ] Update `lib/features/practice_chat/domain/entities/practice_session.dart`.

Add fields:

```dart
@HiveField(16)
final String? practiceMode;

@HiveField(17)
final int? temperatureScore;

@HiveField(18)
final int? hintUsedCount;
```

Constructor defaults:

- `practiceMode` nullable, with caller storing `PracticeLearningMode.wireName`.
- `temperatureScore` nullable.
- `hintUsedCount` nullable.

Update `copyWith` to include all three.

- [ ] Regenerate `lib/features/practice_chat/domain/entities/practice_session.g.dart`.

Run:

```powershell
dart run build_runner build --delete-conflicting-outputs
```

Expected after implementation: generated Hive adapter reads and writes fields 16, 17, and 18 without changing old field ids.

- [ ] Update `test/unit/features/practice_chat/data/repositories/practice_session_repository_test.dart`.

Test cases:

- Old session without fields maps to standard mode in controller.
- Beginner session restores `temperatureScore`.
- Beginner session restores `hintUsedCount`.

Run:

```powershell
flutter test test/unit/features/practice_chat/data/repositories/practice_session_repository_test.dart
```

Expected after implementation: repository tests pass.

Commit:

```powershell
git add lib/features/practice_chat/domain/entities/practice_session.dart lib/features/practice_chat/domain/entities/practice_session.g.dart test/unit/features/practice_chat/data/repositories/practice_session_repository_test.dart
git commit -m "feat(practice-chat): 保存新手模式本地狀態"
```

### 9. Add Controller State And Hint Actions

- [ ] Update `test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart`.

Test cases:

- Initial new room defaults to `PracticeLearningMode.standard`.
- `setPracticeLearningMode(beginner)` works before first message.
- Mode switch does nothing after first message.
- Beginner first chat sends `practiceMode: beginner` and `temperatureScore: 30`.
- Chat response temperature updates state and persists.
- Missing response temperature keeps previous score.
- Standard chat does not set temperature.
- Hint cannot run in standard mode.
- Hint cannot run before an AI reply.
- Hint success updates `hintReplies`, `hintCoaching`, `hintUsedCount`, and usage counts.
- Tapping hint text fills input through UI state only and does not append transcript.
- Hint quota exceeded sets friendly error copy and keeps transcript unchanged.
- Continuing with same partner starts a new billing session and keeps selected learning mode if the previous round was selected before first message.
- Resuming old session falls back to standard.

- [ ] Update `lib/features/practice_chat/data/providers/practice_chat_providers.dart`.

Add state fields:

```dart
final PracticeLearningMode learningMode;
final int? temperatureScore;
final int? lastTemperatureDelta;
final String? temperatureReason;
final bool isHintLoading;
final List<PracticeHintReply> hintReplies;
final String? hintCoaching;
final int hintUsedCount;
final bool hintLimitReached;
```

Add getters:

```dart
bool get isBeginnerMode => learningMode == PracticeLearningMode.beginner;
bool get canChangeLearningMode => messages.isEmpty && !isSending && !isDebriefing;
bool get canRequestHint =>
    isBeginnerMode &&
    isRevealed &&
    !isSending &&
    !isDebriefing &&
    !sessionComplete &&
    messages.isNotEmpty &&
    messages.last.role == 'ai' &&
    hintUsedCount < 5;
int get displayTemperatureScore => temperatureScore ?? 30;
```

Add controller methods:

```dart
void setPracticeLearningMode(PracticeLearningMode mode);
Future<void> requestHint();
void clearHint();
void markHintApplied();
```

Implementation details:

- `sendMessage` passes `learningMode` and `displayTemperatureScore`.
- On optimistic user send, clear hint replies and coaching.
- On beginner chat success, update temperature fields from reply.
- On standard chat success, keep temperature fields null.
- `_persist` stores `learningMode.wireName`, `temperatureScore`, and `hintUsedCount`.
- `_stateFromSession` uses `PracticeLearningMode.fromWire(session.practiceMode)`.
- `_stateFromDraft` starts standard unless the user already selected beginner before first message; draft persistence of mode is optional only if mode selection should survive app close before first message. If implemented, use settings-box draft extension in a separate small commit.
- `requestHint` calls `_api.requestHint`, syncs usage when `costDeducted > 0`, and does not mutate `messages`.
- Hint errors use user-facing Traditional Chinese copy:
  - quota: `訊息額度不足，無法取得提示。`
  - limit: `這輪提示已用完，先試著自己回一則看看。`
  - generic: `提示暫時產生失敗，剛剛沒有扣額度。`

Run:

```powershell
flutter test test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart
```

Expected after implementation: controller tests pass.

Commit:

```powershell
git add lib/features/practice_chat/data/providers/practice_chat_providers.dart test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart
git commit -m "feat(practice-chat): 加入新手模式狀態與提示操作"
```

### 10. Add Practice Room UI

- [ ] Update `test/widget/features/practice_chat/practice_chat_screen_style_test.dart`.

Widget test cases:

- Before first message, the screen shows `實戰` and `新手` segmented choices.
- Standard mode does not show `升溫指數`.
- Beginner mode before first message shows `升溫指數 30/100`.
- After first message, the mode selector is disabled or hidden and mode cannot change.
- After AI reply in beginner mode, the hint button is visible.
- Hint loading shows a compact loading state and disables repeat tapping.
- Hint success shows two chips and one coaching text block.
- Tapping a hint chip fills the input field.
- Hint chips are not visible in standard mode.
- Hint limit reached hides or disables hint button with clear copy.
- All text fits at 360px width.

- [ ] Update `lib/features/practice_chat/presentation/screens/practice_chat_screen.dart`.

Implementation locations:

- Add mode switch to `_PracticeOpeningControls`.
- Add temperature display to `_PracticeOpeningControls` and `_PracticeProfileBar`.
- Add hint controls to `_BottomBar`.
- Keep cards flat; do not nest a hint card inside another card.
- Use Flutter Material icons:
  - `Icons.local_fire_department_outlined` for temperature.
  - `Icons.lightbulb_outline` for hint.
  - `Icons.trending_up` for `升溫回覆`.
  - `Icons.shield_outlined` for `穩住回覆`.
- Add callbacks in `_PracticeChatScreen`:

```dart
void _requestHint() {
  ref.read(practiceChatControllerProvider.notifier).requestHint();
}

void _applyHint(String text) {
  _controller.text = text;
  _controller.selection = TextSelection.collapsed(offset: text.length);
  ref.read(practiceChatControllerProvider.notifier).markHintApplied();
}
```

UI placement:

- In `_PracticeOpeningControls`, place the segmented control below difficulty chips.
- In `_PracticeProfileBar`, show a compact `升溫指數 NN/100` pill at the trailing side for beginner mode.
- In `_BottomBar`, place the hint row above the quota label and input row.
- Hint response area appears above the input row and below the quota label.

Copy:

- Temperature label: `升溫指數`
- Hint button: `提示`
- Hint cost helper before success: `取得提示會扣 1 則`
- Hint limit copy: `這輪提示已用完`
- Coaching title: `這邊該怎麼回覆的心法`

Run:

```powershell
flutter test test/widget/features/practice_chat/practice_chat_screen_style_test.dart
```

Expected after implementation: widget tests pass.

Commit:

```powershell
git add lib/features/practice_chat/presentation/screens/practice_chat_screen.dart test/widget/features/practice_chat/practice_chat_screen_style_test.dart
git commit -m "feat(practice-chat): 加入新手升溫與提示介面"
```

## Integration Validation

### 11. Run Targeted Test Suite

- [ ] Run Edge tests:

```powershell
deno test --allow-env --allow-net=127.0.0.1 supabase/functions/practice-chat/validate_test.ts supabase/functions/practice-chat/quota_decision_test.ts supabase/functions/practice-chat/prompt_test.ts supabase/functions/practice-chat/temperature_test.ts supabase/functions/practice-chat/hint_test.ts supabase/functions/practice-chat/index_test.ts
```

Expected: all selected Deno tests pass.

- [ ] Run Flutter practice-chat tests:

```powershell
flutter test test/unit/features/practice_chat/data/services/practice_chat_api_service_test.dart test/unit/features/practice_chat/data/providers/practice_chat_controller_test.dart test/unit/features/practice_chat/data/repositories/practice_session_repository_test.dart test/widget/features/practice_chat/practice_chat_screen_style_test.dart
```

Expected: all selected Flutter tests pass.

- [ ] Run analyzer:

```powershell
flutter analyze
```

Expected: no new analyzer errors.

Commit if test-only or analyzer fixes were needed:

```powershell
git add <changed-files>
git commit -m "test(practice-chat): 穩定新手模式驗證"
```

### 12. Manual Smoke Checklist

Run the app locally and verify:

- Default room opens in `實戰`.
- `實戰` sends and receives messages exactly as before.
- `實戰` never shows temperature or hint controls.
- Before first message, switching to `新手` shows `升溫指數 30/100`.
- After first message, mode is locked.
- Beginner AI reply updates temperature.
- Temperature delta never jumps outside the expected small range.
- Hint button appears only after AI reply.
- Hint success deducts 1 message and syncs subscription usage.
- Hint failure copy says no quota was deducted.
- Sixth successful hint attempt is blocked.
- Tapping `升溫回覆` fills input and does not send.
- Tapping `穩住回覆` fills input and does not send.
- Sent hint text appears in transcript only after the user taps send.
- End practice debrief still works.
- Continuing same partner starts a new billing round with 20 AI replies available.
- Recent session restore keeps beginner temperature when it was a beginner session.

### 13. High-Risk Review Gate

Because this feature touches quota, Edge schema, prompts, and Hive persistence, get Codex review evidence before calling the build dogfood-safe.

Review packet:

```powershell
git diff --stat origin/main...HEAD
git diff origin/main...HEAD -- supabase/functions/practice-chat supabase/migrations lib/features/practice_chat test/unit/features/practice_chat test/widget/features/practice_chat
```

Ask reviewer to focus on:

- No overcharge or double charge in chat and hint flows.
- Hint failure cannot deduct quota.
- Hint success cannot exceed 5 successful hints per round.
- Standard mode cannot receive beginner prompt instructions.
- Old clients missing `practiceMode` still work.
- Old Hive sessions do not crash.
- Edge response schema cannot crash Flutter parsing.
- Temperature judge failure cannot block chat reply.

If review finds an issue:

- Fix in the smallest relevant commit.
- Add or update a regression test.
- Record durable history in `docs/bug-log.md` only for production-risk findings.

### 14. Deployment Notes

- [ ] Apply the migration through the repo-approved Supabase path.
- [ ] Deploy only `practice-chat` Edge Function after tests pass.
- [ ] Do not deploy `analyze-chat`.
- [ ] Rebuild Flutter for TestFlight after the Flutter commit range lands.
- [ ] Run the manual smoke checklist on a real device before dogfood release notes.

## Final Acceptance Criteria

- `實戰` mode is unchanged for existing users.
- `新手` mode starts at `升溫指數 30/100`.
- Beginner temperature updates after successful AI replies and survives app restore.
- Beginner temperature influences future AI replies through prompt bands.
- Hint returns two reply chips and one coaching note.
- Hint costs 1 message only after successful generation.
- Hint has server-side 5-success cap per round.
- Hint does not auto-send and does not enter transcript unless user sends.
- Quota, subscription usage, and paywall behavior remain consistent with existing practice-chat rules.
- Targeted Deno tests pass.
- Targeted Flutter tests pass.
- `flutter analyze` passes.
- Codex review evidence exists before the feature is described as dogfood-safe.
