import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  assertHintFactClaimsSupported,
  buildHintFactContext,
  extractHintFactClaims,
  partnerFactClaimsFromProfile,
} from "./hint_fact_ledger.ts";
import { resolvePracticeProfile } from "./practice_persona.ts";

const ERROR = "hint_quality_invalid_unsupported_detail";

Deno.test("typed Hint fact ledger rejects partner facts rewritten as user facts", () => {
  const cases = [
    ["我住台南，平常很少跑台北。", "我住的地方也是台南，妳最常去哪一區？"],
    ["我住台南，平常很少跑台北。", "台南也是我家鄉，這個生活感很熟。"],
    ["我讀台大，最近剛畢業。", "我念的也是台大，剛畢業這段很有感。"],
    ["我讀台大，最近剛畢業。", "台大也是我母校，這也太巧了。"],
    ["我是社工，最近工作很忙。", "社工也是我的工作，妳最近最累哪一段？"],
    ["我三十歲，最近開始調作息。", "我也差不多30歲，調作息這段很有感。"],
    ["我最愛壽司，每週都會吃。", "我最愛的也是壽司，妳最常點哪一種？"],
    ["我平常最愛爬山。", "爬山也是我的興趣，妳最愛哪條路線？"],
    ["我養了兩隻貓。", "兩隻貓我家也有，妳家哪隻最皮？"],
    ["我有一個妹妹。", "妹妹我也有一個，這種吐槽我懂。"],
    ["我叫阿哲。", "阿哲也是我的名字，這也太巧了。"],
    ["我明天七點有空。", "明天七點我這邊也排得開。"],
    ["我是社工。", "我不是社工，不過工作忙這點我懂。"],
  ] as const;

  for (const [partner, output] of cases) {
    const context = buildHintFactContext({
      turns: [{ role: "ai", text: partner }],
    });
    assertThrows(
      () =>
        assertHintFactClaimsSupported({
          text: output,
          field: "reply",
          context,
        }),
      Error,
      ERROR,
      `partner=${partner} output=${output}`,
    );
  }
});

Deno.test("typed Hint fact ledger rejects user facts rewritten as partner facts", () => {
  const cases = [
    ["我住台南。", "原來妳也住台南，難怪有同城感。"],
    ["我讀台大。", "原來妳也是台大校友。"],
    ["我是社工。", "原來妳也是社工，難怪懂這種累。"],
    ["我30歲。", "妳也差不多30歲，難怪作息有感。"],
    ["我養兩隻貓。", "妳家也有兩隻貓，最皮的是哪隻？"],
    ["我最愛壽司。", "壽司也是妳的最愛。"],
    ["我明天七點有空。", "妳明天七點也有空，那就好安排。"],
  ] as const;

  for (const [user, output] of cases) {
    const context = buildHintFactContext({
      turns: [
        { role: "user", text: user },
        { role: "ai", text: "換妳說說看。" },
      ],
    });
    assertThrows(
      () =>
        assertHintFactClaimsSupported({
          text: output,
          field: "reply",
          context,
        }),
      Error,
      ERROR,
      `user=${user} output=${output}`,
    );
  }
});

Deno.test("typed Hint fact ledger uses coaching viewpoint and quote ownership", () => {
  const partnerContext = buildHintFactContext({
    turns: [{ role: "ai", text: "我住台南。" }],
  });
  for (
    const coaching of [
      "她住台南，建議你也說自己住台南來製造同城感。",
      "她說住台南，建議你回「我也住台南」建立共鳴。",
    ]
  ) {
    assertThrows(
      () =>
        assertHintFactClaimsSupported({
          text: coaching,
          field: "coaching",
          context: partnerContext,
        }),
      Error,
      ERROR,
    );
  }

  assertHintFactClaimsSupported({
    text: "她說「我住台南」，先承接她的生活圈。",
    field: "coaching",
    context: partnerContext,
  });

  const userContext = buildHintFactContext({
    turns: [
      { role: "user", text: "我住台南。" },
      { role: "ai", text: "你住哪裡？" },
    ],
  });
  assertHintFactClaimsSupported({
    text: "你住台南，可以直接回答自己的生活圈。",
    field: "coaching",
    context: userContext,
  });

  assertHintFactClaimsSupported({
    text: "她願意分享自己住台南。",
    field: "coaching",
    context: partnerContext,
  });
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "她願意分享自己住高雄。",
        field: "coaching",
        context: partnerContext,
      }),
    Error,
    ERROR,
  );
});

Deno.test("typed Hint fact ledger preserves empathy, questions, proposals, and owned facts", () => {
  const partnerContext = buildHintFactContext({
    turns: [{ role: "ai", text: "我養了兩隻貓，今天終於交完專案。" }],
  });
  for (
    const reply of [
      "我也替妳開心，專案終於交完可以喘了。",
      "我也跟著開心，妳終於交完了。",
      "我也被妳家兩隻貓可愛到。",
      "我也想聽妳多講一點。",
      "妳家是不是也有兩隻貓？",
      "如果我也養兩隻貓就太巧了。",
      "我先確認自己的狀況再回妳。",
    ]
  ) {
    assertHintFactClaimsSupported({
      text: reply,
      field: "reply",
      context: partnerContext,
    });
  }

  const sharedContext = buildHintFactContext({
    turns: [
      { role: "user", text: "我30歲，也養了兩隻貓，住臺南。" },
      { role: "ai", text: "我也30歲，也養了兩隻貓，也住台南。" },
    ],
  });
  for (
    const reply of [
      "我差不多30歲。",
      "兩隻貓我家真的有。",
      "台南是我現在住的地方。",
      "原來我們都30歲，也都養兩隻貓。",
    ]
  ) {
    assertHintFactClaimsSupported({
      text: reply,
      field: "reply",
      context: sharedContext,
    });
  }
});

Deno.test("typed Hint fact extractor preserves actor, domain, relation, and anchor", () => {
  const claims = extractHintFactClaims({
    text: "台南也是我家鄉，我念的也是台大，兩隻貓我家也有。",
    perspective: "reply",
    provenance: "generated_reply",
    defaultOwner: "unknown",
  });
  assertEquals(
    claims.map((claim) => [
      claim.owner,
      claim.domain,
      claim.relation,
      claim.anchor,
      claim.quantity ?? null,
    ]),
    [
      ["user", "residence", "hometown_is", "台南", null],
      ["user", "school", "attended_school", "台大", null],
      ["user", "pet", "has_pet", "貓", 2],
    ],
  );
});

Deno.test("typed Hint fact ledger rejects natural paraphrases, schedule reversals, and contact impersonation", () => {
  const cases = [
    ["我住台南。", "我也是台南人，妳呢？"],
    ["我住台南。", "我也來自台南，這也太巧。"],
    ["我住台南。", "我的生活圈就在台南，妳最常去哪？"],
    ["我住台南。", "我目前也以台南為基地。"],
    ["我最愛壽司。", "我也是壽司控，妳最常點什麼？"],
    ["我明天七點有空。", "我明天七點沒空，不然改八點？"],
    ["我明天七點有空。", "我明天七點已經有約了，妳八點可以嗎？"],
    ["我的 LINE ID 是 alice123。", "加我 alice123，晚點聊。"],
    ["我的 LINE ID 是 alice123。", "搜尋 alice123 就找到我。"],
    ["我的 LINE ID 是 alice123。", "我用 alice123，直接丟訊息。"],
  ] as const;

  for (const [partner, output] of cases) {
    const context = buildHintFactContext({
      turns: [{ role: "ai", text: partner }],
    });
    assertThrows(
      () =>
        assertHintFactClaimsSupported({
          text: output,
          field: "reply",
          context,
        }),
      Error,
      ERROR,
      `partner=${partner} output=${output}`,
    );
  }
});

Deno.test("typed Hint fact ledger understands quotes, counterexamples, and natural jokes", () => {
  const context = buildHintFactContext({
    turns: [
      { role: "user", text: "我家住著兩隻貓。" },
      { role: "ai", text: "我住台南，明天七點有空，也養兩隻貓。" },
    ],
  });
  for (
    const coaching of [
      "她說：『我住台南』，先承接她的生活圈。",
      "她說：『我明天七點有空』，可以先確認地點。",
      "不要回『我也養兩隻貓』，那是亂補共同點。",
    ]
  ) {
    assertHintFactClaimsSupported({
      text: coaching,
      field: "coaching",
      context,
    });
  }
  assertHintFactClaimsSupported({
    text: "我叫妳別鬧，妳還真的鬧。",
    field: "reply",
    context,
  });
});

Deno.test("typed profile claims preserve the full profession and name without reparsing", () => {
  const profile = resolvePracticeProfile({ profileId: "practice_girl_001" });
  const context = buildHintFactContext({
    trustedFactClaims: partnerFactClaimsFromProfile(profile),
  });
  assertHintFactClaimsSupported({
    text: `她叫 ${profile.girl.displayName}，先接她的原話。`,
    field: "coaching",
    context,
  });
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: `我也是${profile.girl.professionLabel}，這也太巧。`,
        field: "reply",
        context,
      }),
    Error,
    ERROR,
  );
});

Deno.test("typed fact ledger supports a Debrief-specific error code", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "我住台南。" }],
  });
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "我也是台南人。",
        field: "reply",
        context,
        errorCode: "debrief_quality_invalid_unsupported_detail",
      }),
    Error,
    "debrief_quality_invalid_unsupported_detail",
  );
});

Deno.test("typed Hint fact ledger resolves the actor nearest the predicate", () => {
  const outputs = [
    "妳看我也三十歲，養生梗成立。",
    "妳看我這邊明天七點也有空，咖啡可以。",
    "妳可以加我的 LINE alice123，晚點聊。",
  ];
  const extracted = outputs.flatMap((text) =>
    extractHintFactClaims({
      text,
      perspective: "reply",
      provenance: "generated_reply",
      defaultOwner: "user",
    })
  );
  for (const domain of ["age", "schedule", "social"] as const) {
    const claims = extracted.filter((claim) => claim.domain === domain);
    assertEquals(claims.length > 0, true, domain);
    assertEquals(
      claims.every((claim) => claim.owner === "user"),
      true,
      `${domain}: ${JSON.stringify(claims)}`,
    );
  }
  assertEquals(
    extracted.some((claim) => claim.domain === "age" && claim.anchor === "30"),
    true,
  );
  assertEquals(
    extracted.some((claim) =>
      claim.domain === "schedule" && claim.anchor === "明天7點"
    ),
    true,
  );

  const partnerContext = buildHintFactContext({
    turns: [{
      role: "ai",
      text: "我30歲，明天7點有空，我的 LINE ID 是 alice123。",
    }],
  });
  for (const output of outputs) {
    assertThrows(
      () =>
        assertHintFactClaimsSupported({
          text: output,
          field: "reply",
          context: partnerContext,
        }),
      Error,
      ERROR,
      output,
    );
  }

  const userContext = buildHintFactContext({
    turns: [
      {
        role: "user",
        text: "我三十歲，明天七點有空，我的 LINE ID 是 alice123。",
      },
      { role: "ai", text: "好，妳繼續說。" },
    ],
  });
  for (const output of outputs) {
    assertHintFactClaimsSupported({
      text: output,
      field: "reply",
      context: userContext,
    });
  }
});

Deno.test("typed Hint fact ledger separates an assertion from a trailing follow-up question", () => {
  for (
    const [partner, output] of [
      ["我住台南。", "我也住台南妳呢？"],
      ["我是社工。", "我也是社工妳呢？"],
      ["我三十歲。", "我也三十歲妳呢？"],
      ["我養兩隻貓。", "我也養兩隻貓妳呢？"],
    ] as const
  ) {
    const context = buildHintFactContext({
      turns: [{ role: "ai", text: partner }],
    });
    assertThrows(
      () =>
        assertHintFactClaimsSupported({
          text: output,
          field: "reply",
          context,
        }),
      Error,
      ERROR,
      output,
    );
  }

  assertHintFactClaimsSupported({
    text: "妳也住台南嗎？",
    field: "reply",
    context: buildHintFactContext({ turns: [] }),
  });
});

Deno.test("typed Hint fact ledger rejects commonality and coreference transfers", () => {
  const partnerTransfers = [
    ["我叫阿哲。", "原來我們同名，阿哲這名字很有默契。"],
    ["我三十歲。", "原來我們同年，養生話題有共鳴了。"],
    ["我讀台大。", "台大同校學妹欸，世界真小。"],
    ["我是社工。", "社工同行欸，最近案量真的硬。"],
    ["我住台南，生活圈很固定。", "原來我們是同鄉，生活圈這題很有共鳴。"],
    ["我養兩隻貓。", "兩隻貓奴同盟成立，先說最皮的那隻。"],
    ["我最愛壽司。", "壽司同好加一，妳最常點什麼？"],
    ["我有一個妹妹。", "原來都有手足，這種吐槽我懂。"],
    ["我去年見過阿哲。", "原來那次我們都在場，阿哲這圈真小。"],
    ["我現在在中山站。", "原來我們就在附近，中山站這邊好碰。"],
    ["我明天七點有空。", "明天7點那個時段我也行，咖啡可以。"],
    ["我的 LINE ID 是 alice123。", "LINE 同一串，我這邊也收得到。"],
  ] as const;
  for (const [partner, output] of partnerTransfers) {
    const context = buildHintFactContext({
      turns: [{ role: "ai", text: partner }],
    });
    assertThrows(
      () =>
        assertHintFactClaimsSupported({
          text: output,
          field: "reply",
          context,
        }),
      Error,
      ERROR,
      `partner=${partner} output=${output}`,
    );
  }

  for (
    const [user, partnerQuestion, output] of [
      ["我叫阿哲。", "你也叫阿哲喔？", "原來我們同名，世界真小。"],
      ["我三十歲。", "你也三十歲喔？", "原來我們同年，養生梗成立。"],
      ["我讀台大。", "你也是台大喔？", "台大同校欸，世界真小。"],
      ["我是社工。", "你也是社工喔？", "社工同行欸，最近案量真的硬。"],
    ] as const
  ) {
    const context = buildHintFactContext({
      turns: [
        { role: "user", text: user },
        { role: "ai", text: partnerQuestion },
      ],
    });
    assertThrows(
      () =>
        assertHintFactClaimsSupported({
          text: output,
          field: "reply",
          context,
        }),
      Error,
      ERROR,
      output,
    );
  }
});

Deno.test("typed Hint fact ledger permits commonality only when both owners have evidence", () => {
  const sharedCases = [
    ["我叫阿哲。", "我也叫阿哲。", "原來我們同名。"],
    ["我三十歲。", "我也三十歲。", "原來我們同年。"],
    ["我讀台大。", "我也讀台大。", "原來我們同校。"],
    ["我是社工。", "我也是社工。", "原來我們是同行。"],
    ["我住台南。", "我也住台南。", "原來我們是同鄉。"],
    ["我養兩隻貓。", "我也養兩隻貓。", "貓奴同盟成立。"],
  ] as const;
  for (const [user, partner, output] of sharedCases) {
    assertHintFactClaimsSupported({
      text: output,
      field: "reply",
      context: buildHintFactContext({
        turns: [
          { role: "user", text: user },
          { role: "ai", text: partner },
        ],
      }),
    });
  }

  const sameAgeContext = buildHintFactContext({
    turns: [
      { role: "user", text: "我三十歲。" },
      { role: "ai", text: "我也三十歲。" },
    ],
  });
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "我們不是同年。",
        field: "reply",
        context: sameAgeContext,
      }),
    Error,
    ERROR,
  );
});

Deno.test("typed Hint fact ledger does not confuse travelling together with the same profession", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "我是社工，週末想去看展。" }],
  });
  for (const output of ["我們同行去看展。", "我們同行去咖啡店。"] as const) {
    assertHintFactClaimsSupported({
      text: output,
      field: "reply",
      context,
    });
  }
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "原來我們是同業，最近案量都很硬。",
        field: "reply",
        context,
      }),
    Error,
    ERROR,
  );
});

Deno.test("typed Hint fact ledger keeps third-party and media 同-word phrases natural", () => {
  const context = buildHintFactContext({
    turns: [{
      role: "ai",
      text: "我叫阿哲，三十歲，讀台大，住台南，也喜歡攝影。",
    }],
  });
  for (
    const output of [
      "這張同名專輯很好聽。",
      "那部片同年上映。",
      "她跟同校同學去看展。",
      "她跟同鄉去吃飯。",
      "她跟攝影同好去看展。",
    ] as const
  ) {
    assertHintFactClaimsSupported({
      text: output,
      field: "reply",
      context,
    });
  }
});

Deno.test("typed profile claims include real interests and lifestyle facts", () => {
  const profile = resolvePracticeProfile({ profileId: "practice_girl_065" });
  const claims = partnerFactClaimsFromProfile(profile);
  for (const interest of profile.girl.interestTags) {
    assertEquals(
      claims.some((claim) =>
        claim.domain === "preference" &&
        claim.anchor === interest.toLowerCase()
      ),
      true,
      interest,
    );
  }
  for (const lifestyle of profile.girl.lifestyleTags) {
    assertEquals(
      claims.some((claim) =>
        claim.domain === "lifestyle" &&
        claim.anchor === lifestyle.toLowerCase()
      ),
      true,
      lifestyle,
    );
  }

  const context = buildHintFactContext({ trustedFactClaims: claims });
  for (const output of ["我也喜歡夜景。", "我也常跑活動。"] as const) {
    assertThrows(
      () =>
        assertHintFactClaimsSupported({
          text: output,
          field: "reply",
          context,
        }),
      Error,
      ERROR,
      output,
    );
  }
  const userConfirmedContext = buildHintFactContext({
    trustedFactClaims: claims,
    turns: [{ role: "user", text: "我平常也跑活動。" }],
  });
  assertHintFactClaimsSupported({
    text: "我也常跑活動。",
    field: "reply",
    context: userConfirmedContext,
  });
  assertHintFactClaimsSupported({
    text: "我喜歡妳這個反應。",
    field: "reply",
    context: buildHintFactContext({ turns: [] }),
  });
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "我喜歡爵士樂。",
        field: "reply",
        context: buildHintFactContext({ turns: [] }),
      }),
    Error,
    ERROR,
  );
});

Deno.test("typed Hint fact ledger preserves negated advice and latest-partner quotes", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "我住台南。" }],
  });
  for (
    const coaching of [
      "不是要你回「我也住台南」，重點是承接她。",
      "原話「我住台南」可以回呼，不要冒認。",
      "她說自己住台南，只承接她的生活圈，不替使用者冒認同城。",
    ]
  ) {
    assertHintFactClaimsSupported({
      text: coaching,
      field: "coaching",
      context,
    });
  }

  assertHintFactClaimsSupported({
    text: "妳覺得爬山療癒，我也想聽妳最喜歡的地方。",
    field: "reply",
    context: buildHintFactContext({
      turns: [{ role: "ai", text: "我覺得爬山超療癒，你呢？" }],
    }),
  });
});

Deno.test("typed Hint fact ledger does not parse 台南同鄉 as a venue", () => {
  const claims = extractHintFactClaims({
    text: "台南同鄉欸，世界真小。",
    perspective: "reply",
    provenance: "generated_reply",
    defaultOwner: "user",
  });
  assertEquals(claims.some((claim) => claim.domain === "venue"), false);
});

Deno.test("typed Hint fact ledger scopes residence polarity and analytical suffixes", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "我住台南。" }],
  });
  for (
    const coaching of [
      "她主動說住台南，目前只有地點話題還沒有投入。",
      "有接到她住台南的具體素材。",
    ]
  ) {
    assertHintFactClaimsSupported({
      text: coaching,
      field: "coaching",
      context,
    });
  }

  const positive = extractHintFactClaims({
    text: "她主動說住台南，目前只有地點話題還沒有投入。",
    perspective: "coaching",
    provenance: "generated_coaching",
  });
  assertEquals(
    positive.some((claim) =>
      claim.domain === "residence" && claim.anchor === "台南" &&
      claim.polarity === "positive"
    ),
    true,
  );
  const negative = extractHintFactClaims({
    text: "她沒有住台南。",
    perspective: "coaching",
    provenance: "generated_coaching",
  });
  assertEquals(
    negative.some((claim) =>
      claim.domain === "residence" && claim.anchor === "台南" &&
      claim.polarity === "negative"
    ),
    true,
  );
});

Deno.test("typed Hint fact ledger keeps coaching prose outside venue anchors", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "我最近比較想去象山看夜景。" }],
  });
  for (
    const coaching of [
      "你先問她週末會不會爬山，讓她說出象山夜景這個方向。",
      "下一步要接住象山夜景。",
    ]
  ) {
    assertHintFactClaimsSupported({
      text: coaching,
      field: "coaching",
      context,
    });
    const claims = extractHintFactClaims({
      text: coaching,
      perspective: "coaching",
      provenance: "generated_coaching",
    }).filter((claim) => claim.domain === "venue");
    assertEquals(claims.every((claim) => claim.anchor === "象山"), true);
  }

  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "下一步要接住陽明山夜景。",
        field: "coaching",
        context,
      }),
    Error,
    ERROR,
  );
});

Deno.test("typed Hint fact ledger ignores Game phase prose around real places", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "我住台南，最常在中西區活動。" }],
  });
  for (
    const coaching of [
      "開場仍在台南中西區生活資訊交換",
      "只停在台南中西區資訊交換",
    ]
  ) {
    assertHintFactClaimsSupported({
      text: coaching,
      field: "coaching",
      context,
    });
    const claims = extractHintFactClaims({
      text: coaching,
      perspective: "coaching",
      provenance: "generated_coaching",
    });
    assertEquals(claims.some((claim) => claim.domain === "venue"), false);
  }

  const factual = extractHintFactClaims({
    text: "她常在中西區活動。",
    perspective: "coaching",
    provenance: "generated_coaching",
  });
  assertEquals(
    factual.some((claim) =>
      claim.domain === "venue" && claim.anchor === "中西區"
    ),
    true,
  );
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "下一步要接住陽明山夜景。",
        field: "coaching",
        context,
      }),
    Error,
    ERROR,
  );
});
