// 練習室動態配圖「個人拍照習慣」Step 0 探針（付費，真呼叫 fal Seedream 4.5）。
//
// 問題：同一個場景、同一個 seed、同一個模型，只把「全站固定風格前綴」換成
// 「這位角色的拍法一句」，圖看不看得出是不同的人在拍？
//
// 控制變因：4 個手寫英文場景 × 3 位角色 × {V1 現行 prompt, V2 角色拍法}＝24 張。
// V1 直接用 production 的 buildImagePrompt；seed 用 production 的 momentImageSeed，
// 同一對 V1/V2 共用同一個 seed。場景固定不走 DeepSeek，避免場景句本身帶入差異。
//
// 跑法（repo 根目錄；金鑰讀 ~/.config/fal/key 或 FAL_API_KEY）：
//   deno run --allow-read --allow-write --allow-env --allow-net \
//     tools/moments-visual-probe/run.ts [--dry-run]
// （fal 的 CDN 是 v3b.fal.media 這類子網域，--allow-net 不能只列 fal.media；
//   第一次跑就因此生成成功但下載被擋，24 張白付。）
// 每張生成成功後先把 CDN URL 追加到 out/urls.tsv 再下載；下載失敗可用
//   --redownload 依 urls.tsv 補抓，不重新生成。
// --dry-run 只印 prompt 與 seed 到 out/prompts.md，不打任何網路。
import {
  buildImagePrompt,
  momentImageSeed,
} from "../../supabase/functions/practice-chat/moments_image_gen.ts";
import { MOMENT_IMAGE_SIZE_PRESET } from "../../supabase/functions/practice-chat/moments_constants.ts";

const OUT = new URL("./out/", import.meta.url).pathname;
const ISO_DATE = "2026-09-10";
const DRY = Deno.args.includes("--dry-run");

/** 手寫場景：只有主體與場域，不帶鏡頭／光線／城市。 */
const SCENES = [
  { id: "coffee", scene: "A partly finished coffee in a plain ceramic cup on a cafe counter." },
  { id: "street", scene: "A narrow street corner after rain, wet pavement and a row of parked scooters along the curb." },
  { id: "desk", scene: "A work desk with an open notebook, a pen, and a few loose sheets of paper, some crumpled." },
  { id: "dinner", scene: "A simple home dinner: a bowl of rice with a fried egg on top and a small side dish on a kitchen table." },
] as const;

/** 報告 §4.4 前三位；拍法句＝一個取景習慣＋一個處理習慣。 */
const PROFILES = [
  {
    id: "practice_girl_004",
    name: "Mia",
    recipe: "An oblique close view with the subject slightly off-center, showing its used state and texture. Clear local contrast and neutral color under ordinary available light.",
  },
  {
    id: "practice_girl_005",
    name: "Chloe",
    recipe: "A medium view with the subject toward one side, using an edge or line in the scene as a simple graphic element, with some empty space. Clean, uncluttered, restrained color, natural contrast.",
  },
  {
    id: "practice_girl_002",
    name: "Ivy",
    recipe: "An eye-level view keeping a bit of the surrounding environment, casually framed a little off-center. Daylight-like color with clear, slightly saturated hues.",
  },
] as const;

const HARD =
  "Photorealistic everyday photograph. No people, faces, hands, body parts or silhouettes. No readable text, logos, watermarks or recognizable screen interfaces.";

function v2Prompt(scene: string, recipe: string): string {
  return `${scene}\n${recipe}\n${HARD}`;
}

async function falKey(): Promise<string> {
  const env = Deno.env.get("FAL_API_KEY");
  if (env) return env.trim();
  const home = Deno.env.get("HOME") ?? "";
  return (await Deno.readTextFile(`${home}/.config/fal/key`)).trim();
}

async function generateUrl(key: string, prompt: string, seed: number): Promise<string> {
  const res = await fetch("https://fal.run/fal-ai/bytedance/seedream/v4.5/text-to-image", {
    method: "POST",
    headers: { Authorization: `Key ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      prompt,
      image_size: MOMENT_IMAGE_SIZE_PRESET,
      num_images: 1,
      max_images: 1,
      enable_safety_checker: true,
      seed,
    }),
    signal: AbortSignal.timeout(60_000),
  });
  if (!res.ok) throw new Error(`fal_http_${res.status}`);
  const json = await res.json() as { images?: { url?: string }[] };
  const url = json.images?.[0]?.url;
  if (!url) throw new Error("fal_empty");
  return url;
}

async function download(url: string): Promise<Uint8Array> {
  const img = await fetch(url, { signal: AbortSignal.timeout(30_000) });
  if (!img.ok) throw new Error(`download_${img.status}`);
  return new Uint8Array(await img.arrayBuffer());
}

function ext(bytes: Uint8Array): string {
  return bytes[0] === 0x89 && bytes[1] === 0x50 ? "png" : "jpg";
}

const jobs: { file: string; prompt: string; seed: number }[] = [];
const md: string[] = [`# Step 0 探針 prompt 清單（${ISO_DATE}）`, ""];
PROFILES.forEach((p, pi) => {
  SCENES.forEach((s, si) => {
    const seed = momentImageSeed(p.id, ISO_DATE, si, 1);
    const v1 = buildImagePrompt(s.scene);
    const v2 = v2Prompt(s.scene, p.recipe);
    const base = `${String(pi * 8 + si * 2).padStart(2, "0")}_${p.name}_${s.id}`;
    jobs.push({ file: `${base}_v1`, prompt: v1, seed });
    jobs.push({ file: `${String(pi * 8 + si * 2 + 1).padStart(2, "0")}_${p.name}_${s.id}_v2`, prompt: v2, seed });
    md.push(`## ${p.name} × ${s.id}（seed ${seed}）`, "", "V1:", "```", v1, "```", "V2:", "```", v2, "```", "");
  });
});
await Deno.writeTextFile(`${OUT}prompts.md`, md.join("\n"));
console.log(`prompts.md written (${jobs.length} jobs)`);
if (DRY) Deno.exit(0);

const REDOWNLOAD = Deno.args.includes("--redownload");
const urlsPath = `${OUT}urls.tsv`;
const known = new Map<string, string>();
try {
  for (const line of (await Deno.readTextFile(urlsPath)).split("\n")) {
    const [file, url] = line.split("\t");
    if (file && url) known.set(file, url);
  }
} catch { /* 第一次跑沒有這個檔 */ }

const key = REDOWNLOAD ? "" : await falKey();
const log: string[] = [];
for (const job of jobs) {
  const t0 = Date.now();
  try {
    let url = known.get(job.file);
    if (!url) {
      if (REDOWNLOAD) throw new Error("no_url_recorded");
      url = await generateUrl(key, job.prompt, job.seed);
      await Deno.writeTextFile(urlsPath, `${job.file}\t${url}\n`, { append: true });
    }
    const bytes = await download(url);
    const path = `${OUT}${job.file}.${ext(bytes)}`;
    await Deno.writeFile(path, bytes);
    log.push(`${job.file}\tok\t${bytes.byteLength}B\t${Date.now() - t0}ms`);
    console.log(log.at(-1));
  } catch (e) {
    log.push(`${job.file}\tFAIL\t${e instanceof Error ? e.message : String(e)}\t${Date.now() - t0}ms`);
    console.log(log.at(-1));
  }
}
await Deno.writeTextFile(`${OUT}run.log`, log.join("\n") + "\n");
