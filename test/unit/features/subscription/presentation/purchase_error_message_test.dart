import 'package:flutter_test/flutter_test.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:vibesync/features/subscription/presentation/screens/purchase_error_message.dart';

void main() {
  group('purchaseErrorMessageFor', () {
    test('已分類的錯誤碼回固定繁中文案', () {
      expect(
        purchaseErrorMessageFor(PurchasesErrorCode.purchaseCancelledError),
        '已取消購買。',
      );
      expect(
        purchaseErrorMessageFor(PurchasesErrorCode.networkError,
            fallbackMessage: 'Network error'),
        '目前無法連線到 App Store，請稍後再試。',
      );
    });

    test('未分類錯誤碼：原始例外文字不得露出，改用固定文案', () {
      expect(
        purchaseErrorMessageFor(
          PurchasesErrorCode.unknownError,
          fallbackMessage:
              'PlatformException(23, The operation couldn’t be completed. (SKErrorDomain error 0.), null, null)',
        ),
        '訂閱處理失敗，請稍後再試。',
      );
      expect(
        purchaseErrorMessageFor(null, fallbackMessage: 'Exception: boom'),
        '訂閱處理失敗，請稍後再試。',
      );
    });

    test('未分類錯誤碼但伺服器給了繁中訊息時照用', () {
      expect(
        purchaseErrorMessageFor(
          PurchasesErrorCode.unknownError,
          fallbackMessage: '這個 Apple ID 已有進行中的訂閱，請先在 App Store 檢查。',
        ),
        '這個 Apple ID 已有進行中的訂閱，請先在 App Store 檢查。',
      );
    });
  });
}
