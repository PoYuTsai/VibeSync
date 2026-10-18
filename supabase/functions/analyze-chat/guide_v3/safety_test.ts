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
