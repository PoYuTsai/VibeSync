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

Deno.test("practice invite classifier ignores walking-state, complement 下來/起來 and cross-clause 跟妳 windows", () => {
  // 第 11 輪 eval FP 樣句（docs/reviews/2026-07-23-fact-gate-round11-judgment.md）：
  // 「走路還會抖嗎」走路是行走本身、「看下來感覺如何」讀後感補語、
  // 「先跟妳說一聲，妳要慢慢看」跟妳窗跨逗號湊對。
  for (
    const line of [
      "風景值得但腿真的很誠實哈哈，妳現在走路還會抖嗎？",
      "哈哈也沒有很效率啦剛好今天在家沒事，妳停在第三章的話，目前那段妳看下來感覺如何？",
      "第三章其實是關鍵轉折，我怕爆雷先跟妳說一聲，妳要慢慢看，我等妳追上再聊後面～",
      "這件妳穿看起來如何？",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "none", line);
  }
  // 真邀約不得鬆：約起來／出去走走／妳下來（ADDRESSEE_PLAN_CUE 接手）。
  assertEquals(practiceInviteLevelFor("那就約起來嗎？"), "direct");
  assertEquals(practiceInviteLevelFor("要不要出去走走嗎"), "direct");
  assertEquals(practiceInviteLevelFor("我在樓下了，妳下來嗎"), "direct");
  assertEquals(practiceInviteLevelFor("想跟妳去看那部電影"), "direct");
});

Deno.test("practice invite classifier ignores counterfactual 差點 plan clauses", () => {
  // 第 12 輪 eval FP 樣句：「差點想直接找妳劇透」＝反事實未遂非提案。
  assertEquals(
    practiceInviteLevelFor(
      "第三章那邊其實有點小反轉，我看完差點想直接找妳劇透，妳要先聽爆雷版還是自己抓時間追？",
    ),
    "none",
  );
  // 真提案不得鬆：沒有差點就是真的想找妳。
  assertEquals(practiceInviteLevelFor("我想直接找妳聊"), "direct");
  assertEquals(practiceInviteLevelFor("週六找妳去吃鍋"), "direct");
});

Deno.test("practice invite classifier ignores taste-preference questions and epistemic comparisons", () => {
  // 真機 gh6 FP 樣句（2026-07-23 討推薦局）：品味/習慣問句與推測比較句
  // 撞上 GENERIC_PROPOSAL 的「動詞…嗎/吧」語尾就單獨判 direct。
  // 「妳喝拿鐵挑剔嗎」問的是她挑不挑、「跟平常喝的應該不一樣吧」是推測
  // 感受差異，都沒有把她放進任何行動計畫。
  for (
    const line of [
      "私藏口袋名單還在更新中，比較像是拿鐵愛好者的巡店計畫，妳喝拿鐵挑剔嗎？",
      "我口袋確實有幾間，但我想先聽妳怎麼喝。睡到中午起來的拿鐵，跟平常喝的應該不一樣吧？",
      "妳喝咖啡有什麼講究嗎？",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "none", line);
  }
  // 真提案不得鬆：語尾同是嗎/吧的真邀約維持原判。
  assertEquals(practiceInviteLevelFor("明天中午一起喝咖啡吧"), "direct");
  assertEquals(practiceInviteLevelFor("改天去喝一杯嗎？"), "soft");
});

Deno.test("practice invite classifier ignores share-content promises and her-intent probes", () => {
  // 真機 gh6/gh7 FP 樣句（2026-07-23 通解第二波）：「改天整理給妳」是分享
  // 內容的承諾不是見面；「會有想殺去的候選地嗎」「有偏好嗎」是在測她的
  // 意向與品味——通解教學句教的收口正是這些，gate 不得反殺。
  for (
    const line of [
      "私藏口袋名單確實有幾間，改天整理給妳當拿鐵補給站，妳平常喝拿鐵有偏好嗎？",
      "口袋名單是有幾間常回購的，改天整理給妳。妳呢，除了拿鐵開機，選咖啡廳看氣氛還是看甜點？",
      "最有感那次不是風景多美，是整趟都很隨性，臨時改路線也照樣爽，期待感直接拉滿。妳呢，查機票查久了會有想殺去的候選地嗎？",
    ]
  ) {
    assertEquals(practiceInviteLevelFor(line), "none", line);
  }
  // 真邀約不得鬆：帶妳去／約人見面的軟硬邀照舊。
  assertEquals(practiceInviteLevelFor("改天帶妳去那間店"), "soft");
  assertEquals(practiceInviteLevelFor("改天約杯咖啡吧"), "soft");
  assertEquals(practiceInviteLevelFor("下次會想跟我一起去嗎"), "soft");
});

Deno.test("practice invite classifier ignores 打分數 scoring compounds", () => {
  // 真機 gh6 FP 樣句（2026-07-23）：「妳打分數會嚴嗎」＝問她評分標準，
  // 「打」是打分數複合詞首字不是提案動詞。
  assertEquals(
    practiceInviteLevelFor(
      "私藏是有一兩間啦，不過拿鐵這種開機鍵級的，我覺得妳這種每天喝的才夠格當裁判，妳打分數會嚴嗎？",
    ),
    "none",
  );
  // 真提案不得鬆：打球約戰照算。
  assertEquals(practiceInviteLevelFor("週末一起打球嗎"), "direct");
});

Deno.test("practice invite classifier ignores imagination probes about her own plans", () => {
  // 真機 gh7 FP 樣句（2026-07-23）：「會偷偷想像自己去哪嗎」＝問她的想像，
  // 不是把她放進行程。
  assertEquals(
    practiceInviteLevelFor(
      "最有感一次是自己一個人上路，完全沒排行程，走到哪算哪，那種不確定感反而最有記憶點。妳查特價機票時，會偷偷想像自己去哪嗎？",
    ),
    "none",
  );
  // 真提案不得鬆：想像完直接約照算。
  assertEquals(
    practiceInviteLevelFor("別只想像了，週六直接一起去吧"),
    "direct",
  );
});

Deno.test("practice invite classifier ignores perception 看到 complements", () => {
  // 真機 gh1 FP 樣句（2026-07-23）：「妳看到那邊的節奏還順嗎」＝問她讀到
  // 哪裡的感受，「看到」是感知補語不是提案動詞。
  assertEquals(
    practiceInviteLevelFor("哈哈第三章也是蠻關鍵的轉折，不急，妳看到那邊的節奏還順嗎？"),
    "none",
  );
  // 真提案不得鬆：約看電影照算。
  assertEquals(practiceInviteLevelFor("週六一起去看電影嗎"), "direct");
});

Deno.test("share/imagination stripping keeps trailing real invites in run-on clauses", () => {
  // Codex P2（2026-07-23）：無標點連寫時剝除不得吞掉後面的真邀約。
  assertEquals(
    practiceInviteLevelFor("我把定位傳給妳週六一起去"),
    "direct",
  );
  assertEquals(
    practiceInviteLevelFor("別只想像了週六直接一起去吧"),
    "direct",
  );
  // 原 FP 修不得回退：分享承諾與想像問句仍是 none。
  assertEquals(
    practiceInviteLevelFor(
      "口袋名單是有幾間常回購的，改天整理給妳。妳呢，除了拿鐵開機，選咖啡廳看氣氛還是看甜點？",
    ),
    "none",
  );
  assertEquals(
    practiceInviteLevelFor(
      "妳查特價機票時，會偷偷想像自己去哪嗎？",
    ),
    "none",
  );
});
