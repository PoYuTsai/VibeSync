# Spec 4 Learning Content Refresh Design

> Status: Draft for alignment  
> Date: 2026-05-04  
> Scope: Spec 4 Phase 1.5 learning article curation, Coach Action Card article gaps, content governance  
> Non-scope: production code, OCR, analyze-chat prompt, Spec 5 coach-follow-up prompt

---

## 1. Why This Exists

Spec 4 Phase 1 shipped `CoachActionCard` with 9 deterministic action types. Seven action types already map to exact learning articles, but two are intentionally unresolved:

- `softInvite` -> no article CTA yet
- `pausePursuit` -> no article CTA yet

The learning library already has 20 articles across 4 categories:

- 核心社交心法
- 深度交流
- 幽默與調情
- 非語言溝通

The next learning refresh should not simply add more content. The goal is to add precise, product-aligned lessons that reinforce Coach Action Card and VibeSync's "真誠流 + 自我內核 + 低壓推進" positioning.

---

## 2. Product Lens

### 2.1 What Good Learning Content Should Do

Good VibeSync learning content should help users:

- understand what is happening in an interaction
- regulate their own anxiety before acting
- express interest without pressure
- create connection without performing a fake persona
- know when to continue, pause, invite, or reassess fit

### 2.2 What It Must Not Do

Learning content must not teach:

- PUA tactics as a product frame
- pressure, jealousy, punishment, or hot-cold manipulation
- "high value / low value" ranking language as coaching truth
- treating women as targets, scores, market value, or game objects
- scripted dominance, "make her chase", or intentional insecurity

Hard red-line terms for user-facing article framing:

- `PUA`
- `收割`
- `控住`
- `攻略`
- `壞女人`
- `高分妹`
- `玩咖`
- `SMV`
- `hypergamy`
- `sexual market value`

These can appear in internal notes only when explicitly labeled as anti-patterns.

---

## 3. Source Screening Verdict

### 3.1 Add / Rewrite Into VibeSync Articles

| Priority | Source | Verdict | Why |
|---|---|---|---|
| P0 | https://www.datingnetwork.com/how-to-suggest-a-date-do-this-not-that/ | Rewrite and add | Strong fit for low-pressure, specific invite. Good source for `softInvite`. |
| P0 | https://www.scienceofpeople.com/how-to-ask-someone-out/ | Rewrite and add | Useful ask-out structure: shared hook, positive emotion, clear invitation, low commitment. Good source for `softInvite`. |
| P1 | https://www.lovewellsf.com/blog/ways-men-can-embody-confidence-in-dating | Rewrite and add | Strong fit for "healthy agency": confidence as consistency, self-awareness, intentional action, not showiness. |
| P1 | https://matchmakingcompany.com/dating-tips/why-is-talking-to-women-so-hard-tips-for-men/ | Rewrite and add selectively | Good anxiety framing, gradual exposure, light curiosity, nonverbal signals, and consent-respecting exit. |
| P1 | https://www.scienceofpeople.com/how-to-make-a-conversation-with-a-girl/ | Rewrite and add selectively | Useful for conversation skills, but original tone is more "make girls swoon"; needs VibeSync voice. |
| P1 | https://www.psychologytoday.com/us/blog/a-buoyant-life/202311/what-to-ask-on-a-first-date | Rewrite and add | Good self-disclosure/depth source for first-date conversation. |
| P1 | https://www.verywellmind.com/first-date-questions-for-engaging-conversations-7563587 | Rewrite and add | Practical question bank; useful if reframed as "depth ladder", not interview script. |
| P2 | https://www.verywellmind.com/unpacking-the-36-questions-that-lead-to-love-8559179 | Rewrite with caution | Good for progressive self-disclosure, but must warn against forcing depth too early. |
| P2 | https://www.yourmove.ai/blog/tinder-tips-for-guys | Background / partial rewrite | Useful for profile/photo/lifestyle cues later. Not urgent for current Coach Action Card gaps. |

### 3.2 Background Only / Do Not Add Directly

| Source | Verdict | Why |
|---|---|---|
| https://practicalpie.com/the-push-pull-method-of-flirting/ | Background only | Has a useful caution that unstable security / withdrawal of affection can damage relationships, but the "push-pull" frame itself is risky. |
| https://www.hayleyquinn.com/men-blog/have-better-conversations-with-women | Background only | Page mostly embeds video and marketing; can inspire topic, but not enough structured article text. |
| https://www.marsvenus.com/blog/how-to-talk-to-a-woman | Background only | Has useful "listen more / do not correct" ideas, but gender-essentialist framing needs heavy rewrite. |
| https://medium.com/@RobertBurriss/social-values-how-to-attract-a-long-term-partner-2f98b6904dd2 | Background only | Potentially useful values research angle, but Medium article is not urgent and should not become a public article without better primary-source grounding. |

### 3.3 Reject / Anti-Pattern

| Source | Verdict | Why |
|---|---|---|
| https://beyondages.com/powerful-push-pull-pua-techniques/ | Reject | Explicit PUA framing, "make women obsess", manipulation language. |
| https://www.innerconfidence.com/blog/how-to-push-pull-and-build-sexual-tension-with-a-girl | Reject | Encourages aggressive push/pull and sexual-tension technique framing. Conflicts with product values. |
| https://leadyourlove.com/blog/push-pull-method-of-flirting/ | Reject | Directly frames turning away / making her regain attention as technique; comment thread even surfaces manipulation concern. |
| https://coachcoreywayne.medium.com/a-mans-social-status-value-hypergamy-360d92ade9b | Reject | Hypergamy / status hierarchy / masculine dominance language is incompatible with VibeSync user-facing tone. |
| https://www.marriage.com/advice/physical-intimacy/sexual-market-value/ | Reject for user-facing learning | Even when softened, "sexual market value" frames people as market assets. Not suitable for the app. |
| https://medium.com/@Wilem.Lane/best-tips-for-success-on-tinder-as-a-man-88cde559e0d7 | Mostly reject | Some useful "lifestyle photo" observations, but advice is mixed with appearance/status-heavy assumptions. Use only as internal background if needed. |

---

## 4. Recommended Article Backlog

### P0: Fill Coach Action Card CTA Gaps

#### Article 21: 低壓邀約：讓對方容易說 yes，也能舒服說 no

Target action type:

- `softInvite`

Core teaching:

- 邀約不是逼對方表態，而是把一個低壓、具體、容易回應的選項放出來。
- 好邀約包含三件事：共同線索、輕鬆場景、可拒絕空間。
- 不要用模糊測試句，例如「哪天有空嗎」「要不要約一下」。
- 不要把邀約變成推銷簡報。

Possible VibeSync examples:

- "你剛剛說你也喜歡咖啡，我想到一間週末不太吵的店。這週六下午如果你剛好有空，我們可以去坐一下。"
- "你喜歡散步的話，河濱傍晚蠻舒服的。這週末找一天走走？不行也沒關係。"

LearningLinkResolver target:

- `CoachActionType.softInvite -> '21'`

#### Article 22: 留白不是冷處理：不要一直追問，讓節奏回來

Target action type:

- `pausePursuit`

Core teaching:

- 留白不是消失，也不是懲罰對方。
- 當對方回覆變短、熱度下降、或你開始焦慮想補很多訊息時，先停一下。
- 停不是放棄，而是讓自己回到穩定狀態。
- 下一步可以是等自然話題、換成輕量分享、或把注意力放回自己的生活。

Possible VibeSync examples:

- "這邊先不用再補問，讓對話自然停一下。你可以晚點用一個日常小分享重開，而不是立刻追原因。"
- "她現在回得短，不代表你做錯。先不要把焦慮塞進訊息裡。"

LearningLinkResolver target:

- `CoachActionType.pausePursuit -> '22'`

### P1: Strengthen Spec 5 v1.1 / Healthy Agency

#### Article 23: 有邊界，也敢靠近：健康主動性的練習

Target surfaces:

- Spec 5 v1.1
- Coach Action Card future action / practice
- Learning tab self-core track

Core teaching:

- 邊界不是牆，是門。
- 你可以尊重對方，也可以清楚表達自己想靠近。
- 健康的主動性包含：提出邀約、表達喜歡、承擔被拒絕、對方不舒服就收回。
- 問題不是有慾望，而是用壓力、交易、控制包裝慾望。

#### Article 24: 淺溝通的藝術：輕、準、可推進

Target action types:

- `rightSizeReply`
- `lowerPressureReply`
- `preferenceSignal`

Core teaching:

- 淺不是膚淺；淺是讓對方不用太用力也能接球。
- 好訊息不一定長，也不一定短，而是剛好。
- 用一點個性、一點畫面、一個小鉤子，讓對話自然往下一步走。

### P2: Date / Depth / Fit

#### Article 25: 第一次見面聊什麼：不要面試，也不要急著靈魂拷問

Target surfaces:

- post-invite / pre-date learning
- Spec 5 future postDateReflection

Core teaching:

- 第一次見面先建立安全感、節奏與好奇。
- 可以聊價值觀，但不要像審問。
- 問題要從輕到深，觀察對方也觀察自己。

#### Article 26: 36 問怎麼用：深度要循序，不是硬聊

Target action types:

- `emotionalResonance`
- future deep connection practice

Core teaching:

- 36 問的價值是循序自我揭露，不是照表操課。
- 深度需要場景、互信、同意和節奏。
- 太早硬上深度，反而會變壓力。

#### Article 27: 張力不是推拉：反差、曖昧與分寸

Target action types:

- `playfulReply`

Core teaching:

- 張力可以來自幽默、反差、明確喜好，而不是忽冷忽熱。
- 不要用撤回關心、故意冷淡、讓對方焦慮來製造吸引。
- 好的調情讓人更放鬆，不是更不安。

---

## 5. Learning Information Architecture

### 5.1 Keep Current 4 Categories for Now

Do not redesign the Learning tab UI yet. The current four categories are acceptable for v1:

- 核心社交心法
- 深度交流
- 幽默與調情
- 非語言溝通

### 5.2 Add Management Metadata Behind the Scenes

Future article data should support metadata beyond category:

```dart
enum LearningStage {
  opener,
  lightChat,
  invite,
  date,
  postDate,
  selfCore,
  fitCheck,
}

enum SourceRisk {
  safe,
  rewrite,
  antiPattern,
}
```

Recommended article metadata:

- `stage`: where this lesson applies
- `coachActionTypes`: which Coach Action Card types this supports
- `sourceRisk`: safe / rewrite / antiPattern
- `sourceUrls`: source references
- `coverStyle`: grounded / social / hobby / date / selfCore / avoid

This can be implemented later without changing the current UI immediately.

### 5.3 Stable ID Rule

Do not renumber existing article IDs `1-20`.

New articles should start at:

- `21`: softInvite
- `22`: pausePursuit
- `23+`: future additions

This avoids breaking `LearningLinkResolver`.

---

## 6. Image Curation

The 14 image files are useful, but the cover image system needs taste rules. The goal is not "man surrounded by attractive women." The goal is grounded aspiration: a man with life, social range, warmth, and agency.

### 6.1 Recommended Use

| File | Use | Notes |
|---|---|---|
| `S__40771683_0.jpg` | Playful social / karaoke | Good for humor, group energy, lightness. |
| `S__40771686_0.jpg` | Hobby / beach volleyball | Good for social agency and shared activity. |
| `S__40771689_0.jpg` | Date / roadtrip | Good for low-pressure date or shared experience. |
| `S__40771692_0.jpg` | Camping / social warmth | Good for community, warmth, group connection. |
| `S__40771690_0.jpg` | Hobby / badminton | Good for active life, partnership, play. |
| `S__40771697_0.jpg` | Social night / karaoke street | Good for mature social ease. |
| `S__40771694_0.jpg` | Roadtrip / couple | Good for date energy; slightly polished but acceptable. |
| `S__40771695_0.jpg` | Self-core / solo confidence | Good for self-development and grounded identity. |
| `S__40771696_0.jpg` | Couple / travel date | Good for connection and aspirational relationship. |

### 6.2 Use Carefully

| File | Concern | Recommendation |
|---|---|---|
| `S__40771684_0.jpg` | Business-confidence vibe; less dating-specific | Use for self-core / social confidence, not flirting. |
| `S__40771688_0.jpg` | Marathon self-improvement; not relationship-specific | Use for self-core only. |
| `S__40771687_0.jpg` | Gym image can drift into "alpha gym bro" | Use sparingly for discipline, not attraction hacks. |

### 6.3 Avoid for Learning Covers

| File | Concern |
|---|---|
| `S__40771685_0.jpg` | One man with several bikini women at pool can signal PUA fantasy / conquest. |
| `S__40771691_0.jpg` | Boxing punch is too aggressive for relationship learning tone. |

---

## 7. Proposed Phase 1.5 Scope

### Do

- Add 2 articles:
  - Article 21: `softInvite`
  - Article 22: `pausePursuit`
- Wire `LearningLinkResolver`:
  - `softInvite -> '21'`
  - `pausePursuit -> '22'`
- Add source notes in article comments or separate doc.
- Add tests proving all 9 CoachActionTypes either map to a real article ID or intentionally return null.

### Do Not

- Do not rewrite all 20 existing articles.
- Do not redesign Learning tab.
- Do not add AI article generation.
- Do not touch analyze-chat / OCR / Coach Follow-up Edge Function.
- Do not import PUA terminology into public article titles.
- Do not add new app routes unless a stable article route already exists.

---

## 8. Open Questions

1. Should Article 21 and 22 be visible in the Learning tab immediately, or only reachable from Coach Action Card CTA first?
2. Should we add `LearningStage` metadata now, or keep it as documentation until the next Learning tab refresh?
3. Should cover images be bundled now, or should Phase 1.5 stay text-only to avoid asset/app-size churn?
4. Should "張力不是推拉" be P2 content, or should it wait until Spec 4 practice expansion?

---

## 9. Recommendation

Ship Phase 1.5 as a narrow content patch:

1. Add Article 21 `低壓邀約：讓對方容易說 yes，也能舒服說 no`.
2. Add Article 22 `留白不是冷處理：不要一直追問，讓節奏回來`.
3. Wire both missing action types in `LearningLinkResolver`.
4. Defer metadata schema and image assets to a separate Learning IA refresh.

This gives immediate product value, completes Spec 4's CTA loop, and avoids opening a broad content-management refactor right after Spec 5.
