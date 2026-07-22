import { BEGINNER_HINT_FIXTURES } from "./beginner_hint.ts";
import { GAME_HINT_FIXTURES } from "./game_hint.ts";
import { BEGINNER_DEBRIEF_FIXTURES } from "./beginner_debrief.ts";
import { GAME_DEBRIEF_FIXTURES } from "./game_debrief.ts";
import type { EvalFixture, EvalRoute } from "./types.ts";

export type { EvalFixture, EvalRoute } from "./types.ts";

export const ALL_ROUTES: EvalRoute[] = [
  "beginner_hint",
  "game_hint",
  "beginner_debrief",
  "game_debrief",
];

export const FIXTURES_BY_ROUTE: Record<EvalRoute, EvalFixture[]> = {
  beginner_hint: BEGINNER_HINT_FIXTURES,
  game_hint: GAME_HINT_FIXTURES,
  beginner_debrief: BEGINNER_DEBRIEF_FIXTURES,
  game_debrief: GAME_DEBRIEF_FIXTURES,
};
