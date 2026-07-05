# Practice Girl Expansion 100 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Promote the approved v2 preview set into the formal practice girl catalog, expanding from 60 to 100 profiles.

**Architecture:** `supabase/functions/practice-chat/practice_persona.ts` remains the server source of truth. Flutter's `practice_girl_catalog.dart` is regenerated from the Edge catalog, and formal images are committed under `assets/images/practice_girls/practice_girl_061.jpg` through `practice_girl_100.jpg`.

**Tech Stack:** Flutter/Dart, Deno TypeScript, Supabase Edge Function data, local image conversion via PowerShell/System.Drawing.

---

### Task 1: Add Failing Catalog Guards

**Files:**
- Modify: `test/unit/features/practice_chat/domain/entities/practice_girl_catalog_test.dart`
- Modify: `test/unit/features/practice_chat/domain/entities/practice_girl_rarity_test.dart`
- Modify: `test/widget/features/practice_chat/practice_collection_screen_test.dart`

- [ ] **Step 1: Update expected catalog size to 100**

Change catalog tests from `60` to `100`, keep sequential id assertions, and assert unique ids equal `practiceGirlProfiles.length`.

- [ ] **Step 2: Update rarity guard**

Change SR count from `9` to `20`, and remove the explicit `hasLength(60)` assumption.

- [ ] **Step 3: Update collection total assertion**

Change the collection counter expectation from `' / 60'` to `' / 100'`.

- [ ] **Step 4: Run red tests**

Run:
`flutter test test\unit\features\practice_chat\domain\entities\practice_girl_catalog_test.dart test\unit\features\practice_chat\domain\entities\practice_girl_rarity_test.dart test\widget\features\practice_chat\practice_collection_screen_test.dart`

Expected before implementation: failures showing catalog length/counter still at 60.

### Task 2: Promote v2 Images

**Files:**
- Create: `assets/images/practice_girls/practice_girl_061.jpg` through `assets/images/practice_girls/practice_girl_100.jpg`

- [ ] **Step 1: Convert approved v2 PNGs**

Map `tmp/practice_girl_expansion/v2/images/B01-01.png` through `B04-10.png` to `practice_girl_061.jpg` through `practice_girl_100.jpg`, preserving preview order.

- [ ] **Step 2: Verify asset inventory**

Run a filesystem check that `practice_girl_001.jpg` through `practice_girl_100.jpg` all exist and that exactly 100 formal practice girl JPGs are present.

### Task 3: Expand Server Catalog

**Files:**
- Modify: `supabase/functions/practice-chat/practice_persona.ts`

- [ ] **Step 1: Extend `ProfessionId`**

Add new profession ids used by the approved 40 profiles.

- [ ] **Step 2: Add profession prompt configs**

Add labels, prompt material, and warm topics for each new profession. Prompts must avoid real brands, schools, hospitals, companies, shop names, and logos.

- [ ] **Step 3: Add name display ids**

Add the 40 approved `nameId` values to `NAME_DISPLAY`.

- [ ] **Step 4: Append 40 `GIRL_SEEDS`**

Append the approved candidates in v2 preview order. Persona distribution after expansion must be 20 each across the five existing persona ids.

### Task 4: Regenerate Client Catalog And Tool Text

**Files:**
- Modify: `lib/features/practice_chat/domain/entities/practice_girl_catalog.dart`
- Modify: `tools/gen-practice-catalog/gen_practice_girl_catalog.ts`
- Modify: `tools/gen-practice-photos/convert_practice_photos.dart`
- Modify comments in practice-chat files that still say `60-profile` or `60 位`

- [ ] **Step 1: Make generator comments count-neutral**

Change hardcoded "60" wording to "all" / "catalog" wording where possible.

- [ ] **Step 2: Regenerate client catalog**

Run:
`deno run --allow-read --allow-write tools/gen-practice-catalog/gen_practice_girl_catalog.ts`

- [ ] **Step 3: Update photo conversion helper**

Change the photo conversion helper from fixed `_count = 60` to a `--count` argument defaulting to `100`.

### Task 5: Verify And Finish

**Files:**
- Test: practice catalog, rarity, photo assets, catalog sync, collection widget

- [ ] **Step 1: Run Deno catalog sync test**

Run:
`deno test --allow-read tools/gen-practice-catalog/catalog_sync_test.ts`

- [ ] **Step 2: Run targeted Flutter tests**

Run:
`flutter test test\unit\features\practice_chat\domain\entities\practice_girl_catalog_test.dart test\unit\features\practice_chat\domain\entities\practice_girl_rarity_test.dart test\unit\features\practice_chat\domain\entities\practice_girl_photo_asset_test.dart test\unit\features\practice_chat\domain\entities\practice_profile_test.dart test\widget\features\practice_chat\practice_collection_screen_test.dart`

- [ ] **Step 3: Run targeted analyze**

Run:
`flutter analyze lib\features\practice_chat test\unit\features\practice_chat\domain\entities test\widget\features\practice_chat\practice_collection_screen_test.dart`

- [ ] **Step 4: Commit and push**

Commit with a Traditional Chinese message and push the feature branch.
