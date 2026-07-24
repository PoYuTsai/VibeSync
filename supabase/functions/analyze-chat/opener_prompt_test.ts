import {
  assert,
  assertFalse,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";

Deno.test({
  name: "OPENER_PROMPT teaches users how to reply, not just what to paste",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    assert(source.includes("讓用戶看懂「怎麼去回」"));
    assert(source.includes("先選哪顆球、用什麼框架接"));
    assert(source.includes("回完要留下什麼下一球"));
    assert(source.includes("profileAnalysis.openingStrategy 請用一句話教用戶"));
    assert(source.includes("先接哪個線索、避開哪類題、用哪種球丟回去"));
    assert(source.includes("recommendation.reason 必須像教練講解「怎麼回」"));
    assert(source.includes("刪掉哪種錯誤接法"));
    assert(
      source.includes(
        "教用戶怎麼回：這句示範了什麼框架、接哪顆球、刪掉哪種錯誤接法、女生可以怎麼接回來",
      ),
    );
  },
});

Deno.test({
  name:
    "opener no-charge billing is decided server-side, AI insufficientInfo flag is telemetry only",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // Prompt: AI is told the flag is observability, not a billing lever.
    assert(
      source.includes("## 資訊不足自評（profileAnalysis.insufficientInfo）"),
    );
    assert(source.includes("AI 對自己輸出品質的誠實自評"));
    assert(source.includes("這個欄位**不**直接決定扣帳"));
    assert(
      source.includes(
        "後端會獨立依請求內容（是否有圖、是否有 bio/interests/meetingContext 實質內容）判斷",
      ),
    );
    assert(source.includes('"insufficientInfo": false'));

    // Handler: server-side eligibility is the source of truth for billing.
    assert(
      source.includes(
        "// Server-side eligibility for no-charge: when input is objectively",
      ),
    );
    assert(source.includes("const hasProfileSubstance ="));
    assert(
      source.includes(
        "const serverEligibleForNoCharge = imageCount === 0 &&\n        !hasProfileSubstance;",
      ),
    );
    assert(
      source.includes(
        "const upfrontGateCost = serverEligibleForNoCharge ? 0 : openerCost;",
      ),
    );
    // Upfront 429 gate must use the eligibility-aware cost.
    assert(
      source.includes(
        "sub.monthly_messages_used + upfrontGateCost > monthlyLimit",
      ),
    );
    assert(
      source.includes(
        "sub.daily_messages_used + upfrontGateCost > dailyLimit",
      ),
    );
    // Final billing must be driven by server eligibility, not the AI flag.
    assert(
      source.includes(
        "const effectiveOpenerCost = serverEligibleForNoCharge ? 0 : openerCost;",
      ),
    );
    assert(source.includes("!accountIsTest && effectiveOpenerCost > 0"));
    // 扣費已抽進 chargeOpenerQuota（idempotency ledger 版）；index.ts 只
    // 決定 effectiveOpenerCost 並轉交，canonical RPC 錨點移到 helper 檔。
    assert(source.includes("const chargeOutcome = await chargeOpenerQuota({"));
    assert(source.includes("cost: effectiveOpenerCost,"));
    const chargeHelper = await Deno.readTextFile(
      new URL("./opener_charge.ts", import.meta.url),
    );
    assert(chargeHelper.includes("p_messages: args.cost,"));
    assert(source.includes("opener_credit_deduct_failed"));
    assert(source.includes('error: "credit_deduct_failed"'));
    assert(
      !source.includes(
        "monthly_messages_used: (sub?.monthly_messages_used || 0) +",
      ),
      "opener billing must use the canonical increment_usage RPC",
    );
    // AI flag is captured for telemetry only.
    assert(source.includes("const aiInsufficientFlag ="));
    assert(
      source.includes(
        "serverEligibleForNoCharge,\n        aiInsufficientFlag,",
      ),
    );

    // Single chokepoint: both the substance check and the prompt builder
    // must read from the same normalized profileInfo. A non-string field
    // (e.g. `interests: ["咖啡"]`) cannot bypass billing while slipping
    // into the prompt via JS string coercion.
    assert(
      source.includes(
        'import {\n  hasOpenerProfileSubstance,\n  normalizeOpenerProfileInfo,\n} from "./opener_profile.ts";',
      ),
    );
    assert(
      source.includes(
        "const normalizedProfile = normalizeOpenerProfileInfo(rawProfileInfo);",
      ),
    );
    assert(
      source.includes(
        "const hasProfileSubstance = hasOpenerProfileSubstance(normalizedProfile);",
      ),
    );
    assert(
      source.includes(
        "const { name, bio, interests, meetingContext } = normalizedProfile;",
      ),
    );
    // The prior fragile read pattern must not come back.
    assert(
      !source.includes("rawProfileInfo as Record<string, string>"),
      "prompt builder must not cast rawProfileInfo to Record<string,string>; use normalizedProfile instead",
    );
  },
});

Deno.test({
  name:
    "opener flat-cost: 3 quota per request regardless of image count, user-text-only case prompted to avoid blind A/B guessing",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // Cost is now flat 3 regardless of image count. The per-image
    // surcharge formula must not come back.
    assert(source.includes("const openerCost = 3;"));
    assert(
      !source.includes("const openerCost = 3 + (imageCount * 2);"),
      "openerCost must be flat 3, not 3 + imageCount*2",
    );
    // Comment explaining the flat-cost decision should stay close to
    // the assignment so future readers don't reintroduce per-image surcharge.
    assert(
      source.includes("Flat cost regardless of image count"),
    );

    // The system prompt must now include guidance for the
    // "user-supplied text but no image" case so the model doesn't fall
    // back to generic "比較喜歡 A 還是 B" guessing on second-hand info.
    assert(
      source.includes("沒有截圖、只有用戶手填的文字"),
    );
    assert(
      source.includes("「用戶口中的對方」**二手**資訊"),
    );
    assert(
      source.includes("避開「比較喜歡 A 還是 B」"),
    );
  },
});

// ─── Batch 3：opener prompt Game 化（2026-07-02 opener-game-design）───

async function readIndexSource(): Promise<string> {
  return await Deno.readTextFile(new URL("./index.ts", import.meta.url));
}

// 6 個 prompt 常數的切界：起點＝宣告、終點＝下一個頂層宣告（同 index_test.ts
// readAnalyzeSystemPrompt 的邊界策略；段落間夾到少量 code/註解是刻意的保守掃描）。
const PROMPT_SEGMENTS: Array<[string, string, string]> = [
  [
    "OPENER_REPAIR_PROMPT",
    "const OPENER_REPAIR_PROMPT",
    "function buildOpenerRepairPrompt",
  ],
  [
    "OCR_RECOGNIZE_ONLY_SYSTEM_PROMPT",
    "const OCR_RECOGNIZE_ONLY_SYSTEM_PROMPT",
    "const SYSTEM_PROMPT",
  ],
  [
    "SYSTEM_PROMPT",
    "const SYSTEM_PROMPT",
    "const OPTIMIZE_MESSAGE_MAX_TOKENS",
  ],
  [
    "OPTIMIZE_MESSAGE_PROMPT",
    "const OPTIMIZE_MESSAGE_PROMPT",
    "const MY_MESSAGE_PROMPT",
  ],
  [
    "MY_MESSAGE_PROMPT",
    "const MY_MESSAGE_PROMPT",
    "const OPENER_PROMPT",
  ],
  [
    "OPENER_PROMPT",
    "const OPENER_PROMPT",
    "function normalizeScreenshotClassification",
  ],
];

function slicePromptSegment(
  source: string,
  name: string,
  startMarker: string,
  endMarker: string,
): string {
  const start = source.indexOf(startMarker);
  const end = source.indexOf(endMarker, start + startMarker.length);
  assert(start >= 0 && end > start, `${name} 邊界定位失敗`);
  return source.slice(start, end);
}

async function readOpenerPrompt(): Promise<string> {
  const source = await readIndexSource();
  return slicePromptSegment(
    source,
    "OPENER_PROMPT",
    "const OPENER_PROMPT",
    "function normalizeScreenshotClassification",
  );
}

Deno.test({
  name:
    "all 6 prompt constants keep layer 2-3 blacklist words out (三層線 blocking 掃描)",
  permissions: { read: true },
  fn: async () => {
    const source = await readIndexSource();

    // 黑名單複用 index_test.ts:1480 既有 18 詞（含玩咖）
    const banned = [
      "PUA",
      "紅藥丸",
      "紅丸",
      "DHV",
      "shit test",
      "廢物測試",
      "高價值男性",
      "高分妹",
      "撈女",
      "壞女人",
      "公主病",
      "婊子",
      "怪男",
      "噁男",
      "收割",
      "控住",
      "攻略",
      "玩咖",
    ];

    for (const [name, startMarker, endMarker] of PROMPT_SEGMENTS) {
      const segment = slicePromptSegment(source, name, startMarker, endMarker);
      for (const word of banned) {
        assertFalse(
          segment.includes(word),
          `黑名單詞殘留於 ${name}：${word}`,
        );
      }
      // IOI/IOD（英文縮寫單獨檢，同 index_test.ts 既有 regex）
      assertFalse(/IO[ID]/.test(segment), `IOI/IOD 殘留於 ${name}`);
    }
  },
});

Deno.test({
  name:
    "OPENER_PROMPT carries the 7-term opener vocabulary (子集 4＋開場專屬 3)",
  permissions: { read: true },
  fn: async () => {
    const prompt = await readOpenerPrompt();

    // 7 詞全名以表格列錨定（防單字詞誤命中）
    for (
      const row of [
        "| 吐槽冷讀 |",
        "| 失格 |",
        "| 不自證 |",
        "| 框架維持 |",
        "| 雙球 |",
        "| 旁路冷讀 |",
        "| 好奇心鉤子 |",
      ]
    ) {
      assert(prompt.includes(row), `opener 詞彙表缺：${row}`);
    }

    // 子集 4 詞定義句照抄 10 詞表（同名同定義，防表頭在、內容空殼）
    assert(prompt.includes("基於她給過的素材做輕吐槽式猜測")); // 吐槽冷讀
    assert(prompt.includes("自嘲式暴露無傷小缺點")); // 失格
    assert(prompt.includes("＝輕自嘲式降壓")); // 失格定義行加註（Eric 拍板）
    assert(prompt.includes("被質疑、貼標籤時不急著解釋自己")); // 不自證
    assert(prompt.includes("評價權留在自己手上")); // 框架維持

    // 開場專屬 3 詞定義抽查
    assert(prompt.includes("一次丟兩顆球讓她選")); // 雙球
    assert(prompt.includes("合理但不明說的推測")); // 旁路冷讀
    assert(prompt.includes("傘詞")); // 好奇心鉤子＝五型傘詞
    assert(prompt.includes("好奇心鉤子：二選一")); // 標注格式＝傘詞：型名
  },
});

Deno.test({
  name:
    "OPENER_PROMPT manifestation rule: label in analysis fields only, openers stay clean",
  permissions: { read: true },
  fn: async () => {
    const prompt = await readOpenerPrompt();

    // 硬指令：分析欄位用到表內技巧必須標名＋一句為什麼
    assert(prompt.includes("必須標技巧名＋一句為什麼"));
    // twoBallPlan 建議雙球時要標「雙球」
    assert(prompt.includes("建議雙球時要標「雙球」"));
    // 可直接貼出的文字零技巧名
    assert(
      prompt.includes(
        "openers 五句本體、talkingPoints、pioneerPlan 永遠是可直接貼出的自然句子，不夾技巧名",
      ),
    );
    // 反向禁令（照抄 analyze-chat 顯現規則）
    assert(prompt.includes("不得為了標名而出招"));
    // 線索不足走安全開場時零標籤完全合格
    assert(prompt.includes("整份輸出零技巧標籤也完全合格"));

    // 既有 inline 目標質感句就地標注（從示範學行為，不引進新範例素材）
    assert(prompt.includes("「妳感覺蠻會唱歌。」（旁路冷讀）"));
    assert(prompt.includes("問一題比較像人類的。」（失格）"));
    // 防抄指令（Codex P2 2026-07-02）：示範句旁的括號旁注是教學標注，
    // 不得被照抄進可直接貼出的輸出欄位
    assert(prompt.includes("旁注是給你看的教學標注"));
    assert(prompt.includes("絕不把括號標注抄進 openers"));
  },
});

// ─── F3-1：opener 吃 effectiveStyleContext（2026-07-03 app-review plan）───

Deno.test({
  name:
    "opener path consumes effectiveStyleContext: sanitize before gates, bound into input hash, user-style never treated as target info (F3-1)",
  permissions: { read: true },
  fn: async () => {
    const source = await readIndexSource();
    const prompt = await readOpenerPrompt();

    // ── prompt 消費段：只調語氣、用戶資料絕不冒充對方資料 ──
    assert(prompt.includes("## 用戶風格設定（effectiveStyleContext）"));
    assert(prompt.includes("只用來調整開場白的語氣"));
    assert(prompt.includes("不要替用戶假裝成另一個人"));
    assert(prompt.includes("絕不把用戶的興趣當成對方的興趣"));
    assert(prompt.includes("假造共同點"));
    assert(prompt.includes("對方可見線索、avoidTopics 與安全分寸永遠優先"));
    assert(prompt.includes("沒有附風格設定時照常生成"));

    // ── handler 佈線 ──
    const openerBranch = source.indexOf("if (isOpenerMode) {");
    assert(openerBranch >= 0, "opener branch 定位失敗");

    // sanitize 發生在 opener branch 內、且在 rate-limit gate 之前
    //（gate 鐵則：所有不打模型的拒絕路徑必須先行）。
    const sanitizeInOpener = source.indexOf(
      "const openerStyleValidation = sanitizeEffectiveStyleContext(",
      openerBranch,
    );
    assert(sanitizeInOpener > openerBranch, "opener branch 內必須 sanitize");
    const openerRateGate = source.indexOf('scope: "opener"', openerBranch);
    assert(
      openerRateGate > 0 && sanitizeInOpener < openerRateGate,
      "sanitize 400 必須在 opener rate-limit gate 之前",
    );

    // input hash 綁 style context（同 requestId 換風格＝payload mismatch）
    assert(
      source.includes("effectiveStyleContext: openerStyleContext,"),
      "computeOpenerInputHash 必須吃 openerStyleContext",
    );

    // userContent 注入必須標明是「用戶本人」的設定，且在對方資訊分流之後
    // （防 style context 被當成「可見資訊」觸發對方線索指令）。
    const targetInfoBranch = source.indexOf(
      "用戶沒有提供對方資料",
      openerBranch,
    );
    const styleInjection = source.indexOf(
      "用戶（發訊者本人）的風格設定",
      openerBranch,
    );
    assert(styleInjection > 0, "userContent 必須注入用戶風格設定區塊");
    assert(
      targetInfoBranch > 0 && styleInjection > targetInfoBranch,
      "風格注入必須在對方資訊有無分流之後",
    );
    assert(
      source.includes("這些不是對方的資料；只用來調整開場白語氣"),
      "注入區塊必須帶不冒充對方資料的守門句",
    );
  },
});

Deno.test({
  name:
    "OPENER_PROMPT three-layer cleanup: 玩咖/PUA/把妹/alpha/negging rewritten to bounded phrasing",
  permissions: { read: true },
  fn: async () => {
    const prompt = await readOpenerPrompt();

    // 舊詞不得殘留（玩咖/PUA 由 blocking 掃描蓋，這裡鎖 opener 特有殘詞）
    assertFalse(prompt.includes("把妹"), "把妹殘留於 OPENER_PROMPT");
    assertFalse(prompt.includes("alpha"), "alpha 殘留於 OPENER_PROMPT");
    assertFalse(prompt.includes("negging"), "negging 殘留於 OPENER_PROMPT");

    // 轉寫後的定義句必須在（語意保留、行為不變，只換詞）
    assert(prompt.includes("更鬆、更敢：鬆弛、有觀察、敢丟小框架")); // 原 2174 玩咖人格
    assert(prompt.includes("有點壞但有邊界的鬆弛感")); // 玩咖感統一轉寫
    assert(prompt.includes("借鑑實戰聊天高手的優點")); // 原 2241 把妹高手/alpha 男
    assert(prompt.includes("不能貶低、羞辱、或用打壓她自尊的玩笑")); // 原 2247 negging
    assert(prompt.includes("不要操控式、油膩的罐頭話術")); // 原 2374 PUA，沿 SYSTEM_PROMPT 前例
  },
});

// ─── Opener contract v2 completeness（2026-07-24 Free 3 卡）───

Deno.test({
  name:
    "opener prompts still demand all five styles; Free projection is server-side only",
  permissions: { read: true },
  fn: async () => {
    const source = await readIndexSource();
    const prompt = await readOpenerPrompt();

    // Free 3 卡靠 server tier filter 投影，模型永遠產五種——OPENER_PROMPT
    // 的 schema 與風格任務段不得因 contract v2 縮水或分流。
    for (
      const key of [
        '"extend": "延展風格的開場白"',
        '"resonate": "共鳴風格的開場白"',
        '"tease": "調情風格的開場白"',
        '"humor": "幽默風格的開場白"',
        '"coldRead": "冷讀風格的開場白"',
      ]
    ) {
      assert(prompt.includes(key), `OPENER_PROMPT schema 缺：${key}`);
    }
    assert(prompt.includes("## 五種風格各有任務"));
    // prompt 不得出現依 tier 少產風格的指令（免費/付費分流是 server 的事）
    assertFalse(prompt.includes("免費版"), "OPENER_PROMPT 不得含 tier 分流指令");
    assertFalse(prompt.includes("Free"), "OPENER_PROMPT 不得含 tier 分流指令");

    // completeness gate 走既有 repair：OPENER_REPAIR_PROMPT 必須繼續強制
    // 五 key 齊全，否則 partial 修復修不回五種、gate 恆 502。
    const repairPrompt = slicePromptSegment(
      source,
      "OPENER_REPAIR_PROMPT",
      "const OPENER_REPAIR_PROMPT",
      "function buildOpenerRepairPrompt",
    );
    assert(
      repairPrompt.includes(
        "openers 必須包含 extend / resonate / tease / humor / coldRead 五個 key。",
      ),
    );
  },
});

Deno.test({
  name:
    "公式開場（2026-07-24 計畫 §5.1/§6）：prompt 段落＋schema 殿後＋handler 隔離資料流",
  permissions: { read: true },
  fn: async () => {
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );

    // Prompt：公式段存在、五型不得被取代、共同點需證據、目標長度。
    assert(source.includes("## 公式開場（額外兩則，不取代上面的五種風格）"));
    assert(
      source.includes(
        "不得刪除、合併、改寫或減少\nextend / resonate / tease / humor / coldRead 五種開場",
      ),
    );
    assert(source.includes("不得把\neffectiveStyleContext 與對方素材自行拼成共同點"));
    assert(source.includes("openingLine 目標 45–80 個繁中字元；whyItWorks 目標 60–100 個繁中字元"));
    assert(source.includes("強例只示範結構，不得照抄"));

    // Schema：formulaOpeners 是輸出格式最後一個 key（先完成原契約）。
    const schemaAt = source.indexOf("## 輸出格式 (JSON)");
    assert(schemaAt > 0);
    const formulaKeyAt = source.indexOf('"formulaOpeners": [', schemaAt);
    const recommendationKeyAt = source.indexOf('"recommendation": {', schemaAt);
    assert(
      formulaKeyAt > recommendationKeyAt && recommendationKeyAt > schemaAt,
      "formulaOpeners 必須在 schema 的 recommendation 之後（殿後）",
    );

    // Token cap 維持 3000（本案不得預先上修）。
    assert(source.includes("const OPENER_MAX_TOKENS = 3000;"));

    // Handler：公式只認 primary、base 完整後才 normalize、以最終五句 dedupe。
    assert(
      source.includes(
        "const openerPrimaryFormulaRaw = openerPrimaryParsed?.formulaOpeners;",
      ),
    );
    const incompleteGateAt = source.indexOf('error: "OPENER_RESPONSE_INCOMPLETE"');
    const formulaNormalizeAt = source.indexOf(
      "const openerFormulaOutcome = normalizeFormulaRepliesDetailed(",
    );
    const tierFilterAt = source.indexOf(
      "const filteredOpenerPayload = filterOpenerPayloadForAllowedFeatures(",
    );
    assert(
      incompleteGateAt > 0 && formulaNormalizeAt > incompleteGateAt &&
        tierFilterAt > formulaNormalizeAt,
      "公式 normalize 必須在 completeness gate 之後、tier filter 之前（用最終五句 dedupe）",
    );

    // Response：canonical 覆蓋（雙層保險第二層）＋成功一律帶。
    assert(source.includes("formulaOpeners: openerFormulaOutcome.replies,"));

    // Telemetry 只記數量。
    assert(source.includes("formulaOpenersCount: openerFormulaOutcome.replies.length,"));
    assert(source.includes("formulaOpenersDroppedCount: openerFormulaOutcome.droppedCount,"));

    // 內部標籤守門開啟。
    const openerFormulaBlock = source.slice(formulaNormalizeAt, tierFilterAt);
    assert(openerFormulaBlock.includes("rejectInternalLabels: true"));

    // Repair prompt 只負責 base：不得出現 formulaOpeners schema。
    const repairPromptAt = source.indexOf("const OPENER_REPAIR_PROMPT");
    const repairPromptEnd = source.indexOf("function buildOpenerRepairPrompt");
    const repairPrompt = source.slice(repairPromptAt, repairPromptEnd);
    assertFalse(
      repairPrompt.includes("formulaOpeners"),
      "OPENER_REPAIR_PROMPT 不得要求公式（repair 只修 base）",
    );
  },
});

Deno.test({
  name: "公式示範句與 FORMULA_PROMPT_EXAMPLE_LINES 同步（whitespace 不敏感）",
  permissions: { read: true },
  fn: async () => {
    const { FORMULA_PROMPT_EXAMPLE_LINES, formulaDedupeKey } = await import(
      "./formula_reply.ts"
    );
    const source = await Deno.readTextFile(
      new URL("./index.ts", import.meta.url),
    );
    const sourceKey = formulaDedupeKey(source);
    for (const line of FORMULA_PROMPT_EXAMPLE_LINES) {
      assert(
        sourceKey.includes(formulaDedupeKey(line)),
        `示範句必須存在於 OPENER_PROMPT（排除集才會生效）：${line}`,
      );
    }
  },
});
