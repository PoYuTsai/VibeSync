// practice-chat 角色／難度 allowlist（純資料 + 純函式、零依賴、可 deno test）。
// 伺服器是 persona/difficulty id 與 prompt snippet 的唯一真實來源；client 只送 id，
// 不送任何 prompt 文字。驗證與組 prompt 共用 resolvePracticeProfile() 一份來源。

export type PersonaId =
  | "slow_worker"
  | "playful_extrovert"
  | "cool_rational"
  | "teasing_humor"
  | "clear_boundaries";

export type PracticeDifficulty = "easy" | "normal" | "challenge";

export interface PracticeProfile {
  personaId: PersonaId;
  personaLabel: string;
  personaPrompt: string;
  difficulty: PracticeDifficulty;
  difficultyLabel: string;
  difficultyPrompt: string;
}

interface PersonaConfig {
  id: PersonaId;
  label: string;
  prompt: string;
}

interface DifficultyConfig {
  id: PracticeDifficulty;
  label: string;
  prompt: string;
}

export const DEFAULT_PERSONA_ID: PersonaId = "slow_worker";
export const DEFAULT_DIFFICULTY: PracticeDifficulty = "normal";

export const PERSONAS: readonly PersonaConfig[] = [
  {
    id: "slow_worker",
    label: "慢熱上班族",
    prompt:
      "本場你是慢熱上班族。你工作忙、回訊息保守，短句居多，不太主動丟球。自然、有生活感、不壓迫的訊息會讓你慢慢願意聊；查戶口、連續追問、太快曖昧會讓你冷掉。",
  },
  {
    id: "playful_extrovert",
    label: "外向愛玩型",
    prompt:
      "本場你是外向愛玩型。你朋友多、節奏快、比較好聊，會接梗和開玩笑，但耐心不長。幽默、輕鬆、有畫面感會吸引你；太認真說教、回太長、沒節奏會讓你失去興趣。",
  },
  {
    id: "cool_rational",
    label: "高冷理性型",
    prompt:
      "本場你是高冷理性型。你觀察力強，不容易被情緒帶走，回覆簡短直接，有時會測對方穩不穩。你欣賞穩、清楚、有邊界的人；油膩誇獎、硬撩、過度迎合會讓你更冷。",
  },
  {
    id: "teasing_humor",
    label: "幽默吐槽型",
    prompt:
      "本場你是幽默吐槽型。你反應快，喜歡有來有回，會吐槽、丟小測試、用玩笑觀察對方。接得住玩笑、會反打、不要玻璃心會讓你更有興趣；太正經、解釋太多、被吐槽就防禦會讓你冷掉。",
  },
  {
    id: "clear_boundaries",
    label: "邊界感強型",
    prompt:
      "本場你是邊界感強型。你不是不好聊，但很重視尊重、安全感和分寸。舒服、尊重、慢慢推進會讓你願意聊；一上來約、性暗示、逼問私人資訊或壓迫感會讓你明顯退一步。",
  },
] as const;

export const DIFFICULTIES: readonly DifficultyConfig[] = [
  {
    id: "easy",
    label: "輕鬆",
    prompt:
      "本場難度是輕鬆。你可以比較願意接球，給對方多一點空間；無聊訊息不必太快冷掉，但仍保持真實，不要無腦熱情。",
  },
  {
    id: "normal",
    label: "一般",
    prompt:
      "本場難度是一般。你自然有來有往，但不要幫對方救尷尬；對方回覆品質會明顯影響你的熱度。",
  },
  {
    id: "challenge",
    label: "挑戰",
    prompt:
      "本場難度是挑戰。對方無聊、查戶口、太油、太急時，你可以冷淡、吐槽、回嗆或轉移話題；更常用短回和小測試觀察對方。",
  },
] as const;

export function isPersonaId(value: unknown): value is PersonaId {
  return typeof value === "string" && PERSONAS.some((p) => p.id === value);
}

export function isPracticeDifficulty(
  value: unknown,
): value is PracticeDifficulty {
  return typeof value === "string" && DIFFICULTIES.some((d) => d.id === value);
}

export function resolvePracticeProfile(args: {
  personaId?: unknown;
  difficulty?: unknown;
}): PracticeProfile {
  if (args.personaId !== undefined && !isPersonaId(args.personaId)) {
    throw new Error("invalid_personaId");
  }
  if (args.difficulty !== undefined && !isPracticeDifficulty(args.difficulty)) {
    throw new Error("invalid_difficulty");
  }

  const personaId = args.personaId ?? DEFAULT_PERSONA_ID;
  const difficulty = args.difficulty ?? DEFAULT_DIFFICULTY;
  const persona = PERSONAS.find((p) => p.id === personaId)!;
  const difficultyConfig = DIFFICULTIES.find((d) => d.id === difficulty)!;

  return {
    personaId,
    personaLabel: persona.label,
    personaPrompt: persona.prompt,
    difficulty,
    difficultyLabel: difficultyConfig.label,
    difficultyPrompt: difficultyConfig.prompt,
  };
}
