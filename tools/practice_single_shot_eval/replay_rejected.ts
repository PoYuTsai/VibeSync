// 被拒候選重放診斷儀（取代一次性 replay_r6.ts，落 repo 免重建）。
// 讀 eval 結果 JSON 的 rejectedCandidates，直接 import 現行 prod gate 模組
// 逐筆重放：重現 code＋逐欄定位（grounding 失敗欄、unsupported fact claim
// 錨點、洩漏詞最小子串、invite decision 分路）。純本地，不打 API。
//
// 跑法：
//   deno run --allow-read --allow-env replay_rejected.ts --file=results/<檔>.json
import {
  buildHintDecision,
  hintTrustedFactualEvidence,
  parseHintResult,
} from "../../supabase/functions/practice-chat/hint.ts";
import { parseDebriefCard } from "../../supabase/functions/practice-chat/debrief_card.ts";
import { resolvePracticeProfile } from "../../supabase/functions/practice-chat/practice_persona.ts";
import { assertPracticeTextGroundedInTurns } from "../../supabase/functions/practice-chat/practice_visible_quality.ts";
import {
  buildHintFactContext,
  claimConfidence,
  collectUnsupportedHintFactClaims,
  type HintFactContext,
} from "../../supabase/functions/practice-chat/hint_fact_ledger.ts";
import {
  hasVisibleInternalLabelLeak,
  hasVisibleTemperatureMechanismLeak,
} from "../../supabase/functions/practice-chat/visible_text_guard.ts";
import { type EvalFixture, FIXTURES_BY_ROUTE } from "./fixtures/index.ts";

const SERVER_HINT_DECISION_RATIONALE =
  "只依據本場逐字稿與已知角色資料；貼句已依目前關係階段與邀約路線校驗。";

interface ShotRecord {
  route: keyof typeof FIXTURES_BY_ROUTE;
  fixtureId: string;
  repeatIndex: number;
  outcome: string;
  attemptFailureCodes: string[];
  rejectedCandidates?: Array<{ code: string; raw: string }>;
}

function fileArg(): string {
  for (const arg of Deno.args) {
    if (arg.startsWith("--file=")) return arg.slice("--file=".length);
  }
  throw new Error("需要 --file=results/<檔>.json");
}

/** 把候選 raw JSON 拍平成 路徑→字串（gameBreakdown 巢狀展開）。 */
function flattenFields(
  value: unknown,
  prefix = "",
): Array<[string, string]> {
  const out: Array<[string, string]> = [];
  if (typeof value === "string") {
    if (prefix) out.push([prefix, value]);
    return out;
  }
  if (Array.isArray(value)) {
    value.forEach((item, index) => {
      out.push(...flattenFields(item, `${prefix}[${index}]`));
    });
    return out;
  }
  if (value && typeof value === "object") {
    for (const [key, child] of Object.entries(value)) {
      out.push(...flattenFields(child, prefix ? `${prefix}.${key}` : key));
    }
  }
  return out;
}

/** 用前後綴收縮找出讓 guard 命中的最小子串（定位洩漏詞用）。 */
function localizeGuardHit(
  text: string,
  guard: (value: string) => boolean,
): string {
  if (!guard(text)) return "";
  let start = 0;
  let end = text.length;
  while (start < end && guard(text.slice(start + 1, end))) start += 1;
  while (end > start && guard(text.slice(start, end - 1))) end -= 1;
  return text.slice(start, end);
}

function reportFieldDiagnostics(opts: {
  fields: Array<[string, string]>;
  coachingFieldPattern: RegExp;
  pasteableFieldPattern: RegExp;
  factContext: HintFactContext;
  turns: EvalFixture["turns"];
  groundedFields: string[];
}): void {
  for (const [path, text] of opts.fields) {
    const notes: string[] = [];
    if (hasVisibleTemperatureMechanismLeak(text)) {
      notes.push(
        `temperature_leak 最小命中=「${
          localizeGuardHit(text, hasVisibleTemperatureMechanismLeak)
        }」`,
      );
    }
    if (hasVisibleInternalLabelLeak(text)) {
      notes.push(
        `internal_label_leak 最小命中=「${
          localizeGuardHit(text, hasVisibleInternalLabelLeak)
        }」`,
      );
    }
    const fieldKind = opts.coachingFieldPattern.test(path)
      ? "coaching"
      : opts.pasteableFieldPattern.test(path)
      ? "reply"
      : null;
    if (fieldKind) {
      const unsupported = collectUnsupportedHintFactClaims({
        text,
        field: fieldKind,
        context: opts.factContext,
      });
      for (const claim of unsupported) {
        notes.push(
          `unsupported(${fieldKind}) ${claim.owner}:${claim.domain}:${claim.relation} anchor=「${claim.anchor}」conf=${
            claimConfidence(claim)
          }`,
        );
      }
    }
    if (opts.groundedFields.includes(path)) {
      try {
        assertPracticeTextGroundedInTurns({
          visibleText: text,
          turns: [...opts.turns],
          errorCode: "not_grounded",
        });
      } catch {
        notes.push("grounding 零詞面重疊（全窗）");
      }
    }
    if (notes.length > 0) {
      console.log(`    [${path}]「${text}」`);
      for (const note of notes) console.log(`      → ${note}`);
    }
  }
}

async function main(): Promise<void> {
  const data = JSON.parse(await Deno.readTextFile(fileArg())) as {
    shots: ShotRecord[];
  };
  const failed = data.shots.filter((shot) =>
    (shot.rejectedCandidates?.length ?? 0) > 0
  );
  console.log(`共 ${failed.length} 發帶被拒候選\n`);
  for (const shot of failed) {
    const fixture = (FIXTURES_BY_ROUTE[shot.route] as EvalFixture[]).find(
      (f) => f.id === shot.fixtureId,
    );
    if (!fixture) {
      console.log(`!! 找不到 fixture ${shot.route}/${shot.fixtureId}，跳過`);
      continue;
    }
    const profile = resolvePracticeProfile(fixture.profileArgs);
    const evidence = hintTrustedFactualEvidence({
      profile,
      practiceMode: fixture.practiceMode,
      sceneContext: null,
      memorySummary: fixture.memorySummary,
    });
    const factContext = buildHintFactContext({
      turns: fixture.turns,
      sharedFactualEvidence: evidence.shared,
      partnerFactualEvidence: evidence.partner,
      trustedFactClaims: evidence.claims,
    });
    const isHint = shot.route.endsWith("_hint");
    console.log(
      `═══ ${shot.route} ${shot.fixtureId} r${shot.repeatIndex} (${shot.outcome}) recorded=${
        shot.attemptFailureCodes.join(",")
      }`,
    );
    for (const [ci, candidate] of (shot.rejectedCandidates ?? []).entries()) {
      console.log(`  ── 候選 c${ci + 1} recorded_code=${candidate.code}`);
      let replayCode = "PASS";
      try {
        if (isHint) {
          const parsed = parseHintResult(candidate.raw, {
            mode: fixture.practiceMode,
            turns: fixture.turns,
            sharedFactualEvidence: evidence.shared,
            partnerFactualEvidence: evidence.partner,
            trustedFactClaims: evidence.claims,
            enforceGeneratedQuality: true,
            relaxSubjectiveQualityRubrics: true,
          });
          for (const reply of parsed.replies) {
            buildHintDecision({
              turns: fixture.turns,
              profile,
              practiceMode: fixture.practiceMode,
              temperatureScore: fixture.temperatureScore,
              familiarityScore: fixture.familiarityScore,
              partnerMood: fixture.partnerMood,
              gameState: fixture.gameState,
              replyType: reply.type,
              replyText: reply.text,
              rationale: SERVER_HINT_DECISION_RATIONALE,
            });
          }
        } else {
          parseDebriefCard(candidate.raw, {
            allowGameBreakdown: fixture.practiceMode === "game",
            requireCompleteCard: true,
            turns: fixture.turns,
            appliedHintTurns: fixture.appliedHintTurns,
            repairPreservedHintCritique: false,
            sharedFactualEvidence: evidence.shared,
            partnerFactualEvidence: evidence.partner,
            trustedFactClaims: evidence.claims,
            enforceGeneratedQuality: true,
            relaxSubjectiveQualityRubrics: true,
          });
        }
      } catch (error) {
        replayCode = error instanceof Error ? error.message : String(error);
      }
      console.log(`    replay=${replayCode}`);
      let rawObject: unknown;
      try {
        rawObject = JSON.parse(candidate.raw);
      } catch {
        console.log("    （raw 不是合法 JSON，略過逐欄診斷）");
        continue;
      }
      const fields = flattenFields(rawObject);
      reportFieldDiagnostics({
        fields,
        coachingFieldPattern: isHint
          ? /^coaching$/
          : /^(summary|strengths|watchouts|vibe|dateChanceReason|nextInviteMove|gameBreakdown\.(phaseReached|missedVariable|failureState|inviteDirection))/,
        pasteableFieldPattern: isHint
          ? /^(warmUp|steady)$/
          : /^(suggestedLine|gameBreakdown\.nextFirstLine)$/,
        factContext,
        turns: fixture.turns,
        groundedFields: isHint
          ? ["warmUp", "steady", "coaching"]
          : ["suggestedLine", "gameBreakdown.nextFirstLine"],
      });
      // Game hint 額外分解 invite decision：兩句各自單獨重放取得分路錯誤。
      if (isHint && fixture.practiceMode === "game") {
        const rawFields = rawObject as Record<string, string>;
        for (const replyType of ["warm_up", "steady"] as const) {
          const replyText =
            rawFields[replyType === "warm_up" ? "warmUp" : "steady"];
          if (typeof replyText !== "string") continue;
          try {
            buildHintDecision({
              turns: fixture.turns,
              profile,
              practiceMode: fixture.practiceMode,
              temperatureScore: fixture.temperatureScore,
              familiarityScore: fixture.familiarityScore,
              partnerMood: fixture.partnerMood,
              gameState: fixture.gameState,
              replyType,
              replyText,
              rationale: SERVER_HINT_DECISION_RATIONALE,
            });
          } catch (error) {
            console.log(
              `    [decision:${replyType}] → ${
                error instanceof Error ? error.message : error
              }`,
            );
          }
        }
      }
    }
    console.log("");
  }
}

if (import.meta.main) {
  await main();
}
