import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/widgets/brand/brand_kit.dart';

/// The suggested platforms stay deliberately small. A custom value is always
/// available so the UI does not need a release whenever users move elsewhere.
const commonAnalysisPlatforms = <String>[
  'Omi',
  'LINE',
  'IG',
  'Threads',
  'Tinder',
  'Bumble',
];

String? normalizeAnalysisPlatform(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

/// `null` from [showAnalysisPlatformPicker] means the sheet was cancelled.
/// A non-null result whose [platform] is null explicitly means 「未分類」.
class AnalysisPlatformPickerResult {
  const AnalysisPlatformPickerResult(this.platform);

  final String? platform;
}

Future<AnalysisPlatformPickerResult?> showAnalysisPlatformPicker(
  BuildContext context, {
  String? currentValue,
  String title = '選擇平台',
}) {
  return showModalBottomSheet<AnalysisPlatformPickerResult>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => AnalysisPlatformPickerSheet(
      currentValue: currentValue,
      title: title,
    ),
  );
}

class AnalysisPlatformPickerSheet extends StatefulWidget {
  const AnalysisPlatformPickerSheet({
    super.key,
    this.currentValue,
    this.title = '選擇平台',
  });

  final String? currentValue;
  final String title;

  @override
  State<AnalysisPlatformPickerSheet> createState() =>
      _AnalysisPlatformPickerSheetState();
}

class _AnalysisPlatformPickerSheetState
    extends State<AnalysisPlatformPickerSheet> {
  String? get _current => normalizeAnalysisPlatform(widget.currentValue);

  bool get _isCustomCurrent =>
      _current != null &&
      !commonAnalysisPlatforms.any(
        (platform) => platform.toLowerCase() == _current!.toLowerCase(),
      );

  void _select(String? platform) {
    Navigator.of(context).pop(
      AnalysisPlatformPickerResult(normalizeAnalysisPlatform(platform)),
    );
  }

  Future<void> _enterCustomPlatform() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _CustomPlatformDialog(
        initialValue: _isCustomCurrent ? _current : null,
      ),
    );
    if (!mounted || value == null) return;
    _select(value);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return FractionallySizedBox(
      heightFactor: 0.72,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        child: BrandPageBackground(
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    widget.title,
                    style: AppTypography.titleLarge.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '只用來整理分析紀錄，不會改動 AI 分析內容。',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.onBackgroundSecondary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: ListView(
                      key: const ValueKey('analysis-platform-options'),
                      padding: EdgeInsets.zero,
                      children: [
                        for (final platform in commonAnalysisPlatforms)
                          _PlatformOptionTile(
                            label: platform,
                            selected: _current?.toLowerCase() ==
                                platform.toLowerCase(),
                            onTap: () => _select(platform),
                          ),
                        if (_isCustomCurrent)
                          _PlatformOptionTile(
                            label: _current!,
                            selected: true,
                            icon: Icons.bookmark_outline_rounded,
                            onTap: () => _select(_current),
                          ),
                        _PlatformOptionTile(
                          key: const ValueKey('analysis-platform-custom'),
                          label: '其他平台',
                          selected: false,
                          icon: Icons.add_rounded,
                          onTap: _enterCustomPlatform,
                        ),
                        _PlatformOptionTile(
                          key: const ValueKey('analysis-platform-unclassified'),
                          label: '未分類',
                          selected: _current == null,
                          icon: Icons.help_outline_rounded,
                          onTap: () => _select(null),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomPlatformDialog extends StatefulWidget {
  const _CustomPlatformDialog({this.initialValue});

  final String? initialValue;

  @override
  State<_CustomPlatformDialog> createState() => _CustomPlatformDialogState();
}

class _CustomPlatformDialogState extends State<_CustomPlatformDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = normalizeAnalysisPlatform(_controller.text);
    if (value == null) {
      setState(() => _errorText = '請輸入平台名稱');
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.brandSurface2,
      title: Text(
        '輸入其他平台',
        style: AppTypography.titleLarge.copyWith(
          color: AppColors.onBackgroundPrimary,
        ),
      ),
      content: TextField(
        key: const ValueKey('analysis-platform-custom-input'),
        controller: _controller,
        autofocus: true,
        maxLength: 24,
        textInputAction: TextInputAction.done,
        style: AppTypography.bodyMedium.copyWith(
          color: AppColors.onBackgroundPrimary,
        ),
        cursorColor: AppColors.ctaStart,
        decoration: brandInputDecoration(
          labelText: '平台名稱',
          hintText: '例如：Facebook、Discord',
        ).copyWith(errorText: _errorText),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          key: const ValueKey('analysis-platform-custom-confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.ctaStart,
            foregroundColor: Colors.white,
          ),
          onPressed: _submit,
          child: const Text('套用'),
        ),
      ],
    );
  }
}

class _PlatformOptionTile extends StatelessWidget {
  const _PlatformOptionTile({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon = Icons.chat_bubble_outline_rounded,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? AppColors.ctaStart.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: selected
                      ? AppColors.ctaStart
                      : AppColors.onBackgroundSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.onBackgroundPrimary,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.ctaStart,
                    size: 21,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
