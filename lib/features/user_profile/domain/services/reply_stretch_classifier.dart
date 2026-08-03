import '../entities/user_profile.dart';

/// analyze-chat 五種回覆型別（延展/共鳴/調情/幽默/冷讀）。命名對齊
/// supabase/functions/analyze-chat/index.ts 的 openers key。
enum ReplyStyleKey { extend, resonate, tease, humor, coldRead }

/// 「這則回覆」相對於用戶舒適區風格的延伸程度。
enum ReplyStretchLevel { within, stretch, far }

/// 「關於我」重新定位（2026-08-03 report）v1 本地對照表——已由批3
/// analyze-chat 的 stretchLevels（AI 自己判斷）取代，[resolve] 優先讀
/// 後端值。本地表僅在後端未提供該欄位時當 fallback（例如舊 client 呼叫到
/// 還沒升級的 Edge Function，或新 client 呼叫到還沒部署完的舊 Edge
/// Function 的部署時序空窗）。只看主風格，準確度有限。
///
/// far 只用在明確違反該風格核心特質時（例如溫柔=低壓不催促，直接搞笑/
/// 調情就是跳太遠），其餘一律落在 stretch，鼓勵嘗試而非直接判死。
class ReplyStretchClassifier {
  const ReplyStretchClassifier();

  /// 優先讀後端 [backendStretchLevels]（analyze-chat 回應的 stretchLevels
  /// 欄位，key 為 type 字串）；缺席或值無法辨識時 fallback 到本地
  /// [classifyByTypeString]。
  ReplyStretchLevel? resolve({
    required String type,
    required Map<String, String>? backendStretchLevels,
    required InteractionStyle? comfortStyle,
  }) {
    final backendValue = backendStretchLevels?[type];
    final parsed = _levelFromString(backendValue);
    if (parsed != null) return parsed;
    return classifyByTypeString(comfortStyle: comfortStyle, type: type);
  }

  static ReplyStretchLevel? _levelFromString(String? value) {
    switch (value) {
      case 'within':
        return ReplyStretchLevel.within;
      case 'stretch':
        return ReplyStretchLevel.stretch;
      case 'far':
        return ReplyStretchLevel.far;
      default:
        return null;
    }
  }

  static const Map<InteractionStyle, Set<ReplyStyleKey>> _within = {
    InteractionStyle.steady: {ReplyStyleKey.extend, ReplyStyleKey.coldRead},
    InteractionStyle.direct: {ReplyStyleKey.extend, ReplyStyleKey.coldRead},
    InteractionStyle.humorous: {
      ReplyStyleKey.extend,
      ReplyStyleKey.coldRead,
      ReplyStyleKey.humor,
    },
    InteractionStyle.gentle: {ReplyStyleKey.extend, ReplyStyleKey.resonate},
    InteractionStyle.playful: {
      ReplyStyleKey.extend,
      ReplyStyleKey.coldRead,
      ReplyStyleKey.humor,
      ReplyStyleKey.tease,
    },
  };

  static const Map<InteractionStyle, Set<ReplyStyleKey>> _far = {
    InteractionStyle.gentle: {ReplyStyleKey.humor, ReplyStyleKey.tease},
  };

  ReplyStretchLevel classify({
    required InteractionStyle comfortStyle,
    required ReplyStyleKey replyStyle,
  }) {
    if (_within[comfortStyle]!.contains(replyStyle)) {
      return ReplyStretchLevel.within;
    }
    if (_far[comfortStyle]?.contains(replyStyle) ?? false) {
      return ReplyStretchLevel.far;
    }
    return ReplyStretchLevel.stretch;
  }

  /// analyze-chat 用字串 key（extend/resonate/tease/humor/coldRead）表示
  /// 回覆型別。[comfortStyle] 為 null（用戶沒填舒適區風格）或 [type] 無法
  /// 辨識時回傳 null——呼叫端應視為「沒有判斷」，不顯示延伸提示。
  ReplyStretchLevel? classifyByTypeString({
    required InteractionStyle? comfortStyle,
    required String type,
  }) {
    if (comfortStyle == null) return null;
    final key = _replyStyleKeyFromType(type);
    if (key == null) return null;
    return classify(comfortStyle: comfortStyle, replyStyle: key);
  }

  static ReplyStyleKey? _replyStyleKeyFromType(String type) {
    switch (type) {
      case 'extend':
        return ReplyStyleKey.extend;
      case 'resonate':
        return ReplyStyleKey.resonate;
      case 'tease':
        return ReplyStyleKey.tease;
      case 'humor':
        return ReplyStyleKey.humor;
      case 'coldRead':
        return ReplyStyleKey.coldRead;
      default:
        return null;
    }
  }
}
