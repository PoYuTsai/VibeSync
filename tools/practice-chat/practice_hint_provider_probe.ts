// Direct provider comparison for Hint generation and repair behavior.
// This makes billable provider calls; see README.md.
import {
  callClaude,
  CLAUDE_HAIKU_MODEL,
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
  { role: "user" as const, text: "早安，今天精神還行嗎？" },
  {
    role: "ai" as const,
    text:
      "早～ 追劇真的很難停下來欸哈哈哈\n我剛剛飛回來也還在調時差，腦袋也是空的",
  },
];
const profile = resolvePracticeProfile({
  personaId: "slow_worker",
  difficulty: "normal",
});
const messages = buildHintMessages({
  turns,
  profile,
  practiceMode: "beginner",
  temperatureScore: 28,
  familiarityScore: 0,
});
const repairMessages = [
  ...messages,
  {
    role: "user" as const,
    content:
      '上一版 Hint JSON 被拒絕：欄位太長，若直接裁尾會變成半句。請重新輸出唯一 JSON，shape 必須仍是 {"warmUp":"...","steady":"...","coaching":"..."}。warmUp、steady 各 60 字內，coaching 140 字內，三欄都要完整收句。warmUp、steady、coaching 三欄各自都要逐字重用她最新一句的具體詞或短語，不能只有其中一欄具體。可貼回覆要先接住她最新狀態，再給低壓接球；不要命令、不要面試官語氣、不要內部標籤、不要露骨或私密壓迫。',
  },
];

const providers = [
  [
    "deepseek",
    () =>
      callDeepSeek({
        apiKey: Deno.env.get("DEEPSEEK_API_KEY")!,
        messages,
        maxTokens: 650,
        temperature: 0.45,
        jsonMode: true,
        timeoutMs: 12000,
      }),
  ],
  [
    "claude-sonnet-base",
    () =>
      callClaude({
        apiKey: Deno.env.get("CLAUDE_API_KEY")!,
        model: CLAUDE_SONNET_MODEL,
        messages,
        maxTokens: 650,
        temperature: 0.45,
        timeoutMs: 12000,
      }),
  ],
  [
    "claude-sonnet-repair",
    () =>
      callClaude({
        apiKey: Deno.env.get("CLAUDE_API_KEY")!,
        model: CLAUDE_SONNET_MODEL,
        messages: repairMessages,
        maxTokens: 650,
        temperature: 0.45,
        timeoutMs: 12000,
      }),
  ],
  [
    "claude-haiku-repair",
    () =>
      callClaude({
        apiKey: Deno.env.get("CLAUDE_API_KEY")!,
        model: CLAUDE_HAIKU_MODEL,
        messages: repairMessages,
        maxTokens: 650,
        temperature: 0.45,
        timeoutMs: 12000,
      }),
  ],
] as const;

for (const [provider, call] of providers) {
  try {
    const raw = await call();
    console.log(`--- ${provider} raw ---\n${raw}`);
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
      console.log(`${provider} ACCEPTED`);
    } catch (error) {
      console.log(
        `${provider} REJECTED: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  } catch (error) {
    console.log(
      `${provider} CALL FAILED: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
  }
}
