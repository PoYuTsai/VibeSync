// Offline per-bubble pixel-colour census. NO prod / pipeline / prompt / OCR / LLM.
// Goal: test whether rendered bubble pixels separate right=green from left=gray.
// run: deno run --allow-read --allow-net tools/pixel-census/census.ts
import { decode } from "npm:jpeg-js";

const BASE = "/mnt/c/Users/eric1/OneDrive/Desktop/VibeSync測試照片/OCR測試圖片";
const GROUPS = [
  { dir: "暗色 only_left",  truth: "left"  as const, theme: "dark"  },
  { dir: "暗色 only_right", truth: "right" as const, theme: "dark"  },
  { dir: "暗色 both_sides", truth: "both"  as const, theme: "dark"  },
  { dir: "淺色 only_right", truth: "right" as const, theme: "light" },
  { dir: "淺色雙側",        truth: "both"  as const, theme: "light" },
];

const STRIDE = 2;            // downsample factor for speed
const GREEN_T = 18;          // greenness = G-(R+B)/2 ; > this => "green/me" bubble
const MIN_AREA_FRAC = 0.004; // blob must cover this fraction of (downsampled) image

type Bubble = { r:number; g:number; b:number; green:number; cx:number; area:number };

function greenness(r:number,g:number,b:number){ return g - (r+b)/2; }
function dist(r:number,g:number,b:number, br:number,bg:number,bb:number){
  return Math.hypot(r-br, g-bg, b-bb);
}
function median(a:number[]){ a.sort((x,y)=>x-y); return a[a.length>>1]; }

function bgColor(d:Uint8Array, w:number, h:number){
  // mode of 4-bit/channel histogram = dominant background colour
  const hist = new Map<number, {n:number; r:number; g:number; b:number}>();
  for(let i=0;i<d.length;i+=4*7){
    const r=d[i], g=d[i+1], b=d[i+2];
    const key=((r>>4)<<8)|((g>>4)<<4)|(b>>4);
    const e=hist.get(key)??{n:0,r:0,g:0,b:0}; e.n++; e.r+=r; e.g+=g; e.b+=b; hist.set(key,e);
  }
  let best={n:0,r:0,g:0,b:0}; for(const e of hist.values()) if(e.n>best.n) best=e;
  return {r:best.r/best.n, g:best.g/best.n, b:best.b/best.n};
}

function census(buf:Uint8Array){
  const { width:w, height:h, data:d } = decode(buf, { useTArray:true });
  const bg = bgColor(d, w, h);
  const W = Math.ceil(w/STRIDE), H = Math.ceil(h/STRIDE);
  // bubble mask on downsampled grid: pixel sufficiently far from background
  const mask = new Uint8Array(W*H);
  const idx = (x:number,y:number)=> (y*STRIDE*w + x*STRIDE)*4;
  for(let y=0;y<H;y++) for(let x=0;x<W;x++){
    const i=idx(x,y); if(i>=d.length) continue;
    if(dist(d[i],d[i+1],d[i+2], bg.r,bg.g,bg.b) > 30) mask[y*W+x]=1;
  }
  // connected components (4-conn flood fill)
  const seen=new Uint8Array(W*H); const minArea=W*H*MIN_AREA_FRAC; const bubbles:Bubble[]=[];
  const stack:number[]=[];
  for(let s=0;s<W*H;s++){
    if(!mask[s]||seen[s]) continue;
    stack.length=0; stack.push(s); seen[s]=1;
    const px:number[]=[];
    while(stack.length){
      const p=stack.pop()!; px.push(p);
      const x=p%W, y=(p/W)|0;
      const nb=[[x-1,y],[x+1,y],[x,y-1],[x,y+1]] as const;
      for(const [nx,ny] of nb){
        if(nx<0||ny<0||nx>=W||ny>=H) continue;
        const q=ny*W+nx; if(mask[q]&&!seen[q]){ seen[q]=1; stack.push(q); }
      }
    }
    if(px.length<minArea) continue;
    const rs:number[]=[], gs:number[]=[], bs:number[]=[]; let sumX=0;
    for(const p of px){
      const x=p%W, y=(p/W)|0; sumX+=x; const i=idx(x,y);
      rs.push(d[i]); gs.push(d[i+1]); bs.push(d[i+2]);
    }
    const r=median(rs), g=median(gs), b=median(bs);
    bubbles.push({ r,g,b, green:greenness(r,g,b), cx:(sumX/px.length)/W, area:px.length });
  }
  return { w, h, bg, bubbles };
}

// ---- run ----
const rows:any[] = [];
for(const grp of GROUPS){
  const dirPath = `${BASE}/${grp.dir}`;
  for(const e of [...Deno.readDirSync(dirPath)].filter(f=>/\.jpe?g$/i.test(f.name)).sort((a,b)=>a.name.localeCompare(b.name))){
    const buf = Deno.readFileSync(`${dirPath}/${e.name}`);
    const { w,h,bg,bubbles } = census(buf);
    const greens = bubbles.filter(x=>x.green>GREEN_T);
    const grays  = bubbles.filter(x=>x.green<=GREEN_T);
    rows.push({ ...grp, file:e.name, w,h, bg:`${bg.r|0},${bg.g|0},${bg.b|0}`,
      nBub:bubbles.length, nGreen:greens.length, nGray:grays.length,
      greenCx: greens.length? (greens.reduce((s,x)=>s+x.cx,0)/greens.length).toFixed(2):"-",
      grayCx:  grays.length?  (grays.reduce((s,x)=>s+x.cx,0)/grays.length).toFixed(2):"-",
      greenVals: bubbles.map(x=>x.green|0).sort((a,b)=>a-b).join(" ") });
  }
}
console.log(JSON.stringify(rows, null, 1));
