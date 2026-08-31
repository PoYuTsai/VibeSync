// Batch B3：邀約政策的單一真相源。generation（deterministic 守門）與
// prompts（第一回合就告知模型）都從這裡讀，避免詞群/規則兩處漂移。

// R2 主審 P1-2（Batch A）：補「週六要不要吃飯？」「想不想喝咖啡」這類
// 沒有「約」字的常見邀約句型。
export const LINE_INVITE_RE =
  /約|(?:要不要|想不想)[^？?。]{0,8}(?:吃|喝|見|出來|去|碰面|一起)|一起(?:去|吃|看|喝)|見(?:個)?面|出來(?:走走|坐坐|聊聊)/;

export type SentAdviceOutcomeLike = {
  summary: string;
  outcome: string;
};

const NO_UPTAKE_OUTCOMES = new Set(["cold", "noReply", "negative"]);

/// 兩次未承接 deterministic 禁再邀：inviteHistory（由舊到新）裡被
/// LINE_INVITE_RE 分到「邀約」的最近兩筆，若都未承接（cold/noReply/
/// negative；pending/unknown 誠實不判）→ 本輪禁止建議句再邀約。
/// forceAnswer 不豁免——逃生門只管「要不要正式答案」，不管邀約安全。
export function shouldSuppressInviteLine(
  history: readonly SentAdviceOutcomeLike[] | undefined,
): boolean {
  if (!history || history.length === 0) return false;
  const invites = history.filter((entry) => LINE_INVITE_RE.test(entry.summary));
  if (invites.length < 2) return false;
  return invites
    .slice(-2)
    .every((entry) => NO_UPTAKE_OUTCOMES.has(entry.outcome));
}
