export interface MapShareMessage {
  isFromMe: boolean;
  content: string;
}

export interface MapShareNormalizationResult<T extends MapShareMessage> {
  messages: T[];
  collapsedCount: number;
}

export function normalizeGoogleMapsShares<T extends MapShareMessage>(
  messages: T[],
): MapShareNormalizationResult<T> {
  const normalized: T[] = [];
  let collapsedCount = 0;

  for (let index = 0; index < messages.length; index += 1) {
    const current = messages[index];
    const next = messages[index + 1];
    const currentIsUrl = isStandaloneGoogleMapsUrl(current.content);
    const currentIsPreview = isGoogleMapsPreview(current.content);
    const nextPairsWithCurrent = next != null &&
      next.isFromMe === current.isFromMe;

    if (currentIsUrl) {
      if (nextPairsWithCurrent && isGoogleMapsPreview(next.content)) {
        normalized.push(withMapShareContent(
          current,
          extractGoogleMapsPlaceName(next.content),
        ));
        collapsedCount += 1;
        index += 1;
      } else {
        normalized.push(withMapShareContent(current));
      }
      continue;
    }

    if (currentIsPreview) {
      normalized.push(withMapShareContent(
        current,
        extractGoogleMapsPlaceName(current.content),
      ));
      if (nextPairsWithCurrent && isStandaloneGoogleMapsUrl(next.content)) {
        collapsedCount += 1;
        index += 1;
      }
      continue;
    }

    normalized.push({ ...current });
  }

  return { messages: normalized, collapsedCount };
}

const GOOGLE_MAPS_URL_PATTERN =
  /^(?:https?:\/\/)?(?:maps\.app\.goo\.gl\/|goo\.gl\/maps\/|(?:www\.)?google\.[a-z.]+\/maps(?:[/?#]|$)|maps\.google\.[a-z.]+\/)[^\s]*$/i;
const MAP_PREVIEW_PREFIX_PATTERN = /^\s*(?:\[地圖預覽\]|【地圖預覽】)\s*/i;
const GOOGLE_MAPS_BOILERPLATE_PATTERN =
  /find local businesses,\s*view maps and get driving directions in goo(?:gle maps)?(?:\.{1,3})?/i;

function isStandaloneGoogleMapsUrl(content: string): boolean {
  return GOOGLE_MAPS_URL_PATTERN.test(content.trim());
}

function isGoogleMapsPreview(content: string): boolean {
  const trimmed = content.trim();
  return MAP_PREVIEW_PREFIX_PATTERN.test(trimmed) ||
    GOOGLE_MAPS_BOILERPLATE_PATTERN.test(trimmed);
}

function extractGoogleMapsPlaceName(content: string): string | undefined {
  const withoutPrefix = content.replace(MAP_PREVIEW_PREFIX_PATTERN, "");
  const beforeBoilerplate = withoutPrefix
    .split(GOOGLE_MAPS_BOILERPLATE_PATTERN, 1)[0]
    .trim();
  const title = beforeBoilerplate
    .split(/\s+[·•]\s+|\r?\n/, 1)[0]
    .replace(/[\s,;:·•….-]+$/u, "")
    .trim();

  if (!title || title.length > 120 || isStandaloneGoogleMapsUrl(title)) {
    return undefined;
  }

  return title;
}

function withMapShareContent<T extends MapShareMessage>(
  message: T,
  placeName?: string,
): T {
  return {
    ...message,
    content: placeName
      ? `[分享地點：${placeName}]`
      : "[分享了 Google Maps 地點]",
  };
}
