// 模型偶發把無關文字系統插進繁中句子。這裡只掃已知洩漏面；拉丁字母、
// 數字、emoji、CJK 與台灣聊天常見的日文假名都保留，避免白名單誤殺。
const UNEXPECTED_FOREIGN_SCRIPT =
  /[\p{Script=Greek}\p{Script=Cyrillic}\p{Script=Hebrew}\p{Script=Arabic}\p{Script=Devanagari}\p{Script=Thai}\p{Script=Hangul}]/u;
const UNEXPECTED_FOREIGN_SCRIPT_GLOBAL =
  /[\p{Script=Greek}\p{Script=Cyrillic}\p{Script=Hebrew}\p{Script=Arabic}\p{Script=Devanagari}\p{Script=Thai}\p{Script=Hangul}]/gu;

// 2026-08-20 真實樣本：「妳學新東西的時間都long在白天」。只認直接黏在
// 漢字旁、且不是更長英文單字一部分的已知壞 token；正常的英文句、縮寫、
// 「很 chill」、oolong 與 longboard 不受影響。
const EMBEDDED_LONG_TOKEN =
  /(?:(?<=\p{Script=Han})long(?![a-z])|(?<![a-z])long(?=\p{Script=Han}))/iu;
const EMBEDDED_LONG_TOKEN_GLOBAL =
  /(?:(?<=\p{Script=Han})long(?![a-z])|(?<![a-z])long(?=\p{Script=Han}))/giu;

const CLAUSE_END = /(?<=[，,。.!！？?；;：:])/u;

function containsUnexpectedForeignToken(value: string): boolean {
  return UNEXPECTED_FOREIGN_SCRIPT.test(value) ||
    EMBEDDED_LONG_TOKEN.test(value);
}

function stripUnexpectedCharacters(value: string): string {
  return value
    .replace(UNEXPECTED_FOREIGN_SCRIPT_GLOBAL, "")
    .replace(EMBEDDED_LONG_TOKEN_GLOBAL, "");
}

function trimDanglingClausePunctuation(value: string): string {
  return value
    .replace(/^[\s，,；;：:]+/u, "")
    .replace(/[，,；;：:]+\s*$/u, "")
    .trim();
}

/**
 * 丟掉含異常外語 token 的整個子句，避免只摳掉謂語後留下更怪的殘句。
 * 若整行只有一個子句，才退回逐字清除；清完為空則回 null，讓既有 payload
 * 完整性檢查走 repair／不扣費失敗，而不是把純外語垃圾顯示給客戶。
 */
export function stripUnexpectedForeignClauses(
  value: string | null,
): string | null {
  if (value === null || !containsUnexpectedForeignToken(value)) return value;

  const keptLines = value.split("\n").flatMap((line) => {
    if (!containsUnexpectedForeignToken(line)) return [line];

    const keptClauses = line
      .split(CLAUSE_END)
      .filter((clause) =>
        clause.length > 0 && !containsUnexpectedForeignToken(clause)
      );
    const withoutBadClauses = trimDanglingClausePunctuation(
      keptClauses.join(""),
    );
    if (withoutBadClauses) return [withoutBadClauses];

    const stripped = trimDanglingClausePunctuation(
      stripUnexpectedCharacters(line),
    );
    return stripped ? [stripped] : [];
  });

  const normalized = keptLines.join("\n").trim();
  return normalized || null;
}
