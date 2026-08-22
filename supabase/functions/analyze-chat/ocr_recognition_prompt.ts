// Recognize（OCR）mode-local prompt：辨識-only system prompt、
// recognizedConversation schema（文字版＋structured output 版）、
// Phase 1 量測插樁 addendum 與 prompt 組合工具。
// Prompt bytes 由 baseline_contract_test.ts 以 fc8bbe84 hash 鎖定。

import {
  META_ANCHOR_SCHEMA_NOTE,
  SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS,
} from "./screenshot_ocr_rules.ts";

const OCR_RECOGNIZE_ONLY_SYSTEM_PROMPT =
  `You are an OCR + chat-structure extraction assistant.
Return valid JSON only.
The "warning" and "summary" fields are shown directly to a Traditional Chinese end user: write them in 繁體中文 as one short plain sentence; never output English diagnostics there.
Only extract what is visible in the screenshots.
Do not invent missing text, names, or message order.
If the screenshots are not a normal one-to-one chat UI, classify them conservatively using one of: social_feed, group_chat, gallery_album, call_log_screen, system_ui, sensitive_content, unsupported.`;

const RECOGNIZED_CONVERSATION_SCHEMA = `{
  "recognizedConversation": {
    "contactName": "Alex",
    "screenSpeakerPattern": "mixed",
    "classification": "valid_chat",
    "importPolicy": "allow",
    "confidence": "high",
    "sideConfidence": "high",
    "uncertainSideCount": 0,
    "warning": null,
    "messageCount": 4,
    "summary": "A short summary of the visible exchange.",
    "messages": [
      { "outerColumn": "left", "horizontalPosition": 22, "side": "left", "isFromMe": false, "blockType": "quoted_preview", "content": "Old quoted message the next reply is replying to" },
      { "outerColumn": "left", "horizontalPosition": 22, "side": "left", "isFromMe": false, "blockType": "message", "content": "Visible main reply from the other person" },
      { "outerColumn": "right", "horizontalPosition": 78, "side": "right", "isFromMe": true, "blockType": "message", "content": "Visible message from me" }
    ]
  }
}

Example for single-sided screenshot (all left bubbles, header shows contact name like 'Bruce Chiang'):
{
  "recognizedConversation": {
    "contactName": null,
    "screenSpeakerPattern": "only_left",
    "classification": "valid_chat",
    "importPolicy": "allow",
    "confidence": "high",
    "sideConfidence": "high",
    "uncertainSideCount": 0,
    "warning": null,
    "messageCount": 5,
    "summary": "All visible messages are from the contact on the left side.",
    "messages": [
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "blockType": "message", "content": "到家一下了～～" },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "blockType": "message", "content": "正要來吃晚餐！" },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "blockType": "quoted_preview", "content": "辛苦北鼻了" },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "blockType": "message", "content": "抱抱" },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "blockType": "quoted_preview", "content": "老師也有小獎品哦" },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "blockType": "message", "content": "好喜歡～～～" },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "blockType": "message", "content": "等等吃飽打給北鼻" }
    ]
  }
}
Note: In the single-sided example, even though quoted cards show the header contact's name/avatar (e.g., 'Bruce Chiang'), ALL outer bubbles are on the LEFT, so ALL rows have isFromMe: false. Each quoted card is emitted as its own blockType: "quoted_preview" row on the same LEFT side, placed right before the owner message it belongs to; a deterministic post-step folds it into that owner.

Example for a dark-mode LINE reply where the quoted text is a single dim gray line sitting directly under the sender name+avatar header (no separate card outline and no avatar of its own), above the brighter main message (this is the same pattern as the single-sided example, just rendered as an under-name line instead of a bordered card):
{
  "recognizedConversation": {
    "contactName": null,
    "screenSpeakerPattern": "only_left",
    "classification": "valid_chat",
    "importPolicy": "allow",
    "confidence": "high",
    "sideConfidence": "high",
    "uncertainSideCount": 0,
    "warning": null,
    "messageCount": 2,
    "summary": "All visible messages are from the contact on the left; the two replies quote older messages.",
    "messages": [
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "blockType": "quoted_preview", "content": "明天記得帶傘" },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "blockType": "message", "content": "好喔我知道了" },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "blockType": "quoted_preview", "content": "晚點再打給你" },
      { "outerColumn": "left", "horizontalPosition": 20, "side": "left", "isFromMe": false, "blockType": "message", "content": "沒問題～" }
    ]
  }
}
Note: In this dark-mode example the dim gray line under the name header (e.g. "明天記得帶傘") is NOT a live message — it is the older message the reply is quoting, so it is tagged blockType: "quoted_preview" and a deterministic post-step folds it into the brighter owner message below it. Never emit that dim under-name line as its own blockType: "message".`;

// Sonnet 5 structured output contract for screenshot recognition. Every field
// is required by the provider schema; nullable values represent OCR unknowns.
const OCR_RECOGNITION_OUTPUT_SCHEMA: Record<string, unknown> = {
  type: "object",
  additionalProperties: false,
  required: ["recognizedConversation"],
  properties: {
    recognizedConversation: {
      type: "object",
      additionalProperties: false,
      required: [
        "contactName",
        "screenSpeakerPattern",
        "classification",
        "importPolicy",
        "confidence",
        "sideConfidence",
        "uncertainSideCount",
        "warning",
        "messageCount",
        "summary",
        "messages",
      ],
      properties: {
        contactName: { type: ["string", "null"] },
        screenSpeakerPattern: {
          type: "string",
          enum: ["mixed", "only_left", "only_right"],
        },
        classification: {
          type: "string",
          enum: [
            "valid_chat",
            "low_confidence",
            "social_feed",
            "group_chat",
            "gallery_album",
            "call_log_screen",
            "system_ui",
            "sensitive_content",
            "unsupported",
          ],
        },
        importPolicy: {
          type: "string",
          enum: ["allow", "confirm", "reject"],
        },
        confidence: {
          type: "string",
          enum: ["high", "medium", "low"],
        },
        sideConfidence: {
          type: "string",
          enum: ["high", "medium", "low"],
        },
        uncertainSideCount: {
          type: "integer",
          description: "Zero or a positive count.",
        },
        warning: {
          type: ["string", "null"],
          description:
            "Shown directly to the end user: one short plain sentence in 繁體中文 (never English); null when nothing needs attention.",
        },
        messageCount: {
          type: "integer",
          description: "Zero or a positive count.",
        },
        summary: {
          type: "string",
          description:
            "May be shown directly to the end user: one short plain sentence in 繁體中文 (never English).",
        },
        messages: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            required: [
              "outerColumn",
              "horizontalPosition",
              "side",
              "isFromMe",
              "blockType",
              "content",
              "metaSide",
              "readReceipt",
              "avatarBeside",
            ],
            properties: {
              outerColumn: {
                type: "string",
                enum: ["left", "right", "center"],
              },
              horizontalPosition: {
                type: "number",
                description: "Approximate outer bubble center from 0 to 100.",
              },
              side: {
                type: "string",
                enum: ["left", "right", "unknown"],
              },
              isFromMe: { type: "boolean" },
              blockType: {
                type: "string",
                enum: ["message", "quoted_preview"],
              },
              content: { type: "string" },
              metaSide: {
                type: "string",
                enum: ["left", "right", "none"],
              },
              readReceipt: { type: "boolean" },
              avatarBeside: { type: "boolean" },
            },
          },
        },
      },
    },
  },
};

function joinPromptSections(
  ...sections: Array<string | undefined | null>
): string {
  return sections
    .map((section) => section?.trim())
    .filter((section): section is string => !!section)
    .join("\n\n");
}

function buildRecognizeOnlyImagePrompt(options: {
  imageCount: number;
  contextInfo: string;
  historicalContextInfo: string;
  compiledConversationText: string;
  knownContactName?: string;
}): string {
  const {
    imageCount,
    contextInfo,
    historicalContextInfo,
    compiledConversationText,
    knownContactName,
  } = options;

  return joinPromptSections(
    `You received ${imageCount} chat screenshot(s). Extract the visible conversation only and return the JSON schema below.`,
    SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS,
    '### Quote Preview Rules\n- In LINE-style quoted replies, emit the smaller inset quote card as its OWN row with `blockType: "quoted_preview"`; do not merge or omit it. Put the card\'s readable text in `content`.\n- Do this even when the inset card only shows the old message body and the quoted author\'s name is missing or too small to read.\n- In dark mode the quoted card often renders as a single dimmer gray line sitting DIRECTLY under the sender name+avatar header and ABOVE the brighter main message, with no separate card border and no avatar of its own. That dim under-name line is still a quoted_preview: tag it `blockType: "quoted_preview"` and tag the brighter line below it as its owner `blockType: "message"`. Never output the dim under-name line as a normal message.\n- Emit the larger outer bubble (the live reply) as a separate `blockType: "message"` row on the same side, right after its quoted_preview row. A deterministic post-step folds the card into it.\n- Tag every normal live message row as `blockType: "message"`; do not decide whether a card is worth keeping, just transcribe and tag.\n- Preserve visible names and nicknames exactly as shown in the screenshot header or quote card. Do not guess or normalize similar-looking Han characters.\n- IMPORTANT: If the quoted card shows the same name as the chat header (e.g., header=\'Bruce\' and quoted card shows \'Bruce\'), it means the contact is quoting old messages. The quoted card name does NOT change who is sending the OUTER bubble.\n- When all outer bubbles are visually on the LEFT side and only quoted cards reference the header contact, set `screenSpeakerPattern: only_left` and ALL messages must have `isFromMe: false`.',
    '### Output Rules\n- Return only `recognizedConversation`.\n- Do not include extra analysis fields.\n- Use `classification`, `importPolicy`, and `confidence` conservatively.\n- Valid `classification` values are: `valid_chat`, `low_confidence`, `social_feed`, `group_chat`, `gallery_album`, `call_log_screen`, `system_ui`, `sensitive_content`, `unsupported`.\n- If the thread only contains missed-call or call-record entries but is still a normal one-to-one chat view, return those call events as messages instead of rejecting the screenshot outright.\n- Determine each bubble\'s `side` from the outer chat layout first, before reading the text inside that bubble.\n- For speaker direction, layout beats semantics: a clearly right-side bubble should stay `isFromMe: true` even if the text itself is very short or could also sound like the other person.\n- This also applies to media placeholders and image-in-image content: a right-side photo bubble must not be flipped to `她說` just because the OCR text or the inner image content is generic.\n- If multiple visible bubbles continue on the same left side, keep them as the other person even when only the first bubble shows an avatar; do not treat missing-avatar rows as an automatic side switch.\n- Emit each quoted-reply preview card as its own `blockType: "quoted_preview"` row on the same outer side as the reply it belongs to; do not merge it into the reply and do not omit it. The quoted card never overrides the outer bubble speaker.\n- Tag every live message row as `blockType: "message"`. A deterministic post-step folds quoted_preview rows into their owner message.\n- For each returned message, include `outerColumn` as `left`, `right`, or `center`, and include `horizontalPosition` as an approximate 0-100 number for the outer bubble center.\n- For each returned message, include `side` as `left`, `right`, or `unknown`. If `outerColumn` or `horizontalPosition` is clear, keep `side` and `isFromMe` consistent with that geometry.',
    "### JSON Schema",
    RECOGNIZED_CONVERSATION_SCHEMA,
    META_ANCHOR_SCHEMA_NOTE,
    contextInfo
      ? `${contextInfo}\n- Use this only as weak context for mismatch detection.`
      : "",
    knownContactName
      ? `## Known Contact Name\n- Existing thread contact name: ${knownContactName}\n- Use this only as a tie-breaker when the visible header or nickname is almost the same and OCR is uncertain by one similar-looking character.`
      : "",
    historicalContextInfo,
    compiledConversationText
      ? `## Existing Thread Context\n${compiledConversationText}\nUse this only to judge whether the screenshot likely belongs to the same thread.`
      : "",
  );
}

const PHASE1_VISION_INSTRUMENT_ADDENDUM =
  `### PHASE 1 OBSERVATION FIELDS (measurement only — do NOT change how you decide side / isFromMe)
These are extra append-only observation fields. They must NEVER change your side / isFromMe
decision, which still comes ONLY from the outer bubble position exactly as instructed above.
Report what you actually see; if unsure use null (or "unknown").

For EACH message object, additionally include:
- "bubbleFillColor": dominant fill color of THIS message's OUTER bubble, as a plain lowercase
  English color word ("green", "gray", "dark_gray", "white", "blue", "none" for transparent /
  media-only). Report the color you actually observe, independent of which side it is on.
- "senderNameRaw": the small display name shown ABOVE this bubble, copied verbatim INCLUDING any
  emoji / decoration, or null if no name label is shown above this bubble.
- "senderNameX": approximate 0-100 horizontal center of that sender-name label (0=far left,
  100=far right), or null if there is no name label.
- "quotedName": if this row is or carries a quoted-reply card, the author name shown INSIDE the
  quoted card, copied verbatim, or null. This is whoever is being QUOTED — never the speaker of
  the outer bubble.
- "quotedNamePresent": true if a quoted-reply card is visible for this row, else false.

Also add to the top-level "recognizedConversation" object:
- "myBubbleColor": fill color (same vocabulary as bubbleFillColor) of bubbles that are MINE
  (right side / isFromMe:true), or null if no right-side bubble is visible on screen.
- "myBubbleColorEvidence": exactly one of "right_anchor" (a right-side bubble is visible so my
  color is anchored directly), "app_convention" (no right-side bubble visible; inferred from app
  convention, e.g. LINE renders my bubbles green), or "unknown".

Do not omit any existing required fields. These observations are additive only.`;

// 把單次 recognizeOnly 的「原始 vision 輸出」（normalize 折疊/重排之前）抽成觀測快照。
// 只讀、不改 result。harness 對它算 fill-only 側別、名字召回率、名字位置正確率。

export {
  buildRecognizeOnlyImagePrompt,
  joinPromptSections,
  OCR_RECOGNITION_OUTPUT_SCHEMA,
  OCR_RECOGNIZE_ONLY_SYSTEM_PROMPT,
  PHASE1_VISION_INSTRUMENT_ADDENDUM,
  RECOGNIZED_CONVERSATION_SCHEMA,
};
