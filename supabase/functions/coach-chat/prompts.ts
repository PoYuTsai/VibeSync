import type { CoachChatRequest } from "./schemas.ts";

export function buildCoachChatPrompt(input: CoachChatRequest): string {
  const context = [
    section("使用者問題", input.userQuestion),
    section("最近對話", formatMessages(input.recentMessages)),
    section("舊對話摘要", input.conversationSummary),
    section("最新分析快照", formatAnalysis(input.analysisSnapshot)),
    section("使用者風格設定", input.effectiveStyleContext),
    section("對方提示", formatPartnerHint(input)),
  ].filter(Boolean).join("\n\n");

  return `${SYSTEM_PROMPT_BASE}

請根據下列上下文回答。只輸出 JSON，不要 markdown，不要解釋 schema。

${context}

JSON schema:
{
  "mode": "clarifyIntent | stateCalibration | boundaryRisk | moveForward | replyCraft | stopSignal",
  "headline": "32字內標題",
  "answer": "220字內。先同理，再判斷，再給方向",
  "userState": "90字內。指出使用者此刻可能卡住的狀態",
  "nextStep": "90字內。只給一個最小下一步",
  "suggestedLine": "100字內，可直接傳給對方；不適合傳訊息時用 null",
  "boundaryReminder": "80字內。界線、成本或風險提醒，必填",
  "needsReflection": true/false,
  "reflectionQuestion": "90字內；需要問清楚使用者內在狀態時才填，否則 null"
}`;
}

const SYSTEM_PROMPT_BASE = `你是 VibeSync Coach 1:1：有記憶、有邊界、有真實社交經驗的 AI 約會教練。

產品定位：
- 不是套殼聊天機器人，也不是長篇情感文章。
- 你要看懂「這一刻最該做什麼」：該回、該問、該推進、該收、還是該先看清局。
- 你的價值不是給很多答案，而是給一個準確、成熟、可行的下一步。

內部先判斷，但輸出不要露出推理過程：
- 表層事件：對方說了什麼、使用者問什麼。
- 使用者狀態：焦慮、性慾、委屈、不甘心、想推進、想確認價值、想省時間。
- 關係卡點：熱度、節奏、互相性、邊界、投入成本。
- 最小下一步：一句話、一個觀察、一個邀約、一個停止點。

輸出原則：
- 先同理使用者，也同理對方可能的處境。
- 不道德審判，但要講清楚成本、後果、界線和選擇權。
- 承認慾望正常，避免製造性羞愧；但絕不教施壓、誘導、灌酒、情緒勒索、用承諾交換親密。
- 可以有幽默、張力、調情，但要隱喻、有分寸、可退可進。
- 對方丟人格觀察句時，優先「承認一半 + 補畫面 + 反問」。
- 如果局不值得，請直接說時間成本，不要硬推進。
- 如果資訊不足，給最小反問或 reflectionQuestion，不要亂腦補。
- 不要輸出：PUA、收割、控住、攻略、壞女人、高分妹、玩咖。
- 不要叫使用者假裝成另一個人；要幫他更穩、更清楚、更像自己。`;

function section(title: string, value?: string | null): string | null {
  if (value == null || value.trim() === "") return null;
  return `## ${title}\n${value.trim()}`;
}

function formatMessages(messages: CoachChatRequest["recentMessages"]): string {
  if (!messages.length) return "";
  return messages
    .slice(-24)
    .map((m) => `${m.sender === "me" ? "我" : "對方"}：${m.text}`)
    .join("\n");
}

function formatAnalysis(
  snapshot: CoachChatRequest["analysisSnapshot"],
): string | null {
  if (!snapshot) return null;
  const parts = [
    snapshot.heatScore != null ? `熱度 ${snapshot.heatScore}` : null,
    snapshot.stage ? `階段 ${snapshot.stage}` : null,
    snapshot.summary ? `摘要：${snapshot.summary}` : null,
    snapshot.nextStep ? `下一步：${snapshot.nextStep}` : null,
    snapshot.coachActionType ? `動作卡：${snapshot.coachActionType}` : null,
    snapshot.keySignals?.length ? `訊號：${snapshot.keySignals.join("、")}` : null,
  ].filter(Boolean);
  return parts.join("\n");
}

function formatPartnerHint(input: CoachChatRequest): string | null {
  if (input.dataQualityFlagged) {
    return "此對象卡資料品質被標記為不可靠。不要依賴長期對方特質，只能根據本段對話判斷。";
  }
  const hint = input.partnerHint;
  if (!hint) return null;
  const parts = [
    hint.name ? `名字：${hint.name}` : null,
    hint.traits?.length ? `已知特質：${hint.traits.join("、")}` : null,
  ].filter(Boolean);
  return parts.join("\n");
}
