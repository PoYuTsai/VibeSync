// 練習室動態「配圖重複」的離線普查。純計算：不打 DB、不打模型、不寫檔。
//
// 直接 import 正式的排程／圖庫模組，所以數字跟線上是同一套規則算出來的；
// 改了 imageTags 或挑圖策略之後重跑，就知道撞圖率有沒有真的降下來。
//
// 研究結論與各策略取捨見
// docs/plans/2026-08-25-practice-moments-image-duplication.md
//
// run: deno run --allow-read tools/moments-image-census/census.ts
//  或: node --experimental-strip-types tools/moments-image-census/census.ts
import { GIRL_PROFILES } from "../../supabase/functions/practice-chat/practice_persona.ts";
import {
  fnv1a,
  type MomentDayPlan,
  momentPlanFor,
} from "../../supabase/functions/practice-chat/moments_schedule.ts";
import { taipeiTimeContextFor } from "../../supabase/functions/practice-chat/time_context.ts";
import {
  resolveAvailableMomentImages,
  SELF_PORTRAIT_IMAGE_ID,
} from "../../supabase/functions/practice-chat/moments_image_catalog.ts";
import { FEED_WINDOW_DAYS } from "../../supabase/functions/practice-chat/moments_constants.ts";

/** 模擬起算日；固定值，讓兩次執行可比較。 */
const START = Date.UTC(2026, 7, 1, 4);
/** 「一屏」約略看得到幾則有圖貼文；撞圖對數以此為視窗。 */
const SCREEN = 4;

interface FeedItem {
  day: number;
  profileId: string;
  slot: number;
  /** 畫面上實際畫出來的那張圖；相同字串＝像素級同一張。 */
  asset: string;
}

/** 一則圖文 slot 該畫哪張圖。回傳畫面資產鍵，不是 imageId。 */
type PickStrategy = (
  candidates: readonly string[],
  profileId: string,
  isoDate: string,
  slot: number,
) => string;

/** 現況：模型挑「最貼題材」的那個。用候選首項近似（實際依語意，榜首會不同）。 */
const pickModelObvious: PickStrategy = (c) => c[0];

/** 種子挑：catalog 註解本來就宣稱、但沒有呼叫端實作的那一步。 */
const pickSeeded: PickStrategy = (c, profileId, isoDate, slot) =>
  c[fnv1a(`${profileId}|${isoDate}|moment|${slot}|image_pick`) % c.length];

/** 種子挑 + client 端每 id K 個變體。自拍本來就因人而異，不需要變體。 */
const seededWithVariants = (k: number): PickStrategy =>
  (c, profileId, isoDate, slot) => {
    const id = pickSeeded(c, profileId, isoDate, slot);
    if (id === SELF_PORTRAIT_IMAGE_ID) return `${id}:${profileId}`;
    return `${id}#${fnv1a(`${profileId}|${isoDate}|${slot}|variant`) % k}`;
  };

/**
 * 組出一位使用者看得到的 feed。排序近似 postedAt：先日期，同日內用穩定雜湊，
 * 只求「同一批貼文會彼此相鄰」這個性質，不重現真正的發文時刻。
 */
function buildFeed(unlockedCount: number, pick: PickStrategy): FeedItem[] {
  const unlocked = GIRL_PROFILES.slice(0, unlockedCount);
  const feed: FeedItem[] = [];
  for (let day = 0; day < FEED_WINDOW_DAYS; day++) {
    const time = taipeiTimeContextFor(new Date(START + day * 86_400_000));
    for (const girl of unlocked) {
      let plan: MomentDayPlan;
      try {
        plan = momentPlanFor({ girl, time });
      } catch {
        continue; // 排程炸掉＝那位今天沒貼文，與 handler 的降級一致
      }
      for (const slotPlan of plan.slots) {
        if (!slotPlan.wantsImage) continue;
        const candidates = resolveAvailableMomentImages(slotPlan.imageCandidates);
        if (candidates.length === 0) continue;
        feed.push({
          day,
          profileId: girl.profileId,
          slot: slotPlan.slot,
          asset: pick(candidates, girl.profileId, time.isoDate, slotPlan.slot),
        });
      }
    }
  }
  return feed.sort((a, b) =>
    a.day - b.day ||
    fnv1a(`${a.profileId}|${a.slot}`) - fnv1a(`${b.profileId}|${b.slot}`)
  );
}

/** 相鄰 SCREEN 則內出現同一張圖的對數＝使用者一屏就看得到的撞圖。 */
function screenCollisions(feed: readonly FeedItem[]): number {
  let pairs = 0;
  for (let i = 0; i < feed.length; i++) {
    for (let j = i + 1; j < Math.min(feed.length, i + 1 + SCREEN); j++) {
      if (feed[i].asset === feed[j].asset) pairs++;
    }
  }
  return pairs;
}

function topShare(feed: readonly FeedItem[]): number {
  const counts = new Map<string, number>();
  for (const item of feed) counts.set(item.asset, (counts.get(item.asset) ?? 0) + 1);
  return Math.max(...counts.values()) / feed.length;
}

function pct(value: number): string {
  return `${(value * 100).toFixed(0)}%`;
}

const STRATEGIES: readonly { name: string; pick: PickStrategy }[] = [
  { name: "現況：模型挑最貼題材", pick: pickModelObvious },
  { name: "S2 種子挑", pick: pickSeeded },
  { name: "S2+S3 種子挑 + 3 變體", pick: seededWithVariants(3) },
  { name: "S2+S3 種子挑 + 5 變體", pick: seededWithVariants(5) },
];

console.log(
  `角色名冊 ${GIRL_PROFILES.length} 位・feed 窗 ${FEED_WINDOW_DAYS} 天・一屏視窗 ${SCREEN} 則\n`,
);

for (const unlockedCount of [20, 50, 100]) {
  const sample = buildFeed(unlockedCount, pickModelObvious);
  console.log(`===== 已解鎖 ${unlockedCount} 位｜有圖貼文 ${sample.length} 則 =====`);
  for (const { name, pick } of STRATEGIES) {
    const feed = buildFeed(unlockedCount, pick);
    const distinct = new Set(feed.map((f) => f.asset)).size;
    console.log(
      `  ${name.padEnd(24)} 相異圖 ${String(distinct).padStart(3)}` +
        `｜一屏撞圖 ${String(screenCollisions(feed)).padStart(4)} 對（${
          pct(screenCollisions(feed) / feed.length).padStart(4)
        }）｜最熱門一張佔 ${pct(topShare(feed))}`,
    );
  }
  console.log();
}

// 現況下實際用到哪幾張圖——分佈塌縮到少數幾張，就是撞圖的直接原因。
const feed = buildFeed(50, pickModelObvious);
const counts = new Map<string, number>();
for (const item of feed) counts.set(item.asset, (counts.get(item.asset) ?? 0) + 1);
console.log(`現況下 50 位解鎖的 ${feed.length} 則圖文貼文，只用到 ${counts.size} 張圖：`);
for (const [asset, n] of [...counts].sort((a, b) => b[1] - a[1])) {
  console.log(`  ${String(n).padStart(3)} 則（${pct(n / feed.length).padStart(4)}）  ${asset}`);
}
