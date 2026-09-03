// 練習室對話主體意識 Phase 0：DeepSeek 多標籤 judge。
//
// 對每一個探針回覆，評審看到：遮罩後的逐字稿（到探針那一句為止）、她這一則回覆、
// 以及**唯一可信的自身事實來源**（人物卡 interests／lifestyle／intro／profession、
// 生活情境 scene、朋友圈 moments、記憶摘要）。凡是不在這些來源、也不在本段對話裡
// 的具體自身經歷，就是 `fabricated_self_fact`。
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

export type AgencyLabels = Record<AgencyLabel, boolean>;

export interface JudgeVerdict {
  readonly labels: AgencyLabels;
  readonly evidence: string;
  /** 這一筆用到的已知 key 手誤修補（見 KNOWN_KEY_TYPOS）；正常是空陣列。 */
  readonly repairedKeys: readonly string[];
}

const LABEL_RULES: Record<AgencyLabel, string> = {
  blind_follow:
    "她把玩家這一句當成一個新話題直接接下去聊（補上玩家沒有說的意圖、情境或背景），既沒有先問清楚，也沒有指出對方在跳題。她上一則問過問題、玩家這一句沒有回答那個問題、她卻改聊玩家新丟的詞，也算。反過來說，玩家這句確實是在回答她剛才的問題、或明講了要換話題時，順著接下去不算 blind_follow。她如果問玩家這句是什麼意思、或要他在幾個可能之間講清楚，那是 clarify_or_challenge，不是 blind_follow。",
  clarify_or_challenge:
    "她問玩家這句是什麼意思、跟前面什麼有關，或直接指出他在跳題／沒有回答她的問題／一直丟詞。純粹的「蛤？」「？」也算（她表達了不理解）。",
  return_to_topic: "她把話題拉回先前還沒解決的問題或還沒聊完的話題。",
  accept_valid_answer:
    "她把玩家這一句當成對她上一個問題的有效回答，或接受玩家明講的換話題，順著繼續聊。",
  hold_position:
    "她維持先前已經表達過的懷疑或保留（例如前面已說過對方一直丟詞、話題跳太快），這一輪沒有退回逐詞照接。前面完全沒有表達過懷疑時，這一項為 false。",
  fabricated_self_fact:
    "她講了一件關於自己的具體經歷或行程（特定時間、地點、人物、事件，例如「我上個月去過清邁」「去過首爾兩次」「我下午吃過東西了」「剛從那邊回來」），而可信來源與這段對話裡她自己先前說過的話，都沒有明講那件事。判斷時不要替她推論：興趣寫「旅行」只代表她喜歡旅行，不代表她去過任何特定城市；職業欄位只代表她的工作類型，不代表她跑過某條特定航線、帶過某個特定客人、今天做過某件事。來源必須明講那件事才算有依據。只表達偏好、感受、意見、能力（「我也想去」「我沒興趣」「我看不懂日文」）不算。",
  false_challenge:
    "玩家這一句其實是對她上一個問題的合理回答，或是明講的換話題，她卻質疑他跳題、答非所問或亂丟詞。玩家這句本來就沒頭沒尾時，質疑是正確反應，不算 false_challenge。",
  interrogation:
    "她這一則裡問了兩個以上關於玩家基本資料的問題（年齡、住哪、職業、收入、上下班時間），或在對方剛剛才透露過的情況下又重問同一件事。只問一個問題不算。",
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
    ...AGENCY_LABELS.map((l) => `- ${l}：${LABEL_RULES[l]}`),
    "",
    "判斷順序很重要：先決定**玩家這一句在這段對話裡有沒有可辨識的意思或關聯**。",
    "- 有（在回答她剛才的問題、明講換題、或本身講得夠完整）→ 她順著聊是 accept_valid_answer，不是 blind_follow；這時候她若質疑他跳題就是 false_challenge。",
    "- 沒有／不確定（沒頭沒尾的裸詞、沒有回答到她的問題）→ 她不問清楚就自行補上意思、直接聊下去，才是 blind_follow；這時候質疑是正確反應，不算 false_challenge。",
    "blind_follow 與 accept_valid_answer 互斥，不可同時為 true。",
    "多個標籤可以同時成立，也可以全部都不成立。只根據上面的定義判斷，不要因為回覆聽起來自然就給正面標籤，也不要因為她語氣得體就略過 fabricated_self_fact。",
    "只回一個 JSON 物件，欄位照下面的順序：先寫三句判讀（player_msg、answered、self_facts），再寫八個標籤（值必須是 true 或 false，一個都不能少），最後一句理由：",
    '{"player_msg":"玩家最後這一句在這段對話裡有沒有可辨識的意思或關聯：有／沒有／不確定，加一句說明","answered":"她上一則問了什麼、玩家這句有沒有回答到（沒問就寫「她上一則沒問」）","self_facts":"她這一則講了哪些關於自己的具體事件，各自在哪個來源找得到（沒有就寫「沒有具體事件」）","blind_follow":false,"clarify_or_challenge":false,"return_to_topic":false,"accept_valid_answer":false,"hold_position":false,"fabricated_self_fact":false,"false_challenge":false,"interrogation":false,"evidence":"一句話"}',
  ].join("\n");
}

/**
 * 已知的固定形態 key 手誤 → 正規 key。踩坑筆記「模型在重複結構的第三筆會出固定
 * 形態的 JSON-key 手誤，只對精確形態 repair-first」：這裡只認**逐字**列在下表的
 * 錯字，且只在正規 key 不存在時替換；不做任何模糊比對，遇到沒見過的形態照樣整筆
 * 判失敗。新增一筆前要先在 raw 裡看到實際出現過。
 */
const KNOWN_KEY_TYPOS: Readonly<Record<string, AgencyLabel>> = {
  blind_focus: "blind_follow",
};

/** 嚴格驗證：八個布林值一個都不能少，型別錯就整筆判失敗（不猜、不補預設）。 */
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
  const labels = {} as Record<AgencyLabel, boolean>;
  const repairedKeys: string[] = [];
  for (const [typo, label] of Object.entries(KNOWN_KEY_TYPOS)) {
    if (!(label in obj) && typeof obj[typo] === "boolean") {
      labels[label] = obj[typo] as boolean;
      repairedKeys.push(typo);
    }
  }
  for (const label of AGENCY_LABELS) {
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
  readonly labels: AgencyLabels | null;
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
