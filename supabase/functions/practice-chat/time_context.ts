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
