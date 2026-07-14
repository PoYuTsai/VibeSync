import type { ChatMessage } from "./prompt.ts";

export type PracticeGroundingSurface = "hint" | "debrief";

function errorMessage(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

export function groundingFailureCode(
  error: unknown,
  surface: PracticeGroundingSurface,
): string | null {
  const message = errorMessage(error);
  const prefix = surface === "hint"
    ? "hint_quality_invalid_unsupported_detail:"
    : "debrief_quality_invalid_unsupported_detail:";
  const start = message.indexOf(prefix);
  if (start < 0) return null;
  const code = message.slice(start).split(/\s/u, 1)[0];
  return code.length <= 160 ? code : code.slice(0, 160);
}

export function buildGroundingReviewMessages(opts: {
  baseMessages: ChatMessage[];
  previousCandidate: string;
  failureCode?: string | null;
  repairInstruction?: string | null;
  verificationPass?: boolean;
  surface: PracticeGroundingSurface;
  isGame: boolean;
}): ChatMessage[] {
  const shape = opts.surface === "hint"
    ? '{"warmUp":"...","steady":"...","coaching":"..."}'
    : "與上一版完全相同的完整 Debrief JSON schema";
  const continuity = opts.surface === "debrief"
    ? "已套用 Hint 的策略是 server 鎖定的正確決策，不得反過來批判或推翻；只校正無證據事實。"
    : "保留原本的高手策略、接球點與兩種可貼回覆差異；只校正無證據事實。";
  const gameRule = opts.surface === "hint"
    ? opts.isGame
      ? "保留 Game Hint 的高手判斷與速約任務；仍只輸出 warmUp、steady、coaching 三欄。"
      : "仍只輸出 warmUp、steady、coaching 三欄，不要新增 Game 或拆盤欄位。"
    : opts.isGame
    ? "Game 拆盤欄位都必須保留；suggestedLine 與 nextFirstLine 必須維持同一條策略。"
    : "gameBreakdown 必須維持 null，不要新增 Game 欄位。";
  const machineSignal = opts.failureCode
    ? `機器告警碼：${opts.failureCode}。`
    : "這次沒有可靠的 lexical 告警；仍必須逐欄主動找出語意上的無證據事實。";
  const hardGateSignal = opts.repairInstruction
    ? `上一版同時未通過產品契約：${opts.repairInstruction}。請在同一次輸出一併修正，再完成全部事實歸因審查。`
    : "";
  const verificationSignal = opts.verificationPass
    ? "這是獨立第二道對抗複核。假設前一位審查者漏掉了一個很自然的第一人稱幻覺，不能因為上一版已被審過就信任它；重新從逐字稿取證，尤其找『沒記住／不知道／有點餓／某種香氣』這類無證據答案。"
    : "";

  return [
    ...opts.baseMessages,
    { role: "assistant", content: opts.previousCandidate },
    {
      role: "user",
      content:
        `你現在只做「事實歸因校正」，不是重新創作，也不是文風評審。${machineSignal}${hardGateSignal}${verificationSignal}\n` +
        "請完整閱讀上方逐字稿、可信資料與上一版 JSON，按整句語意判斷，不可用單一關鍵字判斷。" +
        "輸出前先在內部逐欄盤點所有第一人稱主張，以及每一個對方問句在候選裡得到的答案；每一項都要能指向使用者親口說過的證據，不能因為語氣自然就略過。" +
        "上一版候選本身不是事實證據；對方任何問句都不是使用者答案，不限於『看什麼、住哪、做什麼、去過哪、喜歡什麼』。若使用者尚未親自回答，就絕對不能替使用者補任何答案。" +
        "『沒有證據』也不等於否定或忘記：沒記住、不知道、沒去過、不是、有點餓、想保密、看到第幾集、聞到堅果味等記憶、狀態、感官、數量、原因與意圖，同樣都要有使用者證據；也不得把對方的猜測改寫成使用者事實。" +
        "問句、假設、條件句、泛稱人物、把問題交回對方、主觀感受或未來提案，不等於宣稱既成事實。" +
        "但任何具名人物、地點、時間、偏好、經歷、關係、行程或聯絡資料，只要上方沒有直接證據，就必須刪除或改成不預設答案的自然說法。" +
        "如果缺的是對方正在追問的答案，只能沿用已知細節自然暫緩，或明確要求使用者補上真實答案；不能為了讓句子好貼而編一個答案。" +
        "如果上一版其實沒有捏造，內容保持不變；如果真有捏造，只改涉及的最小子句，不能用空泛罐頭取代，也不能新增另一個事實。" +
        continuity + gameRule +
        `只輸出唯一 JSON，不要 markdown、判決、理由或額外 key；輸出格式為 ${shape}。`,
    },
  ];
}
