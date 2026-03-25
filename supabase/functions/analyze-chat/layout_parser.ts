export type LayoutBubbleSide = "left" | "right" | "unknown";

export interface LayoutFirstMessage {
  side: LayoutBubbleSide;
  isFromMe: boolean;
  content: string;
  quotedReplyPreview?: string;
}

export interface LayoutFirstParseResult<TMessage extends LayoutFirstMessage> {
  messages: TMessage[];
  adjustedCount: number;
  systemRowsRemovedCount: number;
}

interface SideRun {
  start: number;
  end: number;
  side: LayoutBubbleSide;
  length: number;
  quotedCount: number;
  mediaCount: number;
}

function isLikelyMediaPlaceholderContent(content: string): boolean {
  const normalized = content.trim().toLowerCase();
  if (!normalized) {
    return false;
  }

  return normalized.startsWith("[photo") ||
    normalized.startsWith("[image") ||
    normalized.startsWith("[sticker") ||
    normalized.startsWith("[video") ||
    normalized.includes("photo of ") ||
    normalized.includes("image of ") ||
    normalized.includes("shared a photo") ||
    normalized.includes("sent a photo") ||
    normalized.includes("uploaded a photo");
}

function isLikelyShortContinuationContent(content: string): boolean {
  const trimmed = content.trim();
  if (!trimmed || isLikelyMediaPlaceholderContent(trimmed)) {
    return false;
  }

  return trimmed.replace(/\s+/g, "").length <= 28;
}

function isLikelySystemRowContent(content: string): boolean {
  const trimmed = content.trim();
  if (!trimmed || trimmed.length > 32) {
    return false;
  }

  const normalized = trimmed.toLowerCase();
  const compact = normalized.replace(/\s+/g, "");

  const standaloneDateOrTimePattern =
    /^(today|yesterday|monday|tuesday|wednesday|thursday|friday|saturday|sunday|\d{1,2}:\d{2}(am|pm)?|\d{4}[/-]\d{1,2}[/-]\d{1,2}|\d{1,2}[/-]\d{1,2})$/i;
  if (standaloneDateOrTimePattern.test(compact)) {
    return true;
  }

  const systemKeywords = [
    "matched",
    "you matched",
    "it's a match",
    "pinned a message",
    "unsent a message",
    "deleted a message",
    "retracted a message",
    "joined the chat",
    "left the chat",
  ];

  return systemKeywords.some((keyword) => normalized.includes(keyword));
}

function stripLikelySystemRows<TMessage extends LayoutFirstMessage>(
  messages: TMessage[],
): {
  messages: TMessage[];
  removedCount: number;
} {
  if (messages.length < 2) {
    return {
      messages,
      removedCount: 0,
    };
  }

  const filtered = messages.filter((message) =>
    !(message.side === "unknown" && isLikelySystemRowContent(message.content))
  );
  const knownSideCount =
    filtered.filter((message) =>
      message.side === "left" || message.side === "right"
    ).length;

  if (
    filtered.length === messages.length ||
    filtered.length < 2 ||
    knownSideCount < 2
  ) {
    return {
      messages,
      removedCount: 0,
    };
  }

  return {
    messages: filtered,
    removedCount: messages.length - filtered.length,
  };
}

function buildSideRuns(messages: LayoutFirstMessage[]): SideRun[] {
  if (messages.length === 0) {
    return [];
  }

  const runs: SideRun[] = [];
  let start = 0;

  for (let index = 1; index <= messages.length; index += 1) {
    const previous = messages[index - 1];
    const current = messages[index];

    if (current && current.side === previous.side) {
      continue;
    }

    const runMessages = messages.slice(start, index);
    runs.push({
      start,
      end: index - 1,
      side: previous.side,
      length: runMessages.length,
      quotedCount: runMessages.filter((message) =>
        !!message.quotedReplyPreview
      ).length,
      mediaCount: runMessages.filter((message) =>
        isLikelyMediaPlaceholderContent(message.content)
      ).length,
    });
    start = index;
  }

  return runs;
}

function countKnownSides(messages: LayoutFirstMessage[]): Record<
  Exclude<LayoutBubbleSide, "unknown">,
  number
> {
  return messages.reduce(
    (totals, message) => {
      if (message.side === "left" || message.side === "right") {
        totals[message.side] += 1;
      }
      return totals;
    },
    { left: 0, right: 0 },
  );
}

function dominantKnownSide(
  messages: LayoutFirstMessage[],
): LayoutBubbleSide | "mixed" {
  const totals = countKnownSides(messages);

  if (totals.left === 0 && totals.right === 0) {
    return "unknown";
  }

  if (totals.left === totals.right) {
    return "mixed";
  }

  return totals.left > totals.right ? "left" : "right";
}

function runLooksFlexible(
  messages: LayoutFirstMessage[],
  run: SideRun,
): boolean {
  const runMessages = messages.slice(run.start, run.end + 1);

  if (run.side === "unknown") {
    return true;
  }

  if (run.length === 1) {
    const [message] = runMessages;
    if (!message) {
      return true; // Treat missing message as flexible
    }
    return !!message.quotedReplyPreview ||
      isLikelyMediaPlaceholderContent(message.content) ||
      isLikelyShortContinuationContent(message.content);
  }

  return run.quotedCount > 0 || run.mediaCount > 0;
}

function otherRunSupportsSide(
  runs: SideRun[],
  side: LayoutBubbleSide,
  excludeIndex: number,
): boolean {
  if (side === "unknown") {
    return false;
  }

  return runs.some((run, index) =>
    index !== excludeIndex &&
    run.side === side &&
    run.length >= 1
  );
}

function applyRunSide<TMessage extends LayoutFirstMessage>(
  adjusted: TMessage[],
  run: SideRun,
  side: Exclude<LayoutBubbleSide, "unknown">,
): number {
  let adjustedCount = 0;

  for (let index = run.start; index <= run.end; index += 1) {
    const message = adjusted[index];
    if (!message) {
      continue; // Skip undefined elements
    }
    if (
      message.side !== side ||
      message.isFromMe !== (side === "right")
    ) {
      adjusted[index] = {
        ...message,
        side,
        isFromMe: side === "right",
      };
      adjustedCount += 1;
    }
  }

  return adjustedCount;
}

export function applyLayoutFirstParser<TMessage extends LayoutFirstMessage>(
  messages: TMessage[],
): LayoutFirstParseResult<TMessage> {
  // Filter out any null/undefined messages to prevent runtime errors
  const validMessages = messages.filter(
    (m): m is TMessage => m != null && typeof m.side === "string"
  );

  const stripped = stripLikelySystemRows(validMessages);

  if (stripped.messages.length < 2) {
    return {
      messages: stripped.messages,
      adjustedCount: 0,
      systemRowsRemovedCount: stripped.removedCount,
    };
  }

  const adjusted = stripped.messages.map((message) => ({ ...message }));
  let adjustedCount = 0;
  let changed = true;

  while (changed) {
    changed = false;
    const runs = buildSideRuns(adjusted);
    const dominantSide = dominantKnownSide(adjusted);

    for (let runIndex = 0; runIndex < runs.length; runIndex += 1) {
      const run = runs[runIndex];
      const previous = runs[runIndex - 1];
      const next = runs[runIndex + 1];

      if (
        run.side === "unknown" &&
        previous?.side &&
        previous.side !== "unknown" &&
        previous.side === next?.side
      ) {
        adjustedCount += applyRunSide(adjusted, run, previous.side);
        changed = true;
        break;
      }

      if (run.side === "unknown") {
        continue;
      }

      const neighborSide = previous?.side !== "unknown" &&
          previous?.side === next?.side
        ? previous.side
        : undefined;
      const currentHasSupportElsewhere = otherRunSupportsSide(
        runs,
        run.side,
        runIndex,
      );
      const isFlexible = runLooksFlexible(adjusted, run);

      if (
        neighborSide &&
        neighborSide !== run.side &&
        (!currentHasSupportElsewhere ||
          isFlexible ||
          dominantSide === neighborSide)
      ) {
        adjustedCount += applyRunSide(adjusted, run, neighborSide);
        changed = true;
        break;
      }

      if (
        !next &&
        previous &&
        previous.side !== "unknown" &&
        previous.side !== run.side &&
        previous.length >= 2 &&
        (previous.quotedCount > 0 ||
          previous.mediaCount > 0 ||
          dominantSide === previous.side) &&
        !currentHasSupportElsewhere &&
        (isFlexible || run.length === 1)
      ) {
        adjustedCount += applyRunSide(adjusted, run, previous.side);
        changed = true;
        break;
      }

      if (
        !previous &&
        next &&
        next.side !== "unknown" &&
        next.side !== run.side &&
        next.length >= 2 &&
        dominantSide === next.side &&
        !currentHasSupportElsewhere &&
        isFlexible
      ) {
        adjustedCount += applyRunSide(adjusted, run, next.side);
        changed = true;
        break;
      }
    }
  }

  return {
    messages: adjusted,
    adjustedCount,
    systemRowsRemovedCount: stripped.removedCount,
  };
}
