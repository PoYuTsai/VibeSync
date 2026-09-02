// 刪帳非阻塞清理失敗的告警：純函式組訊息＋有逾時、不拋例外的投遞。
// 訊息只帶表名、錯誤碼與 user id 的 SHA-256 前 12 碼，不含 Email 或任何內容。
export function buildCleanupFailureAlert(input: {
  table: string;
  errorCode: string | null;
  userRef: string;
}): string {
  return [
    "⚠️ delete-account：帳號已刪除，但一項非必要資料清理失敗，殘留資料需人工確認",
    `Table: ${input.table}`,
    `Error: ${input.errorCode ?? "unknown"}`,
    `User ref: ${input.userRef}`,
  ].join("\n");
}

/** 投遞 Discord webhook。沒設定、逾時、網路錯誤、非 2xx 一律回 false，永不拋出。 */
export async function deliverCleanupAlert(input: {
  webhookUrl: string;
  content: string;
  timeoutMs?: number;
  fetchImpl?: typeof fetch;
}): Promise<boolean> {
  if (!input.webhookUrl) return false;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), input.timeoutMs ?? 3000);
  try {
    const response = await (input.fetchImpl ?? fetch)(input.webhookUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ content: input.content }),
      signal: controller.signal,
    });
    return response.ok;
  } catch {
    return false;
  } finally {
    clearTimeout(timer);
  }
}
