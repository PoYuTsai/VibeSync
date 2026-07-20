// social-game FSM v2 pure rules tests.
// Run: deno test supabase/functions/practice-chat/game_fsm_test.ts

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  applyGameLearningDelta,
  buildGameStrategy,
  evaluateGameFsm,
  hasExplicitSrGameStrategy,
} from "./game_fsm.ts";
import { applyLearningClassification } from "./temperature.ts";
import { GIRL_PROFILES, resolvePracticeProfile } from "./practice_persona.ts";

const SR_STRATEGY_SEMANTIC_EXPECTATIONS: Record<
  string,
  { required: string[]; legacyMismatches: string[] }
> = {
  practice_girl_004: {
    required: ["咖啡", "選物", "吐槽"],
    legacyMismatches: ["法律", "健身"],
  },
  practice_girl_006: {
    required: ["瑜珈", "身心平衡", "週末爬山"],
    legacyMismatches: ["現場音樂", "晚茶"],
  },
  practice_girl_007: {
    required: ["行銷", "電影", "音樂祭"],
    legacyMismatches: ["自律健身", "果昔"],
  },
  practice_girl_008: {
    required: ["診間", "在家做菜", "追劇"],
    legacyMismatches: ["藝術品味", "畫廊", "街頭攝影"],
  },
  practice_girl_009: {
    required: ["櫃上", "穿搭", "保養"],
    legacyMismatches: ["會議空檔", "事業企圖"],
  },
  practice_girl_028: {
    required: ["研究", "實驗室", "自助旅行"],
    legacyMismatches: ["迷你行程"],
  },
  practice_girl_032: {
    required: ["櫃上", "穿搭", "假日旅行"],
    legacyMismatches: ["讀書筆記", "講座後"],
  },
  practice_girl_033: {
    required: ["行銷", "跑活動加班", "音樂祭"],
    legacyMismatches: ["主廚推薦", "炫耀式點餐"],
  },
  practice_girl_036: {
    required: ["顧店手沖", "搞笑表情", "選物"],
    legacyMismatches: ["獨立音樂", "黑膠唱片"],
  },
  practice_girl_038: {
    required: ["瑜珈", "旅行進修", "健康飲食"],
    legacyMismatches: ["寵物故事", "寵物友善"],
  },
  practice_girl_051: {
    required: ["美甲", "做指甲", "拍照"],
    legacyMismatches: ["創業韌性", "展示活動"],
  },
  practice_girl_052: {
    required: ["飛行排班", "落地休整", "旅行"],
    legacyMismatches: ["穿搭細節", "雞尾酒吧"],
  },
  practice_girl_055: {
    required: ["跟診", "烘焙", "看書"],
    legacyMismatches: ["醫療現場", "醫院人脈"],
  },
  practice_girl_063: {
    required: ["理財", "週末烘焙", "老屋咖啡"],
    legacyMismatches: ["語言交換", "跨文化"],
  },
  practice_girl_065: {
    required: ["跑活動", "夜景", "音樂祭"],
    legacyMismatches: ["舞蹈節奏", "拉丁舞"],
  },
  practice_girl_079: {
    required: ["帶課訓練", "健身", "健康料理"],
    legacyMismatches: ["理財紀律", "葡萄酒吧"],
  },
  practice_girl_080: {
    required: ["跑工地", "空間設計", "老屋"],
    legacyMismatches: ["戶外沉著", "步道咖啡"],
  },
  practice_girl_082: {
    required: ["接案畫圖", "插畫", "獨立漫畫"],
    legacyMismatches: ["遊戲梗", "街機小約", "桌遊咖啡"],
  },
  practice_girl_085: {
    required: ["備課", "語言", "手帳"],
    legacyMismatches: ["電影品味", "獨立電影", "爆雷"],
  },
  practice_girl_087: {
    required: ["同理", "界線", "散步"],
    legacyMismatches: ["法律式", "法院", "辯論", "人脈背書"],
  },
};

Deno.test("evaluateGameFsm accumulates BORING when user interrogates instead of sharing", () => {
  const snapshot = evaluateGameFsm({
    turns: [
      { role: "user", text: "你幾歲？住哪？做什麼？" },
      { role: "ai", text: "你查戶口喔 XD" },
      { role: "user", text: "那你下班都去哪？今天在哪？" },
    ],
    temperatureScore: 30,
    familiarityScore: 12,
    partnerMood: "neutral",
  });

  assert(snapshot.failureStates.includes("BORING"));
  assert(snapshot.hidden.inv <= 10);
  assertEquals(snapshot.targetVariable, "Value + Emotion");
});

Deno.test("evaluateGameFsm flags GREASY when low familiarity over-escalates", () => {
  const snapshot = evaluateGameFsm({
    turns: [{ role: "user", text: "今晚直接去我家睡啦" }],
    temperatureScore: 42,
    familiarityScore: 18,
    partnerMood: "neutral",
  });

  assert(snapshot.failureStates.includes("GREASY"));
  assert(snapshot.failureStates.includes("GHOST_RISK"));
  assertEquals(snapshot.spicyLevel, "L0");
  assert(snapshot.hidden.safety < 40);
});

Deno.test("evaluateGameFsm moves frame points and heat on test pass or fail", () => {
  const pass = evaluateGameFsm({
    turns: [{ role: "user", text: "好啦我承認我有點太會加戲，但至少不無聊吧" }],
    temperatureScore: 55,
    familiarityScore: 45,
    partnerMood: "amused",
    classification: {
      connection: "caught",
      impact: "medium",
      testHandling: "passed",
      boundary: "safe",
      hintAlignment: "none",
      partnerMood: "amused",
      moodConfidence: 0.8,
      innerThought: "他有接住我的吐槽。",
    },
  });
  const fail = evaluateGameFsm({
    turns: [{ role: "user", text: "我哪有，我只是正常問而已，不要想太多" }],
    temperatureScore: 55,
    familiarityScore: 45,
    partnerMood: "guarded",
    classification: {
      connection: "defensive",
      impact: "medium",
      testHandling: "failed",
      boundary: "safe",
      hintAlignment: "none",
      partnerMood: "guarded",
      moodConfidence: 0.8,
      innerThought: "他好像有點急著解釋。",
    },
  });

  assert(pass.hidden.fp > fail.hidden.fp);
  assert(pass.hidden.heatBias > 0);
  assert(fail.hidden.heatBias < 0);
  assert(fail.failureStates.includes("FRAME_COLLAPSE"));
});

Deno.test("evaluateGameFsm advances soft invite toward close when maturity is high enough", () => {
  const snapshot = evaluateGameFsm({
    turns: [{ role: "user", text: "那下次找一間你會想吐槽的咖啡店走走？" }],
    temperatureScore: 76,
    familiarityScore: 68,
    partnerMood: "comfortable",
  });

  assertEquals(snapshot.phase, "P5_CLOSE");
  assert(snapshot.hidden.inv >= 60);
  assertEquals(snapshot.speedInviteDirection, "direct_invite_low_pressure");
});

Deno.test("evaluateGameFsm does not turn an activity topic into a soft invite", () => {
  for (
    const text of [
      "剛看到妳喜歡咖啡，我今天路過一家聞起來超香的店。",
      "我今天吃飯吃太飽。",
      "晚點自己去走走。",
      "妳平常會去咖啡店嗎？",
      "你平常想不想喝咖啡？",
      "昨天我們一起喝咖啡，聊得滿開心。",
      "上次陪妳去咖啡店，妳點了拿鐵。",
      "我們都喜歡喝咖啡。",
      "我們喝咖啡的口味差很多。",
      "我們吃飯時間通常不一樣。",
      "我跟朋友一起喝咖啡。",
      "朋友問我要不要一起喝咖啡。",
      "要不要推薦一家咖啡店？",
      "我不想約你喝咖啡。",
      "我沒有要約妳喝咖啡。",
      "我不會帶妳去咖啡店。",
      "我們去喝咖啡這件事已經取消了。",
      "明天你去哪裡吃飯？",
      "週末你會去看電影嗎？",
      "昨天一起喝咖啡，下次再說。",
      "朋友問我，要不要一起喝咖啡？",
      "她說，改天一起喝咖啡。",
      "媽媽問我要不要一起喝咖啡。",
      "室友說週末一起看電影。",
      "同學問我週末要不要一起喝咖啡。",
      "昨天我問妳要不要一起喝咖啡？",
      "上週我問妳，要不要一起喝咖啡？",
      "昨天一起喝咖啡？下次再說。",
      "明天一起喝咖啡，取消了。",
      "明天一起喝咖啡，算了。",
      "本來週末一起看電影，後來取消了。",
      "我取消了明天一起吃飯。",
      "我不是要約你喝咖啡。",
      "沒有要約妳喝咖啡啦。",
      "我沒有想約你喝咖啡。",
      "我沒說要約妳喝咖啡。",
      "已經取消明天一起喝咖啡。",
      "要不要不去喝咖啡？",
      "我不去看電影。",
      "別喝咖啡。",
      "好奇你週末會去哪裡吃飯？",
      "明天去哪裡吃飯？",
      "明天幾點吃飯？",
      "你明天幾點吃飯？",
      "週末會去看電影嗎？",
      "明天打算去哪裡？",
      "週末打算做什麼？",
      "你明天要不要去看醫生？",
      "今晚要打報告嗎？",
      "明天找工作嗎？",
      "今天晚上當班嗎？",
      "明天會相當忙吧。",
      "看起來會下雨吧。",
      "大約幾點下班？",
      "有什麼意見？",
      "請妳推薦一家咖啡店。",
      "我請妳不要生氣。",
      "想不想看我上次拍的照片？",
      "要不要看我剛拍的影片？",
      "要不要我幫你找一間咖啡店？",
      "要不要跟我說妳去哪家咖啡店？",
      "想不想告訴我你去哪吃飯？",
      "我想請你幫我看一下履歷。",
      "我們去年看的電影你還記得嗎？",
      "我們剛才一起吃飯不是嗎？",
      "我們一起看電影的品味很像吧？",
      "朋友跟我一起去看展，還不錯吧？",
      "明天他們一起吃飯吧？",
      "他們都有空去看電影嗎？",
      "你明晚想不想自己去看電影？",
      "我們喜歡一起喝咖啡嗎？",
      "你今晚要不要去睡覺？",
      "你週末要不要去看牙醫？",
      "我們剛一起喝完咖啡吧？",
      "你今晚要不要去洗澡？",
      "你週末要不要去買菜？",
      "你明天想不想去跑步？",
      "你明天要不要去睡？",
      "你下週想不想去復健？",
      "你明天要不要去看牙？",
      "你要不要吃藥？",
      "你要不要打電話？",
      "想不想看這篇文章？",
      "她邀你出去。",
    ]
  ) {
    const snapshot = evaluateGameFsm({
      turns: [{ role: "user", text }],
      temperatureScore: 30,
      familiarityScore: 0,
      partnerMood: "neutral",
    });

    assertEquals(snapshot.phase === "P5_CLOSE", false, text);
    assert(snapshot.hidden.inv < 40, text);
  }
});

Deno.test("evaluateGameFsm recognizes explicit and elliptical activity invitations", () => {
  for (
    const text of [
      "改天要不要一起喝咖啡？",
      "那下次找一間你會想吐槽的咖啡店走走？",
      "有空可以約個咖啡吧鄰居",
      "有機會約一杯 桃園或台北",
      "這間咖啡廳感覺你會喜歡，下次有機會一起去踩點。",
      "你這個潛水故事聽起來很會玩欸，有機會讓你當一次新手村教練。",
      "那間展感覺可以欸，下次如果剛好都有空可以去晃一下。",
      "明天七點信義區吃飯？",
      "改天喝咖啡？",
      "有空吃個飯？",
      "我請妳喝咖啡。",
      "這週末看電影？",
      "要不要一起喝一杯？",
      "哪天一起逛街？",
      "找個時間吃頓飯？",
      "改天一起吃拉麵？",
      "週末要不要去逛市集？",
      "有空一起喝一杯？",
      "我們去吃飯吧。",
      "明天不要喝咖啡，但週六一起去爬山吧。",
      "我想跟你一起喝咖啡。",
      "可以一起吃飯。",
      "不然一起吃飯。",
      "乾脆一起去看電影。",
      "我們去吃飯。",
      "跟我去看電影吧。",
      "陪我去看展吧。",
      "改天喝咖啡。",
      "有空來找我。",
      "我們週末唱歌吧。",
      "如果妳有空，我們去喝咖啡。",
      "等妳忙完，我們去吃飯。",
      "妳哪天有空跟我說，我們去吃飯。",
      "取消原本行程，改天一起喝咖啡？",
      "明天來找我。",
      "週末碰個面吧。",
      "見一面吧。",
      "下次再約。",
      "下次再聚。",
      "改天續攤。",
      "走，去喝咖啡。",
      "喝咖啡去。",
      "來我家吃飯吧。",
      "過來喝咖啡吧。",
      "昨天沒喝成，但下次一起喝吧。",
      "改天一起去野餐。",
      "下次一起騎腳踏車。",
      "明晚一起去聽演唱會。",
      "找天去陶藝教室。",
      "這週一起去游泳吧。",
      "有空一起健身？",
      "週末一起去露營。",
      "我帶你去吃好吃的。",
      "好想跟你一起喝咖啡。",
      "好想和你一起吃飯。",
      "我想找你改天喝咖啡。",
      "改天到我家。",
      "週末到我家吃飯。",
      "有空去我家坐坐。",
      "不是去看電影，是一起逛書店。",
      "不是喝咖啡，是一起去吃飯。",
    ]
  ) {
    const snapshot = evaluateGameFsm({
      turns: [{ role: "user", text }],
      temperatureScore: 30,
      familiarityScore: 0,
      partnerMood: "neutral",
    });

    assertEquals(snapshot.phase, "P5_CLOSE", text);
    assertEquals(
      snapshot.speedInviteDirection,
      "direct_invite_low_pressure",
      text,
    );
  }
});

Deno.test("evaluateGameFsm keeps a future invite that references a prior venue", () => {
  const snapshot = evaluateGameFsm({
    turns: [{ role: "user", text: "下次去上次那家喝咖啡。" }],
    temperatureScore: 30,
    familiarityScore: 0,
    partnerMood: "neutral",
  });

  assertEquals(snapshot.phase, "P5_CLOSE");
  assert(snapshot.hidden.inv >= 40);
});

Deno.test("applyGameLearningDelta scales game deltas but clamps the amplitude", () => {
  const basePositive = applyLearningClassification({
    heatScore: 50,
    familiarityScore: 50,
  }, {
    connection: "caught",
    impact: "strong",
    testHandling: "passed",
    boundary: "safe",
    hintAlignment: "none",
    partnerMood: "amused",
    moodConfidence: 0.9,
    innerThought: "他接得很穩。",
  });
  const snapshot = evaluateGameFsm({
    turns: [{ role: "user", text: "你這題有陷阱吧，我接，但不照劇本走" }],
    temperatureScore: 50,
    familiarityScore: 50,
    partnerMood: "amused",
    classification: basePositive.classification,
  });
  const gamePositive = applyGameLearningDelta({
    judgement: basePositive,
    currentTemperature: 50,
    currentFamiliarity: 50,
    snapshot,
  });

  assert(gamePositive.delta >= basePositive.delta + 4);
  assert(gamePositive.familiarityDelta >= basePositive.familiarityDelta + 3);
  assert(gamePositive.delta <= 18);

  const baseNegative = applyLearningClassification({
    heatScore: 50,
    familiarityScore: 50,
  }, {
    connection: "overstepped",
    impact: "strong",
    testHandling: "none",
    boundary: "overstep",
    hintAlignment: "none",
    partnerMood: "guarded",
    moodConfidence: 1,
    innerThought: "這太快了。",
  });
  const greasy = evaluateGameFsm({
    turns: [{ role: "user", text: "去我家睡啦" }],
    temperatureScore: 50,
    familiarityScore: 20,
    partnerMood: "guarded",
    classification: baseNegative.classification,
  });
  const gameNegative = applyGameLearningDelta({
    judgement: baseNegative,
    currentTemperature: 50,
    currentFamiliarity: 50,
    snapshot: greasy,
  });

  assertEquals(gameNegative.delta, -18);
  assertEquals(gameNegative.familiarityDelta, -18);
});

Deno.test("evaluateGameFsm marks fake familiarity and social proof as reality-anchor traps", () => {
  const snapshot = evaluateGameFsm({
    turns: [{
      role: "user",
      text:
        "我是陳醫師的學生，最近在北醫實習的牙醫師 Bruce，上次經過你們診所跟 Joyce 要的 Line",
    }],
    temperatureScore: 35,
    familiarityScore: 10,
    partnerMood: "neutral",
  });

  assert(snapshot.realityFlags.includes("social_proof_attempt"));
  assert(snapshot.realityFlags.includes("fake_familiarity"));
  assert(snapshot.failureStates.includes("FRAME_OVERREACH"));
  assertEquals(snapshot.spicyLevel, "L0");
});

Deno.test("evaluateGameFsm does not treat content, venue, or ordinary past references as reality traps", () => {
  for (
    const text of [
      "並不是不打算帶妳看展，只是想閱讀策展介紹。",
      "我朋友推薦這家咖啡店，聽說甜點不錯。",
      "同事推薦我去看這個展。",
      "主管推薦這部電影給我。",
      "老師推薦我看這篇文章。",
      "朋友介紹的書店最近在辦講座。",
      "同事給我一組 LINE 貼圖。",
      "朋友叫我來找妳推薦的書店。",
      "老師介紹我認識這位導演。",
      "上次那家店的咖啡很好喝。",
      "我上次看過這部電影，結局很有趣。",
      "妳朋友推薦哪家店？",
    ]
  ) {
    const snapshot = evaluateGameFsm({
      turns: [{ role: "user", text }],
      temperatureScore: 35,
      familiarityScore: 10,
      partnerMood: "neutral",
    });

    assertEquals(
      snapshot.realityFlags.includes("social_proof_attempt"),
      false,
      text,
    );
    assertEquals(
      snapshot.realityFlags.includes("fake_familiarity"),
      false,
      text,
    );
    assertEquals(snapshot.realityFlags.includes("OBVIOUS_TRAP"), false, text);
  }
});

Deno.test("evaluateGameFsm blocks unconfirmed referral and familiarity claims", () => {
  const cases = [
    {
      text: "我朋友把妳的 Line 給我，說可以直接來找妳。",
      flag: "social_proof_attempt" as const,
    },
    {
      text: "陳醫師介紹我來找妳。",
      flag: "social_proof_attempt" as const,
    },
    {
      text: "朋友介紹我們認識。",
      flag: "social_proof_attempt" as const,
    },
    {
      text: "我是 Joyce 介紹來認識妳的。",
      flag: "social_proof_attempt" as const,
    },
    {
      text: "小美把妳的 Line 給我。",
      flag: "social_proof_attempt" as const,
    },
    {
      text: "我是陳醫師的學生。",
      flag: "social_proof_attempt" as const,
    },
    {
      text: "我們上次在信義區見過，妳還記得吧。",
      flag: "fake_familiarity" as const,
    },
    {
      text: "我知道妳住台中。",
      flag: "fake_familiarity" as const,
    },
    {
      text: "我跟妳同事聊過妳。",
      flag: "fake_familiarity" as const,
    },
  ];

  for (const { text, flag } of cases) {
    const snapshot = evaluateGameFsm({
      turns: [{ role: "user", text }],
      temperatureScore: 35,
      familiarityScore: 10,
      partnerMood: "neutral",
    });

    assert(snapshot.realityFlags.includes(flag), text);
    assert(snapshot.realityFlags.includes("OBVIOUS_TRAP"), text);
    assert(snapshot.failureStates.includes("FRAME_OVERREACH"), text);
    assertEquals(snapshot.spicyLevel, "L0", text);
  }
});

Deno.test("evaluateGameFsm accepts only the same fact explicitly confirmed by an earlier partner turn", () => {
  const cases = [
    [
      "對，Joyce 有先跟我說她把我的 Line 給你。",
      "我是 Joyce 給我 Line 的 Bruce。",
    ],
    [
      "對，我們上次在信義區見過，我記得。",
      "我們上次在信義區見過，妳還記得吧。",
    ],
    ["我住台中，平常在西區上班。", "我記得妳住台中。"],
    ["我上次說過我喜歡爵士樂。", "妳上次說喜歡爵士樂。"],
    [
      "對，Joyce 是我同事，她說有跟你聊過。",
      "我跟妳同事 Joyce 聊過。",
    ],
    ["對，小美有說她把我的 Line 給你。", "小美把妳的 Line 給我。"],
    ["對，我們上次一起去看展。", "我們上次一起去看展。"],
    ["對，我知道你是陳醫師的學生。", "我是陳醫師的學生。"],
    ["對，朋友有跟我說是她介紹我們認識的。", "朋友介紹我們認識。"],
    ["對，陳醫師有說是他介紹你來找我。", "陳醫師介紹我來找妳。"],
  ] as const;

  for (const [partnerConfirmation, userReference] of cases) {
    const snapshot = evaluateGameFsm({
      turns: [
        { role: "ai", text: partnerConfirmation },
        { role: "user", text: userReference },
      ],
      temperatureScore: 35,
      familiarityScore: 10,
      partnerMood: "neutral",
    });

    assertEquals(snapshot.realityFlags, [], userReference);
    assertEquals(
      snapshot.failureStates.includes("FRAME_OVERREACH"),
      false,
      userReference,
    );
  }
});

Deno.test("evaluateGameFsm does not accept denial, questions, or a different fact as grounding", () => {
  const cases = [
    [
      "Joyce 沒有把我的 Line 給你。",
      "我是 Joyce 給我 Line 的 Bruce。",
      "social_proof_attempt" as const,
    ],
    [
      "Joyce 有把我的 Line 給你嗎？",
      "我是 Joyce 給我 Line 的 Bruce。",
      "social_proof_attempt" as const,
    ],
    [
      "對，Amy 有先跟我說她把我的 Line 給你。",
      "我是 Joyce 給我 Line 的 Bruce。",
      "social_proof_attempt" as const,
    ],
    [
      "我住台北。",
      "我知道妳住台中。",
      "fake_familiarity" as const,
    ],
    [
      "我們以前見過嗎？",
      "我們上次在信義區見過，妳還記得吧。",
      "fake_familiarity" as const,
    ],
    [
      "對吧，我們以前見過嗎？",
      "我們上次在信義區見過，妳還記得吧。",
      "fake_familiarity" as const,
    ],
    [
      "我不住台中。",
      "我知道妳住台中。",
      "fake_familiarity" as const,
    ],
    [
      "對，我們上次在台中見過。",
      "我們上次在信義區見過，妳還記得吧。",
      "fake_familiarity" as const,
    ],
    [
      "對，我介紹 Joyce 給你認識。",
      "我是 Joyce 介紹來認識妳的。",
      "social_proof_attempt" as const,
    ],
    [
      "對，你把我的 Line 給 Joyce。",
      "我是 Joyce 給我 Line 的 Bruce。",
      "social_proof_attempt" as const,
    ],
    [
      "對，我知道你是陳醫師的助理。",
      "我是陳醫師的學生。",
      "social_proof_attempt" as const,
    ],
  ] as const;

  for (const [partnerText, userText, flag] of cases) {
    const snapshot = evaluateGameFsm({
      turns: [
        { role: "ai", text: partnerText },
        { role: "user", text: userText },
      ],
      temperatureScore: 35,
      familiarityScore: 10,
      partnerMood: "neutral",
    });

    assert(snapshot.realityFlags.includes(flag), userText);
    assert(snapshot.realityFlags.includes("OBVIOUS_TRAP"), userText);
    assert(snapshot.failureStates.includes("FRAME_OVERREACH"), userText);
  }
});

Deno.test("evaluateGameFsm does not use a later partner turn to retroactively ground a claim", () => {
  const snapshot = evaluateGameFsm({
    turns: [
      { role: "user", text: "我是 Joyce 給我 Line 的 Bruce。" },
      { role: "ai", text: "對，Joyce 有先跟我說她把我的 Line 給你。" },
    ],
    temperatureScore: 35,
    familiarityScore: 10,
    partnerMood: "neutral",
  });

  assert(snapshot.realityFlags.includes("social_proof_attempt"));
  assert(snapshot.realityFlags.includes("OBVIOUS_TRAP"));
});

Deno.test("evaluateGameFsm flags a direct introduced-me referral until it is grounded", () => {
  const snapshot = evaluateGameFsm({
    turns: [{ role: "user", text: "老師介紹我來認識妳。" }],
    temperatureScore: 35,
    familiarityScore: 10,
    partnerMood: "neutral",
  });

  assert(snapshot.realityFlags.includes("social_proof_attempt"));
  assert(snapshot.realityFlags.includes("OBVIOUS_TRAP"));
  assert(snapshot.failureStates.includes("FRAME_OVERREACH"));
});

Deno.test("evaluateGameFsm does not ground a prior interaction at a different place", () => {
  const snapshot = evaluateGameFsm({
    turns: [
      { role: "ai", text: "對啊，我記得上次我們在河濱看過。" },
      { role: "user", text: "上次我們在老戲院看過。" },
    ],
    temperatureScore: 35,
    familiarityScore: 10,
    partnerMood: "neutral",
  });

  assert(snapshot.realityFlags.includes("fake_familiarity"));
  assert(snapshot.realityFlags.includes("OBVIOUS_TRAP"));
  assert(snapshot.failureStates.includes("FRAME_OVERREACH"));
});

Deno.test("buildGameStrategy derives distinct SR hooks", () => {
  const srMia = resolvePracticeProfile({ profileId: "practice_girl_004" });
  const srNora = resolvePracticeProfile({ profileId: "practice_girl_006" });

  const mia = buildGameStrategy(srMia);
  const nora = buildGameStrategy(srNora);

  assert(mia);
  assert(nora);
  assert(mia.valueHooks.join("|") !== nora.valueHooks.join("|"));
  assert(mia.closeHooks.length > 0);
  assert(mia.punishments.length > 0);
});

Deno.test("buildGameStrategy gives non-SR cards concrete fallback hooks from tags", () => {
  const normalAlice = resolvePracticeProfile({
    profileId: "practice_girl_001",
  });

  const strategy = buildGameStrategy(normalAlice);

  assert(strategy, "non-SR card should still get a concrete strategy");
  assertEquals(strategy.profileId, "practice_girl_001");
  assertEquals(hasExplicitSrGameStrategy("practice_girl_001"), false);
  assert(strategy.valueHooks.length > 0);
  assert(strategy.closeHooks.length > 0);
  assert(strategy.punishments.length > 0);
  assert(strategy.testStyle.trim().length > 0);
  assert(strategy.tensionStyle.trim().length > 0);
  const girl = normalAlice.girl;
  const hookText = [...strategy.valueHooks, ...strategy.closeHooks].join("|");
  assert(
    [...girl.interestTags, ...girl.lifestyleTags].some((tag) =>
      hookText.includes(tag)
    ),
    "fallback hooks should be derived from this card's own tags",
  );
});

Deno.test("every card in the pool gets a non-empty Game strategy regardless of rarity", () => {
  const seenRarities = new Set<string>();
  for (const girl of GIRL_PROFILES) {
    seenRarities.add(girl.rarity);
    const profile = resolvePracticeProfile({ profileId: girl.profileId });
    const strategy = buildGameStrategy(profile);
    assert(
      strategy,
      `${girl.profileId} (${girl.rarity}) should get a strategy`,
    );
    assert(
      strategy.valueHooks.length > 0,
      `${girl.profileId} should have valueHooks`,
    );
    assert(
      strategy.closeHooks.length > 0,
      `${girl.profileId} should have closeHooks`,
    );
    assert(
      strategy.punishments.length > 0,
      `${girl.profileId} should have punishments`,
    );
  }
  assert(seenRarities.has("sr"));
  assert(seenRarities.has("r"));
  assert(seenRarities.has("n"));
});

Deno.test("every SR card has an explicit Game strategy track", () => {
  const srProfiles = GIRL_PROFILES.filter((girl) => girl.rarity === "sr");

  assertEquals(srProfiles.length > 0, true);
  for (const girl of srProfiles) {
    const profile = resolvePracticeProfile({ profileId: girl.profileId });
    const strategy = buildGameStrategy(profile);
    assert(strategy, `${girl.profileId} should have an SR Game strategy`);
    assert(
      hasExplicitSrGameStrategy(girl.profileId),
      `${girl.profileId} should not rely on fallback derivation`,
    );
    assert(strategy.valueHooks.length >= 2);
    assert(strategy.closeHooks.length >= 2);
    assert(strategy.punishments.length >= 1);
  }
});

Deno.test("every explicit SR Game strategy uses Traditional Chinese prompt values", () => {
  const srProfiles = GIRL_PROFILES.filter((girl) => girl.rarity === "sr");

  for (const girl of srProfiles) {
    assert(
      hasExplicitSrGameStrategy(girl.profileId),
      `${girl.profileId} should have an explicit SR Game strategy`,
    );
    const strategy = buildGameStrategy(
      resolvePracticeProfile({ profileId: girl.profileId }),
    );
    const promptValues = [
      ...strategy.valueHooks,
      strategy.testStyle,
      strategy.tensionStyle,
      ...strategy.closeHooks,
      ...strategy.punishments,
    ];

    for (const value of promptValues) {
      assert(
        !/[A-Za-z]/.test(value),
        `${girl.profileId} leaked English prompt value: ${value}`,
      );
    }
  }
});

Deno.test("every explicit SR Game strategy stays semantically aligned with its current catalog card", () => {
  const srProfiles = GIRL_PROFILES.filter((girl) => girl.rarity === "sr");
  assertEquals(
    Object.keys(SR_STRATEGY_SEMANTIC_EXPECTATIONS).sort(),
    srProfiles.map((girl) => girl.profileId).sort(),
    "semantic parity table must cover exactly the current SR pool",
  );

  for (const girl of srProfiles) {
    const expectation = SR_STRATEGY_SEMANTIC_EXPECTATIONS[girl.profileId];
    const strategy = buildGameStrategy(
      resolvePracticeProfile({ profileId: girl.profileId }),
    );
    const strategyText = [
      ...strategy.valueHooks,
      strategy.testStyle,
      strategy.tensionStyle,
      ...strategy.closeHooks,
      ...strategy.punishments,
    ].join("｜");

    for (const required of expectation.required) {
      assert(
        strategyText.includes(required),
        `${girl.profileId} strategy lost current-card anchor: ${required}`,
      );
    }

    const matchedInterests = girl.interestTags.filter((tag) =>
      strategyText.includes(tag)
    );
    assert(
      matchedInterests.length >= 2,
      `${girl.profileId} strategy should use at least two current interests; matched=${
        matchedInterests.join(",")
      }`,
    );
    assert(
      girl.lifestyleTags.some((tag) => strategyText.includes(tag)),
      `${girl.profileId} strategy should use at least one current lifestyle tag`,
    );

    for (const mismatch of expectation.legacyMismatches) {
      assert(
        !strategyText.includes(mismatch),
        `${girl.profileId} strategy still contains legacy mismatched concept: ${mismatch}`,
      );
    }
  }
});
