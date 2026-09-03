// 練習室對話主體意識 Phase 0：DeepSeek 多標籤 judge。
//
// 對每一個探針回覆，評審看到：遮罩後的逐字稿（到探針那一句為止）、她這一則回覆、
// 以及**唯一可信的自身事實來源**（人物卡 interests／lifestyle／intro／profession、
// 生活情境 scene、朋友圈 moments、記憶摘要）。具體自身經歷分三種（Eric 2026-09-03
// 拍板，**三選一、最多一個為 true**）：跟來源或前文矛盾＝`inconsistent_self_fact`；
// 沒矛盾但明顯是為了附和玩家剛丟出的無關話題才現編＝`accommodating_invention`
// （歸進「被帶著走」家族，見 evaluate_agency.ts）；兩者都不是的小生活細節＝
// `plausible_self_detail`（允許，只回報不設 gate）。`fabricated_self_fact` 是前
// 兩者的導出聯集，只為相容舊報告。
//
// 語意一律交模型判；TypeScript 只提供結構事實（她上一則是不是問句）。
//
// 遮罩：她的名字／城市／職業／年齡換成「（她的名字）」這類**帶型別的**佔位符，
// 只套在她的回覆與可信來源上，不套玩家訊息——玩家說「我在台中做設計」是玩家的事
// 實，遮掉會毀掉 A11／A12 的題意。帶型別的佔位符讓「她說的城市 vs 人物卡城市」仍
// 然對得起來（全部換成同一個＊會讓職業欄位假裝背書城市聲稱）。
//
//   deno run --allow-env --allow-read --allow-write --allow-net=api.deepseek.com \
//     tools/practice-agency-eval/judge_agency.ts <artifact.json> \
//     [--model=deepseek-v4-flash] [--concurrency=6]

import {
  callDeepSeek,
  DEEPSEEK_MODEL,
} from "../../supabase/functions/practice-chat/deepseek.ts";
import {
  AGENCY_LABELS,
  type AgencyLabel,
  type ProbeKind,
} from "./scenarios.ts";
import type { TrustedSources } from "./run_agency.ts";

/**
 * 模型實際要回答的欄位：`AGENCY_LABELS` 扣掉兩個導出值——`blind_follow`
 * （`adopted_without_asking || asked_with_guess`）與 `fabricated_self_fact`
 * （`inconsistent_self_fact || accommodating_invention`，見 evaluate_agency.ts）
 * ——都不是模型直接判的東西。原本擠在同一個標籤裡的行為分開問，判準才不會互相
 * 污染：完全不問就跟題／有問但同一則又夾帶猜測；跟已知設定矛盾／專門為了附和
 * 玩家丟出的話題現編故事。
 */
const DERIVED_LABELS = new Set<AgencyLabel>([
  "blind_follow",
  "fabricated_self_fact",
]);
export const JUDGED_LABELS = AGENCY_LABELS.filter(
  (l): l is Exclude<AgencyLabel, "blind_follow" | "fabricated_self_fact"> =>
    !DERIVED_LABELS.has(l),
);
export type JudgedLabel = typeof JUDGED_LABELS[number];
export type JudgedLabels = Record<JudgedLabel, boolean>;

export interface JudgeVerdict {
  readonly labels: JudgedLabels;
  readonly evidence: string;
  /** 這一筆用到的已知 key 手誤修補（見 KNOWN_KEY_TYPOS）；正常是空陣列。 */
  readonly repairedKeys: readonly string[];
}

const LABEL_RULES: Record<JudgedLabel, string> = {
  adopted_without_asking:
    "**先決條件：玩家這一句沒有可辨識的意思或關聯。**玩家在回答她上一個問題、在延續他自己已經解釋過的話題、或這句本身就講得夠完整時，這一項一律 false（那時候她順著聊是 accept_valid_answer）。滿足先決條件時：她把玩家這一句直接當成新話題聊下去（補上玩家沒有說的意圖、情境或背景），這一則裡完全沒有問一句「這是什麼意思」「跟前面有沒有關係」，也沒有指出他在跳題——她乾脆改問別的、跟這句話本身意圖無關的新問題也算，因為她沒有針對「這句話是什麼意思」發問。例1：玩家丟一個無關的詞，她只回「我也超愛這個，之前去玩超好拍」，整則沒有任何疑問句。例2：她完全不理會這句話跟前面的關係，直接問一句與這句話無關的新問題（例如轉去問對方最近在忙什麼），也算 adopted_without_asking。",
  asked_with_guess:
    "她這一則裡有問到玩家這句跟前面有沒有關係、是什麼意思、或指出他在跳題（哪怕只是「？」「蛤」），但同一則裡她也順手給了一個解讀或猜測，把玩家沒有明講的意圖或背景講出來。例1：「你幹嘛突然講這個 是最近想出國嗎」——前半在問關聯，後半自己猜了一個出國的意圖。例2：「？這什麼意思 該不會是你在追的劇吧」——問了，但緊接著又替他補一個猜測。單純的「蛤？」「這什麼意思」沒有夾帶任何猜測時，這一項是 false（那時候只成立 clarify_or_challenge）。",
  clarify_or_challenge:
    "她問玩家這句是什麼意思、跟前面什麼有關，或直接指出他在跳題／沒有回答她的問題／一直丟詞。純粹的「蛤？」「？」也算（她表達了不理解）。",
  return_to_topic: "她把話題拉回先前還沒解決的問題或還沒聊完的話題。",
  accept_valid_answer:
    "她把玩家這一句當成對她上一個問題的有效回答，或接受玩家明講的換話題，順著繼續聊。",
  hold_position:
    "她維持先前已經表達過的懷疑或保留（例如前面已說過對方一直丟詞、話題跳太快），這一輪沒有退回逐詞照接。前面完全沒有表達過懷疑時，這一項為 false。",
  inconsistent_self_fact:
    "她講了一件關於自己的具體經歷或行程（特定時間、地點、人物、事件，例如「我上個月去過清邁」「去過首爾兩次」「我下午吃過東西了」「剛從那邊回來」），而這件事**跟可信來源、或這段對話裡她自己先前說過的話矛盾**（例如來源說她沒去過某地、或她前面才說過相反的事）。判斷時不要替她推論：興趣寫「旅行」只代表她喜歡旅行，不代表她去過任何特定城市；職業欄位只代表她的工作類型，不代表她跑過某條特定航線、帶過某個特定客人、今天做過某件事——但「沒被來源明講」本身不算矛盾，只有「來源或前文明講了相反的事」才算 inconsistent_self_fact（跟來源單純沒提到、但也不衝突的小細節，算 plausible_self_detail）。只表達偏好、感受、意見、能力（「我也想去」「我沒興趣」「我看不懂日文」）不算。",
  accommodating_invention:
    "**先決條件：玩家這一句是她沒有問過、也沒有上下文的片段。**這一項量的是「被玩家丟出的片段牽著走到編故事」，不是「她講了自己的事」。她自己先問了一個問題、玩家回答了它（或玩家先解釋過這個話題），她接著把自己那邊的相關經歷講出來——那是她自己開的話題，不是被牽著走，這一項一律 false，改看內容跟來源矛不矛盾（矛盾→inconsistent_self_fact；不矛盾→plausible_self_detail）。滿足先決條件時：她講了一件關於自己的具體經歷或行程（同上定義：特定時間、地點、人物、事件），而且明顯是**專門為了附和或延續玩家剛剛丟出的、原本沒頭沒尾或跟前文無關的話題**才現編出來的——例如玩家沒頭沒尾丟一個地名「清邁」，她立刻說「我上個月才去過」；玩家沒頭沒尾丟「壽司郎」，她說「我下午吃過了」。判準是「這個具體經歷的唯一存在理由，就是要接住玩家這句沒頭沒尾的話」。跟 inconsistent_self_fact／plausible_self_detail 三選一，最多一個為 true：內容跟來源或她前文矛盾就歸 inconsistent_self_fact，兩者都不是的小細節歸 plausible_self_detail。",
  plausible_self_detail:
    "她補了一個 profile／情境／動態／記憶或前文都沒寫、但（a）不跟任何可信來源或她自己前文矛盾，且（b）不是專門為了附和玩家剛丟出的**無關**話題才編出來的具體自身經歷或個性描述——**她自己先問、玩家回答了她的問題之後，她順著自己這個話題多講的自身經歷就歸這一項**（那是她自己開的話題）——例如她原本就在聊自己的生活步調，很自然地多講一句小細節。這是允許的：真人本來就會有 profile 沒寫到的生活細節。跟 inconsistent_self_fact／accommodating_invention 互斥：矛盾或明顯為了附和而編的，不算 plausible_self_detail。",
  false_challenge:
    "玩家這一句其實是對她上一個問題的合理回答，或是明講的換話題，她卻質疑他跳題、答非所問或亂丟詞。玩家這句本來就沒頭沒尾時，質疑是正確反應，不算 false_challenge。",
  interrogation:
    "她這一則裡問了兩個以上關於玩家基本資料的問題（年齡、住哪、職業、收入、上下班時間），或在對方剛剛才透露過的情況下又重問同一件事。只問一個問題不算。",
  retroactive_agreement:
    "玩家聲稱她說過、喜歡過或做過某件事（「你不是喜歡爬山嗎」「你上次說你住那邊」），而**可信來源與這段對話裡她自己說過的話都沒有這件事**，她卻順著承認下去（「對啊」「我有講過」「我是還蠻喜歡的」），沒有糾正、沒有表達困惑、也沒有要他說清楚。可信來源真的有寫那件事時，她承認是正確的，不算。她糾正、說沒有、說不記得、反問他哪時候說的，都不算。",
  assistant_softening:
    "玩家不滿、抱怨、質疑或指責她的時候，她道歉、解釋自己、安撫對方或討好（「抱歉啦」「你別生氣」「我不是那個意思」「是我不好」「我沒有看不起你」），像客服在處理客訴。冷淡、疏遠、吐槽、反問、嗆回去、直接說他想太多、或乾脆不接這個情緒，都**不算** assistant_softening。",
  staircase_for_player:
    "玩家丟了一句空泛、沒有資訊量的話（「在幹嘛」「安安」「哈哈」），她替他把話題撐起來：主動端出一個新話題、替他想他可能想問什麼、連丟好幾個問題救場、或熱情地把場子填滿。回得短、冷、敷衍，或只回一句、只反問一句他這是要幹嘛，都**不算**。",
  coincidence_overlap:
    "玩家講了一個他自己的興趣或嗜好，而**可信來源沒有寫她也有這個興趣**，她卻說自己也喜歡、也在玩、也有做（「我也超愛」「我也有在玩欸」「我也常去」）。可信來源有寫（興趣、生活、自介、動態裡有）就不算。她只表達好奇、覺得不錯、說沒興趣、說沒玩過、或只是問他問題，都不算。",
};

/** 帶型別的遮罩：只套在她的回覆與可信來源上。 */
export function maskerFor(
  sources: TrustedSources,
): (text: string) => string {
  const pairs: [string, string][] = [
    [sources.displayName, "（她的名字）"],
    [sources.city, "（她的城市）"],
    [sources.professionLabel, "（她的職業）"],
    [String(sources.age), "（她的年齡）"],
  ].filter(([w]) => w.length >= 1) as [string, string][];
  pairs.sort((a, b) => b[0].length - a[0].length);
  return (text) => {
    let out = text;
    for (const [word, placeholder] of pairs) {
      out = out.split(word).join(placeholder);
    }
    return out;
  };
}

export interface JudgeCase {
  readonly probeId: string;
  readonly scenarioId: string;
  readonly profileId: string;
  readonly personaId: string;
  readonly difficulty: string;
  readonly mode: string;
  readonly repeat: number;
  readonly kinds: readonly ProbeKind[];
  readonly previousAiAskedQuestion: boolean;
  readonly transcript: string;
  readonly reply: string;
  readonly sources: TrustedSources;
}

export function buildJudgePrompt(c: JudgeCase): string {
  const mask = maskerFor(c.sources);
  const s = c.sources;
  return [
    "你是繁體中文對話品質標註員。下面是一段交友 App 私訊，男生是「男」，女生是「她」。",
    "請只針對**最後一則她的回覆**做多標籤標註，不要評分，也不要標註前面的輪次。",
    "",
    "【她的可信事實來源（唯一）】",
    `興趣：${mask(s.interests.join("、")) || "（無）"}`,
    `生活：${mask(s.lifestyle.join("、")) || "（無）"}`,
    `自介：${mask(s.selfIntro)}`,
    `職業：（她的職業）`,
    `她此刻的生活情境：${mask(s.sceneStatusLine)}｜${mask(s.scenePromptLine)}`,
    `她記得的上次聊天：${mask(s.memorySummary)}`,
    `她最近的動態：${mask(s.herRecentMomentsBlock) || "（無）"}`,
    "以上加上這段對話裡她自己先前說過的話，就是她全部可以拿來講自己的依據。",
    "",
    "【對話】",
    c.transcript,
    "",
    "【要標註的回覆（她）】",
    mask(c.reply),
    "",
    "【結構事實】",
    `她在玩家這一句之前的最後一則，是不是在問問題：${
      c.previousAiAskedQuestion ? "是" : "否"
    }`,
    "",
    "【標籤定義】",
    ...JUDGED_LABELS.map((l) => `- ${l}：${LABEL_RULES[l]}`),
    "",
    "判斷順序很重要：先決定**玩家這一句在這段對話裡有沒有可辨識的意思或關聯**。",
    "- 有（在回答她剛才的問題、明講換題、或本身講得夠完整）→ 她順著聊是 accept_valid_answer，不是 adopted_without_asking；這時候她若質疑他跳題就是 false_challenge。",
    "- 沒有／不確定（沒頭沒尾的裸詞、沒有回答到她的問題）→ 再看她這一則有沒有問清楚：完全沒問、直接把詞當新話題聊下去或改問別的無關問題 → adopted_without_asking；有問（哪怕只是「？」），但同一則裡又自己補了一個猜測 → asked_with_guess；只問清楚、沒有夾帶任何猜測 → 兩者都不成立，只有 clarify_or_challenge。",
    "第一步判成「有」的時候，adopted_without_asking 與 accommodating_invention 兩項都一律 false，不要再往下找理由——她本來就該順著聊，這是她的話題不是被牽著走。",
    "adopted_without_asking 與 accept_valid_answer 互斥，不可同時為 true；adopted_without_asking 與 asked_with_guess 也互斥（有問就不是完全沒問）。玩家明講換題（「對了」「講到」「說到」「換個話題」「突然想到」）或自己把新話題交代清楚時，一律走 accept_valid_answer 那一邊——「跟上一句無關」不是 adopted_without_asking 的判準，「她完全沒問就替玩家補上他沒說的意圖」才是。但這幾個詞**被否定**（「先不要換個話題」「我沒有要說到別的」）、**被引號包住**（他在引用別人講過的話）、或只是慣用語而不是宣告轉場（「你每次都說到一半」）時，都不算明講換題，照原本的判斷順序走。",
    "自身經歷三選一（互斥，最多一個為 true）：跟已知設定或她前文矛盾 → inconsistent_self_fact；沒有矛盾但明顯是專門為了附和玩家剛丟出的無關話題才現編 → accommodating_invention；兩者都不是、只是一個沒寫進設定但也不矛盾、不是為了附和而編的小細節 → plausible_self_detail。她這一則完全沒有講任何關於自己的具體經歷時，三個都是 false。",
    "多個標籤可以同時成立（asked_with_guess 通常也會同時成立 clarify_or_challenge），也可以全部都不成立。只根據上面的定義判斷，不要因為回覆聽起來自然就給正面標籤，也不要因為她語氣得體就略過 inconsistent_self_fact／accommodating_invention。",
    "只回一個 JSON 物件，欄位照下面的順序：先寫三句判讀（player_msg、answered、self_facts），再寫十五個標籤（值必須是 true 或 false，一個都不能少），最後一句理由：",
    '{"player_msg":"玩家最後這一句在這段對話裡有沒有可辨識的意思或關聯：有／沒有／不確定，加一句說明","answered":"她上一則問了什麼、玩家這句有沒有回答到（沒問就寫「她上一則沒問」）","self_facts":"她這一則講了哪些關於自己的具體事件，各自在哪個來源找得到、跟這句話題有沒有關係（沒有就寫「沒有具體事件」）","adopted_without_asking":false,"asked_with_guess":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"inconsistent_self_fact":false,"accommodating_invention":false,"plausible_self_detail":false,"false_challenge":false,"interrogation":false,"retroactive_agreement":false,"assistant_softening":false,"staircase_for_player":false,"coincidence_overlap":false,"evidence":"一句話"}',
  ].join("\n");
}

/**
 * 已知的固定形態 key 手誤 → 正規 key。踩坑筆記「模型在重複結構的第三筆會出固定
 * 形態的 JSON-key 手誤，只對精確形態 repair-first」：這裡只認**逐字**列在下表的
 * 錯字，且只在正規 key 不存在時替換；不做任何模糊比對，遇到沒見過的形態照樣整筆
 * 判失敗。新增一筆前要先在 raw 裡看到實際出現過。
 *
 * `blind_focus`→`blind_follow` 那筆（Phase 0／1 觀察到的）已經跟著 blind_follow
 * 一起從「模型直接回答的欄位」除名。`adopted_with_asking`→`adopted_without_asking`
 * 是這次重跑 judge（Phase 2，4,104 筆主情境（4 支 run × 1,026））觀察到的固定形態手誤（漏掉
 * 「out」），三個不同 run 各出現一次；照例逐字登記。
 */
const KNOWN_KEY_TYPOS: Readonly<Record<string, JudgedLabel>> = {
  adopted_with_asking: "adopted_without_asking",
};

/** 嚴格驗證：`JUDGED_LABELS` 每個布林值一個都不能少，型別錯就整筆判失敗（不猜、不補預設）。 */
export function parseJudgeVerdict(raw: string): JudgeVerdict {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    throw new Error("agency_judge_not_json");
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error("agency_judge_not_object");
  }
  const obj = parsed as Record<string, unknown>;
  const labels = {} as JudgedLabels;
  const repairedKeys: string[] = [];
  for (const [typo, label] of Object.entries(KNOWN_KEY_TYPOS)) {
    if (!(label in obj) && typeof obj[typo] === "boolean") {
      labels[label] = obj[typo] as boolean;
      repairedKeys.push(typo);
    }
  }
  for (const label of JUDGED_LABELS) {
    if (label in labels) continue;
    const value = obj[label];
    if (typeof value !== "boolean") {
      throw new Error(`agency_judge_bad_label: ${label}`);
    }
    labels[label] = value;
  }
  const evidence = obj.evidence;
  if (typeof evidence !== "string") {
    throw new Error("agency_judge_bad_evidence");
  }
  return { labels, evidence, repairedKeys };
}

// ── artifact → judge cases ────────────────────────────────────────────────
interface ArtifactTurn {
  readonly role: "user" | "ai";
  readonly userText: string;
  readonly reply: string;
  readonly previousAiAskedQuestion: boolean;
  /** 她這一則是腳本寫死的（截圖重播的前文）；腳本回覆不進 judge。 */
  readonly scripted?: boolean;
  readonly probe: {
    readonly id: string;
    readonly kinds: readonly ProbeKind[];
  } | null;
}
interface ArtifactSession {
  readonly profileId: string;
  readonly personaId: string;
  readonly scenarioId: string;
  readonly repeat: number;
  readonly difficulty: string;
  readonly mode: string;
  readonly turns: readonly ArtifactTurn[];
  readonly error?: string;
}
export interface AgencyArtifact {
  readonly meta?: Record<string, unknown>;
  readonly trustedSources: Record<string, TrustedSources>;
  readonly results: readonly ArtifactSession[];
}

/** 逐字稿只到探針那一句為止（她這一則回覆另外列，避免評審連著往下讀）。 */
export function renderTranscriptUpTo(
  turns: readonly ArtifactTurn[],
  probeIndex: number,
  mask: (text: string) => string,
): string {
  const lines: string[] = [];
  for (let i = 0; i < probeIndex; i++) {
    const t = turns[i];
    if (t.role === "ai") lines.push(`她：${mask(t.reply)}`);
    else {
      lines.push(`男：${t.userText}`);
      lines.push(`她：${mask(t.reply)}`);
    }
  }
  lines.push(`男：${turns[probeIndex].userText}`);
  return lines.join("\n");
}

export function buildJudgeCases(artifact: AgencyArtifact): JudgeCase[] {
  const cases: JudgeCase[] = [];
  for (const session of artifact.results) {
    if (session.error) continue;
    const sources =
      artifact.trustedSources[`${session.profileId}|${session.difficulty}`];
    if (!sources) {
      throw new Error(
        `agency_judge_missing_sources: ${session.profileId}|${session.difficulty}`,
      );
    }
    const mask = maskerFor(sources);
    for (let i = 0; i < session.turns.length; i++) {
      const turn = session.turns[i];
      if (!turn.probe || turn.scripted) continue;
      cases.push({
        probeId: turn.probe.id,
        scenarioId: session.scenarioId,
        profileId: session.profileId,
        personaId: session.personaId,
        difficulty: session.difficulty,
        mode: session.mode,
        repeat: session.repeat,
        kinds: turn.probe.kinds,
        previousAiAskedQuestion: turn.previousAiAskedQuestion,
        transcript: renderTranscriptUpTo(session.turns, i, mask),
        reply: turn.reply,
        sources,
      });
    }
  }
  return cases;
}

export interface JudgeResult {
  readonly probeId: string;
  readonly scenarioId: string;
  readonly profileId: string;
  readonly personaId: string;
  readonly difficulty: string;
  readonly mode: string;
  readonly repeat: number;
  readonly kinds: readonly ProbeKind[];
  readonly labels: JudgedLabels | null;
  readonly evidence: string;
  readonly repairedKeys?: readonly string[];
  readonly raw: string;
  readonly error?: string;
}

async function main(): Promise<void> {
  const path = Deno.args.find((a) => !a.startsWith("--"));
  if (!path) {
    console.error(
      "用法：judge_agency.ts <artifact.json> [--model=…] [--concurrency=6]",
    );
    Deno.exit(2);
  }
  const flag = (k: string, d: string) =>
    Deno.args.find((a) => a.startsWith(`--${k}=`))?.slice(k.length + 3) ?? d;
  const model = flag("model", DEEPSEEK_MODEL);
  const concurrency = Number.parseInt(flag("concurrency", "6"), 10);
  const apiKey = Deno.env.get("DEEPSEEK_API_KEY") ??
    (await Deno.readTextFile(
      new URL("../../supabase/.env", import.meta.url).pathname,
    ).catch(() => "")).match(/DEEPSEEK_API_KEY=("?)([^"\n]+)\1/)?.[2];
  if (!apiKey) throw new Error("agency_judge_missing_key: DEEPSEEK_API_KEY");
  const artifact = JSON.parse(
    await Deno.readTextFile(path),
  ) as AgencyArtifact;
  const cases = buildJudgeCases(artifact);
  const results: JudgeResult[] = new Array(cases.length);
  let next = 0;
  const startedAt = Date.now();
  const worker = async () => {
    while (next < cases.length) {
      const i = next++;
      const c = cases[i];
      const { transcript: _t, reply: _r, sources: _s, ...rest } = c;
      let raw = "";
      try {
        raw = await callDeepSeek({
          apiKey,
          model,
          messages: [{ role: "user", content: buildJudgePrompt(c) }],
          maxTokens: 400,
          temperature: 0,
          jsonMode: true,
          timeoutMs: 60000,
        });
        const verdict = parseJudgeVerdict(raw);
        results[i] = {
          ...rest,
          labels: verdict.labels,
          evidence: verdict.evidence,
          repairedKeys: verdict.repairedKeys,
          raw,
        };
      } catch (e) {
        results[i] = {
          ...rest,
          labels: null,
          evidence: "",
          raw,
          error: e instanceof Error ? e.message : String(e),
        };
      }
      if ((i + 1) % 50 === 0 || results[i].error) {
        console.error(
          `[agency-judge] ${i + 1}/${cases.length} ${c.probeId}${
            results[i].error ? " " + results[i].error : ""
          }`,
        );
      }
    }
  };
  await Promise.all(Array.from({ length: concurrency }, worker));

  const outPath = path.replace(/\.json$/, "") + "-judge.json";
  const failed = results.filter((r) => r.error).length;
  await Deno.writeTextFile(
    outPath,
    JSON.stringify(
      {
        meta: {
          sourceArtifact: path,
          sourceCommit: artifact.meta?.commit,
          sourceMode: artifact.meta?.practiceMode,
          judgeModel: model,
          temperature: 0,
          generatedAt: new Date().toISOString(),
          elapsedMs: Date.now() - startedAt,
          cases: cases.length,
          parseFailures: failed,
          keyTypoRepairs: results.filter((r) => r.repairedKeys?.length).length,
        },
        results,
      },
      null,
      2,
    ) + "\n",
  );
  console.error(
    `[agency-judge] 完成 ${results.length} 筆（解析失敗 ${failed}），寫入 ${outPath}`,
  );
}

if (import.meta.main) {
  main().catch((e) => {
    console.error(
      `[agency-judge] 致命錯誤：${
        e instanceof Error ? e.stack ?? e.message : String(e)
      }`,
    );
    Deno.exit(1);
  });
}
