// lib/shared/widgets/brand/brand_kit.dart
//
// VibeSync 暗紫橘品牌 UI primitives.
//
// 這套 primitives 把已上線的「關於我 / 作戰板」視覺語言抽成共用元件，讓其餘頁面
// 吃同一套質感、不再混雜舊 glass 風。數值刻意與 about_me_screen /
// profile_chip_section 的已上線版本逐一對齊，確保視覺 byte 級一致。
//
// 設計憲法（改任何頁面都必須遵守）：
//   背景：brandInk → brandSurface → brandSurface2 垂直漸層（stops 0 / .58 / 1）。
//   卡片：brandSurface 系漸層 @ ~.9，圓角 22–24，white@.10 邊框，黑色柔陰影。
//   重點色：ctaStart → ctaEnd 橘色（CTA / 焦點 / icon badge），絕不換成紫色主色。
//   文字：卡上白字 + onBackgroundSecondary 次要；hint 一律低對比白。
//
// 注意：本檔**不**全域改 GlassmorphicContainer——舊頁文字/圖表對比另案處理。
import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// 全頁暗紫橘漸層背景。對齊 about_me_screen 的靜態 gradient（不含動態 bokeh——
/// 動態光球只保留在首頁的 [GradientBackground]，避免每頁都跑動畫拖效能）。
class BrandPageBackground extends StatelessWidget {
  const BrandPageBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.brandInk,
            AppColors.brandSurface,
            AppColors.brandSurface2,
          ],
          stops: [0.0, 0.58, 1.0],
        ),
      ),
      child: child,
    );
  }
}

/// 透明 AppBar，配深色品牌背景使用。標題 w800 白字、白色返回鍵。
PreferredSizeWidget brandAppBar({
  required String title,
  List<Widget>? actions,
  Widget? leading,
  bool centerTitle = true,
}) {
  return AppBar(
    backgroundColor: Colors.transparent,
    elevation: 0,
    centerTitle: centerTitle,
    leading: leading,
    actions: actions,
    iconTheme: const IconThemeData(color: AppColors.onBackgroundPrimary),
    title: Text(
      title,
      style: AppTypography.titleLarge.copyWith(
        color: AppColors.onBackgroundPrimary,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

/// 整頁鷹架：背景 + 透明 Scaffold + 透明 AppBar 一次組好。
/// 不傳 [title] 就不顯示 AppBar（自行在 body 處理標題）。
class BrandScaffold extends StatelessWidget {
  const BrandScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.leading,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.resizeToAvoidBottomInset,
    this.safeArea = true,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? leading;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final bool? resizeToAvoidBottomInset;
  final bool safeArea;

  @override
  Widget build(BuildContext context) {
    final content = safeArea ? SafeArea(child: body) : body;
    return BrandPageBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: resizeToAvoidBottomInset,
        appBar: title == null
            ? null
            : brandAppBar(title: title!, actions: actions, leading: leading),
        bottomNavigationBar: bottomNavigationBar,
        floatingActionButton: floatingActionButton,
        body: content,
      ),
    );
  }
}

/// 品牌卡片表面。[elevated] = true 用漸層 + 較重陰影（主層級內容卡）；
/// false 用單色 brandSurface@.88（次層級 / 內嵌區塊，對齊 _ProfileInputSection）。
class BrandSurfaceCard extends StatelessWidget {
  const BrandSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.elevated = true,
    this.borderRadius = 24,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool elevated;
  final double borderRadius;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    final decoration = elevated
        ? BoxDecoration(
            gradient: LinearGradient(
              colors: [
                AppColors.brandSurface2.withValues(alpha: 0.90),
                AppColors.brandSurface.withValues(alpha: 0.96),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: radius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.22),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          )
        : BoxDecoration(
            color: AppColors.brandSurface.withValues(alpha: 0.88),
            borderRadius: radius,
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          );

    final card = Container(
      width: double.infinity,
      padding: padding,
      decoration: decoration,
      child: child,
    );

    if (onTap == null) return card;
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: card,
      ),
    );
  }
}

/// 橘漸層圓角 icon 章。對齊 about_me 介紹卡的 34×34 tune icon。
class BrandIconBadge extends StatelessWidget {
  const BrandIconBadge({
    super.key,
    required this.icon,
    this.size = 34,
    this.iconSize = 18,
  });

  final IconData icon;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.ctaStart, AppColors.brandBlush],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(size * 0.38),
      ),
      child: Icon(icon, color: Colors.white, size: iconSize),
    );
  }
}

/// 區塊標題。預設用 4px 橘漸層豎條（對齊 profile_chip_section）；
/// 傳 [icon] 改用 [BrandIconBadge]（對齊 about_me 介紹卡）。
class BrandSectionHeader extends StatelessWidget {
  const BrandSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              BrandIconBadge(icon: icon!),
              const SizedBox(width: 10),
            ] else ...[
              Container(
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [AppColors.ctaStart, AppColors.brandBlush],
                  ),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                title,
                style: (icon != null
                        ? AppTypography.titleMedium
                        : AppTypography.titleSmall)
                    .copyWith(
                  color: AppColors.onBackgroundPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}

/// 品牌輸入框 decoration。對齊 about_me 的 _fieldDecoration：brandInk@.38 底、
/// 圓角 18、focus 橘邊。
InputDecoration brandInputDecoration({
  String? hintText,
  String? labelText,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    hintText: hintText,
    labelText: labelText,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    hintStyle: AppTypography.bodyMedium.copyWith(
      color: Colors.white.withValues(alpha: 0.40),
    ),
    labelStyle: AppTypography.bodyMedium.copyWith(
      color: AppColors.onBackgroundSecondary.withValues(alpha: 0.80),
    ),
    filled: true,
    fillColor: AppColors.brandInk.withValues(alpha: 0.38),
    counterStyle: AppTypography.caption.copyWith(
      color: AppColors.onBackgroundSecondary.withValues(alpha: 0.62),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    enabledBorder: border(Colors.white.withValues(alpha: 0.12)),
    focusedBorder: border(AppColors.ctaStart.withValues(alpha: 0.74), 1.3),
    errorBorder: border(AppColors.error.withValues(alpha: 0.80)),
    focusedErrorBorder: border(AppColors.error),
  );
}

/// 橘色 pill 主 CTA。對齊 about_me 的儲存鍵：ctaStart→ctaEnd 漸層、圓角 999、
/// 橘色外光、w800 字。支援 loading 與 leading icon。
class BrandPrimaryButton extends StatelessWidget {
  const BrandPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
    this.verticalPadding = 15,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || isLoading;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: disabled
              ? [Colors.grey.shade700, Colors.grey.shade800]
              : const [AppColors.ctaStart, AppColors.ctaEnd],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: disabled
            ? null
            : [
                BoxShadow(
                  color: AppColors.ctaStart.withValues(alpha: 0.30),
                  blurRadius: 18,
                  offset: const Offset(0, 9),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: disabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.transparent,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.70),
          padding: EdgeInsets.symmetric(vertical: verticalPadding),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 次要描邊 pill 鍵（深底、白字、白邊）。用在非主要動作。
class BrandSecondaryButton extends StatelessWidget {
  const BrandSecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: AppColors.brandInk.withValues(alpha: 0.30),
          padding: const EdgeInsets.symmetric(vertical: 14),
          side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// 品牌 ChoiceChip。對齊 profile_chip_section 的暗紫底 / 橘選中態 pill。
/// 此版本獨立可用於任意 chip 群（不限 ProfileChipSection 泛型）。
class BrandChoiceChip extends StatelessWidget {
  const BrandChoiceChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: trailing == null
          ? Text(label)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [Text(label), const SizedBox(width: 4), trailing!],
            ),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onTap(),
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return const Color(0xFF4D2630);
        }
        if (states.contains(WidgetState.pressed)) {
          return const Color(0xFF3A2032);
        }
        return const Color(0xFF261735);
      }),
      backgroundColor: const Color(0xFF261735),
      selectedColor: const Color(0xFF4D2630),
      disabledColor: const Color(0xFF261735),
      surfaceTintColor: Colors.transparent,
      labelStyle: AppTypography.bodySmall.copyWith(
        color: selected
            ? Colors.white
            : AppColors.onBackgroundSecondary.withValues(alpha: 0.86),
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
        height: 1.2,
      ),
      side: BorderSide(
        color: selected
            ? AppColors.ctaStart.withValues(alpha: 0.64)
            : Colors.white.withValues(alpha: 0.16),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

/// 暗紫橘分段選擇器（取代淺色 GlassmorphicSegmentedButton）。深色 track、
/// 橘漸層選中段 + check icon、白字。API 與舊版對齊（value + label）。
class BrandSegment<T> {
  const BrandSegment({required this.value, required this.label});

  final T value;
  final String label;
}

class BrandSegmentedButton<T> extends StatelessWidget {
  const BrandSegmentedButton({
    super.key,
    required this.segments,
    required this.selected,
    required this.onChanged,
  });

  final List<BrandSegment<T>> segments;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.brandInk.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: segments.map((segment) {
          final isSelected = segment.value == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(segment.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [AppColors.ctaStart, AppColors.ctaEnd],
                        )
                      : null,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.ctaStart.withValues(alpha: 0.32),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isSelected) ...[
                      const Icon(Icons.check, size: 15, color: Colors.white),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          segment.label,
                          maxLines: 1,
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            color: isSelected
                                ? Colors.white
                                : AppColors.onBackgroundSecondary
                                    .withValues(alpha: 0.82),
                            fontWeight:
                                isSelected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// 低對比資訊條（隱私 / 提示），對齊 about_me 的 _PrivacyNote。
class BrandInfoNote extends StatelessWidget {
  const BrandInfoNote({
    super.key,
    required this.text,
    this.icon = Icons.lock_outline_rounded,
  });

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.055),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.ctaStart.withValues(alpha: 0.86)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.onBackgroundSecondary.withValues(alpha: 0.78),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
