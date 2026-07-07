export type InviteStage =
  | "not_ready"
  | "soft_invite_ready"
  | "direct_invite_ready"
  | "partner_window"
  | "high_intimacy";

export type InviteDateChance = "low" | "medium" | "high";

export interface InviteMaturity {
  score: number;
  stage: InviteStage;
  label: string;
  guidance: string;
  dateChance: InviteDateChance;
}

type PartnerMoodLike =
  | "neutral"
  | "curious"
  | "amused"
  | "comfortable"
  | "guarded"
  | "annoyed"
  | string;

function clampScore(score: number): number {
  if (!Number.isFinite(score)) return 0;
  return Math.max(0, Math.min(100, Math.round(score)));
}

function stageForScore(score: number): InviteStage {
  if (score >= 85) return "high_intimacy";
  if (score >= 80) return "partner_window";
  if (score >= 65) return "direct_invite_ready";
  if (score >= 50) return "soft_invite_ready";
  return "not_ready";
}

function stageRank(stage: InviteStage): number {
  return {
    not_ready: 0,
    soft_invite_ready: 1,
    direct_invite_ready: 2,
    partner_window: 3,
    high_intimacy: 4,
  }[stage];
}

function capStage(stage: InviteStage, maxStage: InviteStage): InviteStage {
  return stageRank(stage) > stageRank(maxStage) ? maxStage : stage;
}

function maturityForStage(stage: InviteStage): Omit<InviteMaturity, "score"> {
  switch (stage) {
    case "high_intimacy":
      return {
        stage,
        label: "高親密／類女友感",
        dateChance: "high",
        guidance:
          "可以呈現類女友感：她能主動丟出想見面的時間窗口，但仍要保留安全感與界線，不把親密推成必然結果。",
      };
    case "partner_window":
      return {
        stage,
        label: "她可釋出窗口",
        dateChance: "high",
        guidance:
          "她可以自然釋出空檔、暗示想被安排；使用者若接得穩，可順勢提出具體但低壓的見面安排。",
      };
    case "direct_invite_ready":
      return {
        stage,
        label: "可直接邀約",
        dateChance: "medium",
        guidance:
          "可以接受明確邀約，但仍要低壓、可拒絕、保留退路；避免把邀約寫成命令或交換。",
      };
    case "soft_invite_ready":
      return {
        stage,
        label: "可模糊邀約",
        dateChance: "medium",
        guidance:
          "適合模糊邀約：改天一起喝咖啡、下次帶妳去、哪天妳有空再說；先測她願不願意把話題延伸到線下。",
      };
    case "not_ready":
      return {
        stage,
        label: "暫不適合邀約",
        dateChance: "low",
        guidance:
          "先建立熟悉感與安全感，延續她的生活線索，不急著推線下或私人場景。",
      };
  }
}

export function inviteMaturityForScore(
  rawScore: number,
  opts: { partnerMood?: PartnerMoodLike | null } = {},
): InviteMaturity {
  const score = clampScore(rawScore);
  let stage = stageForScore(score);
  const mood = opts.partnerMood;
  if (mood === "guarded") {
    stage = capStage(stage, "direct_invite_ready");
  } else if (mood === "annoyed") {
    stage = capStage(stage, "soft_invite_ready");
  }
  const maturity = maturityForStage(stage);
  const guardedNote = mood === "guarded" || mood === "annoyed"
    ? ` partnerMood=${mood}，所以先降一階處理，避免硬推。`
    : "";
  return {
    score,
    ...maturity,
    guidance: `${maturity.guidance}${guardedNote}`,
  };
}

export function inviteMaturityFromLearningScores(opts: {
  temperatureScore?: number | null;
  familiarityScore?: number | null;
  partnerMood?: PartnerMoodLike | null;
}): InviteMaturity | null {
  if (opts.temperatureScore === undefined || opts.temperatureScore === null) {
    return null;
  }
  const heat = clampScore(opts.temperatureScore);
  const familiarity = clampScore(opts.familiarityScore ?? 0);
  const score = Math.round(heat * 0.6 + familiarity * 0.4);
  return inviteMaturityForScore(score, { partnerMood: opts.partnerMood });
}

export function inviteMaturityPrompt(
  maturity?: InviteMaturity | null,
): string {
  if (!maturity) return "";
  return `\n\ninviteMaturity(hidden guidance)\nrelationshipScore: ${maturity.score}/100\ninviteStage: ${maturity.stage}\nlabel: ${maturity.label}\ndateChance: ${maturity.dateChance}\nguidance: ${maturity.guidance}\n不要向使用者或角色明講分數、階段名或規則；把它當作線下邀約成熟度的隱藏邊界。`;
}
