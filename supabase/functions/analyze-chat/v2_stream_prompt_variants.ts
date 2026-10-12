// 對話分析 v2 串流提示詞上鎖用的四種組合（只給測試與快照工具用，入口 index.ts
// 不會載入，不隨函式部署）。組法照正式呼叫點 analyze_stream_handler.ts：
// noSendDecisions 與 divergencePlan 都開、選單由 offeredNoSendDecisions 決定、
// 風格由 streamReplyStylesForTier 決定。情境知識每次請求不同，不在鎖的範圍。
import { buildAnalyzeStreamSystemPrompt } from "./analyze_prompt.ts";
import { offeredNoSendDecisions } from "./no_send_decision.ts";
import { streamReplyStylesForTier } from "./tier_sync_contract.ts";

export const SNAPSHOT_PATH = "testdata/v2_stream_prompt_paid.txt";

type Message = { isFromMe: boolean };

// 讓 offeredNoSendDecisions 產生三種選單的代表對話。
const USUAL_EXCHANGE: Message[] = [
  { isFromMe: false },
  { isFromMe: true },
  { isFromMe: false },
  { isFromMe: true },
  { isFromMe: false },
];
const FIRST_EXCHANGE: Message[] = [{ isFromMe: true }, { isFromMe: false }];

function render(
  tier: "free" | "essential",
  messages: Message[],
  lowInvestment: boolean,
): string {
  return buildAnalyzeStreamSystemPrompt(streamReplyStylesForTier(tier), {
    noSendDecisions: true,
    situationKnowledge: [],
    divergencePlan: true,
    offeredNoSendDecisions: offeredNoSendDecisions(messages, lowInvestment),
  });
}

export interface V2PromptVariant {
  id: string;
  /** 只有最常見的組合存全文快照，其餘只鎖長度與雜湊。 */
  snapshot: boolean;
  render: () => string;
}

export const V2_PROMPT_VARIANTS: readonly V2PromptVariant[] = [
  {
    id: "paid_usual_menu",
    snapshot: true,
    render: () => render("essential", USUAL_EXCHANGE, false),
  },
  {
    id: "paid_low_investment_menu",
    snapshot: false,
    render: () => render("essential", USUAL_EXCHANGE, true),
  },
  {
    id: "paid_first_exchange_menu",
    snapshot: false,
    render: () => render("essential", FIRST_EXCHANGE, false),
  },
  {
    id: "free_usual_menu",
    snapshot: false,
    render: () => render("free", USUAL_EXCHANGE, false),
  },
];
