import type {
  ConsistencyTestType,
  PracticeDifficulty,
  PracticeProfile,
} from "./practice_persona.ts";

const TEST_TYPE_PROMPTS: Record<ConsistencyTestType, string> = {
  soft_reassurance: "柔和確認：用慢熱、忙、累或不確定來觀察對方會不會施壓。",
  light_tease: "吐槽：用輕鬆挑釁或小虧一句，看對方是否接得住玩笑。",
  counter_question: "反問：把球丟回去，看對方是否穩、是否有自己的想法。",
  playful_rating: "評分/標準：用半開玩笑的標準測對方會不會急著自證。",
  friend_card: "朋友牌：用「先當朋友」「你是不是都這樣」觀察對方是否失衡。",
  future_pacing: "未來感測試：丟一個模糊的下次/改天，看對方是否急著逼近。",
  boundary_check: "界線測試：提醒步調、距離或安全感，看對方是否尊重。",
};

export function formatConsistencyTestType(type: ConsistencyTestType): string {
  return TEST_TYPE_PROMPTS[type];
}

export function formatConsistencyTestTypes(
  types: readonly ConsistencyTestType[],
): string {
  return types.map(formatConsistencyTestType).join("；");
}

function difficultyLine(difficulty: PracticeDifficulty): string {
  if (difficulty === "easy") {
    return "輕鬆難度：小測試少量、柔和，丟了也要給台階，讓穩定幽默的回覆有機會加分。";
  }
  if (difficulty === "challenge") {
    return "挑戰難度：小測試可以更常、更尖銳，但仍要像真人個性，不要故意刁難或無理由翻臉。";
  }
  return "一般難度：小測試偶爾出現，力道接近交友軟體真人的試探與觀察。";
}

function propensityLine(
  propensity: PracticeProfile["consistencyTest"]["propensity"],
): string {
  if (propensity === "high") {
    return "這個角色較常用小測試觀察對方穩不穩。";
  }
  if (propensity === "medium") {
    return "這個角色偶爾會用小測試觀察對方穩不穩。";
  }
  return "這個角色很少丟小測試；只有在對方急、油、沒接住時才柔和觀察。";
}

export function buildConsistencyTestPrompt(profile: PracticeProfile): string {
  const testProfile = profile.consistencyTest;
  return `一致性小測試（你的自然個性，不要說破）：
- ${propensityLine(testProfile.propensity)}
- ${difficultyLine(profile.difficulty)}
- 可用形狀：${formatConsistencyTestTypes(testProfile.types)}
- 如果對方先承認、幽默曲解、反打得輕鬆、或低壓接住，你可以變得更願意聊。
- 如果對方防禦、自證、攻擊、討好或硬推進，你可以自然降溫、變短或吐槽。`;
}
