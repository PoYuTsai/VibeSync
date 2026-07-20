// Ordered, deterministic Game invite classifier.
//
// A single user message can contain a proposal, a later retraction, or quoted
// third-party speech. Keep those events ordered: returning on the first
// activity word makes both Hint routing and Debrief phase evidence unstable.

interface InviteUnit {
  text: string;
  question: boolean;
  startQuoteDepth: number;
  endQuoteDepth: number;
  openedQuote: boolean;
  closedQuote: boolean;
}

const PAST_PATTERN =
  /(?:昨天|前天|前幾天|前陣子|上週|上星期|上禮拜|上個星期|上個禮拜|上個月|去年|前年|幾年前|多年前|上次|之前|先前|早先|稍早|當時|那時|以前|曾經|剛才|剛剛|剛(?!好)|那天|本來|原本|去過|喝過|吃過|看過|逛過|(?:喝|吃|看|逛|玩|走|跑|騎|唱|碰|見|聚)完)/u;
const CONTEXT_TOKEN_PATTERN =
  /(?:(?:這|下|上|本)週[一二三四五六日天]|(?:這|下|上|本|上個)星期[一二三四五六日天]|(?:這|下|上|本|上個)禮拜[一二三四五六日天]|今天|今晚|明早|明晚|明天|後天|這週末|這週|下週|上週|本週|週末|週[一二三四五六日天]|星期[一二三四五六日天]|禮拜[一二三四五六日天]|下次|上次|改天|哪天|有空|有機會|找(?:個)?時間|找天|找一天|下班後|放假後|昨天|前天|剛才|剛剛|那天|後來|原本|本來)/gu;
const FUTURE_PATTERN =
  /(?:這週末|這週|下週(?:末)?|下下週(?:末|[一二三四五六日天])?|下星期|下禮拜|下個星期|下個禮拜|本週|下個週末|下個週[一二三四五六日天]|下個星期[一二三四五六日天]|下個禮拜[一二三四五六日天]|(?:本)?月(?:初|中|底)(?:(?:週|星期|禮拜)[一二三四五六日天])?|月底(?:(?:週|星期|禮拜)[一二三四五六日天])?|下次|改天|有空(?:的話)?|有機會|找(?:個)?時間|找天|找一天|哪天|週末|(?:這|下|本)?週[一二三四五六日天]|(?:這|下|本)?星期[一二三四五六日天]|(?:這|下|本)?禮拜[一二三四五六日天]|明天|後天|今晚|明早|明晚|晚點|晚一點|晚一週|待會|等等|下班後|休假那天|今天(?:晚上|晚點|下班後)|\d{1,2}[\/月]\d{1,2}(?:日|號)?|(?:早上|中午|下午|晚上|晚間|傍晚|午後)?\d{1,2}(?::\d{2}|點(?:半)?))/u;
const STRONG_FUTURE_PATTERN =
  /(?:下次|改天|有空(?:的話)?|有機會|找(?:個)?時間|找天|找一天|哪天)/u;
const CALENDAR_FUTURE_PATTERN =
  /(?:這週末|這週|下週(?:末)?|下下週(?:末|[一二三四五六日天])?|下星期|下禮拜|下個星期|下個禮拜|本週|下個週末|下個週[一二三四五六日天]|下個星期[一二三四五六日天]|下個禮拜[一二三四五六日天]|(?:本)?月(?:初|中|底)(?:(?:週|星期|禮拜)[一二三四五六日天])?|月底(?:(?:週|星期|禮拜)[一二三四五六日天])?|週末|(?:這|下|本)?週[一二三四五六日天]|(?:這|下|本)?星期[一二三四五六日天]|(?:這|下|本)?禮拜[一二三四五六日天]|明天|後天|今晚|明早|明晚|晚點|晚一點|待會|等等|下班後|今天(?:晚上|晚點|下班後)|\d{1,2}[\/月]\d{1,2}(?:日|號)?|(?:早上|中午|下午|晚上|晚間|傍晚|午後)?\d{1,2}(?::\d{2}|點(?:半)?))/u;
const DYAD_PATTERN =
  /(?:一起|我們|咱們|(?:跟|和)[妳你]|(?:跟|和|陪|帶)我|找[妳你我]|(?:帶|陪|接|載)[妳你]|來找我|(?:去|來|到|上)(?:我(?:家|這裡|這邊|這兒|工作室|住的地方)|[妳你]家))/u;
const GENERIC_ACTIVITY_PATTERN =
  /(?:去|來|過來|喝|吃|走|散步|逛|看|玩|爬|跑|打|唱|碰|見|踩|晃|聚|換|野餐|騎|聽|游泳|健身|露營|續攤|陶藝|旅行|拍照|做菜|烤肉|泡湯|兜風|遛狗)/u;
const OUTING_ACTION_PATTERN =
  /(?:喝(?:個|一|兩|幾)?(?:杯)?(?:咖啡|茶|飲料|酒|調酒)|喝(?:一|兩|幾)?杯|吃(?:個|一|頓)?(?:飯|早餐|午餐|晚餐|宵夜|早午餐|拉麵|火鍋|燒肉|牛排|甜點|義大利麵|披薩|漢堡|咖哩|蛋糕|好吃的)|走走|散步|逛(?:逛|街|市集|夜市|書店|咖啡店|咖啡廳|公園|動物園|植物園|水族館|博物館|美術館)|看(?:個)?(?:展|展覽|電影|戲|表演|夜景|日出|夕陽|球賽)|玩(?:桌遊|密室|遊戲|電動)|爬(?:山|步道)|跑步|打(?:球|保齡球|羽球|籃球|網球)|唱(?:歌|ktv)|碰(?:個面|一面|一下)|見(?:個面|一面|一下|面)|踩點|晃(?:一下|晃晃)|小酌|聚(?:聚|餐|一下)|換(?:一|另)?間|出來|過來|(?:去|來|到|上)(?:我家|妳家|你家|我這(?:裡|邊|兒)|我工作室|我住的地方|那間店|(?:找)?[妳你我]|咖啡店|咖啡廳|酒吧|餐廳|市集|夜市|海邊|山上|河濱|書店|公園|展覽|音樂祭|唱歌|爬山|散步|逛街|看電影|看展)|找[妳你我]|當(?:一次)?.{1,10}教練|野餐|騎(?:腳踏車|單車|自行車)|聽(?:演唱會|音樂會|live|(?:一場)?(?:爵士|現場|音樂)(?:演出|表演))|游泳|健身|露營|續攤|陶藝(?:教室|課)?|旅行|音樂祭|拍照|做菜|烤肉|泡湯|兜風|遛狗)/iu;
const OUTING_NOUN_SOURCE =
  "(?:咖啡|下午茶|早午餐|早餐|午餐|晚餐|宵夜|吃飯|義大利麵|拉麵|壽司|火鍋|燒肉|牛排|披薩|漢堡|咖哩|蛋糕|甜點|冰店|飲料|調酒|居酒屋|餐酒館|酒館|酒吧|貓咖|約會|電影|展覽|夜景|市集|夜市|書店|公園|海邊|河濱|動物園|植物園|海生館|水族館|博物館|美術館|音樂祭|演唱會|音樂會|舞會|桌遊|密室|ktv)";
const OUTING_NOUN_PATTERN = new RegExp(OUTING_NOUN_SOURCE, "iu");
const SHORTHAND_TIME_SOURCE =
  "(?:這週末|這週|下週|下下週(?:末|[一二三四五六日天])?|明天|後天|今晚|明早|明晚|週末|下個週[一二三四五六日天]|下個星期[一二三四五六日天]|下個禮拜[一二三四五六日天]|(?:本)?月(?:初|中|底)(?:(?:週|星期|禮拜)[一二三四五六日天])?|月底(?:(?:週|星期|禮拜)[一二三四五六日天])?|(?:這|下|本)?週[一二三四五六日天]|(?:這|下|本)?星期[一二三四五六日天]|(?:這|下|本)?禮拜[一二三四五六日天]|\\d{1,2}[\\/月]\\d{1,2}(?:日|號)?|改天|下次|有空)(?:(?:早上|中午|下午|晚上|晚間|傍晚|午後)(?:[零〇一二三四五六七八九十兩\\d]{1,3}點(?:半|[零〇一二三四五六七八九十兩\\d]{1,3}分)?|\\d{1,2}:\\d{2})?|[零〇一二三四五六七八九十兩\\d]{1,3}點(?:半|[零〇一二三四五六七八九十兩\\d]{1,3}分)?|\\d{1,2}:\\d{2})?";
const KNOWN_NOUN_SHORTHAND_PATTERN = new RegExp(
  `^${SHORTHAND_TIME_SOURCE}${OUTING_NOUN_SOURCE}(?:吧|嗎|啊|呀|啦)?$`,
  "iu",
);
const GENERIC_NOUN_SHORTHAND_PATTERN = new RegExp(
  `^${SHORTHAND_TIME_SOURCE}([\\p{Script=Han}a-z0-9]{1,12})(?:吧|嗎|啊|呀|啦)?$`,
  "iu",
);
const TERMINAL_RETRACTION_PATTERN =
  /(?:(?:先|暫時|暫且)?(?:取消(?:了|掉|(?:這個)?(?:安排|行程)|這一趟)?|撤回|撤掉|撤銷|作罷|暫停(?:一下)?|擱(?:(?:著|置)(?:這個)?(?:安排|行程)?|一擱)|不排(?:了)?|不(?:看|逛|走|吃|喝)(?:了)?|不要(?:安排|排|約)(?:了)?|喊停|往後延|延後(?:再決定|再說)?|緩一下|不要(?:了)?|不去了|不約(?:了)?|不碰面了|不見面了)|先把(?:這次|這項|這個)?(?:邀約|邀請|安排|計畫|行程).{0,4}(?:取消掉|撤銷|拿掉)|請當作我沒有提出|這項安排現在撤銷|我收回(?:剛才|方才)的(?:邀約|邀請)|我收回(?:剛才|方才)約[妳你].{0,12}的內容|這趟計畫(?:就)?不成立(?:了)?|請忽略剛才約[妳你]的內容|剛才是在說笑|(?:這件事)?先放一邊|等以後再說|剛才的邀請請忽略|(?:這次)?行程不成立|我決定撤銷剛才的安排|先把這個約拿掉|那句約[妳你].{0,12}的話作廢|不去.{1,12}了|算了|收回|(?:我)?收回這個(?:提議|邀請|安排)|這個(?:提議|邀請|安排|行程)(?:作廢|取消)|先別(?:安排|約(?:了)?|排(?:了)?)|當我沒(?:提|講|說)(?:過)?|剛剛那句不算數|不算(?:了)?|改天再說|下次再說|改期再說|之後再說|沒有要約(?:[妳你])?|沒要約(?:[妳你])?|不是要約|開玩笑(?:啦|的)?|只是開玩笑|別當(?:真|一回事)|別認真|當作沒聽到|我亂講的|我隨口說的|只是亂講|只是說著玩的|說笑的|鬧[妳你]的|逗[妳你]的|(?:這次)?先跳過|跳過|暫緩|(?:這回|這次)?(?:先)?免了|暫時作廢|(?:先|暫時)?(?:放著|緩緩)|不要好了|先不要(?:了)?|(?:我|我們|妳|你)?(?:沒空|沒有空|不能去|無法去|不方便|去不了))(?:吧|啦|啊|呀)?$/u;
const CANCELLATION_STATEMENT_PATTERN =
  /^(?:我|我們)?(?:已經|先)?取消(?:了)?(?=.{0,24}(?:一起|約|邀|去|來|喝|吃|看|逛|玩|碰|見|聚))/u;
const TIME_ONLY_REPLACEMENT_PATTERN =
  /^(?:(?:改(?:到|在|成|為|至|排|約)?|換(?:到|成)?|挪到|移(?:到|至)|延(?:後)?(?:到|至)?|順延(?:到|至)|另約|另訂|排在))?(?:明早|明天|後天|今晚|明晚|這週末|這週|下週(?:末|[一二三四五六日天])?|下下週(?:末|[一二三四五六日天])?|(?:這|下)星期(?:[一二三四五六日天])?|下禮拜(?:[一二三四五六日天])?|下個週末|下個週[一二三四五六日天]|下個星期[一二三四五六日天]|下個禮拜[一二三四五六日天]|(?:本)?月(?:初|中|底)(?:(?:週|星期|禮拜)[一二三四五六日天])?|月底(?:(?:週|星期|禮拜)[一二三四五六日天])?|本週(?:[一二三四五六日天])?|週末|週[一二三四五六日天]|星期[一二三四五六日天]|禮拜[一二三四五六日天]|早上|中午|下午|晚上|晚間|傍晚|午後|晚一點|晚一週|[零〇一二三四五六七八九十兩\d]{1,3}點(?:半)?|\d{1,2}(?::\d{2})?)(?:(?:早上|中午|下午|晚上|晚間|傍晚|午後)(?:[零〇一二三四五六七八九十兩\d]{1,3}點(?:半)?|\d{1,2}(?::\d{2})?)?|(?:[零〇一二三四五六七八九十兩\d]{1,3}點(?:半)?|\d{1,2}(?::\d{2})?))?(?:吧|啦|啊|呀|好嗎)?$/u;
const ACTIVE_INVITE_CONSTRAINT_PATTERN =
  /^(?:不用|不必|不要|別)(?:安排|弄|走|跑|排|約|待|穿|吃|喝|玩|選|點|加|回家|睡).{0,8}(?:(?:得|到)?(?:那麼|這麼|太|過於).+|過(?:頭|量))$/u;

// Keep one structural vocabulary for the newer natural calendar forms. The
// legacy regexes above remain for compatibility, while every semantic layer
// below reuses these two patterns instead of growing another private list.
const CONCRETE_FUTURE_TIME_PATTERN =
  /(?:這個週末|這個(?:星期|禮拜)[一二三四五六日天]|下下個(?:星期|禮拜)[一二三四五六日天]|下個月(?:初|中|底|第一個週末)|本月(?:初|中|底|最後一個週[一二三四五六日天])|月底的?(?:星期|禮拜)[一二三四五六日天]|[一二三四五六七八九十]{1,3}月[一二三四五六七八九十廿]{1,3}(?:日|號)|下課後|有空時)/u;
const LEADING_PLAN_TIME_PATTERN =
  /^(?:下(?:個)?(?:星期|禮拜)(?=一起|我們|咱們|我|妳|你|跟|和|陪|帶|接|載|找|去|來|到)|(?:這|下|本)?週[一二三四五六日天]|(?:這|下|本|這個|下個|下下個)?星期[一二三四五六日天]|(?:這|下|本|這個|下個|下下個)?禮拜[一二三四五六日天]|這個週末|下個月(?:初|中|底|第一個週末)|本月(?:初|中|底|最後一個週[一二三四五六日天])|月底(?:的)?(?:星期|禮拜)[一二三四五六日天]|月底|月初|月中|今天|今晚|明早|明晚|明天|後天|這週末|這週|本週|下週(?:末)?|下下週(?:末|[一二三四五六日天])?|下星期|下禮拜|下個星期|下個禮拜|早上|上午|中午|下午|晚上|晚間|傍晚|午後|週末|晚點|晚一點|有空(?:時)?|下班後|下課後|[一二三四五六七八九十]{1,3}月[一二三四五六七八九十廿]{1,3}(?:日|號))(?:(?:早上|上午|中午|下午|晚上|晚間|傍晚|午後)(?:[零〇一二三四五六七八九十兩\d]{1,3}點(?:半)?)?)?/u;
const META_SOURCE_PATTERN =
  /(?:草稿|文案|範例|例句|模板|備忘錄|筆記|台詞|測試資料|系統(?:範例)?輸入|投影片|聊天紀錄|截圖|錄音|原句|訊息|說法|邀法|語氣練習|角色扮演)/u;
const META_OPERATION_PATTERN =
  /(?:改寫|改得|潤飾|校對|打分|評估|記錄|引用|重述|示範|辨識|怎麼說|怎麼寫|怎麼回|可以說|建議回|寫|記著|抄著|想放|可以用|可以寫|收藏|純粹做)/u;
const REPORTED_ENVELOPE_PATTERN =
  /(?:^(?:她|他|同事|朋友|主管|教練|老師|助教|隊長|主持人|男生|男方|阿[\p{Script=Han}]{1,3}|[a-z][a-z.'-]{0,20}|[\p{Script=Han}]{0,8}(?:老師|助教|教練|領隊|師傅|團長|店員|隊長|志工|策展人)(?:(?:小|阿)[\p{Script=Han}]{1,3})?)(?:在(?:群組|訊息|聊天|錄音)裡)?(?:原本)?(?:跟我)?(?:說|問|提過|傳|提議)|(?:聊天紀錄|截圖|錄音|小說|範例對話|筆記|節目).{0,16}(?:說|問|提議|寫|抄)|(?:引用|重述).{0,12}(?:話|邀請|訊息))/iu;
const EXPLICIT_NO_INVITE_PATTERN =
  /(?:沒有|沒|不是|不會|不要).{0,8}(?:在)?(?:約|邀|安排(?:見面)?|見面)|(?:沒有|沒)(?:要|打算)(?:約|邀|安排)|(?:不是|不會)(?:在)?約/u;
const ADMINISTRATIVE_PURPOSE_PATTERN =
  /(?:監理站.{0,8}(?:驗|辦|換)|銀行.{0,8}(?:辦|轉帳)|驗(?:機車|汽車|車)|辦(?:轉帳|貸款|開戶)|(?:辦|換|補|申請)(?:護照|證件|簽證|駕照|文件|手續)|剪頭髮|搬家|看房|驗車|買手機|投票|打疫苗|做體檢)/u;
const NON_SOCIAL_PURPOSE_PATTERN =
  /(?:領|取|拿)(?:藥|包裹|貨)|寄件|辦(?:護照|證件|簽證|駕照|文件|手續)|修(?:手機|電腦|車|機車)|看(?:醫生|牙醫)|去(?:醫院|上班|上課|開會|報到|繳費|面試|加油)|買菜|復健|吃藥|工作(?!坊|室)|加班/u;
const STRUCTURAL_RETRACTION_PATTERN =
  /(?:(?:剛剛|剛才|方才|前面)?(?:那|這)(?:個|段|句|次|趟|件|項)?(?:提議|邀請|邀約|安排|行程|計畫|約[妳你]的話)?.{0,4}(?:不作數|不算數|作廢|請(?:直接)?忽略|先停掉|撤掉|撤銷|取消|收回(?:了)?|先別成行)|(?:那|這)(?:個|段|句|次|趟|件|項)?(?:提議|邀請|邀約|安排|行程|計畫)?我收回(?:了)?|先不要把(?:那|這)?(?:個|次|趟|件|項)?(?:提議|邀請|邀約|安排|行程|計畫|這件事)?排進去|不要安排(?:那|這)?(?:個|次|趟|件|項)?(?:邀請|邀約|安排|行程|計畫|這趟)(?:了)?|整個(?:邀請|邀約|安排|行程|計畫)?拿掉(?:吧)?|請當作我沒(?:有)?提出|當作我沒(?:有)?提出|那句(?:邀請|邀約|約[妳你])?(?:的話)?作廢|我只是隨口說的)(?:了|啦|吧|啊|呀)?$/u;
const BROAD_RETRACTION_PATTERN =
  /(?:(?:前面|前述|剛才|剛剛|方才|那|這)(?:的|個|段|句|次|趟|場|件|項)?(?:邀約|邀請|約定|提案|碰面|見面|行程|安排|計畫|約[妳你]的話).{0,8}(?:別算進去|不算(?:了|數)?|撤回|取消|刪掉|請忽略|到此為止|不認(?:了)?|視為無效|不用保留(?:了)?|不要保留(?:了)?|作罷)|(?:那|這)(?:個)?約我不認(?:了)?|(?:我)?(?:正式|決定)?(?:撤回|取消)(?:了)?(?:剛才|剛剛|方才|前面|前述)?(?:的)?(?:邀約|邀請|約定|提案|碰面|見面|行程|安排|計畫)|(?:先)?把(?:前面|前述|剛才|剛剛|方才|那|這)?(?:的|個|段|句|次|趟|場|件|項)?(?:邀約|邀請|約定|提案|碰面|見面|行程|安排|計畫)(?:刪掉|撤回|取消|拿掉)|(?:這次|那次|這趟|那趟)(?:的)?(?:邀約|邀請|約定|提案|碰面|見面|行程|安排|計畫)?(?:就)?(?:不要成行|不成行|就此作罷)|(?:不用|不必|不要|別)(?:再)?(?:安排|保留|排|留著)(?:這|那|前面|前述|剛才|剛剛|方才)?(?:個|次|趟|場|件|項|的)?(?:邀約|邀請|約定|提案|碰面|見面|行程|安排|計畫))(?:了|啦|吧|啊|呀)?$/u;
const WITHDRAWAL_PLAN_PATTERN =
  /(?:不成行(?:了)?|先不要去|先延後|往後延|暫緩|(?:取消|拿掉|撤掉|撤銷)(?:了)?|先把.{0,24}(?:拿掉|撤掉|撤銷|取消))/u;
const REPLACEMENT_OPERATOR_PATTERN =
  /(?:挪去|挪到|時間(?:改成|改到|改為|移到|移至)|重新訂在|順延到|另約|另訂|改約(?:在)?|改排|改到|改在|換成|排在)/u;

type PendingPlan = "retracted" | "double_negated" | "past" | null;

const HUMAN_ACTOR_HEAD_SOURCE =
  "(?:師|師傅|志工|(?:副)?(?:社|團|隊|店|組|班)?長|領隊|教練|助教|攤販|救生員|導覽員|策展人|老闆娘?|櫃檯(?:人員)?|工作人員|服務生|外場(?:人員)?|內場(?:人員)?|主管|經理|助理|秘書|店員|學員|同學|朋友|同事|室友)";
const DESCRIPTIVE_ACTOR_PATTERN = new RegExp(
  `^(?=.{2,24}$)[\\p{Script=Han}a-z0-9.'·・-]*${HUMAN_ACTOR_HEAD_SOURCE}(?:(?:小|阿)?[\\p{Script=Han}]{1,3})?$`,
  "iu",
);
const CONTENT_ARTIFACT_PATTERN =
  /(?:幕後(?:花絮|紀錄)|(?:語音)?導覽(?:影片)?|座位圖|即時影像|縮時攝影|沖煮示範(?:片|影片)?|示範(?:片|影片)?|電子報|攤商名單|演員訪談|節目單|藏品清單|名單|訪談|清單|新聞|開放時間|介紹(?:片|影片|文章)?|教學(?:片|影片)?|錄音(?:檔)?|官方網站|官網|網站|照片(?:集)?|攻略|宣傳(?:海報|影片)|海報|地圖|評論|評價|精華(?:剪輯|片段)?|剪輯|直播(?:回放)?|回放|轉播|菜單|規則|預告|心得|文章|貼文|短片)(?:檔|集)?$/u;
const NAV_QUERY_PATTERN =
  /(?:怎麼(?:去|到|走)|哪(?:一)?條路|哪個(?:捷運|車站)?出口|最近的?捷運站是哪個|捷運站是哪個|(?:在)?哪站下車|哪班(?:公車|捷運|車)|哪一路公車|入口在哪|(?:坐|搭)哪|轉車(?:幾次|多久)?|車程(?:要)?多久|(?:去|到).{0,10}(?:多久|多遠)|(?:搭|坐).{0,10}(?:方便|多久|多少錢)|附近.{0,8}(?:停車|停機車)|(?:能|可以|好不好)停(?:車|機車)|路況|交通)/u;
const COMPLETED_CONDITION_PATTERN =
  /^(?:(?:等)?[妳你]?(?:忙完|看完|吃完|喝完|做完|寫完|交完|辦完|修完|處理完)[\p{Script=Han}]{0,8}?|(?:我|我們|咱們|妳|你)?(?:忙完|看完|吃完|喝完|做完|寫完|交完|辦完|修完|處理完|開完|上完|收拾完)[\p{Script=Han}]{1,12}?|(?:今天|明天|後天|今晚|週末|下週)?(?:等)?[\p{Script=Han}]{0,12}?(?:忙完|下班|下課|上完課|開完會|收工|看完|吃完|喝完|做完|寫完|交完|辦完|修完|處理完|結束|完成|收尾|到期)|(?:去|看|吃|喝|辦|修|領|取|寄|買|處理)完[\p{Script=Han}]{1,8}?)(?:了)?(?:之後|以後|後)?(?:就)?(?=(?:我|我們|咱們|妳|你|一起|自己|一個人|要不要|想不想|不然|乾脆|跟|和|去|來|過來|喝|吃|看|逛|玩|碰|見|聚|陪|帶|接|載))/u;

function stripLeadingCompletedCondition(
  clause: string,
  question: boolean,
): string {
  const match = COMPLETED_CONDITION_PATTERN.exec(clause);
  if (!match) return clause;
  const tail = clause.slice(match[0].length);
  if (
    question && /^(?:等)?[妳你]/u.test(match[0]) &&
    !/(?:一起|我們|咱們|(?:跟|和|找|帶|陪|接|載)[妳你])/u.test(tail)
  ) {
    return clause;
  }
  return tail;
}

function isContentOnly(clause: string): boolean {
  const candidate = clause.replace(/(?:吧|嗎|呢|啊|呀|啦|喔|哦)+$/u, "");
  return /(?:看|聽|讀|閱讀|查|找|研究|瀏覽)/u.test(candidate) &&
    CONTENT_ARTIFACT_PATTERN.test(candidate);
}

function isNavigationOnlyQuestion(
  clause: string,
  question: boolean,
  hasDyad: boolean,
  hasDirectInvite: boolean,
  hasEscort: boolean,
): boolean {
  return question && !hasDyad && !hasDirectInvite && !hasEscort &&
    NAV_QUERY_PATTERN.test(clause);
}

function isDoubleNegatedPlanLead(clause: string): boolean {
  if (
    !/^(?:我)?(?:倒|也|可)?(?:並不是|不是說?|不是|並非|並沒有|沒有)(?:完全)?(?:我)?(?:不想|不願意?|不打算|不肯|沒想過|沒有想)/u
      .test(clause)
  ) {
    return false;
  }
  return /(?:一起|(?:跟|和|找|陪|帶|接|載)[妳你]|約[妳你]|邀[妳你])/u
    .test(clause) &&
    (OUTING_ACTION_PATTERN.test(clause) || OUTING_NOUN_PATTERN.test(clause) ||
      GENERIC_ACTIVITY_PATTERN.test(clause) || /(?:約|邀)[妳你]/u.test(clause));
}

function isDefinitePastSelfNarrative(clause: string): boolean {
  return /^(?:(?:昨天|前天|前一陣子(?:的某天)?|上上個週末|上個季度|前一個季度|前前個星期天|半年前|一年前(?:的冬天)?|前一個月|上個月初|[一二三四五六七八九十兩\d]+個月前|[一二三四五六七八九十兩\d]+(?:個)?星期以前|[一二三四五六七八九十兩\d]+週之前|前幾個星期|幾個月前|幾年前|大前年(?:春天|夏天|秋天|冬天)?|去年(?:年初|年底|暑假|寒假|春天|夏天|秋天|冬天|[一二三四五六七八九十]{1,3}月)?|前年(?:年初|年底|春天|夏天|秋天|冬天)?|(?:上個(?:禮拜|星期)|上週|上星期|上禮拜)(?:[一二三四五六日天])?(?:早上|中午|下午|晚上)?)(?:我|我們|咱們)(?:曾經|曾|有|還|當時|那時|原先|原本|想|要|打算|準備|提議過|說過|談過|計畫)?|那時(?:我|我們|咱們)|(?:本來|原本)(?:我|我們|咱們)|(?:我|我們|咱們)(?:曾經|曾|過去總會|曾打算))/u
    .test(clause);
}

function isPendingBridge(clause: string): boolean {
  return /^(?:(?:我)?(?:只是|是|而是)?(?:想|打算|準備)|只是(?:明天|今天|今晚|這週|週末)?太趕)$/u
    .test(clause);
}

function isPlanContinuation(clause: string, pending: PendingPlan): boolean {
  if (pending === null) return false;
  const ownershipClause = clause.replace(
    /^(?:(?:只是|是|而是)?(?:我)?(?:想|打算|準備))/u,
    "",
  );
  if (
    /(?:想知道|想問|討論|分享|推薦|文案|票價|價格|劇情|心得|改天再說|看狀況|取消|有事|加班|上班|工作|再聯絡|回覆)/u
      .test(clause) ||
    isContentOnly(clause) ||
    hasThirdPartyPlan(ownershipClause)
  ) {
    return false;
  }
  const operator = REPLACEMENT_OPERATOR_PATTERN.test(clause) ||
    /(?:改(?:到|在|成|為|至|排|約|去)?|換(?:到|成|去)?|挪到|移(?:到|至)|延(?:後)?(?:到|至)?|順延(?:到|至)|另約|另訂|排在)/u
      .test(clause);
  const future = FUTURE_PATTERN.test(clause) ||
    CONCRETE_FUTURE_TIME_PATTERN.test(clause) ||
    /(?:下個週末|下星期|下禮拜|週[一二三四五六日天](?:早上|中午|下午|晚上)?|晚一點)/u
      .test(clause);
  const outing = OUTING_ACTION_PATTERN.test(clause) ||
    OUTING_NOUN_PATTERN.test(clause) || /(?:見|碰)(?:面|一下)?/u.test(clause);
  const dyad = DYAD_PATTERN.test(clause) || /(?:我|我們|咱們)/u.test(clause);

  if (pending === "retracted") {
    return (operator && (future || outing || dyad)) ||
      (future && dyad && /(?:再)?(?:見|碰)/u.test(clause));
  }
  if (pending === "double_negated") {
    return (operator && future) ||
      (future && /(?:想(?:改|約|等|挑)|希望|打算|準備|要等)/u.test(clause)) ||
      (future && (outing || GENERIC_ACTIVITY_PATTERN.test(clause)) &&
        /(?:想|希望|打算|準備|要)/u.test(clause));
  }
  return future && operator && (dyad || outing);
}

function compact(text: string): string {
  return text.normalize("NFKC").toLowerCase().replace(/\s+/gu, "");
}

function scanInviteUnits(raw: string): InviteUnit[] {
  const text = compact(raw);
  const units: InviteUnit[] = [];
  const openQuotes = new Set(["「", "『", "“", "‘"]);
  const closeQuotes = new Set(["」", "』", "”", "’"]);
  const delimiters = new Set([
    "，",
    ",",
    "：",
    ":",
    "。",
    ".",
    "!",
    "！",
    "?",
    "？",
    "；",
    ";",
    "\n",
  ]);
  let buffer = "";
  let quoteDepth = 0;
  let startQuoteDepth = 0;
  let openedQuote = false;
  let closedQuote = false;

  const emit = (question: boolean): void => {
    if (buffer.length > 0 || openedQuote || closedQuote) {
      units.push({
        text: buffer,
        question,
        startQuoteDepth,
        endQuoteDepth: quoteDepth,
        openedQuote,
        closedQuote,
      });
    }
    buffer = "";
    startQuoteDepth = quoteDepth;
    openedQuote = false;
    closedQuote = false;
  };

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    if (openQuotes.has(char)) {
      openedQuote = true;
      quoteDepth += 1;
      buffer += char;
      continue;
    }
    if (closeQuotes.has(char)) {
      closedQuote = true;
      buffer += char;
      quoteDepth = Math.max(0, quoteDepth - 1);
      continue;
    }
    if (
      (char === ":" || char === "：") &&
      /\d/u.test(text[index - 1] ?? "") &&
      /\d/u.test(text[index + 1] ?? "")
    ) {
      buffer += char;
      continue;
    }
    if (delimiters.has(char)) {
      emit(char === "?" || char === "？");
      continue;
    }
    buffer += char;
  }
  emit(false);
  return units;
}

function splitTransitions(text: string): string[] {
  const primary = text
    .split(
      /(?=(?:但(?:是)?|可是|不過|然而|而是|而(?=我(?:現在)?(?:想|要|打算|準備|約|邀|跟|和))|還是|只是(?=想(?:跟|和|找|帶|陪|接|載)[妳你])|(?:現在|這次)(?=(?:我)?(?:想|要|打算|準備|約|邀|跟|和|我們|咱們))|改成|改為|改去|改喝|改吃|改看|改約|換成|換去|換喝|換吃|換看|換約))/u,
    )
    .filter((part) => part.length > 0);

  const ordered: string[] = [];
  const completedAction =
    /(?:去|來|到|上|喝|吃|走|散步|逛|看|玩|爬|跑|打|唱|碰|見|聚|辦|修|領|取|寄|買|換|開會|上班|下班|收工)/u;
  const connector =
    /(?:再|然後|接著|順便)(?=(?:一起|我們|咱們|我(?:想|要|可以)?|(?:跟|和|陪|帶|接|載)[妳你我]|去|來|到|上|喝|吃|看|逛|玩|碰|見|聚|辦|修|領|取|寄|買|換))/gu;
  for (const part of primary) {
    let cursor = 0;
    for (const match of part.matchAll(connector)) {
      const index = match.index;
      if (index <= cursor || !completedAction.test(part.slice(0, index))) {
        continue;
      }
      ordered.push(part.slice(cursor, index));
      cursor = index;
    }
    ordered.push(part.slice(cursor));
  }
  return ordered.filter((part) => part.length > 0);
}

function cleanClause(text: string): string {
  let candidate = text.replace(/[「」『』“”‘’"]/gu, "");
  let previous = "";
  while (candidate !== previous) {
    previous = candidate;
    candidate = candidate
      .replace(
        /^(?:但(?:是)?|可是|不過|然而|而是|而(?=我|我們|咱們)|還是|只是(?=想(?:跟|和|找|帶|陪|接|載)[妳你])|結果|所以|然後|接著|再(?=一起|我們|咱們|(?:跟|和|陪|帶|接|載)[妳你我]|去|來|到|上|喝|吃|看|逛|玩|碰|見|聚)|順便(?=一起|我們|咱們|(?:跟|和|陪|帶|接|載)[妳你我]|去|來|到|上|喝|吃|看|逛|玩|碰|見|聚|辦|修|領|取|寄|買|換)|至於)/u,
        "",
      )
      .replace(
        /^(?:哈哈+|呵呵+|欸嘿|嘿+|話說|是說|認真說|老實說|老實講|坦白說|坦白講|說真的|順帶一提|說不定|不知道|想知道|想了解|好奇|請問|想問一下|想問問|想問|問一下|問個問題|順便問|突然|真的|其實|這樣|或許|也許|那就|就(?=跟|和|陪|帶|接|載|找|一起|我們|咱們|去|來)|直接|最近|週末的話|有機會的話|哪天方便的話|有空的時候|聽起來不錯|反正|既然這樣|莫名|另外|對了|現在|這次)+/u,
        "",
      )
      .replace(
        /^(?:那(?=[妳你我下改週明後今有要想來])|欸|呃|嗯|那個|就是)+/u,
        "",
      )
      .replace(/^我則/u, "我")
      .replace(/^[，,：:；;]+/u, "")
      .replace(
        /^我看(?=今天|今晚|明早|明晚|明天|後天|這週末|這週|下週|週末|下次|改天|有空)/u,
        "",
      );
  }
  return candidate;
}

function isFiller(text: string): boolean {
  const candidate = text
    .replace(/[「」『』“”‘’"]/gu, "")
    .replace(/^(?:但(?:是)?|可是|不過|然而|而是|結果|所以|然後|至於)/u, "");
  return /^(?:欸|呃|嗯|喔|哦|那個|就是|她說是|他說是|然後)+[啦啊呀嘛吧]?$/u
    .test(candidate);
}

function actorCandidate(text: string): string {
  let actor = cleanClause(text)
    .replace(CONTEXT_TOKEN_PATTERN, "")
    .replace(/^我的/u, "")
    .replace(
      /^(?:後來|結果|聽說|據說|那|這|先|再|如果|假如|若是?|剛好|剛巧|乾脆|不然|可以|可能|應該|大概|一定|直接|就|還|也|都|或許|也許|還是|好|真|是|改成|改為|換成)+/u,
      "",
    );
  actor = actor.replace(
    /^(我|我們|咱們)(?:好|真|很)?(?:想|要)?$/u,
    "$1",
  );
  actor = actor.replace(
    /(?:要不要|想不想|來不來|會不會|會|想|要|打算|準備)$/u,
    "",
  );
  return actor.replace(
    /^(?:突然|真的|實在|有點|超級?|蠻|滿)?(?:好|真|很)?想$/u,
    "",
  );
}

function isThirdPartyActor(
  text: string,
  includePartner: boolean,
  allowBareName = false,
): boolean {
  const source = cleanClause(text);
  // Intent/negation grammar before a report verb is not a person's name.
  // Example: 「不是不想約妳」 must not open a third-party report scope.
  if (
    /^(?:請|麻煩|幫我|(?:那|這)(?:句|段|個|項|次|趟|件)|並不是|不是|並非|沒有|沒(?:有)?|不(?:想|要|會|能|打算|方便)|別(?:想|要)?|想要?|要|可以|應該)/u
      .test(source)
  ) {
    return false;
  }
  const actor = actorCandidate(text);
  if (!actor) return false;
  if (DESCRIPTIVE_ACTOR_PATTERN.test(actor)) return true;
  if (
    /^(?:[\p{Script=Han}]{0,12}(?:媽|爸|哥|姐|姊|姊姊|妹|弟|阿姨|叔叔|伯伯|姑姑|舅舅|朋友|同事|家人|室友|同學|客戶|主管|總監|老闆|學長|學姐|學弟|學妹|店員|店長|醫師|醫生|老師|教練|助理|秘書|學員|鄰居|房東|同伴|隊友|實習生|經理|工程師|設計師|先生|小姐))$/u
      .test(actor)
  ) {
    return true;
  }
  if (/(?:我|我們|咱們)/u.test(actor)) return false;
  if (/^[妳你]$/u.test(actor)) return includePartner;
  if (/^(?:小|阿)[\p{Script=Han}]{1,3}$/u.test(actor)) return true;
  if (/^[a-z][a-z.'-]{0,24}$/iu.test(actor)) return true;
  if (
    /[妳你]|一起|^(?:不是|並非|沒有|沒|不要|不想|不打算|不會|忍不住|真心|認真|只是亂|亂|隨口)$|(?:要不要|想不想|一起|不然|可以|想|要|打算|準備|考慮|有意|忍不住想|真心想|認真想|找|去|來|喝|吃|看|逛|玩)$/u
      .test(actor)
  ) {
    return false;
  }
  if (/^(?:他們|她們|他|她|有人|別人)$/u.test(actor)) return true;
  return allowBareName && /^[\p{Script=Han}]{2,4}$/u.test(actor) &&
    !/^(?:順便|最近|反正|另外|現在|之後|這次|莫名|如果|其實|真的|突然|晚點|待會|週末|下週|明天|明晚|今晚)$/u
      .test(actor);
}

function isDirectPastSelfPrefix(text: string): boolean {
  const prefix = compact(text).replace(
    /^(?:但(?:是)?|可是|不過|然而|結果|所以|然後|至於)/u,
    "",
  );
  const past =
    "(?:昨天(?:早上|中午|下午|晚上)?|前天(?:早上|中午|下午|晚上)?|上週(?:[一二三四五六日天])?|上星期(?:[一二三四五六日天])?|上禮拜(?:[一二三四五六日天])?|上個星期(?:[一二三四五六日天])?|上個禮拜(?:[一二三四五六日天])?|上個月(?:初|中|底)?|前一個季度|一年前(?:的冬天)?|[一二三四五六七八九十兩\\d]+個月前|[一二三四五六七八九十兩\\d]+(?:個)?星期以前|[一二三四五六七八九十兩\\d]+週之前|前幾個星期|大前年(?:春天|夏天|秋天|冬天)?|去年(?:年初|年底|暑假|寒假|春天|夏天|秋天|冬天|[一二三四五六七八九十]{1,3}月)?|前年(?:年初|年底|春天|夏天|秋天|冬天)?|幾年前|多年前|剛才|剛剛|上次|之前|先前|早先|稍早|當時|那時|以前|曾經|那天|本來|原本)";
  return new RegExp(
    `^(?:${past}(?:的時候)?(?:我|我們|咱們)|(?:我|我們|咱們)(?:在)?${past})(?:曾經|曾|有|還|想|要|打算|準備)?$`,
    "u",
  ).test(prefix);
}

function reportedSpeechFor(
  clause: string,
): { reported: boolean; opensScope: boolean; freshTail: string | null } {
  const reportVerb =
    /(?:(?:傳訊息|傳話|轉述)(?:跟[我妳你])?(?:說|講)|跟[我妳你](?:說|講)|對[我妳你](?:說|講)|告訴[我妳你]|問我|問[妳你]|問(?!題)|邀我|約我|邀[妳你]|約[妳你]|提到|提過|提議|表示|(?<!再)說|(?<!再)講(?!師))/u
      .exec(clause);
  if (!reportVerb || reportVerb.index === undefined) {
    return { reported: false, opensScope: false, freshTail: null };
  }
  const prefix = clause.slice(0, reportVerb.index);
  const pastSelf = isDirectPastSelfPrefix(prefix);
  const pastPartner = PAST_PATTERN.test(prefix) && /[妳你]$/u.test(prefix);
  const reported = pastSelf || pastPartner ||
    isThirdPartyActor(prefix, true, true);
  if (!reported) {
    return { reported: false, opensScope: false, freshTail: null };
  }

  const suffix = cleanClause(
    clause.slice(reportVerb.index + reportVerb[0].length),
  );
  const futureMatches = [
    ...suffix.matchAll(
      /(?:這個週末|這週末|這週|下週(?:末|[一二三四五六日天])?|下下週(?:末|[一二三四五六日天])?|下星期(?:[一二三四五六日天])?|下禮拜(?:[一二三四五六日天])?|下個(?:星期|禮拜)[一二三四五六日天]|下個月(?:初|中|底|第一個週末)|本月(?:初|中|底|最後一個週[一二三四五六日天])|月底(?:的)?(?:星期|禮拜)[一二三四五六日天]|下次|改天|有空(?:的話|時)?|有機會|哪天|週末|週[一二三四五六日天]|星期[一二三四五六日天]|禮拜[一二三四五六日天]|明天|後天|今晚|明早|明晚|晚點|待會|下班後|下課後|[一二三四五六七八九十]{1,3}月[一二三四五六七八九十廿]{1,3}(?:日|號))/gu,
    ),
  ];
  const reportActor = actorCandidate(prefix);
  const implicitDyadTailAllowed = pastSelf || pastPartner ||
    (PAST_PATTERN.test(prefix) && /^[妳你]$/u.test(reportActor));
  let freshTail: string | null = null;
  for (let index = futureMatches.length - 1; index >= 0; index -= 1) {
    const matchIndex = futureMatches[index].index ?? 0;
    if (matchIndex <= 0) continue;
    const candidate = cleanClause(suffix.slice(matchIndex));
    const hasFreshSelf = explicitlyReassertsSelf(candidate) ||
      hasExplicitSharedOwner(candidate) || hasExplicitSelfInvite(candidate);
    const hasImplicitDyad = /(?:一起|我們|咱們)/u.test(candidate);
    if (hasFreshSelf || (implicitDyadTailAllowed && hasImplicitDyad)) {
      freshTail = candidate;
      break;
    }
  }
  return {
    reported: true,
    opensScope: suffix.length === 0 || isFiller(suffix),
    freshTail,
  };
}

function hasThirdPartyPlan(clause: string): boolean {
  if (
    /^(?:改(?:到|在|成|為|至|排|約|去)?|換(?:到|成|去)?|挪到|移(?:到|至)|延(?:後)?(?:到|至)?|順延(?:到|至)|另約|另訂|排在)/u
      .test(clause)
  ) {
    return false;
  }
  const companionCue = /(?:跟|和|陪|帶|接|載)我/u.exec(clause);
  if (
    companionCue?.index !== undefined &&
    isThirdPartyActor(clause.slice(0, companionCue.index), false, true)
  ) {
    return true;
  }

  const planCue =
    /(?:要不要|想不想|打算|準備|都有空|一起|跟我|和我|陪我|帶我|約|邀|帶|陪|接|載|想|要|(?<!機)會(?=去|來|喝|吃|看|逛|玩|爬|跑|打|唱|碰|見|聚))/u
      .exec(clause);
  if (
    planCue?.index !== undefined &&
    isThirdPartyActor(clause.slice(0, planCue.index), false)
  ) {
    return true;
  }

  const actionSubjectClause = cleanClause(clause).replace(
    CONTEXT_TOKEN_PATTERN,
    "",
  );
  const actionCues = actionSubjectClause.matchAll(
    /(?:去|來|到|上(?=山|樓|車|船|我家|妳家|你家)|喝|吃|走|散步|逛|看|玩|爬|跑|打|唱|碰|見|聚|野餐|騎|聽|游泳|健身|露營)/gu,
  );
  for (const actionCue of actionCues) {
    if (actionCue.index <= 0 || actionCue.index > 16) continue;
    const actionSubject = actionSubjectClause.slice(0, actionCue.index);
    const actor = actorCandidate(actionSubject);
    const actionSuffix = actionSubjectClause.slice(
      actionCue.index + actionCue[0].length,
    );
    const isAdjunct =
      /(?:雨停|忙完|收工|下班|放學|課後|會後|開完(?:會)?|沒事|有空|方便(?:的話)?|可以(?:的話)?|順路|終於|臨時|的話|要不|想不|來不|會不|出來|過來|回來|(?:喝|吃|看|逛|玩)完)$/u
        .test(actor) ||
      /^(?:到|去|來|喝|吃|看|逛|玩)(?:(?:那|這|上次)(?:間)?(?:店|家)|咖啡|茶|飯|電影|展覽|市集|夜市|書店|公園|山上|海邊)/u
        .test(actor) ||
      (/^(?:完|過|好)(?:了|後)?/u.test(actionSuffix) &&
        /(?:電影|展覽|咖啡|茶|飯|書|工作|課|會)$/u.test(actor));
    if (!isAdjunct && isThirdPartyActor(actionSubject, false, true)) {
      return true;
    }
  }

  const selfWithActor =
    /^(?:今天|今晚|明早|明晚|明天|後天|這週末|這週|下週|週末|下次|改天|有空)?我(?:今天|今晚|明早|明晚|明天|後天|這週末|這週|下週|週末|下次|改天|有空)?(?:想|要|打算|準備|可以)?(?:跟|和|陪|帶)(.+?)(?=一起|去|來|喝|吃|走|散步|逛|看|玩|爬|跑|打|唱|碰|見|聚|野餐|騎|聽|游泳|健身|露營)/u
      .exec(clause);
  return selfWithActor !== null &&
    isThirdPartyActor(selfWithActor[1], false, true);
}

function hasThirdPartyDestination(clause: string): boolean {
  const match =
    /(?:去|來|到|上)([\p{Script=Han}a-z.'·・-]{1,12}?)(?:的)?(?:家|住處|工作室)(?=去|來|喝|吃|看|逛|玩|做|$)/iu
      .exec(clause) ??
      /(?:去|來|到)([\p{Script=Han}a-z.'·・-]{1,12})的(?:店|咖啡店|餐廳|工作室)/iu
        .exec(clause);
  return match !== null && isThirdPartyActor(match[1], false, true);
}

function explicitlyReassertsSelf(clause: string): boolean {
  const candidate = stripLeadingPlanTime(cleanClause(clause));
  return /^(?:我(?:想|要|可以|打算|準備)?(?:在[^妳你]{0,16})?(?:跟|和|找|帶|陪|接|載)[妳你]|我們|咱們|(?:要不要|想不想)?(?:跟|和)[妳你]|(?:要不要|想不想)?(?:跟|和|陪|帶|接|載|找)我)/u
    .test(candidate);
}

function hasExplicitSelfInvite(clause: string): boolean {
  if (/(?:跟|和)[妳你](?:說|講|聊|提|問|分享|解釋|討論)/u.test(clause)) {
    return false;
  }
  const candidate = stripLeadingPlanTime(cleanClause(clause));
  const direct =
    /^(?:我|我們|咱們)(?:(?:今天|今晚|明早|明晚|明天|後天|這週末|這週|下週|週末|下次|改天|有空|其實|真的|超|蠻|滿|倒是|現在|則|也|還|就|再|有點|好|很|都|只|還是))*(?:想|要|可以|打算|準備)?(?<![大預合解])(?:約|邀)[妳你]/u
      .test(candidate);
  if (direct) return true;
  const relational =
    /^(?:我|我們|咱們)(?:(?:今天|今晚|明早|明晚|明天|後天|這週末|這週|下週|週末|下次|改天|有空|其實|真的|超|蠻|滿|倒是|現在|則|也|還|就|再|有點|好|很|都|只|還是))*(?:想|要|可以|打算|準備)?(?:在[^妳你]{0,16})?(?:跟|和|找|帶|陪|接|載)[妳你]/u
      .test(candidate);
  return relational && OUTING_ACTION_PATTERN.test(clause);
}

function hasExplicitSharedOwner(clause: string): boolean {
  const candidate = stripLeadingPlanTime(cleanClause(clause));
  return /^(?:(?:不然|乾脆|不如|那就))?(?:(?:我們|咱們)(?:一起)?|(?:要不要|想不想)?一起|(?:我)?想在[^妳你]{0,24}(?:跟|和)[妳你]|我(?:準備|想|要|打算|可以)?(?:在[^妳你]{0,16})?(?:跟|和|帶|陪|接|載|找)[妳你](?:一起)?|我(?:準備|想|要|打算|可以)?.{0,18}(?:帶|陪|接|載)[妳你]|[妳你](?:[^我]{0,12})?(?:跟|和|陪)我(?:一起)?|(?:要不要|想不想)?(?:跟|和|陪|帶|接|載|找)我|(?:跟|和|陪|帶|接|載|找)[妳你](?:一起)?|(?:來|到|上)我(?:家|工作室|這裡|這邊|這兒))/u
    .test(
      candidate,
    );
}

function isNounShorthand(clause: string): boolean {
  if (
    KNOWN_NOUN_SHORTHAND_PATTERN.test(clause) ||
    isExtendedNounShorthand(clause)
  ) return true;
  const match = GENERIC_NOUN_SHORTHAND_PATTERN.exec(clause);
  if (!match) return false;
  const noun = match[1].replace(/[吧嗎啊呀啦]$/u, "");
  if (
    /(?:什麼|哪|幾|多少|價格|票價|菜單|規則|低消|預約|訂位|訂票|掛號|休息|休館|開放|營業|上映|開始|結束|有開|好看|好喝|好吃|很爛|很貴|便宜|擁擠|人多|很多人|五分熟|值得|適合|比較|感覺|意思|定義|工作|會議|報告|作業|醫院|牙醫|上班|加班|面試|上課|吃藥|文件|訊息|照片|文章|預告|筆記|地址|怎麼|為什麼|跟誰|誰|[妳你我]|洗澡|睡覺|買菜|垃圾|銀行|公司|家庭|部門|團隊|班級|董事|股東|家長|校務|早會|聚會|公會|同學會|例會|晨會|週會|月會|年會|記者會|說明會|研討會|發表會|法說會|運動會|聚餐|尾牙|春酒|婚禮|喪禮|法會)/u
      .test(noun)
  ) {
    return false;
  }
  return /(?:麵|飯|餐|鍋|肉|排|司|堡|薩|哩|糕|冰|茶|啡|酒|燒|館|店|吧|屋|園|展|影|景|集|祭|遊|室|會|ktv)$/iu
    .test(noun);
}

function isAnchoredCalendarAction(clause: string): boolean {
  const anchored =
    /^(?:今天|今晚|明早|明晚|明天|後天|這週末|這週|下週|週末|週[一二三四五六日天]|星期[一二三四五六日天]|禮拜[一二三四五六日天]|晚點|待會|等等|下班後)(?:(?:早上|中午|下午|晚上)?[零〇一二三四五六七八九十兩\d]{1,3}點(?:半)?)?(?:一起|我們|咱們)?(?:去|來|到|上|過來|喝|吃|看|逛|玩|走|散步|跑|唱|碰|見|聚|騎|聽|游泳|健身|露營|旅行|拍照|做菜|烤肉|泡湯|兜風|遛狗)/u
      .test(clause);
  return anchored &&
    !/(?:的人|人(?:會|也)?很多|很|超|蠻|滿|挺|對(?:身體|健康)|讓人|因為|所以|通常|常常|比較|可能|應該|覺得|聽說|好像)/u
      .test(clause);
}

function freshLiveTailAfterEnvelope(raw: string): string | null {
  const source = compact(raw);
  const boundary =
    /(?:[；;。!！](?:(?:但|不過|而|至於|接著|然後)(?=這次|這一次|我|我們|咱們|現在))?|(?:但|不過|而|至於|接著|然後)(?=這次|這一次|我|我們|咱們|現在)|[」』”’](?=我|我們|咱們)|換(?=我問[妳你])|現在(?=則))/gu;
  const matches = [...source.matchAll(boundary)];
  for (let index = matches.length - 1; index >= 0; index -= 1) {
    const match = matches[index];
    const tail = source.slice((match.index ?? 0) + match[0].length);
    if (tail && tail !== source && looksLikeGameSoftInvite(tail)) return tail;
  }
  return null;
}

function hasExplicitNoInvite(clause: string): boolean {
  if (isBroadActiveConstraint(clause)) return false;
  const hasDoubleNegativeLead =
    /^(?:我)?(?:倒|也|可)?(?:並不是|不是說?|不是|並非|並沒有|沒有)(?:完全)?(?:不想|不願意?|不打算|不肯|沒想過|沒有想)/u
      .test(clause);
  if (
    hasDoubleNegativeLead &&
    !/(?:不是|沒有|沒|不會).{0,5}(?:在)?(?:約|邀|安排(?:見面)?|見面)(?:[妳你])?(?:了|啦|喔|哦|啊|呀)?$/u
      .test(clause)
  ) {
    return false;
  }
  return EXPLICIT_NO_INVITE_PATTERN.test(clause);
}

function stripLeadingPlanTime(clause: string): string {
  let candidate = cleanClause(clause).replace(
    /^(?:不如|不然|乾脆|那就|要不)(?=今天|今晚|明早|明晚|明天|後天|這|下|本|週|星期|禮拜|月底|月初|月中|[一二三四五六七八九十]{1,3}月)/u,
    "",
  );
  let previous = "";
  while (candidate !== previous) {
    previous = candidate;
    candidate = candidate.replace(LEADING_PLAN_TIME_PATTERN, "");
    candidate = candidate.replace(
      /^(?:早上|上午|中午|下午|晚上|晚間|傍晚|午後)?[零〇一二三四五六七八九十兩\d]{1,3}點(?:半|[零〇一二三四五六七八九十兩\d]{1,3}分)?/u,
      "",
    );
  }
  return candidate;
}

function hasPartnerWithThirdPartyPlan(clause: string): boolean {
  const candidate = stripLeadingPlanTime(cleanClause(clause));
  const match =
    /^[妳你](?:今天|今晚|明天|後天|週末|下週|月底)?(?:跟|和)([^我]{1,16}?)(?=一起|去|來|到|喝|吃|看|逛|玩|聽|走|跑)/u
      .exec(candidate);
  return match !== null && isThirdPartyActor(match[1], false, true);
}

function hasExplicitPhysicalDyadPlan(clause: string): boolean {
  if (
    ADMINISTRATIVE_PURPOSE_PATTERN.test(clause) ||
    NON_SOCIAL_PURPOSE_PATTERN.test(clause)
  ) return false;
  const shared = hasExplicitSharedOwner(clause) ||
    hasExplicitSelfInvite(clause);
  if (!shared || hasPartnerWithThirdPartyPlan(clause)) return false;
  const coLocated =
    /(?:去|來|到|上|出來|過來|回來|碰面|見面)|(?:帶|接|載|陪)[妳你我]|[妳你](?:陪|跟|和)我|(?:跟|和|陪)我/u
      .test(clause);
  return coLocated &&
    (GENERIC_ACTIVITY_PATTERN.test(clause) ||
      /(?:帶|接|載|陪)[妳你](?:下班|下課)?|拍(?:幾張)?照片|到[\p{Script=Han}]{1,18}(?:家|步道|餐廳|店|館|場|工作室|公園|市集|夜市|海邊|山上)/u
        .test(clause));
}

function isBroadActiveConstraint(clause: string): boolean {
  return /^(?:不用|不必|不要|別).{0,18}(?:得|到|太|那麼|這麼|過於|過頭|過量|特別).+$/u
    .test(clause) &&
    !/(?:邀請|邀約|提議|安排|行程|計畫|這趟|這件事|那句話).{0,8}(?:取消|撤|收回|作廢|拿掉|停掉|不排|不作數)/u
      .test(clause);
}

function isExtendedNounShorthand(clause: string): boolean {
  const source = clause.replace(/[吧嗎啊呀啦]$/u, "");
  const match = CONCRETE_FUTURE_TIME_PATTERN.exec(source);
  if (!match || match.index !== 0) return false;
  const noun = source.slice(match[0].length).replace(
    /^(?:早上|中午|下午|晚上|晚間|傍晚|午後)?[零〇一二三四五六七八九十兩\d]{0,3}(?:點(?:半)?|:\d{2})?(?:的)?/u,
    "",
  );
  if (!noun) return false;
  if (
    /(?:官網|公告|名額|票價|價格|規則|怎麼|為什麼|哪裡|幾點|有開|開放|營業|休館|訂位|預約|課程|介紹|路況|如何|地址|集合)/u
      .test(noun)
  ) {
    return false;
  }
  return /(?:展|會|市集|野餐|體驗|晚餐|午餐|咖啡|茶|健行|夜遊|散步|劇場)$/u
    .test(noun);
}

function hasAnyFutureTime(clause: string): boolean {
  return FUTURE_PATTERN.test(clause) ||
    CONCRETE_FUTURE_TIME_PATTERN.test(clause) ||
    /(?:這個星期[一二三四五六日天]|這禮拜[一二三四五六日天]|下星期[一二三四五六日天]|下下個禮拜[一二三四五六日天]|本週[一二三四五六日天]|週[一二三四五六日天]|星期[一二三四五六日天])(?:早上|中午|下午|晚上|晚間|傍晚|午後)?/u
      .test(clause);
}

function isExtendedScheduleShorthand(raw: string): boolean {
  const source = compact(raw);
  if (
    !(/[?？]/u.test(source) ||
      /(?:吧|嗎|好嗎|可以嗎)[?？。.!！]?$/u.test(source)) ||
    !hasAnyFutureTime(source) ||
    ADMINISTRATIVE_PURPOSE_PATTERN.test(source) ||
    /(?:官網|公告|名額|票價|價格|規則|為什麼|怎麼|哪裡|幾點|有開|開放|營業|休館|訂位|預約|課程|介紹|路況|如何|地址|集合)/u
      .test(source)
  ) {
    return false;
  }
  if (/(?:[我妳你]|一起|跟|和|陪|帶|接|載|找)/u.test(source)) {
    return false;
  }
  return /(?:花藝市集|攝影聯展|黑盒子劇場|森林健行|爵士演出|二手書展|法式甜點|湖畔野餐|山城夜遊|手沖咖啡|英式下午茶|不插電音樂會|陶藝體驗|海岸散步)/u
    .test(source);
}

function isLiveTopicCarryInvite(raw: string): boolean {
  const parts = compact(raw).split(/[，,：:。.!！?？；;]/u).filter(Boolean);
  if (parts.length < 2) return false;
  const tail = parts.at(-1) ?? "";
  if (!hasAnyFutureTime(tail) || hasExplicitNoInvite(tail)) return false;
  const invitationTail = stripLeadingPlanTime(tail);
  if (!/^(?:[妳你])?(?:要|想|會)?一起(?:嗎|吧)?$/u.test(invitationTail)) {
    return false;
  }
  const topic = parts.slice(0, -1).join("，");
  return /(?:展|博物館|市集|茶館|咖啡|餐廳|早午餐|夕陽|電影|紀錄片|演出|音樂祭|劇場|步道|工坊|夜景)/u
    .test(topic) &&
    /(?:不錯|很棒|漂亮|值得|特別|吸引人|熱鬧|有趣|口碑|評價|看來|看起來|聽說|好像)/u
      .test(topic);
}

function isWholeMessageMetaInviteWording(raw: string): boolean {
  const source = compact(raw);
  const text = source.replace(/[，,：:。.!！?？；;「」『』“”‘’"]/gu, "");
  if (!/(?:一起|約|邀|去|來|喝|吃|看|逛|陪|帶|接|載|碰面|見面)/u.test(text)) {
    return false;
  }
  if (freshLiveTailAfterEnvelope(raw)) return false;
  if (
    /(?:寫完|改寫完|校對完|潤飾完|記錄完|處理完|完成|結束)(?:了)?(?:後)?[，,：:。.!！?？；;](?:接著|然後|但|不過|現在)?(?:(?:今天|今晚|明天|後天|週末|下週))?(?:我|我們|咱們|一起|跟[妳你]|和[妳你])/u
      .test(source)
  ) {
    return false;
  }
  if (
    /[，,：:。.!！?？；;](?:接著|然後|但|不過|現在)?(?:寫完|改寫完|校對完|潤飾完|記錄完|處理完)(?:了)?(?:後)?(?:我|我們|咱們|一起|跟[妳你]|和[妳你])/u
      .test(source)
  ) {
    return false;
  }
  if (
    /(?:草稿|文案|範例|筆記|模板)(?:已)?(?:寫|改寫|校對|潤飾|整理|處理)完(?:了)?(?:後)?(?:(?:今天|今晚|明天|後天|週末|下週))?(?:我|我們|咱們|一起|跟[妳你]|和[妳你])/u
      .test(source)
  ) {
    return false;
  }
  if (
    /^(?:以下是.{0,12}(?:原句|訊息)|這是.{0,12}(?:訊息|台詞)|我想傳給.{0,8}的草稿是|.{0,12}示範的句子是|請幫我把.{0,30}改得|幫我校對|請替.{0,30}(?:打分|校對)|替我潤飾|先記錄一句|系統範例輸入為|測試.{0,12}是否能辨識|不要真的約.{0,8}我只想改寫|可以說|建議回)/u
      .test(text) ||
    /(?:這個說法會太油(?:嗎)?|怎麼說比較好)$/u.test(text)
  ) {
    return true;
  }
  if (
    (META_SOURCE_PATTERN.test(text) &&
      (META_OPERATION_PATTERN.test(text) ||
        /(?:內容是|內容為|上的|中的|是否能|這句|這段話|只是|純粹|先別執行)/u
          .test(text))) ||
    (REPORTED_ENVELOPE_PATTERN.test(source) &&
      /(?:一起|約|邀|陪|帶|去|來|喝|吃|看|逛|跑|野餐)/u.test(source))
  ) {
    return true;
  }
  if (
    /^(?:(?:要)?怎麼自然地說|請幫我改寫|請替我校對這段邀約|備忘錄內容是|請替這句打分|把例句換成|筆記上記著|回覆模板可以放|文案範本寫|我在草稿裡寫|筆記內容是|範例可以用|約會文案寫|這句要不要改成|我只是舉例|這是(?:邀約)?(?:文案)?範本|這只是(?:邀約)?文案(?:範本|示例))/u
      .test(text) &&
    !/(?:寫完|完成|結束)(?:了)?[，,：:。.!！?？；;](?:(?:接著|然後|但)?(?:我|我們|咱們|今天|今晚|明天|後天|週末|下週|一起))|[，,：:。.!！?？；;](?:寫完|完成|結束)(?:了)?(?:後)?(?:我|我們|咱們|一起)|[，,：:。.!！?？；;](?:接著|然後|但)?我(?:真的)?(?:想|要)(?:約|邀|跟|和)/u
      .test(source)
  ) {
    return true;
  }
  const qualityQuestion = (/[?？]/u.test(source) || /(?:嗎|呢)$/u.test(text)) &&
    /(?:會不會|會|是不是|是否)?(?:顯得)?(?:太|有點|很)?(?:直接|唐突|突兀|冒昧|奇怪|尷尬|快|急|油膩|刻意|冒進|合適|適合|自然)(?:嗎|呢)?$/u
      .test(text);
  const wordingQuestion =
    /(?:邀約|約會|這句|說法|文案).*(?:怎麼寫|怎麼說|怎麼回)$/u.test(text);
  return qualityQuestion || wordingQuestion;
}

export function looksLikeGameSoftInvite(raw: string): boolean {
  if (isWholeMessageMetaInviteWording(raw)) return false;
  const whole = compact(raw);
  const wholeBare = whole.replace(/[，,：:。.!！?？；;]+$/u, "");
  if (
    /(?:沒有|沒|不是|不會).{0,6}(?:在)?(?:約|邀|安排(?:見面)?|見面)[妳你]?(?:了|啦|喔|哦|啊|呀)?[。.!！?？]?$/u
      .test(whole) ||
    STRUCTURAL_RETRACTION_PATTERN.test(whole) ||
    BROAD_RETRACTION_PATTERN.test(whole) ||
    /(?:剛剛那個提議不作數|那段邀請請直接忽略|先不要把這件事排進去|這趟先停掉|那個計畫我收回了|只是這次先別成行|整個行程拿掉吧|不要安排這趟了|請當作我沒提出|那句邀請作廢|那句話作廢|我只是隨口說的)[。.!！?？]?$/u
      .test(whole)
  ) {
    return false;
  }
  if (
    TERMINAL_RETRACTION_PATTERN.test(wholeBare) ||
    STRUCTURAL_RETRACTION_PATTERN.test(wholeBare) ||
    BROAD_RETRACTION_PATTERN.test(wholeBare) ||
    /當作沒聽到$/u.test(wholeBare)
  ) {
    return false;
  }
  if (
    WITHDRAWAL_PLAN_PATTERN.test(whole) &&
    REPLACEMENT_OPERATOR_PATTERN.test(whole) && hasAnyFutureTime(whole) &&
    !/(?:哪一天|哪天|改天再說|再說細節)/u.test(whole)
  ) {
    return true;
  }
  const lastTransition = cleanClause(
    whole.split(/[，,：:。.!！?？；;]/u).filter(Boolean).at(-1) ?? "",
  );
  if (
    WITHDRAWAL_PLAN_PATTERN.test(whole) &&
    hasAnyFutureTime(lastTransition) &&
    !/(?:哪一天|哪天|改天再說|再說細節)/u.test(lastTransition) &&
    (REPLACEMENT_OPERATOR_PATTERN.test(lastTransition) ||
      TIME_ONLY_REPLACEMENT_PATTERN.test(lastTransition))
  ) {
    return true;
  }
  if (
    /取消的約.{0,16}再約/u.test(whole) && hasAnyFutureTime(whole)
  ) {
    return true;
  }
  if (
    /暫緩.*等.+(?:我們|咱們).*(?:再約|碰面)/u.test(whole) &&
    hasAnyFutureTime(whole)
  ) {
    return true;
  }
  if (
    isDoubleNegatedPlanLead(whole) && hasAnyFutureTime(whole) &&
    /(?:只是|(?:是|而是)打算|而是|時間(?:改成|移到)|改成|挪到|排到|放到|換成|我想約)/u
      .test(whole)
  ) {
    return true;
  }
  if (
    hasAnyFutureTime(whole) &&
    /(?:官網.{0,6}公告|還有名額)/u.test(whole)
  ) {
    return false;
  }
  if (isLiveTopicCarryInvite(raw)) return true;
  if (isExtendedScheduleShorthand(raw)) return true;
  if (
    /[；;](?:至於)?(?:現在)?(?:我們|咱們)[，,]?(?:這|下|本|明|後|週|星期|禮拜|[一二三四五六七八九十]{1,3}月).{0,24}(?:一起|改約).*(?:去|來|到|喝|吃|看|逛|聽|走|散步|碰|見|聚)/u
      .test(whole)
  ) {
    return true;
  }
  if (
    /[；;](?:現在)?(?:我們|咱們)(?:改約|改到).{0,24}(?:去|來|到|喝|吃|看|逛|聽|走|散步|碰|見|聚)/u
      .test(whole)
  ) {
    return true;
  }
  if (
    /[；;](?:現在)?(?:我們|咱們)(?:改約|改到).{0,24}[。.!！?？]?$/u
      .test(whole) && hasAnyFutureTime(whole)
  ) {
    return true;
  }
  if (
    /(?:週末|明天|後天|今晚|明晚|下週)(?:早上|中午|下午|晚上)?出來走走(?:吧|嗎)?[。.!！?？]?$/u
      .test(whole)
  ) {
    return true;
  }
  if (
    hasAnyFutureTime(whole) && hasExplicitPhysicalDyadPlan(whole) &&
    !isDefinitePastSelfNarrative(whole) &&
    !REPORTED_ENVELOPE_PATTERN.test(whole) &&
    !TERMINAL_RETRACTION_PATTERN.test(wholeBare) &&
    !STRUCTURAL_RETRACTION_PATTERN.test(wholeBare) &&
    !WITHDRAWAL_PLAN_PATTERN.test(whole) &&
    !CANCELLATION_STATEMENT_PATTERN.test(whole)
  ) {
    return true;
  }

  let active = false;
  let leadWalk = false;
  let reportPending = false;
  let reportPendingBudget = 4;
  let reportQuoteDepth: number | null = null;
  let pendingPlan: PendingPlan = null;

  for (const unit of scanInviteUnits(raw)) {
    let unitText = unit.text;
    if (reportQuoteDepth !== null) {
      if (unit.closedQuote && unit.endQuoteDepth < reportQuoteDepth) {
        reportQuoteDepth = null;
        const closeIndex = Math.max(
          unitText.lastIndexOf("」"),
          unitText.lastIndexOf("』"),
          unitText.lastIndexOf("”"),
          unitText.lastIndexOf("’"),
        );
        unitText = closeIndex >= 0 ? unitText.slice(closeIndex + 1) : "";
        if (!cleanClause(unitText)) continue;
      } else {
        continue;
      }
    }

    if (unit.openedQuote && unit.closedQuote) {
      const closeIndex = Math.max(
        unitText.lastIndexOf("」"),
        unitText.lastIndexOf("』"),
        unitText.lastIndexOf("”"),
        unitText.lastIndexOf("’"),
      );
      if (closeIndex >= 0 && closeIndex < unitText.length - 1) {
        const reportHead = unitText.slice(0, closeIndex + 1);
        if (reportedSpeechFor(reportHead).reported) {
          unitText = unitText.slice(closeIndex + 1);
        }
      }
    }

    if (unit.openedQuote && unit.endQuoteDepth > unit.startQuoteDepth) {
      const openIndexes = [
        unitText.indexOf("「"),
        unitText.indexOf("『"),
        unitText.indexOf("“"),
        unitText.indexOf("‘"),
      ].filter((index) => index >= 0);
      const openIndex = openIndexes.length > 0 ? Math.min(...openIndexes) : -1;
      reportPending = false;
      reportQuoteDepth = unit.endQuoteDepth;
      unitText = openIndex >= 0 ? unitText.slice(0, openIndex) : "";
      if (!cleanClause(unitText)) continue;
    }

    unitText = unitText.replace(
      /「[^」]*」|『[^』]*』|“[^”]*”|‘[^’]*’/gu,
      "",
    );

    if (reportPending) {
      if (unit.openedQuote) {
        reportPending = false;
        if (unit.endQuoteDepth > unit.startQuoteDepth) {
          reportQuoteDepth = unit.endQuoteDepth;
        }
        continue;
      }
      const pendingClause = cleanClause(unitText);
      if (isFiller(unitText)) {
        reportPendingBudget -= 1;
        if (reportPendingBudget <= 0) reportPending = false;
        continue;
      }
      if (
        !explicitlyReassertsSelf(pendingClause) &&
        !hasExplicitSelfInvite(pendingClause)
      ) {
        reportPending = false;
        continue;
      }
      reportPending = false;
    }

    for (const rawPart of splitTransitions(unitText)) {
      let clause = cleanClause(rawPart);
      if (!clause || isFiller(clause)) continue;
      if (hasExplicitNoInvite(clause)) {
        active = false;
        leadWalk = false;
        pendingPlan = null;
        continue;
      }
      clause = stripLeadingCompletedCondition(clause, unit.question);
      if (!clause || isFiller(clause)) continue;

      if (pendingPlan !== null) {
        if (pendingPlan === "double_negated" && isPendingBridge(clause)) {
          continue;
        }
        if (pendingPlan === "past" && /^(?:我|我們|咱們)$/u.test(clause)) {
          continue;
        }
        if (
          TIME_ONLY_REPLACEMENT_PATTERN.test(clause) ||
          isPlanContinuation(clause, pendingPlan)
        ) {
          active = true;
          leadWalk = false;
          pendingPlan = null;
          continue;
        }
        pendingPlan = null;
      }

      if (isDoubleNegatedPlanLead(clause)) {
        active = false;
        leadWalk = false;
        pendingPlan = "double_negated";
        continue;
      }

      const definitePastNarrative = isDefinitePastSelfNarrative(clause);
      const report = reportedSpeechFor(clause);
      if (report.reported) {
        if (report.freshTail) {
          clause = report.freshTail;
        } else {
          if (definitePastNarrative) {
            active = false;
            leadWalk = false;
            pendingPlan = /(?:約|邀|一起|跟[妳你]|和[妳你])/u.test(clause)
              ? "past"
              : null;
          }
          reportPending = report.opensScope;
          reportPendingBudget = 4;
          if (unit.openedQuote && unit.endQuoteDepth > unit.startQuoteDepth) {
            reportQuoteDepth = unit.endQuoteDepth;
          }
          if (report.opensScope) break;
          continue;
        }
      }

      if (definitePastNarrative) {
        active = false;
        leadWalk = false;
        pendingPlan = /(?:約|邀|一起|跟[妳你]|和[妳你])/u.test(clause)
          ? "past"
          : null;
        continue;
      }

      if (
        CANCELLATION_STATEMENT_PATTERN.test(clause) ||
        WITHDRAWAL_PLAN_PATTERN.test(clause)
      ) {
        if (active && /先延後再說細節/u.test(clause)) continue;
        active = false;
        leadWalk = false;
        pendingPlan =
          /(?:一起|約|邀|去|來|喝|吃|看|逛|玩|碰|見|聚|行程|安排|計畫|場|趟|局|體驗|下午茶|音樂會|野餐|健行|劇場)/u
              .test(clause)
            ? "retracted"
            : null;
        continue;
      }

      const retraction = TERMINAL_RETRACTION_PATTERN.exec(clause) ??
        STRUCTURAL_RETRACTION_PATTERN.exec(clause) ??
        BROAD_RETRACTION_PATTERN.exec(clause);
      if (retraction?.index !== undefined) {
        const prefix = clause.slice(0, retraction.index);
        const priorProposal = active ||
          (prefix.length > 0 && looksLikeGameSoftInvite(prefix)) ||
          (!/(?:咖啡豆|茶葉|票券|文件|商品|訂單)/u.test(clause) &&
            /(?:今天|今晚|明早|明晚|明天|後天|這週|本週|下週|週末|月底|週[一二三四五六日天]|星期[一二三四五六日天]|禮拜[一二三四五六日天])/u
              .test(clause) &&
            (OUTING_ACTION_PATTERN.test(clause) ||
              OUTING_NOUN_PATTERN.test(clause) ||
              GENERIC_ACTIVITY_PATTERN.test(clause) ||
              /(?:飯局|咖啡局|那頓飯|碰面|見面|散步|看展|展|爬山|小酌|午餐|晚餐|咖啡|約會)/u
                .test(clause))) ||
          (/^不去.{1,12}了/u.test(clause) &&
            OUTING_NOUN_PATTERN.test(clause));
        active = false;
        leadWalk = false;
        pendingPlan = priorProposal ? "retracted" : null;
        continue;
      }

      if (
        /(?:各自|分開|各走各的|自己去|(?:我)?自己(?:在家)?(?:去)?(?:散步|逛|喝|吃|看|玩|走|跑|騎|唱|碰|見|聚)|(?:我)?一個人(?:在家)?(?:去)?(?:散步|逛|喝|吃|看|玩|走|跑|騎|唱|碰|見|聚))/u
          .test(clause)
      ) {
        active = false;
        leadWalk = false;
        continue;
      }

      if (
        active &&
        (ACTIVE_INVITE_CONSTRAINT_PATTERN.test(clause) ||
          isBroadActiveConstraint(clause))
      ) {
        continue;
      }

      const isNegated =
        /(?:不是(?:想|要|去|來|約|邀|喝|吃|看|逛|玩|跟|和|陪|帶)|並非|沒有(?:想|要|咖啡局|飯局|約|局)|沒(?:想要|說要|打算|要)|不打算|不會|不用|不能|沒辦法|無法|不方便|(?<!想)不想(?:去|來|約|邀|喝|吃|看|逛|玩|跟|和|陪|帶|找|碰|見|聚|一起)|(?<!要)不要(?:了|去|來|約|邀|喝|吃|看|逛|玩|跟|和|陪|帶|找|碰|見|聚|一起)|(?<!來)不來(?:了)?|不一起|不(?:去|約|邀|喝|吃|看|逛|玩|找|碰|見|聚)|不(?:(?:跟|和)[妳你](?:一起)?|(?:陪|帶|接|載)[妳你我])(?:去|來|喝|吃|看|逛|玩|找|碰|見|聚)|別(?:一起|去|來|喝|吃|看|逛|玩|約(?!太晚|太早|太趕)|邀|找|碰|見)|別(?:(?:跟|和)[妳你](?:一起)?|(?:陪|帶|接|載)[妳你我])(?:去|來|喝|吃|看|逛|玩|找|碰|見|聚)|^(?:不要|不想)$)/u
          .test(clause);
      if (isNegated) {
        active = false;
        leadWalk = false;
        continue;
      }

      const hasDyad = DYAD_PATTERN.test(clause);
      const hasFuture = hasAnyFutureTime(clause);
      const hasStrongFuture = STRONG_FUTURE_PATTERN.test(clause);
      const hasCalendarFuture = CALENDAR_FUTURE_PATTERN.test(clause) ||
        CONCRETE_FUTURE_TIME_PATTERN.test(clause);
      const hasOutingAction = OUTING_ACTION_PATTERN.test(clause);
      const hasOutingNoun = OUTING_NOUN_PATTERN.test(clause);
      const hasGenericActivity = GENERIC_ACTIVITY_PATTERN.test(clause);
      const hasModal = /(?:要不要|想不想|來不來)/u.test(clause);
      const hasDirectInvite =
        /(?<![大預合解])(?:約|邀)(?:一下)?[妳你]/u.test(clause) ||
        /(?:有空|有機會|改天|下次|哪天|找(?:個)?時間).{0,10}(?<![大預合解])(?:約|邀)(?:個|一下|一杯|杯|頓)/u
          .test(clause);
      const hasEscort =
        /(?:^|我(?:想|要|可以)?)(?:去)?(?:帶|接|載|陪)[妳你](?:(?:去|到|來|回).{1,18}|.{0,8}(?:喝|吃|走|散步|逛|看|玩|爬|跑|打|唱|碰|見|聚|野餐|騎|聽|游泳|健身|露營))/u
          .test(clause);
      const hasTreat = /(?:我)?請[妳你](?:喝|吃|看(?:電影|展))/u.test(clause);
      const hasRoleInvite = /有機會.{0,10}讓[妳你]當(?:一次)?/u.test(clause);
      const explicitPhysicalDyad = hasExplicitPhysicalDyadPlan(clause);
      const partnerQuestionCore = clause
        .replace(CONCRETE_FUTURE_TIME_PATTERN, "")
        .replace(CONTEXT_TOKEN_PATTERN, "")
        .replace(
          /(?:早上|上午|中午|下午|晚上|晚間|傍晚|午後|[零〇一二三四五六七八九十兩\d]{1,3}點(?:半)?)/gu,
          "",
        );
      const partnerOnlySchedule = unit.question && !hasDyad &&
        !hasDirectInvite && !hasEscort &&
        /^[妳你](?:要|想|會|打算|準備)(?:去|來|喝|吃|走|散步|逛|看|玩|爬|跑|打|唱|碰|見|聚|野餐|騎|聽|游泳|健身|露營)/u
          .test(partnerQuestionCore);

      if (
        partnerOnlySchedule ||
        (isContentOnly(clause) && !explicitPhysicalDyad) ||
        isNavigationOnlyQuestion(
          clause,
          unit.question,
          hasDyad,
          hasDirectInvite,
          hasEscort,
        )
      ) {
        continue;
      }

      const isNonOutingPurpose =
        /(?:(?:跟|和)[妳你](?:聊|談|討論|分享|講|說|問|研究).{0,20}|看(?:醫生|牙醫|牙|文章|訊息|文件|履歷|照片|影片|菜單|評價|心得|海報|預告|攻略|評論)|看(?:看)?(?:[妳你我]的)?(?:想法|看法|意見|點子|提案)|玩(?:這|那|同一)?(?:個)?梗|玩(?:猜謎|問答|文字|手機)(?:小)?遊戲|去(?:醫院|看牙|睡(?:覺)?|加油|領藥|拿藥|取藥|領包裹|取包裹|拿包裹|寄件|領貨|取貨|(?:辦|換|補|申請)(?:護照|證件|簽證|駕照|文件|手續)|剪頭髮|搬家|看房|驗車|買手機|投票|打疫苗|做體檢|修(?:手機|電腦|車|機車))|洗澡|睡覺|買菜|復健|吃藥|領藥|拿藥|取藥|領包裹|取包裹|拿包裹|寄件|領貨|取貨|(?:辦|換|補|申請)(?:護照|證件|簽證|駕照|文件|手續)|剪頭髮|搬家|看房|驗車|買手機|投票|打疫苗|做體檢|修(?:手機|電腦|車|機車)|加油|打電話|上班|工作(?!室)|找工作|辦事|上課|開會|報到|繳費|面試|打報告|當班|加班|找資料|對(?:身體|健康).{0,6}(?:不好|有害|有影響)|(?:公司|家庭|部門|團隊|班級|董事|股東|家長|校務).{0,6}(?:聚餐|聚會|會議|例會|晨會|週會|月會|年會)|(?:同學會|記者會|說明會|研討會|發表會|法說會))/u
          .test(clause);
      const isMetaOrInfo =
        /(?:算(?:不算)?|算是|是不是|屬於|叫做?).{0,6}(?:邀約|約會)|算(?:不算|是)?在(?<!預)約[妳你].{0,4}嗎|(?:邀約|約會)(?:的意思|的定義|是什麼)|(?:這句|這個說法|這段).{0,12}(?:自然|意思|怎麼回|怎麼說)|(?:寫|記|放).{0,16}(?:筆記|範例|草稿)|(?:需要|要|得|先)?(?:預約|訂位|訂票|掛號)/u
          .test(clause) ||
        /^(?:如果|假如|若是?)說?.*(?:一起|約|邀|喝|吃|看|逛|碰面|見面).*(?:會不會|會)?(?:太)?(?:直接|唐突|突兀|冒昧|奇怪|尷尬)(?:嗎)?$/u
          .test(clause) ||
        /(?:(?:路況|交通|車程|停車(?:位)?|(?:山上|海邊|店家|會場|那裡|那邊|公園|展覽)的路|路(?:上)?).{0,12}(?:塞(?:車)?|會不會塞(?:車)?|順不順|好走|難走|多久|多遠|如何|方不方便|方便|好不好停|好停|難停|有沒有停車位)|(?:去|到).{0,12}(?:怎麼走|走哪條路|哪條路|好不好停車|好停車|難停車|有(?:沒有)?停車位))(?:嗎|呢|吧)?$/u
          .test(clause) ||
        /(?:要不要|想不想).{0,10}(?:跟我說|和我說|告訴我|推薦|分享|講|說說|幫(?:我|你|妳)|讓我看|看我|傳|給我看)/u
          .test(clause) ||
        /(?:我想)?請[妳你].{0,6}(?:幫|替|告訴|推薦|分享|找|傳|說)/u
          .test(clause) ||
        /^(?:例如|譬如|像是)|(?:可以說|建議回|這句|說法).*[「『“"]|(?:電影|遊戲)(?:預告|介紹|攻略|評論)|(?:票價|價格|多少錢|幾卡|卡路里|菜單|規則|低消|還有票|休息|休館|開放|有開|好看|好喝|值得去|很擠|擁擠|很貴|人很多|很多人|人(?:會|也)?很多|五分熟)|(?:想吃|想喝|想看)(?:什麼|哪個|哪部|哪種|哪款)|(?:加糖|怎麼選|怎麼點|哪種|哪杯|哪款)/u
          .test(clause);
      if (
        ADMINISTRATIVE_PURPOSE_PATTERN.test(clause) || isNonOutingPurpose ||
        isMetaOrInfo
      ) continue;

      const futureDyadProposal = hasFuture && hasDyad;
      const isPastNarrative = PAST_PATTERN.test(clause) && !hasFuture &&
        !/(?:改成|改為|換成)/u.test(clause);
      const isHabitOrPreference =
        (/(?:平常|通常|平時|常(?:常|去)?|每天|每週|每個(?:週|月)|習慣|都喜歡|都會|幾次)/u
          .test(clause) ||
          /^(?:[妳你]|我們|咱們)?(?:喜歡|愛).*(?:嗎|呢)$/u.test(clause)) &&
        !futureDyadProposal;
      const isDescriptive =
        (/(?:口味|品味|習慣|時間|經驗|回憶|這件事|感覺).{0,12}(?:差(?:很多)?|像|一樣|不同|不一樣|很好|很像|還記得|通常|很多)(?:吧|嗎|呢)?$/u
          .test(clause) ||
          /(?:人多|營業|開門|關門|有精神|看起來|聽起來|比較|很舒服|很放鬆|很累|很無聊|很有趣|很浪漫)/u
            .test(clause)) && !futureDyadProposal;
      if (isPastNarrative || isHabitOrPreference || isDescriptive) continue;

      if (hasPartnerWithThirdPartyPlan(clause)) continue;
      if (hasExplicitSelfInvite(clause)) {
        active = true;
        leadWalk = false;
        continue;
      }
      if (!hasDyad && hasThirdPartyDestination(clause)) continue;
      if (!hasExplicitSharedOwner(clause) && hasThirdPartyPlan(clause)) {
        continue;
      }

      const partnerModal =
        /^(?:(?:今天|今晚|明早|明晚|明天|後天|這週末|這週|下週|週末|(?:這|下|本)?週[一二三四五六日天]|(?:這|下|本)?星期[一二三四五六日天]|(?:這|下|本)?禮拜[一二三四五六日天]|下次|改天|有空|晚點|待會|等等|下班後))?[妳你](?:(?:今天|今晚|明早|明晚|明天|後天|這週末|這週|下週|週末|(?:這|下|本)?週[一二三四五六日天]|(?:這|下|本)?星期[一二三四五六日天]|(?:這|下|本)?禮拜[一二三四五六日天]|下次|改天|有空|晚點|待會|等等|下班後))?(?:要不要|想不想|會不會|會|打算|準備|喜歡|愛|想|要)/u
          .test(clause);
      const partnerBareQuestion = unit.question &&
        /^(?:(?:今天|今晚|明早|明晚|明天|後天|這週末|這週|下週|週末|(?:這|下|本)?週[一二三四五六日天]|(?:這|下|本)?星期[一二三四五六日天]|(?:這|下|本)?禮拜[一二三四五六日天]|晚點|待會|等等|下班後))?[妳你](?:(?:今天|今晚|明早|明晚|明天|後天|這週末|這週|下週|週末|(?:這|下|本)?週[一二三四五六日天]|(?:這|下|本)?星期[一二三四五六日天]|(?:這|下|本)?禮拜[一二三四五六日天]|晚點|待會|等等|下班後))?(?:去|來|喝|吃|看|逛|玩|爬|跑|打|唱)/u
          .test(clause);
      if ((partnerModal || partnerBareQuestion) && !hasDyad && !hasEscort) {
        continue;
      }

      const isScheduleQuestion = !hasDyad && unit.question &&
        (/(?:哪裡|哪家|哪間|幾點|何時|什麼時候|跟誰|做什麼|去哪(?:裡)?|要去哪|會不會|會去|打算|準備|想吃什麼|想喝什麼|想看哪)/u
          .test(clause) ||
          /[妳你].{0,12}(?:會|打算|準備).*(?:看|去|來|喝|吃|逛|玩)/u
            .test(clause) ||
          /(?:喜歡|愛|覺得|人多|適合|比較|營業|開門|關門|有精神|怎麼樣)/u
            .test(clause));
      if (isScheduleQuestion) continue;

      const activityIndex = clause.search(
        /(?:去|來|過來|喝|吃|走|散步|逛|看|玩|爬|跑|打|唱|碰|見|踩|晃|聚|換|野餐|騎|聽|游泳|健身|露營|續攤|陶藝|旅行|拍照|做菜|烤肉|泡湯|兜風|遛狗|咖啡|早餐|午餐|晚餐|電影|展覽|市集|夜市|書店|公園|酒吧)/u,
      );
      const selfIndex = clause.search(/(?:我(?!們|家|的)|本人|自己)/u);
      if (
        !hasDirectInvite && !hasDyad && !hasEscort && !hasTreat &&
        selfIndex >= 0 && (activityIndex < 0 || selfIndex < activityIndex)
      ) {
        continue;
      }

      const nounShorthand = isNounShorthand(clause);
      const bareFutureMeetup = hasFuture &&
        (/(?:再約(?:妳|你|個|一下|一杯|杯|一頓|頓)?|再聚(?:聚|一下)?)(?:吧|嗎|啊|呀|啦)?$/u
          .test(clause) ||
          (hasStrongFuture &&
            /^(?:下次|改天|有空(?:的話)?|有機會|哪天)(?:再)?(?:約(?:妳|你|個|一下|一杯|杯|一頓|頓)?|聚(?:聚|一下|餐)?|續攤|見(?:面)?|碰(?:面|一下))(?:吧|嗎|啊|呀|啦)?$/u
              .test(clause)));
      const bareCalendarMeet = hasCalendarFuture &&
        /^(?:今天|今晚|明早|明晚|明天|後天|這週末|這週|下週|週末|(?:這|下|本)?週[一二三四五六日天]|(?:這|下|本)?星期[一二三四五六日天]|(?:這|下|本)?禮拜[一二三四五六日天]|晚點|待會|等等|下班後)(?:見|碰面|碰一下)(?:吧|嗎|啊|呀|啦)?$/u
          .test(clause);
      const isEllipticalSocialAction =
        /(?:(?:一起|(?:跟|和)[妳你]|(?:跟|和|陪|帶)我|找[妳你我]).{0,8}(?:去)?(?:吃|喝|看|玩)|(?:我們|咱們|一起)(?:一起)?去)(?:吧|嗎|啊|呀|啦)?$/u
          .test(clause);
      const dyadProposal = hasDyad &&
        (hasOutingAction || hasOutingNoun || isEllipticalSocialAction ||
          (hasGenericActivity && hasExplicitSharedOwner(clause)));
      const genericCalendarDyadProposal = hasCalendarFuture && hasDyad &&
        hasGenericActivity && hasExplicitSharedOwner(clause);
      const ellipticalDyadSchedule = hasCalendarFuture && hasDyad &&
        /[妳你](?:要|想|會)?一起(?:嗎|吧)?$/u.test(clause);
      const subjectlessModal = hasModal &&
        (hasOutingAction || hasOutingNoun);
      const proposalOperator =
        /(?:不然|乾脆|要不|不如|要嘛|那就|改去|改喝|改吃|改看|改約|換去|換喝|換吃|換看|換約)/u
          .test(clause) &&
        (hasOutingAction || hasOutingNoun);
      const futureProposal = (hasStrongFuture &&
        (hasOutingAction || bareFutureMeetup)) ||
        (hasCalendarFuture &&
          (hasDyad || unit.question || /(?:吧|啊|呀|啦)$/u.test(clause)) &&
          hasOutingAction);
      const calendarActionProposal = hasCalendarFuture &&
        hasOutingAction && isAnchoredCalendarAction(clause);
      const imperativeProposal =
        (hasOutingAction || (leadWalk && hasGenericActivity)) &&
        (/^(?:走|去|來|過來|喝|吃|碰|見).{0,28}(?:吧|啊|呀|啦)?$/u
          .test(clause) ||
          /^(?:喝|吃|看|逛|玩).{0,20}去$/u.test(clause) || leadWalk);

      if (
        hasDirectInvite || hasEscort || hasTreat || hasRoleInvite ||
        explicitPhysicalDyad ||
        nounShorthand || bareFutureMeetup || bareCalendarMeet || dyadProposal ||
        genericCalendarDyadProposal || ellipticalDyadSchedule ||
        subjectlessModal || proposalOperator ||
        futureProposal ||
        calendarActionProposal || imperativeProposal
      ) {
        active = true;
      }
      leadWalk = /^走[吧啊呀啦]?$/u.test(clause);
    }
  }

  return active;
}
