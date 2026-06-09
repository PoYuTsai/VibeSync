export const VALID_IMAGE_MEDIA_TYPES = new Set([
  "image/jpeg",
  "image/png",
  "image/webp",
]);
export const MAX_IMAGE_BYTES = 900 * 1024;
export const MAX_TOTAL_IMAGE_BYTES = MAX_IMAGE_BYTES * 3;

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function validateOpenerImages(
  value: unknown,
): { error?: string; status?: number } {
  if (value == null) return {};
  if (!Array.isArray(value)) return { error: "Invalid images", status: 400 };
  if (value.length > 3) {
    return { error: "最多上傳 3 張截圖", status: 400 };
  }

  const imageOrders = new Set<number>();
  let totalImageBytes = 0;
  for (const image of value) {
    let data: string;
    let mediaType = "image/jpeg";

    if (typeof image === "string") {
      data = image.trim();
    } else if (isPlainObject(image)) {
      if (
        typeof image.data !== "string" ||
        typeof image.mediaType !== "string" ||
        typeof image.order !== "number"
      ) {
        return { error: "圖片格式錯誤", status: 400 };
      }
      data = image.data.trim();
      mediaType = image.mediaType;

      if (!Number.isInteger(image.order) || image.order < 1) {
        return { error: "圖片排序錯誤", status: 400 };
      }
      if (imageOrders.has(image.order)) {
        return { error: "圖片排序重複", status: 400 };
      }
      imageOrders.add(image.order);
    } else {
      return { error: "圖片格式錯誤", status: 400 };
    }

    if (!data) {
      return { error: "圖片格式錯誤", status: 400 };
    }
    if (!VALID_IMAGE_MEDIA_TYPES.has(mediaType)) {
      return { error: "Unsupported image type", status: 400 };
    }

    const estimatedBytes = (data.length * 3) / 4;
    totalImageBytes += estimatedBytes;
    if (totalImageBytes > MAX_TOTAL_IMAGE_BYTES) {
      return { error: "Total image payload too large", status: 400 };
    }
    if (estimatedBytes > MAX_IMAGE_BYTES) {
      return { error: "圖片太大，請壓縮後重試", status: 400 };
    }
  }

  return {};
}
