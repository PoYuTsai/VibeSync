import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 開場救星送出的 effectiveStyleContext。「關於我」只給 Coach 1:1
/// （2026-08-04），這裡固定回 null，不讀任何關於我或對象風格設定；伺服器
/// 也只拿舊版 App 帶來的值算重送指紋（2026-10-20）。
///
/// Provider 本身保留：開場救星畫面每次嘗試前會 await 它，再把結果和
/// requestId 一起凍結進 OpenerAttempt，重送指紋才不會漂移（Codex R1 P2）。
/// 拿掉它要一併改畫面與防重複邏輯，另案處理。
final openerStyleContextProvider =
    FutureProvider.family<String?, String?>((ref, partnerId) async => null);
