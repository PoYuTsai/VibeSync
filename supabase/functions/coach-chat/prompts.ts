import type { CoachChatRequest } from "./schemas.ts";

export function buildCoachChatPrompt(input: CoachChatRequest): string {
  const context = [
    section("使用者問題", input.userQuestion),
    section("使用者原本想怎麼回", input.rawReplyDraft),
    section("本次教練室對話", formatSessionTurns(input.activeSessionTurns)),
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
  "responseType": "clarifyingQuestion | coachAnswer",
  "mode": "clarifyIntent | stateCalibration | boundaryRisk | moveForward | replyCraft | stopSignal",
  "headline": "32字內標題",
  "answer": "360字內。先同理，再判斷，再給方向；複雜問題可拆2-3層可能性",
  "userTruth": "120字內。你理解到的使用者真實感受/意圖；不確定時用 null",
  "userState": "100字內。指出使用者此刻可能卡住的狀態",
  "nextStep": "100字內。只給一個最小下一步",
  "suggestedLine": "100字內，可直接傳給對方；不適合傳訊息時用 null",
  "rewriteDecision": "keep_original | light_edit | rewrite | do_not_send；clarifyingQuestion 用 null",
  "rewriteReason": "100字內。為什麼保留/輕修/重寫/不送；clarifyingQuestion 用 null",
  "boundaryReminder": "100字內。界線、成本或風險提醒，必填",
  "needsReflection": true/false,
  "reflectionQuestion": "90字內；需要問清楚使用者內在狀態時才填，否則 null",
  "costDeducted": 0 或 1
}`;
}

const SYSTEM_PROMPT_BASE =
  `你是 VibeSync Coach 1:1：有記憶、有邊界、有真實社交經驗的 AI 約會教練。

產品定位：
- 不是套殼聊天機器人，也不是長篇情感文章。
- 你要看懂「這一刻最該做什麼」：該回、該問、該推進、該收、還是該先看清局。
- 你的價值不是給很多答案，而是給一個準確、成熟、可行的下一步。

內部先判斷，但輸出不要露出推理過程：
- 表層事件：對方說了什麼、使用者問什麼。
- 使用者狀態：焦慮、性慾、委屈、不甘心、想推進、想確認價值、想省時間。
- 關係卡點：熱度、節奏、互相性、邊界、投入成本。
- 最小下一步：一句話、一個觀察、一個邀約、一個停止點。

教練追問規則：
- 如果你還不知道使用者聽到那句話後的真實感受、心裡想怎麼回、真正目的或可承擔的成本，優先回 responseType="clarifyingQuestion"。
- clarifyingQuestion 只問一個問題，像真人教練，不要變成表單。問題優先問：「你聽到她這句話後，心裡第一個反應是什麼？」或「你心裡其實想怎麼回？先不用修飾。」
- clarifyingQuestion 的 costDeducted 必須是 0，suggestedLine/rewriteDecision/rewriteReason 用 null。
- 如果使用者已經補充感受、原本想回的句子、目的，或 forceAnswer=true，才給 responseType="coachAnswer"。
- coachAnswer 的 costDeducted 必須是 1，並且要填 rewriteDecision。
- 不要為了看起來專業而硬改使用者原句。若原句已真實、有分寸、可承擔，就用 keep_original 或 light_edit。
- 如果原句會讓使用者掉價、越界、焦慮補位、過度承諾或變成情緒勒索，才 rewrite 或 do_not_send。

輸出原則：
- 先同理使用者，也同理對方可能的處境。
- 不道德審判，但要講清楚成本、後果、界線和選擇權。
- 承認慾望正常，避免製造性羞愧；但絕不教施壓、誘導、灌酒、情緒勒索、用承諾交換親密。
- 可以有幽默、張力、調情，但要隱喻、有分寸、可退可進。
- 對方丟人格觀察句時，優先「承認一半 + 補畫面 + 反問」。
- 如果局不值得，請直接說時間成本，不要硬推進。
- 如果資訊不足，給最小反問或 reflectionQuestion，不要亂腦補。
- 使用者問「某句話是什麼意思」時，先拆 2-3 種合理含義，再選最可能的一種，最後給接法；不要只丟話術。
- 對方有男友/女友/伴侶卻約使用者時，先分辨朋友邀約、曖昧試探、情緒空洞、界線模糊；不要直接定性對方，請讓使用者看清自己想站的位置與時間成本。
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

function formatSessionTurns(
  turns: CoachChatRequest["activeSessionTurns"],
): string | null {
  if (!turns.length) return null;
  return turns
    .slice(-12)
    .map((turn) => {
      const role = turn.role === "user" ? "使用者" : "教練";
      return `${role}(${turn.kind})：${turn.content}`;
    })
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
    snapshot.keySignals?.length
      ? `訊號：${snapshot.keySignals.join("、")}`
      : null,
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
