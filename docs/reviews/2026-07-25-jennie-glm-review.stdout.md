# Adversarial Review: Jennie NotebookLM 實戰案例報告

Since no separate requirements document was provided, I treat the artifact's self-declared purpose as the requirement baseline: *「把 Jennie 的聊天實戰與真實使用者困境，轉成 VibeSync 可驗證、可安全使用的產品素材」*, plus the internal consistency of its own stated methods and recommendations.

---

## Critical Findings

### C1 — A-Level Evidence Standard Claimed but Not Demonstrated for Most "代表性閉環"

**Evidence:** The A-level definition requires *「看得到原始情境、Jennie 建議、實際送出內容、對方後續反應」*. Of the four "代表性閉環" cases presented, only Day 13 explicitly describes the sent message and the recipient's subsequent reaction (女生問去哪裡吃 → 傳位置 → 見面). Day 6, Day 7, and Day 11 describe situations and principles but do **not** show what was actually sent or what the recipient did next.

**Why it matters:** The report's central methodological claim is that it distinguishes rigorous closed-loop cases from weaker evidence. If 3 of 4 showcase "closed loops" are not actually closed loops, the grading framework is not being applied as defined, undermining the credibility of the entire evidence hierarchy.

**Verification step:** For each of Day 6, Day 7, Day 11, confirm whether the source contains (a) the actual message sent after Jennie's advice and (b) the recipient's verifiable reaction. If not, relabel them as B-level and adjust the section heading.

---

### C2 — "12 題" Evaluation Set Lacks the A/B/C Source Grading It Declares Mandatory

**Evidence:** The methodology section states every evaluation case must save *「來源等級 A/B/C，避免把假設寫成真理」*. The proposed "第一批 12 題" table contains columns for 情境, 理想決策, and 主要錯誤 — but **no A/B/C source-grade column**. None of the 12 cases cite a specific Notebook source or grade.

**Why it matters:** This is the report's single most concrete deliverable, and it immediately violates the evidence-grading rule the report itself establishes as foundational.

**Verification step:** Map each of the 12 scenarios to at least one specific Notebook source and assign an A/B/C grade. Flag any scenario that is purely synthetic (no source) as ungraded.

---

## Important Findings

### I1 — "Sonnet 5" Reference Is Unverifiable and Possibly Anachronistic

**Evidence:** P0 section: *「驗證現有 Sonnet 5 路徑是否已經能穩定做對」*. As of the knowledge cutoff, no model called "Sonnet 5" has been publicly released by Anthropic. The document is dated 2026-07-25, which is itself a future date, so this may be intentional projection — but it makes the recommendation non-actionable for any reader today.

**Why it matters:** A P0 action item that references a non-verifiable model version cannot be executed or audited.

**Verification step:** Confirm the actual model identifier and version currently in use by VibeSync's production pipeline and replace "Sonnet 5" with the verified string.

---

### I2 — Evaluation Methodology Is Undefined: Who Scores, How, Against What Baseline

**Evidence:** The report proposes 12→30 test cases and 7 scoring dimensions, but never specifies:
- Whether scoring is automated (LLM-as-judge) or human.
- How many evaluators per case and what inter-rater agreement threshold is required.
- What the **current** error rates are for the metrics listed in "可衡量的成功標準" (e.g., *「繼續追問／強推邀約」錯誤率下降* — down from what?).

**Why it matters:** Without a baseline measurement, "下降" is unmeasurable. Without a defined scoring procedure, the evaluation set cannot be reproduced.

**Verification step:** Add (a) a one-time baseline run plan against the 12 cases, (b) scoring method (human/automated/hybrid), (c) pass/fail criteria per dimension.

---

### I3 — Tension Between "Do Not Add Rules to Prompts" and Extensive Prescriptive Recommendations

**Evidence:** The report explicitly warns: *「不要把這次研究變成四個 prompt 都多一段規則」* and lists three reasons. Yet subsequent sections make feature-level prescriptions such as:
- *「Keyboard 應…對邀約、性、金錢、衝突等高影響情境降低自信」*
- *「Coach 應先問發生了什麼、使用者要什麼、界線在哪」*
- *「幽默版本應受情緒、階段與界線約束」*

These are effectively prompt-level behavioral rules.

**Why it matters:** The report's own meta-recommendation (test first, then change minimally) is contradicted by the volume and specificity of its prescriptive output. A reader cannot tell which items are "test hypotheses" versus "change the prompt now."

**Verification step:** Tag every prescriptive statement as either (H) hypothesis-to-test or (A) action-to-implement-now. Currently they are indistinguishable.

---

### I4 — "壞案例的八個根因" Lacks Specific Source Citations

**Evidence:** Unlike the "代表性閉環" section, which names specific sources (Day 13, Day 6, etc.), the eight root causes section (*把聊天變成高低位競賽*, *KPI 壓過同理心*, etc.) cites **zero specific Notebook sources**. The report itself states *「重要結論仍以可看到的原始案例為準」*.

**Why it matters:** These eight failure modes are presented as findings from the research, but without traceability they could be general knowledge rather than evidence-derived. This directly conflicts with the report's stated epistemic standards.

**Verification step:** For each of the 8 root causes, cite at least one specific Notebook source where the pattern is observable, or relabel the section as "general domain knowledge" rather than "research findings."

---

## Minor Findings

### M1 — Source Count Arithmetic Has Overlapping Ranges Totaling Less Than 166

**Evidence:** *「約 100–110 + 約 15–20 + 約 10–15 + 約 20–25 + 少量其他」* = 145–170 + "少量." The lower bound (145 + 少量) could be below 166. "少量" is undefined and could be 0–10.

**Verification step:** State the approximate count of the "少量其他" bucket so the total reconciles to 166.

---

### M2 — Document Date Is in the Future

**Evidence:** *「日期：2026-07-25」*

**Verification step:** Confirm whether this is a projected/deliberate future date or a typo. If the report is meant to be current, correct the date.

---

### M3 — The "不建議做的功能" List Partially Duplicates "不能直接搬進 VibeSync 的內容"

**Evidence:** *「將嫉妒、冷落、比較或性暗示包裝成進階技巧」* (不建議做) overlaps heavily with *「刻意製造嫉妒、不安全感或稀缺感」* and *「把尖酸、否定、比較包裝成推拉」* (不能搬進). The two sections serve slightly different purposes (content policy vs. feature roadmap) but the redundancy may cause confusion about which list governs what.

**Verification step:** Merge or clearly cross-reference the two lists, stating which is a content-policy constraint and which is a feature-backlog exclusion.

---

### M4 — No Explicit Handling of the Case Where the User Is the Problematic Party

**Evidence:** The report focuses on the user being anxious or over-eager, but the "壞案例" analysis frames failures primarily as the user's mistakes. There is no case in the 12-item evaluation set where the user exhibits stalking, harassment, or refusal to accept rejection, and the system must prioritize the *other party's* safety.

**Why it matters:** The report repeatedly emphasizes safety, but the evaluation set doesn't test the scenario where safety intervention is needed against the user.

**Verification step:** Add at least one evaluation case where the correct system behavior is to discourage continued pursuit (e.g., user has been blocked and asks how to circumvent it).

---

## Uncertain Findings

### U1 — Product Feature Claims Cannot Be Independently Verified

**Evidence:** The "對照 VibeSync 現況" table asserts the existence of specific features and parameters: *Analyze 已有 stage、heat、對話球、邀約成熟度與退場判斷*, *Coach 已有 clarifyIntent、stateCalibration、boundaryRisk、consent、boundary、stop-loss*, *Practice 已模擬冷淡、忙碌、質疑、邀約成熟度*. Without access to VibeSync's actual prompt specifications or codebase, these claims are unverifiable.

**Verification step:** Cross-reference each claimed feature/parameter against the actual VibeSync prompt architecture document or code.

---

### U2 — External Links Are Unverifiable

**Evidence:**
- NotebookLM source: `https://notebooklm.google.com/notebook/d5789623-c0c4-4715-b6ed-6316ecd277a4` — likely access-controlled.
- YouTube: `https://www.youtube.com/watch?v=FDC__eRhrlI` — cannot confirm the video exists or matches the described Day 13 content.

**Verification step:** Attempt to open both links and confirm content matches the described scenarios.

---

## What Appears Correct

1. **Core thesis is well-reasoned:** The argument that "judgment over catchphrases" and "build an evaluation set before changing prompts" is methodologically sound and internally consistent with the stated limitations.

2. **Evidence hierarchy (A/B/C) is conceptually sound** — the problem is application, not design.

3. **The "six things good cases share" and "eight root causes" are internally plausible and non-contradictory** with the stated product values (consent, safety, emotional attunement).

4. **The translation table** (測試→質疑/顧慮, 高低位→投資平衡, 通關→互信與自願, 升溫→可撤回同意) is a genuinely useful product-level reframing that aligns with safety-oriented design.

5. **The Keyboard low-context honesty gap** is correctly identified as the one area where the report concludes the product has a genuine deficiency rather than just needing regression tests.

6. **The "不做 as a visible option" recommendation** (P2) is a strong, non-obvious product insight that follows logically from the case analysis.

7. **The recommendation against fixed 三版本 generation** is consistent with the report's broader argument against template-driven interaction.
