// 貼文的具體時刻（決定論純函式、零 DB 狀態、零外部依賴）。
//
// 排程（moments_schedule.ts）只決定「哪個時段」，feed 需要的是「幾點幾分」：
// - client 要顯示「3 小時前」這種相對時間；
// - handler 要判斷「這則到時間了沒」——早上 8 點不該看到她今晚 23:30 的貼文，
//   也不該為那一則先燒掉一次模型呼叫。
//
// 兩條非顯然的規則：
// 1. late_night 收斂到 23:00-23:59。time_context 的 dayPartFor 把 23 點與
//    0-4 點都算成 late_night，但 post_date 在 00:00 就翻頁了；若讓深夜這一則
//    落在凌晨，它的顯示時間會跟自己的 post_date 對不起來（feed 會出現一則
//    「昨天」的貼文顯示成今天凌晨）。
// 2. 同一時段內，slot 0 一定早於 slot 1。做法是把時段切成 MOMENT_SLOT_COUNT
//    個等寬子帶，slot k 只在第 k 個子帶裡選分鐘——這樣「她今天的第一則」
//    在 feed 上就真的排在第二則前面，而不是靠運氣。
//
// 種子範式沿用 moments_schedule.ts：fnv1a 的 [0,1) 擲骰，同一組輸入永遠
// 得到同一個時刻，故生成失敗可安全重試而不會冒出第二個時間。

import type { TaipeiDayPart } from "./time_context.ts";
import { MOMENT_SLOT_COUNT } from "./moments_constants.ts";

export interface MomentDayPartWindow {
  /** 台北時的起始小時（含）。 */
  startHour: number;
  /** 台北時的結束小時（不含）。 */
  endHourExclusive: number;
}

/**
 * 各時段的台北小時區間。前六項與 time_context.ts 的 dayPartFor 一致；
 * late_night 刻意只取 23 點那一小時（見檔頭規則 1）。
 */
export const MOMENT_DAY_PART_WINDOWS: Readonly<
  Record<TaipeiDayPart, MomentDayPartWindow>
> = {
  dawn: { startHour: 5, endHourExclusive: 7 },
  morning: { startHour: 7, endHourExclusive: 11 },
  noon: { startHour: 11, endHourExclusive: 14 },
  afternoon: { startHour: 14, endHourExclusive: 17 },
  early_evening: { startHour: 17, endHourExclusive: 19 },
  evening: { startHour: 19, endHourExclusive: 23 },
  late_night: { startHour: 23, endHourExclusive: 24 },
};

const TAIPEI_OFFSET_MS = 8 * 60 * 60 * 1000;

function fnv1a(input: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < input.length; i++) {
    hash ^= input.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/** 把 ISO 日期（台北日）解析成年/月/日；格式不合法時丟錯，不靜默漂移。 */
function parseIsoDate(isoDate: string): [number, number, number] {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(isoDate);
  if (!match) throw new Error(`moment_time_invalid_iso_date:${isoDate}`);
  return [Number(match[1]), Number(match[2]), Number(match[3])];
}

/**
 * 算出這一則貼文的具體發文時刻（回傳 UTC 瞬間；client 自己轉當地時間）。
 *
 * 純函式：同樣的 (profileId, isoDate, slot, dayPart) 永遠得到同一個 Date。
 */
export function momentPostedAtFor(opts: {
  profileId: string;
  isoDate: string;
  slot: number;
  dayPart: TaipeiDayPart;
}): Date {
  const { profileId, isoDate, slot, dayPart } = opts;
  const [year, month, day] = parseIsoDate(isoDate);
  const window = MOMENT_DAY_PART_WINDOWS[dayPart];
  const totalMinutes = (window.endHourExclusive - window.startHour) * 60;

  // 子帶：slot k 只在第 k 段裡選分鐘，保證同時段內 slot 遞增。
  const bandIndex = Math.min(Math.max(slot, 0), MOMENT_SLOT_COUNT - 1);
  const bandWidth = Math.floor(totalMinutes / MOMENT_SLOT_COUNT);
  const bandStart = bandIndex * bandWidth;
  // 最後一個子帶吃掉除不盡的餘數，避免時段尾端永遠選不到。
  const bandLength = bandIndex === MOMENT_SLOT_COUNT - 1
    ? totalMinutes - bandStart
    : bandWidth;

  const seed = fnv1a(`${profileId}|${isoDate}|${slot}|${dayPart}|minute`);
  const offsetMinutes = bandStart + (bandLength > 0 ? seed % bandLength : 0);
  const hour = window.startHour + Math.floor(offsetMinutes / 60);
  const minute = offsetMinutes % 60;

  // 先算出「台北牆上時刻」對應的 UTC 瞬間：Date.UTC 給的是把台北時刻當
  // UTC 讀的值，再扣掉 +08:00 的位移就是真正的 UTC 瞬間。
  const taipeiWallClock = Date.UTC(year, month - 1, day, hour, minute, 0, 0);
  return new Date(taipeiWallClock - TAIPEI_OFFSET_MS);
}
