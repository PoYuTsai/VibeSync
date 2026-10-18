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

Deno.test("金錢不掃關鍵字：主審找到的借東西、理專講投資，單獨出現都不會觸發任何東西", () => {
  for (
    const line of [
      "可以借我5分鐘嗎",
      "跟你借1支筆",
      "我是理專，沒有零風險的投資喔",
      "可以先借我五千嗎",
    ]
  ) {
    assertEquals(scanSafetyKeywords([her(line)]), {
      minorWords: false,
      selfHarmWords: false,
      wantsToDie: false,
    }, line);
  }
});
