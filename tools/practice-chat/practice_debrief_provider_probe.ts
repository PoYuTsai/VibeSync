// Direct provider comparison for the generated Debrief quality contract.
// This makes billable provider calls; see README.md.
import {
  callClaude,
  CLAUDE_SONNET_MODEL,
} from "../../supabase/functions/practice-chat/claude.ts";
import { parseDebriefCard } from "../../supabase/functions/practice-chat/debrief_card.ts";
import { callDeepSeek } from "../../supabase/functions/practice-chat/deepseek.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import { buildDebriefMessages } from "../../supabase/functions/practice-chat/prompt.ts";

const selectedHint =
  "哈飛回來時間亂亂的最難熬，我追劇熬夜還算自找的 😂 你現在狀態有好一點了嗎？";
const turns = [
  {
    role: "user" as const,
    text: "早安，我昨晚追劇追到兩點，現在腦袋還沒開機 😂",
  },
  {
    role: "ai" as const,
    text: "早～剛飛回來時間還亂亂的\n你也是熬夜型喔😂",
  },
  { role: "user" as const, text: selectedHint },
  {
    role: "ai" as const,
    text: "剛瞇了一下有好一點\n不然等等又要出門補貨😅\n你追什麼劇啊",
  },
];
const appliedHintTurns = [{
  turnIndex: 2,
  type: "steady" as const,
  originalHintText: selectedHint,
  sentText: selectedHint,
  exact: true,
  hintRequestId: "synthetic-hint",
  decision: {
    move: "build_connection" as const,
    phase: "building_familiarity",
    rationale:
      "穩住選項：她丟了兩個入口：飛回來時間亂、問你熬夜型。先接住她的「時間亂」狀態，讓她感覺被看見；再用輕鬆的共同點（都沒睡好）拉近距離。升溫版多一句低壓小問回她現況，讓她繼續說；穩住版語氣更輕，不搶戲。",
    inviteRoute: "not_ready",
    targetVariable: "安全感與熟悉感",
  },
}];
const profile = resolvePracticeProfile({ profileId: "practice_girl_001" });
const messages = buildDebriefMessages(turns, profile, {
  practiceMode: "beginner",
  temperatureScore: 28,
  familiarityScore: 0,
  appliedHintTurns,
});

function lengths(raw: string): Record<string, unknown> {
  try {
    const parsed = JSON.parse(
      raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1),
    );
    const len = (value: unknown) =>
      typeof value === "string" ? value.length : null;
    return {
      summary: len(parsed.summary),
      strengths: Array.isArray(parsed.strengths)
        ? parsed.strengths.map(len)
        : null,
      watchouts: Array.isArray(parsed.watchouts)
        ? parsed.watchouts.map(len)
        : null,
      suggestedLine: len(parsed.suggestedLine),
      dateChanceReason: len(parsed.dateChanceReason),
      nextInviteMove: len(parsed.nextInviteMove),
    };
  } catch {
    return { invalidJson: true };
  }
}

function validate(raw: string): string {
  try {
    parseDebriefCard(raw, {
      allowGameBreakdown: false,
      requireCompleteCard: true,
      enforceGeneratedQuality: true,
      turns,
      appliedHintTurns,
    });
    return "accepted";
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
}

console.log(JSON.stringify({
  promptChars: messages.reduce(
    (total, message) => total + message.content.length,
    0,
  ),
}));

for (
  const [provider, call] of [
    [
      "deepseek",
      () =>
        callDeepSeek({
          apiKey: Deno.env.get("DEEPSEEK_API_KEY")!,
          messages,
          maxTokens: 800,
          temperature: 0.5,
          jsonMode: true,
          timeoutMs: 12000,
        }),
    ],
    [
      "claude",
      () =>
        callClaude({
          apiKey: Deno.env.get("CLAUDE_API_KEY")!,
          model: CLAUDE_SONNET_MODEL,
          messages,
          maxTokens: 800,
          temperature: 0.5,
          timeoutMs: 24000,
        }),
    ],
  ] as const
) {
  try {
    const raw = await call();
    const result = validate(raw);
    console.log(JSON.stringify({ provider, result, lengths: lengths(raw) }));
    if (result !== "accepted") console.log(raw);
  } catch (error) {
    console.log(JSON.stringify({
      provider,
      result: error instanceof Error ? error.message : String(error),
    }));
  }
}
