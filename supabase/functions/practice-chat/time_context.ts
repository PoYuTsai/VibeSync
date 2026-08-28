// practice-chat server-side Taipei wall-clock context.
// Pure functions only: no client time, no DB state.

export type TaipeiDayPart =
  | "dawn"
  | "morning"
  | "noon"
  | "afternoon"
  | "early_evening"
  | "evening"
  | "late_night";

export interface TaipeiTimeContext {
  isoDate: string;
  hour: number;
  minute: number;
  weekday: number;
  isWeekend: boolean;
  dayPart: TaipeiDayPart;
}

/**
 * 時段的中文說法。放在這裡是因為「時段怎麼稱呼」跟 dayPartFor 的切點是同一份
 * 契約：改了切點卻沒改稱呼，貼文與聊天就會各講各的。
 */
export const TAIPEI_DAY_PART_LABEL: Readonly<Record<TaipeiDayPart, string>> = {
  dawn: "清晨",
  morning: "早上",
  noon: "中午",
  afternoon: "下午",
  early_evening: "傍晚",
  evening: "晚上",
  late_night: "深夜",
};

/** getUTCDay() 的 0-6 對應；weekday 已經是台北日的星期。 */
const TAIPEI_WEEKDAY_LABEL = [
  "星期日",
  "星期一",
  "星期二",
  "星期三",
  "星期四",
  "星期五",
  "星期六",
] as const;

const TAIPEI_OFFSET_MS = 8 * 60 * 60 * 1000;

function pad2(value: number): string {
  return value.toString().padStart(2, "0");
}

function dayPartFor(hour: number): TaipeiDayPart {
  if (hour >= 5 && hour < 7) return "dawn";
  if (hour >= 7 && hour < 11) return "morning";
  if (hour >= 11 && hour < 14) return "noon";
  if (hour >= 14 && hour < 17) return "afternoon";
  if (hour >= 17 && hour < 19) return "early_evening";
  if (hour >= 19 && hour < 23) return "evening";
  return "late_night";
}

export function taipeiTimeContextFor(now: Date): TaipeiTimeContext {
  const taipei = new Date(now.getTime() + TAIPEI_OFFSET_MS);
  const year = taipei.getUTCFullYear();
  const month = taipei.getUTCMonth() + 1;
  const date = taipei.getUTCDate();
  const hour = taipei.getUTCHours();
  const minute = taipei.getUTCMinutes();
  const weekday = taipei.getUTCDay();
  return {
    isoDate: `${year}-${pad2(month)}-${pad2(date)}`,
    hour,
    minute,
    weekday,
    isWeekend: weekday === 0 || weekday === 6,
    dayPart: dayPartFor(hour),
  };
}

/**
 * 把台北時間情境攤成一行人看得懂的話，例如
 * `2026-08-28（星期五・平日）09:03 早上`。
 *
 * 模型的 prompt 只吃得到我們餵的字，不會自己去看時鐘：日期、星期、時刻
 * 只要有一項沒寫進去，它就會用最近一個看得到的日期（例如她自己的貼文日期）
 * 去推「今天」，於是端出一個錯的禮拜幾還講得很有把握。這一行就是那個唯一
 * 的錨點，chat / hint / debrief 三條路徑共用同一份寫法，免得三邊各報一個時間。
 */
export function taipeiNowLabel(time: TaipeiTimeContext): string {
  const weekday = TAIPEI_WEEKDAY_LABEL[time.weekday];
  const dayType = time.isWeekend ? "週末" : "平日";
  const clock = `${pad2(time.hour)}:${pad2(time.minute)}`;
  return `${time.isoDate}（${weekday}・${dayType}）${clock} ${
    TAIPEI_DAY_PART_LABEL[time.dayPart]
  }`;
}
