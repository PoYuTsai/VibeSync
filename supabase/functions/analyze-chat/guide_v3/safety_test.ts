// 程式自己掃的安全訊號：只看有沒有這些字（主審第 1 輪之後不再猜句型）。哪一層什麼時候用，
// 見 plan.ts（planTurn、planWithoutRead）與 flow_parts_test.ts。
import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { scanSafetyKeywords } from "./safety.ts";

const her = (content: string) => ({ isFromMe: false, content });
const me = (content: string) => ({ isFromMe: true, content });

function minorIn(...lines: string[]): boolean {
  return scanSafetyKeywords(lines.map(her)).minorWords;
}

Deno.test("未成年字眼（只在讀局面失敗時用）：有年紀、國高中、未成年的字就算，含主審找到的漏網句", () => {
  for (
    const line of [
      "我是17歲",
      "我今年剛滿17歲",
      "我高二啦",
      "人家才16歲",
      "我十六歲",
      "我還在讀高中",
      "我是國中生",
      "我未成年",
      "高一啦",
      "我們國高中都同校",
      // 簡體、全形數字照樣認得。
      "我才１６歲",
      "我读高二",
      "我还没成年，未成年喔",
    ]
  ) {
    assert(minorIn(line), line);
  }
  // 他自己說的也算（用戶本人未成年）。
  assert(scanSafetyKeywords([me("我高一"), her("真的假的")]).minorWords);
});

Deno.test("未成年字眼只看字：講以前、老師、高中同學也算（讀局面失敗時本來就不出卡，誤判無害）", () => {
  for (
    const line of [
      "我高中的時候也很愛打球",
      "以前我讀高中，很愛打球",
      "我是高中生物老師",
      "我高中同學下週結婚",
    ]
  ) {
    assert(minorIn(line), line);
  }
  for (
    const line of [
      "我28歲了",
      "我三十歲",
      "我18歲就搬出來住",
      "我在銀行上班",
      "我們週末去爬山",
    ]
  ) {
    assert(!minorIn(line), line);
  }
});

Deno.test("未成年字眼：背景也掃", () => {
  const scan = (background: Record<string, string>) =>
    scanSafetyKeywords([her("哈哈")], background).minorWords;
  assert(scan({ targetDescription: "高二學妹" }));
  assert(scan({ partnerSummary: "- 使用者確認的對方資料：17歲" }));
  assert(!scan({ targetDescription: "28歲上班族，台北人" }));
});

Deno.test("沒有背景、沒有訊息都不會出錯", () => {
  assertEquals(scanSafetyKeywords([]).minorWords, false);
  assertEquals(scanSafetyKeywords([her("")], {}).minorWords, false);
});

function selfHarmIn(line: string) {
  return scanSafetyKeywords([her(line)]);
}

Deno.test("自傷字眼：她的訊息有自殺、自殘、割腕、輕生、不想活就一律關心，含主審找到的漏網句", () => {
  for (
    const line of [
      "我要自殘了",
      "我打算自殘",
      "我真的不想活了",
      "最近一直有自殺的念頭",
      "以前割腕過",
      "有時候會想輕生",
      // 簡體也認得。
      "我又自残了",
      "我想自杀",
    ]
  ) {
    assert(selfHarmIn(line).selfHarmWords, line);
  }
});

Deno.test("自傷字眼：否定、轉述新聞也算（Eric 2026-10-18 接受的誤判：寧可先關心）", () => {
  for (
    const line of [
      "我沒有自殺的念頭",
      "新聞說那個藝人想自殺",
      "我沒有割腕啦",
      "不想活在別人的期待裡",
    ]
  ) {
    assert(selfHarmIn(line).selfHarmWords, line);
  }
});

Deno.test("想死：只算後援層（讀局面失敗才用），不會一律關心", () => {
  for (const line of ["我現在想死", "我好想死", "熱到想死", "想死你了"]) {
    const h = selfHarmIn(line);
    assert(h.wantsToDie && !h.selfHarmWords, line);
  }
});

Deno.test("自傷：沒有這些字的誇張說法都不算", () => {
  for (const line of ["熱死了", "笑死", "累死了", "餓死了"]) {
    const h = selfHarmIn(line);
    assert(!h.wantsToDie && !h.selfHarmWords, line);
  }
});

Deno.test("自傷：只掃她的訊息", () => {
  const h = scanSafetyKeywords([me("我真的不想活了"), her("怎麼了？")]);
  assertEquals([h.selfHarmWords, h.wantsToDie], [false, false]);
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
