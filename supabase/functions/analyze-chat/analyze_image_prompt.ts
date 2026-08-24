// AnalyzeChat screenshot analysis prompt and vision content assembler.
// This module is separate from the dating-coach reasoning prompt.

import { SCREENSHOT_OCR_ACCURACY_RULES } from "./screenshot_ocr_rules.ts";
import {
  joinPromptSections,
  RECOGNIZED_CONVERSATION_SCHEMA,
} from "./ocr_recognition_prompt.ts";
import type { ImageData } from "./analysis_input_compiler.ts";

function buildVisionContent(
  textContent: string,
  images: ImageData[],
): Array<
  {
    type: string;
    text?: string;
    source?: { type: string; media_type: string; data: string };
  }
> {
  const content: Array<
    {
      type: string;
      text?: string;
      source?: { type: string; media_type: string; data: string };
    }
  > = [];

  // 先加入圖片（按 order 排序）
  const sortedImages = [...images].sort((a, b) => a.order - b.order);
  for (const img of sortedImages) {
    content.push({
      type: "image",
      source: {
        type: "base64",
        media_type: img.mediaType,
        data: img.data,
      },
    });
  }

  // 最後加入文字內容
  content.push({
    type: "text",
    text: textContent,
  });

  return content;
}

function buildImageAnalysisPrompt(options: {
  imageCount: number;
  contextInfo: string;
  partnerContextInfo: string;
  styleContextInfo: string;
  historicalContextInfo: string;
  compiledConversationText: string;
  knownContactName?: string;
}): string {
  const {
    imageCount,
    contextInfo,
    partnerContextInfo,
    styleContextInfo,
    historicalContextInfo,
    compiledConversationText,
    knownContactName,
  } = options;

  return joinPromptSections(
    `You received ${imageCount} chat screenshot(s). First extract the visible conversation, then analyze it and return the normal structured JSON response.`,
    SCREENSHOT_OCR_ACCURACY_RULES,
    '### Quote Preview Rules\n- In LINE-style quoted replies, emit the smaller inset quote card as its OWN row with `blockType: "quoted_preview"`; do not merge or omit it. Put the card\'s readable text in `content`.\n- Do this even when the inset card only shows the old message body and the quoted author\'s name is missing or too small to read.\n- In dark mode the quoted card often renders as a single dimmer gray line sitting DIRECTLY under the sender name+avatar header and ABOVE the brighter main message, with no separate card border and no avatar of its own. That dim under-name line is still a quoted_preview: tag it `blockType: "quoted_preview"` and tag the brighter line below it as its owner `blockType: "message"`. Never output the dim under-name line as a normal message.\n- Emit the larger outer bubble (the live reply) as a separate `blockType: "message"` row on the same side, right after its quoted_preview row. A deterministic post-step folds the card into it.\n- Tag every normal live message row as `blockType: "message"`; do not decide whether a card is worth keeping, just transcribe and tag.\n- Preserve visible names and nicknames exactly as shown in the screenshot header or quote card. Do not guess or normalize similar-looking Han characters.\n- IMPORTANT: If the quoted card shows the same name as the chat header (e.g., header=\'Bruce\' and quoted card shows \'Bruce\'), it means the contact is quoting old messages. The quoted card name does NOT change who is sending the OUTER bubble.\n- When all outer bubbles are visually on the LEFT side and only quoted cards reference the header contact, set `screenSpeakerPattern: only_left` and ALL messages must have `isFromMe: false`.',
    '### Additional Rules\n- Always include `recognizedConversation` in the response.\n- Base the final analysis on the screenshot content plus any existing thread context.\n- If the screenshot is likely unsupported, set `recognizedConversation.importPolicy` to `reject` and explain why in `warning`.\n- Prefer the most specific `classification` from: `valid_chat`, `low_confidence`, `social_feed`, `group_chat`, `gallery_album`, `call_log_screen`, `system_ui`, `sensitive_content`, `unsupported`.\n- Do not reject a screenshot only because the visible thread is dominated by call records, as long as it is still clearly a one-to-one chat conversation view.\n- Build `recognizedConversation.messages` with a layout-first pass: identify bubble side from the screen position first, then transcribe content.\n- When `recognizedConversation.messages` is built, verify speaker direction from bubble side before finalizing the JSON. Do not let semantic inference override a clearly left- or right-aligned bubble.\n- If a LINE-style bubble contains a quoted-reply preview card plus a larger main reply, emit BOTH as separate rows: the card as `blockType: "quoted_preview"` and the larger main reply as `blockType: "message"`, both on the same outer side, card first. Do not merge or omit the card. A deterministic post-step folds the card into the reply.\n- The quoted card never flips the outer reply bubble\'s speaker.\n- Be extra careful with media rows: image bubbles and the text bubble immediately after them often belong to the same side and should not be split across two speakers unless the layout clearly changes.\n- If a bubble contains a screenshot/photo/video preview, use the outer bubble container to decide side; ignore the inner image contents for speaker assignment.\n- If the screenshots seem to mix two different contacts or unrelated thread segments, do not silently merge them into a clean conversation. Mark it low-confidence and explain the mismatch in `warning`.',
    "### recognizedConversation Schema",
    RECOGNIZED_CONVERSATION_SCHEMA,
    contextInfo,
    knownContactName
      ? `## Known Contact Name\n- Existing thread contact name: ${knownContactName}\n- Use this only as a tie-breaker when the visible header or nickname is almost the same and OCR is uncertain by one similar-looking character.`
      : "",
    partnerContextInfo,
    styleContextInfo,
    historicalContextInfo,
    compiledConversationText
      ? `## Existing Thread Context\n${compiledConversationText}`
      : "",
    "### Multi-Message Reply Reminder\n- 截圖中如果對方連發多條訊息，先判斷哪些球值得接。中文問句不一定都是必答題；先分辨真問題、情緒球、框架測試或玩笑反問，再決定答、半答、重框、略過或反丟。finalRecommendation.content 是最推薦的訊息組文字，可用換行表示 2-5 則真人訊息，但不要放 ①② 標註或「回某句」報告格式；對方連發 2 顆以上值得接的球時，必須填 finalRecommendation.replySegments 一球一段（最多 5 段，每段必填 sourceIndex 與 sourceMessage），讓 App 顯示引用原句與分段複製。replyOptions 則要提供五種風格各自的「接法 + 訊息組」。finalRecommendation.reason 再簡短說明接了哪些球、略過哪些低價值資訊。",
  );
}

export { buildImageAnalysisPrompt, buildVisionContent };
