// 程式自己掃的安全訊號：明講的才算，以前的事、別人的事、誇張說法都不算。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { scanSafetyKeywords } from "./safety.ts";

const her = (content: string) => ({ isFromMe: false, content });
const me = (content: string) => ({ isFromMe: true, content });

function minorIn(...lines: string[]): boolean {
  return scanSafetyKeywords(lines.map(her)).minor;
}

Deno.test("未成年：她或他自己明講現在的年紀、年級、未成年就算", () => {
  for (
    const line of [
      "我高二啦",
      "我現在高三，要準備學測",
      "我才國三而已",
      "人家才16歲",
      "我今年17",
      "我十六歲",
      "我還在讀高中",
      "我是高中生",
      "我還沒成年喔",
      "我未成年",
      "我也才高一",
      "高二啦",
      "16歲而已",
      // 簡體、全形數字照樣認得。
      "我才１６歲",
      "我读高二",
      "我还没成年",
    ]
  ) {
    assert(minorIn(line), line);
  }
  // 他自己說的也算（用戶本人未成年）。
  assert(scanSafetyKeywords([me("我高一"), her("真的假的")]).minor);
});

Deno.test("未成年：講以前、講別人、泛稱高中，或老師在講學生都不算", () => {
  for (
    const line of [
      "我高中的時候也很愛打球",
      "以前讀高中都騎腳踏車",
      "我以前讀高中的時候很叛逆",
      "我高中同學下週結婚",
      "我高中老師超嚴",
      "高中老師都這樣啦",
      "我高三那年搬到台北",
      "我高一就開始打工了",
      "我國一到國三都住宿",
      "我高中生活很無聊",
      "我17歲的時候第一次出國",
      "我今天帶高二去校外教學，學生超吵",
      "我們班國三的學生要會考了",
      "我教高三數學",
      "我是高一導師",
      "我是高中老師",
      "我妹今年高二",
      "我弟才16歲",
      "未成年不能喝酒喔",
      "未滿18歲禁止進入",
      "你當我三歲小孩",
      "我28歲了",
      "我三十歲",
      "我18歲就搬出來住",
      "再高一點就好了",
      "我去美國三天",
      "我16號有空",
      "我今年17號要出差",
    ]
  ) {
    assert(!minorIn(line), line);
  }
});

Deno.test("未成年：背景裡他寫她（她、對方、欄位開頭）也算；寫別人、寫以前不算", () => {
  const scan = (background: Record<string, string>) =>
    scanSafetyKeywords([her("哈哈")], background).minor;
  assert(scan({ targetDescription: "高二學妹" }));
  assert(scan({ targetDescription: "17歲，很可愛" }));
  assert(scan({ analysisContextNote: "她現在高三，我大一" }));
  assert(scan({ partnerSummary: "- 使用者確認的對方資料：高一" }));
  assert(scan({ analysisContextNote: "對方今年16" }));
  assert(!scan({ meetingContext: "高中同學" }));
  assert(!scan({ targetDescription: "28歲上班族，高雄人" }));
  assert(!scan({ analysisContextNote: "她弟弟國三，她常幫忙看功課" }));
  assert(!scan({ duration: "高中就認識了" }));
  assert(!scan({ targetDescription: "高中老師" }));
});

Deno.test("沒有背景、沒有訊息都不會出錯", () => {
  assertEquals(scanSafetyKeywords([]).minor, false);
  assertEquals(scanSafetyKeywords([her("")], {}).minor, false);
});

function selfHarmIn(...lines: string[]) {
  return scanSafetyKeywords(lines.map(her));
}

Deno.test("自傷：她明講想自殺、不想活了、割腕、自殘，是最明確的一層", () => {
  for (
    const line of [
      "我真的不想活了",
      "我不想再活下去",
      "最近一直有自殺的念頭",
      "我想自殺",
      "我又自殘了",
      "以前割腕過",
      "有時候會想輕生",
      // 簡體也認得。
      "我又自残了",
      "我想自杀",
    ]
  ) {
    const h = selfHarmIn(line);
    assert(h.selfHarmExplicit && h.selfHarm, line);
  }
});

Deno.test("自傷：「我好想死」只算後援層（讀局面失敗才用），不強制關心", () => {
  for (const line of ["我好想死", "真的想死", "好想去死"]) {
    const h = selfHarmIn(line);
    assert(h.selfHarm && !h.selfHarmExplicit, line);
  }
});

Deno.test("自傷：誇張說法、想念、講別人或電影、勸人的話都不算", () => {
  for (
    const line of [
      "熱死了",
      "笑死",
      "累死了",
      "熱到想死",
      "笑到我想死",
      "累得想死",
      "想死你了",
      "我好想死你喔",
      "自殺小隊好看嗎",
      "新聞說那個藝人輕生了",
      "我不想自殺啦，只是累",
      "不要自殺喔",
      "這樣熬夜根本自殘",
      "不想活在別人的期待裡",
      "沒有咖啡我活不下去",
    ]
  ) {
    const h = selfHarmIn(line);
    assert(!h.selfHarm && !h.selfHarmExplicit, line);
  }
});

Deno.test("自傷：只掃她的訊息", () => {
  const h = scanSafetyKeywords([me("我真的不想活了"), her("怎麼了？")]);
  assertEquals([h.selfHarm, h.selfHarmExplicit], [false, false]);
});

function moneyIn(...lines: string[]): boolean {
  return scanSafetyKeywords(lines.map(her)).money;
}

Deno.test("金錢：她要他借錢、轉帳、代付儲值，拉他投資，或叫他下載 App 又講到錢", () => {
  for (
    const line of [
      "可以先借我五千嗎，下個月還你",
      "我想跟你借點錢",
      "借我2000就好",
      "你可以轉帳給我嗎",
      "先匯給我，我明天就還",
      "幫我儲值一下遊戲點數",
      "我舅舅是分析師，可以帶你一起投資",
      "這個平台穩賺不賠",
      "你先入金一萬試試看",
      "我都換成USDT轉過去",
      "下載這個APP，我教你怎麼操作獲利",
      "加入我們的投資群組，裡面老師會報明牌",
      // 簡體。
      "可以借我钱吗",
      "你转账给我就好",
    ]
  ) {
    assert(moneyIn(line), line);
  }
});

Deno.test("金錢：分帳、她自己在金融業上班、聊她的工作、單純換 LINE 都不算", () => {
  for (
    const line of [
      "AA就好，我轉帳給你",
      "晚餐我先付，你那份轉帳給我就好",
      "我們分帳吧，等等匯給我一半",
      "我轉給你了喔",
      "我在銀行上班，每天都在幫客戶處理投資",
      "我是理專，最近很多人問基金",
      "我在券商上班，今天客戶一直問入金的問題",
      "公司下單系統又當機了",
      "我做跨境電商，每天都在跟單",
      "我們換LINE聊吧",
      "下載這個App可以看我拍的照片",
      "借我看一下你的照片",
      "可以借我充電器嗎",
      "可以跟你借個充電器嗎",
      "借我一點時間想一下",
      "我最近在學投資理財",
    ]
  ) {
    assert(!moneyIn(line), line);
  }
  // 只掃她的訊息：他自己說要借她錢不算。
  assertEquals(
    scanSafetyKeywords([me("要不要我借妳錢"), her("不用啦")]).money,
    false,
  );
});
