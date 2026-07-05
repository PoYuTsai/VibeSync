# Practice Girl Expansion Preview Design

## Goal

Expand the practice chat girl catalog from 60 toward 100 profiles, but review new visual/persona candidates in batches before they become app assets or server catalog entries.

## Current Gaps

- Persona distribution is uneven: `teasing_humor` is underrepresented, while `cool_rational` is overrepresented.
- `bank_staff` exists in the server profession allowlist but has no current profile.
- Existing professions lean heavily on students, nurses, flight attendants, and sales/service roles.
- Taipei is intentionally common, but the next 40 should include more New Taipei, Taoyuan, Hsinchu, Taichung, Tainan, Kaohsiung, and a few less-used city vibes.
- New photos should avoid repeating the current dating-app portrait feel too closely: vary face shape, hairstyle, glasses, makeup level, styling, scene, crop, lighting, and body language.

## Batch Strategy

- Work in batches of 10 preview candidates.
- Each batch includes a metadata table: candidate id, name, age, city, profession, persona, relationship goal, tags, self intro, and visual prompt.
- Preview images stay outside the formal `assets/images/practice_girls/practice_girl_NNN.jpg` path until approved.
- Approved candidates are later promoted into `GIRL_SEEDS`, regenerated into the Flutter catalog, and covered by tests.

## Diversity Rules

- Keep all characters clearly adult, age 22 or above.
- Avoid real brands, school names, hospital names, airline names, logos, uniforms, or identifiable institutions.
- Avoid sexualized framing; use realistic Taiwanese dating-app / lifestyle profile photos.
- Reuse existing persona ids for compatibility, but diversify the personality flavor inside each persona.
- Use `bank_staff` and existing allowlisted professions first; only add a new profession id if it is clearly worth the extra server prompt surface.

## First Preview Batch

The first batch should emphasize:

- More `teasing_humor` candidates to help balance SR count.
- At least two `bank_staff` profiles.
- Less repeated looks: short hair, glasses, natural makeup, sporty style, clean office style, artsy style, outdoor casual, mature elegant, playful streetwear, and quiet bookish style.
- Mixed cities and relationship goals.

## Promotion Criteria

A candidate can move into the formal catalog only after visual review confirms:

- The face and styling do not strongly duplicate an existing profile.
- The image has no visible text, brand logo, watermark, or institution identifier.
- The profile/persona/profession feel coherent.
- The image works as a cropped mobile card portrait.
