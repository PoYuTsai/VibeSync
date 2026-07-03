import 'package:purchases_flutter/purchases_flutter.dart';

/// 以真實 store 價計算季繳相對於「月繳 ×3」的折扣徽章文字。
///
/// 任一價格缺失、幣別不一致、或沒有實際折扣時回傳 null（不顯示徽章），
/// 避免向用戶展示與 App Store 實價不符的優惠宣稱。
/// 百分比取 floor：寧可少報也絕不高報折扣。
String? quarterlySavingsLabel({
  required StoreProduct? monthly,
  required StoreProduct? quarterly,
}) {
  if (monthly == null || quarterly == null) return null;
  if (monthly.currencyCode != quarterly.currencyCode) return null;

  final monthlyPrice = monthly.price;
  final quarterlyPrice = quarterly.price;
  if (monthlyPrice <= 0 || quarterlyPrice <= 0) return null;

  final baseline = monthlyPrice * 3;
  if (quarterlyPrice >= baseline) return null;

  final percent = ((1 - quarterlyPrice / baseline) * 100).floor();
  if (percent < 1) return null;
  return '省 $percent%';
}
