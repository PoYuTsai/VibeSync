// reply-style-v1：跨回合的 style 狀態（存在 practice_relationship_threads.recent_facts）。
//
// 只存結構化代碼：她自己前幾輪 plan 的 primaryAct、以及「她已明確拒絕過邀約」。
// 不存文字、不存分數。舊 thread 沒有這個 key＝初始狀態；壞資料一律當初始狀態。

import type { ReplyAct, TurnResponsePlan } from "./turn_response_plan.ts";

export const REPLY_STYLE_STATE_KEY = "replyStyle";
const RECENT_ACTS_MAX = 3;
const ACT_RE = /^[a-z_]{3,20}$/;

export interface ReplyStyleState {
  readonly version: 1;
  readonly priorDecline: boolean;
  readonly recentActs: readonly ReplyAct[];
}

export const INITIAL_REPLY_STYLE_STATE: ReplyStyleState = {
  version: 1,
  priorDecline: false,
  recentActs: [],
};

/** 從 thread 的 recent_facts（任意 JSON）讀出狀態；缺或壞＝null。 */
export function parseReplyStyleState(
  recentFacts: unknown,
): ReplyStyleState | null {
  if (typeof recentFacts !== "object" || recentFacts === null) return null;
  const raw = (recentFacts as Record<string, unknown>)[REPLY_STYLE_STATE_KEY];
  if (typeof raw !== "object" || raw === null) return null;
  const r = raw as Record<string, unknown>;
  if (r.version !== 1) return null;
  const acts = Array.isArray(r.recentActs)
    ? r.recentActs.filter((a): a is ReplyAct =>
      typeof a === "string" && ACT_RE.test(a)
    ).slice(-RECENT_ACTS_MAX)
    : [];
  return {
    version: 1,
    priorDecline: r.priorDecline === true,
    recentActs: acts,
  };
}

/**
 * 這回合的 plan 決定下一個狀態。「明確拒絕過」只認結構化來源：stance 已是 decline，
 * 或邀約輪她用 direct_boundary 回（soft_deflect 是帶開，不算明確拒絕）。
 */
export function nextReplyStyleState(
  prev: ReplyStyleState | null,
  plan: TurnResponsePlan,
): ReplyStyleState {
  const base = prev ?? INITIAL_REPLY_STYLE_STATE;
  const declinedNow = plan.policyStance === "decline" ||
    (plan.situation === "early_invite" &&
      plan.primaryAct === "direct_boundary");
  return {
    version: 1,
    priorDecline: base.priorDecline || declinedNow,
    recentActs: [...base.recentActs, plan.primaryAct].slice(-RECENT_ACTS_MAX),
  };
}
