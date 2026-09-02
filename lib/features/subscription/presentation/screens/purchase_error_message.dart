import 'package:purchases_flutter/purchases_flutter.dart';

/// 購買失敗時給使用者看的文案。未分類的錯誤碼只在 fallback 是可讀的繁中訊息時
/// 照用；原始例外文字（PlatformException、SKErrorDomain…）一律換成固定文案，
/// 不得露到 SnackBar。
String purchaseErrorMessageFor(
  PurchasesErrorCode? errorCode, {
  String? fallbackMessage,
}) {
  switch (errorCode) {
    case PurchasesErrorCode.purchaseCancelledError:
      return '已取消購買。';
    case PurchasesErrorCode.paymentPendingError:
      return '付款仍在等待 App Store 確認。';
    case PurchasesErrorCode.productNotAvailableForPurchaseError:
      return '此方案目前無法購買。';
    case PurchasesErrorCode.storeProblemError:
    case PurchasesErrorCode.networkError:
      return '目前無法連線到 App Store，請稍後再試。';
    default:
      if (fallbackMessage != null &&
          fallbackMessage.contains(RegExp(r'[一-鿿]'))) {
        return fallbackMessage;
      }
      return '訂閱處理失敗，請稍後再試。';
  }
}
