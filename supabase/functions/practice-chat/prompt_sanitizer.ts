const RAW_IMAGE_FILENAME_PATTERN_SOURCE = String
  .raw`(?:[A-Za-z]:)?(?:[\\/][^\s\\/]+)*[\\/]?(?:S__\d+(?:\.(?:jpe?g|png|webp|heic))?|IMG_\d+(?:\.(?:jpe?g|png|webp|heic))?|[^\\/\s]+\.(?:jpe?g|png|webp|heic))`;

const RAW_IMAGE_FILENAME_REPLACE_PATTERN = new RegExp(
  RAW_IMAGE_FILENAME_PATTERN_SOURCE,
  "gi",
);
const RAW_IMAGE_FILENAME_TEST_PATTERN = new RegExp(
  RAW_IMAGE_FILENAME_PATTERN_SOURCE,
  "i",
);

export const IMAGE_CONCEPT_PLACEHOLDER = "[image concept omitted]";

export function containsRawImageFilename(text: string): boolean {
  return RAW_IMAGE_FILENAME_TEST_PATTERN.test(text);
}

export function scrubRawImageFilenames(text: string): string {
  return text.replace(
    RAW_IMAGE_FILENAME_REPLACE_PATTERN,
    IMAGE_CONCEPT_PLACEHOLDER,
  );
}

export function clipUtf16Safe(text: string, maxCodeUnits: number): string {
  if (maxCodeUnits <= 0) return "";
  if (text.length <= maxCodeUnits) return text;
  let end = maxCodeUnits;
  const lastCodeUnit = text.charCodeAt(end - 1);
  if (lastCodeUnit >= 0xD800 && lastCodeUnit <= 0xDBFF) {
    end -= 1;
  }
  return text.slice(0, end);
}
