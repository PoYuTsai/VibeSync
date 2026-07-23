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
const NEGATED_PLAN_CLAUSE =
  /(?:我|我們)?(?:不是(?:想|要)?|並非(?:想|要)?|沒有要|不會|不想|不要|不用|不必|不能|無法|沒辦法|沒要|不打算|沒打算|別|不)(?:我|我們)?(?:再)?(?:(?:跟|和)[妳你]|一起)?(?:去)?(?:過來|來|到|接|載|帶|找|約|請|見|碰面|等|吃|喝|看|逛|玩|走|爬|打|唱)[^，,。！？!?；;]*/gu;
const ADDRESSEE_PLAN_CUE =
  /(?:我(?:想|要|會|可以)?(?:去|來)?(?:接|載|帶|找|約|請)[妳你]|(?:接|載|帶|找|約|請)[妳你](?:去|來|吃|喝|看|玩|走)?|(?:在|到).{0,12}等[妳你](?![的回])|[妳你](?:(?:直接)?(?:過來|過去)|直接(?:來|到)|下樓|出來|出門)|我(?:到|到了).{0,4}(?:叫|跟)[妳你](?:說)?|(?:跟|和)[妳你].{0,10}(?:去|來|吃|喝|看|逛|玩|走|爬|打|唱|見|碰面)|(?:[妳你].{0,10}|(?:明天|後天|今晚|明晚|週末|週[一二三四五六日天]|禮拜[一二三四五六日天]).{0,6})(?:留|空出|撥)(?:半小時|一小時|[0-9０-９一二三四五六七八九十兩]{1,3}分鐘|時間)?給我)/u;
const IMPLICIT_ARRIVAL_CUE =
  /(?:(?:來|過來)(?:找我|我家|我這邊|我這)|(?:到|來)我(?:家|這邊|這))/u;
const BARE_ARRIVAL_CUE =
  /(?:^|[，,。！？!?；;])[那妳你明天後今晚這週末一二三四五六七八九十兩0-9０-９點時可以直接]{0,14}過來(?:[喔哦啦囉咯呀啊唷欸齁])?[\p{P}\p{S}]*$/u;
const THIRD_PARTY_ARRIVAL =
  /(?:朋友|同事|家人|客戶|姐妹|兄弟|他|她).{0,10}(?:來|過來|到)(?:找我|我家|我這邊|我這)/u;
const WAIT_FOR_PERSON_CUE =
  /(?:(?:樓下|門口|車站|捷運站|咖啡店|咖啡廳|餐廳|店裡|那邊|現場|老地方).{0,6}等[妳你]|我等[妳你](?:[喔哦啦囉咯呀啊唷欸齁])?[\p{P}\p{S}]*$|等[妳你](?:來|到|下樓|出來))/u;
// 「要不要」前置認知動詞＝疑問補語不是提案（round8 bh2「評估要不要出發」；
// round6 疑問補語 schedule 家族的 invite 變體）。
const MUTUAL_CUE =
  /(?:(?<!評估)(?<!考慮)(?<!決定)(?<!研究)(?<!糾結)(?<!煩惱)要不要|一起|我們.{0,10}(?:去|來|約|吃|喝|看|逛|玩|走|爬|打|唱|見|碰面)|[妳你](?:要|想)不要)/u;
// 單字動詞要求非構詞環境：好看/難看、換來/聽起來（「一起來」除外）、被打/挨打、
// 打算/打工/打字/打卡（round8 bh3「打算跟咖啡過一輩子了吧」——「打」為複合詞
// 首字時不得當提案動詞）。語尾段落再排除「敢」擋住反問句
// （「還敢跟嗎」是追問對方敢不敢，不是提案）。
const GENERIC_PROPOSAL =
  /(?:(?<![好難耐])(?:看|吃|喝|玩)|(?<!換)(?<!(?<!一)起)來|(?<![被挨])打(?!(?:算|工|字|掃|卡|招呼|氣|擊))|(?<!下)去|逛|走|爬|唱|約|碰面|見面)(?!(?:下去|對了|錯了))[^，,。！？!?；;敢]{0,18}(?<!了)(?:吧|嗎|好不好|怎麼樣|如何)(?:[?？])?$/u;
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
const INTENT_QUESTION_CLAUSE =
  /(?:還會想?再?|會想?再)(?:去|爬|來|吃|喝|看|逛|玩|走|打|唱)[^，,。！？!?；;我]{0,10}嗎/gu;

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
  ).replace(INTENT_QUESTION_CLAUSE, "");
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
