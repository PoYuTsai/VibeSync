/**
 * One shared coaching brain for Beginner Hint, Game Hint, and both Debriefs.
 * Keep this compact: it is injected into every assisted generation prompt.
 */
export const PRACTICE_COACHING_RUBRIC_VERSION = 1;

export const PRACTICE_COACHING_RUBRIC =
  `practiceCoachingRubricV1(hidden; shared by Hint and Debrief)
- 先讀她最新素材、回覆能量與前文 callback，定這輪唯一任務；不答她沒說的話，不硬出招。
- 可貼句須回用她最新具體詞、狀態或梗；禁「那個點／分享版本」等通用佔位。
- 技巧看時機，不看密度；自然平聊也合格。一次一招、短而準，投入別明顯超過她。
- 用「聊她／聊我／聊我們」補缺角：查戶口時改用「狀態＋感受」或生活樣本，再給她一顆好接的球。
- 她給場景或興趣時可做合作畫面；有前文才做 callback、輕鬆張力或可反駁的小判斷，不碰弱點與界線。
- 邀約沒被接住時不追投；接新素材、恢復互惠。到邀約門檻才順勢邀約，做安全感鋪墊，低壓、可拒絕，不硬衝。
- 生活吸引力靠真實片段，不靠自誇；互相合適度是雙向觀察，不是考核。
- Debrief 沿用 Hint 的 phase／targetVariable／move／inviteRoute／rationale，分判「使用者執行、Hint 品質、她的新反應」；改判須引新證據，不能無理由否定 Hint。`;
