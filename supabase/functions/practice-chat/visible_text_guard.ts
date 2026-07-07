const INTERNAL_VISIBLE_LABELS = [
  "notready",
  "softinviteready",
  "directinviteready",
  "partnerwindow",
  "highintimacy",
  "relationshipscore",
  "invitestage",
  "currenttemperaturescore",
  "memorysummary",
  "scenestatus",
  "datechance",
  "nextinvitemove",
  "partnerstate",
  "partnermood",
  "innerthought",
  "sceneprompt",
  "replytempo",
  "inviteguidance",
];

function normalizeVisibleText(value: string): string {
  return value
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "");
}

export function hasVisibleInternalLabelLeak(value: string): boolean {
  const normalized = normalizeVisibleText(value);
  return INTERNAL_VISIBLE_LABELS.some((label) => normalized.includes(label));
}

export function rejectVisibleInternalLabelLeak(
  value: string,
  errorCode: string,
) {
  if (hasVisibleInternalLabelLeak(value)) {
    throw new Error(errorCode);
  }
}
