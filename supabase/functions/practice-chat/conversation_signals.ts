/**
 * 窄逐客令／敵意偵測：只認明確要求使用者停止聯絡的句子。
 *
 * 不靠裸關鍵字猜語境，避免把否定、和解、第三人稱敘事、店家評論，或
 * 「不想聊了？」這類詢問誤判成她正在下逐客令。
 */
export function latestAssistantShowsHostility(
  latestAssistant: string,
): boolean {
  const normalized = latestAssistant
    .normalize("NFKC")
    .toLowerCase()
    // Newlines are semantic clause boundaries. Convert them before stripping
    // other control/default-ignorable characters.
    .replace(/\r\n?|\n/gu, "。")
    // Remove default-ignorables plus visually blank Hangul/Braille fillers so
    // an exit boundary cannot be split by invisible copy/paste characters.
    .replace(/[\p{C}\p{M}\u115f\u1160\u2800]+/gu, "")
    .trim();
  const clauses = normalized
    .split(/(?<=[，,。.!！?？；;：:])/)
    .map((raw) => ({
      isQuestion: /[?？]\s*$/.test(raw),
      text: raw
        .replace(/[，,。.!！?？；;：:\s]+$/g, "")
        .replace(/^[\s（(「『"'`]+|[\s）)」』"'`]+$/g, "")
        .trim(),
    }))
    .filter((clause) => clause.text.length > 0);

  return clauses.some(({ text, isQuestion }, index) => {
    const previousClause = clauses[index - 1]?.text ?? "";
    const endsWithSpeechAttribution =
      /(?:跟(?:我|他|她|你|妳)說|說|告訴(?:我|他|她|你|妳)|叫(?:我|他|她|你|妳)|問(?:我|他|她|你|妳)?|傳訊息(?:說)?|回覆(?:我|他|她|你|妳)?|回(?:我|他|她|你|妳))(?:了)?$/
        .test(previousClause);
    const isDirectSpeakerPreamble =
      /^(?:我(?:跟(?:你|妳)說|想說|要說|就說|只是說|說)|老實說|坦白說)(?:了)?$/
        .test(previousClause);
    if (endsWithSpeechAttribution && !isDirectSpeakerPreamble) return false;

    const directBlockThreat = [
      /^(?:(?:那|不然|否則)\s*)?(?:我(?:要|會|就|想|直接|現在要|現在就)?\s*)?封鎖(?:你|妳)(?:了)?(?:啦|囉|喔|哦|吧|欸)?$/,
      /^(?:(?:那|不然|否則)\s*)?(?:我(?:要|會|就|想|直接|現在要|現在就)?\s*)?(?:把|將)(?:你|妳)(?:給我)?封鎖(?:了)?(?:啦|囉|喔|哦|吧|欸)?$/,
      /^(?:你|妳)(?:已經)?被封鎖(?:也|就是|才|活該|剛好).*/,
      /^(?:你|妳)?再(?:這樣|這麼|亂傳|傳|煩|鬧).{0,6}就(?:把(?:你|妳))?封鎖(?:你|妳)?$/,
    ].some((pattern) => pattern.test(text)) ||
      (!isQuestion &&
        /^(?:你|妳)(?:已經)?被我封鎖(?:了)?(?:啦|囉|喔|哦|吧|欸)?$/
          .test(text));
    if (directBlockThreat) return true;

    const directText = text.replace(
      /^(?:(?:現在|今天|先|暫時)\s*)?(?:(?:拜託|請|麻煩)(?:你|妳)?\s*)?(?:(?:你|妳)?(?:可以|可不可以|能不能|真的|最好)\s*|(?:你|妳)\s*)?(?:(?:現在|今天|先|暫時)\s*)?/,
      "",
    );
    const compactDirectText = directText.replace(/\s+/g, "");
    const directExitPatterns = [
      /^(?:停止|不要|別|勿)(?:再)?(?:聯絡|聯繫|密|私訊|回覆?|傳(?:line|訊息)?)(?:我|給我)?(?:了)?(?:啦|囉|喔|哦|吧|欸|嗎)?$/,
      /^(?:我們?\s*)?(?:不要|別)(?:再)?(?:聯絡|聯繫)(?:了)?(?:啦|囉|喔|哦|吧|欸|嗎)?$/,
      /^(?:不用|不要|別)再傳(?:訊息)?(?:給我|過來)?(?:了)?(?:啦|囉|喔|哦|吧|欸|嗎)?$/,
      /^(?:不要|別)傳(?:了)(?:啦|囉|喔|哦|吧|欸|嗎)?$/,
      /^(?:不要|別)再來(?:找我|煩我|亂)?(?:了)?(?:啦|囉|喔|哦|吧|欸|嗎)?$/,
      /^(?:不要|別)(?:再)?來(?:找|煩)我(?:了)?(?:啦|囉|喔|哦|吧|欸|嗎)?$/,
      /^(?:不要|別)(?:再)?(?:找|煩|聯絡|聯繫|打擾|密|私訊|吵)我(?:了)?(?:啦|囉|喔|哦|吧|欸|嗎)?$/,
      /^(?:停止|不要|別|勿)(?:再)?跟我(?:聯絡|聯繫|說話|聊天|聊)(?:了)?(?:啦|囉|喔|哦|吧|欸|嗎)?$/,
      /^(?:我)?(?:希望|要求)(?:你|妳)(?:不要|別|勿)(?:再)?(?:聯絡|聯繫|密|私訊|回覆?|傳(?:line|訊息)?)(?:我|給我)?(?:了)?(?:啦|囉|喔|哦|吧|欸|嗎)?$/,
      /^(?:我)?(?:覺得|認為|想)(?:我們)(?:還是)?(?:不要|別)(?:再)?(?:聯絡|聯繫)(?:比較好|了)?(?:啦|囉|喔|哦|吧|欸|嗎)?$/,
      /^(?:離我(?:遠(?:一?點)?|遠遠的)|滾開|走開)(?:了)?(?:啦|囉|喔|哦|吧|欸|嗎)?$/,
      /^別來亂(?:了)?(?:啦|囉|喔|哦|吧|欸|嗎)?$/,
      /^(?:我\s*)?想(?:先|暫時)?(?:不要|別|不)(?:再)?(?:跟(?:你|妳))?(?:聊|說話)(?:了)?(?:啦|囉|喔|哦|吧|欸)?$/,
      /^(?:我們?\s*)?(?:現在|今天|先|暫時)?(?:不要|別|不)(?:再)?(?:跟(?:你|妳))?(?:聊|說話)(?:了)?(?:啦|囉|喔|哦|吧|欸)?$/,
    ];
    const matchesDirectExit = directExitPatterns.some((pattern) =>
      pattern.test(compactDirectText)
    );
    const nextClause = clauses[index + 1]?.text ?? "";
    const mentionsVenue =
      /(?:這|那)(?:家|間)(?:店|店家|餐廳|酒吧|咖啡廳)|(?:這|那)個地方|店家|服務|餐點/
        .test(nextClause);
    const hasNegativeVenueReview =
      /(?:很|超|有夠|真的)?(?:雷|爛|差)|不好|難吃|難喝|不推薦|踩雷|不行/
        .test(nextClause);
    const isVenueAdvice = /^(?:不要|別)再來/.test(compactDirectText) &&
      mentionsVenue && hasNegativeVenueReview;
    if (matchesDirectExit && !isVenueAdvice) return true;

    // 「可以不要再聯絡我嗎」已由 directExitPatterns 命中；裸「不想聊了？」
    // 是詢問，不能當成她宣告退場。
    if (isQuestion) return false;
    return [
      /^(?:(?:其實|說真的|老實說)\s*)?(?:我\s*)?(?:(?:其實|真的|現在|今天|已經|目前|暫時|有點)\s*)*不(?:太)?想(?:再)?(?:跟(?:你|妳))?(?:聊|說話)(?:了)?(?:啦|囉|喔|哦|吧|欸)?$/,
      /^(?:(?:其實|說真的|老實說)\s*)?(?:我\s*)?(?:(?:其實|真的|現在|今天|已經|目前|暫時|有點)\s*)*不(?:太)?想(?:再)?理(?:你|妳)(?:了)?(?:啦|囉|喔|哦|吧|欸)?$/,
      /^(?:我)?不想再收到(?:你|妳)(?:的)?(?:訊息|消息|回覆)(?:了)?(?:啦|囉|喔|哦|吧|欸)?$/,
      /^(?:我)?不想再跟(?:你|妳)有任何(?:聯絡|聯繫)(?:了)?(?:啦|囉|喔|哦|吧|欸)?$/,
    ].some((pattern) => pattern.test(text));
  });
}

// ── 2026-09-10 她否認自己大頭照細節（debrief 結構證據） ────────────────────
// 黑箱 10/10：使用者正確引用 photoScene、她自己否認，debrief 反扣使用者
// 「查戶口／不信任她」。抽象規則三個位置各 10 場只壓到 5～8/10，改走結構刀：
// server 把她否認照片的原句點名給 debrief（同 agency ledger「第 N 則」的形狀，
// 但逐字稿沒序號，直接引原句更好對）。
//
// 觸發條件窄：使用者這句提到照片，她緊接的下一句含否認詞。
// ponytail: 純規則；整句只有「沒有啦」的客套謙辭已排除，但「沒有啦我很醜」這種
// 帶內容的仍會中，注入文只叫 debrief「對照大頭照事實判定」，誤觸代價是多一段
// 提醒。要抓職業／城市／寵物等非照片事實或提高精度，再升級成分類器。
const PHOTO_MENTION = /大頭照|頭像|照片|自拍|那張/u;
const PHOTO_DENIAL =
  /沒有|不是|認錯|記錯|看錯|亂講|沒去過|沒穿|沒拍|沒戴|哪有|才不|才沒|不對|誤會/u;
const PHOTO_DENIAL_QUOTE_MAX = 40;
// 整句只是「沒有啦～」「哪有哈哈」這種客套謙辭（不含任何事實）不算否認——
// 「妳照片很好看→沒有啦」點名給 debrief 會讓它無中生有寫「她否認照片細節」。
const PHOTO_MODEST_DEFLECTION =
  /^(?:沒有|哪有|才沒有?|沒有沒有|哪有哪有)(?:[啦啊呀喔哦欸耶嘛吧哈嘿嘻～~!！。.\s]|xd|XD|lol)*$/u;

/**
 * 她否認自己大頭照細節的原句（依逐字稿順序、去重、各截 40 字）。
 * 空陣列＝沒觸發，呼叫端必須保持 prompt 逐位元組不變。
 */
export function partnerPhotoDenialQuotes(
  turns: readonly { role: "user" | "ai"; text: string }[],
): string[] {
  const quotes: string[] = [];
  for (let i = 1; i < turns.length; i++) {
    const prev = turns[i - 1];
    const cur = turns[i];
    if (cur.role !== "ai" || prev.role !== "user") continue;
    if (!PHOTO_MENTION.test(prev.text) || !PHOTO_DENIAL.test(cur.text)) continue;
    if (PHOTO_MODEST_DEFLECTION.test(cur.text.trim())) continue;
    const quote = cur.text.replace(/\s+/gu, " ").trim().slice(
      0,
      PHOTO_DENIAL_QUOTE_MAX,
    );
    if (quote.length > 0 && !quotes.includes(quote)) quotes.push(quote);
  }
  return quotes;
}
