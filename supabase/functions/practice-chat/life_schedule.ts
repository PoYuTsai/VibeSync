// Deterministic practice-chat life scene context.
// The scene is derived from server time + profile + thread seed; no DB state.

import type { PracticeProfile } from "./practice_persona.ts";
import type { TaipeiDayPart, TaipeiTimeContext } from "./time_context.ts";

export type SceneReplyTempo = "short" | "normal" | "engaged";

export interface PracticeSceneContext {
  id: string;
  statusLine: string;
  promptLine: string;
  replyTempo: SceneReplyTempo;
}

interface SceneEvent {
  id: string;
  statusLine: string;
  promptLine: string;
  replyTempo: SceneReplyTempo;
  availableIn?: TaipeiDayPart[];
}

const MORNING_TO_EVENING: TaipeiDayPart[] = [
  "morning",
  "noon",
  "afternoon",
  "early_evening",
  "evening",
];

const BASE_EVENTS: Record<TaipeiDayPart, SceneEvent[]> = {
  dawn: [
    {
      id: "dawn_slow_wake",
      statusLine: "剛醒，還在慢慢回神",
      promptLine:
        "妳剛醒，還在慢慢回神，回覆可以短一點、帶一點剛睡醒的鬆散感。",
      replyTempo: "short",
    },
    {
      id: "dawn_commute_prep",
      statusLine: "正準備出門，腦袋還有點空",
      promptLine: "妳正準備出門，腦袋還有點空，回覆自然簡短，不主動展開太多。",
      replyTempo: "short",
    },
  ],
  morning: [
    {
      id: "morning_work_start",
      statusLine: "剛開始上班，手邊有點忙",
      promptLine:
        "妳剛開始上班，手邊有點忙，可以回得俐落一點，但不要無故冷掉。",
      replyTempo: "short",
    },
    {
      id: "morning_coffee",
      statusLine: "剛買完咖啡，準備進入工作狀態",
      promptLine: "妳剛買完咖啡，準備進入工作狀態，可以自然帶出咖啡或通勤感。",
      replyTempo: "normal",
    },
  ],
  noon: [
    {
      id: "noon_lunch",
      statusLine: "正在吃午餐，短暫休息一下",
      promptLine: "妳正在吃午餐，短暫休息一下，回覆可以比上班時段放鬆一點。",
      replyTempo: "normal",
    },
    {
      id: "noon_late_lunch",
      statusLine: "剛忙完，正想找東西吃",
      promptLine: "妳剛忙完，正想找東西吃，可以自然有一點餓或想放空的感覺。",
      replyTempo: "normal",
    },
  ],
  afternoon: [
    {
      id: "afternoon_focus",
      statusLine: "下午工作進入卡關狀態",
      promptLine: "妳下午工作有點卡，回覆可以帶一點疲憊但仍願意接球。",
      replyTempo: "normal",
    },
    {
      id: "afternoon_errand",
      statusLine: "下午在處理一些零碎事情",
      promptLine: "妳下午在處理零碎事情，語氣可以自然、生活感強一點。",
      replyTempo: "normal",
    },
  ],
  early_evening: [
    {
      id: "early_evening_commute",
      statusLine: "剛下班，在回家的路上",
      promptLine: "妳剛下班，在回家的路上，回覆可以短一點但比白天鬆。",
      replyTempo: "normal",
    },
    {
      id: "early_evening_dinner_plan",
      statusLine: "正準備吃晚餐",
      promptLine: "妳正準備吃晚餐，可以自然接食物、餐廳或下班後放鬆的話題。",
      replyTempo: "normal",
    },
  ],
  evening: [
    {
      id: "evening_friend_dinner",
      statusLine: "剛跟朋友吃完飯，在回家的路上",
      promptLine: "妳剛跟朋友吃完飯，在回家的路上，回覆可以比白天放鬆一點。",
      replyTempo: "normal",
    },
    {
      id: "evening_home_chill",
      statusLine: "已經回到家，正在放鬆",
      promptLine: "妳已經回到家，正在放鬆，可以比白天更願意閒聊一點。",
      replyTempo: "engaged",
    },
  ],
  late_night: [
    {
      id: "late_night_winding_down",
      statusLine: "準備睡了，精神快關機",
      promptLine: "妳準備睡了，精神快關機，回覆應短、低能量，不要硬開新話題。",
      replyTempo: "short",
    },
    {
      id: "late_night_phone_scroll",
      statusLine: "睡前滑一下手機，快要收工",
      promptLine: "妳睡前滑一下手機，快要收工，回覆可以輕鬆但不要聊得太滿。",
      replyTempo: "short",
    },
  ],
};

const WEEKEND_EVENTS: SceneEvent[] = [
  {
    id: "weekend_brunch",
    statusLine: "週末剛吃完早午餐，節奏比較慢",
    promptLine:
      "妳週末剛吃完早午餐，整個人比較放鬆，可以自然多接一點生活話題。",
    replyTempo: "engaged",
    availableIn: ["morning", "noon", "afternoon"],
  },
  {
    id: "weekend_friend_outing",
    statusLine: "週末跟朋友在外面晃",
    promptLine: "妳週末跟朋友在外面晃，回覆可以帶一點正在移動或分心的感覺。",
    replyTempo: "normal",
    availableIn: ["afternoon", "early_evening", "evening"],
  },
];

const INTEREST_EVENTS: Array<{ keywords: string[]; event: SceneEvent }> = [
  {
    keywords: ["潛水", "衝浪", "海"],
    event: {
      id: "interest_ocean_plan",
      statusLine: "正在看週末海邊行程",
      promptLine: "妳正在看週末海邊行程，可以自然接潛水、衝浪或出門玩的話題。",
      replyTempo: "engaged",
      availableIn: MORNING_TO_EVENING,
    },
  },
  {
    keywords: ["瑜珈", "健身", "舞蹈"],
    event: {
      id: "interest_body_class",
      statusLine: "剛結束一堂運動課，有點累但心情不錯",
      promptLine:
        "妳剛結束一堂運動課，有點累但心情不錯，可以自然接身體放鬆或生活節奏。",
      replyTempo: "normal",
      availableIn: ["early_evening", "evening"],
    },
  },
  {
    keywords: ["咖啡", "甜點", "烘焙"],
    event: {
      id: "interest_cafe_note",
      statusLine: "剛收藏一間看起來不錯的咖啡店",
      promptLine:
        "妳剛收藏一間看起來不錯的咖啡店，可以自然接咖啡、甜點或踩點話題。",
      replyTempo: "engaged",
      availableIn: MORNING_TO_EVENING,
    },
  },
  {
    keywords: ["追劇", "電影", "音樂", "書"],
    event: {
      id: "interest_media_chill",
      statusLine: "正在放空看點東西",
      promptLine: "妳正在放空看點東西，可以自然接追劇、電影、音樂或書的話題。",
      replyTempo: "normal",
      availableIn: ["evening"],
    },
  },
];

const PROFESSION_EVENTS: Record<string, SceneEvent> = {
  nurse_hospital: {
    id: "profession_hospital_shift",
    statusLine: "剛下護理班，體力有點被抽乾",
    promptLine: "妳剛下護理班，體力有點被抽乾，回覆可以短但不是針對對方冷。",
    replyTempo: "short",
  },
  flight_attendant: {
    id: "profession_flight_recover",
    statusLine: "剛結束一段飛行，時差感還沒退",
    promptLine: "妳剛結束一段飛行，時差感還沒退，可以自然帶出累或移動感。",
    replyTempo: "short",
  },
  graduate_student: {
    id: "profession_grad_paper",
    statusLine: "剛從論文或研究資料裡抬頭",
    promptLine:
      "妳剛從論文或研究資料裡抬頭，可以自然有一點腦袋還卡在資料裡的感覺。",
    replyTempo: "normal",
    availableIn: ["afternoon", "early_evening", "evening"],
  },
};

function fnv1a(value: string): number {
  let hash = 0x811c9dc5;
  for (let index = 0; index < value.length; index++) {
    hash ^= value.charCodeAt(index);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

function pickEvent(events: SceneEvent[], seed: string): SceneEvent {
  return events[fnv1a(seed) % events.length];
}

function interestEventsFor(profile: PracticeProfile): SceneEvent[] {
  const tags = [
    ...profile.girl.interestTags,
    ...profile.girl.lifestyleTags,
    profile.girl.professionLabel,
  ].join("、");
  return INTEREST_EVENTS
    .filter((entry) => entry.keywords.some((keyword) => tags.includes(keyword)))
    .map((entry) => entry.event);
}

function eventIsAvailable(event: SceneEvent, dayPart: TaipeiDayPart): boolean {
  return event.availableIn === undefined || event.availableIn.includes(dayPart);
}

export function buildPracticeSceneContext(opts: {
  profile: PracticeProfile;
  time: TaipeiTimeContext;
  visiblePracticeThreadId?: string | null;
}): PracticeSceneContext {
  const professionEvent = PROFESSION_EVENTS[opts.profile.girl.professionId];
  const events = [
    ...BASE_EVENTS[opts.time.dayPart],
    ...(opts.time.isWeekend ? WEEKEND_EVENTS : []),
    ...interestEventsFor(opts.profile),
    ...(professionEvent ? [professionEvent] : []),
  ].filter((event) => eventIsAvailable(event, opts.time.dayPart));
  const seed = [
    opts.profile.girl.profileId,
    opts.time.isoDate,
    opts.time.dayPart,
    opts.visiblePracticeThreadId ?? "no-thread",
  ].join("|");
  return pickEvent(events, seed);
}
