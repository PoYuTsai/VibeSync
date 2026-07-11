export type PracticeInviteLevel = "none" | "soft" | "direct";

const CONCRETE_TIME =
  /(?:明天|後天|今晚|明晚|這週|週末|週[一二三四五六日天]|下班後?|中午|下午|晚上|[0-9０-９一二三四五六七八九十兩]{1,3}[點時])/u;
const CLOCK_TIME = /[0-9０-９一二三四五六七八九十兩]{1,3}[點時]/u;
const SOFT_TIME = /(?:改天|下次|有空|有機會|哪天|找天)/u;
const ACTIVITY =
  /(?:喝(?:杯)?咖啡|咖啡|吃(?:飯|宵夜|甜點)|散步|走走|看(?:展|電影)|逛(?:展|夜市)|小酌|喝一杯|碰面|見面|出去玩)/u;
const NEGATED_PLAN_CLAUSE =
  /(?:我|我們)?(?:不是(?:想|要)?|並非(?:想|要)?|沒有要|不會|不想|不要|不用|不必|不能|無法|沒辦法|沒要|不打算|沒打算|別|不)(?:我|我們)?(?:再)?(?:(?:跟|和)[妳你]|一起)?(?:去)?(?:過來|來|到|接|載|帶|找|約|請|見|碰面|等|吃|喝|看|逛|玩|走|爬|打|唱)[^，,。！？!?；;]*/gu;
const ADDRESSEE_PLAN_CUE =
  /(?:我(?:想|要|會|可以)?(?:去|來)?(?:接|載|帶|找|約|請)[妳你]|(?:接|載|帶|找|約|請)[妳你](?:去|來|吃|喝|看|玩|走)?|(?:在|到).{0,12}等[妳你]|[妳你](?:(?:直接)?(?:過來|過去)|直接(?:來|到)|下樓|出來)|我(?:到|到了).{0,4}(?:叫|跟)[妳你](?:說)?|(?:跟|和)[妳你].{0,10}(?:去|來|吃|喝|看|逛|玩|走|爬|打|唱|見|碰面))/u;
const IMPLICIT_ARRIVAL_CUE =
  /(?:(?:來|過來)(?:找我|我家|我這邊|我這)|(?:到|來)我(?:家|這邊|這))/u;
const BARE_ARRIVAL_CUE =
  /(?:^|[，,。！？!?；;])[那妳你明天後今晚這週末一二三四五六七八九十兩0-9０-９點時可以直接]{0,14}過來(?:[喔哦啦囉咯呀啊唷欸齁])?[\p{P}\p{S}]*$/u;
const THIRD_PARTY_ARRIVAL =
  /(?:朋友|同事|家人|客戶|姐妹|兄弟|他|她).{0,10}(?:來|過來|到)(?:找我|我家|我這邊|我這)/u;
const WAIT_FOR_PERSON_CUE =
  /(?:(?:樓下|門口|車站|捷運站|咖啡店|咖啡廳|餐廳|店裡|那邊|現場|老地方).{0,6}等[妳你]|我等[妳你](?:[喔哦啦囉咯呀啊唷欸齁])?[\p{P}\p{S}]*$|等[妳你](?:來|到|下樓|出來))/u;
const MUTUAL_CUE =
  /(?:要不要|一起|我們.{0,10}(?:去|來|約|吃|喝|看|逛|玩|走|爬|打|唱|見|碰面)|[妳你](?:要|想)不要)/u;
const GENERIC_PROPOSAL =
  /(?:去|來|吃|喝|看|逛|玩|走|爬|打|唱|約|碰面|見面)[^，,。！？!?；;]{0,18}(?:吧|嗎|好不好|怎麼樣|如何)(?:[?？])?$/u;
const EXECUTION_CUE =
  /(?:我(?:來)?(?:找店|訂位|訂那間店|安排|買票|規劃)|幾點(?:見|碰面)|約在)/u;
const SELF_DISCLOSURE =
  /我[^妳你，,。！？!?；;]{0,12}(?:去|來|到|吃|喝|看|逛|玩|走|爬|打|唱|在)/u;
const MEETING_CUE =
  /(?:見面|碰面|碰(?:個|一個)面|(?:樓下|門口|車站|捷運站|咖啡店|咖啡廳|餐廳|店裡|那邊|現場|老地方)?見(?:[喔哦啦囉咯呀啊唷欸齁])?[\p{P}\p{S}]*$)/u;
const ARRANGEMENT_CONTEXT =
  /(?:到時|待會|等等|一會兒|樓下|門口|車站|捷運站|咖啡店|咖啡廳|餐廳|店裡|那邊|現場|老地方)/u;
const THIRD_PARTY_MEETING =
  /(?:(?:跟|和|找|陪)(?:朋友|同事|家人|客戶|姐妹|兄弟|他|她).{0,8}(?:見|見面|碰面|碰(?:個|一個)面)|(?:見|見面|碰面|碰(?:個|一個)面).{0,6}(?:朋友|同事|家人|客戶|姐妹|兄弟|他|她))/u;
const CLOCK_LOCATION_PLAN =
  /[0-9０-９一二三四五六七八九十兩]{1,3}[點時].{0,10}(?:樓下|門口|車站|捷運站|咖啡店|咖啡廳|餐廳|店裡|那邊|現場|老地方)(?:[喔哦啦囉咯呀啊唷欸齁])?[\p{P}\p{S}]*$/u;

function compactInviteText(value: string): string {
  return value.normalize("NFKC").replace(/\s+/gu, "");
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
  );
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
  const hasPositivePlan = hasAddresseePlan || hasMutualCue ||
    hasMeetingArrangement || hasClockLocationPlan ||
    (!selfDisclosure && hasGenericProposal) ||
    (hasExecution && (hasActivity || ARRANGEMENT_CONTEXT.test(positiveText)));

  if (
    hasSoftTime && !hasConcreteTime &&
    (hasPositivePlan || (!selfDisclosure && hasActivity))
  ) {
    return "soft";
  }
  if (
    hasAddresseePlan || hasMeetingArrangement || hasClockLocationPlan ||
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
