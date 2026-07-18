import {
  callClaudeAPI,
  runCoachChat,
} from "../../supabase/functions/coach-chat/generation.ts";
import type { CoachChatRequest } from "../../supabase/functions/coach-chat/schemas.ts";

interface SmokeCase {
  id: string;
  request: CoachChatRequest;
}

const apiKey = Deno.env.get("CLAUDE_API_KEY");
if (!apiKey) throw new Error("CLAUDE_API_KEY missing");

const runs = parseRuns(Deno.args);
const cases: SmokeCase[] = [
  {
    id: "whole-turn-last-ack",
    request: {
      conversationId: "local-coach-whole-turn",
      userQuestion:
        "她剛剛連續傳這些，我想自然接住整輪，不要逐句點名，也不要只回最後的哈哈。直接給我一個可傳版本。",
      rawReplyDraft: "恭喜妳提案過了，陶藝也太好笑了哈哈",
      activeSessionTurns: [],
      forceAnswer: true,
      recentMessages: [
        {
          sender: "partner",
          text: "今天終於把卡兩個月的專案提案過了，老闆還說我這次抓得很準",
        },
        {
          sender: "partner",
          text: "晚上又去上第一次陶藝課，杯子歪得超像被揍過 😂",
        },
        { sender: "partner", text: "哈哈" },
      ],
      dataQualityFlagged: false,
    },
  },
  {
    id: "low-investment",
    request: {
      conversationId: "local-coach-low",
      userQuestion:
        "她只回這句，我該怎麼接？直接給一句，輕一點，不要逼她解釋或安撫我。",
      activeSessionTurns: [],
      forceAnswer: true,
      recentMessages: [{ sender: "partner", text: "還好啦哈哈" }],
      dataQualityFlagged: false,
    },
  },
  {
    id: "explicit-long-message",
    request: {
      conversationId: "local-coach-long",
      userQuestion:
        "我想回一段稍微完整、溫暖一點的訊息，不要只給超短金句。請直接給可傳版本。",
      activeSessionTurns: [],
      forceAnswer: true,
      recentMessages: [
        {
          sender: "partner",
          text: "這週連續加班，還把搬家的事情處理完了",
        },
        {
          sender: "partner",
          text: "週末我只想好好睡一覺，暫時什麼都不排",
        },
      ],
      dataQualityFlagged: false,
    },
  },
];

let failures = 0;
for (let run = 1; run <= runs; run++) {
  for (const smokeCase of cases) {
    let attempts = 0;
    const result = await runCoachChat(
      {
        userId: "local-test-account",
        request: smokeCase.request,
        tier: "essential",
        accountIsTest: true,
        apiKey,
      },
      {
        callClaude: (args) => {
          attempts++;
          return callClaudeAPI(args);
        },
        deductCredit: () => {
          throw new Error("test account attempted deduction");
        },
        logger: { info() {}, warn() {} },
      },
    );

    const card = result.body.card as Record<string, unknown> | undefined;
    const suggestedLine = typeof card?.suggestedLine === "string"
      ? card.suggestedLine
      : null;
    const verdict = judge(smokeCase.id, suggestedLine);
    if (result.status !== 200 || !verdict.pass) failures++;

    console.log(JSON.stringify({
      case: smokeCase.id,
      run,
      status: result.status,
      model: result.body.model,
      responseType: card?.responseType,
      rewriteDecision: card?.rewriteDecision,
      attempts,
      suggestedLine,
      verdict,
    }));
  }
}

console.log(JSON.stringify({
  summary: {
    cases: cases.length,
    runs,
    samples: cases.length * runs,
    failures,
  },
}));

if (failures > 0) Deno.exit(1);

function parseRuns(args: string[]): number {
  const runsArg = args.find((arg) => arg.startsWith("--runs="));
  const value = runsArg ? Number(runsArg.slice("--runs=".length)) : 2;
  if (!Number.isInteger(value) || value < 1 || value > 5) {
    throw new Error("--runs must be an integer from 1 to 5");
  }
  return value;
}

function judge(
  id: string,
  suggestedLine: string | null,
): { pass: boolean; failures: string[]; length: number } {
  const text = suggestedLine?.trim() ?? "";
  const failures: string[] = [];

  if (!text) failures.push("missing_suggested_line");
  if (/(1\.8|倍|字數|上限)/.test(text)) failures.push("formula_leak");

  if (id === "whole-turn-last-ack") {
    if (!/(提案|老闆|陶藝|杯子|被揍)/.test(text)) {
      failures.push("missed_high_value_ball");
    }
    if (/(升職|升官|隔天|第一天上班)/.test(text)) {
      failures.push("invented_timeline");
    }
  }

  if (id === "low-investment") {
    if (Array.from(text).length > 48) {
      failures.push("too_long_for_low_investment");
    }
    if (/(我是不是|不夠吸引|不想理我|冷掉|安撫我)/.test(text)) {
      failures.push("reassurance_bid");
    }
    if (/(為什麼|怎麼|什麼|哪一)/.test(text)) {
      failures.push("forced_explanation_question");
    }
    if (/[?？]/.test(text)) failures.push("explicit_no_question_violated");
    if (/(會裝|敷衍|冷淡|吊胃口|不想理)/.test(text)) {
      failures.push("invented_negative_motive");
    }
  }

  if (id === "explicit-long-message") {
    if (Array.from(text).length < 30) {
      failures.push("explicit_long_request_cut_too_short");
    }
    if (/(這幾週|最近幾週|這陣子)/.test(text)) {
      failures.push("invented_timeline");
    }
  }

  return {
    pass: failures.length === 0,
    failures,
    length: Array.from(text).length,
  };
}
