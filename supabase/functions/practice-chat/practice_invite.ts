export type PracticeInviteLevel = "none" | "soft" | "direct";

// 裸「一點/一時」不當時鐘（round8 gh4）：「多聊一點」「再加一點」是程度副詞、
// 「一時說不準」是慣用語；只有「一點半/一點鐘/一點整」才是報時。真實聊天報
// 1 點幾乎必帶時段詞（下午/晚上），而時段詞本身已是 CONCRETE_TIME。
const CONCRETE_TIME =
  /(?:明天|後天|今晚|明晚|這週|週末|週[一二三四五六日天]|禮拜[一二三四五六日天]|下班後?|中午|下午|晚上|(?:[0-9０-９一二三四五六七八九十兩]{2,3}|[0-9０-９二三四五六七八九十兩])[點時]|一[點時](?=[半鐘整]))/u;
const CLOCK_TIME =
  /(?:(?:[0-9０-９一二三四五六七八九十兩]{2,3}|[0-9０-９二三四五六七八九十兩])[點時]|一[點時](?=[半鐘整]))/u;
const SOFT_TIME = /(?:改天|下次|有空|有機會|哪天|找天)/u;
const ACTIVITY =
  /(?:喝(?:杯)?咖啡|咖啡|吃(?:飯|宵夜|甜點)|散步|走走|看(?:展|電影)|逛(?:展|夜市)|小酌|喝一杯|碰面|見面|碰一下|見一下|出去玩)/u;
// round12 gh1「差點想直接找妳劇透」：差點（想/要）＝反事實未遂，不是提案；
// 「直接」副詞槽補進鏈，否則「差點想直接找妳」剝不掉。
const NEGATED_PLAN_CLAUSE =
  /(?:我|我們)?(?:不是(?:想|要)?|並非(?:想|要)?|沒有要|不會|不想|不要|不用|不必|不能|無法|沒辦法|沒要|不打算|沒打算|差點(?:想|要)?|別|不)(?:我|我們)?(?:再)?(?:(?:跟|和)[妳你]|一起)?(?:直接)?(?:去)?(?:過來|來|到|接|載|帶|找|約|請|見|碰面|等|吃|喝|看|逛|玩|走|爬|打|唱)[^，,。！？!?；;]*/gu;
// 「跟妳＋動詞」窗不得跨標點（round11 gh1「先跟妳說一聲，妳要慢慢看」——
// 跟妳說的是說一聲，「看」在下一子句，跨逗號湊對＝假邀約）。
const ADDRESSEE_PLAN_CUE =
  /(?:我(?:想|要|會|可以)?(?:去|來)?(?:接|載|帶|找|約|請)[妳你]|(?:接|載|帶|找|約|請)[妳你](?:去|來|吃|喝|看|玩|走)?|(?:在|到).{0,12}等[妳你](?![的回])|[妳你](?:(?:直接)?(?:過來|過去)|直接(?:來|到)|下樓|下來|出來|出門)|我(?:到|到了).{0,4}(?:叫|跟)[妳你](?:說)?|(?:跟|和)[妳你][^，,。！？!?；;]{0,10}(?:去|來|吃|喝|看|逛|玩|走|爬|打|唱|見|碰面)|(?:[妳你].{0,10}|(?:明天|後天|今晚|明晚|週末|週[一二三四五六日天]|禮拜[一二三四五六日天]).{0,6})(?:留|空出|撥)(?:半小時|一小時|[0-9０-９一二三四五六七八九十兩]{1,3}分鐘|時間)?給我)/u;
const IMPLICIT_ARRIVAL_CUE =
  /(?:(?:來|過來)(?:找我|我家|我這邊|我這)|(?:到|來)我(?:家|這邊|這))/u;
const BARE_ARRIVAL_CUE =
  /(?:^|[，,。！？!?；;])[那妳你明天後今晚這週末一二三四五六七八九十兩0-9０-９點時可以直接]{0,14}過來(?:[喔哦啦囉咯呀啊唷欸齁])?[\p{P}\p{S}]*$/u;
const THIRD_PARTY_ARRIVAL =
  /(?:朋友|同事|家人|客戶|姐妹|兄弟|他|她).{0,10}(?:來|過來|到)(?:找我|我家|我這邊|我這)/u;
const WAIT_FOR_PERSON_CUE =
  /(?:(?:樓下|門口|車站|捷運站|咖啡店|咖啡廳|餐廳|店裡|那邊|現場|老地方).{0,6}等[妳你]|我等[妳你](?:[喔哦啦囉咯呀啊唷欸齁])?[\p{P}\p{S}]*$|等[妳你](?:來|到|下樓|出來))/u;
// 「要不要」前置認知動詞＝疑問補語不是提案（round8 bh2「評估要不要出發」；
// round6 疑問補語 schedule 家族的 invite 變體）。round10 bh2「要不要先簽
// 切結書」＝玩笑建議非邀約：要不要後面必須接得上共同行動詞才算提案。
const MUTUAL_CUE =
  /(?:(?<!評估)(?<!考慮)(?<!決定)(?<!研究)(?<!糾結)(?<!煩惱)要不要(?=[^，,。！？!?；;]{0,12}(?:一起|去|來|出來|出門|吃|喝|看|逛|玩|走|爬|打|唱|約|見|碰|跟我|和我|找我))|一起|我們.{0,10}(?:去|來|約|吃|喝|看|逛|玩|走|爬|打|唱|見|碰面)|[妳你](?:要|想)不要)/u;
// 單字動詞要求非構詞環境：好看/難看、換來/聽起來（「一起來」除外）、被打/挨打、
// 打算/打工/打字/打卡（round8 bh3「打算跟咖啡過一輩子了吧」——「打」為複合詞
// 首字時不得當提案動詞）。語尾段落再排除「敢」擋住反問句
// （「還敢跟嗎」是追問對方敢不敢，不是提案）。「繼續＋動詞＋吧」是勸她
// 延續自己的活動（round10 bh3「繼續喝吧」），不是提案。round11 兩變體：
// 「走路還會抖嗎」——「走路」是行走本身不是同行提案，走後接路即剝；
// 「看下來感覺如何」「看起來如何」——看/吃/喝/玩＋起來/下來是體感補語
// （讀後感/嘗起來），不是提案；「約起來嗎」不在此列仍算邀約。裸「來」
// 前一字是下（看下來的來）同屬補語剝除；真邀約「妳下來嗎」由
// ADDRESSEE_PLAN_CUE 的 [妳你]下來 接手，不漏。真機 gh6（2026-07-23
// 討推薦局）補：語尾助詞緊貼評價/比較詞（挑剔嗎/講究嗎/不一樣吧）＝
// 問她的品味感受或推測差異，不是把她放進行動計畫。
const GENERIC_PROPOSAL =
  /(?:(?<![好難耐])(?<!繼續)(?:看|吃|喝|玩)(?!(?:起來|下來|到))|(?<!換)(?<!(?<!一)起)(?<!下)來|(?<![被挨])打(?!(?:算|工|字|掃|卡|招呼|氣|擊|分))|(?<!下)去|逛|走(?!路)|爬|唱|約|碰面|見面)(?!(?:下去|對了|錯了))[^，,。！？!?；;敢]{0,18}(?<!了)(?<!一樣)(?<!挑剔)(?<!講究)(?<!偏好)(?<!習慣)(?<!的人)(?<!類型)(?:吧|嗎|好不好|怎麼樣|如何)(?:[?？])?$/u;
const EXECUTION_CUE =
  /(?:我(?:來)?(?:找店|訂位|訂那間店|安排|買票|規劃)|幾點(?:見|碰面)|約在)/u;
const SELF_DISCLOSURE =
  /我[^妳你，,。！？!?；;]{0,12}(?:去|來|到|吃|喝|看|逛|玩|走|爬|打|唱|在)/u;
const MEETING_CUE =
  /(?:見面|碰面|碰(?:個|一個)面|碰一下|見一下|(?:樓下|門口|車站|捷運站|咖啡店|咖啡廳|餐廳|店裡|那邊|現場|老地方)?見(?:[喔哦啦囉咯呀啊唷欸齁])?[\p{P}\p{S}]*$)/u;
const ARRANGEMENT_CONTEXT =
  /(?:到時|待會|等等|一會兒|樓下|門口|車站|捷運站|咖啡店|咖啡廳|餐廳|店裡|那邊|現場|老地方)/u;
const THIRD_PARTY_MEETING =
  /(?:(?:跟|和|找|陪)(?:朋友|同事|家人|客戶|姐妹|兄弟|他|她).{0,8}(?:見|見面|見一下|碰面|碰一下|碰(?:個|一個)面)|(?:見|見面|見一下|碰面|碰一下|碰(?:個|一個)面).{0,6}(?:朋友|同事|家人|客戶|姐妹|兄弟|他|她))/u;
const CLOCK_LOCATION_PLAN =
  /[0-9０-９一二三四五六七八九十兩]{1,3}[點時].{0,10}(?:樓下|門口|車站|捷運站|咖啡店|咖啡廳|餐廳|店裡|那邊|現場|老地方)(?:[喔哦啦囉咯呀啊唷欸齁])?[\p{P}\p{S}]*$/u;
const COMMAND_SCHEDULE_CUE =
  /(?:準備出門|記得(?:出門|留(?:下)?時間)|把(?:時間|行程|晚上)(?:空下來|空著|留空|清掉|清空|排開)|(?:行程|晚上)(?:清空|空下來)|(?:先)?空下來|(?:先)?保留|(?:先|暫時)?(?:別|不要)(?:排(?:事|行程)?|約(?:人|別人)?|遲到|有約|答應別人)|(?:時間|行程|這週末|週末|週[一二三四五六日天]|禮拜[一二三四五六日天])(?:都)?(?:給我|歸我|排給我)|(?:排|留)(?:給我|空)|留空|空著|聽我的|(?:空|留|預留)(?:半小時|一小時|[0-9０-９一二三四五六七八九十兩]{1,3}分鐘)|[妳你]?等我|待命)/u;
const SELF_SCHEDULE_DISCLOSURE =
  /我.{0,18}(?:準備出門|記得(?:出門|留(?:下)?時間)|把(?:時間|行程|晚上)(?:空下來|空著|留空|清掉|清空|排開)|(?:行程|晚上)(?:清空|空下來)|(?:先)?空下來|(?:先)?保留|(?:先|暫時)?(?:別|不要)(?:排(?:事|行程)?|約(?:人|別人)?|有約|答應別人)|(?:有)?空(?:著|半小時|一小時|[0-9０-９一二三四五六七八九十兩]{1,3}分鐘)|留空|預留(?:半小時|一小時|[0-9０-９一二三四五六七八九十兩]{1,3}分鐘))/u;
const BARE_SOCIAL_INVITE = /(?:喝一杯|碰一下|見一下|碰面|見面)/u;
const THIRD_PARTY_ACTIVITY =
  /(?:跟|和|陪)(?:朋友|同事|家人|客戶|姐妹|兄弟|他|她).{0,10}(?:去|來|吃|喝|看|逛|玩|走|爬|打|唱|見|碰)/u;
const PERSONAL_RECOVERY_ACTIVITY =
  /(?:醒腦|補血|續命|放空|早點睡|運動|跑步|值完班|下班後)/u;
const NEGATED_ACTIVITY =
  /(?:咖啡|吃飯|宵夜|甜點|散步|電影|夜市|小酌|喝一杯)(?:先)?(?:免了|不要|取消|算了)/u;
// 意圖問句（round8 bh2）：「還會想再爬嗎」「還會再去嗎」問的是她自己會不會
// 重複某活動，不是提案；子句含「我」（會再跟我去嗎）不剝，保留給邀約判定。
// round10 bh2 補兩變體：「還敢去嗎」（敢在動詞前，語尾排敢擋不到）與被動
// 「還會被拖去嗎」（拖她的是朋友）；「被我拖去」含我不剝，仍算邀約。
// 真機 gh7 補（2026-07-23）：「會有想殺去的候選地嗎」＝問她自己的旅遊意向，
// 前綴補「會有想/有沒有想/會不會想」變體＋動詞前容許 3 字修飾（殺去/衝去）；
// 修飾窗與語尾都排「我」，「會想再跟我去嗎」仍算邀約。
// 臆測句（真機 debrief 2026-07-23「我猜妳吃得比誰都香吧」）：我猜/我賭…吧
// 是對她狀態的玩笑推測，不是提案。
const CONJECTURE_CLAUSE =
  /我(?:猜|賭|敢說)[^，,。！？!?；;]{0,20}(?:吧|嗎)/gu;
// 回憶句（Codex 覆審/三審/四審 P2 疊代）：想起＝回憶動詞。
// 問句形「(會)想起…嗎」整段剝（回憶內容含過去的週六/一起也照剝），
// 只在未來提案詞（下次/改天/要不要）前停，保住連寫真邀約
// 「想起那家店下次一起去嗎」。
const MEMORY_RECALL_QUESTION_CLAUSE =
  /(?:會|還會)?想起(?:(?!下次|改天|明天|後天|要不要).){0,20}嗎/gu;
// 敘述形 tempered dot 停在邀約窗口詞前，無標點連寫的真邀約
// （想起上次那家店下次一起去吧）不被吞。
const MEMORY_RECALL_CLAUSE =
  /想起(?:(?!下次|改天|週[一二三四五六日末]|星期[一二三四五六日天]|禮拜[一二三四五六日天]|明天|後天|一起|要不要|約).){0,16}/gu;
const INTENT_QUESTION_CLAUSE =
  /(?:還會想?再?|會想?再|還?敢再?|會有想|有沒有(?:很)?想|會不會想|會[^，,。！？!?；;我]{0,4}想|還?有(?:力氣|心情|餘裕|體力)|(?:平常|通常|一般|每次)[^，,。！？!?；;我]{0,8}會(?:這樣)?|也會這樣)(?:被[^我，,。！？!?；;]{0,3})?[^，,。！？!?；;我起]{0,3}?(?:去|爬|來|吃|喝|看|逛|玩|走|打|唱|約)[^，,。！？!?；;我]{0,10}嗎/gu;
// 第三方主詞邀約（round10 bh2「朋友下次還會約妳嗎」）：子句開頭是朋友/他她
// 在約妳，不是我在約妳——整句剝除。限子句開頭才剝，「我帶朋友去找妳」不受影響。
const THIRD_PARTY_INVITER_CLAUSE =
  /(?:^|[，,。！？!?；;])(?:朋友|同事|家人|客戶|姐妹|兄弟|閨蜜|他|她)(?:們)?[^，,。！？!?；;]{0,8}(?:約|找|接|載|帶|請)[妳你][^，,。！？!?；;]*/gu;
// 真機 gh6 補（2026-07-23）：「改天整理給妳」「回頭傳給妳」是分享內容的
// 承諾，不是把她放進見面計畫——剝到「給妳」為止（Codex P2：不吞語尾，
// 「傳給妳週六一起去」的真邀約要留下來）。「帶妳去」沒有分享動詞，不受影響。
const SHARE_CONTENT_CLAUSE =
  /[^，,。！？!?；;]*(?:整理|列|傳|發|寄|截圖|分享)[^，,。！？!?；;]*?給[妳你](?:[喔哦啦囉呀啊唷欸])?/gu;
// 真機 gh7 補（2026-07-23）：「會偷偷想像自己去哪嗎」＝問她的想像/夢想清單，
// 不是把她放進行程——只剝到疑問標記（哪/嗎）為止的想像問句（Codex P2：
// 「別只想像了週六直接一起去吧」無疑問標記不剝，真提案保留）。
const IMAGINATION_CLAUSE = /(?:想像|幻想|做夢夢到)[^，,。！？!?；;]*?[哪嗎]/gu;

function compactInviteText(value: string): string {
  return value.normalize("NFKC").replace(/\s+/gu, "");
}

export function isCommandStyleSchedule(value: string): boolean {
  const compact = compactInviteText(value);
  return CONCRETE_TIME.test(compact) && COMMAND_SCHEDULE_CUE.test(compact) &&
    !SELF_SCHEDULE_DISCLOSURE.test(compact);
}

/**
 * Classifies the pasteable sentence itself. A time plus an activity is not
 * enough: 「明天我也想喝咖啡」is self-disclosure, not an invitation. Generic
 * activities are accepted only when a joint/proposal cue makes the addressee
 * part of the plan.
 */
export function practiceInviteLevelFor(value: string): PracticeInviteLevel {
  const compact = compactInviteText(value);
  // Remove a negated/cancelled plan clause before looking for positive plan
  // grammar. This preserves a later positive clause after punctuation while
  // ensuring「不要一起喝」「不是要約妳」never becomes an invitation cue.
  const positiveText = compact.replace(NEGATED_PLAN_CLAUSE, "").replace(
    /(?:這輪|現在|今天)?(?:先)?(?:不急著約|不約|不用約|不硬約|別急著約)/gu,
    "",
  ).replace(INTENT_QUESTION_CLAUSE, "").replace(CONJECTURE_CLAUSE, "")
    .replace(MEMORY_RECALL_QUESTION_CLAUSE, "")
    .replace(MEMORY_RECALL_CLAUSE, "").replace(
    THIRD_PARTY_INVITER_CLAUSE,
    "",
  ).replace(SHARE_CONTENT_CLAUSE, "").replace(IMAGINATION_CLAUSE, "");
  const hasConcreteTime = CONCRETE_TIME.test(positiveText);
  const hasSoftTime = SOFT_TIME.test(positiveText);
  const hasImplicitArrival = (IMPLICIT_ARRIVAL_CUE.test(positiveText) ||
    BARE_ARRIVAL_CUE.test(positiveText)) &&
    !THIRD_PARTY_ARRIVAL.test(positiveText) &&
    !SELF_DISCLOSURE.test(positiveText);
  const hasWaitPlan = WAIT_FOR_PERSON_CUE.test(positiveText) &&
    (hasConcreteTime || hasSoftTime || ARRANGEMENT_CONTEXT.test(positiveText));
  const hasAddresseePlan = ADDRESSEE_PLAN_CUE.test(positiveText) ||
    hasImplicitArrival || hasWaitPlan;
  const hasMutualCue = MUTUAL_CUE.test(positiveText);
  const hasActivity = ACTIVITY.test(positiveText);
  const hasExecution = EXECUTION_CUE.test(positiveText);
  const proposalText = positiveText.replace(
    /[，,、]?\s*[妳你]呢[?？]?$/u,
    "",
  );
  const hasGenericProposal = GENERIC_PROPOSAL.test(proposalText);
  const selfDisclosure = SELF_DISCLOSURE.test(positiveText);
  const hasClockLocationPlan = CLOCK_TIME.test(positiveText) &&
    CLOCK_LOCATION_PLAN.test(positiveText) && !selfDisclosure &&
    !THIRD_PARTY_MEETING.test(positiveText);
  const hasMeetingCue = MEETING_CUE.test(positiveText) &&
    !THIRD_PARTY_MEETING.test(positiveText);
  const hasMeetingArrangement = hasMeetingCue && !selfDisclosure &&
    (hasConcreteTime || hasSoftTime || ARRANGEMENT_CONTEXT.test(positiveText));
  // Command-style grabs are intentionally inspected before negated-plan
  // cleanup: 「週末別約別人」is an imperative aimed at her, not a cancelled
  // plan that should disappear from classification.
  const hasCommandSchedule = isCommandStyleSchedule(compact);
  const hasNonInviteActivityContext = THIRD_PARTY_ACTIVITY.test(positiveText) ||
    THIRD_PARTY_MEETING.test(positiveText) ||
    PERSONAL_RECOVERY_ACTIVITY.test(positiveText) ||
    NEGATED_ACTIVITY.test(positiveText);
  const hasBareSocialInvite = hasConcreteTime &&
    BARE_SOCIAL_INVITE.test(positiveText) && !selfDisclosure &&
    !hasNonInviteActivityContext;
  const hasPositivePlan = hasAddresseePlan || hasMutualCue ||
    hasMeetingArrangement || hasClockLocationPlan || hasCommandSchedule ||
    hasBareSocialInvite ||
    (!selfDisclosure && hasGenericProposal) ||
    (hasExecution && (hasActivity || ARRANGEMENT_CONTEXT.test(positiveText)));

  if (
    hasSoftTime && !hasConcreteTime &&
    (hasPositivePlan ||
      (!selfDisclosure && !hasNonInviteActivityContext && hasActivity))
  ) {
    return "soft";
  }
  if (
    hasAddresseePlan || hasMeetingArrangement || hasClockLocationPlan ||
    hasCommandSchedule ||
    hasBareSocialInvite ||
    (hasMutualCue && (hasActivity || hasConcreteTime || hasGenericProposal)) ||
    (hasConcreteTime && hasPositivePlan) ||
    (!selfDisclosure && hasGenericProposal)
  ) {
    return "direct";
  }
  return "none";
}

export function practiceInviteLevelRank(level: PracticeInviteLevel): number {
  return level === "direct" ? 2 : level === "soft" ? 1 : 0;
}
