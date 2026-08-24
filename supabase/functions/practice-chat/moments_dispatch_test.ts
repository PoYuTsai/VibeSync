// practice_moments 這條 mode 分派的**行為**測試。
//
// 為什麼要獨立一支（2026-08-24 複審建議）：
// 在此之前這條路徑只有兩層守門，兩層都不是行為測試——
//   1. source 字串掃描（moments_generated_only_source_test.ts）只證明「原始碼裡有這些字」
//   2. `deno check moments_handler.ts` 只證明生成端本身型別對
// 兩者都攔不住「dispatch 分支根本沒接上」「接錯 handler」「掉到通用 chat 驗證去回 400」
// 這類真正會讓功能整條死掉的錯。所以這裡走真的 createPracticeChatHandler，
// 從 HTTP Request 進去、看 Response 出來。
//
// 刻意不寫在 index_test.ts：那個檔不在 flutter-ci.yml 的白名單裡，
// 加在那裡等於零 CI 守門。本檔已加進白名單。

import {
  assert,
  assertEquals,
} from "https://deno.land/std@0.168.0/testing/asserts.ts";
import {
  createPracticeChatHandler,
  type DeepSeekCaller,
  type PracticeSupabaseClient,
} from "./handler.ts";

const USER_ID = "11111111-2222-3333-4444-555555555555";

interface FakeOptions {
  /** 這個帳號翻到過誰；預設一個都沒有（feed 空但仍是 200）。 */
  drawRows?: { profile_id: string; created_at: string }[];
  /** 認證使用者；預設一般帳號。 */
  user?: { id: string; email: string } | null;
}

interface FakeState {
  rpcCalls: string[];
  selectedTables: string[];
  deepSeekCalls: number;
}

function makeFake(options: FakeOptions = {}) {
  const state: FakeState = {
    rpcCalls: [],
    selectedTables: [],
    deepSeekCalls: 0,
  };

  const filterBuilder = (rows: unknown[]) => {
    const builder = {
      eq: () => builder,
      then: (
        // deno-lint-ignore no-explicit-any
        resolve: (v: any) => unknown,
      ) => Promise.resolve({ data: rows, error: null }).then(resolve),
    };
    return builder;
  };

  const client = {
    auth: {
      getUser(_token: string) {
        const user = options.user === undefined
          ? { id: USER_ID, email: "user@example.com" }
          : options.user;
        return Promise.resolve({
          data: { user },
          error: user ? null : { message: "no user" },
        });
      },
    },
    from(table: string) {
      state.selectedTables.push(table);
      return {
        select: () => filterBuilder(options.drawRows ?? []),
      };
    },
    rpc(fn: string, _params: unknown) {
      state.rpcCalls.push(fn);
      // feed 讀取回空清單即可；本檔驗的是分派，不是生成細節。
      return Promise.resolve({ data: [], error: null });
    },
  };

  const deepSeek: DeepSeekCaller = () => {
    state.deepSeekCalls++;
    return Promise.reject(new Error("這條路徑不該打模型"));
  };

  return {
    state,
    handler: createPracticeChatHandler({
      createSupabaseClient: () => client as unknown as PracticeSupabaseClient,
      callDeepSeek: deepSeek,
      getEnv: (name: string) =>
        name === "DEEPSEEK_API_KEY" ? "deepseek-key" : "",
      now: () => new Date("2026-09-03T04:00:00.000Z"),
    }),
  };
}

function momentsRequest(extra: Record<string, unknown> = {}) {
  return new Request("http://localhost/practice-chat", {
    method: "POST",
    headers: {
      Authorization: "Bearer test-token",
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ mode: "practice_moments", ...extra }),
  });
}

Deno.test("practice_moments 這個 mode 真的被分派到動態 feed，而不是掉到通用 chat 驗證", async () => {
  const fake = makeFake();
  const res = await fake.handler(momentsRequest());

  // 這是最重要的一條：分派沒接上時，body 少了 profile 會掉到 validateRequest
  // 回 400，功能整條死掉，而 source 掃描與 type-check 都看不出來。
  assertEquals(res.status, 200);

  const body = await res.json() as Record<string, unknown>;
  assert("posts" in body, `回應沒有 posts 欄位：${JSON.stringify(body)}`);
  assert("generatedCount" in body, "回應沒有 generatedCount 欄位");
  assert("pendingCount" in body, "回應沒有 pendingCount 欄位");
  assertEquals(body.posts, []);

  // 走的是動態 feed 的資料來源，不是聊天那條。
  assert(
    fake.state.selectedTables.includes("practice_profile_draw_events"),
    `沒有讀角色解鎖紀錄，實際讀了：${fake.state.selectedTables.join(", ")}`,
  );
});

Deno.test("一個角色都沒抽到時不打模型、也不碰貼文 RPC", async () => {
  const fake = makeFake({ drawRows: [] });
  const res = await fake.handler(momentsRequest());

  assertEquals(res.status, 200);
  assertEquals(fake.state.deepSeekCalls, 0);
  assertEquals(
    fake.state.rpcCalls.includes("reserve_practice_moment_slot"),
    false,
    "沒有角色卻還去認領 slot，會白燒成本額度",
  );
});

Deno.test("未認證的請求在進到動態 feed 之前就被擋下", async () => {
  const fake = makeFake({ user: null });
  const res = await fake.handler(momentsRequest());

  assert(
    res.status === 401 || res.status === 403,
    `未認證應被擋下，實際 ${res.status}`,
  );
  // 認證失敗就不該碰任何資料來源——貼文是全域資料，更不能未認證就讀。
  assertEquals(fake.state.selectedTables.length, 0);
  assertEquals(fake.state.rpcCalls.length, 0);
  assertEquals(fake.state.deepSeekCalls, 0);
});

Deno.test("動態 feed 的請求 body 不需要、也不該帶聊天欄位", async () => {
  // 隱私鐵則：貼文生成的輸入只有 server profile + 日期 + 題材。
  // 就算 client 亂塞聊天內容，這條路徑也不該因此改變行為或報錯。
  const fake = makeFake();
  const res = await fake.handler(momentsRequest({
    messages: [{ role: "user", content: "這是使用者的私人對話，不該被用到" }],
    profile: { girl: { profileId: "practice_girl_001" } },
  }));

  assertEquals(res.status, 200);
  const body = await res.json() as Record<string, unknown>;
  assertEquals(body.posts, []);
  assertEquals(fake.state.deepSeekCalls, 0);
});
