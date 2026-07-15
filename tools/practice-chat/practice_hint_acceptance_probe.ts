// Direct provider acceptance probe for generated Beginner Hint candidates.
// This makes billable provider calls; see README.md.
import {
  callClaude,
  CLAUDE_SONNET_MODEL,
} from "../../supabase/functions/practice-chat/claude.ts";
import { callDeepSeek } from "../../supabase/functions/practice-chat/deepseek.ts";
import {
  buildHintDecision,
  buildHintMessages,
  parseHintResult,
} from "../../supabase/functions/practice-chat/hint.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";

const turns = [
  {
    role: "user" as const,
    text: "早安，我昨晚追劇追到兩點，現在腦袋還沒開機 😂",
  },
  {
    role: "ai" as const,
    text:
      "早～ 追劇真的很難停下來欸哈哈哈\n我剛剛飛回來也還在調時差，腦袋也是空的",
  },
];
const profile = resolvePracticeProfile({ profileId: "practice_girl_001" });
const messages = buildHintMessages({
  turns,
  profile,
  practiceMode: "beginner",
  temperatureScore: 28,
  familiarityScore: 0,
});

function fieldLengths(raw: string): Record<string, number | null> {
  try {
    const start = raw.indexOf("{");
    const end = raw.lastIndexOf("}");
    const parsed = JSON.parse(raw.slice(start, end + 1));
    return {
      warmUp: typeof parsed.warmUp === "string" ? parsed.warmUp.length : null,
      steady: typeof parsed.steady === "string" ? parsed.steady.length : null,
      coaching: typeof parsed.coaching === "string"
        ? parsed.coaching.length
        : null,
    };
  } catch {
    return { warmUp: null, steady: null, coaching: null };
  }
}

function validate(raw: string): string | null {
  try {
    const parsed = parseHintResult(raw, {
      mode: "beginner",
      turns,
      enforceGeneratedQuality: true,
    });
    for (const reply of parsed.replies) {
      buildHintDecision({
        turns,
        profile,
        practiceMode: "beginner",
        temperatureScore: 28,
        familiarityScore: 0,
        replyType: reply.type,
        replyText: reply.text,
        rationale: parsed.coaching,
      });
    }
    return null;
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
}

for (let run = 1; run <= 4; run++) {
  let deepError = "provider_error";
  try {
    const raw = await callDeepSeek({
      apiKey: Deno.env.get("DEEPSEEK_API_KEY")!,
      messages,
      maxTokens: 650,
      temperature: 0.45,
      jsonMode: true,
      timeoutMs: 12000,
    });
    deepError = validate(raw) ?? "accepted";
    console.log(JSON.stringify({
      run,
      provider: "deepseek",
      result: deepError,
      lengths: fieldLengths(raw),
    }));
  } catch (error) {
    deepError = error instanceof Error ? error.message : String(error);
    console.log(
      JSON.stringify({ run, provider: "deepseek", result: deepError }),
    );
  }

  if (deepError === "accepted") continue;
  const repairMessages = [
    ...messages,
    {
      role: "user" as const,
      content: `上一版 Hint JSON 被拒絕：${deepError}。請重新輸出唯一 JSON，` +
        'shape 必須仍是 {"warmUp":"...","steady":"...","coaching":"..."}。' +
        "warmUp、steady 各 60 字內，coaching 140 字內，三欄都要完整收句。" +
        "warmUp、steady、coaching 三欄各自都要逐字重用她最新一句的具體詞或短語，不能只有其中一欄具體。" +
        "可貼回覆要先接住她最新狀態，再給低壓接球；不要命令、不要面試官語氣、不要內部標籤、不要露骨或私密壓迫。",
    },
  ];
  try {
    const raw = await callClaude({
      apiKey: Deno.env.get("CLAUDE_API_KEY")!,
      model: CLAUDE_SONNET_MODEL,
      messages: repairMessages,
      maxTokens: 650,
      temperature: 0.45,
      timeoutMs: 12000,
    });
    console.log(JSON.stringify({
      run,
      provider: "claude",
      result: validate(raw) ?? "accepted",
      lengths: fieldLengths(raw),
    }));
  } catch (error) {
    console.log(JSON.stringify({
      run,
      provider: "claude",
      result: error instanceof Error ? error.message : String(error),
    }));
  }
}
