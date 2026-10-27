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

/// 季繳的月均價小字（Onboarding 第 9 步）：扣款金額 ÷ 3，無條件進位到價格的最小位數
/// （寧可多算一點，也不把每月成本說少）。幣別符號、千分位、小數點照 StoreKit 的
/// priceString，只把數字換掉；整除時寫「平均每月」，進位過的寫「平均每月約」。
///
/// 這只是補充說明，扣款金額才是主角。解不出 priceString 的數字、解出來跟
/// [StoreProduct.price] 對不上、或算出來沒有比扣款金額小，就回傳 null 不顯示——
/// 寧可不寫，也不寫錯。
String? quarterlyMonthlyAverageLabel(StoreProduct? quarterly) {
  if (quarterly == null) return null;
  final parsed = _StorePriceFormat.tryParse(
    quarterly.priceString,
    quarterly.price,
  );
  if (parsed == null) return null;

  final chargeMinor = parsed.minorUnits;
  final averageMinor = (chargeMinor + 2) ~/ 3; // 無條件進位
  if (averageMinor <= 0 || averageMinor >= chargeMinor) return null;

  final average = parsed.format(averageMinor);
  return chargeMinor % 3 == 0 ? '平均每月 $average' : '平均每月約 $average';
}

/// priceString 裡的數字：一個數字開頭、一個數字結尾，中間可夾千分位或小數點
///（逗號、句點、撇號、一般／不換行空白）。
final _priceNumber = RegExp('\\d(?:[\\d.,\'   ]*\\d)?');
final _nonDigit = RegExp(r'\D');

/// 拆開 StoreKit 的價格字串：數字前後的幣別字樣原樣保留，換一個金額也照同一種寫法。
class _StorePriceFormat {
  const _StorePriceFormat({
    required this.prefix,
    required this.suffix,
    required this.decimals,
    required this.decimalSeparator,
    required this.groupSeparator,
    required this.minorUnits,
  });

  final String prefix;
  final String suffix;
  final int decimals;
  final String decimalSeparator;
  final String? groupSeparator;

  /// 金額換成最小單位（TWD 是元；兩位小數的幣別是分）。
  final int minorUnits;

  /// 兩種讀法（最後一個符號是小數點／全部都是千分位）都試，只收跟 [price]
  /// 對得上的那一種；都對不上就是看不懂，回傳 null。
  static _StorePriceFormat? tryParse(String priceString, double price) {
    if (!price.isFinite || price <= 0) return null;
    final match = _priceNumber.firstMatch(priceString);
    if (match == null) return null;
    final number = match.group(0)!;
    final prefix = priceString.substring(0, match.start);
    final suffix = priceString.substring(match.end);

    final candidates = <_StorePriceFormat>[
      _StorePriceFormat(
        prefix: prefix,
        suffix: suffix,
        decimals: 0,
        decimalSeparator: '',
        groupSeparator: _firstSeparator(number),
        minorUnits: int.parse(number.replaceAll(_nonDigit, '')),
      ),
    ];
    final lastSeparator = number.lastIndexOf(_nonDigit);
    if (lastSeparator > 0) {
      final integerPart = number.substring(0, lastSeparator);
      final fraction = number.substring(lastSeparator + 1);
      if (fraction.length <= 3) {
        candidates.add(_StorePriceFormat(
          prefix: prefix,
          suffix: suffix,
          decimals: fraction.length,
          decimalSeparator: number[lastSeparator],
          groupSeparator: _firstSeparator(integerPart),
          minorUnits: int.parse(
            '${integerPart.replaceAll(_nonDigit, '')}$fraction',
          ),
        ));
      }
    }

    for (final candidate in candidates) {
      final value = candidate.minorUnits / _unit(candidate.decimals);
      if ((value - price).abs() < 0.005) return candidate;
    }
    return null;
  }

  /// 用同一種寫法寫出另一個金額（最小單位）。
  String format(int minorUnits) {
    final unit = _unit(decimals);
    var integer = (minorUnits ~/ unit).toString();
    final separator = groupSeparator;
    if (separator != null) {
      final buffer = StringBuffer();
      for (var i = 0; i < integer.length; i++) {
        if (i > 0 && (integer.length - i) % 3 == 0) buffer.write(separator);
        buffer.write(integer[i]);
      }
      integer = buffer.toString();
    }
    if (decimals == 0) return '$prefix$integer$suffix';
    final fraction = (minorUnits % unit).toString().padLeft(decimals, '0');
    return '$prefix$integer$decimalSeparator$fraction$suffix';
  }

  static String? _firstSeparator(String digits) {
    final index = digits.indexOf(_nonDigit);
    return index < 0 ? null : digits[index];
  }

  static int _unit(int decimals) {
    var unit = 1;
    for (var i = 0; i < decimals; i++) {
      unit *= 10;
    }
    return unit;
  }
}
