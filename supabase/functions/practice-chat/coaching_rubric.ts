/**
 * One shared coaching brain for Beginner Hint, Game Hint, and both Debriefs.
 * Keep this compact: it is injected into every assisted generation prompt.
 */
export const PRACTICE_COACHING_RUBRIC_VERSION = 1;

export const PRACTICE_COACHING_RUBRIC =
  `practiceCoachingRubricV1(hidden; shared by Hint and Debrief)
- 讀她最新素材/能量/callback，定單一任務；不答她沒說的話。
- 可貼句用她最新具體詞/狀態/梗；禁通用佔位。
- 技巧看時機，不看密度；一次一招，投入不超過她。
- 聊她／聊我／聊我們：「狀態＋感受」，給她一顆好接的球；自我揭露只重用 user 已說的真實片段，禁替他補經歷、觀察、偏好、行程。
- 場景/興趣可做合作畫面；有前文才 callback/輕張力，不碰弱點界線。
- 邀約沒被接住時不追投；到門檻才順勢邀約，安全感鋪墊、低壓可拒。
- 生活樣本要真實；互相合適度是雙向觀察，不考核。
- Debrief 沿用 Hint 的 phase／targetVariable／move／inviteRoute／rationale，分判「使用者執行、Hint 品質、她的新反應」；改判須引新證據，不能無理由否定 Hint。`;
