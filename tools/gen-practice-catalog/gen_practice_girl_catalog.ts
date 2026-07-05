// 從 Edge 權威 catalog 產生 Flutter client 的 display-only 鏡像，確保 client
// 與 server GIRL_PROFILES 逐欄一致（profileId/nameId/professionId/personaId/...）。
//
// 執行：
//   deno run --allow-read --allow-write \
//     tools/gen-practice-catalog/gen_practice_girl_catalog.ts
//
// 只鏡像 display 欄位；server-only（professionPrompt/reactionModel/signalStyle）不外洩。
import { GIRL_PROFILES } from "../../supabase/functions/practice-chat/practice_persona.ts";

function dartStr(s: string): string {
  // 單引號字串；跳脫反斜線、單引號、$。
  return "'" + s.replace(/\\/g, "\\\\").replace(/'/g, "\\'").replace(/\$/g, "\\\$") + "'";
}

function dartList(items: readonly string[]): string {
  return "[" + items.map(dartStr).join(", ") + "]";
}

const entries = GIRL_PROFILES.map((g) => {
  const fields = [
    `profileId: ${dartStr(g.profileId)}`,
    `nameId: ${dartStr(g.nameId)}`,
    `displayName: ${dartStr(g.displayName)}`,
    `age: ${g.age}`,
    `heightCm: ${g.heightCm}`,
    `city: ${dartStr(g.city)}`,
    `zodiac: ${dartStr(g.zodiac)}`,
    `relationshipGoal: ${dartStr(g.relationshipGoal)}`,
    `professionId: ${dartStr(g.professionId)}`,
    `professionLabel: ${dartStr(g.professionLabel)}`,
    `photoId: ${dartStr(g.photoId)}`,
    `personaId: ${dartStr(g.personaId)}`,
    `personalityTags: ${dartList(g.personalityTags)}`,
    `interestTags: ${dartList(g.interestTags)}`,
    `lifestyleTags: ${dartList(g.lifestyleTags)}`,
    `selfIntro: ${dartStr(g.selfIntro)}`,
  ];
  return `  PracticeGirlProfile(\n    ${fields.join(",\n    ")},\n  ),`;
}).join("\n");

export function buildCatalogDart(): string {
  return `// GENERATED FILE — do not edit by hand.
// 由 server 權威 catalog 鏡像而來，保證 client ${GIRL_PROFILES.length} 位與 Edge GIRL_PROFILES 逐欄一致。
// 來源：supabase/functions/practice-chat/practice_persona.ts (GIRL_PROFILES)
// 重新產生：deno run --allow-read --allow-write tools/gen-practice-catalog/gen_practice_girl_catalog.ts
import 'practice_girl_profile.dart';

/// ${GIRL_PROFILES.length} 位陪練女孩的 display-only catalog（profileId=photoId=practice_girl_NNN）。
const List<PracticeGirlProfile> practiceGirlProfiles = <PracticeGirlProfile>[
${entries}
];
`;
}

export const catalogTarget = new URL(
  "../../lib/features/practice_chat/domain/entities/practice_girl_catalog.dart",
  import.meta.url,
);

if (import.meta.main) {
  await Deno.writeTextFile(catalogTarget, buildCatalogDart());
  console.log(`wrote ${GIRL_PROFILES.length} profiles to ${catalogTarget.pathname}`);
}
