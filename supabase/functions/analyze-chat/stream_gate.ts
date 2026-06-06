export const STREAM_TEST_ACCOUNT = "vibesync.test@gmail.com";
export const STREAM_ALLOW_ALL = "*";

export type StreamingAccessInput = {
  email?: string | null;
  flagOn?: boolean;
  whitelist?: string | null;
  tier?: string | null;
};

export function parseStreamWhitelist(value?: string | null): Set<string> {
  const emails = new Set<string>();

  for (const part of (value ?? "").split(",")) {
    const email = normalizeEmail(part);
    if (email) {
      emails.add(email);
    }
  }

  emails.add(STREAM_TEST_ACCOUNT);
  return emails;
}

export function isStreamingAllowed(input: StreamingAccessInput): boolean {
  if (input.flagOn !== true) {
    return false;
  }

  // `analyze-chat` is already protected by Supabase auth. The feature flag is
  // the rollout switch; tier still gates the number of reply styles elsewhere.
  return true;
}

function normalizeEmail(value?: string | null): string | null {
  const email = value?.trim().toLowerCase();
  return email ? email : null;
}
