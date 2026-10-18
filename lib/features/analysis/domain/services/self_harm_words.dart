import '../../../conversation/domain/entities/message.dart';

/// 額度不夠時的自傷關心（Eric 2026-10-18）：她的訊息有這些字，App 不跳額度不足的框，
/// 照常送出；伺服器只回關心訊息與專線，不扣額度、不呼叫模型。
///
/// [traditional] 跟伺服器 `guide_v3/safety.ts` 的 SELF_HARM_WORDS 是同一份（測試會對兩邊，
/// 只改一邊會失敗）。伺服器會把簡體轉成繁體再掃，這裡直接多列簡體寫法（割腕、不想活
/// 簡繁相同）。兩邊對不上時伺服器照舊回額度不足，App 照舊顯示額度不足的卡。
class SelfHarmWords {
  const SelfHarmWords._();

  static const traditional = ['自殺', '自殘', '割腕', '輕生', '不想活'];
  static const simplified = ['自杀', '自残', '轻生'];

  /// 只看她傳的訊息本文；引用的內容可能是他的話，跟伺服器一樣不看。
  static bool inHerMessages(Iterable<Message> messages) => messages.any(
        (message) =>
            !message.isFromMe &&
            [...traditional, ...simplified].any(message.content.contains),
      );
}
