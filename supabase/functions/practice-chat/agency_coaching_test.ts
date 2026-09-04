// Phase 4.1 純函式門檻的兩側正反例。逐字稿全部是合成的，不打任何模型。
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  debriefAgencyLedgerFor,
  hintAgencyCoachingFor,
} from "./agency_coaching.ts";
import { INITIAL_CONVERSATION_AGENCY_STATE } from "./conversation_agency.ts";
import type { PracticeTurn } from "./validate.ts";

const t = (role: "user" | "ai", text: string): PracticeTurn =>
  ({ role, text }) as PracticeTurn;

Deno.test("hint coaching：她剛問完＋玩家丟片段 → answer_her_question", () => {
  const turns = [
    t("user", "東東"),
    t("ai", "東東是誰"),
    t("user", "阿布達比"),
    t("ai", "阿布達比？那是哪裡"),
  ];
  assertEquals(hintAgencyCoachingFor(turns, null), {
    kind: "answer_her_question",
    unresolvedCount: 1,
  });
});

Deno.test("hint coaching：有效短答（她問→他答、零欠債）→ none", () => {
  const turns = [
    t("user", "我今天去看了場電影"),
    t("ai", "什麼片"),
    t("user", "沙丘"),
    t("ai", "好看嗎"),
  ];
  assertEquals(hintAgencyCoachingFor(turns, null), {
    kind: "none",
    unresolvedCount: 0,
  });
});

Deno.test("hint coaching：她沒問過、玩家丟無前文片段 → none（不亂點火）", () => {
  const turns = [t("user", "台北"), t("ai", "哈哈")];
  const got = hintAgencyCoachingFor(turns, null);
  assertEquals(got.kind, "none");
  assertEquals(got.unresolvedCount, 0);
});

Deno.test("hint coaching：欠債 ≥2 → stop_dropping_words（比 answer 優先）", () => {
  const turns = [
    t("user", "東東"),
    t("ai", "東東是誰"),
    t("user", "阿布達比"),
    t("ai", "那是哪裡"),
    t("user", "韓國"),
    t("ai", "怎麼突然講韓國"),
  ];
  const got = hintAgencyCoachingFor(turns, null);
  assertEquals(got.kind, "stop_dropping_words");
  assertEquals(got.unresolvedCount >= 2, true);
});

Deno.test("hint coaching：同一個詞原樣再丟一次 → stop_dropping_words", () => {
  const turns = [
    t("user", "阿布達比"),
    t("ai", "那是哪裡"),
    t("user", "阿布達比"),
    t("ai", "你在說什麼"),
  ];
  assertEquals(
    hintAgencyCoachingFor(turns, null).kind,
    "stop_dropping_words",
  );
});

Deno.test("hint coaching：她上一則沒有問句標記，但狀態記得她問過意圖 → answer_her_question", () => {
  const turns = [
    t("user", "台北"),
    t("ai", "喔"),
    t("user", "高雄"),
    t("ai", "喔"),
  ];
  assertEquals(
    hintAgencyCoachingFor(turns, {
      ...INITIAL_CONVERSATION_AGENCY_STATE,
      lastAgencyAct: "ask_intent",
    }).kind,
    "answer_her_question",
  );
  // 同一份逐字稿、沒有狀態＝她沒問過 → 不點火。
  assertEquals(hintAgencyCoachingFor(turns, null).kind, "none");
});

Deno.test("debrief ledger：連環丟詞的場記到序號與分類", () => {
  const turns = [
    t("user", "東東"),
    t("ai", "東東是誰"),
    t("user", "阿布達比"),
    t("ai", "那是哪裡"),
    t("user", "韓國"),
    t("ai", "怎麼突然講韓國"),
  ];
  const ledger = debriefAgencyLedgerFor(turns);
  assertEquals(ledger.repairTurns, [1, 2, 3]);
  assertEquals(
    ledger.fragmentTurns + ledger.topicShiftTurns + ledger.loopTurns,
    3,
  );
  assertEquals(ledger.fragmentTurns, 1);
});

Deno.test("debrief ledger：正常對話全 0", () => {
  const turns = [
    t("user", "我今天下班超累的"),
    t("ai", "怎麼了"),
    t("user", "開了一整天的會"),
    t("ai", "辛苦欸"),
    t("user", "妳今天呢"),
    t("ai", "還好啦"),
  ];
  assertEquals(debriefAgencyLedgerFor(turns), {
    fragmentTurns: 0,
    topicShiftTurns: 0,
    loopTurns: 0,
    repairTurns: [],
  });
});

Deno.test("debrief ledger：序號清單最多 10 個，計數不設上限", () => {
  const turns: PracticeTurn[] = [];
  for (let i = 0; i < 12; i++) {
    turns.push(t("user", `城市${i}`));
    turns.push(t("ai", "那是哪裡"));
  }
  const ledger = debriefAgencyLedgerFor(turns);
  assertEquals(ledger.repairTurns.length, 10);
  assertEquals(
    ledger.fragmentTurns + ledger.topicShiftTurns + ledger.loopTurns,
    12,
  );
});
