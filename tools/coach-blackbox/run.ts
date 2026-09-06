// Coach 1:1 黑箱：用真模型跑 runCoachChat（含語意審核與 retry），輸出每張卡
// 供人工復檢＋幾個機械旗標。付費呼叫——只在 Eric 授權後跑。
//
//   deno run --allow-read --allow-net --allow-write --allow-env \
//     tools/coach-blackbox/run.ts --label baseline [--only G1,P3] [--concurrency 3]
//
// 結果寫到 tools/coach-blackbox/results/<label>-<timestamp>.{json,md}（gitignored）。

import {
  callClaudeAPI,
  runCoachChat,
} from "../../supabase/functions/coach-chat/generation.ts";
import { RequestSchema } from "../../supabase/functions/coach-chat/schemas.ts";

type Msg = { sender: "me" | "partner"; text: string };
type Turn = {
  role: "user" | "coach";
  kind: "question" | "supplement" | "clarification" | "answer";
  content: string;
};

interface Case {
  id: string;
  family: string;
  request: Record<string, unknown>;
  /// 首輪預期的 responseType（修後）；null＝不檢查。
  expectRound1: "clarifyingQuestion" | "coachAnswer" | null;
  /// 補充輪：使用者回釐清（或追問）的文字。
  followUp?: string;
}

const STYLE =
  "主風格：自然直接；副風格：帶一點幽默。句子偏短、不油膩，不用長篇。";
const daysAgo = (d: number) =>
  new Date(Date.now() - d * 86_400_000).toISOString();

const global = (
  id: string,
  family: string,
  userQuestion: string,
  extra: Record<string, unknown> = {},
  followUp?: string,
  expectRound1: Case["expectRound1"] = "clarifyingQuestion",
): Case => ({
  id,
  family,
  expectRound1,
  followUp,
  request: {
    conversationId: "global:me",
    partnerId: null,
    scope: { type: "global" },
    userQuestion,
    activeSessionTurns: [],
    recentMessages: [],
    effectiveStyleContext: STYLE,
    dataQualityFlagged: false,
    ...extra,
  },
});

const PARTNER_HINT = { name: "小婕", traits: ["慢熱", "愛旅行"], note: null };
const partner = (
  id: string,
  family: string,
  userQuestion: string,
  recentMessages: Msg[],
  extra: Record<string, unknown> = {},
  expectRound1: Case["expectRound1"] = "coachAnswer",
  followUp?: string,
): Case => ({
  id,
  family,
  expectRound1,
  followUp,
  request: {
    conversationId: "partner:p1",
    partnerId: "p1",
    scope: { type: "partner", partnerId: "p1" },
    userQuestion,
    activeSessionTurns: [],
    recentMessages,
    partnerHint: PARTNER_HINT,
    effectiveStyleContext: STYLE,
    dataQualityFlagged: false,
    ...(recentMessages.length
      ? {
        contextProvenance: {
          sourceConversationId: "conv-p1",
          lastMessageAt: daysAgo(1),
        },
      }
      : {}),
    ...extra,
  },
});

const conversation = (
  id: string,
  family: string,
  userQuestion: string,
  recentMessages: Msg[],
  extra: Record<string, unknown> = {},
): Case => ({
  id,
  family,
  expectRound1: "coachAnswer",
  request: {
    conversationId: "c1",
    partnerId: "p1",
    scope: { type: "conversation", conversationId: "c1" },
    userQuestion,
    activeSessionTurns: [],
    recentMessages,
    partnerHint: PARTNER_HINT,
    effectiveStyleContext: STYLE,
    dataQualityFlagged: false,
    ...extra,
  },
});

const m = (sender: "me" | "partner", text: string): Msg => ({ sender, text });

export const CASES: Case[] = [
  // ── 一般模式（沒有對方原話）──
  global(
    "G1",
    "global-judgment",
    "對方回得很短，我該怎麼判斷？",
    {},
    "她最近這樣回——我：這週末有要去哪玩嗎？她：沒欸 在家。我：那我推薦你一部影集。她：好啊 哪部？",
  ),
  global(
    "G2",
    "global-opener",
    "不知道怎麼開啟話題，給我一點方向？",
    {},
    "全新對象，交友軟體剛配對，她自介寫喜歡爬山跟找咖啡廳，還沒聊過。",
  ),
  global(
    "G3",
    "global-invite",
    "怎麼把聊天推進到約出來？",
    {},
    "聊了兩週，幾乎每天都聊，她會主動講工作的事，也問過我週末都在幹嘛。",
  ),
  global(
    "G4",
    "global-anxiety",
    "她已讀不回我好焦慮，我要再傳嗎？",
    {},
    "昨天我傳「今天好累喔」她已讀沒回，之前都會回。我很想再傳一則問她是不是在忙。",
  ),
  global(
    "G5",
    "global-force",
    "對方回得很短，我該怎麼判斷？",
    { forceAnswer: true },
    undefined,
    "coachAnswer",
  ),
  global(
    "G6",
    "global-draft",
    "幫我看這句可以傳嗎？",
    { rawReplyDraft: "你今天過得怎樣啊 有沒有想我 哈哈" },
    "她剛剛回我「今天開會開到快死」。",
  ),
  global(
    "G7",
    "global-mindset",
    "我是不是太主動了？每次都我先傳",
    {},
    "認識一個月，十次有八次是我開頭，但她每次回得都蠻長，也會問我問題。",
  ),
  // ── 對象模式 ──
  partner("P1", "partner-judgment", "她這樣回是有興趣嗎？", [
    m("me", "妳上次說想去的那間拉麵店，我昨天路過發現排超長"),
    m("partner", "真的假的 那應該很好吃"),
    m("me", "看起來是，門口一堆人在拍照"),
    m("partner", "你有吃到嗎"),
    m("me", "沒 我趕時間就走了"),
    m("partner", "可惜 我也還沒去過"),
  ]),
  partner(
    "P2",
    "partner-invite",
    "我想約她去吃那間拉麵，怎麼開口比較自然？",
    [
      m("me", "妳上次說想去的那間拉麵店，我昨天路過發現排超長"),
      m("partner", "真的假的 那應該很好吃"),
      m("me", "看起來是，門口一堆人在拍照"),
      m("partner", "你有吃到嗎"),
      m("me", "沒 我趕時間就走了"),
      m("partner", "可惜 我也還沒去過"),
    ],
    {
      lifecyclePhase: "prepareInvite",
      conversationSummary: "兩週內聊得穩定，她會主動問問題，聊過旅行與美食。",
    },
  ),
  partner("P3", "partner-low-investment", "她回得很冷，我要不要再傳？", [
    m("me", "今天天氣超好，妳有出門嗎？"),
    m("partner", "沒"),
    m("me", "那在家追劇嗎 最近有什麼好看的"),
    m("partner", "還好"),
    m("me", "我最近在看一部日劇 講一個廚師的 蠻療癒的"),
    m("partner", "喔喔"),
  ]),
  partner(
    "P4",
    "partner-no-evidence",
    "小婕最近怎麼樣？我該怎麼跟她聊？",
    [],
    {},
    "clarifyingQuestion",
  ),
  partner(
    "P5",
    "partner-stalled",
    "她已讀不回兩天了，我要傳什麼？",
    [
      m("partner", "週末去了宜蘭 好累但很開心"),
      m("me", "宜蘭哪裡？我上個月也有去"),
      m("partner", "礁溪 泡湯"),
      m("me", "礁溪的湯不錯欸 妳有去吃那邊的蔥油餅嗎"),
      m("me", "對了 妳下週有空嗎"),
    ],
    {
      lifecyclePhase: "chatStalled",
      contextProvenance: {
        sourceConversationId: "conv-p1",
        lastMessageAt: daysAgo(2),
      },
    },
  ),
  partner(
    "P6",
    "partner-invite-suppressed",
    "這週末再約她一次？",
    [
      m("me", "這週六要不要一起去看展"),
      m("partner", "我看看喔"),
      m("me", "好～那下週呢 有一間新開的咖啡廳"),
      m("partner", "最近有點忙欸"),
      m("partner", "你最近在忙什麼"),
      m("me", "在準備一個案子 快忙完了"),
    ],
    {
      inviteHistory: [
        { summary: "週六看展邀約", outcome: "noReply", createdAt: daysAgo(6) },
        { summary: "下週咖啡廳邀約", outcome: "cold", createdAt: daysAgo(3) },
      ],
    },
  ),
  // ── 對話模式（分析頁 CTA 進來）──
  conversation("C1", "conversation-meaning", "她說我很有故事是什麼意思？", [
    m("partner", "你感覺是個很有故事的人"),
    m("me", "哈哈哪有那麼誇張"),
  ], {
    conversationSummary: "她前面會接話，但回覆速度偏慢。",
    analysisSnapshot: {
      heatScore: 64,
      stage: "升溫",
      summary: "對方有好奇，但還在觀察你的穩定度。",
      nextStep: "承認一半，再丟一個輕反問。",
      keySignals: ["人格觀察", "好奇但保留"],
    },
  }),
  conversation("C2", "conversation-draft", "這樣回可以嗎？", [
    m("partner", "你感覺是個很有故事的人"),
  ], {
    rawReplyDraft: "哈哈哪有 我只是比較常出去玩而已",
    analysisSnapshot: { heatScore: 64, stage: "升溫" },
  }),
  {
    ...conversation(
      "C3",
      "conversation-boundary",
      "她說她有男友但一直找我聊，我要不要約她？",
      [
        m("partner", "我男友最近都不理我 好煩"),
        m("me", "怎麼了"),
        m("partner", "算了 不想講 你週末都在幹嘛"),
        m("me", "通常去爬山 或在家耍廢"),
        m("partner", "好好喔 我也想去"),
      ],
      { analysisSnapshot: { heatScore: 58, stage: "曖昧" } },
    ),
    expectRound1: null,
  }, // 先問他要什麼位置也是合理教練行為
];

// ── 機械旗標 ──
const ENGLISH_ALLOW = /LINE|IG|KTV|Netflix|Instagram|YouTube|Threads/g;
function flags(
  req: Record<string, unknown>,
  card: Record<string, unknown>,
  expect: Case["expectRound1"],
  round: number,
): string[] {
  const out: string[] = [];
  const line = (card.suggestedLine as string | null) ?? null;
  const msgs = (req.recentMessages as Msg[]) ?? [];
  const draft = (req.rawReplyDraft as string | null) ?? null;
  if (round === 1 && expect && card.responseType !== expect) {
    out.push(`responseType!=${expect}`);
  }
  // 補充輪的證據在 userQuestion（使用者貼的原話／描述），只看首輪。
  if (
    round === 1 && line && msgs.length === 0 && !draft &&
    card.responseType === "coachAnswer"
  ) {
    out.push("line_without_evidence");
  }
  const visible = [card.nextStep, card.boundaryReminder, card.headline];
  for (const [i, v] of visible.entries()) {
    if (typeof v === "string" && v.length > (i === 2 ? 32 : 60)) {
      out.push(
        `${["nextStep", "boundaryReminder", "headline"][i]}>${
          i === 2 ? 32 : 60
        }(${v.length})`,
      );
    }
  }
  const text = [card.answer, card.nextStep, card.boundaryReminder, line]
    .filter((v) => typeof v === "string").join(" ").replace(ENGLISH_ALLOW, "");
  if (/[A-Za-z]{3,}/.test(text)) out.push("english_leak");
  if (/PUA|收割|控住|攻略|壞女人|高分妹|玩咖/.test(text)) {
    out.push("banned_word");
  }
  if (
    line &&
    /我(上|前|這)?(禮拜|週|周|星期|次|幾天|陣子)|我(昨天|前天|今天早上)/.test(
      line,
    ) &&
    !msgs.some((x) => x.sender === "me" && line.includes(x.text.slice(0, 6)))
  ) {
    out.push("anecdote_in_line?");
  }
  return out;
}

async function main() {
  const args = new Map<string, string>();
  for (let i = 0; i < Deno.args.length; i += 2) {
    args.set(Deno.args[i].replace(/^--/, ""), Deno.args[i + 1] ?? "true");
  }
  const label = args.get("label") ?? "run";
  const only = args.get("only")?.split(",").map((s) => s.trim());
  const concurrency = Number(args.get("concurrency") ?? "3");
  const home = Deno.env.get("HOME") ?? "";
  const apiKey = (await Deno.readTextFile(`${home}/.config/anthropic/key`))
    .trim();

  const cases = only ? CASES.filter((c) => only.includes(c.id)) : CASES;
  const results: Record<string, unknown>[] = [];

  async function runOne(
    id: string,
    round: number,
    reqRaw: Record<string, unknown>,
    expect: Case["expectRound1"],
  ) {
    const request = RequestSchema.parse(reqRaw);
    const events: string[] = [];
    const logger = {
      info: (e: string, d?: Record<string, unknown>) =>
        events.push(`${e}${d?.attempt ? `#${d.attempt}` : ""}`),
      warn: (e: string, d?: Record<string, unknown>) =>
        events.push(
          `WARN ${e}${d?.violations ? `:${d.violations}` : ""}${
            d?.errorClass ? `:${d.errorClass}` : ""
          }`,
        ),
    };
    const t0 = Date.now();
    const res = await runCoachChat(
      {
        userId: "blackbox",
        request,
        tier: "free",
        accountIsTest: true,
        apiKey,
      },
      {
        callClaude: callClaudeAPI,
        callSemanticCritic: callClaudeAPI,
        deductCredit: async () => {},
        logger,
      },
    );
    const card = (res.body.card ?? {}) as Record<string, unknown>;
    const row = {
      id,
      round,
      status: res.status,
      latencyMs: Date.now() - t0,
      question: request.userQuestion,
      events,
      flags: flags(reqRaw, card, expect, round),
      card,
    };
    results.push(row);
    console.log(
      `${id} r${round} ${res.status} ${card.responseType}/${card.mode} md=${card.messageDecision} ${
        row.flags.join(",") || "ok"
      } (${row.latencyMs}ms)`,
    );
    return card;
  }

  const queue = [...cases];
  const workers = Array.from({ length: concurrency }, async () => {
    while (queue.length) {
      const c = queue.shift()!;
      try {
        const card1 = await runOne(c.id, 1, c.request, c.expectRound1);
        if (c.followUp) {
          const isClar = card1.responseType === "clarifyingQuestion";
          const turns: Turn[] = [
            {
              role: "user",
              kind: "question",
              content: String(c.request.userQuestion),
            },
            {
              role: "coach",
              kind: isClar ? "clarification" : "answer",
              content: String(
                (isClar ? card1.reflectionQuestion : null) ?? card1.answer ??
                  "",
              ).slice(0, 500),
            },
          ];
          await runOne(
            c.id,
            2,
            {
              ...c.request,
              activeSessionTurns: turns,
              userQuestion: c.followUp,
            },
            null,
          );
        }
      } catch (e) {
        results.push({ id: c.id, error: String(e) });
        console.log(`${c.id} ERROR ${String(e).slice(0, 200)}`);
      }
    }
  });
  await Promise.all(workers);

  results.sort((a, b) =>
    String(a.id).localeCompare(String(b.id)) ||
    Number(a.round ?? 0) - Number(b.round ?? 0)
  );
  const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
  const dir = "tools/coach-blackbox/results";
  await Deno.mkdir(dir, { recursive: true });
  await Deno.writeTextFile(
    `${dir}/${label}-${stamp}.json`,
    JSON.stringify(results, null, 2),
  );
  const md = results.map((r) => {
    if (r.error) return `## ${r.id}\nERROR ${r.error}\n`;
    const c = r.card as Record<string, unknown>;
    return [
      `## ${r.id} r${r.round} — ${c.responseType}/${c.mode} md=${c.messageDecision} rd=${c.rewriteDecision} ft=${c.frictionType}`,
      `flags: ${(r.flags as string[]).join(", ") || "—"} | events: ${
        (r.events as string[]).join(" ")
      } | ${r.latencyMs}ms`,
      `**問**：${r.question}`,
      `**headline**：${c.headline}`,
      c.reflectionQuestion ? `**釐清問**：${c.reflectionQuestion}` : null,
      `**answer**：${c.answer}`,
      `**nextStep**：${c.nextStep}`,
      c.suggestedLine ? `**line**：${c.suggestedLine}` : "**line**：null",
      c.rewriteReason ? `**rewriteReason**：${c.rewriteReason}` : null,
      `**boundary**：${c.boundaryReminder}`,
      `**userState**：${c.userState}`,
      "",
    ].filter((x) => x != null).join("\n");
  }).join("\n");
  await Deno.writeTextFile(`${dir}/${label}-${stamp}.md`, md);
  const flagged = results.filter((r) => (r.flags as string[])?.length);
  console.log(
    `\n${results.length} cards, ${flagged.length} flagged → ${dir}/${label}-${stamp}.md`,
  );
}

if (import.meta.main) await main();
