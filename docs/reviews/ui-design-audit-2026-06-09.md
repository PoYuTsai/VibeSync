# VibeSync — Pre-Launch UI / Copy / Visual Consistency Audit

> Date: 2026-06-09 · Reviewer: Claude Code (10-agent workflow) · Mode: review-only, no code changed.
> Scope: all user-visible screens, dialogs, sheets, and empty/loading/error states across the app.
> Evidence: code-first. Live screenshots blocked in sandbox (see §12). Findings labeled `code-verified` or `native-risk`.

**Totals: 73 findings — 0 P0 · 29 P1 · 30 P2 · 14 Polish.** 44 need an Eric taste decision · 66 code-verified · 7 native-risk.

---

## 1. Executive Summary

VibeSync is visually ambitious and, screen by screen, often genuinely attractive — but it is not yet *one* product. The audit found **73 findings (0 P0, 29 P1, 30 P2, 14 Polish)**. Nothing is outright broken or blocks App Review, but there is a thick band of ship-quality issues, and they share a small number of root causes.

**The single biggest issue is architectural, not cosmetic: two color systems coexist and are mixed *within the same screen*.** `app_colors.dart` defines a flat dark-Material system (the only one wired into `ThemeData`) AND a 'warm theme' (purple gradient + glassmorphism + bokeh + orange CTAs). The warm-glass text tokens were designed for a near-white glass surface; when they land on the dark gradient (which happens across opener, analyze cards, coach follow-up, partner dialogs, paywall) contrast collapses. This one root cause generates roughly a dozen of the P1 contrast/consistency findings. Fix the system once and a large fraction of the list retires together.

**The second theme is positioning.** The only screen that explains what VibeSync *is* — the 3-page onboarding deck — is **dead code** (A-01: never routed, zero callers). New users go splash → login wall → empty partner list, never told this is an AI dating coach. Meanwhile the post-login shell reads as a *tracking/reporting tool* (首頁/報告/學習 + '新增對象'), not a coach, contradicting the snapshot's own 'coach on your side' positioning.

**The third theme is brand voice vs. brief.** Eric's brief names purple/blue gradients, bokeh, and over-glassmorphism as 'AI-slop' to avoid — yet those are the *literal named tokens* of the warm theme, leaned on hardest in the highest-stakes flows (opener, paywall, partner detail). And copy repeatedly frames the product as 'AI 正在分析' (the tool analyzing you) rather than 'a coach helping you'. These are not bugs to fix silently — they are taste decisions only Eric can make, which is why **44 of 73 findings are tagged `needsEricTaste`**.

**App Review risk is low but non-zero:** an English-only booster sheet leaking 'RevenueCat booster IAP / read-only for now' to end users (H-02/H-03/DATA-03), a paywall promising a '五維雷達圖' the product never delivers (G-03), and a '免費' quota message shown to paying users (COPY-01).

Evidence is **code-first and honestly labeled**: live web-preview screenshots were impossible in this sandbox (no browser system libraries, no test credentials — see §12). 66 findings are provable from source (`code-verified`); 7 depend on device rendering (`native-risk`). No finding is claimed as screenshot-verified.

---

## 2. Overall Scores

Grades are A–F per the 13-category rubric, calibrated to the same shared design-system facts so clusters are comparable. The pattern is clear: **typography, layout and App-Review-readiness are solid (mostly B); color/contrast and cross-screen consistency are the weak columns (multiple C/D), driven entirely by the dual-color-system mixing.** AI-slop scores cluster at C/D because the warm theme *is* the thing the brief flags. Copywriting scores well in isolation (B/A) per screen but the dedicated copy pass surfaced systemic engineering-vocab leakage. 'A' in paywallQuota for opener/coach reflects correct *gating logic*, not visual polish.

| Cluster | First | Hier | Type | Color | Layout | RWD | Inter | Motion | Copy | Consist | Pay | Slop | Review |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **A** Entry & Shell | C | B | B | C | B | B | B | C | C | C | N/A | D | B |
| **B** Opener / 開場救星 | B | B | B | C | C | C | B | C | A | B | A | C | B |
| **C** Analyze input & OCR | B | B | B | C | C | C | B | B | A | C | N/A | C | B |
| **D** Analyze result cards & charts | C | C | B | D | B | C | C | D | B | D | B | C | B |
| **E** Coach 1:1 & follow-up | B | B | B | D | B | C | B | C | A | C | A | C | B |
| **F** Partner | B | B | B | C | B | C | C | C | A | C | B | C | B |
| **G** Profile / Learning / Report | B | B | B | C | B | C | B | B | A | C | C | C | B |
| **H** Subscription / Paywall / Settings | B | B | B | D | B | C | C | B | C | D | B | C | C |
| **COPY** Copy pass (Traditional-Chinese product language) | – | – | – | – | – | – | – | – | B | – | – | N/A | – |
| **DATA** Data-state / quota / paywall consistency pass | – | N/A | N/A | N/A | – | – | C | – | – | – | B | N/A | B |

*Grade key: A excellent · B good · C mediocre · D weak · F broken · N/A or – = not applicable to cluster.*

---

## 3. Top 10 Must Fix Before Launch

1. **A-01 (P1) — Onboarding (OnboardingScreen) + router**
   - The only product-explanation surface is unreachable dead code — fixing it is the highest-leverage positioning win and it's ~1h.
2. **D-03 (P1, taste) — Whole analyze result stack (final_recommendation_card + psychology_card vs score_hero_card/radar/gauge/stage/reply_style_card)**
   - The dual color system is stacked inside a single analyze result (core flow); this is the canonical instance of the root-cause that drives ~12 other findings.
3. **C-01 (P1) — ImagePickerWidget helper text (rendered in analysis_screen screenshot setup + opening_rescue_screen)**
   - Hardcoded #8B4557 hint on dark gradient is <2:1 — functionally invisible helper text on the analyze/opener entry, the most-used flow.
4. **G-03 (P1, taste) — my_report_screen _lockedReportCard (free-user paywall card)**
   - Paywall promises a '五維雷達圖' the paid product never shows — a concrete pay-for-something-you-don't-get claim with App-Review + trust risk.
5. **H-02 (P1, taste) — BoosterPurchaseSheet (whole sheet)**
   - Booster sheet is English-only inside a 100% Traditional-Chinese product AND leaks engineering status to users — embarrassing on the conversion path.
6. **C-05 (P1, taste) — AnalysisErrorWidget (analysis_error_widget.dart)**
   - Moderation refusal painted full error-red with a blocking '無法處理此內容' reads as the coach judging the user — directly against the brand promise.
7. **B-01 (P1) — OpeningRescueScreen body (Scaffold inside GradientBackground)**
   - Opener (core, high-frequency) has no SafeArea — trailing content/CTA risks the home-indicator zone on modern iPhones.
8. **A-05 (P1, taste) — MainShell (post-login home shell) — copy + nav**
   - The home shell positions the app as a data-entry tool, not a coach — weakens the core value right after the login cost. (Taste: touches ADR-15.)
9. **DATA-01 (P1) — opening_rescue_screen.dart — opener generation error state**
   - Raw exception strings render directly in the opener error state on network/timeout failures — users see stack-ish text, never raw errors rule.
10. **COPY-01 (P1) — Manual / screenshot analysis (analysis_service.dart MonthlyLimitExceededException + DailyLimitExceededException, surfaced via streaming_analyze_notifier.dart:247 and AnalysisException.message)**
   - '免費' is hardcoded into a quota message that also fires for paying Starter/Essential users — wrong and confusing on the billing surface.

---

## 3b. Taste Decisions Needing Eric (decide these before CC fixes)

44 findings are subjective brand/voice calls. They collapse into **6 decisions** — make these first, especially #1, which gates the whole contrast/consistency band.

### 1. Color-system direction (decide FIRST — unblocks ~12 findings)
Commit to ONE system, or formally split which screens use warm-glass vs flat-dark. Either de-purple/de-glass the warm theme toward a calmer coach aesthetic, OR keep the warm theme but STOP rendering its near-white-surface text tokens on dark gradients. Until this is decided, the contrast/consistency P1s (D-03, F-01, G-01, H-01, C-02, C-07, E-05) can't be fixed cleanly.

*Related findings:* `A-03`, `D-03`, `F-01`, `F-02`, `G-01`, `H-01`, `C-07`, `E-05`

### 2. AI-slop aesthetic — how far to lean on gradient/bokeh/glass
Your brief calls these out, but they are the brand's current signature on opener/paywall/partner-detail (the highest-stakes screens). Decide the intended aesthetic: keep-and-own it, dial it back, or remove. This is pure brand taste.

*Related findings:* `B-03`, `A-06`, `C-06`, `D-08`, `G-07`, `H-07`

### 3. Coach voice vs tool voice (copy register)
Multiple surfaces frame the app as 'AI 正在分析你' rather than 'a coach helping you'. Decide the canonical voice and whether to rewrite loading/score/error copy toward warmth. Also: numeric heat scores / '5維雷達' / game-stage funnel read metric-forward — keep the gamified register or soften it?

*Related findings:* `B-05`, `DATA-02`, `C-05`, `F-06`, `D-04`, `D-09`, `E-03`

### 4. Positioning & first-run (onboarding + shell)
Should onboarding be revived (A-01) and should the home shell + primary FAB lead with a coach action instead of '新增對象'? A-05 contradicts ADR-15's partner-first FAB, so it needs a product call, not a silent edit.

*Related findings:* `A-01`, `A-05`, `F-05`, `E-06`

### 5. Splash timing & identity legibility
3.5s pure-decoration splash on every cold start (A-02) + low-contrast tagline (A-04). Trim to ~1.6–2s + tap-to-skip, and raise the '你專屬的 AI 約會教練' contrast?

*Related findings:* `A-02`, `A-04`, `A-07`

### 6. Gendered copy assumption
Hardcoded '她' across analyze-input assumes a female counterpart / male user. Keep, parameterize, or neutralize?

*Related findings:* `C-10`

---

## 4. Screen-by-Screen Findings

### Cluster A — Entry & Shell (8)

> _Reviewer notes:_ Could-not-verify caveats: live/on-device rendering was NOT observable (no browser .so deps, no test creds) — all contrast figures are computed/estimated from hardcoded values, so exact ratios behind the splash orbs/vignette (A-04) and behind the transparent AppBar over moving bokeh (A-08) are marked native-risk. KNOWN CONTRAST SUSPECTS checked: glassTextHint #8B4557 on glassWhite #F5F0F8 ≈ 6.9:1 and glassTextSecondary #6C5A6B on #F5F0F8 ≈ 6.2:1 both PASS AA — not reported as defects. unselectedText #5D4E6B and textSecondary #B3B3B3 are not used in this cluster's visible entry screens (login/shell use onBackgroundSecondary #E0D0E8 on the dark gradient, which passes). The most consequential finding is A-01: the onboarding deck is fully built/tested but unreachable (zero callers of OnboardingService.isCompleted, router never visits /onboarding), so the cluster's clearest positioning asset never renders — this drags firstImpression and copywriting scores. paywallQuota is N/A (no quota/paywall surface in the entry cluster; /paywall exists in routes but is outside scope). appReviewRisk graded B: login has proper Apple+Google on iOS, legal disclaimer with terms/privacy links, and plain-language error mapping — no raw JSON/engineering vocab leaks found in this cluster.

#### A-01 — P1 · First
- **Screen/Flow:** Onboarding (OnboardingScreen) + router
- **Evidence (`code-verified`):** lib/app/routes.dart:27 initialLocation '/login'; redirect (lines 35-41) only routes between '/login' and '/'. '/onboarding' (routes.dart:48-51) is never pushed/go'd from anywhere. grep confirms OnboardingService.isCompleted() (onboarding_service.dart:7) has ZERO callers; the only consumer of the onboarding route does not exist. New users go splash -> /login -> / (MainShell partner list), never seeing the 3-page value-prop deck.
- **Problem:** The entire onboarding deck — the only place that explains WHAT VibeSync does ('貼上對話或截圖,AI 幫你分析…', 熱度 0-100, 五種風格) — is dead code. It is built, styled, and tested, but unreachable. First-time users land directly on the login wall, then on an empty partner list, with no explanation of the product.
- **User impact:** A brand-new user never learns within 3s (or ever) that this is an AI dating coach that analyzes chats and drafts replies. The clearest positioning asset in the cluster is invisible. Hurts activation and the 'is this for me' moment App Review and dogfooders judge on.
- **Suggested fix:** Wire onboarding into the flow: in App/splash-complete or after first successful login, check OnboardingService.isCompleted() and route to '/onboarding' before '/' when false. Lowest-risk: gate it post-login so it doesn't interfere with the auth redirect in routes.dart.
- **Effort:** ~1h · **Risk if fixed:** Touches the go_router redirect/auth gate (routes.dart). Must ensure the onboarding check does NOT bypass the !isLoggedIn -> /login guard, or it could expose app shell to unauthenticated users. Add a widget test for the redirect matrix. · **Needs Eric taste:** no

#### A-03 — P1 · Consist · 🎨 **TASTE**
- **Screen/Flow:** Entry cluster as a whole (splash / login / main_shell vs onboarding / app_theme)
- **Evidence (`code-verified`):** THREE different visual systems in one entry flow. (1) Splash: bespoke #0A0A0F bg + purple orbs #8A3CDC/#B450FF, NOT in app_colors at all (splash_screen.dart:183,206-232). (2) Login + MainShell: warm theme — GradientBackground #1A0533->#4A2C6A + bokeh + glass + orange ctaStart/ctaEnd nav pills (login_screen.dart:730, main_shell.dart:70,139-143). (3) Onboarding: flat dark Material — AppColors.background #121212, AppColors.primary #6B4EE6 purple button (onboarding_screen.dart:69,142). app_theme.dart only wires the FLAT system, yet the screens the user actually sees ignore it.
- **Problem:** The first three screens a user sees each pull from a different palette and primary color (purple orbs -> warm-purple gradient with ORANGE CTAs -> flat-dark with PURPLE CTA). The 'primary action color' changes meaning between screens. The one screen that obeys the wired ThemeData (onboarding) is the one nobody sees.
- **User impact:** Reads as three apps stitched together — exactly the 'engineering/template feel' Eric flags. Undermines the premium 'your personal coach' positioning at the highest-stakes first moments.
- **Suggested fix:** Pick ONE entry identity. Either commit splash+onboarding to the warm theme (matching login/shell), or de-purple the warm theme. At minimum make the splash purple resolve into the login warm gradient so the transition feels continuous, and align CTA color (orange vs purple) across login button and onboarding button.
- **Effort:** ~half-day · **Risk if fixed:** Medium visual-regression surface; many shared warm widgets. No logic/quota/auth risk, but touches GradientBackground used app-wide — snapshot/golden the affected screens. · **Needs Eric taste:** yes

#### A-05 — P1 · Copy · 🎨 **TASTE**
- **Screen/Flow:** MainShell (post-login home shell) — copy + nav
- **Evidence (`code-verified`):** main_shell.dart:76 AppBar title hardcoded 'VibeSync'; tabs (lines 113-115) '首頁 / 報告 / 學習'; FAB tooltip '新增對象' opening /partner/new (lines 92, 206-209). Nowhere in the shell does the word 教練 / Coach appear, and Coach 1:1 (described as THE core product) has no top-level entry — the primary FAB is partner CRUD, not 'start coaching / get a reply'.
- **Problem:** The home shell positions the app as a tracking/reporting tool (首頁/報告/學習 + 'add a person'), not as a coach on your side. The headline moat 'it remembers and converges you on a better next move' is absent from the nav. A first-time post-login user sees an empty partner list and an 'add object' button, not a 'help me reply' coach action.
- **User impact:** The tool-feel vs coach-feel tension snapshot.md explicitly warns about. Users don't feel guided; they feel like they're being asked to do data entry. Weakens the core value perception right after the login cost.
- **Suggested fix:** Reframe nav/CTA toward coaching: make the primary action '貼上對話 / 截圖,讓教練幫你' (analyze/opener entry) rather than '新增對象', or rename the AppBar/first tab to lead with the coach value. Subjective wording — align with Eric.
- **Effort:** ~1h · **Risk if fixed:** Low-medium: FAB currently routes to /partner/new per ADR-15 (documented in code). Changing the primary action contradicts an existing architecture decision, so this needs a product call, not a silent edit. · **Needs Eric taste:** yes

#### A-02 — P2 · Motion · 🎨 **TASTE**
- **Screen/Flow:** SplashScreen
- **Evidence (`code-verified`):** splash_screen.dart:136-161 _startAnimationSequence: title forward, +1000ms subtitle, +800ms shimmer, +200ms dots, +1500ms onComplete. Total fixed delay ≈ 3.5s of pure animation with no work happening behind it (Supabase/RevenueCat/Hive init already finished in main.dart:21-32 BEFORE runApp). There is no skip/tap-to-continue.
- **Problem:** A hard 3.5s branded splash gates EVERY cold start, and it is pure decoration — all real initialization completed before the widget tree even built. Returning users (the dogfood cohort) eat 3.5s every launch before reaching their task. No tap-to-skip.
- **User impact:** Daily/returning users (TestFlight dogfooders, the people whose retention matters now) pay a 3.5s tax on every open. Feels slow and self-indulgent rather than fast-to-value. The product promise is 'help me reply NOW' — 3.5s of orbs contradicts it.
- **Suggested fix:** Cut the total sequence to ~1.6-2.0s (title + tagline land, then exit), and/or add a GestureDetector that calls widget.onComplete() on tap. Consider showing splash only on first launch / cold start.
- **Effort:** <30min · **Risk if fixed:** Low. Only timing constants and an optional tap handler; no auth/quota/data touched. Verify onComplete isn't double-fired (guard with a bool). · **Needs Eric taste:** yes

#### A-04 — P2 · Color · 🎨 **TASTE**
- **Screen/Flow:** SplashScreen subtitle '你專屬的 AI 約會教練'
- **Evidence (`native-risk`):** splash_screen.dart:286-291: tagline rendered Colors.white.withValues(alpha: 0.35) at fontSize 14 on bg #0A0A0F. Effective foreground ≈ RGB(96,96,99); estimated contrast ≈ 2.7-2.9:1, below WCAG AA 4.5:1 for body text. Exact on-device value depends on the orb glow and vignette compositing behind it, hence native-risk.
- **Problem:** The single line that states the product's identity (AI dating coach) is the lowest-contrast text on the splash. It is also animated (opacity tween from 0) and small (14px), so it is barely legible at the exact moment positioning matters most.
- **User impact:** Users with average eyesight or in daylight may not read the one sentence that tells them what the app is. Weak positioning + accessibility shortfall.
- **Suggested fix:** Raise tagline opacity to ~0.7-0.8 once its entrance animation settles, or bump weight/size. Keep the fade-in but land it at a legible final alpha.
- **Effort:** <30min · **Risk if fixed:** None — single style value. · **Needs Eric taste:** yes

#### A-06 — P2 · Slop · 🎨 **TASTE**
- **Screen/Flow:** GradientBackground (used by Login + MainShell) and SplashScreen
- **Evidence (`code-verified`):** gradient_background.dart:60-115 ships a purple gradient #1A0533->#4A2C6A plus three perpetually-breathing bokeh blobs (bokehPink/Coral/Yellow, blur 50-70, 18% scale pulse). splash_screen.dart:204-233 adds three MORE animated purple glow orbs + vignette. These are precisely the named tokens (bokehPink, glassWhite, gradient bg, purple primary) that the brief lists as Eric's stated AI-slop aversions.
- **Problem:** Both entry surfaces lean hard on purple/blue gradients + bokeh blobs + over-glassmorphism — the exact 'generic AI app' aesthetic Eric dislikes. It is decorative motion with no informational role, running continuously (battery + 'template feel').
- **User impact:** Reads as a stock AI-app template to a discerning user, diluting the premium personal-coach positioning. Continuous animation also costs battery/GPU on the entry screens.
- **Suggested fix:** This is a taste call, not an objective bug: decide how much bokeh/glow survives. If trimming, reduce blob count/opacity and freeze the pulse after entrance. Flagging the tension, not asserting it is wrong.
- **Effort:** ~half-day · **Risk if fixed:** GradientBackground is app-wide; visual regression surface is large. No logic risk. · **Needs Eric taste:** yes

#### A-07 — P2 · Hier · 🎨 **TASTE**
- **Screen/Flow:** OnboardingPage illustrations
- **Evidence (`code-verified`):** onboarding_page.dart:28-40 + 71-82: each of the 3 pages renders a 200x200 purple-tinted circle containing a generic Material glyph (favorite_border / psychology_outlined / chat_bubble_outline). Comment at line 27 admits 'Image placeholder (can be replaced with actual images)'.
- **Problem:** The value-prop deck (if A-01 is fixed and it becomes visible) leads each page with a placeholder decorative icon in a tinted circle — meaningless decorative icons / generic stacked layout, another AI-slop pattern. They illustrate nothing about the actual product (no screenshot of an analysis, no hotness meter, no reply styles).
- **User impact:** Even once reachable, onboarding fails to SHOW the product. A psychology brain icon does not demonstrate '熱度 0-100' or 'five reply styles'; users still can't picture the value.
- **Suggested fix:** Replace the three placeholder glyphs with real product visuals (a sample analyzed chat, the 0-100 heat bar, the five-style picker). Ties to A-01 — only worth doing if onboarding is wired in.
- **Effort:** ~half-day · **Risk if fixed:** None functionally; needs asset creation. · **Needs Eric taste:** yes

#### A-08 — Polish · Layout
- **Screen/Flow:** MainShell AppBar over GradientBackground
- **Evidence (`native-risk`):** main_shell.dart:70-83: GradientBackground wraps a Scaffold whose AppBar is backgroundColor transparent over the moving bokeh layer. The bottom nav uses SafeArea (line 109) but the AppBar relies on the default Scaffold top inset. The animated bokehPink orb is positioned top:-30,right:-20 (gradient_background.dart:77-89), i.e. directly behind the transparent AppBar title/settings icon.
- **Problem:** A bright animated pink blob drifts behind the transparent AppBar where the 'VibeSync' title (white) and settings icon sit. On the lighter part of the gradient/blob, white-on-pink contrast for the title and icon may dip, and the moving blob creates a distracting backdrop for the top bar.
- **User impact:** Intermittent legibility dip and visual noise on the persistent top bar of the main shell — felt on every session, device-dependent.
- **Suggested fix:** Add a subtle scrim/blur behind the AppBar (or a soft top-down dark gradient) so title+settings stay legible regardless of blob position. Confirm on a real device.
- **Effort:** <30min · **Risk if fixed:** Low; cosmetic. Verify the scrim doesn't clash with the warm theme. · **Needs Eric taste:** no

### Cluster B — Opener / 開場救星 (6)

> _Reviewer notes:_ Could NOT capture screenshots (sandbox lacks browser deps, no test creds) — no rendered-pixel or on-device verification. Contrast findings on semi-transparent glass (B-02) are marked native-risk because the composited background depends on runtime alpha blending I could not measure; on a fully-opaque glassWhite #F5F0F8 surface the maroon hint #8B4557 actually passes AA (~6:1), so the risk is specifically the 0.42-alpha draft rows. Keyboard-overlap behavior for the manual-input tab relies on SingleChildScrollView reflow and was not runtime-verified. Strengths worth noting: paywall/quota handling is genuinely strong — `_estimatedCost` is a flat 3, the quota hint clearly says '已生成，不會重複扣額度', free-user locking is per-style with a clean upgrade path, and `_canStartGeneration` defers to the Edge Function rather than blocking a fresh free user (good 'free users keep core access' compliance). The next-step / pioneer-plan copy is the best coach-voice writing in the cluster. profileAnalysis rendering whitelists keys (line 1327) so telemetry keys like insufficientInfo never leak — no raw JSON shown. GradientButton has a proper disabled visual (grey gradient, no glow) and loading spinner. App Review risk graded B mainly due to B-06 (raw exception leak) and B-01 (no SafeArea), both fixable pre-launch.

#### B-01 — P1 · RWD
- **Screen/Flow:** OpeningRescueScreen body (Scaffold inside GradientBackground)
- **Evidence (`code-verified`):** opening_rescue_screen.dart:526-528 body is `SingleChildScrollView` with `padding: EdgeInsets.symmetric(horizontal:20, vertical:8)` and NO SafeArea. GradientBackground (gradient_background.dart) also has no SafeArea; it is a Stack with the Scaffold child. The AppBar covers the top notch, but the scroll content's bottom (line 667 `SizedBox(height:40)`) is the only bottom inset protection.
- **Problem:** There is no `SafeArea` (or `MediaQuery.viewPadding.bottom`) wrapping the scrollable content. On devices with a home indicator / gesture bar, the trailing content and the final '她回覆了，開始分析對話' FilledButton can sit very close to or under the gesture area. The fixed 40px bottom spacer is a guess, not an inset.
- **User impact:** Users on modern iPhones (the TestFlight target) may find the bottom CTA and the closing helper copy crowding the home indicator, and during keyboard entry the manual-input fields rely solely on SingleChildScrollView reflow with no explicit bottom inset.
- **Suggested fix:** Wrap the body's Column (or the SingleChildScrollView) content in a SafeArea(top:false) or add `MediaQuery.of(context).padding.bottom` to the trailing SizedBox so the last CTA clears the gesture bar on all devices.
- **Effort:** <30min · **Risk if fixed:** Low; pure layout. No quota/paywall path touched. Verify the AppBar still owns the top inset so you don't double-pad. · **Needs Eric taste:** no

#### B-02 — P1 · Color · 🎨 **TASTE**
- **Screen/Flow:** Recent drafts card draft row + opener helper rows (_buildDraftRow, _buildNextStepRow, _buildProfileAnalysisItems, _buildPioneerPlanCard)
- **Evidence (`native-risk`):** glassTextHint = #8B4557 (app_colors.dart:48). In _buildDraftRow the row background is `AppColors.glassWhite.withValues(alpha:0.42)` over the dark #1A0533→#4A2C6A gradient (opening_rescue_screen.dart:748), and the preview text uses glassTextHint (line 787). The same #8B4557 hint is used for description lines in _buildNextStepRow (line 1199/1216) and the pioneer-plan intro (line 1265). On full-opacity glassWhite #F5F0F8 the maroon hint clears AA (~6:1), but on a 0.42-alpha glass composited over the dark gradient the effective background is much darker, collapsing the ratio.
- **Problem:** #8B4557 (a dark maroon) was chosen as a 'hint' colour assuming a near-white surface. Where the surface is a semi-transparent glass over the dark gradient (the draft rows), the composite background darkens and the maroon-on-dark contrast likely drops below AA 4.5:1 for these small caption-sized strings.
- **User impact:** The draft preview line and several secondary helper descriptions become hard to read for users in bright environments, exactly the secondary copy that tells them what each saved draft is.
- **Suggested fix:** Either raise the draft-row glass alpha toward opaque (so hint text sits on a light surface as designed), or swap glassTextHint for glassTextSecondary on the semi-transparent rows, or pin a solid light fill behind hint text. Verify the composited ratio on-device.
- **Effort:** <30min · **Risk if fixed:** Low; cosmetic colour/alpha change. No logic touched. · **Needs Eric taste:** yes

#### B-03 — P1 · Slop · 🎨 **TASTE**
- **Screen/Flow:** Whole screen — GradientBackground bokeh orbs + glass cards
- **Evidence (`code-verified`):** Screen is wrapped in `GradientBackground` (line 514) which renders three perpetually animating bokeh orbs (gradient_background.dart:77-115: bokehPink/bokehCoral/bokehYellow, blur 50-70, infinite `repeat(reverse:true)`), over the #1A0533→#2D1B4E→#4A2C6A purple gradient, with every content block a `GlassmorphicContainer`. This is the exact stack Eric lists as AI-slop: purple gradient + over-glassmorphism + bokeh blobs.
- **Problem:** The opener (a core, high-frequency flow) leans hard on every named AI-slop token at once: animated bokeh orbs, purple gradient bg, and stacked glass cards (analysis card + opener cards + reason card + pioneer card + saved-draft notice + next-step card). This is a brand-taste tension, not an objective bug, but it is the strongest aiSlop concentration in the cluster and the bokeh animation runs forever (3 AnimationControllers).
- **User impact:** Risks the 'generic/template/engineering' feel Eric explicitly dislikes on a screen users hit often; the always-on bokeh also costs battery/GPU during long manual entry.
- **Suggested fix:** Eric decision: either dial the bokeh opacity/animation down (or freeze it while the keyboard is open / during scroll), reduce the number of stacked glass cards by merging the saved-draft notice into the next-step card, and consider whether this flow should align to the flat dark Material system instead of the warm glass one.
- **Effort:** ~half-day · **Risk if fixed:** Medium; touches shared GradientBackground used by other screens — changing it ripples cluster-wide. Keep change local to this screen if possible. · **Needs Eric taste:** yes

#### B-04 — P2 · Layout
- **Screen/Flow:** Opener cards horizontal list (_buildResults / _buildOpenerCard)
- **Evidence (`code-verified`):** Outer list is `SizedBox(height:220)` (line 1000) holding cards of fixed `width:280` (line 1372). Inside, content is `Expanded` with `Text(... maxLines:6, overflow:ellipsis)` (line 1423-1424). The 220px height and 6-line cap are hardcoded regardless of text scale.
- **Problem:** With larger system font sizes (Dynamic Type / accessibility text scaling), AppTypography.bodyMedium at height 1.6 inside a fixed 220px card will exceed 6 lines and silently ellipsis-truncate the actual opener line — the paid deliverable the user is meant to copy. The fixed height does not grow with text scale.
- **User impact:** Users with larger text settings may see their recommended opener cut off mid-sentence with '…', and the copy button still copies the full (correct) text, so the visible vs copied mismatch is confusing.
- **Suggested fix:** Let the card height be intrinsic (wrap list in a height that derives from content, or use a vertical layout / expandable card for the recommended opener) and/or scale the 220 height by MediaQuery.textScaler. At minimum raise maxLines and test at 1.3x text scale.
- **Effort:** ~1h · **Risk if fixed:** Low-medium; layout only, but the opener content is the paid artifact so verify nothing clips at default scale after the change. · **Needs Eric taste:** no

#### B-05 — P2 · Copy · 🎨 **TASTE**
- **Screen/Flow:** 'AI 正在分析...' loading state + 'AI 推薦' badge + 'AI 推薦理由' (build, _buildResults)
- **Evidence (`code-verified`):** Loading copy is `'AI 正在分析...'` (line 637). Result surfaces say `'AI 推薦'` (line 1401) and `'AI 推薦理由：...'` (line 1034). snapshot.md product-language rule: prefer '教練在幫你整理下一步' over 'AI 在分析你' — coach-on-your-side, not a tool analyzing the user.
- **Problem:** The loading and recommendation copy frames the product as 'AI analyzing' rather than a coach helping. '分析' here even reads as analyzing the user's situation, which is precisely the tool-like framing the product-language rule warns against. The rest of this screen's copy (next-step card, pioneer card) is excellent and coach-voiced, so this is an inconsistency.
- **User impact:** Minor brand-voice erosion on a core flow; small but it is the one spot that breaks the otherwise strong 'coach on your side' tone the rest of the screen nails.
- **Suggested fix:** Reword loading to coach voice, e.g. '教練正在幫你想開場…', and consider '教練建議' instead of 'AI 推薦' / 'AI 推薦理由'. Pure string change.
- **Effort:** <30min · **Risk if fixed:** Very low; copy only. Confirm no widget test asserts the exact 'AI 正在分析' / 'AI 推薦' strings before changing. · **Needs Eric taste:** yes

#### B-06 — P2 · Motion
- **Screen/Flow:** Error state in build() (line 647-659)
- **Evidence (`code-verified`):** The catch-all handler sets `_error = e.toString().replaceFirst('Exception: ', '')` (line 464) and the UI renders it raw as red centered text (line 651-657). Only OpenerQuotaExceededException is specially handled (line 453); any other thrown message (network, format failure, server error string) is shown verbatim to the user.
- **Problem:** A generic exception's `.toString()` is shown directly. If the OpenerService ever throws a message containing engineering vocabulary (schema/JSON/responseMode/error code) or an untranslated server/network string, it leaks straight to the user as the error UI. The product rule requires plain, actionable, reassuring errors and never raw schema/JSON. There is also no retry affordance in the error state.
- **User impact:** On a backend/format hiccup the user could see a raw or English technical string instead of a calm Chinese 'reassuring + actionable' message; format failure should not even look like it cost quota, and there is no clear 'try again' path beyond re-tapping generate.
- **Suggested fix:** Map non-quota exceptions to a small set of friendly Chinese messages (network vs server vs format) before assigning `_error`, never surface a raw `.toString()`, and add a '再試一次' affordance. Confirm format-failure path does not charge quota (server side) and consider a reassurance line that it didn't.
- **Effort:** ~1h · **Risk if fixed:** Medium; this is the analyze/opener high-risk zone. Ensure the quota-exceeded branch still routes to paywall and that you don't swallow a real message needed for debugging (log it, show friendly). · **Needs Eric taste:** no

### Cluster C — Analyze input & OCR (10)

> _Reviewer notes:_ Could-not-verify caveats (no screenshots: sandbox has no browser deps, no test creds — all rendering claims are code-derived or marked native-risk): (1) analysis_screen.dart is 297KB and exceeds the read limit; I read the cluster widgets in full and grepped analysis_screen only for render-context (GradientBackground/SafeArea/widget usage). I did NOT audit the full analysis_screen body, so quota-charging behaviour on UNSAFE_INPUT/format-failure (C-05) is unverified — flagged as a thing to check, not a confirmed defect. (2) Contrast ratios: glassTextHint #8B4557 on glassWhite #F5F0F8 actually PASSES AA (~5.9:1) — the suspect list overstated that pairing on glass; the real failure is glassTextHint/unselectedText on the DARK gradient (C-01) and unselectedText on light translucent cards (C-08, borderline, native-risk). (3) Keyboard/scroll behaviour in the screenshot dialog (C-04) and all bottom-sheet keyboard overlap are native-risk — could not run on device. (4) SafeArea: new_conversation_screen.dart and profile_card_screen.dart use SingleChildScrollView inside Scaffold without an explicit SafeArea, relying on AppBar; not flagged as a finding since AppBar covers the top inset, but bottom-inset on gesture devices is unverified. (5) ConversationTile (C-02) appears superseded by PartnerConversationTile in the live partner-detail path; treat the deletion suggestion as conditional on confirming no remaining route. Strong points worth noting: copywriting in the recognition dialog and new-conversation hints is genuinely good coach-voice (graded A) — context-aware hints, reassuring '不確定可以先跳過', non-pushy. Error/empty/loading states all EXIST and are styled (error widget, retry-exhausted state, summary empty-state, image-picker reject/warn paths) — that maturity lifted interactionStates and motionLoading to B.

#### C-01 — P1 · Color
- **Screen/Flow:** ImagePickerWidget helper text (rendered in analysis_screen screenshot setup + opening_rescue_screen)
- **Evidence (`code-verified`):** image_picker_widget.dart lines 195-220: helper strings ('每張盡量保留 15 則內，辨識會更穩。', '請上傳聊天畫面...') use color: AppColors.glassTextHint (#8B4557, a dark maroon). The widget is mounted at analysis_screen.dart:5090 inside a Container with color AppColors.primary @5% alpha sitting on GradientBackground (#1A0533→#2D1B4E dark purple). glassTextHint is a GLASS-surface token (designed for #F5F0F8 near-white), used here on a dark surface.
- **Problem:** glassTextHint #8B4557 (relative luminance ~0.05) on dark purple gradient (~#2D1B4E, luminance ~0.03) yields a contrast ratio well under 2:1 — far below WCAG AA 4.5:1 for body text. The token is being used on the wrong color system's background. The sibling helper text 12 lines below at analysis_screen.dart:5104 correctly uses Colors.white@0.55, proving the inconsistency.
- **User impact:** Every user in the screenshot-import flow gets near-invisible guidance about how many messages per screenshot and how to capture LINE reply frames — exactly the instructions that prevent bad OCR. They will skip it and feed poor screenshots, degrading analysis quality and confidence.
- **Suggested fix:** Swap glassTextHint for an on-dark token (AppColors.onBackgroundSecondary #E0D0E8 or Colors.white@0.6) in image_picker_widget.dart for the helper texts and the '選圖'/'壓縮中' labels (which use unselectedText #5D4E6B, also too dark on the gradient). Audit whether ImagePickerWidget is ever shown on a glass surface; if not, drop glass tokens entirely.
- **Effort:** <30min · **Risk if fixed:** Low. Pure color swap, no logic. Only caveat: ImagePickerWidget is shared by opener too — verify opener also renders on dark gradient (it does, opening_rescue_screen.dart:686 path), so the fix is consistent across both. · **Needs Eric taste:** no

#### C-02 — P1 · Color
- **Screen/Flow:** ConversationTile (conversation_tile.dart)
- **Evidence (`code-verified`):** conversation_tile.dart uses glass tokens throughout: title color AppColors.glassTextPrimary #4A3548 (line 74), date/preview AppColors.glassTextHint #8B4557 (lines 80,104), delete icon glassTextHint (line 46), avatar text Colors.black87 on a yellow gradient (avatarHerStart #FFD54F→avatarHerEnd #FFC107). ListTile has no background of its own, so it inherits whatever surface the list provides.
- **Problem:** The tile is built entirely from glass-surface tokens (#4A3548 / #8B4557 — dark text meant for a near-white glass card). If this tile is ever placed directly on the dark GradientBackground or the flat #121212 Material background (rather than inside a GlassmorphicContainer), the name, timestamp, last-message preview and delete icon all collapse to near-invisible dark-on-dark. Grep shows the live conversation list uses PartnerConversationTile, not this widget — so ConversationTile is either dead code or used on a path not verified here; either way it is a latent contrast trap shipping in the binary.
- **User impact:** If reachable, users see an unreadable conversation list (the core navigation surface for analyze-chat history). If dead code, it is shipping confusion and a maintenance landmine that will be copy-pasted incorrectly.
- **Suggested fix:** Confirm whether ConversationTile is still routed anywhere. If dead, delete it. If live, wrap it in a GlassmorphicContainer (so the glass tokens are correct) OR re-token it to the flat dark system (textPrimary/textSecondary). Do not leave glass tokens floating with no guaranteed glass surface.
- **Effort:** <30min · **Risk if fixed:** Low if deleted (verify no route). Low if re-tokened. Confirm the partner-detail path genuinely uses PartnerConversationTile before deleting. · **Needs Eric taste:** no

#### C-03 — P1 · Consist · 🎨 **TASTE**
- **Screen/Flow:** Manual new-conversation (new_conversation_screen.dart) vs Screenshot recognition dialog (screenshot_recognition_dialog.dart)
- **Evidence (`code-verified`):** Two parallel 本次分析設定 blocks diverge. Manual (new_conversation_screen.dart:430-496) renders 認識情境/認識多久/目前目標 as GlassmorphicSegmentedButton with full GradientBackground/glass styling and a collapse header '這次分析設定（可不改）' + summary line. Screenshot dialog (screenshot_recognition_dialog.dart:1042-1192) renders the SAME three fields as bare ChoiceChips inside an AlertDialog on glassWhite, with no collapse and a different label '認識場景（選填）'. Field label even differs: manual says '認識情境', dialog says '認識場景'. Both then have an identical '補充背景（選填）' helper string (new_conversation_screen.dart:490 vs screenshot_recognition_dialog.dart:1186) confirming they are meant to be the same feature.
- **Problem:** Recent commits (d6ea851/9fec841 '收合本次分析設定') collapsed and polished the manual entry settings block, but the screenshot-path equivalent was not aligned: different widget family (segmented button vs chips), different collapse behaviour (manual collapses, dialog always expanded), and a label mismatch (情境 vs 場景). The stated cluster goal — manual and screenshot analyze should feel consistent — is not met for this block.
- **User impact:** A user who does both manual entry and screenshot import sees two visually and behaviourally different versions of 'the same' analysis-settings step, undermining the 'it remembers / coherent coach' positioning and making the product feel template-assembled.
- **Suggested fix:** Unify the field label to one term (pick 認識情境 or 認識場景 and use everywhere — '場景' reads slightly better). Consider extracting a shared SessionContextFields widget so both surfaces use identical controls and copy. At minimum align the label string now (cheap) and file the widget-unification as a follow-up.
- **Effort:** ~half-day for full widget unification; <30min for the label-string alignment · **Risk if fixed:** Medium. screenshot_recognition_dialog feeds analyze-chat sessionContext — changing which control sets meetingContext/duration/goal must preserve the exact enum values written. The label-only fix is low risk; the widget unification needs a regression pass on both create paths. · **Needs Eric taste:** yes

#### C-04 — P1 · RWD
- **Screen/Flow:** ScreenshotRecognitionDialog — message editor scroll area (screenshot_recognition_dialog.dart)
- **Evidence (`code-verified`):** The whole dialog is an AlertDialog with content in a SingleChildScrollView (line 629). Inside it, the per-message editor is a fixed-height Container (lines 967-972) whose height comes from _messageEditorHeight() = clamp(220, screenHeight*0.5) (lines 303-313), wrapping a ListView. So a scrollable ListView (min 220px) is nested inside a scrollable AlertDialog. On a small phone (e.g. 667pt height) with the keyboard open, the AlertDialog max height shrinks dramatically while the inner editor still demands ≥220px plus the name field, 4 settings blocks, guidance card and warning card above it.
- **Problem:** Nested vertical scroll (ListView inside SingleChildScrollView) with a hard 220px floor inside a keyboard-shrunk AlertDialog risks the inner editor and the action buttons ('確認加入對話') being pushed off-screen or the inner list stealing the drag from the outer scroll. When the user taps a message TextField to fix OCR text, the keyboard can occlude the field they are editing with no guaranteed scroll-to-focus inside the fixed box.
- **User impact:** On small phones, users correcting OCR text (the explicitly-encouraged 'always expand editor' flow, line 243) may not be able to reach the field they are typing in or the confirm button, blocking screenshot import — a core analyze-chat entry path.
- **Suggested fix:** Replace the AlertDialog with a full-height DraggableScrollableSheet / bottom sheet for this dense editor, or lower the inner floor and rely on a single outer scroll with scroll-to-focus. At minimum reduce the 220px clamp on short screens (use screenHeight*0.3 floor) and verify keyboard-open layout on a 4.7in device.
- **Effort:** ~half-day · **Risk if fixed:** Medium. This dialog returns the ScreenshotRecognitionDialogResult that drives import into analyze-chat; restructuring the container must not change _submit() / _sanitizedMessages() behaviour or the cancel ('稍後再加入') path. Keyboard behaviour is native-risk and must be device-tested. · **Needs Eric taste:** no

#### C-05 — P1 · Review · 🎨 **TASTE**
- **Screen/Flow:** AnalysisErrorWidget (analysis_error_widget.dart)
- **Evidence (`code-verified`):** AnalysisErrorWidget.fromCode(code,...) (lines 32-71) maps server codes to UI. UNSAFE_INPUT maps to a hard-blocking state: title '無法處理此內容' (line 169), message '偵測到不適當的內容，無法提供建議' (line 187), and _isRetryable returns false for UNSAFE_INPUT (lines 65-71) so NO retry button renders. The widget always paints in AppColors.error red (icon, title, border, button).
- **Problem:** Two issues. (1) Brand/copy: a dating-coach moderation refusal painted entirely in error-red with a blocking '無法處理此內容' reads as the tool judging the user — the opposite of snapshot.md's 'coach on the user's side' rule, and risks feeling punitive on borderline-flirty (but legitimate) content. (2) App Review / quota: I could not verify from this widget whether a format/unsafe failure still charges quota — CLAUDE.md says format failure must not charge quota. The widget has no quota-aware copy, so if the caller decrements quota on UNSAFE_INPUT the user is charged for a refusal.
- **User impact:** Users hitting the moderation path on legitimate dating content feel accused and get a dead-end (no retry, no guidance on what to change). If quota is also burned, that compounds into a trust-breaking moment right before a paywall decision.
- **Suggested fix:** Soften UNSAFE_INPUT copy to coach voice and give an actionable next step (e.g. '這段內容我先不分析。換一段你們最近的對話，我幫你看下一步。'). Use warning amber rather than full error-red for the moderation case to distinguish it from genuine failures. Separately verify (in analysis_screen caller) that UNSAFE_INPUT/format failures do NOT decrement quota.
- **Effort:** ~1h for copy/color; quota verification separate · **Risk if fixed:** Low for copy/color. The quota check is high-risk-zone (analyze-chat + quota) — verify, do not blind-edit; needs Codex review evidence per CLAUDE.md before claiming safe. · **Needs Eric taste:** yes

#### C-06 — P2 · Slop · 🎨 **TASTE**
- **Screen/Flow:** FullAnalysisRetryCard (streaming_analysis_loading_widgets.dart) within analysis_screen
- **Evidence (`code-verified`):** FullAnalysisRetryCard (lines 233-257) is a heavy gradient card: LinearGradient [backgroundGradientMid #2D1B4E, #351A52, #4A245C], 18px radius, bokehCoral-tinted rounded icon chip, primaryDark boxShadow blur 24 offset (0,12), pill FilledButton. This is the warm/glass theme's purple-gradient + bokeh + glow vocabulary — exactly the AI-slop aversions Eric named (purple gradients, glow, decorative chip). Meanwhile its sibling in the same flow, AnalysisErrorWidget, is a flat error-red card, and StreamingAnalysisLoader uses plain flat-theme text.
- **Problem:** Within one analyze-chat result view, the error/retry surfaces mix three idioms: a glossy purple-gradient+bokeh+shadow retry card, a flat red error card, and flat Material loader text. The retry card leans hardest into the named AI-slop tokens, and its visual weight (glow + gradient) overstates a routine 'try again' moment.
- **User impact:** Users perceive an inconsistent, template-y assembled UI at the emotionally-sensitive 'analysis failed' moment; the heavy gradient/glow can read as generic engineering-flashy rather than a calm coach.
- **Suggested fix:** Eric to decide the house style for failure cards. If keeping the warm theme, calm the retry card (drop the boxShadow glow and the bokeh icon chip, flatten the gradient) and bring AnalysisErrorWidget into the same family so error and retry feel like one system. Pick ONE idiom for transient-failure surfaces.
- **Effort:** ~1h · **Risk if fixed:** Low (pure styling). Keep retry button enable/disable logic and kRetryExhaustedMessage swap intact. · **Needs Eric taste:** yes

#### C-07 — P2 · Consist · 🎨 **TASTE**
- **Screen/Flow:** FullAnalysisPlaceholder / StreamingAnalysisLoader (streaming_analysis_loading_widgets.dart)
- **Evidence (`code-verified`):** StreamingAnalysisLoader uses Theme.of(context).textTheme.bodyLarge/bodySmall (lines 105,112) and FullAnalysisPlaceholder._SkeletonBlock uses theme.colorScheme.surfaceContainerHighest and theme.textTheme.bodyMedium (lines 198,203) — i.e. the FLAT dark Material ThemeData. But these render inside analysis_screen which is wrapped in GradientBackground (warm purple gradient, confirmed analysis_screen.dart:4805 GradientBackground>Scaffold). So flat-theme surfaces (#2D2D2D-derived surfaceContainerHighest skeleton blocks, B3B3B3-ish secondary text) are painted over the warm gradient.
- **Problem:** The two coexisting color systems are mixed within the same screen: warm GradientBackground host + flat-Material loading/skeleton children. The skeleton blocks' grey surface and the loader's secondary text are tuned for #121212/#1E1E1E, not the purple gradient, so they look slightly off-tone (grey haze on purple) rather than intentional.
- **User impact:** Subtle but pervasive: during the most-watched moment (waiting for analysis), the skeletons read as a foreign grey panel on the purple screen, eroding the polished, intentional feel.
- **Suggested fix:** Decide the loading surface's allegiance. Either give the loader/placeholder explicit warm-theme tokens (glass surface or onBackground text) to match the host, or confirm the grey-on-purple is acceptable. Avoid relying on Theme.of(context) inside a screen that overrides the background.
- **Effort:** ~1h · **Risk if fixed:** Low. Visual only; FullAnalysisPlaceholder is noted as legacy/rollback-test retained, so verify rollback tests still pass if you re-token it. · **Needs Eric taste:** yes

#### C-08 — P2 · Color
- **Screen/Flow:** ScreenshotRecognitionDialog editable message card (screenshot_recognition_dialog.dart)
- **Evidence (`code-verified`):** In _buildEditableMessageCard the card background is hardcoded const Color(0xFFF0EAF5) (line 415, pale lilac). Inside it, the batch-action helper box uses Colors.white@0.08 fill with text in AppColors.glassTextPrimary #4A3548 (lines 482-497) and a secondary line in AppColors.unselectedText #5D4E6B (line 518). The quoted-reply and main TextFields use fillColor Colors.white@0.35–0.5 (lines 568,596) on the same pale lilac, with hintText unselectedText #5D4E6B (lines 566,594).
- **Problem:** Two concerns. (1) A hardcoded hex (0xFFF0EAF5) bypasses the design system entirely — a magic color with an inline comment, not a token. (2) unselectedText #5D4E6B as hint/secondary text on the pale-lilac/translucent-white card is a muted purple-grey on a light background; it is borderline for the 4.5:1 AA body threshold (estimated ~4–4.5:1) and the hint text especially may fail. Contrast here is native-risk because the translucent white fill composites against the lilac.
- **User impact:** Users editing OCR results (the encouraged path) may find hint text and the secondary batch-action guidance faint, slowing the verify-and-correct step that protects analysis quality.
- **Suggested fix:** Replace 0xFFF0EAF5 with a named token (or surfaceVariant of the glass system). Bump hint/secondary text to glassTextSecondary #6C5A6B at minimum, and verify the composited contrast on-device. Make the magic color a constant either way.
- **Effort:** <30min · **Risk if fixed:** Low. Color/token only; no change to message data flow. · **Needs Eric taste:** no

#### C-09 — Polish · Copy
- **Screen/Flow:** ScreenshotAddedFeedbackCard (screenshot_added_feedback_card.dart)
- **Evidence (`code-verified`):** _nextStep getter (lines 39-44): the lastMessageIsFromMe==false branch returns '最後一則是她說。按「分析新增內容」後，會開始串流整理下一步與完整分析。' The word '串流' (streaming) is an engineering term leaking to the user, against snapshot.md's product-language rule (no engineering vocabulary). The same card otherwise uses warm coach voice ('我會用最新來回分析下一步').
- **Problem:** '串流' is implementation vocabulary. Users do not need to know the response is streamed; it adds nothing and breaks the coach persona.
- **User impact:** Minor immersion break; reads as the dev talking rather than the coach. Cumulative with other leaks it cheapens the brand voice.
- **Suggested fix:** Drop '串流': e.g. '最後一則是她說。按「分析新增內容」，我就開始幫你整理下一步與完整分析。' Grep the cluster for other '串流' user-facing strings while here.
- **Effort:** <30min · **Risk if fixed:** Very low. Pure copy. Note copy_sweep_snapshot_test may snapshot strings — update the snapshot if it covers this card. · **Needs Eric taste:** no

#### C-10 — Polish · Copy · 🎨 **TASTE**
- **Screen/Flow:** ScreenshotAddedFeedbackCard + ScreenshotRecognitionDialog speaker chips
- **Evidence (`code-verified`):** Gendered '她說' / '她' is hardcoded throughout: screenshot_added_feedback_card.dart:29 ('她說'), screenshot_recognition_dialog.dart:454 ('她說')/541('引用對方'), new_conversation_screen.dart BubbleAvatar label '她' (line 547) and hints '她說了什麼...' (line 555). The app targets dating coaching broadly but the entire analyze input cluster assumes the counterpart is female.
- **Problem:** Hardcoded '她' assumes a female counterpart and male user across every analyze-input surface. This is a product-positioning/inclusivity decision baked into UI strings, and could surface in App Review or alienate non-hetero users.
- **User impact:** Users pursuing a male/non-binary counterpart see mismatched pronouns on every message they enter — a persistent small friction and a brand-inclusivity signal.
- **Suggested fix:** Eric to decide scope. Minimum: a neutral '對方' for the counterpart instead of '她' in chips/avatars/hints; or a per-conversation counterpart-gender setting. Not necessarily a launch blocker but a deliberate call, not an accident.
- **Effort:** ~half-day if going neutral across the cluster · **Risk if fixed:** Low technically; copy_sweep snapshot test will need updating. Real risk is product-positioning, hence Eric's call. · **Needs Eric taste:** yes

### Cluster D — Analyze result cards & charts (9)

> _Reviewer notes:_ Could NOT verify on-device: live web-preview capture was unavailable (no browser deps, no test creds), so no screenshots. All contrast figures are computed WCAG ratios from the hex tokens in lib/core/theme/app_colors.dart (sRGB formula) and are code-verified; actual perceived contrast over the warm gradient background (for message_bubble's white@0.7 bubbles) is native-risk and not separately reported. Notably the brief's listed contrast suspects glassTextHint #8B4557 (6.06:1) and glassTextSecondary #6C5A6B (5.65:1) on glass #F5F0F8 PASS AA — the real, severe failures are the enthusiasm-scale type tokens and ctaStart coral used as text on the light glass card (D-01, D-02), which I verified numerically (1.97–2.66:1). textSecondary #B3B3B3 on surface #1E1E1E = 7.95:1, passes. Scroll/keyboard/snap feel for the reply_style_card carousel (D-05) and radar legibility at 200px height on small screens are native-risk — flagged but not asserted. message_bubble was reviewed; its maxWidth uses MediaQuery (good) and it has no clipping/SafeArea issue worth a finding. analysis_preview_dialog copy is strong and quota-safe ('只有送出完整分析才會扣次數') — paywallQuota graded B on its strength; no engineering-vocab leak found in the dialog. consistency graded D and colorContrast D are the load-bearing scores. motionLoading graded D because zero loading/empty/error states exist in any of the 10 widgets (D-07).

#### D-01 — P1 · Color
- **Screen/Flow:** reply_style_card.dart (type label header) + reply_card.dart (_label)
- **Evidence (`code-verified`):** reply_style_card.dart:41-56 _colorForType returns AppColors.cold/warm/veryHot/hot/primaryLight; line 97-102 renders the category label (延展/共鳴/調情/幽默/冷讀) in that color at AppTypography.titleMedium ON a GlassmorphicContainer whose bg is AppColors.glassWhite #F5F0F8 (glassmorphic_container.dart:35). reply_card.dart:38-51,86-92 does the same with _color over glassWhite. Computed WCAG: cold 1.97:1, warm 1.98:1, veryHot 2.38:1, hot 2.66:1, primaryLight 2.47:1 — ALL fail AA large-text 3:1.
- **Problem:** Every reply-style category header across the core 字卡 experience uses the enthusiasm-scale tokens (designed for dark backgrounds) on a light glass card, so all five label colors fail WCAG large-text contrast. The labels — the primary way a user tells 調情 from 共鳴 — are the least legible text on the card.
- **User impact:** Users on bright screens / outdoors can't reliably read which reply strategy each card is, undermining the whole point of offering 5 styles. Affects every analyze and opener result.
- **Suggested fix:** Either darken each type color to a glass-safe variant (e.g. add a glassOn* set hitting >=4.5:1 on #F5F0F8), or render the label inside a tinted pill (color.withAlpha as bg + a dark-enough text) the way reply_card already does for its pill at line 82-92 but with a darker foreground. Keep the bright token only as the pill background, not the text.
- **Effort:** ~1h · **Risk if fixed:** Low — pure presentation. No quota/analyze logic touched. Verify against snapshot tests that assert label color. · **Needs Eric taste:** no

#### D-02 — P1 · Color
- **Screen/Flow:** All warm-glass cards: score_hero_card, dimension_radar_chart, game_stage_indicator, reply_style_card (accent/label text)
- **Evidence (`code-verified`):** ctaStart #FF7043 on glassWhite #F5F0F8 = 2.44:1 (fails AA). Used as small-text foreground at: score_hero_card.dart:78-81 ('對話健康分數'), dimension_radar_chart fill/border (decorative, ok) but game_stage_indicator.dart:63-69 badge text '目前・X', reply_style_card.dart:116-119 & 166-170 ('接法'/'為什麼推薦' labels at AppTypography.caption).
- **Problem:** The coral CTA token is reused as a small-caption accent on the light glass surface where it only reaches 2.44:1, below AA body (4.5) and even below large (3). These are section labels users scan to orient inside each result card.
- **User impact:** Section labels look like faint orange ghost text; low-vision and bright-light users lose the scannable structure of the result.
- **Suggested fix:** Use a darker coral (e.g. #C2410C-ish) for text-on-glass, reserve #FF7043 for fills/gradients/borders only. Add a dedicated ctaTextOnGlass token.
- **Effort:** <30min · **Risk if fixed:** Low — presentation only. · **Needs Eric taste:** no

#### D-03 — P1 · Consist · 🎨 **TASTE**
- **Screen/Flow:** Whole analyze result stack (final_recommendation_card + psychology_card vs score_hero_card/radar/gauge/stage/reply_style_card)
- **Evidence (`code-verified`):** final_recommendation_card.dart:18-29 uses FLAT-DARK system: AppColors.primary purple gradient, AppColors.surface #1E1E1E inner box, white text. psychology_card.dart:18 uses AppColors.surfaceVariant #2D2D2D dark grey. But score_hero_card.dart:23, dimension_radar_chart.dart:31, enthusiasm_gauge.dart:19, game_stage_indicator.dart:38, reply_style_card.dart:90 all use the WARM glass system (glassWhite #F5F0F8 + coral). Same scroll view mixes purple-on-dark and coral-on-light cards.
- **Problem:** The two coexisting color systems are not split by screen — they are stacked within a single analyze result. The hero score and dimension charts are light warm-glass coral; the FINAL RECOMMENDATION (the most important card) and psychology card are dark purple/grey. Visually they look like two different apps glued together.
- **User impact:** Result feels unpolished/templated; the brand's warm coach identity is broken precisely on the recommendation card that should feel most like 'your coach'. App Review reviewers and dogfooders read this as inconsistent.
- **Suggested fix:** Pick ONE system for the analyze result. Given brand = warm coach, migrate final_recommendation_card and psychology_card to GlassmorphicContainer + warm tokens (or vice versa). Decide once, apply across the cluster.
- **Effort:** ~half-day · **Risk if fixed:** Medium — touches the copy-to-clipboard CTA styling in final_recommendation_card; re-verify the copy button still legible and snapshot tests updated. No quota/analyze logic. · **Needs Eric taste:** yes

#### D-04 — P2 · First · 🎨 **TASTE**
- **Screen/Flow:** psychology_card.dart + final_recommendation_card.dart (emotional tone)
- **Evidence (`code-verified`):** psychology_card.dart:18 BoxDecoration color: AppColors.surfaceVariant (#2D2D2D flat grey), no gradient/warmth, body text default white. final_recommendation_card.dart leans on emoji ⭐📝🧠 (lines 36,77,86) over a flat purple tint for warmth.
- **Problem:** The brief's 'cards too black/white & emotionless' worry is real for psychology_card: it is a literal flat #2D2D2D rectangle with monochrome text and no warmth or hierarchy beyond a 🧠 emoji. The coach's most human insight ('她話裡的意思') is delivered in the coldest-looking card.
- **User impact:** The empathetic/insightful moments read as a debug panel rather than a coach talking to the user — works against '教練在你這邊' product language.
- **Suggested fix:** Give psychology_card the same warm treatment as the other cards (subtle tinted surface, a soft accent stripe, sectioned subtext), drop reliance on bare emoji for warmth.
- **Effort:** ~1h · **Risk if fixed:** Low — presentation only. · **Needs Eric taste:** yes

#### D-05 — P2 · RWD
- **Screen/Flow:** reply_style_card.dart (horizontal carousel card)
- **Evidence (`code-verified`):** reply_style_card.dart:88 Container(width: 312) hardcoded, plus margin right:12 (line 89), with an Expanded+SingleChildScrollView inside (line 108-160). No MediaQuery-based sizing.
- **Problem:** Each reply-style card is a fixed 312pt wide. On a 320pt-logical small phone (iPhone SE) the card is 312 + 12 margin = 324 > viewport, so peeking/snapping is off and content nearly fills the screen edge-to-edge; on tablet the cards stay tiny and waste space. The Expanded inside a horizontally-scrolling card also depends on the parent giving bounded height.
- **User impact:** Small-phone users (a meaningful TestFlight slice) get cards that touch the screen edge with no peek affordance; the carousel feels cramped. Tablet users see undersized cards.
- **Suggested fix:** Derive width from MediaQuery (e.g. min(312, screenWidth*0.82)) so a consistent peek shows on all sizes; cap on tablet.
- **Effort:** <30min · **Risk if fixed:** Low — verify the parent ListView still lays out; native-risk on actual scroll snap feel. · **Needs Eric taste:** no

#### D-06 — P2 · Layout · 🎨 **TASTE**
- **Screen/Flow:** reply_style_card.dart inner message rows
- **Evidence (`code-verified`):** reply_style_card.dart:259-268 _ReplyOptionMessageRow draws each suggested message in a box with color AppColors.surface.withValues(alpha:0.72) (#1E1E1E dark) and white textPrimary (line 285-290), nested inside the light GlassmorphicContainer (#F5F0F8).
- **Problem:** Dark message chips sit inside a light glass card — a card-in-card with inverted polarity. Internally the dark-box white-text contrast is fine, but the polarity flip between the card body (light) and its message chips (dark) is visually noisy and reinforces the mixed-system problem at the component level.
- **User impact:** The actual reply suggestions (the thing users copy) look pasted in from a different surface; reduces perceived quality of the core deliverable.
- **Suggested fix:** Make message chips a light tinted surface consistent with the glass card (e.g. white with low alpha + glassTextPrimary), matching message_bubble's incoming-bubble treatment.
- **Effort:** <30min · **Risk if fixed:** Low — presentation only; keep the tap-to-copy InkWell intact. · **Needs Eric taste:** yes

#### D-07 — P2 · Motion
- **Screen/Flow:** All result cards (loading/empty/error states)
- **Evidence (`code-verified`):** None of the 10 cluster widgets contain a loading skeleton, empty branch, or error branch — they unconditionally render from non-null entities (e.g. final_recommendation_card requires FinalRecommendation; dimension_radar_chart indexes titles[index] at line 99 assuming exactly 5; reply_style_card falls back to a single 'building 訊息' segment but has no error visual). score_hero_card/enthusiasm_gauge assume a valid 0-100 score.
- **Problem:** The cards are pure presentation with no defensive state. If analyze returns partial/malformed schema (a known high-risk zone), these widgets either render empty boxes or risk RangeError (radar titles[index]). There is no styled 'something went wrong, you weren't charged' state at the card level.
- **User impact:** On a format failure the user could see blank/half cards rather than a plain reassuring message — violates the 'errors must be plain, actionable, reassuring' and 'never show malformed schema' rules.
- **Suggested fix:** Add a shared graceful fallback (partial-data placeholder + guard radar to default missing dimensions to 0) and ensure the parent screen shows a styled error card on schema failure. Confirm format failure path does not charge quota.
- **Effort:** ~half-day · **Risk if fixed:** Medium — the error/empty wiring touches the analyze result pipeline; verify no quota charged on the failure branch and Codex-review since analyze-chat is a high-risk zone. · **Needs Eric taste:** no

#### D-08 — Polish · Slop · 🎨 **TASTE**
- **Screen/Flow:** final_recommendation_card.dart
- **Evidence (`code-verified`):** final_recommendation_card.dart:19-28 purple LinearGradient bg + border; decorative emoji ⭐ (line 36), 📝 (line 77), 🧠 (line 87) as section icons.
- **Problem:** This card leans on exactly the brand's stated AI-slop aversions: a purple gradient panel plus a row of decorative emoji icons. It reads as the 'generic AI result card' template.
- **User impact:** Eric's stated taste: purple gradients + decorative emoji feel template/engineering. The single most important card is the most slop-leaning one.
- **Suggested fix:** Drop the purple gradient for a warm-glass treatment (ties to D-03), replace emoji with restrained typographic labels or a single meaningful accent.
- **Effort:** ~1h · **Risk if fixed:** Low — presentation; keep the copy CTA logic. · **Needs Eric taste:** yes

#### D-09 — Polish · Copy · 🎨 **TASTE**
- **Screen/Flow:** enthusiasm_gauge.dart:31 + game_stage_indicator labels
- **Evidence (`code-verified`):** enthusiasm_gauge.dart:30-33 renders '$score/100' as a prominent headline. game_stage_indicator.dart:19-32 stage labels 破冰/升溫/深入/連結/邀約 with numbered circles 1-5 (line 164-171).
- **Problem:** '$score/100' and the numbered 5-stage funnel read slightly game-y/metric-forward rather than coach-voiced. score_hero_card already softens this with a sentence ('對話偏冷，需要換個方式'); the bare gauge does not. Minor tension with 'coach on your side, not a tool scoring you'.
- **User impact:** Low — a user may feel measured/graded rather than coached when the raw 'X/100' dominates without a supportive sentence.
- **Suggested fix:** Pair the gauge number with a short coach line like score_hero_card does, or prefer score_hero_card over the bare enthusiasm_gauge in the result.
- **Effort:** <30min · **Risk if fixed:** Low. · **Needs Eric taste:** yes

### Cluster E — Coach 1:1 & follow-up (6)

> _Reviewer notes:_ Could NOT screenshot: sandbox has no browser deps and no test creds, so all on-device rendering (actual contrast under the real gradient, keyboard overlap on the bottom-sheet input, scroll feel, streaming latency) is marked native-risk, not verified.

Host discovery: CoachChatCard is rendered ONLY in analysis_screen.dart:5649, gated on a completed analysis (_enthusiasmScore && _gameStage && _finalRecommendation). CoachFollowUp* widgets render on the partner-detail screen (per the C24 header comment) on a dark backdrop (#070812→#0B0A14). This split is the root of the color-system mixing in E-01.

Color-system verdict: CoachChatCard, CoachFollowUpResultCard, CoachActionCard all sit on the WARM glass surface (GlassmorphicContainer = solid glassWhite #F5F0F8, glassmorphic_container.dart:35) — NOT the flat-dark ThemeData. CoachFollowUpSection's own chips/buttons fall back to flat-dark ThemeData. So the cluster leans warm-glass but with two accent colors (purple in chat, orange in cards) plus flat-dark controls — that mix drove E-05.

Verified contrast (WCAG, computed in-session): glassTextSecondary #6C5A6B on glassWhite = 5.65 PASS (so it's fine inside cards) but on the dark partner backdrop = 3.10 FAIL (E-01). ctaStart #FF7043 on glassWhite = 2.44 FAIL large-text (E-02). glassTextHint #8B4557 on glassWhite = 6.06 PASS. glassTextPrimary #4A3548 on glassWhite = 9.87 PASS. The known-suspect textSecondary #B3B3B3 on #1E1E1E does not apply here (this cluster doesn't use the flat-dark surface for body text).

Strengths worth noting (not filed as findings): copywriting is excellent and on-brand — failure/quota copy explicitly reassures '未扣額度' and 'Format failure must not charge quota' is honored in the UI labels (failureMessageFor lines 66-72, _CostStatusChip lines 1398-1405); no engineering vocab leaks to users (quota shown as '額度/則', no token/JSON/schema). paywallQuota handling is mature: free clarify vs paid advice is clearly separated, force-answer has an explicit confirm dialog (lines 964-987). appReviewRisk is low — no raw JSON, errors are plain and actionable. These drove the A grades for copywriting/paywallQuota.

aiSlop graded C (needsEricTaste): the cluster sits squarely on the warm glass + purple/orange gradient tokens Eric dislikes (GlassmorphicContainer, ctaStart gradient, primary purple), and uses several decorative icons (auto_awesome, auto_stories, psychology_alt). This is the named-token irony flagged in the brief, not an objective defect — left as taste tension inside E-02/E-05 rather than a separate slop finding.

#### E-01 — P1 · Color
- **Screen/Flow:** CoachFollowUpSection (_buildDefault caption + _buildWithResult line 408) and CoachFollowUpChipRow (hint + 額度 caption)
- **Evidence (`code-verified`):** coach_follow_up_section.dart:407 uses AppColors.glassTextSecondary (#6C5A6B) for the 'ⓘ 重新生成會再扣 1 則額度' caption; coach_follow_up_chip_row.dart:70 and :78 use glassTextSecondary for the 💡 hint line and '生成會使用 1 則額度'. These widgets render on the partner-detail dark backdrop (#070812→#0B0A14), NOT inside a glass surface. Header text in the same section correctly uses onBackgroundSecondary (#E0D0E8). Measured WCAG: #6C5A6B on #070812 = 3.10:1, on #0B0A14 = 3.10:1 — fails AA 4.5:1 body.
- **Problem:** The follow-up section mixes both color systems on one screen: white/light-violet on-dark tokens for the header, but dark warm 'glass' text tokens for the captions/hints. The dark warm tokens were authored for the light glass surface (#F5F0F8) where they pass; on the dark backdrop they fail contrast and look muddy.
- **User impact:** Every partner-detail visitor sees the quota cost line and the AI lifecycle hint as low-legibility dark-grey-violet on near-black. The two pieces of copy most tied to spending money (quota) and to the coach's 'it remembers' value prop (the hint) are the hardest to read.
- **Suggested fix:** Swap glassTextSecondary → onBackgroundSecondary (#E0D0E8, measured 13.6:1) for these three on-dark captions/hints. No layout change.
- **Effort:** <30min · **Risk if fixed:** Cosmetic only; touches no quota logic. Verify the hint line still reads as secondary against the header. · **Needs Eric taste:** no

#### E-02 — P1 · Color · 🎨 **TASTE**
- **Screen/Flow:** CoachFollowUpResultCard (phase label, '可以這樣說' label) and CoachActionCard ('本回合怎麼接', '試試這樣回', '看 3 分鐘教學')
- **Evidence (`code-verified`):** coach_follow_up_result_card.dart:46, :90 and coach_action_card.dart:30,:83,:109,:117 set caption/label text to AppColors.ctaStart (#FF7043) inside a GlassmorphicContainer whose surface is glassWhite (#F5F0F8, per glassmorphic_container.dart:35). Measured WCAG: #FF7043 on #F5F0F8 = 2.44:1 — fails even the 3:1 large-text floor, and these are small caption-size labels needing 4.5:1.
- **Problem:** Orange CTA color is used as a text accent on a near-white surface. The orange-on-cream pairing is a known low-contrast combination; here it labels the result card's section headers and the 'try this line' callout.
- **User impact:** Users reading the coach's action/result card see the orienting labels ('可以這樣說', phase, '本回合怎麼接') as washed-out orange that's hard to scan, especially in sunlight or for low-vision users. It weakens the card's at-a-glance hierarchy — the exact moment the coach is delivering its advice.
- **Suggested fix:** Use ctaEnd (#FF5722) which is darker, or better AppColors.primaryDark / a dedicated accessible accent for text labels; reserve the FF7043→FF5722 gradient for fills/buttons only. Confirm the chosen color hits ≥4.5:1 on #F5F0F8.
- **Effort:** ~1h · **Risk if fixed:** Pure color token swap across two shared cards; CoachActionCard is reused by analyze-chat, so visually QA both Coach result and analysis recommendation surfaces. · **Needs Eric taste:** yes

#### E-03 — P2 · Motion · 🎨 **TASTE**
- **Screen/Flow:** CoachChatCard — streaming / thinking state (_CoachThinkingNotice) and submit button spinner
- **Evidence (`native-risk`):** coach_chat_card.dart:294-299 and :1245-1249 use a bare CircularProgressIndicator for 'in-flight'. The whole answer arrives atomically via state.isLoading → _CoachChatResultView; there is no token streaming or skeleton of the answer fields. _CoachThinkingNotice shows a fixed line '教練正在接這句' + the echoed question.
- **Problem:** The core product is a 'coach chatting with you', but the loading model is request/response with a spinner, not a streamed/typing feel. The analysis screen above it DOES stream (StreamingAnalysisLoader at analysis_screen.dart:5665), so the coach turn feels comparatively sterile and slow — a spinner with no progressive reveal. Actual perceived latency depends on Sonnet response time on-device (cannot observe here).
- **User impact:** On a slow turn the user stares at a spinner with no sense of progress; the coach feels like a form submit rather than someone responding. Higher abandonment / re-tap risk mid-generation.
- **Suggested fix:** Either stream the answer text token-by-token like analyze-chat, or add a lightweight typing/ellipsis animation and a skeleton of the labelled rows so the card feels alive. Keep the reassuring copy.
- **Effort:** ~half-day · **Risk if fixed:** Streaming touches the coach-chat API/result plumbing (high-risk zone per CLAUDE.md); a skeleton-only change is low risk. Do not let a partial stream charge quota on format failure. · **Needs Eric taste:** yes

#### E-04 — P2 · Layout · 🎨 **TASTE**
- **Screen/Flow:** CoachChatCard result + history (dense Column on small screens)
- **Evidence (`code-verified`):** _CoachChatResultView (coach_chat_card.dart:746-908) stacks, in one card, up to ~10 labelled rows: headline, cost chip, answer, 我理解你的真實想法, 這輪卡點, 你現在卡在, 這次先做, 教練判斷, suggestedLine bubble, 邊界提醒, 教練追問, two action buttons, and a full _CoachOutcomeCaptureCard with 5 ChoiceChips + two help captions. All inside a glass card inside a scrolling analysis screen, with no truncation/collapse on the latest turn.
- **Problem:** Message density is very high for one coach answer. On a small phone the 'one clear next move' moat is buried under ~7 metadata _InfoLine rows plus an outcome-capture block the user must scroll past every turn. The signal (next step + suggested line) competes with diagnostic labels.
- **User impact:** Small-screen users scroll a long wall of labelled rows to find the actionable line; the convergence-to-a-better-next-move promise is visually diluted by analysis metadata on every single turn.
- **Suggested fix:** Lead with headline + 這次先做 + suggested line; collapse the diagnostic rows (卡點/卡在/真實想法/教練判斷) behind a '看教練怎麼判讀' expander like the history tiles already do; consider deferring the outcome-capture card until after the user acts.
- **Effort:** ~half-day · **Risk if fixed:** Layout reshuffle of the core coach card; no quota/logic impact but high visibility — needs taste sign-off and regression of existing widget tests. · **Needs Eric taste:** yes

#### E-05 — P2 · Consist · 🎨 **TASTE**
- **Screen/Flow:** CoachFollowUp cluster vs CoachChat cluster — visual system split
- **Evidence (`code-verified`):** CoachChatCard (coach_chat_card.dart:169) wraps everything in GlassmorphicContainer (warm light glass) and uses AppColors.primary (#6B4EE6 purple) for icon tint, send button, chips, accent borders, and outcome ChoiceChip selectedColor (lines 179,302,749,1130). CoachFollowUpResultCard (coach_follow_up_result_card.dart:48,89) and CoachActionCard use the SAME glass surface but accent with ctaStart ORANGE (#FF7043). CoachFollowUpSection's chips/buttons are bare Material ChoiceChip/OutlinedButton themed by ThemeData (flat-dark primary purple). So within 'Coach', the chat surface is purple-accented glass, the follow-up result card is orange-accented glass, and the follow-up controls are flat-dark Material.
- **Problem:** Three different accent/surface treatments inside one product (Coach 1:1 + follow-up). The header comment in coach_follow_up_result_card.dart even says it 'mirrors CoachActionCard for cross-coach consistency' — but CoachChatCard uses purple, not orange, so the two coach surfaces are NOT consistent.
- **User impact:** The coach product feels assembled from different design eras: purple here, orange there, flat Material chips in between. Undermines the 'one coach on your side' brand cohesion and reads as engineering-template-y.
- **Suggested fix:** Pick one coach accent (purple primary or warm orange) and apply it across CoachChatCard, CoachActionCard, and CoachFollowUpResultCard; align the follow-up section chips/buttons to the same theme rather than raw ThemeData defaults.
- **Effort:** ~half-day · **Risk if fixed:** Token-level but spans shared CoachActionCard used by analyze-chat; QA all three host screens. Pure visual, no quota risk. · **Needs Eric taste:** yes

#### E-06 — Polish · First · 🎨 **TASTE**
- **Screen/Flow:** CoachChatCard — Coach 1:1 entry has no empty/zero-state guidance; gated behind full analysis
- **Evidence (`code-verified`):** analysis_screen.dart:5644-5661 only renders CoachChatCard when _enthusiasmScore != null && _gameStage != null && _finalRecommendation != null. With no timeline (history empty, no current result), CoachChatCard build path renders header + memory strip + 5 suggestion chips + text field and nothing below (timeline.isEmpty, not loading, not error → no thread view). The first-run state is just an input with chips — no example of what a coach answer looks like.
- **Problem:** Coach 1:1, the core product, is only reachable after a successful full analysis, and its first-paint empty state gives no preview of the payoff. There is no illustrative example or 'try asking…' result, so the value of the moat (remembers + converges) isn't shown until the user spends an interaction.
- **User impact:** New users who reach the coach see a bare question box and may not understand they're talking to a coach that remembers context; the suggestion chips help but the payoff is invisible until first ask.
- **Suggested fix:** Add a one-line empty-state framing under the chips ('問完，教練會給你下一步＋可直接送出的一句話'), or a collapsed sample answer; consider whether the coach should be reachable without a complete analysis.
- **Effort:** ~1h · **Risk if fixed:** Adding copy is safe. Loosening the gating condition touches analysis flow and could surface the coach before snapshot data exists — verify _buildCoachChatAnalysisSnapshot handles partial state. · **Needs Eric taste:** yes

### Cluster F — Partner (8)

> _Reviewer notes:_ Could NOT capture live screenshots — sandbox has no browser deps and no test credentials, so all rendering/contrast claims are either code-verified from Dart sources + token hex values, or marked native-risk where on-device rendering matters (GlassmorphicTextField internals in F-03, keyboard overlap on the dialogs/AddPartner form which I could not observe). I verified contrast math from app_colors.dart hex values: glassTextHint #8B4557 on glassWhite #F5F0F8 ~6.5:1 and glassTextSecondary #6C5A6B on glassWhite ~5.8:1 — both PASS AA body, so the 'known suspects' on glass surfaces are actually fine; the real consistency problem is the two-color-system mixing (F-01), not raw contrast. The unselectedText/#2D1B4E suspect pair does not occur in this cluster (unselectedText is used only as a dialog cancel-button foreground on glassWhite in partner_list_screen.dart:247, where it passes). SafeArea is present on detail + add + merge screens; AddPartner correctly adds kToolbarHeight inset. The 56px hero number, the deep maxLines on note dialogs (maxLines 5-7 with maxLength) and the Wrap-based tag layouts looked overflow-safe in source. The main launch-relevant items are F-01 (system mixing), F-02 (AI-slop taste), and F-04 (no busy state on irreversible merge/delete).

#### F-01 — P1 · Consist · 🎨 **TASTE**
- **Screen/Flow:** PartnerListScreen delete dialogs (_showInformationalDialog / _showConfirmDialog) + SameNameDedupeBanner + PartnerDataQualityBanner
- **Evidence (`code-verified`):** partner_list_screen.dart:202-256 dialogs use backgroundColor: AppColors.glassWhite (#F5F0F8 light) with AppColors.glassTextPrimary/unselectedText; same_name_dedupe_banner.dart:34 & partner_data_quality_banner.dart:46 use glassWhite surface. Meanwhile the host screens (partner_detail_screen.dart, partner_heat_hero_card.dart, partner_traits_card.dart, _PartnerDetailSection) are built entirely on the flat-dark on-dark system (Colors.white.withValues + onBackgroundPrimary #FFFFFF / onBackgroundSecondary #E0D0E8 on the #070812 navy backdrop).
- **Problem:** The cluster mixes BOTH color systems. The list/detail surfaces are dark-glass-on-navy, but every dialog and both banners flip to the light warm-glass theme (#F5F0F8 cards with maroon/purple text). A delete confirm popping up as a bright white card over the deep-navy detail page is a jarring tonal break.
- **User impact:** Users feel the app was assembled from two different design kits; the white dialogs over a dark page read as a borrowed/system component, undercutting the premium coach feel right at the destructive-action moment.
- **Suggested fix:** Pick one allegiance for the Partner cluster. Either restyle the two banners + 3 dialogs to the dark-glass tokens used by _PartnerDetailSection (white@8% surface, onBackground* text), or accept light dialogs everywhere. Do not straddle both within one flow.
- **Effort:** ~half-day · **Risk if fixed:** Pure visual; banner widgets have snapshot tests (same_name_dedupe_banner_test, partner_data_quality_banner_test enforce a no-red lexicon) that will need regolding. No quota/auth/data risk. · **Needs Eric taste:** yes

#### F-02 — P1 · Slop · 🎨 **TASTE**
- **Screen/Flow:** AddPartnerScreen + PartnerDetailScreen background
- **Evidence (`code-verified`):** add_partner_screen.dart:202-280 renders backgroundGradient #1A0533->#2D1B4E->#4A2C6A plus 3 _StaticBubble blur-60/spread-25 halos in primaryLight (purple) / ctaStart (orange) / bokehPink. partner_detail_screen.dart:923-1006 renders the navy gradient + 3 _GlowBubble blur-80/spread-30 halos (primaryLight purple, ctaStart, bokehPink). partner_heat_hero_card.dart:115-156 adds a decorative two-layer RadialGradient _HeatOrb bound to no data.
- **Problem:** These screens lean directly into Eric's stated AI-slop aversions: purple gradient backgrounds, bokeh blobs, and a purely decorative orb with no data binding. The _HeatOrb in particular is a meaningless decorative element sitting next to the one number that matters.
- **User impact:** Risks the exact 'generic/template/AI-generated' feel Eric wants to avoid; the bokeh halos add nothing to comprehension and the orb competes with the heat score for attention.
- **Suggested fix:** This is a taste call, not an objective bug. Recommend dialing the bubble opacities down hard (AddPartner uses 0.55/0.5/0.4 — quite strong) and reconsidering whether the _HeatOrb earns its space or should encode heat (e.g. orb tint follows enthusiasm scale).
- **Effort:** ~1h · **Risk if fixed:** Visual only; bubbles are deliberately static to keep pumpAndSettle-safe for widget tests — do not reintroduce AnimationControllers. · **Needs Eric taste:** yes

#### F-03 — P1 · Color
- **Screen/Flow:** AddPartnerScreen text intro + GlassmorphicTextField
- **Evidence (`native-risk`):** add_partner_screen.dart:147-154 the subtitle uses onBackgroundSecondary (#E0D0E8) at fontSize 13 directly over the mid-gradient (#2D1B4E .. #4A2C6A) region. #E0D0E8 on #2D1B4E is high-contrast and fine, BUT the GlassmorphicTextField hint (line 158 '例：Alice / Tinder 上的空姐') is rendered by the shared glass widget whose hint token is glassTextHint #8B4557 — on the field's light glass fill that computes to ~6.5:1 (ok) but the field itself sits on a saturated purple gradient.
- **Problem:** Cannot verify the actual rendered hint contrast without seeing GlassmorphicTextField internals on-device; the field fill + hint pairing is the documented contrast suspect zone and the surrounding gradient changes perceived contrast.
- **User impact:** If the hint resolves to low contrast, first-time users on the empty Add form may not see the example that teaches the 'one card = one person' mental model.
- **Suggested fix:** Verify GlassmorphicTextField hint color on device against its actual fill; if it uses glassTextHint, confirm >=4.5:1 and bump if borderline.
- **Effort:** <30min · **Risk if fixed:** Shared widget — a token change ripples to every glass field app-wide; scope a local override instead of editing the shared token. · **Needs Eric taste:** no

#### F-04 — P2 · Motion
- **Screen/Flow:** PartnerMergePickerScreen / merge + delete flows (loading state)
- **Evidence (`code-verified`):** partner_merge_picker_screen.dart:105-138 _confirm awaits merge with NO busy flag — the FilledButton 'confirmed' dialog returns and then merge() runs with no spinner; partner_list_screen.dart:150-179 _onMergeDuplicate and 222-280 delete likewise await the write controller with only a post-hoc SnackBar, no in-flight indicator. AddPartner (add_partner_screen.dart:74 _busy) is the only screen in the cluster with a proper busy guard.
- **Problem:** Merge, direct-dedupe-merge, and partner delete have no loading/disabled state during the async Hive write. On a slow device the user can double-tap '確認合併'/'立即合併' or sit on an unresponsive screen with no feedback.
- **User impact:** Destructive irreversible operations (merge is '不可復原' per the dialog) can be double-fired or feel hung; user anxiety on the highest-stakes action in the cluster.
- **Suggested fix:** Add a busy flag around merge/delete confirm like AddPartner already does: disable the confirm button and show a spinner while the controller call is in flight.
- **Effort:** ~1h · **Risk if fixed:** Touches the merge/delete write path — guard must not change ordering of markDismissed/invalidate. Re-run partner_merge_picker + partner_list delete tests. · **Needs Eric taste:** no

#### F-05 — P2 · First · 🎨 **TASTE**
- **Screen/Flow:** PartnerListScreen empty state
- **Evidence (`code-verified`):** partner_list_screen.dart:37-71 empty state is a centered Column of 3 text blocks (titleMedium + 2 secondary lines) with NO call-to-action button. Partner creation lives on AddPartnerScreen reached via a FAB that is NOT part of this widget (the screen is only the tab body).
- **Problem:** The first-run empty state tells the user '先建立第一張對象卡' but provides no affordance inside the empty view to act on it — the user must discover the FAB elsewhere. It is pure copy with no button.
- **User impact:** New users on the most important first screen (partner-first home) read an instruction with no obvious next tap; cold-start activation friction.
- **Suggested fix:** Add a primary CTA button ('+ 新增第一張對象卡') directly in the empty state that routes to /partner/new, so the instruction and the action are co-located.
- **Effort:** <30min · **Risk if fixed:** Low; confirm it doesn't duplicate/conflict with the host scaffold FAB and that the route push matches AddPartner's expectations. · **Needs Eric taste:** yes

#### F-06 — P2 · Copy · 🎨 **TASTE**
- **Screen/Flow:** PartnerHeatHeroCard / PartnerRadarSummaryCard / PartnerListCard heat labels
- **Evidence (`code-verified`):** partner_heat_hero_card.dart:24-40 surfaces a raw 0-100 '熱度' number ('--'/56/etc) as the 56px hero figure; partner_radar_summary_card.dart:55 '最新對話 5 維' with axis labels 熱度/互動/深度/回應/情感; partner_traits_card.dart:122 '最新熱度 ${view.latestHeat}'; partner_list_card.dart:149 '🌡️ 待分析'.
- **Problem:** A bare numeric heat score (and '5 維' radar) leans toward the 'tool analyzing the person' register that snapshot.md warns against, rather than 'coach helping you read the relationship'. '5 維' is mildly engineering-flavored. The number is presented as fact without a coach voice around it (the subtitle helps, but the 56px number dominates).
- **User impact:** Borderline product-language: the headline of the detail page is a metric, not a coach read; could feel like being scored/quantified rather than coached.
- **Suggested fix:** Taste call — consider demoting the raw number visually relative to the deterministic label ('升溫中'), and rename '5 維' to plainer language. Keep the read-only/no-synthesis contract.
- **Effort:** ~1h · **Risk if fixed:** Hero label/number mapping is a locked spec with partner_heat_hero_card_test contract; any wording change needs the test regolded. No data risk. · **Needs Eric taste:** yes

#### F-07 — Polish · Inter
- **Screen/Flow:** PartnerDetailScreen partner-not-found state
- **Evidence (`code-verified`):** partner_detail_screen.dart:66-70 returns a bare Scaffold with a single centered Text '找不到對象（可能已被合併或刪除）' — no AppBar (so no back button), no styling, default theme surface.
- **Problem:** After a merge (source partner is deleted, screen pops to '/') or a deep-link to a stale id, this fallback can render with no way back and no visual identity — a dead-end grey screen with engineering-tinged parenthetical copy.
- **User impact:** Rare but real: a user landing here (stale route / race) is stranded with no navigation and copy that exposes internal merge/delete mechanics.
- **Suggested fix:** Add an AppBar with a back button and a friendlier line ('這個對象已經整理掉了'); optionally a button back to the list.
- **Effort:** <30min · **Risk if fixed:** Trivial; ensure it still satisfies any partner_detail_screen_test expectation for the null branch. · **Needs Eric taste:** no

#### F-08 — Polish · Color · 🎨 **TASTE**
- **Screen/Flow:** SameNameDedupeBanner / PartnerDataQualityBanner secondary action
- **Evidence (`code-verified`):** same_name_dedupe_banner.dart:55-58 '以後再說' and partner_data_quality_banner.dart:74-77 '拆成新對象' use TextStyle(color: glassTextSecondary #6C5A6B) on glassWhite #F5F0F8. Computed ratio ~5.8:1 (passes AA body). glassTextHint #8B4557 used in partner_list_card.dart:128/151/159/169 on glassWhite computes ~6.5:1 (passes).
- **Problem:** The flagged contrast suspects actually PASS WCAG AA on the glass surfaces, but the secondary action ('以後再說' / '拆成新對象') is the lowest-emphasis element and '拆成新對象' is a fairly consequential action (creates a new partner) styled as the de-emphasized choice.
- **User impact:** Minor: the destructive-ish split action is visually subordinate; acceptable but worth a deliberate check that the emphasis hierarchy matches intent.
- **Suggested fix:** No contrast fix needed (passes). Confirm intentionally that 'split' should be the quiet option vs 'same person' as primary. Taste-level.
- **Effort:** <30min · **Risk if fixed:** None; banners are snapshot-tested with a no-red lexicon — don't introduce error colors. · **Needs Eric taste:** yes

### Cluster G — Profile / Learning / Report (8)

> _Reviewer notes:_ Could-not-verify caveats: (1) No screenshots — sandbox had no browser libs and no test credentials, so all on-device contrast, ChoiceChip rendered colors, keyboard-overlap on the notes TextFields, scroll feel, and fl_chart wrap-at-320pt are reasoned from source, not observed. G-01/G-04 (chip & input theming collision) are code-verified as a system mismatch but the exact rendered colors are native-risk. (2) Contrast ratios I report are computed (WCAG formula) from the literal hex tokens in app_colors.dart against the confirmed solid GlassmorphicContainer surface (#F5F0F8) — glassTextSecondary 5.65:1 PASSES (the KNOWN-SUSPECT list flagged it, but on the actual SOLID glass it's fine, not on a translucent blur); the real failure is ctaStart-as-text 2.44:1 (G-02). (3) glassTextHint #8B4557 measures 6.06:1 on glassWhite — PASSES, not a defect on this cluster's screens. (4) onBackgroundSecondary is #E0D0E8 (light lavender), not #B3B3B3, so dark-screen body text (about_me, learning, report empty/locked) is high-contrast (>11:1) and fine. (5) Empty states EXIST and are styled for report (line+bars+donut all have '尚無數據' branches and a top-level empty hero) and partner-style (沿用全域 hints); learning grid has no empty branch but `articles` is a 27-item static const, so unreachable — not filed. (6) G-03 radar-chart over-promise is the highest-signal launch/App-Review item and is fully code-verified (grep found zero RadarChart). Copy across this cluster is genuinely strong and coach-voiced ('不會替你假裝成另一個人', '讀完可練一次') with no leaked engineering vocabulary — hence copywriting A. paywallQuota scored C only because of the radar over-promise; the read-gate and locked-card flows themselves are clean and non-pushy.

#### G-01 — P1 · Consist · 🎨 **TASTE**
- **Screen/Flow:** partner_style_edit_screen — _InteractionStyleSection / _PracticeGoalsSection ChoiceChips inside GlassmorphicContainer
- **Evidence (`code-verified`):** app_theme.dart:12 ColorScheme.dark(...) with no ChipTheme defined; partner_style_edit_screen.dart:259 GlassmorphicContainer wraps ChoiceChips (lines 284-291, 383-390). glassmorphic_container.dart:33 surface = AppColors.glassWhite #F5F0F8 (solid light).
- **Problem:** The two color systems collide on this screen. M3 ChoiceChips inherit the global dark ColorScheme (dark unselected surface + light label, dark-purple secondaryContainer when selected) but are placed on a LIGHT glass card (#F5F0F8). A dark-theme chip on a light surface reads as a foreign control: unselected light-on-light or dark-block, selected purple from system (1) clashing with the warm-theme (2) coral/pink CTAs on the same card.
- **User impact:** Users editing per-partner style see chips that look mis-themed vs the identical chips on 關於我 (which sit correctly on dark #121212). Inconsistent, lowers perceived polish on a core personalization flow shown during dogfood.
- **Suggested fix:** Add an explicit ChipThemeData scoped to glass cards (light backgroundColor, glassTextPrimary label, selectedColor = selectedStart/ctaStart, side using glassBorder), or wrap these sections in a Theme override with a light ColorScheme so chips match the glass surface. Mirror whatever about_me uses but inverted for light bg.
- **Effort:** ~1h · **Risk if fixed:** Low; visual-only. Verify selected/unselected states on both light glass and dark scaffold so about_me chips don't regress. · **Needs Eric taste:** yes

#### G-02 — P1 · Color · 🎨 **TASTE**
- **Screen/Flow:** about_me_card _FilledState 編輯 button; article_detail _PracticeLabel; heat_trend month pill; any ctaStart-as-foreground on glass
- **Evidence (`code-verified`):** about_me_card.dart:153 TextButton foregroundColor: AppColors.ctaStart (#FF7043) on GlassmorphicContainer glassWhite #F5F0F8 → measured 2.44:1. heat_trend_chart.dart:86-99 white month-pill text on solid ctaStart fill → 2.74:1. ctaStart label text also used in article_detail _PracticeLabel (line 467) and learning header accent.
- **Problem:** ctaStart #FF7043 as TEXT on the light glass surface is 2.44:1 — fails WCAG AA (4.5:1 body, 3:1 large). The '編輯' action link and orange accent labels are hard to read. White-on-ctaStart pill at 2.74:1 is also under 3:1 even as large text.
- **User impact:** Users with average vision (and especially outdoors / low-brightness) struggle to see the '編輯' link and orange micro-labels. Affects discoverability of the edit affordance on the report's top card.
- **Suggested fix:** For text/links on glass use a darker orange (e.g. ctaEnd #FF5722 → still ~3:1; better: a dedicated accent-on-light token around #C8431B for >=4.5:1). For the month pill keep white but darken the pill fill or add weight; or invert (orange text on subtle tint). Do not change the CTA button fills themselves (those are white-on-orange buttons, acceptable as large).
- **Effort:** ~1h · **Risk if fixed:** Low; introduce one new on-light accent token rather than editing ctaStart globally (ctaStart is reused for gradient buttons where white-on-orange is fine). · **Needs Eric taste:** yes

#### G-03 — P1 · Pay · 🎨 **TASTE**
- **Screen/Flow:** my_report_screen _lockedReportCard (free-user paywall card)
- **Evidence (`code-verified`):** my_report_screen.dart:94 copy '升級後可以看五維雷達圖、歷史趨勢與不同對話的比較'. grep across lib/features/report for 雷達/radar/RadarChart returns only this string — no RadarChart widget exists. Rendered report (lines 59-72) is HeatTrendChart (line) + ConversationComparisonChart (bars) + StageDistributionChart (donut).
- **Problem:** The paywall promises a '五維雷達圖' (5-dimension radar chart) that the product does not contain. After paying, the user never sees a radar — only a trend line, bar comparison, and donut. This is a feature over-promise in a purchase-driving surface.
- **User impact:** A free user upgrades expecting a radar chart and finds it missing → feels misled, churn/refund risk. Also an App Review red flag: paid-feature description not matching delivered functionality.
- **Suggested fix:** Either (a) change copy to describe what actually ships ('歷史熱度趨勢、對話比較、階段分佈') or (b) build the radar. For launch, fix the copy. Coordinate with pricing-final.md if the radar was a promised tier feature.
- **Effort:** <30min (copy) / ~half-day (build radar) · **Risk if fixed:** Copy-only fix is safe; touches paywall messaging so verify against pricing-final.md and any store screenshots that also show '雷達圖'. · **Needs Eric taste:** yes

#### G-04 — P2 · Consist
- **Screen/Flow:** partner_style_edit_screen _NotesSection TextField; about_me_screen TextFields
- **Evidence (`code-verified`):** app_theme.dart:30-36 InputDecorationTheme filled:true fillColor: AppColors.surfaceVariant (#2D2D2D dark). partner_style_edit_screen.dart:470 InputDecoration only overrides border (OutlineInputBorder), not fillColor, while the field sits inside GlassmorphicContainer glassWhite #F5F0F8.
- **Problem:** The notes TextField inherits the global dark fill (#2D2D2D) but lives on a light glass card. You get a dark input box embedded in a light card — another (1)/(2) system collision. The typed text color and hint also follow dark-theme defaults on a dark fill, while the surrounding card is light.
- **User impact:** Visually jarring on the per-partner style editor; the input looks like it belongs to a different screen. Lower polish, but functional.
- **Suggested fix:** Provide a light InputDecoration for glass-card fields (fillColor: white/transparent, hint glassTextHint, text glassTextPrimary) via a scoped Theme or explicit decoration. about_me TextFields are on dark bg so they're fine — scope the override to glass usage only.
- **Effort:** ~1h · **Risk if fixed:** Low; verify dark-screen TextFields (about_me) unaffected. · **Needs Eric taste:** no

#### G-05 — P2 · RWD
- **Screen/Flow:** stage_distribution_chart (donut + legend); heat_trend_chart; conversation_comparison_chart on small screens
- **Evidence (`code-verified`):** stage_distribution_chart.dart:51-53 fixed SizedBox(width:140,height:140) donut + SizedBox(width:24) gap inside a Row; legend in Expanded. heat_trend_chart.dart:164 fixed height:180 with leftTitles reservedSize:32 + bottomTitles reservedSize:28. conversation_comparison_chart.dart:92 fixed name width 72 + 32 score, bar in Expanded.
- **Problem:** The donut Row reserves a hard 140+24=164px before the legend's Expanded; on a 320pt-wide device inside 16px card padding the legend column gets very little width, and Chinese stage names + counts can wrap/cramp. The 72px conversation-name column will ellipsize most real partner names to 3-4 chars. These are hardcoded sizes not scaled to MediaQuery.
- **User impact:** Users on small phones (iPhone SE/mini) see cramped legends and heavily truncated conversation names in the comparison bars, reducing the report's legibility — the report's whole value is at-a-glance legibility.
- **Suggested fix:** Make the donut size responsive (e.g. min(140, constraints.maxWidth*0.38)) and let conversation name width flex (Flexible instead of fixed 72, or 2-line). Confirm on 320pt width. Charts are otherwise sound.
- **Effort:** ~half-day · **Risk if fixed:** Low-medium; layout-only, but fl_chart sizing needs device testing (native-risk for exact wrap behavior). · **Needs Eric taste:** no

#### G-06 — P2 · Hier · 🎨 **TASTE**
- **Screen/Flow:** stage_distribution_chart legend (color-only encoding)
- **Evidence (`code-verified`):** stage_distribution_chart.dart:21-27 maps 5 stages to bokehYellow #FFD54F, bokehCoral #FF8A65, ctaStart #FF7043, hot #E57373, veryHot #FF6B9D. Donut sections showTitle:false (line 125); legend dots are the only key (lines 135-141).
- **Problem:** Four of the five stage colors (coral #FF8A65, ctaStart #FF7043, hot #E57373, veryHot #FF6B9D) are near-adjacent warm orange/pink hues. On the donut they are nearly indistinguishable from each other, and the legend relies purely on a 10px color dot to disambiguate (no in-segment labels). Yellow is the only clearly separable hue.
- **User impact:** Users (especially red-deficient color-vision) cannot tell 升溫/深入/連結/邀約 segments apart in the donut, defeating the 'see your stage distribution' purpose. The legend dot + name still works but the chart itself communicates little.
- **Suggested fix:** Use a wider-spread palette across the 5 stages (introduce the cold/info blue and a distinct mid-tone so hues are separable), or add percentage labels per segment and/or vary lightness markedly. Keep enthusiasm semantics where they matter but ensure adjacent stages differ.
- **Effort:** ~1h · **Risk if fixed:** Low; palette change only. needsEricTaste — it touches the warm brand palette. · **Needs Eric taste:** yes

#### G-07 — Polish · Slop · 🎨 **TASTE**
- **Screen/Flow:** article_detail_screen content rendering / GradientBackground glass theme
- **Evidence (`code-verified`):** article_detail_screen.dart:80 GradientBackground + glass GlassmorphicContainer body; heavy stacked card pattern: _PracticeBriefCard, glass content card, _PracticeActionCard, _ExampleBox x2 — each a glass/tinted card with an icon (lightbulb_outline, near_me_outlined, check_circle, cancel). gradient_background.dart drives the purple/pink warm gradient.
- **Problem:** This is the cluster's strongest lean into the named warm-theme tokens Eric flags as AI-slop: full-screen purple→pink gradient, multiple stacked glass cards, and several decorative outline icons (lightbulb/near_me) used purely as labels. The reading experience is broken into 4-5 glass cards rather than a single clean long-form column.
- **User impact:** Long-form reading feels like a template/engineering-generated 'card soup' rather than an editorial article. This is a brand-taste tension, not an objective bug — but it is exactly the generic feel Eric dislikes, on a screen meant to feel like coaching content.
- **Suggested fix:** Consider flattening article body to one calm reading surface (single card or no card), reserve glass cards only for the two practice CTAs, and drop the lightbulb/near_me decorative icons in favor of plain bold labels. Eric to decide how far to de-glass.
- **Effort:** ~half-day · **Risk if fixed:** Low (visual); but it is a deliberate brand direction, so confirm before reworking. Read-gate logic must not change. · **Needs Eric taste:** yes

#### G-08 — Polish · Inter
- **Screen/Flow:** article_detail_screen read-gate / not-found state
- **Evidence (`code-verified`):** article_detail_screen.dart:71-73 missing-article state: bare Scaffold Center Text('找不到這篇文章') with default theme (no GradientBackground, no AppBar/back). Line 80-86 read-gate loading is a centered spinner with no message.
- **Problem:** The article-not-found fallback is an unstyled dead-end: no app bar, no back button, no way to navigate out except the system gesture, and it visually drops out of the warm theme entirely. The read-gate loading spinner is silent (no '正在開啟' reassurance) before a potential paywall redirect.
- **User impact:** A user who hits a stale/bad article id (or during the free-quota redirect frame) lands on a plain screen with no exit affordance — feels broken. Edge case but reachable.
- **Suggested fix:** Give the not-found state an AppBar with back + the GradientBackground, and a friendly line. Optionally add a short caption under the gate spinner. Keep paywall redirect logic untouched.
- **Effort:** <30min · **Risk if fixed:** Low; do not alter _applyReadGate quota/recordRead logic (that path charges a free read). · **Needs Eric taste:** no

### Cluster H — Subscription / Paywall / Settings (7)

> _Reviewer notes:_ Could NOT verify on-device rendering: sandbox has no browser deps and no test creds, so no screenshots — all contrast figures are computed from source hex values via WCAG formula, and runtime compositing of translucent fills is marked native-risk (H-06). Verified contrast math: glassTextHint #8B4557 on glassWhite #F5F0F8 = 6.06:1 (PASS body), glassTextSecondary #6C5A6B = 5.65:1 (PASS), glassTextPrimary #4A3548 = 9.87:1 (PASS), unselectedText #5D4E6B on glassWhite = 6.76:1 (PASS, used only inside glass dialogs not on the dark gradient), textSecondary #B3B3B3 on surface #1E1E1E = 7.95:1 (PASS, booster sheet). The headline contrast failure is H-01: selected option card composited fill (#FF6B9D@0.3 over gradient = #5e2352–#803e79) with retained dark-glass text = 1.0–1.8:1, code-verified from glassmorphic_container.dart:33-35 + paywall_screen.dart:822. Positives worth recording: quota IS shown in human language ('本月剩餘 50/300', '今日剩餘'), not tokens/quota-left-N; restore path exists on both paywall (line 388) and settings (line 209); consent dialog correctly states declining does NOT charge quota (line 88); purchase errors are mapped to plain Chinese (lines 1071-1087); upgrade/downgrade/pending-downgrade copy is careful about 'today won't be re-charged'. appReviewRisk graded C mainly due to the non-functional English 'Coming Soon' booster sheet (H-02/H-03) being reachable in a review build; consistency graded D due to booster sheet using the flat Material system while the rest of the cluster uses warm glass. Two color systems DO coexist in this cluster: warm-glass (paywall, settings, consent-adjacent dialogs) vs flat-dark Material (booster sheet + the default-themed consent AlertDialog) — that mixing is the central consistency defect.

#### H-01 — P1 · Color · 🎨 **TASTE**
- **Screen/Flow:** PaywallScreen — selected plan option card (_buildOptionCard with GlassmorphicContainer isSelected=true)
- **Evidence (`code-verified`):** glassmorphic_container.dart:33-35 sets fill to AppColors.selectedStart (#FF6B9D) withValues(alpha:0.3) when isSelected; paywall_screen.dart:822-823 passes isSelected to the option card while ALL text children (lines 837-935: plan name, priceLabel headlineMedium, highlights) keep dark-glass colors glassTextPrimary #4A3548 / glassTextSecondary. Composited #FF6B9D@0.3 over the gradient stops (#1A0533/#2D1B4E/#4A2C6A) yields #5e2352–#803e79; #4A3548 on that = 1.03–1.52:1, #6C5A6B = 1.15–1.80:1.
- **Problem:** The selected option card flips its surface to a dark pink-purple but keeps text colors that were designed for the light glassWhite (#F5F0F8) surface. Contrast collapses to ~1.0–1.8:1, far below AA 4.5:1.
- **User impact:** The plan the user is about to BUY (selected card: name, price, feature bullets) becomes the least legible card on the paywall. Worst-hit at the exact decision moment; affects every paying user.
- **Suggested fix:** When isSelected, either keep the glassWhite fill and show selection via border/glow only (drop the 0.3 pink fill), or switch the card's text colors to on-dark (#FFFFFF / #E0D0E8). Simplest: in GlassmorphicContainer keep glassWhite fill for selected and rely on the existing selectedStart border + boxShadow already present at lines 38-52.
- **Effort:** ~1h · **Risk if fixed:** Visual-only; touches the shared GlassmorphicContainer used app-wide, so regression-test any other screen that relies on the pink selected fill (new-conversation style picker likely). No quota/purchase logic touched. · **Needs Eric taste:** yes

#### H-02 — P1 · Consist · 🎨 **TASTE**
- **Screen/Flow:** BoosterPurchaseSheet (whole sheet)
- **Evidence (`code-verified`):** booster_purchase_sheet.dart:25-27 uses AppColors.surface/background and AppColors.textSecondary (the FLAT dark Material system), while every sibling subscription screen (paywall, settings) uses the warm glass system (GlassmorphicContainer, glassWhite, GradientBackground). All copy is English: 'Message Booster' (44), 'Preview the planned one-time packages. Purchase is not live yet.' (51), 'Coming Soon' (83); message_booster.dart:33 label = '$messageCount messages', :35 'NT\$...'.
- **Problem:** This sheet belongs to a different color system AND is entirely in English inside a 100% Traditional-Chinese product. It also leaks engineering vocab to users (see H-03).
- **User impact:** A Traditional-Chinese user opening the booster sheet hits English UI on a visually mismatched dark card — feels like a half-built debug screen, not the same app. Breaks brand trust mid-purchase-intent.
- **Suggested fix:** Either hide the booster entry entirely until live, or rebuild the sheet on the warm glass system with Traditional-Chinese copy ('加購訊息額度', '即將推出'). Localize message_booster.dart labels.
- **Effort:** ~half-day · **Risk if fixed:** Low logic risk (sheet is non-functional 'Coming Soon'). If hidden, verify no dead nav entry. No purchase actually completes here so quota is untouched. · **Needs Eric taste:** yes

#### H-03 — P1 · Copy
- **Screen/Flow:** BoosterPurchaseSheet — descriptive copy
- **Evidence (`code-verified`):** booster_purchase_sheet.dart:67 'This sheet is read-only for now. RevenueCat booster IAP still needs to be integrated before any purchase can complete.' and :51 'Preview the planned one-time packages. Purchase is not live yet.' and snackbar :167 'Booster purchases are not live yet.'
- **Problem:** Internal engineering status ('read-only', 'RevenueCat booster IAP still needs to be integrated') is shown verbatim to end users, violating the product-language rule against leaking RevenueCat/integration vocabulary. It reads like a developer TODO.
- **User impact:** Users see implementation notes meant for the team. Looks unfinished and unprofessional; an App Review reviewer could flag a non-functional 'Coming Soon' purchase surface.
- **Suggested fix:** Remove the integration-status sentence. If the feature must be visible pre-launch, say only '加購包即將推出，敬請期待' in plain user language. Best: gate the sheet behind a feature flag so it never ships visible.
- **Effort:** <30min · **Risk if fixed:** None to purchase flow (no live IAP). Only copy/visibility change. · **Needs Eric taste:** no

#### H-04 — P2 · RWD
- **Screen/Flow:** BoosterPurchaseSheet — bottom sheet layout
- **Evidence (`code-verified`):** booster_purchase_sheet.dart:23-32 root is a non-scrollable Column inside a Container with no SafeArea; showModalBottomSheet at :176-181 uses isScrollControlled:true but content is fixed. Content = drag handle + title + subtitle + 3 package rows (BoosterPackage.values) + 12px note block + 16px note block + button + paddings.
- **Problem:** No scroll wrapper and no SafeArea bottom inset on a content-heavy bottom sheet. On small devices (SE-class) the stacked content can exceed available height and clip the button / collide with the home indicator.
- **User impact:** Small-screen users may not see the 'Coming Soon' button or have it overlap the gesture bar.
- **Suggested fix:** Wrap the Column in SingleChildScrollView and add SafeArea(top:false) (or MediaQuery viewInsets/padding bottom) so the sheet never clips.
- **Effort:** <30min · **Risk if fixed:** Pure layout; negligible. · **Needs Eric taste:** no

#### H-05 — P2 · Copy · 🎨 **TASTE**
- **Screen/Flow:** AiDataSharingConsent dialog
- **Evidence (`code-verified`):** ai_data_sharing_consent.dart:78 '經由 VibeSync 後端服務（Supabase Edge Functions）傳送至 Anthropic Claude API', :113 checkbox repeats '傳送至 Supabase Edge Functions 與 Anthropic Claude API'. Dialog is a default Material AlertDialog (no theming) so it renders in the flat ThemeData, mismatching the warm glass dialogs used elsewhere (e.g. restore/delete dialogs set backgroundColor: AppColors.glassWhite).
- **Problem:** Engineering/vendor terms ('Supabase Edge Functions', 'Anthropic Claude API') surface to users, which the product-language rule lists as defects. Also a visual-system mismatch vs the rest of the cluster's dialogs.
- **User impact:** Two-sided: naming the sub-processors is GOOD for App-Review honesty/GDPR transparency, but 'Supabase Edge Functions' specifically is implementation detail a user can't parse. The unthemed dialog also looks like a different app.
- **Suggested fix:** Keep the honest disclosure that data goes to a third-party AI provider (Anthropic Claude) but soften infra wording: drop 'Supabase Edge Functions' or rephrase to '我們的伺服器'. Consider theming the dialog to match. Confirm final wording with Eric given the App-Review tradeoff.
- **Effort:** ~1h · **Risk if fixed:** Consent copy is App-Review/legal sensitive — any wording change should preserve the honest third-party-AI disclosure and the 'no quota charged if declined' line (already correct at :88). Do not weaken the disclosure. · **Needs Eric taste:** yes

#### H-06 — P2 · Color
- **Screen/Flow:** PaywallScreen / SettingsScreen — quota & usage pills, feature comparison Free column
- **Evidence (`native-risk`):** Quota pills (paywall :683-689, settings :333-339) fill with Colors.white.withValues(alpha:0.42) painted INSIDE a GlassmorphicContainer whose own fill is solid glassWhite #F5F0F8 (glassmorphic_container.dart:35). Composited that is light and pill text (glassTextHint #8B4557 ≈6.06:1, glassTextPrimary #4A3548 ≈9.87:1) passes. BUT the feature table Free-column values use glassTextHint #8B4557 and the comparison header non-Essential labels use glassTextHint — measured 6.06:1 (passes body) yet visually the lowest-emphasis. glassTextSecondary #6C5A6B on glassWhite = 5.65:1 (passes). The only real ambiguity is whether the GlassmorphicContainer ever renders translucent on some devices; it does not in current code.
- **Problem:** On the as-written solid glassWhite surface all these greys actually pass AA. The residual risk is purely runtime: if any future change makes the glass container translucent, the pill's 0.42-white fill would composite over the dark gradient and drop dark-glass text to ~1.4–2.0:1.
- **User impact:** Today: fine. The flag is to prevent a regression — the pill alpha + dark text is only safe because the container behind it is opaque.
- **Suggested fix:** Give the quota/usage pill an explicit opaque light fill (e.g. solid glassWhite-tinted color) instead of white@0.42, so legibility no longer depends on the parent container staying opaque.
- **Effort:** <30min · **Risk if fixed:** Visual-only. · **Needs Eric taste:** no

#### H-07 — Polish · Slop · 🎨 **TASTE**
- **Screen/Flow:** PaywallScreen — top free-form copy and bg motion / aiSlop
- **Evidence (`code-verified`):** Paywall and Settings wrap in GradientBackground (gradient_background.dart) which renders 3 continuously animating bokeh orbs (bokehPink/Coral/Yellow, opacity 0.6-0.7, 6-8s repeat) behind the purchase content; plus purple primary, glass cards, pink CTA gradient. These are exactly the named tokens (bokehPink, glassWhite, gradient bg) on Eric's AI-slop aversion list.
- **Problem:** The paywall — the highest-stakes conversion screen — leans on animated bokeh blobs + glassmorphism + purple/pink gradients, the precise aesthetic Eric has flagged as 'generic/template feel'.
- **User impact:** Subjective: constant background motion behind price/legal text can feel busy and slightly cheapen a payment screen; also a minor battery/repaint cost during a screen users dwell on.
- **Suggested fix:** Consider freezing or removing the bokeh animation on the paywall specifically (static gradient, or pause controllers) and dialing back decorative motion behind pricing/consent. Brand-taste call.
- **Effort:** ~1h · **Risk if fixed:** Low; isolated to background widget. Confirm no test asserts the animation. · **Needs Eric taste:** yes

### Cluster COPY — Copy pass (Traditional-Chinese product language) (6)

> _Reviewer notes:_ Method: grep'd lib/features + lib/shared for Traditional-Chinese string literals across paywall, analysis error/quota paths, coach-chat, opener, login, onboarding; read surrounding widgets to judge context. Live web-preview/screenshot capture was NOT available (no browser deps, no test creds), so no screenshot-verified findings — anything runtime-dependent is marked native-risk.

False positives I deliberately did NOT flag (verified clean): (1) The heavy telemetry/guardrail jargon ('服務不穩定 / 重試或 fallback / benchmark / OCR 量測 / 引用併回 / 版面分群') in analysis_screen.dart lines ~2670-2900 and analysis_telemetry_guardrail_helper.dart is ALL gated behind `_showTelemetryDiagnostics => kDebugMode` (analysis_screen.dart:73, gating ifs at 5354 and 5446) — not user-facing in release. (2) glassTextHint/glassTextSecondary on glassWhite PASS AA (6.06/5.65), contrary to the suspect list — did not flag. (3) No App-Review-risky medical/guarantee/脫單/成功率 claims found; all '一定' hits are natural usage inside learning-article body copy.

Overall copy quality is high and genuinely coach-voiced — coach_chat_card.dart ('這是額度限制，不是教練失敗', '未扣額度') and opening_rescue_screen.dart are exemplary brand voice. Login error mapping (login_screen.dart:211-259) is clean and plain. The defects cluster narrowly: (a) the '免費' word baked into tier-agnostic quota exceptions reaching paid users (COPY-01, the one true P1 copy bug), (b) '格式異常/串流分析' engineering leakage in analyze error strings (COPY-02), and (c) '同步/異常/診斷' jargon on the paywall (COPY-03/04). Fixing COPY-01 and COPY-02 are the must-do-before-launch items; both are string-only with low regression risk (verify quota/analysis widget tests don't assert the old literals).

#### COPY-01 — P1 · Copy
- **Screen/Flow:** Manual / screenshot analysis (analysis_service.dart MonthlyLimitExceededException + DailyLimitExceededException, surfaced via streaming_analyze_notifier.dart:247 and AnalysisException.message)
- **Evidence (`code-verified`):** lib/features/analysis/data/services/analysis_service.dart:2187 '今日免費額度已用完，可以明天再試，或升級解鎖更多分析。' and :2201 '本月免費額度已用完，升級後可以繼續分析。' These are the unconditional default .message of the exceptions, thrown regardless of tier (throws at lines 1456/1463/1657/1663/2067/2073 with no tier branch). streaming_analyze_notifier.dart:247 surfaces 'e is AnalysisException ? e.message' directly into recommendationPreviewErrorMessage shown to the user.
- **Problem:** The word '免費' (free) is hardcoded into the quota-exhausted message but the exception fires for ALL tiers. A paying Starter/Essential user who hits their paid monthly cap (e.g. 800/month) is told '本月免費額度已用完' — they have no free quota; they pay. The analysis_screen.dart:229-230 override is tier-aware and drops '免費', but any path that shows e.message directly (the streaming notifier preview-error path) leaks the wrong word.
- **User impact:** A paying customer who exhausts their paid quota is told their FREE quota ran out, implying they were never charged / the plan they bought does nothing. Confusing, undermines trust in the subscription they paid for, and reads as a billing bug.
- **Suggested fix:** Remove '免費' from the default messages: '今日額度已用完，可以明天再試，或升級解鎖更多分析。' and '本月額度已用完，升級後可以繼續分析。' Keep the friendlier tier-aware override in analysis_screen as the primary path. Free-vs-paid distinction, if wanted, should be injected at the UI layer based on actual tier, not baked into the exception.
- **Effort:** <30min · **Risk if fixed:** Touches quota-exhaustion copy. Low logic risk (string-only) but verify no test asserts the literal '免費額度' string; widget/golden tests on the analysis error path may need the expected text updated. · **Needs Eric taste:** no

#### COPY-02 — P1 · Copy
- **Screen/Flow:** Manual / screenshot analysis error states (analysis_service.dart format-failure throws)
- **Evidence (`code-verified`):** lib/features/analysis/data/services/analysis_service.dart:1436 '伺服器回傳格式異常，請稍後再試。', :1550 '分析回應格式錯誤，請稍後再試。', :1705 & :1866 '串流分析回傳格式異常，請重新分析。', :2052 '伺服器回傳格式異常，請稍後再試。'. These are AnalysisException.message values that flow to AnalysisErrorWidget.message and override the friendly _getDefaultMessage().
- **Problem:** These error strings leak engineering vocabulary the snapshot rules explicitly ban for users: '回傳格式異常' (response schema/format abnormal), '回應格式錯誤' (response format error), '串流分析' (streaming analysis = internal pipeline name). To a dating-app user, '伺服器回傳格式異常' and '串流分析回傳格式' are meaningless and alarming — they read like a raw backend error, not a coach reassuring them.
- **User impact:** User hitting a transient format/parse failure (which per project rule must NOT charge quota and must be reassuring) instead sees backend jargon. Feels like the app is broken / engineering-grade, not like a coach. Erodes the premium 'coach on your side' positioning at the exact moment of failure.
- **Suggested fix:** Replace all with plain, reassuring, non-technical copy, e.g. '這次分析沒順利完成，沒有扣到額度，請再試一次。' Drop '格式異常/格式錯誤/串流分析' entirely from anything that can reach AnalysisErrorWidget.message. If you want a distinct retry hint use '請重新分析' (already user-safe) without the '串流分析回傳格式' prefix.
- **Effort:** <30min · **Risk if fixed:** analyze-chat is a high-risk zone, but these are pure display strings (no control flow). Confirm the messages aren't string-matched anywhere (e.g. analysis_service.dart:815/824 matches '圖片格式錯誤'/'圖片順序錯誤' — different strings, so safe). Verify no test asserts the literal '格式異常' text. · **Needs Eric taste:** no

#### COPY-03 — P2 · Copy · 🎨 **TASTE**
- **Screen/Flow:** Paywall (paywall_screen.dart info cards + snackbars)
- **Evidence (`code-verified`):** lib/features/subscription/presentation/screens/paywall_screen.dart:285 '正在同步方案資訊', :301 '方案同步異常' / '目前無法更新你的最新方案狀態', :1055 'App Store 價格同步逾時', :1059 '無法重新載入 App Store 價格', :1226 '已重新同步訂閱狀態。', :1233 '同步失敗，請稍後再試。'
- **Problem:** Repeated use of '同步' (sync) and '異常' (abnormal) leaks engineering vocabulary onto the paywall — the most conversion-sensitive and App-Review-scrutinized screen. '方案同步異常' reads as a system error message, not as customer-facing reassurance. The product-language rule lists 'sync' as engineering vocabulary that is a defect when surfaced to users.
- **User impact:** A user on the paywall about to pay sees '方案同步異常 / 正在同步方案資訊' and reads it as 'this billing system is glitchy' — directly suppresses purchase confidence and may look unfinished to an App Review reviewer.
- **Suggested fix:** Soften to plain language: '方案同步異常' -> '暫時讀不到你最新的方案狀態'; '正在同步方案資訊' -> '正在載入方案'; 'App Store 價格同步逾時' -> '讀取 App Store 價格逾時'; '已重新同步訂閱狀態' -> '已更新訂閱狀態'. Avoid '同步/異常' on user-facing paywall copy.
- **Effort:** <30min · **Risk if fixed:** Paywall is a high-risk zone, but these are display-only strings. No quota/purchase logic touched. Low risk; just verify paywall widget tests don't assert the old literals. · **Needs Eric taste:** yes

#### COPY-04 — P2 · Copy · 🎨 **TASTE**
- **Screen/Flow:** Paywall footer (paywall_screen.dart:393-398 '複製訂閱診斷' button, :1206 '訂閱診斷已複製')
- **Evidence (`code-verified`):** lib/features/subscription/presentation/screens/paywall_screen.dart:390 'if (!kIsWeb) ...' gates a TextButton labelled '複製訂閱診斷' that copies a JSON blob (userId, email, RevenueCat snapshot, tier, usage) to clipboard. It is NOT behind kDebugMode / test-account gating — every production iOS user sees it next to 服務條款/隱私政策/管理訂閱/恢復購買.
- **Problem:** '複製訂閱診斷' (copy subscription diagnostics) is a developer/support affordance exposing engineering vocabulary ('診斷' = diagnostics) and an internal JSON payload, placed in the consumer legal/links row of the paywall. It reads as unfinished/engineering and sits beside legally-required links where App Review looks closely.
- **User impact:** Normal users are confused by a '診斷' button among legal links; a curious user copies a JSON dump containing their own email/userId. An App Review reviewer may flag a debug-looking control on the purchase screen. Dilutes the premium feel.
- **Suggested fix:** Gate the '複製訂閱診斷' button behind kDebugMode or the test-account flag (the codebase already has isTestAccount plumbing in analysis_screen and _showTelemetryDiagnostics => kDebugMode as precedent). If it must stay for support, relabel to user-plain '回報訂閱問題' and move it out of the legal-links row.
- **Effort:** <30min · **Risk if fixed:** Subscription/paywall high-risk zone. The fix is gating a UI button, not changing purchase/restore logic. Ensure '恢復購買' and '管理訂閱' remain visible (those are App-Review-required). Low regression risk. · **Needs Eric taste:** yes

#### COPY-05 — Polish · Copy · 🎨 **TASTE**
- **Screen/Flow:** Paywall feature comparison table (paywall_screen.dart:541)
- **Evidence (`code-verified`):** lib/features/subscription/presentation/screens/paywall_screen.dart:541 _buildComparisonRow('回覆風格', '延展', '全部 5 種', '全部 5 種') — the Free column value is the single word '延展'.
- **Problem:** In the '回覆風格' (reply styles) row, the Free tier value is just '延展' with no qualifier, while Starter/Essential say '全部 5 種'. '延展' alone is ambiguous — a user cannot tell it means 'only the 延展 style (1 of 5)'. Onboarding lists the five styles as 延展、共鳴、調情、幽默、冷讀, so '延展' here is an unlabelled single style.
- **User impact:** Free users reading the comparison cannot tell how limited the free reply-style set is, weakening the upgrade rationale; or they assume '延展' is a feature name they don't recognise. Mild conversion/clarity loss on the comparison table.
- **Suggested fix:** Make the Free value explicit and parallel, e.g. '僅延展 1 種' or '延展（1 種）', so it reads against '全部 5 種'.
- **Effort:** <30min · **Risk if fixed:** Display-string only on paywall. No logic risk. Confirm the actual free-tier style entitlement is indeed 1 style before writing '1 種' (verify against SubscriptionTierHelper / style gating). · **Needs Eric taste:** yes

#### COPY-06 — Polish · accessibility · 🎨 **TASTE**
- **Screen/Flow:** Warm-theme glass surfaces app-wide (paywall, login, opener) — glassTextHint #8B4557 / glassTextSecondary #6C5A6B on glassWhite #F5F0F8; unselectedText #5D4E6B on warm gradient
- **Evidence (`native-risk`):** Computed WCAG (sRGB): glassTextHint #8B4557 on glassWhite #F5F0F8 = 6.06:1 (PASS AA), glassTextSecondary #6C5A6B on glassWhite = 5.65:1 (PASS AA). BUT unselectedText #5D4E6B on mid-gradient #2D1B4E = 2.01:1 (FAIL AA 4.5). textSecondary #B3B3B3 on surface #1E1E1E = 7.95:1 (PASS). unselectedText is used for hint/secondary copy in screenshot_recognition_dialog.dart, new_conversation_sheet.dart, settings_screen.dart, partner_list_screen.dart.
- **Problem:** I cleared the two named glass suspects — glassTextHint/glassTextSecondary on glassWhite actually pass AA (6.06 / 5.65), so flagging them would be a false positive. The real risk is unselectedText #5D4E6B: on the warm dark gradient it computes to 2.01:1, far below AA. Whether any of its usages land on the gradient (vs on a glassWhite dialog where it would pass) is surface-dependent and I could not confirm per-call-site at runtime.
- **User impact:** Wherever unselectedText body/hint copy renders over the dark warm gradient rather than a glass card, the text is functionally near-invisible (cancel labels, hints in dialogs). Affects readability for all users, worse in sunlight / low brightness.
- **Suggested fix:** Audit each unselectedText usage for its actual background. For any on the gradient (not on glassWhite), switch to onBackgroundSecondary #E0D0E8 or a lighter token. Do not change the glassTextHint/glassTextSecondary tokens — they pass.
- **Effort:** ~1h · **Risk if fixed:** Pure color-token swap per call-site; no logic. Risk is only visual regression on glass surfaces where unselectedText currently passes — change only the gradient-background instances. · **Needs Eric taste:** yes

### Cluster DATA — Data-state / quota / paywall consistency pass (5)

> _Reviewer notes:_ Scope: subscription (paywall_screen, settings_screen, booster_purchase_sheet), opener (opening_rescue_screen, opener_service), analysis (analysis_screen, analysis_service, streaming loaders). No live screenshots possible (sandbox lacks browser libs / test creds) — all findings are code-verified from Dart source; no screenshot claims made.

Invariant verification results:
(1) Free-not-blocked-until-exhausted: PASS. opening_rescue_screen.dart:169-193 _canStartGeneration refreshes then defers to the Edge Function ('let the Edge Function make the authoritative quota decision instead of blocking a fresh free user', line 177-179). Analysis flow charges only server-side and maps 429 to clear copy.
(2) Path-to-paywall-when-exhausted: PASS. Opener quota exception routes to /paywall (_showPaywallAndRefresh, l195); analysis surfaces '升級方案可取得更多額度' + routes to paywall (analysis_screen.dart:226-235).
(3) Quota/button/paywall internal consistency: mostly PASS; one latent dual-source-of-truth hazard (DATA-04).
(4) Raw JSON never reaches UI: PASS for analysis — _decodeResponseBody wraps non-JSON as {_nonJson,_rawBody} and the consumers (analysis_service.dart:1434, 2050) convert it to a coded INVALID_RESPONSE_FORMAT retry error, never rendering _rawBody. Schema-leak sanitizer (_sanitizeSchemaLeakText / _replaceSchemaListFields, ~l500-560) humanizes interests/traits/notes leaks. Opener parses defensively and throws '開場產生格式異常' on empty (opener_service.dart:365-367). The one passthrough gap is plain text, not JSON (DATA-05).
(5) loading/streaming/retry/failed/empty states: PASS for analysis (StreamingAnalysisLoader rotating coach copy, FullAnalysisRetryCard with exhausted-retry message). Opener has loading + error + result but the error state lacks an explicit retry affordance (folded into DATA-01).
(6) Opener paid result next-step: PASS — '她回覆了，開始分析對話' CTA (l1163) + handoffLocationFor carries partnerId.
(7) Manual vs screenshot analysis consistency: both run through the same notifier/states; copy differs appropriately (analysis_screen.dart:2385-2386). No contradiction found.
(8) Naming consistency: tier labels centralized via _tierLabel in both paywall and settings; consistent.

Contrast check (computed, WCAG): the listed glass suspects PASS on the glass surface — glassTextHint #8B4557 on #F5F0F8 = 6.06:1, glassTextSecondary #6C5A6B on #F5F0F8 = 5.65:1 (both > AA 4.5). The quota pills (paywall l686) sit on white@0.42 (lighter than glass) so hint text passes there too. The genuine failure is unselectedText #5D4E6B on mid-gradient #2D1B4E = 2.01:1, but in the data-state screens audited here unselectedText is used inside glass dialogs/light surfaces (paywall restore dialog l1117 on glassWhite, settings l572), not directly on the dark gradient — so it is a native-risk for the broader visual cluster rather than a DATA-state defect; not raised as a separate DATA finding to avoid double-counting with the color/contrast cluster.

#### DATA-01 — P1 · Inter
- **Screen/Flow:** opening_rescue_screen.dart — opener generation error state
- **Evidence (`code-verified`):** lib/features/opener/presentation/screens/opening_rescue_screen.dart:461-466 — `catch (e) { setState(() { _error = e.toString().replaceFirst('Exception: ', ''); }); }`. The only typed catch above it is OpenerQuotaExceededException (line 453). OpenerService.generateOpeners calls `_invoke('analyze-chat', ...)` (opener_service.dart:336) → `SupabaseService.invokeFunction`, which can throw raw network/platform exceptions (SocketException, TimeoutException, ClientException) that are NOT wrapped in a Chinese-message Exception(). Those propagate to this catch-all and are rendered verbatim.
- **Problem:** On any non-quota failure that isn't a pre-wrapped Exception (network drop, host-lookup failure, timeout, platform error), the raw exception string is rendered directly into the on-screen red error text. e.g. the user sees 'ClientException with SocketException: Failed host lookup...' instead of a plain Chinese message.
- **User impact:** Free and paid users on flaky mobile networks (the common dogfood/TestFlight condition) see raw English engineering error strings on the opener screen. Violates the product-language rule that errors must be plain, actionable, reassuring and never leak engineering vocabulary. Also no retry button is shown — the error only clears when the user re-edits an input field (input listener at line 138).
- **Suggested fix:** In the catch-all, map unrecognized exceptions to a fixed Chinese fallback ('開場暫時生成失敗，請稍後再試；本次不會扣額度。') instead of e.toString(). Optionally add an explicit 重試 button in the error block (lines 647-659) that re-runs generation, since input-edit-to-clear is non-obvious.
- **Effort:** <30min · **Risk if fixed:** Touches the opener (a core flow). Low regression risk: only changes the failure-copy branch, not quota/charge logic. Verify the quota-exceeded path (line 453) still surfaces its specific message and still routes to paywall. · **Needs Eric taste:** no

#### DATA-02 — P1 · contentDesign · 🎨 **TASTE**
- **Screen/Flow:** opening_rescue_screen.dart — opener generation loading state
- **Evidence (`code-verified`):** lib/features/opener/presentation/screens/opening_rescue_screen.dart:636-641 loading label is hardcoded 'AI 正在分析...'. This screen GENERATES openers (開場救星), it does not analyze the user. Contrast with the analyze flow which uses on-your-side coach copy (streaming_analysis_loading_widgets.dart:20-26: '正在讀取對話脈絡...','整理下一步建議...').
- **Problem:** The opener loading copy says 'AI 正在分析...' — both factually wrong (it is generating an opener, not analyzing) and tonally a 'tool analyzing you' frame, which snapshot.md explicitly says to avoid in favor of a coach-on-your-side voice.
- **User impact:** Every user who generates an opener sees a generic 'AI analyzing' tool-feel string during the wait, weakening the '你專屬的 AI 約會教練' positioning at a core moment.
- **Suggested fix:** Replace with coach-voiced generation copy consistent with the analyze flow, e.g. '正在幫你想開場白...' or a short rotating set ('讀取對方資料...','調出 5 種風格...','挑出最適合的一句...').
- **Effort:** <30min · **Risk if fixed:** None functional — pure copy. No quota/paywall/auth impact. · **Needs Eric taste:** yes

#### DATA-03 — P2 · Review · 🎨 **TASTE**
- **Screen/Flow:** booster_purchase_sheet.dart + message_booster.dart — Message Booster sheet
- **Evidence (`code-verified`):** booster_purchase_sheet.dart is entirely English in a zh-Hant app: 'Message Booster' (l44), 'Preview the planned one-time packages. Purchase is not live yet.' (l51), 'This sheet is read-only for now. RevenueCat booster IAP still needs to be integrated before any purchase can complete.' (l67), 'Coming Soon' (l83), 'Per message X NTD' (l128). message_booster.dart:33 `label => '$messageCount messages'`, l42/44 'Save 15%'/'Save 23%'. Grep confirms showBoosterPurchaseSheet/BoosterPurchaseSheet have NO callers outside their own file — the sheet is currently dead code.
- **Problem:** A fully English, engineering-vocab-leaking purchase sheet ('RevenueCat booster IAP', 'read-only for now') exists in the subscription feature. It is unreachable today, but it is a latent App Review / brand-consistency defect the moment anyone wires it to the paywall (the paywall headline '方案與額度' already implies booster/額度 top-ups).
- **User impact:** If shipped/wired, Traditional-Chinese users see an all-English sheet exposing internal integration status ('RevenueCat booster IAP still needs to be integrated') — App Review red flag for an incomplete/placeholder IAP surface, and off-brand.
- **Suggested fix:** Either delete the dead booster sheet + entity until the booster IAP is real, or fully translate it to zh-Hant and strip engineering vocab BEFORE wiring any entry point. Do not surface a 'Coming Soon' placeholder IAP in an App Review build.
- **Effort:** <30min to delete; ~1h to localize · **Risk if fixed:** Low. It is unreferenced, so deletion cannot regress live UX. If localizing instead, ensure no entry point gets added that could be read as a non-functional IAP during review. · **Needs Eric taste:** yes

#### DATA-04 — P2 · Pay
- **Screen/Flow:** paywall_screen.dart — feature comparison table vs option cards
- **Evidence (`code-verified`):** paywall_screen.dart:546-547 hardcodes the comparison table quota literals: '每日額度' row '15 則 / 50 則 / 120 則' and '每月額度' row '30 則 / 300 則 / 800 則'. The option cards directly above (lines 71-118) instead interpolate SubscriptionTierHelper.limitsFor(...).monthly/.daily. The hardcoded literals currently match app_constants.dart (free 30/15, starter 300/50, essential 800/120), so today they are consistent.
- **Problem:** Two sources of truth for the same quota numbers on the same screen: the option highlights are data-driven from the tier helper, the comparison table is string literals. A future quota/pricing change to AppConstants will silently update the cards but leave the comparison table stale, producing contradictory quota figures within one paywall.
- **User impact:** Latent: after any limit change, users could see e.g. '每月 300 則' in the Starter card but a different number in the comparison row, eroding trust at the purchase decision point. Also a paper-trail risk per the project's policy-change rule.
- **Suggested fix:** Drive the comparison table's 每日/每月 rows from SubscriptionTierHelper.limitsFor(free/starter/essential) instead of literals, so all paywall quota figures share one source.
- **Effort:** <30min · **Risk if fixed:** Low and isolated to display. Touches paywall but not purchase/entitlement logic; verify the table still renders Free column (helper must be queried for the free tier). · **Needs Eric taste:** no

#### DATA-05 — Polish · Inter
- **Screen/Flow:** opening_rescue_screen.dart / analysis_service.dart — server raw error passthrough
- **Evidence (`code-verified`):** opener_service.dart:404-405 `_nonQuotaErrorMessage` returns the server's raw `errorData['error']` string verbatim when no localized `message` is present: `return error == null || error.isEmpty ? '開場產生失敗，請稍後再試。' : error;`. That string is then shown via the screen error text (DATA-01 path).
- **Problem:** When the Edge Function returns an error payload with an `error` field but no `message` field, the opener UI displays the server's raw `error` string, which may be English/technical (e.g. a backend code or stack fragment).
- **User impact:** Edge-case: a malformed/older error payload shape surfaces backend wording to the user. Low frequency but same class of leak as DATA-01.
- **Suggested fix:** Prefer localized `message`; if absent, fall back to a fixed Chinese string by status class rather than echoing the raw `error` field. Reserve the raw `error` for debugPrint only.
- **Effort:** <30min · **Risk if fixed:** Low. Only changes the no-message fallback branch; does not affect the 429/quota branch (lines 340-352) which already builds localized copy. · **Needs Eric taste:** no

---

## 5. Copywriting Findings

Dedicated copy pass + every copywriting-category finding from screen clusters. Full detail in §4.

- **A-05 (P1, taste)** — MainShell (post-login home shell) — copy + nav: The home shell positions the app as a tracking/reporting tool (首頁/報告/學習 + 'add a person'), not as a coach on your side. The headline moat 'it remembers and converges you on a better next move' is absent from the nav. A first-time post-login… → _Fix:_ Reframe nav/CTA toward coaching: make the primary action '貼上對話 / 截圖,讓教練幫你' (analyze/opener entry) rather than '新增對象', or rename the AppBar/first tab to lead with the coach value. S…
- **H-03 (P1)** — BoosterPurchaseSheet — descriptive copy: Internal engineering status ('read-only', 'RevenueCat booster IAP still needs to be integrated') is shown verbatim to end users, violating the product-language rule against leaking RevenueCat/integration vocabulary. It reads like a develope… → _Fix:_ Remove the integration-status sentence. If the feature must be visible pre-launch, say only '加購包即將推出，敬請期待' in plain user language. Best: gate the sheet behind a feature flag so it …
- **COPY-01 (P1)** — Manual / screenshot analysis (analysis_service.dart MonthlyLimitExceededException + DailyLimitExceededException, surfaced via streaming_analyze_notifier.dart:247 and AnalysisException.message): The word '免費' (free) is hardcoded into the quota-exhausted message but the exception fires for ALL tiers. A paying Starter/Essential user who hits their paid monthly cap (e.g. 800/month) is told '本月免費額度已用完' — they have no free quota; they p… → _Fix:_ Remove '免費' from the default messages: '今日額度已用完，可以明天再試，或升級解鎖更多分析。' and '本月額度已用完，升級後可以繼續分析。' Keep the friendlier tier-aware override in analysis_screen as the primary path. Free-vs-…
- **COPY-02 (P1)** — Manual / screenshot analysis error states (analysis_service.dart format-failure throws): These error strings leak engineering vocabulary the snapshot rules explicitly ban for users: '回傳格式異常' (response schema/format abnormal), '回應格式錯誤' (response format error), '串流分析' (streaming analysis = internal pipeline name). To a dating-app… → _Fix:_ Replace all with plain, reassuring, non-technical copy, e.g. '這次分析沒順利完成，沒有扣到額度，請再試一次。' Drop '格式異常/格式錯誤/串流分析' entirely from anything that can reach AnalysisErrorWidget.message. If y…
- **B-05 (P2, taste)** — 'AI 正在分析...' loading state + 'AI 推薦' badge + 'AI 推薦理由' (build, _buildResults): The loading and recommendation copy frames the product as 'AI analyzing' rather than a coach helping. '分析' here even reads as analyzing the user's situation, which is precisely the tool-like framing the product-language rule warns against. … → _Fix:_ Reword loading to coach voice, e.g. '教練正在幫你想開場…', and consider '教練建議' instead of 'AI 推薦' / 'AI 推薦理由'. Pure string change.
- **F-06 (P2, taste)** — PartnerHeatHeroCard / PartnerRadarSummaryCard / PartnerListCard heat labels: A bare numeric heat score (and '5 維' radar) leans toward the 'tool analyzing the person' register that snapshot.md warns against, rather than 'coach helping you read the relationship'. '5 維' is mildly engineering-flavored. The number is pre… → _Fix:_ Taste call — consider demoting the raw number visually relative to the deterministic label ('升溫中'), and rename '5 維' to plainer language. Keep the read-only/no-synthesis contract.
- **H-05 (P2, taste)** — AiDataSharingConsent dialog: Engineering/vendor terms ('Supabase Edge Functions', 'Anthropic Claude API') surface to users, which the product-language rule lists as defects. Also a visual-system mismatch vs the rest of the cluster's dialogs. → _Fix:_ Keep the honest disclosure that data goes to a third-party AI provider (Anthropic Claude) but soften infra wording: drop 'Supabase Edge Functions' or rephrase to '我們的伺服器'. Consider…
- **COPY-03 (P2, taste)** — Paywall (paywall_screen.dart info cards + snackbars): Repeated use of '同步' (sync) and '異常' (abnormal) leaks engineering vocabulary onto the paywall — the most conversion-sensitive and App-Review-scrutinized screen. '方案同步異常' reads as a system error message, not as customer-facing reassurance. T… → _Fix:_ Soften to plain language: '方案同步異常' -> '暫時讀不到你最新的方案狀態'; '正在同步方案資訊' -> '正在載入方案'; 'App Store 價格同步逾時' -> '讀取 App Store 價格逾時'; '已重新同步訂閱狀態' -> '已更新訂閱狀態'. Avoid '同步/異常' on user-facing pay…
- **COPY-04 (P2, taste)** — Paywall footer (paywall_screen.dart:393-398 '複製訂閱診斷' button, :1206 '訂閱診斷已複製'): '複製訂閱診斷' (copy subscription diagnostics) is a developer/support affordance exposing engineering vocabulary ('診斷' = diagnostics) and an internal JSON payload, placed in the consumer legal/links row of the paywall. It reads as unfinished/engi… → _Fix:_ Gate the '複製訂閱診斷' button behind kDebugMode or the test-account flag (the codebase already has isTestAccount plumbing in analysis_screen and _showTelemetryDiagnostics => kDebugMode …
- **C-09 (Polish)** — ScreenshotAddedFeedbackCard (screenshot_added_feedback_card.dart): '串流' is implementation vocabulary. Users do not need to know the response is streamed; it adds nothing and breaks the coach persona. → _Fix:_ Drop '串流': e.g. '最後一則是她說。按「分析新增內容」，我就開始幫你整理下一步與完整分析。' Grep the cluster for other '串流' user-facing strings while here.
- **C-10 (Polish, taste)** — ScreenshotAddedFeedbackCard + ScreenshotRecognitionDialog speaker chips: Hardcoded '她' assumes a female counterpart and male user across every analyze-input surface. This is a product-positioning/inclusivity decision baked into UI strings, and could surface in App Review or alienate non-hetero users. → _Fix:_ Eric to decide scope. Minimum: a neutral '對方' for the counterpart instead of '她' in chips/avatars/hints; or a per-conversation counterpart-gender setting. Not necessarily a launch …
- **D-09 (Polish, taste)** — enthusiasm_gauge.dart:31 + game_stage_indicator labels: '$score/100' and the numbered 5-stage funnel read slightly game-y/metric-forward rather than coach-voiced. score_hero_card already softens this with a sentence ('對話偏冷，需要換個方式'); the bare gauge does not. Minor tension with 'coach on your side… → _Fix:_ Pair the gauge number with a short coach line like score_hero_card does, or prefer score_hero_card over the bare enthusiasm_gauge in the result.
- **COPY-05 (Polish, taste)** — Paywall feature comparison table (paywall_screen.dart:541): In the '回覆風格' (reply styles) row, the Free tier value is just '延展' with no qualifier, while Starter/Essential say '全部 5 種'. '延展' alone is ambiguous — a user cannot tell it means 'only the 延展 style (1 of 5)'. Onboarding lists the five styles… → _Fix:_ Make the Free value explicit and parallel, e.g. '僅延展 1 種' or '延展（1 種）', so it reads against '全部 5 種'.
- **COPY-06 (Polish, taste)** — Warm-theme glass surfaces app-wide (paywall, login, opener) — glassTextHint #8B4557 / glassTextSecondary #6C5A6B on glassWhite #F5F0F8; unselectedText #5D4E6B on warm gradient: I cleared the two named glass suspects — glassTextHint/glassTextSecondary on glassWhite actually pass AA (6.06 / 5.65), so flagging them would be a false positive. The real risk is unselectedText #5D4E6B: on the warm dark gradient it comput… → _Fix:_ Audit each unselectedText usage for its actual background. For any on the gradient (not on glassWhite), switch to onBackgroundSecondary #E0D0E8 or a lighter token. Do not change th…

---

## 6. RWD Findings

Layout/responsive findings (full detail in §4). Note: deep RWD is mostly `native-risk` — verify on real SE / tablet widths.

- **B-01 (P1)** — OpeningRescueScreen body (Scaffold inside GradientBackground): There is no `SafeArea` (or `MediaQuery.viewPadding.bottom`) wrapping the scrollable content. On devices with a home indicator / gesture bar, the trailing content and the final '她回覆了，開始分析對話' FilledButton can sit very close to or under the ge… → _Fix:_ Wrap the body's Column (or the SingleChildScrollView) content in a SafeArea(top:false) or add `MediaQuery.of(context).padding.bottom` to the trailing SizedBox so the last CTA clear…
- **C-04 (P1)** — ScreenshotRecognitionDialog — message editor scroll area (screenshot_recognition_dialog.dart): Nested vertical scroll (ListView inside SingleChildScrollView) with a hard 220px floor inside a keyboard-shrunk AlertDialog risks the inner editor and the action buttons ('確認加入對話') being pushed off-screen or the inner list stealing the drag… → _Fix:_ Replace the AlertDialog with a full-height DraggableScrollableSheet / bottom sheet for this dense editor, or lower the inner floor and rely on a single outer scroll with scroll-to-…
- **B-04 (P2)** — Opener cards horizontal list (_buildResults / _buildOpenerCard): With larger system font sizes (Dynamic Type / accessibility text scaling), AppTypography.bodyMedium at height 1.6 inside a fixed 220px card will exceed 6 lines and silently ellipsis-truncate the actual opener line — the paid deliverable the… → _Fix:_ Let the card height be intrinsic (wrap list in a height that derives from content, or use a vertical layout / expandable card for the recommended opener) and/or scale the 220 heigh…
- **D-05 (P2)** — reply_style_card.dart (horizontal carousel card): Each reply-style card is a fixed 312pt wide. On a 320pt-logical small phone (iPhone SE) the card is 312 + 12 margin = 324 > viewport, so peeking/snapping is off and content nearly fills the screen edge-to-edge; on tablet the cards stay tiny… → _Fix:_ Derive width from MediaQuery (e.g. min(312, screenWidth*0.82)) so a consistent peek shows on all sizes; cap on tablet.
- **D-06 (P2, taste)** — reply_style_card.dart inner message rows: Dark message chips sit inside a light glass card — a card-in-card with inverted polarity. Internally the dark-box white-text contrast is fine, but the polarity flip between the card body (light) and its message chips (dark) is visually nois… → _Fix:_ Make message chips a light tinted surface consistent with the glass card (e.g. white with low alpha + glassTextPrimary), matching message_bubble's incoming-bubble treatment.
- **E-04 (P2, taste)** — CoachChatCard result + history (dense Column on small screens): Message density is very high for one coach answer. On a small phone the 'one clear next move' moat is buried under ~7 metadata _InfoLine rows plus an outcome-capture block the user must scroll past every turn. The signal (next step + sugges… → _Fix:_ Lead with headline + 這次先做 + suggested line; collapse the diagnostic rows (卡點/卡在/真實想法/教練判斷) behind a '看教練怎麼判讀' expander like the history tiles already do; consider deferring the out…
- **G-05 (P2)** — stage_distribution_chart (donut + legend); heat_trend_chart; conversation_comparison_chart on small screens: The donut Row reserves a hard 140+24=164px before the legend's Expanded; on a 320pt-wide device inside 16px card padding the legend column gets very little width, and Chinese stage names + counts can wrap/cramp. The 72px conversation-name c… → _Fix:_ Make the donut size responsive (e.g. min(140, constraints.maxWidth*0.38)) and let conversation name width flex (Flexible instead of fixed 72, or 2-line). Confirm on 320pt width. Ch…
- **H-04 (P2)** — BoosterPurchaseSheet — bottom sheet layout: No scroll wrapper and no SafeArea bottom inset on a content-heavy bottom sheet. On small devices (SE-class) the stacked content can exceed available height and clip the button / collide with the home indicator. → _Fix:_ Wrap the Column in SingleChildScrollView and add SafeArea(top:false) (or MediaQuery viewInsets/padding bottom) so the sheet never clips.
- **A-08 (Polish)** — MainShell AppBar over GradientBackground: A bright animated pink blob drifts behind the transparent AppBar where the 'VibeSync' title (white) and settings icon sit. On the lighter part of the gradient/blob, white-on-pink contrast for the title and icon may dip, and the moving blob … → _Fix:_ Add a subtle scrim/blur behind the AppBar (or a soft top-down dark gradient) so title+settings stay legible regardless of blob position. Confirm on a real device.

---

## 7. Motion / Loading Findings

Full detail in §4.

- **A-02 (P2, taste)** — SplashScreen: A hard 3.5s branded splash gates EVERY cold start, and it is pure decoration — all real initialization completed before the widget tree even built. Returning users (the dogfood cohort) eat 3.5s every launch before reaching their task. No ta… → _Fix:_ Cut the total sequence to ~1.6-2.0s (title + tagline land, then exit), and/or add a GestureDetector that calls widget.onComplete() on tap. Consider showing splash only on first lau…
- **B-06 (P2)** — Error state in build() (line 647-659): A generic exception's `.toString()` is shown directly. If the OpenerService ever throws a message containing engineering vocabulary (schema/JSON/responseMode/error code) or an untranslated server/network string, it leaks straight to the use… → _Fix:_ Map non-quota exceptions to a small set of friendly Chinese messages (network vs server vs format) before assigning `_error`, never surface a raw `.toString()`, and add a '再試一次' af…
- **D-07 (P2)** — All result cards (loading/empty/error states): The cards are pure presentation with no defensive state. If analyze returns partial/malformed schema (a known high-risk zone), these widgets either render empty boxes or risk RangeError (radar titles[index]). There is no styled 'something w… → _Fix:_ Add a shared graceful fallback (partial-data placeholder + guard radar to default missing dimensions to 0) and ensure the parent screen shows a styled error card on schema failure.…
- **E-03 (P2, taste)** — CoachChatCard — streaming / thinking state (_CoachThinkingNotice) and submit button spinner: The core product is a 'coach chatting with you', but the loading model is request/response with a spinner, not a streamed/typing feel. The analysis screen above it DOES stream (StreamingAnalysisLoader at analysis_screen.dart:5665), so the c… → _Fix:_ Either stream the answer text token-by-token like analyze-chat, or add a lightweight typing/ellipsis animation and a skeleton of the labelled rows so the card feels alive. Keep the…
- **F-04 (P2)** — PartnerMergePickerScreen / merge + delete flows (loading state): Merge, direct-dedupe-merge, and partner delete have no loading/disabled state during the async Hive write. On a slow device the user can double-tap '確認合併'/'立即合併' or sit on an unresponsive screen with no feedback. → _Fix:_ Add a busy flag around merge/delete confirm like AddPartner already does: disable the confirm button and show a spinner while the controller call is in flight.

---

## 8. Data-State / Quota / Paywall UI Findings

Dedicated data-state pass + paywall/quota findings. Full detail in §4.

- **G-03 (P1, taste)** — my_report_screen _lockedReportCard (free-user paywall card): The paywall promises a '五維雷達圖' (5-dimension radar chart) that the product does not contain. After paying, the user never sees a radar — only a trend line, bar comparison, and donut. This is a feature over-promise in a purchase-driving surfa… → _Fix:_ Either (a) change copy to describe what actually ships ('歷史熱度趨勢、對話比較、階段分佈') or (b) build the radar. For launch, fix the copy. Coordinate with pricing-final.md if the radar was a pr…
- **DATA-01 (P1)** — opening_rescue_screen.dart — opener generation error state: On any non-quota failure that isn't a pre-wrapped Exception (network drop, host-lookup failure, timeout, platform error), the raw exception string is rendered directly into the on-screen red error text. e.g. the user sees 'ClientException w… → _Fix:_ In the catch-all, map unrecognized exceptions to a fixed Chinese fallback ('開場暫時生成失敗，請稍後再試；本次不會扣額度。') instead of e.toString(). Optionally add an explicit 重試 button in the error blo…
- **DATA-02 (P1, taste)** — opening_rescue_screen.dart — opener generation loading state: The opener loading copy says 'AI 正在分析...' — both factually wrong (it is generating an opener, not analyzing) and tonally a 'tool analyzing you' frame, which snapshot.md explicitly says to avoid in favor of a coach-on-your-side voice. → _Fix:_ Replace with coach-voiced generation copy consistent with the analyze flow, e.g. '正在幫你想開場白...' or a short rotating set ('讀取對方資料...','調出 5 種風格...','挑出最適合的一句...').
- **DATA-03 (P2, taste)** — booster_purchase_sheet.dart + message_booster.dart — Message Booster sheet: A fully English, engineering-vocab-leaking purchase sheet ('RevenueCat booster IAP', 'read-only for now') exists in the subscription feature. It is unreachable today, but it is a latent App Review / brand-consistency defect the moment anyon… → _Fix:_ Either delete the dead booster sheet + entity until the booster IAP is real, or fully translate it to zh-Hant and strip engineering vocab BEFORE wiring any entry point. Do not surf…
- **DATA-04 (P2)** — paywall_screen.dart — feature comparison table vs option cards: Two sources of truth for the same quota numbers on the same screen: the option highlights are data-driven from the tier helper, the comparison table is string literals. A future quota/pricing change to AppConstants will silently update the … → _Fix:_ Drive the comparison table's 每日/每月 rows from SubscriptionTierHelper.limitsFor(free/starter/essential) instead of literals, so all paywall quota figures share one source.
- **DATA-05 (Polish)** — opening_rescue_screen.dart / analysis_service.dart — server raw error passthrough: When the Edge Function returns an error payload with an `error` field but no `message` field, the opener UI displays the server's raw `error` string, which may be English/technical (e.g. a backend code or stack fragment). → _Fix:_ Prefer localized `message`; if absent, fall back to a fixed Chinese string by status class rather than echoing the raw `error` field. Reserve the raw `error` for debugPrint only.

---

## 9. AI Template / Generic Design Risk

The warm-theme tokens (gradient/bokeh/glass/purple) ARE the brief's named AI-slop signals. These are taste calls — see §3b bucket 2.

- **B-03 (P1, taste)** — Whole screen — GradientBackground bokeh orbs + glass cards: The opener (a core, high-frequency flow) leans hard on every named AI-slop token at once: animated bokeh orbs, purple gradient bg, and stacked glass cards (analysis card + opener cards + reason card + pioneer card + saved-draft notice + nex… → _Fix:_ Eric decision: either dial the bokeh opacity/animation down (or freeze it while the keyboard is open / during scroll), reduce the number of stacked glass cards by merging the saved…
- **F-02 (P1, taste)** — AddPartnerScreen + PartnerDetailScreen background: These screens lean directly into Eric's stated AI-slop aversions: purple gradient backgrounds, bokeh blobs, and a purely decorative orb with no data binding. The _HeatOrb in particular is a meaningless decorative element sitting next to the… → _Fix:_ This is a taste call, not an objective bug. Recommend dialing the bubble opacities down hard (AddPartner uses 0.55/0.5/0.4 — quite strong) and reconsidering whether the _HeatOrb ea…
- **A-06 (P2, taste)** — GradientBackground (used by Login + MainShell) and SplashScreen: Both entry surfaces lean hard on purple/blue gradients + bokeh blobs + over-glassmorphism — the exact 'generic AI app' aesthetic Eric dislikes. It is decorative motion with no informational role, running continuously (battery + 'template fe… → _Fix:_ This is a taste call, not an objective bug: decide how much bokeh/glow survives. If trimming, reduce blob count/opacity and freeze the pulse after entrance. Flagging the tension, n…
- **C-06 (P2, taste)** — FullAnalysisRetryCard (streaming_analysis_loading_widgets.dart) within analysis_screen: Within one analyze-chat result view, the error/retry surfaces mix three idioms: a glossy purple-gradient+bokeh+shadow retry card, a flat red error card, and flat Material loader text. The retry card leans hardest into the named AI-slop toke… → _Fix:_ Eric to decide the house style for failure cards. If keeping the warm theme, calm the retry card (drop the boxShadow glow and the bokeh icon chip, flatten the gradient) and bring A…
- **D-08 (Polish, taste)** — final_recommendation_card.dart: This card leans on exactly the brand's stated AI-slop aversions: a purple gradient panel plus a row of decorative emoji icons. It reads as the 'generic AI result card' template. → _Fix:_ Drop the purple gradient for a warm-glass treatment (ties to D-03), replace emoji with restrained typographic labels or a single meaningful accent.
- **G-07 (Polish, taste)** — article_detail_screen content rendering / GradientBackground glass theme: This is the cluster's strongest lean into the named warm-theme tokens Eric flags as AI-slop: full-screen purple→pink gradient, multiple stacked glass cards, and several decorative outline icons (lightbulb/near_me) used purely as labels. The… → _Fix:_ Consider flattening article body to one calm reading surface (single card or no card), reserve glass cards only for the two practice CTAs, and drop the lightbulb/near_me decorative…
- **H-07 (Polish, taste)** — PaywallScreen — top free-form copy and bg motion / aiSlop: The paywall — the highest-stakes conversion screen — leans on animated bokeh blobs + glassmorphism + purple/pink gradients, the precise aesthetic Eric has flagged as 'generic/template feel'. → _Fix:_ Consider freezing or removing the bokeh animation on the paywall specifically (static gradient, or pause controllers) and dialing back decorative motion behind pricing/consent. Bra…

---

## 10. Quick Wins under 30 minutes

Low-risk, high-ratio fixes CC can batch:

- **B-01 (P1)** OpeningRescueScreen body (Scaffold inside GradientBackground): Wrap the body's Column (or the SingleChildScrollView) content in a SafeArea(top:false) or add `MediaQuery.of(context).padding.bottom` to the trailing SizedBox so the last CTA clears the gesture bar on
- **B-02 (P1)** Recent drafts card draft row + opener helper rows (_buildDraftRow, _buildNextStepRow, _buildProfileAnalysisItems, _buildPioneerPlanCard): Either raise the draft-row glass alpha toward opaque (so hint text sits on a light surface as designed), or swap glassTextHint for glassTextSecondary on the semi-transparent rows, or pin a solid light
- **C-01 (P1)** ImagePickerWidget helper text (rendered in analysis_screen screenshot setup + opening_rescue_screen): Swap glassTextHint for an on-dark token (AppColors.onBackgroundSecondary #E0D0E8 or Colors.white@0.6) in image_picker_widget.dart for the helper texts and the '選圖'/'壓縮中' labels (which use unselectedTe
- **C-02 (P1)** ConversationTile (conversation_tile.dart): Confirm whether ConversationTile is still routed anywhere. If dead, delete it. If live, wrap it in a GlassmorphicContainer (so the glass tokens are correct) OR re-token it to the flat dark system (tex
- **C-03 (P1)** Manual new-conversation (new_conversation_screen.dart) vs Screenshot recognition dialog (screenshot_recognition_dialog.dart): Unify the field label to one term (pick 認識情境 or 認識場景 and use everywhere — '場景' reads slightly better). Consider extracting a shared SessionContextFields widget so both surfaces use identical controls 
- **D-02 (P1)** All warm-glass cards: score_hero_card, dimension_radar_chart, game_stage_indicator, reply_style_card (accent/label text): Use a darker coral (e.g. #C2410C-ish) for text-on-glass, reserve #FF7043 for fills/gradients/borders only. Add a dedicated ctaTextOnGlass token.
- **E-01 (P1)** CoachFollowUpSection (_buildDefault caption + _buildWithResult line 408) and CoachFollowUpChipRow (hint + 額度 caption): Swap glassTextSecondary → onBackgroundSecondary (#E0D0E8, measured 13.6:1) for these three on-dark captions/hints. No layout change.
- **F-03 (P1)** AddPartnerScreen text intro + GlassmorphicTextField: Verify GlassmorphicTextField hint color on device against its actual fill; if it uses glassTextHint, confirm >=4.5:1 and bump if borderline.
- **G-03 (P1)** my_report_screen _lockedReportCard (free-user paywall card): Either (a) change copy to describe what actually ships ('歷史熱度趨勢、對話比較、階段分佈') or (b) build the radar. For launch, fix the copy. Coordinate with pricing-final.md if the radar was a promised tier feature.
- **H-03 (P1)** BoosterPurchaseSheet — descriptive copy: Remove the integration-status sentence. If the feature must be visible pre-launch, say only '加購包即將推出，敬請期待' in plain user language. Best: gate the sheet behind a feature flag so it never ships visible.
- **COPY-01 (P1)** Manual / screenshot analysis (analysis_service.dart MonthlyLimitExceededException + DailyLimitExceededException, surfaced via streaming_analyze_notifier.dart:247 and AnalysisException.message): Remove '免費' from the default messages: '今日額度已用完，可以明天再試，或升級解鎖更多分析。' and '本月額度已用完，升級後可以繼續分析。' Keep the friendlier tier-aware override in analysis_screen as the primary path. Free-vs-paid distinction, if
- **COPY-02 (P1)** Manual / screenshot analysis error states (analysis_service.dart format-failure throws): Replace all with plain, reassuring, non-technical copy, e.g. '這次分析沒順利完成，沒有扣到額度，請再試一次。' Drop '格式異常/格式錯誤/串流分析' entirely from anything that can reach AnalysisErrorWidget.message. If you want a distinct r
- **DATA-01 (P1)** opening_rescue_screen.dart — opener generation error state: In the catch-all, map unrecognized exceptions to a fixed Chinese fallback ('開場暫時生成失敗，請稍後再試；本次不會扣額度。') instead of e.toString(). Optionally add an explicit 重試 button in the error block (lines 647-659) t
- **DATA-02 (P1)** opening_rescue_screen.dart — opener generation loading state: Replace with coach-voiced generation copy consistent with the analyze flow, e.g. '正在幫你想開場白...' or a short rotating set ('讀取對方資料...','調出 5 種風格...','挑出最適合的一句...').
- **A-02 (P2)** SplashScreen: Cut the total sequence to ~1.6-2.0s (title + tagline land, then exit), and/or add a GestureDetector that calls widget.onComplete() on tap. Consider showing splash only on first launch / cold start.
- **A-04 (P2)** SplashScreen subtitle '你專屬的 AI 約會教練': Raise tagline opacity to ~0.7-0.8 once its entrance animation settles, or bump weight/size. Keep the fade-in but land it at a legible final alpha.
- **B-05 (P2)** 'AI 正在分析...' loading state + 'AI 推薦' badge + 'AI 推薦理由' (build, _buildResults): Reword loading to coach voice, e.g. '教練正在幫你想開場…', and consider '教練建議' instead of 'AI 推薦' / 'AI 推薦理由'. Pure string change.
- **C-08 (P2)** ScreenshotRecognitionDialog editable message card (screenshot_recognition_dialog.dart): Replace 0xFFF0EAF5 with a named token (or surfaceVariant of the glass system). Bump hint/secondary text to glassTextSecondary #6C5A6B at minimum, and verify the composited contrast on-device. Make the
- **D-05 (P2)** reply_style_card.dart (horizontal carousel card): Derive width from MediaQuery (e.g. min(312, screenWidth*0.82)) so a consistent peek shows on all sizes; cap on tablet.
- **D-06 (P2)** reply_style_card.dart inner message rows: Make message chips a light tinted surface consistent with the glass card (e.g. white with low alpha + glassTextPrimary), matching message_bubble's incoming-bubble treatment.
- **F-05 (P2)** PartnerListScreen empty state: Add a primary CTA button ('+ 新增第一張對象卡') directly in the empty state that routes to /partner/new, so the instruction and the action are co-located.
- **H-04 (P2)** BoosterPurchaseSheet — bottom sheet layout: Wrap the Column in SingleChildScrollView and add SafeArea(top:false) (or MediaQuery viewInsets/padding bottom) so the sheet never clips.
- **H-06 (P2)** PaywallScreen / SettingsScreen — quota & usage pills, feature comparison Free column: Give the quota/usage pill an explicit opaque light fill (e.g. solid glassWhite-tinted color) instead of white@0.42, so legibility no longer depends on the parent container staying opaque.
- **COPY-03 (P2)** Paywall (paywall_screen.dart info cards + snackbars): Soften to plain language: '方案同步異常' -> '暫時讀不到你最新的方案狀態'; '正在同步方案資訊' -> '正在載入方案'; 'App Store 價格同步逾時' -> '讀取 App Store 價格逾時'; '已重新同步訂閱狀態' -> '已更新訂閱狀態'. Avoid '同步/異常' on user-facing paywall copy.
- **COPY-04 (P2)** Paywall footer (paywall_screen.dart:393-398 '複製訂閱診斷' button, :1206 '訂閱診斷已複製'): Gate the '複製訂閱診斷' button behind kDebugMode or the test-account flag (the codebase already has isTestAccount plumbing in analysis_screen and _showTelemetryDiagnostics => kDebugMode as precedent). If it
- **DATA-03 (P2)** booster_purchase_sheet.dart + message_booster.dart — Message Booster sheet: Either delete the dead booster sheet + entity until the booster IAP is real, or fully translate it to zh-Hant and strip engineering vocab BEFORE wiring any entry point. Do not surface a 'Coming Soon' 
- **DATA-04 (P2)** paywall_screen.dart — feature comparison table vs option cards: Drive the comparison table's 每日/每月 rows from SubscriptionTierHelper.limitsFor(free/starter/essential) instead of literals, so all paywall quota figures share one source.
- **A-08 (Polish)** MainShell AppBar over GradientBackground: Add a subtle scrim/blur behind the AppBar (or a soft top-down dark gradient) so title+settings stay legible regardless of blob position. Confirm on a real device.
- **C-09 (Polish)** ScreenshotAddedFeedbackCard (screenshot_added_feedback_card.dart): Drop '串流': e.g. '最後一則是她說。按「分析新增內容」，我就開始幫你整理下一步與完整分析。' Grep the cluster for other '串流' user-facing strings while here.
- **D-09 (Polish)** enthusiasm_gauge.dart:31 + game_stage_indicator labels: Pair the gauge number with a short coach line like score_hero_card does, or prefer score_hero_card over the bare enthusiasm_gauge in the result.
- **F-07 (Polish)** PartnerDetailScreen partner-not-found state: Add an AppBar with a back button and a friendlier line ('這個對象已經整理掉了'); optionally a button back to the list.
- **F-08 (Polish)** SameNameDedupeBanner / PartnerDataQualityBanner secondary action: No contrast fix needed (passes). Confirm intentionally that 'split' should be the quiet option vs 'same person' as primary. Taste-level.
- **G-08 (Polish)** article_detail_screen read-gate / not-found state: Give the not-found state an AppBar with back + the GradientBackground, and a friendly line. Optionally add a short caption under the gate spinner. Keep paywall redirect logic untouched.
- **COPY-05 (Polish)** Paywall feature comparison table (paywall_screen.dart:541): Make the Free value explicit and parallel, e.g. '僅延展 1 種' or '延展（1 種）', so it reads against '全部 5 種'.
- **DATA-05 (Polish)** opening_rescue_screen.dart / analysis_service.dart — server raw error passthrough: Prefer localized `message`; if absent, fall back to a fixed Chinese string by status class rather than echoing the raw `error` field. Reserve the raw `error` for debugPrint only.

---

## 11. Bigger Creative Direction Suggestions

- **Resolve to a single 'coach' identity, not two themes.** The strongest path: keep ONE warm, intimate surface (the partner-detail '深夜陪你讀懂這段關係' mood is the best instinct in the codebase) and let *that* set the whole app's tone — warm dark, low-chroma, one accent. Retire the flat-Material screens into it rather than maintaining two. This simultaneously fixes the consistency column and the AI-slop tension, because a deliberately warm-dark coach aesthetic is the opposite of generic glassy-purple SaaS.
- **Make the first 10 seconds say 'coach'.** Revive onboarding (or fold a one-card value-prop into post-login), and reframe the home primary action from '新增對象' (data entry) to '貼上對話，讓教練幫你' (immediate value). The moat is 'help me reply now' — lead with it.
- **Shift copy from analysis to companionship.** Replace 'AI 正在分析…' loading frames with coach-voiced lines ('教練正在幫你想怎麼接…'), soften the numeric score's prominence, and rewrite error/refusal states so the coach is *on the user's side* even when it can't help.
- **Give charts/cards emotional warmth.** The 'too black/white & emotional-dead' worry (D-04) is real for psychology_card and the flat result panels — once on one warm system, add subtle tonal hierarchy instead of flat #2D2D2D.
- **Treat the paywall as a coach recommendation, not a SaaS upsell** — drop bokeh/glass theatrics, remove the diagnostics/sync vocab, and only promise features that exist (kill the '五維雷達圖' claim).

---

## 12. Screenshots / Evidence Index

Live visual capture was attempted and BLOCKED in this sandbox, recorded honestly per the review contract:
1. The Playwright MCP server is pinned to the Chrome *channel* at `/opt/google/chrome/chrome`, which requires `sudo`/apt to install — not available.
2. The bundled Chromium binary was downloaded (`~/.cache/ms-playwright/chromium-1223`) but fails to launch: `error while loading shared libraries: libnspr4.so` — the system is missing Chromium's runtime `.so` dependencies, which need root (`playwright install-deps`).
3. No web test credentials were available, so even pre-auth flows past the login wall couldn't be reached.
The web preview (`web-beta-tawny.vercel.app`) itself returns HTTP 200, so capture is viable on a host with browser deps + a test login. Until then, every finding is `code-verified` (provable from Dart source) or `native-risk` (real concern, device-rendering-dependent). The `docs/reviews/assets/ui-audit-2026-06-09/` directory was created for screenshots and is currently empty by design.

**Evidence-type breakdown:** 66 `code-verified` · 7 `native-risk` · 0 `screenshot-verified`.

Native-risk findings (need on-device confirmation): `A-04`, `A-08`, `B-02`, `E-03`, `F-03`, `H-06`, `COPY-06`.

Per-pass provenance (which agent found what): A=8, B=6, C=10, D=9, E=6, F=8, G=8, H=7, COPY=6, DATA=5.

---

## 13. Recommended Fix Order

**0. DECIDE (Eric, ~30min)**
Taste buckets 1–5 above. Bucket 1 (color-system direction) is the gate for everything else — nothing in the contrast/consistency band should be touched until it's decided.

**1. Zero-risk quick wins (CC, batch, <2h total)**
Pure copy + single-value fixes with no logic risk: COPY-01/02, H-03, C-05 copy, DATA-02 copy, A-04, C-09, H-05, COPY-03/04. See §10 Quick Wins.

**2. Honest-claim & App-Review safety (CC, low risk)**
G-03 (remove/deliver the 五維雷達圖 claim), H-02 (translate booster sheet, remove eng-status), DATA-01/DATA-05 (never render raw exception text).

**3. Positioning (CC + Eric sign-off)**
A-01 onboarding wiring (needs redirect-matrix test — touches auth gate), then A-05 shell reframing IF Eric overrides ADR-15.

**4. The color-system convergence (CC, larger, golden-tested)**
Implement bucket-1 decision: collapse to one system, then sweep D-03/F-01/G-01/H-01/C-01/C-02/D-01/D-02/E-01/E-02/G-02 contrast fixes. Snapshot/golden the affected screens; this is the big visual-regression surface.

**5. RWD hardening (CC)**
B-01/C-04/H-04 SafeArea + scroll wrappers; D-05/G-05 small-screen fixed-width/height fixes. Verify on SE width.

**6. Polish pass (CC, post-launch ok)**
Remaining Polish-severity items and the motion/empty-state refinements.

---

## Appendix — Workflow & Method

- **Step 1 Bootstrap:** read `docs/snapshot.md`, `docs/shared-agent-rules.md`, `git log -15`, newest OPEN queue item.
- **Step 2 Inventory:** 18 screens, 12 dialogs/sheets, 16 shared widgets, app shell — full file list assigned to clusters.
- **Step 3 Evidence plan:** hybrid intended; live capture blocked → code-first with honest labels (§12).
- **Step 4 Parallel review:** 10 agents (8 screen clusters + copy pass + data-state pass), one shared 13-category rubric + identical design-system facts so scores are comparable. ~830k tokens, ~5 min.
- **Steps 5–8 Synthesis:** structured JSON returned by each agent → deduped/ranked in the main loop → this report.
- **Step 9 Report:** this file. No code was changed.
