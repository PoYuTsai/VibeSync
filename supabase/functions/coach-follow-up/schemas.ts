// supabase/functions/coach-follow-up/schemas.ts
//
// zod schemas for request / response. Stable English keys throughout — 繁中 lives
// only in client-side displayLabel getters (lib/.../coach_follow_up_phase.dart).
//
// Caps mirror design §1.3 (response card field caps) and §2.2 (request hint cap).
// `boundaryReminder` is REQUIRED with min(1) so missing/null/empty all reject.

import { z } from "https://deno.land/x/zod@v3.22.4/mod.ts";

export const PhaseEnum = z.enum([
  "prepareInvite",
  "preDateReminder",
  "postDateReflection",
]);

export const RequestSchema = z.object({
  phase: PhaseEnum,
  answers: z.object({
    q1: z.string().min(1),
    q2: z.string().nullable().optional(),
    q3: z.string().max(80).nullable().optional(),
  }),
  partnerHint: z
    .object({
      name: z.string(),
      heatScore: z.number().int().min(0).max(100).nullable().optional(),
      gameStage: z.string().nullable().optional(),
      lastConversationSummary: z.string().max(200).nullable().optional(),
    })
    .optional(),
}).strict();

// Response card schema — boundaryReminder REQUIRED (Codex P1 #3 boundary contract).
// Caps: headline 30 / observation 80 / task 30 / suggestedLine 80 / boundaryReminder 60.
export const ResponseCardSchema = z.object({
  headline: z.string().min(1).max(30),
  observation: z.string().min(1).max(80),
  task: z.string().min(1).max(30),
  suggestedLine: z.string().max(80).nullable().optional(),
  boundaryReminder: z.string().min(1).max(60),
});

export const ResponseSchema = z.object({
  phase: PhaseEnum,
  card: ResponseCardSchema,
  model: z.string(),
  generatedAt: z.string(),
});

export type CoachFollowUpRequest = z.infer<typeof RequestSchema>;
export type CoachFollowUpResponseCard = z.infer<typeof ResponseCardSchema>;
export type CoachFollowUpResponse = z.infer<typeof ResponseSchema>;
