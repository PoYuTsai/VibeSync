// supabase/functions/analyze-chat/screenshot_ocr_rules.ts
// 截圖 OCR side 判別規則，兩個變體：
// - SCREENSHOT_OCR_ACCURACY_RULES：baseline，full-analysis 圖片路徑沿用（行為不變）。
// - SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS：recognize-only 路徑專用，
//   啟用 LINE meta 錨點（已讀/時間戳/邊欄頭像）判 side。
// 黑箱 A/B/C 驗證（2026-07，18 張困難樣本、claude-sonnet-4-6）：
// baseline pattern 55.6% → meta 錨點 C 臂 88.9%（修 6 張零倒退，McNemar p≈0.03），
// 單側逐泡 76.8%→84.3%，only_right 全數救回（已讀標記=決定性）。
// 歷史失敗方案（幾何/顏色/預處理）都沒碰過這三個 meta 訊號；
// 錨點是介面規則（已讀只出現在我方訊息旁）非統計先驗，theme/顏色無關。

import { normalizeBlockType } from "./blocktype_fold.ts";

const LAYOUT_FIRST_STEP_LINES = [
  "### MANDATORY FIRST STEP: Visual Layout Analysis",
  "- STOP. Before reading ANY text, you MUST first analyze the visual layout:",
  "- Step 1: Draw an imaginary vertical line through the CENTER of the screenshot (at x=50%).",
  "- Step 2: Look at ONLY the OUTER bubble containers (ignore any small inset quoted-reply cards inside bubbles).",
  "- Step 3: For each outer bubble, determine if its CENTER is LEFT of the midline (x < 40%) or RIGHT of the midline (x > 60%).",
  "- Step 4: If ALL outer bubbles are on the LEFT side → set screenSpeakerPattern: 'only_left' and ALL messages are isFromMe: false.",
  "- Step 5: If ALL outer bubbles are on the RIGHT side → set screenSpeakerPattern: 'only_right' and ALL messages are isFromMe: true.",
  "- Step 6: Only if outer bubbles appear on BOTH sides → set screenSpeakerPattern: 'mixed'.",
];

// meta 錨點段：插在 MANDATORY FIRST STEP 之後（同黑箱驗證版位）。
// 含 C 臂三個堵漏：引用卡內頭像不算邊欄頭像、metaSide/isFromMe 一致性強制、
// 同側連發共用錨點。
const META_ANCHOR_SECTION_LINES = [
  "",
  "### MANDATORY META ANCHORS (strongest side evidence — trust these over your own position estimate)",
  '- LINE renders tiny dim meta text (timestamps like "10:05 AM" / "凌晨1:03", and read receipts "已讀" / "Read" / "既読") in the margin BESIDE each outer bubble, near the bubble\'s bottom corner.',
  "- This meta text always sits on the side of the bubble that faces the screen CENTER:",
  "  - Meta text at the bubble's LEFT edge → the bubble is right-aligned → isFromMe: true.",
  "  - Meta text at the bubble's RIGHT edge → the bubble is left-aligned → isFromMe: false.",
  '- Read receipts ("已讀" / "Read" / "既読") appear ONLY beside messages that I sent. Any bubble with a read receipt beside it MUST be isFromMe: true — regardless of bubble color, theme, or your position estimate.',
  "- A small circular profile photo (avatar) in the margin directly beside an outer bubble (NOT inside a quoted card) appears ONLY for the other person's messages. A bubble with such a margin avatar, or continuing the same-side run under one, MUST be isFromMe: false. My own sent messages never show my avatar in the margin.",
  "- These anchors are theme-independent and color-independent. They work even when every bubble has the same color, when my own bubbles render gray instead of green, and when the whole screen is one-sided.",
  "- If your midline position estimate conflicts with these anchors, THE ANCHORS WIN. Re-examine the layout and correct the side.",
  '- For every message row, also report three evidence fields: "metaSide": "left" | "right" | "none" (which side of that bubble its timestamp/read-receipt sits on), "readReceipt": true | false, "avatarBeside": true | false.',
  "- CRITICAL avatar scope: a margin avatar is a small circular photo OUTSIDE the bubble, hugging the far LEFT edge of the screen (x < 10%). An avatar rendered INSIDE a bubble, inside a quoted-reply card, or inside an embedded screenshot is NOT a margin avatar — set avatarBeside: false for those rows.",
  "- CONSISTENCY CHECK before returning JSON: metaSide and isFromMe must agree on every row — metaSide 'left' requires isFromMe true; metaSide 'right' requires isFromMe false. If any drafted row violates this, the metaSide observation wins: fix isFromMe (and side/outerColumn) to match it.",
  "- Same-side runs share anchors: if a row has no meta text of its own, inherit the side of the nearest row above/below it whose anchors are clear, unless the layout clearly switches columns.",
];

const BASELINE_IGNORE_LINE =
  '- Ignore LINE announcement banners, pinned-message jump banners, date separators, read receipts, timestamps, "回到最新訊息" style system hints, and other non-message UI. Do not turn them into chat messages.';

const META_IGNORE_LINE =
  '- Ignore LINE announcement banners, pinned-message jump banners, date separators, "回到最新訊息" style system hints, and other non-message UI as chat content. Read receipts and timestamps are NOT messages either — never output them as message rows — but you MUST use them as side anchors (see MANDATORY META ANCHORS above).';

const BASELINE_OUTER_COLUMN_LINE =
  "- The outer bubble column is the source of truth across chat apps. Ignore quoted preview cards, inner screenshots, photo/video thumbnails, and avatar/no-avatar differences when deciding left vs right.";

const META_OUTER_COLUMN_LINE =
  "- The outer bubble column is the source of truth across chat apps. Ignore quoted preview cards, inner screenshots, and photo/video thumbnails when deciding left vs right — but margin meta text (timestamps/read receipts) and margin avatars beside the outer bubble ARE valid side anchors.";

function buildScreenshotOcrAccuracyRules(
  options: { metaAnchors: boolean },
): string {
  const { metaAnchors } = options;
  return [
    ...LAYOUT_FIRST_STEP_LINES,
    ...(metaAnchors ? META_ANCHOR_SECTION_LINES : []),
    "",
    "### CRITICAL: What Counts as an 'Outer Bubble'",
    "- An outer bubble is the main message container that sits against the left or right edge of the chat area.",
    "- Quoted-reply cards (small inset boxes with colored borders showing old messages) are INSIDE outer bubbles - they are NOT outer bubbles themselves.",
    "- Even if a quoted card shows someone's avatar/name, the OUTER bubble position determines the speaker.",
    "- A left-side outer bubble with a quoted card showing 'Bruce' inside it is STILL a left-side message (isFromMe: false).",
    "",
    "### OCR Accuracy Rules",
    "- Preserve Traditional Chinese exactly; do not guess unreadable characters.",
    "- Read screenshots from top to bottom and keep message order stable across multiple images.",
    "",
    "### CRITICAL: Header Name vs Message Sender",
    "- The contact name in the chat header (e.g., 'Bruce Chiang' at the top) is WHO YOU ARE CHATTING WITH, not who is sending messages.",
    "- In one-on-one chat: left-side bubbles = messages FROM the contact (the header name person); right-side bubbles = messages FROM me.",
    "- Do NOT confuse 'chatting with Bruce' with 'Bruce is sending these messages'. If the header says 'Bruce Chiang', then LEFT bubbles are Bruce's messages to me, and RIGHT bubbles are my messages to Bruce.",
    "",
    "### CRITICAL: Quoted Reply Cards in LINE",
    "- LINE quoted-reply cards (colored/bordered inset boxes with avatar + name + quoted text) show OLD messages being quoted, NOT new messages.",
    "- If a quoted card shows the header contact's avatar/name (e.g., 'Bruce Chiang'), it means the OUTER bubble is quoting Bruce's OLD message. The OUTER bubble itself is still from whoever owns that bubble position (left or right).",
    "- NEVER let the avatar or name INSIDE a quoted card determine the speaker of the OUTER bubble. The outer bubble position (left/right) is the ONLY way to determine the current speaker.",
    "",
    "### SPECIFIC EXAMPLE: Single-Sided Screenshot with Quoted Replies",
    "- Scenario: Header shows 'Bruce Chiang'. All visible outer bubbles are on the LEFT side. Some bubbles contain red-bordered quoted cards showing 'Bruce Chiang' avatar.",
    "- CORRECT interpretation: This is screenSpeakerPattern: 'only_left'. ALL messages are from the contact (isFromMe: false). The quoted cards show Bruce's OLD messages being replied to.",
    "- WRONG interpretation: Thinking messages without Bruce's avatar are 'from me' (right side). This is WRONG because the outer bubble position is LEFT for all of them.",
    "- The presence or absence of an avatar in a quoted card does NOT change the outer bubble's side.",
    "",
    "### Screen Pattern Detection",
    "- Before deciding each row, first judge the whole screenshot's visible outer-bubble pattern as `mixed`, `only_left`, or `only_right`, ignoring quoted-reply inset cards.",
    "- If every visible outer bubble on the screen belongs to the left gutter and only the smaller quoted cards mention the other person, return `screenSpeakerPattern: only_left`.",
    "- If every visible outer bubble on the screen belongs to the right gutter and only the smaller quoted cards mention the other person, return `screenSpeakerPattern: only_right`.",
    "- When screenSpeakerPattern is `only_left`, ALL messages should be `isFromMe: false`. When it is `only_right`, ALL messages should be `isFromMe: true`.",
    "",
    "### Quoted Reply Handling (emit every block and tag it)",
    "- Do NOT merge or omit anything. Emit EVERY visual block as its own message row, and tag each row with `blockType`, either `message` or `quoted_preview`.",
    '- A LINE/Messenger quoted-reply card (the smaller embedded card with avatar/name/light-gray text) is its own block: output it as a separate row with `blockType: "quoted_preview"` and put its readable text in `content`.',
    '- The larger main reply text below or beside that card is a separate row with `blockType: "message"`.',
    "- Output the `quoted_preview` row immediately before its owner `message` row, on the SAME outer bubble side as that owner.",
    '- Tag every normal live message row as `blockType: "message"`. When unsure which type, use `message`.',
    "- Do not decide whether a card is readable, important, or worth keeping — just transcribe and tag it. A deterministic post-step folds quoted_preview rows into their owner message.",
    "- This applies on both left-side and right-side bubbles. A quoted card sits on the same outer side as the reply that owns it; the current speaker is still decided by the outer bubble side.",
    "- Never use the quoted card avatar, name, or quoted-text author to override the speaker of the outer reply bubble.",
    metaAnchors ? META_IGNORE_LINE : BASELINE_IGNORE_LINE,
    "- If the screenshot was opened from a pinned announcement and starts in older history, only extract the visible real chat bubbles. Do not invent or summarize missing messages above the visible area.",
    "- Use a layout-first process: first identify each visible message bubble's horizontal side from the outer bubble/container position, then transcribe its content.",
    "- For every message, first decide the outer bubble column as `outerColumn: left | right | center` before deciding speaker.",
    "- Also estimate `horizontalPosition` as a rough 0-100 value for the outer bubble center, where 0 is far left, 50 is screen center, and 100 is far right.",
    "- If a bubble contains an embedded photo, screenshot, video preview, or sticker, determine `side` from the outer bubble frame on the main chat layout, never from the inner image content.",
    "- Determine `isFromMe` from bubble alignment first, not from wording, tone, or whose message would 'make sense' semantically.",
    "- In a normal one-to-one chat UI, left-side bubbles are usually the other person (`isFromMe: false`) and right-side bubbles are usually me (`isFromMe: true`).",
    "- If a bubble contains a quoted-reply preview card, keep the outer message on its own side, and emit the card as its own `blockType: \"quoted_preview\"` row on that same side (do not flip the owner's side to match the card's quoted author).",
    "- Even for very short replies, stickers, image placeholders, or one-word bubbles like '超爽', follow the bubble side rather than guessing from meaning.",
    "- A photo, sticker, or image placeholder inside a clearly right-side bubble is still `isFromMe: true`; inside a clearly left-side bubble it is `isFromMe: false`.",
    "- If an image bubble and the next text bubble appear on the same side, keep them on the same speaker unless the layout clearly switches sides.",
    "- If a media/image bubble is visually sandwiched between two bubbles on the same side, keep the media bubble on that same side too.",
    "- Consecutive bubbles on the same side are common. Do not force alternating speakers if the layout still shows the same side.",
    "- Build a left/right side sequence for all visible outer bubbles in top-to-bottom order before deciding speakers. Preserve same-side runs exactly as they appear on screen.",
    "- Speaker changes should happen only when the visible outer bubble column actually switches sides. A pattern like left, left, left, right, right, left is normal and should stay that way.",
    "- Imagine a vertical midline through the screenshot first. Judge each outer bubble by whether the bubble body sits mostly left or mostly right of that midline before you read the text.",
    metaAnchors ? META_OUTER_COLUMN_LINE : BASELINE_OUTER_COLUMN_LINE,
    "- If the whole visible screen is one-sided, keep the whole run on that side even if quoted preview cards mention the other person's name or the app theme makes some bubbles look visually different.",
    "- In many chat apps, only the first bubble in a same-side run shows the avatar. Do not flip the last bubble in a left-side run to `isFromMe: true` just because the avatar disappears.",
    "- If multiple screenshots appear to come from different contacts or different chat threads, do not merge them as one clean thread. Lower confidence, set `importPolicy: confirm`, and explain that the screenshots may belong to different conversations.",
    "- Before returning JSON, double-check that no clearly right-aligned bubble is labeled `isFromMe: false` and no clearly left-aligned bubble is labeled `isFromMe: true`.",
    "- If a bubble side is genuinely ambiguous, keep the message but lower confidence and use `importPolicy: confirm` instead of making a confident guess.",
    "- Distinguish between a standalone phone call log screen and a one-to-one chat thread that contains missed-call or call-record entries.",
    "- If missed calls, outgoing calls, or answered-call records appear inside a normal chat thread with the contact header, treat them as valid conversation events instead of rejecting the screenshot outright.",
    "- Convert in-thread call records into messages while preserving direction: the other person's missed/incoming call is usually `isFromMe: false`, while my outgoing call is usually `isFromMe: true`.",
    "- If the screenshot looks like a social feed, comment thread, profile page, group chat, album, call-log page, sensitive media, or other non-chat UI, classify it with the most specific label: `social_feed`, `group_chat`, `gallery_album`, `call_log_screen`, `system_ui`, `sensitive_content`, or `unsupported`.",
    "- If text is blurry, cropped, or incomplete, lower confidence and use `importPolicy: confirm` instead of guessing.",
    "- If the contact name is unclear, return `contactName: null`.",
  ].join("\n");
}

export const SCREENSHOT_OCR_ACCURACY_RULES = buildScreenshotOcrAccuracyRules({
  metaAnchors: false,
});

export const SCREENSHOT_OCR_ACCURACY_RULES_WITH_META_ANCHORS =
  buildScreenshotOcrAccuracyRules({ metaAnchors: true });

// 接在 RECOGNIZED_CONVERSATION_SCHEMA 之後（僅 recognize-only prompt）。
export const META_ANCHOR_SCHEMA_NOTE =
  'Note: In addition to the fields shown above, EVERY message row MUST also include "metaSide" ("left" | "right" | "none"), "readReceipt" (true/false), and "avatarBeside" (true/false) as described in MANDATORY META ANCHORS.';

// readReceipt=true 是 LINE 介面規則級的我方訊號（已讀只會出現在我發的訊息旁）。
// 黑箱 C 臂 29 個 readReceipt=true 回報中，only_left 圖上捏造 0、only_right 全對、
// mixed 零不自洽（metaSide 會被硬骨頭樣本捏造，readReceipt 沒有）。
// 後處理以此鎖死 isFromMe=true（metaDecisive），與 geometryDecisive 同款 invariant。
export function isReadReceiptSideDecisive(
  record: Record<string, unknown>,
): boolean {
  // quoted_preview row 的已讀標記屬於 owner 訊息的介面元素；若拿來翻卡，
  // 左側 owner 的引用卡會被鎖成 right，fold 時因不同側被當孤兒丟棄。
  if (normalizeBlockType(record) === "quoted_preview") {
    return false;
  }
  return record.readReceipt === true;
}
