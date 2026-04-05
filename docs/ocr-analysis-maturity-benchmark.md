# OCR / Analysis Maturity Benchmark

Last updated: 2026-04-05

This file defines what “good enough to launch” means for VibeSync OCR and
analysis quality.

## Target Outcome

The goal is not perfect OCR.

The goal is:

- launch-safe screenshot import
- trustworthy speaker direction
- stable quoted-reply handling
- predictable quota behavior
- low enough latency that users still prefer the product over generic LLM use

## Launch Readiness Levels

### Level A: Not launchable

Any of these is a blocker:

- OCR frequently flips `me` vs `her`
- quoted replies are turned into standalone messages
- screenshot import often corrupts conversation ordering
- users see raw stack traces or broken JSON-style failures
- analysis can silently charge quota in the wrong mode

### Level B: Early-launch acceptable

This is the current target:

- mainline screenshot imports are trustworthy
- quoted replies usually attach correctly
- only a small number of complex edge cases still need manual review
- telemetry exists for slow / uncertain / repaired cases
- users can recover when OCR confidence is low

### Level C: Mature product quality

This would be a later target:

- highly stable across long screenshots and multi-image imports
- very low uncertainty rate on quoted-reply direction
- better media / sticker / video-bubble handling
- measurable latency improvements at p95
- lower need for manual OCR correction

## Quality Benchmarks

### Speaker Direction

- `me / her` direction accuracy on normal screenshots: `>= 98%`
- quoted reply preview direction accuracy: `>= 95%`
- overall import-order correctness: `>= 98%`

### Structural Accuracy

- quoted replies should remain context, not become new messages
- overlap dedupe should not frequently delete real messages
- short continuation bubbles should not frequently merge into the wrong message
- system rows / banners should be filtered without damaging real content

### User Trust Benchmarks

- raw OCR/analysis errors shown to users: `~0`
- timeout rate on OCR / image-heavy requests: `<= 2%`
- users should almost always understand whether they need to:
  - retry
  - force re-recognize
  - manually correct
  - split screenshots

## Performance Benchmarks

### Current launch targets

- single screenshot OCR p50: `< 4s`
- single screenshot OCR p95: `< 8s`
- 2-3 image OCR p95: `< 15s`
- full image-backed analysis p95: `< 12s`

### Product expectation

If the user experience starts to feel like:

- upload
- wait
- doubt whether OCR understood the screenshot
- retry again

then the product becomes easier to replace with a general-purpose LLM.

Speed is therefore part of PMF, not only an engineering metric.

## High-Value Test Cases

These are the most valuable scenarios to keep testing before launch:

1. Normal left/right chat screenshot
2. LINE quoted reply where the outer bubble is left and the quoted reply points to a prior right-side message
3. Long screenshot with date separators / system rows
4. Multi-image import with overlap at the boundary
5. Very short continuation bubbles such as:
   - `ok`
   - `到了`
   - single emoji
6. Media / sticker / video placeholders mixed with text
7. Small-text contact names or low-contrast names
8. `only_right` screenshots to confirm import behavior and user messaging remain clear

## Launch Guardrails

### Recognize-only mode

Expected behavior:

- no quota charge
- no paid-analysis deduction
- used only for OCR / import preparation

### Test-account behavior

Expected behavior:

- explicit internal test accounts may bypass quota
- this bypass should be controlled from backend configuration, not repo hardcode
- production behavior for normal users must remain identical

### Full analysis behavior

Expected behavior:

- message-based quota is applied only to real analysis flows
- image-backed analysis uses the same subscription logic as the rest of the app
- retry / fallback behavior should not double-charge

## Telemetry To Watch

The most important launch metrics are:

- OCR success rate
- timeout rate
- `slow_request`
- `near_timeout`
- `uncertain_speaker_side`
- `structure_repaired`
- `overlap_removed_count`
- `quoted_preview_attached_count`
- `system_rows_removed_count`
- quota reason / charged message count consistency

## Current Assessment

As of the current TestFlight cycle:

- mainline OCR is close to Level B
- quoted-reply handling is much improved
- launch risk is now concentrated in:
  - long screenshots
  - overlapping multi-image imports
  - short continuation bubbles
  - media/sticker/video bubbles
  - small-text / name drift cases

## Launch Decision Rule

Ship when all of the following are true:

- no P1 OCR bugs remain in TestFlight
- no quota/accounting mismatch remains for OCR-backed analysis
- users can recover cleanly from low-confidence OCR
- latency feels acceptable in common real-world flows
- telemetry is live enough to catch regressions after launch
