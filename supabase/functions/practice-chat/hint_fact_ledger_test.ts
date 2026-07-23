import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  assertHintFactClaimsSupported,
  buildHintFactContext,
  claimConfidence,
  collectUnsupportedHintFactClaims,
  extractHintFactClaims,
  type HintFactClaim,
  isLikelyProperPlaceAnchor,
  partnerFactClaimsFromProfile,
  stripUnsupportedThirdPartyDetails,
} from "./hint_fact_ledger.ts";
import { resolvePracticeProfile } from "./practice_persona.ts";
import type { PracticeTurn } from "./validate.ts";

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
    // 「我明天七點有空」型 user 自身 schedule 已依 Eric 裁決（2026-07-23）
    // 放行：第一人稱邀約提案語是合法邀約教學，見下方 proposals 測試。
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
      // Eric 裁決（2026-07-23）：第一人稱邀約提案語＝合法邀約教學，
      // user 自身 schedule 不 fail-closed。
      "我週三晚上有空，要不要一起去看？",
      "明天七點我這邊也排得開。",
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
    // 「我明天七點沒空，不然改八點？」型 user 自身 schedule 已依 Eric 裁決
    // （2026-07-23）放行：改約提案是合法邀約教學。
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
    // user 自身 schedule 依 Eric 裁決（2026-07-23）放行：邀約提案語不 fail-closed。
    if (/有空，咖啡可以/u.test(output)) {
      assertHintFactClaimsSupported({
        text: output,
        field: "reply",
        context: partnerContext,
      });
      continue;
    }
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
    // 「明天7點那個時段我也行」型 user 自身 schedule 已依 Eric 裁決
    // （2026-07-23）放行：跟上她的時段提案是合法邀約教學。
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

Deno.test("typed Hint fact ledger carries only evidenced relative shop locations", () => {
  for (
    const [source, output] of [
      [
        "我今天路過公司附近一家聞起來很香的店。",
        "妳問在哪，就是公司附近那間啦。",
      ],
      [
        "我今天路過學校附近一家聞起來很香的店。",
        "妳問在哪，就是學校附近那間啦。",
      ],
      [
        "我今天路過轉角那間聞起來很香的店。",
        "妳問在哪，就是轉角那間啦。",
      ],
      [
        "我今天路過那附近一家聞起來很香的店。",
        "妳問在哪，就是那附近那間啦。",
      ],
    ] as const
  ) {
    assertHintFactClaimsSupported({
      text: output,
      field: "reply",
      context: buildHintFactContext({
        turns: [
          { role: "user", text: source },
          { role: "ai", text: "哪裡啊？" },
        ],
      }),
    });
  }

  const missingContext = buildHintFactContext({
    turns: [
      { role: "user", text: "我今天路過一家聞起來很香的店。" },
      { role: "ai", text: "哪裡啊？" },
    ],
  });
  for (
    const output of [
      "妳問在哪，就是公司附近那間啦。",
      "妳問在哪，就是學校附近那間啦。",
      "妳問在哪，就是轉角那間啦。",
      "妳問在哪，就是那附近那間啦。",
      "不是公司旁邊啦。",
    ]
  ) {
    assertThrows(
      () =>
        assertHintFactClaimsSupported({
          text: output,
          field: "reply",
          context: missingContext,
        }),
      Error,
      ERROR,
    );
  }
});

Deno.test("typed Hint fact ledger treats coaching warnings and conditions as non-assertive", () => {
  const context = buildHintFactContext({
    turns: [
      { role: "user", text: "我今天路過一家聞起來很香的店。" },
      { role: "ai", text: "哪裡啊？" },
    ],
  });
  for (
    const coaching of [
      "她問店在哪，你應該先說不記得，不要亂補附近。",
      "她在追問位置；你沒有說公司旁邊，別補這個細節。",
      "如果在附近，可以順勢問她要不要踩點。",
      "假如是公司旁邊，再接上班路線。",
      "若在附近，再看她要不要去。",
      "可能在附近，但你其實不知道。",
      "也許在公司旁邊，但不能亂猜。",
      "或許在轉角，但逐字稿沒有證據。",
    ]
  ) {
    assertHintFactClaimsSupported({
      text: coaching,
      field: "coaching",
      context,
    });
  }

  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "她問店在哪，答案就是公司旁邊。",
        field: "coaching",
        context,
      }),
    Error,
    ERROR,
  );
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

// ── 2026-07-13 game hint 503 回歸：分層信心捏造守門 ──────────────────────────
// probe 實錄（scratchpad hint-gate-probe/out.json）：忠實回呼對方原句的輸出被
// venue/third_party 字尾 regex 抽成「捏造事實」而殺。新設計：只有高信心
// （聯絡方式／帶引介語境的人名／具專名形態且輸入找不到出處的地名）才 fail-closed。

const PROBE_S1_TURNS: PracticeTurn[] = [
  { role: "user", text: "今天過得如何？該不會又被會議追殺吧" },
  { role: "ai", text: "被你說中，剛開完第三個會，腦袋已經當機了" },
  { role: "user", text: "哈哈那妳現在需要的是充電還是放電" },
  { role: "ai", text: "充電吧，我現在只想躺著耍廢看劇" },
  { role: "user", text: "看劇充電派的喔，我以為妳會說要出去跑步" },
  { role: "ai", text: "跑步？你把我想得太勵志了吧😂 我頂多從沙發走到冰箱" },
];

const PROBE_S2_TURNS: PracticeTurn[] = [
  { role: "user", text: "妳週末都在幹嘛，感覺妳是行程排滿的那種人" },
  {
    role: "ai",
    text: "哪有，我週末最大的行程是睡到自然醒，然後找間咖啡廳坐一下午",
  },
  { role: "user", text: "咖啡廳坐一下午是在看書還是純發呆" },
  { role: "ai", text: "都有，不過最近迷上手沖，開始會挑豆子了" },
  { role: "user", text: "喔？那妳算是入坑了，最喜歡哪個產區的" },
  { role: "ai", text: "衣索比亞的耶加雪菲吧，果酸很明顯我很愛" },
  { role: "user", text: "品味不錯嘛，我家附近剛好有一間自家烘焙的店" },
  { role: "ai", text: "你該不會是要順勢約我吧？也太快了吧哈哈" },
];

const PROBE_S3_TURNS: PracticeTurn[] = [
  { role: "user", text: "妳笑起來應該很好看，頭貼就看得出來" },
  { role: "ai", text: "這句話你是不是對每個女生都講過一遍" },
  { role: "user", text: "冤枉，我平均三個月才講一次，妳是本季額度" },
  { role: "ai", text: "哦？講得跟真的一樣，那我要看證據" },
  { role: "user", text: "證據就是我現在還在這裡跟妳聊，沒有跑去跟別人講" },
  { role: "ai", text: "好啦勉強及格，不過先警告你，我對嘴甜的男生免疫" },
];

const PROBE_PROFILE_CLAIMS = partnerFactClaimsFromProfile(
  resolvePracticeProfile({
    difficulty: "normal",
    profileId: "practice_girl_004",
  }),
);

function probeContext(turns: PracticeTurn[]) {
  return buildHintFactContext({
    turns,
    trustedFactClaims: PROBE_PROFILE_CLAIMS,
  });
}

const PROBE_FALSE_KILL_CASES: ReadonlyArray<{
  turns: PracticeTurn[];
  field: "reply" | "coaching";
  text: string;
}> = [
  {
    turns: PROBE_S1_TURNS,
    field: "reply",
    text:
      "從沙發到冰箱這段路我懂，還會在冰箱前站五分鐘假裝在思考人生😂 妳冰箱裡現在有什麼好料？",
  },
  {
    turns: PROBE_S1_TURNS,
    field: "reply",
    text:
      "沙發到冰箱這段路我懂，還會在冰箱前站三分鐘假裝在選，其實只是不想動😂 妳冰箱裡現在有什麼救命食物？",
  },
  {
    turns: PROBE_S1_TURNS,
    field: "reply",
    text: "從沙發到冰箱這段路，我猜妳已經來回好幾趟了😂 冰箱裡有什麼戰利品？",
  },
  {
    turns: PROBE_S1_TURNS,
    field: "reply",
    text: "從沙發到冰箱這段路我懂，那叫做「精準移動」😂 冰箱裡有什麼戰利品？",
  },
  {
    turns: PROBE_S1_TURNS,
    field: "reply",
    text:
      "從沙發到冰箱這段路我懂，那叫「精準移動」，不浪費能量😂 妳冰箱裡現在有什麼好料？",
  },
  {
    turns: PROBE_S1_TURNS,
    field: "reply",
    text:
      "那我該慶幸妳至少還有冰箱這段路，不然真的會餓死😂 我們是同一國的，沙發萬歲。",
  },
  {
    turns: PROBE_S1_TURNS,
    field: "coaching",
    text:
      "Game 心法：她這句可能是在用自嘲梗測你能不能接住、一起玩，不是真的要你給建議。現在是 P1 建立熟悉感，任務是讓她覺得你懂她的生活感、聊起來輕鬆。升溫版接她的「沙發到冰箱」梗再補一個自己的生活小畫面，然後丟一顆低壓的球讓她繼續說；穩住版就純接梗共鳴，不扣分。速約任務：這輪在鋪墊階，先把熟悉感建起來，不約。",
  },
  {
    turns: PROBE_S1_TURNS,
    field: "coaching",
    text:
      "Game 心法：她這句可能是在用自嘲測你接不接得住梗、會不會笑她。現在是 P1 建立熟悉感，她剛用「沙發到冰箱」這個具體畫面給了你素材，任務是接住這個梗再給她一顆好接的球，讓她多說一點生活細節。速約任務：這輪在鋪墊階，不約，先把她的耍廢習慣聊開，累積共同話題。",
  },
  {
    turns: PROBE_S2_TURNS,
    field: "coaching",
    text:
      "Game 心法：她這句可能是在測你夠不夠穩、被戳穿會不會慌。現在是輕推曖昧階段，她主動點破邀約，代表她有意識到但還在觀望。任務是先接住這個吐槽、不防禦，再用耶加雪菲這個她自己說的梗把邀約包進去，讓她覺得是自然延伸而非硬追。速約任務：本輪在低壓試探邀約階，用「改天去聞聞那家豆子」丟出模糊窗口，不逼她回應，保留退路。",
  },
  {
    turns: PROBE_S2_TURNS,
    field: "coaching",
    text:
      "Game 心法：她這句可能是在測你會不會慌張解釋或硬追。現在是輕推曖昧階段，她已經主動點破邀約意圖，代表她有意識到、也沒有排斥。升溫版先承認一小部分、再用耶加雪菲做幽默轉移，把邀約變成「品味合不合」的低壓框架；穩住版輕鬆反打讓她覺得是她想太多，降低壓力。速約任務：這輪在低壓試探邀約階，用「確認合不合拍」代替直接約，保留退路，下一輪再把窗口收成短咖啡。",
  },
  {
    turns: PROBE_S3_TURNS,
    field: "coaching",
    text:
      "Game 心法：她這句可能是在丟小測試——用『免疫』推開，看你會不會慌著自證或繼續猛誇。現在是 P1 建立熟悉，主要任務是讓她覺得你接得住梗、不無聊。warmUp 用她的『免疫』反打，暗示她其實有反應，幽默不防禦；steady 更輕，直接把球丟回她。兩句都不解釋、不自證，短而穩。速約任務：本輪在鋪墊階，先過這個小測試，累積她對你的好奇，還不到丟窗口的時機。",
  },
  {
    turns: PROBE_S3_TURNS,
    field: "coaching",
    text:
      "Game 心法：她這句是典型『免疫嘴甜』測試，要看你能不能接梗轉向。目前建立熟悉階段，任務是接住她給的框架（免疫），用自嘲或換路線過關，不要繼續硬攻。速約任務：先鋪墊安全感，不約，等她願聊咖啡細節再開窗口。",
  },
  {
    turns: PROBE_S3_TURNS,
    field: "coaching",
    text:
      "Game心法：她這句是在丟小測試，先接受及格再設邊界免疫嘴甜。目前階段P1建立熟悉，任務是接住她的警告，轉向真實互動或生活樣本，不硬推張力。速約任務：這輪先鋪墊，把她的咖啡師身份變成可兌現的小場景，但低壓不約。",
  },
];

Deno.test("typed Hint fact gate keeps grounded game-hint echoes alive (2026-07-13 probe corpus)", () => {
  for (const testCase of PROBE_FALSE_KILL_CASES) {
    assertHintFactClaimsSupported({
      text: testCase.text,
      field: testCase.field,
      context: probeContext(testCase.turns),
    });
  }
});

Deno.test("typed Hint fact extractor never emits high-confidence claims for probe false-kill anchors", () => {
  for (const testCase of PROBE_FALSE_KILL_CASES) {
    const risky = extractHintFactClaims({
      text: testCase.text,
      perspective: testCase.field,
      provenance: testCase.field === "coaching"
        ? "generated_coaching"
        : "generated_reply",
      defaultOwner: testCase.field === "coaching" ? "unknown" : "user",
    }).filter((claim) =>
      (claim.domain === "venue" ||
        (claim.owner === "third_party" && claim.domain === "name")) &&
      (claim.confidence ?? "high") === "high"
    );
    assertEquals(
      risky,
      [],
      `${testCase.field}: ${testCase.text.slice(0, 24)}`,
    );
  }
});

Deno.test("typed venue morphology separates proper place names from prose fragments", () => {
  for (
    const proper of ["台北車站", "信義區", "陽明山", "士林夜市", "台北101"]
  ) {
    assertEquals(isLikelyProperPlaceAnchor(proper), true, proper);
  }
  for (
    const prose of [
      "冰箱前站", // stem 以方位詞結尾
      "冰箱這段路", // 指示詞＋量詞
      "從沙發到冰箱這段路",
      "保留退路", // 抽象複合詞
      "用自嘲或換路", // 功能詞黏連
      "象山", // 單字 stem 資訊量不足，寧可放行
      "路", // 無 stem
    ]
  ) {
    assertEquals(isLikelyProperPlaceAnchor(prose), false, prose);
  }
});

Deno.test("typed venue extraction downgrades prose anchors to low confidence but keeps proper names high", () => {
  const confidences = (text: string): Array<[string, string]> =>
    extractHintFactClaims({
      text,
      perspective: "reply",
      provenance: "generated_reply",
      defaultOwner: "user",
    }).filter((claim) => claim.domain === "venue").map((
      claim,
    ) => [claim.anchor, claim.confidence ?? "high"]);

  const proper = confidences("我們約在台北車站見面。");
  assertEquals(proper.length > 0, true);
  assertEquals(proper.every(([, confidence]) => confidence === "high"), true);

  for (
    const prose of [
      "從沙發到冰箱這段路我懂，還會在冰箱前站五分鐘。",
      "先接住吐槽，保留退路。",
    ]
  ) {
    assertEquals(
      confidences(prose).every(([, confidence]) => confidence === "low"),
      true,
      prose,
    );
  }
});

Deno.test("typed third-party name extraction requires introduction context for high confidence", () => {
  const thirdPartyNames = (text: string): HintFactClaim[] =>
    extractHintFactClaims({
      text,
      perspective: "coaching",
      provenance: "generated_coaching",
      defaultOwner: "unknown",
    }).filter((claim) =>
      claim.owner === "third_party" && claim.domain === "name"
    );

  for (
    const intro of ["我朋友阿凱也想去那間店。", "那個人叫阿凱，人還不錯。"]
  ) {
    const claims = thirdPartyNames(intro);
    assertEquals(
      claims.some((claim) =>
        claim.anchor === "阿凱" && (claim.confidence ?? "high") === "high"
      ),
      true,
      intro,
    );
  }

  for (
    const prose of [
      "steady 更輕，直接把球丟回她。",
      "我們是同一國的，沙發萬歲。",
      "她這句是在丟小測試，先穩住。",
      "不是真的要你給建議。",
    ]
  ) {
    assertEquals(
      thirdPartyNames(prose).every((claim) =>
        (claim.confidence ?? "high") === "low"
      ),
      true,
      prose,
    );
  }

  // 送收語境沒有引介語詞，但強人名形態（阿哲/阿凱）仍要 high——
  // 既有真陽性「傳給阿哲」不得放掉。
  const strong = thirdPartyNames("記得傳給阿凱，他會喜歡。");
  assertEquals(
    strong.some((claim) =>
      claim.anchor === "阿凱" && (claim.confidence ?? "high") === "high"
    ),
    true,
  );
});

// P0 對抗審：中文口語提朋友多半只講名不講姓（嘉玲/雅婷/淑芬…），這類一般
// 給定名不是暱稱/疊字/姓氏開頭，先前用 looksLikeStrongPersonName 判準全部
// 落 low，捏造的第三方人名在送收/同行語境永遠不 fail-closed。改用
// looksLikePersonReference 後，這些一般給定名在無出處時必須 throw。
Deno.test("typed third-party ordinary given names fail-closed in send/companion/receipt context without provenance", () => {
  const context = probeContext(PROBE_S1_TURNS);
  const fabricatedOrdinaryNames = [
    "我跟嘉玲一起去看電影。",
    "我傳給雅婷。",
    "淑芬收到照片了。",
    "我跟志明一起去吃飯。",
    "傳給家豪。",
    "怡君收到訊息了，說很喜歡。",
    "我跟佩珊一起去逛街。",
    "傳給冠宇。",
    "我跟詩婷一起去看展。",
    "傳給佳穎。",
  ];
  for (const text of fabricatedOrdinaryNames) {
    assertThrows(
      () => assertHintFactClaimsSupported({ text, field: "reply", context }),
      Error,
      ERROR,
      text,
    );
  }
});

// probe corpus 實錄的具體假陽性慣用語：長得像二至四字漢字但不是人名，
// 一般給定名判準放寬後仍不得誤抽成高信心第三方人名。
Deno.test("typed third-party name extraction keeps probe corpus idioms at low confidence after widening to ordinary names", () => {
  const thirdPartyNames = (text: string): HintFactClaim[] =>
    extractHintFactClaims({
      text,
      perspective: "coaching",
      provenance: "generated_coaching",
      defaultOwner: "unknown",
    }).filter((claim) =>
      claim.owner === "third_party" && claim.domain === "name"
    );

  for (
    const prose of [
      "steady 更輕，直接把球丟回她。",
      "我們是同一國的，沙發萬歲。",
      "她這句是在丟小測試，先穩住。",
      "不是真的要你給建議。",
      "這個具體畫面給了你素材，任務是接住這個梗。",
    ]
  ) {
    assertEquals(
      thirdPartyNames(prose).every((claim) =>
        (claim.confidence ?? "high") === "low"
      ),
      true,
      prose,
    );
  }
});

Deno.test("typed Hint fact gate still kills fabricated venues, third-party names, and contacts", () => {
  const context = probeContext(PROBE_S1_TURNS);
  const fabricated: ReadonlyArray<[string, "reply" | "coaching"]> = [
    ["我們可以約在台北車站見面。", "reply"],
    ["那間店叫貓下去，我們去過。", "reply"],
    ["我朋友阿凱說這家超好吃。", "reply"],
  ];
  for (const [text, field] of fabricated) {
    assertThrows(
      () => assertHintFactClaimsSupported({ text, field, context }),
      Error,
      ERROR,
      text,
    );
  }

  // 帶引介語境的新人名在 coaching 也要殺。
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "可以提到我朋友阿凱上次的做法。",
        field: "coaching",
        context,
      }),
    Error,
    ERROR,
  );
});

Deno.test("typed Hint fact gate passes when output entities all come from the inputs", () => {
  const stationContext = buildHintFactContext({
    turns: [
      { role: "user", text: "妳等等要去哪？" },
      { role: "ai", text: "我明天會去台北車站附近晃晃" },
    ],
  });
  assertHintFactClaimsSupported({
    text: "台北車站那邊人超多，妳習慣嗎？",
    field: "reply",
    context: stationContext,
  });

  // 實體級模糊比對：她只說過「貓空」，輸出「貓空站」是同一實體的改寫。
  const gondolaContext = buildHintFactContext({
    turns: [{ role: "ai", text: "我住貓空附近，纜車聲都聽習慣了" }],
  });
  assertHintFactClaimsSupported({
    text: "那改天貓空站見？",
    field: "reply",
    context: gondolaContext,
  });

  // 證據字串（非 turns）出現過的實體也算有出處。
  const evidenceContext = buildHintFactContext({
    turns: [{ role: "ai", text: "下班了，累爆" }],
    partnerFactualEvidence: ["她在信義區的咖啡店上班"],
  });
  assertHintFactClaimsSupported({
    text: "信義區下班時間人潮很猛，辛苦了。",
    field: "reply",
    context: evidenceContext,
  });
});

// P1 對抗審：asksPlace 新增的「在X(?=發現|找到|喝到…)」pattern 沒限定 X 是
// 地點名詞，會把「在聊天過程中發現」「在等你的時候」這種心情/動作句抓成
// venue candidate 誤殺。X 不具地點形態時必須落 low 放行，不確定就不殺。
Deno.test("typed asksPlace venue pattern does not misfire on narrative/state clauses", () => {
  const asksPlaceContext = buildHintFactContext({
    turns: [{ role: "ai", text: "你剛剛在哪啊" }],
  });

  // 心情/動作句：不是在報地點，即使跟在「在」後面也不能被殺。
  for (
    const text of [
      "我在聊天過程中發現妳超好聊。",
      "我在等你的時候看到一隻貓經過。",
      "我剛剛在心裡想著要怎麼回妳。",
    ]
  ) {
    assertHintFactClaimsSupported({
      text,
      field: "reply",
      context: asksPlaceContext,
    });
  }

  // 真回答地點：X 具地點形態（信義區）時仍要能抽出且視為有出處來源時通過，
  // 沒出處時仍要 fail-closed（正面對照組，鎖住 asksPlace 抽取能力沒被削弱）。
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "我在信義區那間店發現一家很讚的酒吧，改天帶妳去。",
        field: "reply",
        context: asksPlaceContext,
      }),
    Error,
    ERROR,
  );
});

Deno.test("collectUnsupportedHintFactClaims mirrors assert without throwing", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "最近好嗎？" }],
  });
  const unsupported = collectUnsupportedHintFactClaims({
    text: "我朋友阿凱說那家店很棒，一起去看看？",
    field: "reply",
    context,
  });
  assertEquals(
    unsupported.some((claim) =>
      claim.owner === "third_party" && claim.anchor === "阿凱"
    ),
    true,
  );
  // 已接地內容不得被收進未接地清單。
  const grounded = collectUnsupportedHintFactClaims({
    text: "你剛說在忙報告，先不打擾你？",
    field: "reply",
    context: buildHintFactContext({
      turns: [{ role: "ai", text: "我最近在忙報告" }],
    }),
  });
  assertEquals(
    grounded.some((claim) => claim.owner === "third_party"),
    false,
  );
});

Deno.test("stripUnsupportedThirdPartyDetails removes third-party clause and rejoins", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "週末想做什麼？" }],
  });
  const stripped = stripUnsupportedThirdPartyDetails({
    text: "我朋友阿凱說那家店很棒，一起去看看？",
    field: "reply",
    context,
  });
  assertEquals(stripped.includes("阿凱"), false);
  assertEquals(stripped.length > 0, true);
});

Deno.test("stripUnsupportedThirdPartyDetails never touches user or partner facts", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "最近好嗎？" }],
  });
  // partner-owned 未接地推測不屬第三方幻覺，安全底線交給 Change B，一律不 strip。
  const text = "先聊聊你平常喜歡的類型，再看要不要約。";
  const before = stripUnsupportedThirdPartyDetails({
    text,
    field: "reply",
    context,
  });
  assertEquals(before, text);
});

Deno.test("stripUnsupportedThirdPartyDetails returns empty when whole text is third-party detail (P1#4)", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "最近好嗎？" }],
  });
  // 整段就是被清光的第三方細節 → 回空字串，讓呼叫端當 salvage 失敗、維持 503。
  const out = stripUnsupportedThirdPartyDetails({
    text: "我朋友阿凱說那家店很棒。",
    field: "reply",
    context,
  });
  assertEquals(out, "");
});

Deno.test("stripUnsupportedThirdPartyDetails leaves no unsupported third-party residue (P1#3)", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "最近好嗎？" }],
  });
  const out = stripUnsupportedThirdPartyDetails({
    text: "我朋友阿凱說讚，我同事小美也推，一起吧？",
    field: "reply",
    context,
  });
  // 非空輸出必須已無第三方未接地殘留。
  if (out.length > 0) {
    const residual = collectUnsupportedHintFactClaims({
      text: out,
      field: "reply",
      context,
    }).filter((claim) =>
      claim.owner === "world" || claim.owner === "third_party"
    );
    assertEquals(residual.length, 0);
  }
});

// ── 2026-07-23 eval 第 4/5 輪判定表回歸包 ──────────────────────────────
// FP 樣本（曾被誤殺，必須放行）＋TP 樣本（真捏造，必須照擋）＋FN 補抓。

Deno.test("regression: 送收語境不再吃「給＋抽象詞」與詞中「發」（round4 #1/#3/#4/#7、round5 沙發/傳給妳）", () => {
  const context = buildHintFactContext({
    turns: [
      { role: "user", text: "我週末大多在家追劇配鹹酥雞。" },
      { role: "ai", text: "隔天鐵腿才發現爬山有多累哈哈。" },
    ],
  });
  for (
    const [field, text] of [
      ["coaching", "順著她的邏輯給認同，再輕輕開一個窗口。"],
      ["coaching", "給予認同，展現理解，先讓她安心。"],
      ["coaching", "先給接納感，用自我調侃拉近距離。"],
      ["reply", "妳怎麼發現的，是隔天鐵腿才知道嗎？"],
      ["reply", "我週末都窩在家裡沙發還是床上，看妳挑哪個吐槽。"],
      ["reply", "整理好照片週一傳給妳，先讓妳期待一下。"],
      ["coaching", "她開玩笑丟測試，接住再丟回她那邊就好。"],
    ] as const
  ) {
    assertHintFactClaimsSupported({ text, field, context });
  }
  // TP 對照：真名字送收語境照樣 fail-closed。
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "整理好照片我週一傳給嘉玲。",
        field: "reply",
        context,
      }),
    Error,
    ERROR,
  );
});

Deno.test("regression: 地名字尾不再詞中切割（區域/市集/街道），真地名照抽（round4 #23/#29、round5 gd5）", () => {
  const context = buildHintFactContext({
    turns: [
      { role: "user", text: "上次說的那間唱片行我還記得。" },
      { role: "ai", text: "唱片行在哪一區？" },
    ],
  });
  for (
    const text of [
      "哈哈區域不算太隱密啦，但我想留著當驚喜。",
      "這時候答區域反而洩氣，我想帶妳去才好玩。",
      "星期六下午市集門口見，妳先把時間留給我。",
      "順著她的話延伸出街道氛圍的畫面感。",
    ]
  ) {
    const claims = extractHintFactClaims({
      text,
      perspective: "reply",
      provenance: "generated_reply",
      defaultOwner: "user",
    });
    assertEquals(
      claims.filter((claim) =>
        claim.domain === "venue" &&
        (claim.confidence ?? "high") === "high"
      ).length,
      0,
      text,
    );
  }
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "就西門町那間啊，妳一定知道。",
        field: "reply",
        context,
      }),
    Error,
    ERROR,
  );
});

Deno.test("regression: 「能量」不再被抽成 schedule；「她今天能量沒那麼高」放行（round4 #2）", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "今天好累，回家只想躺著。" }],
  });
  assertHintFactClaimsSupported({
    text: "這句適合她今天能量沒那麼高時使用，先降成本。",
    field: "coaching",
    context,
  });
});

Deno.test("regression: schedule 粒度與極性——「這週六下午有空」支持「週六有空」，後綴否定不翻極性（round5 gd1）", () => {
  const context = buildHintFactContext({
    turns: [
      { role: "user", text: "那要不要找個時間看展？" },
      { role: "ai", text: "我這週六下午剛好有空喔。" },
    ],
  });
  for (
    const text of [
      "她主動說出週六下午有空，這是明確的邀約窗口。",
      "她說週六有空時，你沒有接住這個訊號。",
      "她說『這週六下午有空』後沒有立即確認時間，是可惜點。",
    ]
  ) {
    assertHintFactClaimsSupported({ text, field: "coaching", context });
  }
  // 對照：她沒說過的日子照擋。
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "她說下週三有空，直接約下週三。",
        field: "coaching",
        context,
      }),
    Error,
    ERROR,
  );
});

Deno.test("regression: 「敢跟我比吃辣的人」不再抽成籍貫 claim（round4 #18）", () => {
  const claims = extractHintFactClaims({
    text: "這句話我可是留給敢跟我比吃辣的人限定的。",
    perspective: "reply",
    provenance: "generated_reply",
    defaultOwner: "user",
  });
  assertEquals(
    claims.filter((claim) =>
      claim.domain === "residence" && (claim.confidence ?? "high") === "high"
    ).length,
    0,
  );
});

Deno.test("regression: 「我們幾點在展覽附近碰面」不再誤判同住 commonality（round5 gd1 #39）", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "那個展我也想看！" }],
  });
  assertHintFactClaimsSupported({
    text: "那我們幾點在展覽附近碰面？我先查好路線。",
    field: "reply",
    context,
  });
});

Deno.test("regression: 無主詞「養狗」附和句不再變 user 有狗（round5 bd5）", () => {
  const context = buildHintFactContext({
    turns: [
      { role: "ai", text: "自從養狗之後每天都被布丁逼著早起散步。" },
    ],
  });
  for (
    const [field, text] of [
      ["reply", "哈哈養狗之後回不去我信，布丁根本是鬧鐘。"],
      ["reply", "我也想試試被狗逼著早起的生活，一起走一圈？"],
    ] as const
  ) {
    assertHintFactClaimsSupported({ text, field, context });
  }
});

Deno.test("regression: 她問地點時 coaching 引號教學語不再變 venue claim（round4 #27/#30）", () => {
  const context = buildHintFactContext({
    turns: [
      { role: "user", text: "那間唱片行超有味道。" },
      { role: "ai", text: "唱片行在哪一區？" },
    ],
  });
  for (
    const text of [
      "Game 心法：她在問細節，先丟出「這週/半小時」的具體窗口再回答。",
      "Game 心法：用「一起去被推薦」的框架轉邀約，不用急著給答案。".replace(
        "框架",
        "方式",
      ),
      "Game 心法：老闆推薦卡黑膠味道都是她給過的線索，回呼即可。",
    ]
  ) {
    assertHintFactClaimsSupported({ text, field: "coaching", context });
  }
});

Deno.test("regression: 她問地點時「方位詞/交通耐受」直接報點＝捏造照擋（round4 FN #24/#28/#30）", () => {
  const context = buildHintFactContext({
    turns: [
      { role: "user", text: "那間唱片行超有味道。" },
      { role: "ai", text: "唱片行在哪一區？" },
    ],
  });
  for (
    const text of [
      "北邊，靠近捷運站，我下週可以帶妳去。",
      "南邊，騎車10分鐘左右就到。",
      "就在北邊，妳一定找得到。",
    ]
  ) {
    assertThrows(
      () => assertHintFactClaimsSupported({ text, field: "reply", context }),
      Error,
      ERROR,
      text,
    );
  }
  // 氛圍式回應與賣關子照 Eric 裁決放行。
  for (
    const text of [
      "其實我也還沒去過，要不要哪天一起去找？",
      "先保密，我帶路比較好玩。",
    ]
  ) {
    assertHintFactClaimsSupported({ text, field: "reply", context });
  }
});

Deno.test("regression: 「她喜歡的旅行/場景感」所有格指涉不再 fail-closed（round5 bd2/bd3/bd4）", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "放假就想到處走走。" }],
    partnerFactualEvidence: ["她喜歡旅行和美食。"],
  });
  for (
    const text of [
      "用她喜歡的旅行話題開場，比較不突兀。",
      "她喜歡的場景感可以拿來當下次的話題。",
    ]
  ) {
    assertHintFactClaimsSupported({ text, field: "coaching", context });
  }
});

Deno.test("round6: coaching 轉述「她問位置是X」不再變 venue claim（#10/#13）", () => {
  const context = buildHintFactContext({
    turns: [
      { role: "user", text: "那間店我週末想去。" },
      { role: "ai", text: "那間店位置在哪？" },
    ],
  });
  for (
    const text of [
      "她問位置是實際確認，不是拒絕，準備好資訊就能接住。",
      "她問位置是邀約信號，直接給具體資訊就對了。",
    ]
  ) {
    assertHintFactClaimsSupported({ text, field: "coaching", context });
  }
  // TP 回歸：coaching 真報點（地點形態）與 reply 嚴格模式照擋。
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "位置就是永康街那家，直接約。",
        field: "coaching",
        context,
      }),
    Error,
    ERROR,
  );
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "店名就是藍瓶咖啡，妳一定聽過。",
        field: "reply",
        context,
      }),
    Error,
    ERROR,
  );
});

Deno.test("round6: 她問在哪時「還沒實際去過」迴避句不再被當店名（#9 warmUp）", () => {
  const context = buildHintFactContext({
    turns: [
      { role: "user", text: "上次聽妳說的那間咖啡店。" },
      { role: "ai", text: "那間咖啡店在哪啊？" },
    ],
  });
  assertHintFactClaimsSupported({
    text: "我也是聽朋友提的，還沒實際去過欸。",
    field: "reply",
    context,
  });
  // TP 回歸：真報店名（語尾助詞形態）照擋。
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "藍瓶咖啡欸，妳應該知道。",
        field: "reply",
        context,
      }),
    Error,
    ERROR,
  );
});

Deno.test("round6: 地名字尾切割殘漏三型不再產生假 venue 錨點（#9/#12/#24）", () => {
  const highVenueAnchors = (text: string) =>
    extractHintFactClaims({
      text,
      perspective: "reply",
      provenance: "generated_reply",
      defaultOwner: "user",
    })
      .filter((claim) =>
        claim.domain === "venue" && claimConfidence(claim) === "high"
      )
      .map((claim) => claim.anchor);
  // 「說到區」動詞短語＋字尾、「帶路」複合詞、「巷口」切出「老地方巷」。
  assertEquals(highVenueAnchors("說到區我還真的答不上來。"), []);
  assertEquals(highVenueAnchors("不知道確切位置，但可以帶路。"), []);
  assertEquals(highVenueAnchors("那星期六下午三點，老地方巷口等妳。"), []);
  // TP 回歸：真地名字尾照收 high。
  assertEquals(
    highVenueAnchors("那家店在中山區。").includes("中山區"),
    true,
  );
  assertEquals(
    highVenueAnchors("就在永康街12巷。").includes("永康街12巷"),
    true,
  );
});

Deno.test("round6: 進行貌「她在＋動詞短語」不再誤判 current_location（#12）", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "好啦，地點你來想。" }],
  });
  assertHintFactClaimsSupported({
    text: "她在幫你把邀約鋪好路，接住這個節奏就好。",
    field: "coaching",
    context,
  });
  // TP 回歸：真「她在＋地名」照擋。
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "她現在在台北，直接約市區。",
        field: "coaching",
        context,
      }),
    Error,
    ERROR,
  );
});

Deno.test("round6: 裸「傳」語氣詞不再切出假人名（#3）", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "被你講到懷疑人生哈哈。" }],
  });
  for (
    const text of [
      "懷疑人生這三個字太傳神了哈哈，我收下這個評價。",
      "那句話直接傳瘋了哈哈，被笑一整天。",
    ]
  ) {
    assertHintFactClaimsSupported({ text, field: "reply", context });
  }
  // TP 回歸：真送收人名照擋。
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "這張我會傳阿哲，他一定笑翻。",
        field: "reply",
        context,
      }),
    Error,
    ERROR,
  );
});

Deno.test("round6: 第一人稱假設句「怕自己養狗」不再變 user 養寵事實（#14）", () => {
  const petConfidences = (text: string) =>
    extractHintFactClaims({
      text,
      perspective: "reply",
      provenance: "generated_reply",
      defaultOwner: "user",
    })
      .filter((claim) => claim.domain === "pet")
      .map((claim) => claimConfidence(claim));
  assertEquals(
    petConfidences("我超怕自己養狗會被牽著跑，妳都怎麼訓練布丁聽話的？"),
    ["low"],
  );
  // TP 回歸：真自陳養寵照樣 high。
  assertEquals(petConfidences("我養了一隻狗，每天被牠鬧醒。"), ["high"]);

  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "我養了一隻狗叫布丁。" }],
  });
  assertHintFactClaimsSupported({
    text: "我超怕自己養狗會被牽著跑，妳都怎麼訓練布丁聽話的？",
    field: "reply",
    context,
  });
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "我家也養了一隻狗，改天讓牠們見面。",
        field: "reply",
        context,
      }),
    Error,
    ERROR,
  );
});

Deno.test("round6: 「問她能不能配合」疑問補語不再變 schedule 事實（#17）", () => {
  const context = buildHintFactContext({
    turns: [{ role: "ai", text: "週間比較好排喔。" }],
  });
  assertHintFactClaimsSupported({
    text: "先提一個具體的日期或時段（「下禮拜三晚上」），再問她能不能配合。",
    field: "coaching",
    context,
  });
  // TP 回歸：時間前置的第三式 schedule 陳述照擋。
  assertThrows(
    () =>
      assertHintFactClaimsSupported({
        text: "下週三晚上她有空，直接把位子訂下去。",
        field: "coaching",
        context,
      }),
    Error,
    ERROR,
  );
});

// round7 判定表（2026-07-23）：動賓片語與動賓「路」複合詞不得誤抽成
// 高信心捏造事實——「丟測試句/丟資訊題」不是第三方人名（bd2/gd3）、
// coaching 引號教學語「帶路」與勸戒語「別急著報路名」不是報點（gh5）。
Deno.test("typed round7 verb-object idioms stay out of high-confidence claims", () => {
  const turns: PracticeTurn[] = [
    {
      role: "user",
      text: "妳上次說想找回聽實體專輯的儀式感，我知道一間唱片行超有味道",
    },
    { role: "ai", text: "被你說得我有點心動，你說的那間唱片行是在哪一區啊" },
  ];
  const context = buildHintFactContext({ turns });
  assertHintFactClaimsSupported({
    text:
      "Game 心法：她問「在哪一區」是想確認這件事能不能成真，不是單純要地址。" +
      "這階段可以直接邀約，但別急著報路名（逐字稿沒給地點就別編）。" +
      "用「帶路」把資訊需求轉成兩人行程，順勢收成一個具體但輕鬆的邀約。",
    field: "coaching",
    context,
  });
  for (
    const analytical of [
      "她願意玩梗、丟測試句，但只聊歌單，未給場景或時間線索",
      "沒有給她任何情緒或內容，只丟資訊題，她開始感覺被審問",
    ]
  ) {
    assertEquals(
      collectUnsupportedHintFactClaims({
        text: analytical,
        field: "coaching",
        context,
      }).filter((claim) =>
        claim.owner === "third_party" && claim.domain === "name"
      ),
      [],
      analytical,
    );
  }
});

// round8 判定表（2026-07-23）：裸「丟」比喻賓語與「路」字首複合詞不得誤抽——
// 「丟球給你接」不是第三方人名（gd2，與格「給」＋字尾「球」雙防）、
// 「只知道路過會被勾住」的「路過」不是報點（gh5，路(?!過) lookahead＋知道路）。
Deno.test("typed round8 metaphor objects and 路-initial compounds stay out of high-confidence claims", () => {
  const turns: PracticeTurn[] = [
    {
      role: "user",
      text: "妳上次說想找回聽實體專輯的儀式感，我知道一間唱片行超有味道",
    },
    { role: "ai", text: "被你說得我有點心動，你說的那間唱片行是在哪一區啊" },
  ];
  const context = buildHintFactContext({ turns });
  assertEquals(
    collectUnsupportedHintFactClaims({
      text: "她說「用行動證明」是丟球給你接，你沒把這個張力延續下去",
      field: "coaching",
      context,
    }).filter((claim) =>
      claim.owner === "third_party" && claim.domain === "name"
    ),
    [],
  );
  assertEquals(
    collectUnsupportedHintFactClaims({
      text: "哈哈其實我還沒仔細記地址，只知道路過會被那個黑膠味道勾住。",
      field: "reply",
      context,
    }).filter((claim) =>
      claim.domain === "venue" && claim.confidence === "high"
    ),
    [],
  );
});

// round9 判定表（2026-07-23）：命名系詞「只是/店是＋形容詞」與「這週一起」
// 切割不得誤抽 venue_named／schedule（gh5 r1 兩筆）。
Deno.test("typed round9 copula and weekday segmentation stay out of claims", () => {
  const turns: PracticeTurn[] = [
    { role: "user", text: "我知道一間唱片行超有味道" },
    { role: "ai", text: "被你說得我有點心動，你說的那間唱片行是在哪一區啊" },
  ];
  const context = buildHintFactContext({ turns });
  for (
    const [text, field] of [
      ["哈其實我還沒去過那間，只是路過聞到黑膠味就記下來了", "reply"],
      ["她可能是在確認妳說的店是真實的、妳是認真的。", "coaching"],
      ["這階段具體到「這週一起去」但保留她能婉拒的空間。", "coaching"],
    ] as const
  ) {
    assertEquals(
      collectUnsupportedHintFactClaims({ text, field, context })
        .filter((claim) =>
          (claim.domain === "venue" && claim.relation === "venue_named") ||
          claim.anchor === "週一"
        ),
      [],
      text,
    );
  }
});

// round10 判定表（2026-07-23）：副詞「一路」不是路名（gh5「不要一路追問」）、
// 裸「丟」的「丟球」比喻不是第三方人名（gd2「丟球考驗你」）；真路名
//（民生一路）與真送收語境不受影響。
Deno.test("typed round10 adverbial 一路 and 丟球 metaphor stay out of claims", () => {
  for (
    const [text, banned] of [
      [
        "速約任務：把窗口收成30分鐘的短行程邀約，具體但保留她可以拒絕的空間，不要一路追問她要不要去。",
        (claim: HintFactClaim) =>
          claim.domain === "venue" && claim.anchor.includes("一路"),
      ],
      [
        "她說「要用行動證明」是丟球考驗你，你卻只問「哪個時段」變回查戶口",
        (claim: HintFactClaim) =>
          claim.relation === "is_named" && claim.anchor.includes("球"),
      ],
    ] as const
  ) {
    assertEquals(
      extractHintFactClaims({
        text,
        perspective: "coaching",
        provenance: "generated_coaching",
        defaultOwner: "user",
      }).filter(banned),
      [],
      text,
    );
  }
  // 真路名（專名構詞＋一路）仍要抽得到，不得被副詞排除吃掉。
  const road = extractHintFactClaims({
    text: "那間店在民生一路上，靠近捷運站",
    perspective: "reply",
    provenance: "generated_reply",
    defaultOwner: "user",
  });
  assertEquals(
    road.some((claim) =>
      claim.relation === "located_at" && claim.anchor.includes("民生一路")
    ),
    true,
  );
});
