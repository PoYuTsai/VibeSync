// 練習室動態的日期小工具（純函式、零依賴）。
//
// 獨立成模組的理由（第四輪複審 P3）：feed handler、記憶挑選、配圖清掃都
// 需要「台北日往前推 N 天」。原本 handler 與 memory 各留一份、清掃模組又
// 反向 import handler，形成 handler ↔ sweep 的循環依賴。共用 helper 放在
// 這裡，三邊都只單向依賴這一個葉節點模組。
//
// 台北日以 ISO 日字串（YYYY-MM-DD）表示；時區換算在 time_context.ts，
// 這裡只做日期加減，刻意不碰時鐘。

/** 台北日往前／往後推 N 天（負數往前）。 */
export function shiftIsoDate(isoDate: string, days: number): string {
  const shifted = new Date(`${isoDate}T00:00:00.000Z`);
  shifted.setUTCDate(shifted.getUTCDate() + days);
  return shifted.toISOString().slice(0, 10);
}
