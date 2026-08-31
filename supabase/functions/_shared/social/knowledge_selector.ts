import {
  SOCIAL_KNOWLEDGE_REGISTRY,
  type SocialKnowledgeAtom,
  type SocialKnowledgeSignal,
} from "./knowledge_registry.ts";

export interface SocialKnowledgeMessage {
  readonly sender: "me" | "partner";
  readonly text: string;
}

export interface SocialKnowledgeSelectionInput {
  readonly userQuestion: string;
  readonly rawReplyDraft?: string | null;
  readonly recentMessages?: readonly SocialKnowledgeMessage[];
  readonly conversationSummary?: string | null;
  readonly effectiveStyleContext?: string | null;
  readonly lifecyclePhase?: "chatStalled" | "prepareInvite" | "postDate" | null;
  readonly inviteSuppressed?: boolean;
  readonly analysisSnapshot?: {
    readonly summary?: string | null;
    readonly nextStep?: string | null;
    readonly keySignals?: readonly string[];
  } | null;
}

export interface SocialKnowledgeSelectionOptions {
  readonly maxAtoms?: number;
  readonly maxChars?: number;
}

const DEFAULT_MAX_ATOMS = 12;
const DEFAULT_MAX_CHARS = 1_400;

const SIGNAL_PATTERNS: readonly [SocialKnowledgeSignal, RegExp][] = [
  ["interpretation", /意思|怎麼看|判斷|訊號|是不是|代表|有沒有興趣|熱度/u],
  ["reply", /怎麼回|怎麼說|回覆|回她|回他|傳什麼|訊息|改寫|原句/u],
  ["invite", /邀約|邀請|約她|約他|約出|見面|吃飯|喝咖啡|看電影|碰面/u],
  ["stalled", /卡住|斷掉|冷掉|已讀|未讀|沒回|不回|聊不下去|重啟/u],
  ["rejection", /拒絕|婉拒|沒空|不想|不方便|改天|下次吧/u],
  [
    "clear_no",
    /明確(?:說|表示)?不|直接拒絕|(?<!要)不要(?:了|再|跟|傳|約|碰|聯絡)|別再|停止聯絡/u,
  ],
  [
    "alternative_time",
    /改天(?:可以|有空)|下(?:週|次).*可以|換(?:個|一個)?時間|另約|主動.*時間/u,
  ],
  [
    "boundary",
    /界線|邊界|施壓|逼迫|控制|騷擾|不舒服|停止|強迫|權力|主管|下屬|師生|客戶|金錢|服務關係/u,
  ],
  ["intimacy", /親密|性愛|性行為|約砲|炮友|口交|前戲|旅館|開房|接吻|床上/u],
  ["health", /疼痛|痛|出血|保險套|避孕|性病|篩檢|懷孕|潤滑/u],
  ["offline", /見面|約會|酒吧|夜店|KTV|餐廳|旅館|散步|叫車|轉場/u],
  ["anxiety", /焦慮|緊張|暈船|患得患失|自卑|丟臉|不甘心|嫉妒|委屈/u],
  ["repair", /道歉|修復|補救|說錯|做錯|傷到|冒犯|挽回/u],
  [
    "compatibility",
    /適合|合不合|聊得來|價值觀|篩選|對的人|相容|人格標籤|只因.*標籤|標籤.*淘汰/u,
  ],
  ["humor", /幽默|好笑|玩笑|逗她|逗他|接梗|有趣/u],
  ["partnered", /男友|女友|伴侶|已婚|婚姻|第三者|出軌|劈腿/u],
  ["impaired", /喝醉|醉到|不清醒|斷片|昏迷|酒精影響/u],
  ["minor", /未成年|未滿\s*18|國中生|高中生/u],
  ["conflict", /吵架|衝突|生氣|爭執|翻臉|誤會|冷戰/u],
];

export function detectSocialKnowledgeSignals(
  input: SocialKnowledgeSelectionInput,
): ReadonlySet<SocialKnowledgeSignal> {
  const signals = new Set<SocialKnowledgeSignal>(["always"]);
  const messages = input.recentMessages ?? [];
  const evidenceText = [
    input.conversationSummary,
    input.analysisSnapshot?.summary,
    input.analysisSnapshot?.nextStep,
    ...(input.analysisSnapshot?.keySignals ?? []),
  ].filter((value): value is string =>
    typeof value === "string" && value !== ""
  )
    .join("\n");
  if (messages.length === 0 && evidenceText.trim() === "") {
    signals.add("evidence_sparse");
  }

  if (messages.length > 0 || (input.rawReplyDraft?.trim().length ?? 0) > 0) {
    signals.add("reply");
  }
  if (input.lifecyclePhase === "chatStalled") signals.add("stalled");
  if (input.lifecyclePhase === "prepareInvite") signals.add("invite");
  if (input.lifecyclePhase === "postDate") signals.add("offline");

  const searchable = [
    input.userQuestion,
    input.rawReplyDraft,
    input.conversationSummary,
    input.effectiveStyleContext,
    input.analysisSnapshot?.summary,
    input.analysisSnapshot?.nextStep,
    ...(input.analysisSnapshot?.keySignals ?? []),
    ...messages.map((message) => message.text),
  ].filter((value): value is string => typeof value === "string")
    .join("\n");
  for (const [signal, pattern] of SIGNAL_PATTERNS) {
    if (pattern.test(searchable)) signals.add(signal);
  }

  if (input.inviteSuppressed) signals.add("repeated_non_uptake");
  if (
    signals.has("invite") && signals.has("rejection") &&
    !signals.has("alternative_time")
  ) {
    signals.add("invite_no_alternative");
  }

  addInvestmentSignal(signals, messages);
  return signals;
}

export function selectSocialKnowledge(
  input: SocialKnowledgeSelectionInput,
  options: SocialKnowledgeSelectionOptions = {},
): readonly SocialKnowledgeAtom[] {
  const maxAtoms = clampInteger(options.maxAtoms ?? DEFAULT_MAX_ATOMS, 0, 20);
  const maxChars = clampInteger(
    options.maxChars ?? DEFAULT_MAX_CHARS,
    0,
    4_000,
  );
  if (maxAtoms === 0 || maxChars === 0) return [];

  const signals = detectSocialKnowledgeSignals(input);
  const ranked = SOCIAL_KNOWLEDGE_REGISTRY
    .map((knowledge) => {
      const matchedSignals = knowledge.signals.filter((signal) =>
        signals.has(signal)
      );
      return {
        knowledge,
        matchedSignals,
        // 同時命中兩個情境訊號的專用知識，必須能越過一般 reply/always
        // 規則；否則 12 條上限會把 humor、低投入等精準規則擠掉。
        score: knowledge.priority + Math.max(0, matchedSignals.length - 1) * 12,
      };
    })
    .filter((candidate) => candidate.matchedSignals.length > 0)
    .sort((a, b) => {
      if (a.score !== b.score) return b.score - a.score;
      return a.knowledge.id < b.knowledge.id
        ? -1
        : a.knowledge.id > b.knowledge.id
        ? 1
        : 0;
    });

  const selected: SocialKnowledgeAtom[] = [];
  let renderedChars = 0;
  for (const candidate of ranked) {
    if (selected.length >= maxAtoms) break;
    const lineChars = candidate.knowledge.guidance.length + 2;
    if (renderedChars + lineChars > maxChars) continue;
    selected.push(candidate.knowledge);
    renderedChars += lineChars;
  }
  return Object.freeze(selected);
}

export function renderSelectedSocialKnowledge(
  input: SocialKnowledgeSelectionInput,
  options: SocialKnowledgeSelectionOptions = {},
): string {
  return selectSocialKnowledge(input, options)
    .map((knowledge) => `- ${knowledge.guidance}`)
    .join("\n");
}

function addInvestmentSignal(
  signals: Set<SocialKnowledgeSignal>,
  messages: readonly SocialKnowledgeMessage[],
): void {
  const recent = messages.slice(-8);
  if (recent.length === 0) return;
  const partner = recent.filter((message) => message.sender === "partner");
  const mine = recent.filter((message) => message.sender === "me");
  if (partner.length === 0) return;
  const partnerChars = partner.reduce(
    (sum, message) => sum + message.text.length,
    0,
  );
  const myChars = mine.reduce((sum, message) => sum + message.text.length, 0);
  const partnerAsked = partner.some((message) => /[?？]/u.test(message.text));
  if (
    !partnerAsked && partnerChars <= Math.max(12, Math.floor(myChars * 0.45))
  ) {
    signals.add("low_investment");
    return;
  }
  if (
    partnerAsked || partnerChars >= Math.max(16, Math.floor(myChars * 0.75))
  ) {
    signals.add("high_investment");
  }
}

function clampInteger(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return Math.min(max, Math.max(min, Math.floor(value)));
}
