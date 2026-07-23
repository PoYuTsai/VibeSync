import { assertEquals } from "jsr:@std/assert@1";
import { practiceInviteLevelFor } from "./practice_invite.ts";

Deno.test("practice invite classifier separates self-disclosure from plans involving her", () => {
  for (
    const line of [
      "明天我也想喝咖啡補血",
      "這週六我想去爬山",
      "週末我去看電影放空，妳呢？",
      "週末看電影放空，妳呢？",
      "明天我去打球，妳呢？",
      "明天我在咖啡廳跟朋友見面。",
      "明天我要去咖啡廳見面。",
      "明晚碰一下客戶。",
      "明晚碰一下同事。",
      "明晚要碰一下客戶談案子。",
      "週六朋友來我家。",
      "妳到家跟我說一聲。",
      "不是要約妳，我明天也會去那間店。",
      "等妳時差歸位，我拿一杯咖啡跟妳交換故事。",
      "調時差辛苦了，妳這趟回來最想先用什麼方式回血？",
      "明晚我早點睡。",
      "週六我空半小時再去跑步。",
      "明天我準備出門買咖啡。",
      "週六我預留半小時運動。",
      "週末散步醒腦。",
      "明晚吃飯後早點睡。",
      "明天喝杯咖啡補血，最近太累了。",
      "週末跟朋友喝咖啡。",
      "明晚陪家人吃飯。",
      "週末咖啡先免了。",
      "明天咖啡先不要。",
      "明天值完班喝咖啡續命。",
      "週末逛夜市放空。",
      "明晚吃宵夜後早點睡。",
      "週末回家見一下家人。",
      "明晚要碰一下客戶談案子。",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "none", line);
  }
  assertEquals(practiceInviteLevelFor("週六一起去爬山吧"), "direct");
  assertEquals(practiceInviteLevelFor("明晚我們去打羽球吧"), "direct");
  assertEquals(practiceInviteLevelFor("下次有空去打羽球吧"), "soft");
});

Deno.test("practice invite classifier recognises generic scheduling language", () => {
  for (
    const line of [
      "週六我帶妳去那間店。",
      "明晚我帶妳出去玩。",
      "週末直接出來，我帶妳去一個地方。",
      "我們週六約在那間店。",
      "週六去陶藝教室玩吧？",
      "明天七點我去接妳。",
      "七點我會去接妳。",
      "明晚我想請妳吃飯。",
      "明天七點樓下見。",
      "明天七點我在妳家樓下等妳。",
      "明天七點在咖啡廳見面。",
      "週六咖啡店見。",
      "明晚七點咖啡店碰面。",
      "週六我訂那間店，妳直接過來。",
      "明晚妳直接過來。",
      "週六來找我。",
      "明晚過來找我。",
      "週末來我家。",
      "明晚到我這邊。",
      "明天七點樓下見喔。",
      "明天七點樓下見啦",
      "明天七點樓下等妳。",
      "明天七點我等妳。",
      "明天七點妳下樓，我到了叫妳。",
      "明天七點碰個面吧。",
      "明晚過來。",
      "妳明晚直接過來。",
      "明晚七點老地方。",
      "七點樓下。",
      "咖啡這題可以，禮拜六留半小時給我。",
      "咖啡收到，明晚七點妳出門就好。",
      "咖啡收到，明晚碰一下。",
      "咖啡收到，週末喝一杯。",
      "咖啡收到，妳週六留給我。",
      "賴床收到，明晚七點準備出門。",
      "週六別排事。",
      "週六時間給我。",
      "這週末歸我。",
      "明晚七點聽我的。",
      "週六空半小時。",
      "明晚七點把時間空下來。",
      "週六把行程清掉。",
      "明晚七點記得出門。",
      "週末別約別人。",
      "週六排給我。",
      "明晚七點不要遲到。",
      "週六留空。",
      "週六空著。",
      "明晚先別排。",
      "週六先別約人。",
      "週六記得留時間。",
      "明晚妳等我。",
      "明晚待命。",
      "週六先空下來。",
      "明晚行程清空。",
      "明晚先保留。",
      "明晚不要有約。",
      "週六把晚上空下來。",
      "週六暫時別答應別人。",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "direct", line);
  }
  assertEquals(
    practiceInviteLevelFor("下次有空再去那間咖啡店走走。"),
    "soft",
  );
});

Deno.test("practice invite classifier ignores mid-word verbs and rhetorical dare questions", () => {
  // 第 6 輪 eval FP 樣句（docs/reviews/2026-07-23-fact-gate-round6-judgment.md #1/#2/#4/#5）：
  // 單字動詞被構詞環境（好看/換來/被打）或反問語氣（還敢跟嗎）切中，全句零邀約語意。
  for (
    const line of [
      "追劇配鹹酥雞聽起來根本是治癒套餐吧，最近在追什麼劇，好看到讓妳暫時忘記開會的當機感嗎？",
      "懷疑人生也要撐到看風景，這波你算是精神值爆表了哈哈，下次爬山還敢跟嗎？",
      "哈哈「懶得戒了」這態度我喜歡，反正咖啡因換來的清醒感也算划算吧？",
      "很嚴格喔？那我可要挑最不糊的那張交作業，被打回票要重拍嗎？",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "none", line);
  }
  // 真邀約回歸：構詞守門不得弱化既有偵測（判定表 #7＋一起來構詞例外）。
  assertEquals(practiceInviteLevelFor("麻辣鍋那家我可以帶妳去試試"), "direct");
  assertEquals(practiceInviteLevelFor("改天一起去"), "soft");
  assertEquals(practiceInviteLevelFor("一起來吧"), "direct");
});

Deno.test("practice invite classifier removes cancelled or negated plans", () => {
  for (
    const line of [
      "放心，明天七點我不會去接妳。",
      "明天七點不用我去接妳。",
      "週末我們不要去看電影了。",
      "明天不要一起喝咖啡。",
      "不是要約妳，我明天也會去那間店。",
      "明天七點我不去接妳。",
      "明天七點我不接妳了。",
      "明天七點我沒有要去接妳。",
      "週末別一起看電影了。",
      "週末不要來找我。",
      "週末不用來我家。",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "none", line);
  }
  assertEquals(
    practiceInviteLevelFor("明天不要喝咖啡，週六一起去爬山吧。"),
    "direct",
  );
});

Deno.test("practice invite classifier ignores degree adverbs, intent questions and embedded complements", () => {
  // 第 8 輪 eval FP 樣句（docs/reviews/2026-07-23-fact-gate-round8-judgment.md）：
  // 「一點/一時」程度副詞與慣用語不是報時；「還會(想)再V嗎」問她自己的重複
  // 意願不是提案；「評估要不要」是疑問補語；「打算」的「打」是複合詞首字；
  // 「在等妳的◯◯」是擬人等待不是到場等人。
  for (
    const line of [
      "「勉強及格」我收下，但妳都親口承認猜中了，這分數是不是該再加一點？",
      "懷疑人生這段太真實了哈哈，但聽起來風景有補償妳的痛苦。下次還會想再爬嗎？",
      "哈哈懷疑人生的樣子一定很狼狽，不過看起來還是值得啦，下次還會再去嗎？",
      "懷疑人生也要撐到山頂看風景，這波值得！下次爬山找教練陪你評估要不要出發啦哈哈",
      "哈哈「懶得戒」根本是官方認證咖啡因愛好者宣言，妳這是打算跟咖啡過一輩子了吧？",
      "那就繼續考驗我吧，我歌單還有好幾首在等妳的評分。妳最近在聽什麼？",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "none", line);
  }
  // 真報時/真邀約回歸：假時鐘收窄不得弱化既有偵測。
  assertEquals(practiceInviteLevelFor("明天下午一點老地方見"), "direct");
  assertEquals(practiceInviteLevelFor("一點半在咖啡店等妳"), "direct");
  assertEquals(practiceInviteLevelFor("週六兩點一起去爬山吧"), "direct");
  assertEquals(
    practiceInviteLevelFor("要不要哪天我們一起去挖寶？"),
    "soft",
  );
  // 含「一點」的軟邀約仍是 soft（round8 gh4：一點≠時鐘，不得推高成 direct）。
  assertEquals(
    practiceInviteLevelFor("妳說勉強可以跟你多聊一點，那改天一起聽新歌？"),
    "soft",
  );
});

Deno.test("practice invite classifier ignores continuation aspect and completed-state confirmations", () => {
  // 第 9 輪 eval FP 樣句（docs/reviews/2026-07-23-fact-gate-round9-judgment.md）：
  // 「V下去」持續貌、「…了吧/了嗎」完成態確認、「還會想去嗎」意圖問句（無「再」）。
  for (
    const line of [
      "哈哈「懶得戒」這態度我喜歡，反正咖啡因換頭痛也不划算，不如就順順地喝下去吧",
      "妳停在第三章，會想繼續看下去嗎？",
      "下山懷疑人生我懂，但看到風景那瞬間應該還是覺得爬對了吧？",
      "哈哈懷疑人生的時候應該有點狼狽，不過那種累到值得的感覺我懂。下次還會想去嗎？",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "none", line);
  }
  assertEquals(practiceInviteLevelFor("改天一起去"), "soft");
  assertEquals(practiceInviteLevelFor("週六一起去爬山吧"), "direct");
});

Deno.test("practice invite classifier ignores dare/passive intent questions, third-party inviters and continuation advice", () => {
  // 第 10 輪 eval FP 樣句（docs/reviews/2026-07-23-fact-gate-round10-judgment.md）：
  // 「還敢去嗎」敢在動詞前、「還會被拖去嗎」被動（拖她的是朋友）、
  // 「朋友…約妳嗎」第三方主詞、「繼續喝吧」勸延續、「要不要先簽切結書」玩笑建議。
  for (
    const line of [
      "哈哈懷疑人生的樣子一定很狼狽，不過這樣的故事才值得講啊。下次還敢去嗎？",
      "風景值回票價就好，鐵腿那種懷疑人生感過幾天就忘了，下次還會被拖去嗎？",
      "下山懷疑人生我懂，但妳這樣講代表風景有打動妳。朋友下次還會約妳嗎？",
      "哈哈「懶得戒」這句我信，反正戒斷頭痛比人生選擇還可怕，繼續喝吧",
      "哈哈懷疑人生也太真實，看來這山頭是拿風景騙妳去的，下次爬山前要不要先簽切結書",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "none", line);
  }
  // 含「我」的被動子句不剝：拖她的是我＝真邀約試探；第三方剝除限子句開頭。
  assertEquals(practiceInviteLevelFor("妳明天要不要出來喝一杯"), "direct");
  assertEquals(practiceInviteLevelFor("我帶朋友去找妳"), "direct");
});
